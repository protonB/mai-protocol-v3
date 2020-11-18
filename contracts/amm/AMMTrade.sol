// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.7.4;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/math/SignedSafeMath.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

import "../Type.sol";
import "../libraries/Constant.sol";
import "../libraries/Math.sol";
import "../libraries/SafeMathExt.sol";
import "../libraries/Utils.sol";

import "./AMMCommon.sol";

library AMMTrade {
    using Math for int256;
    using Math for uint256;
    using SafeMathExt for int256;
    using SignedSafeMath for int256;
    using SafeMath for uint256;

    int256 constant FUNDING_INTERVAL = 3600 * 8;

    function trade(
        FundingState storage fundingState,
        RiskParameter storage riskParameter,
        MarginAccount storage ammAccount,
        int256 indexPrice,
        int256 tradingAmount,
        bool partialFill
    ) internal view returns (int256 deltaMargin, int256 deltaPosition) {
        require(tradingAmount != 0, "Zero trade amount");
        int256 mc = AMMCommon.availableCashBalance(
            ammAccount,
            fundingState.unitAccFundingLoss
        );
        int256 positionAmount = ammAccount.positionAmount;
        (int256 closingAmount, int256 openingAmount) = Utils.splitAmount(
            positionAmount,
            tradingAmount
        );
        deltaMargin = closePosition(
            riskParameter,
            indexPrice,
            mc,
            positionAmount,
            closingAmount
        );
        (int256 openDeltaMargin, int256 openDeltaPosition) = openPosition(
            riskParameter,
            indexPrice,
            mc.add(deltaMargin),
            positionAmount.add(closingAmount),
            openingAmount,
            partialFill
        );
        deltaMargin = deltaMargin.add(openDeltaMargin);
        deltaPosition = closingAmount.add(openDeltaPosition);
        int256 spread = riskParameter.halfSpreadRate.value.wmul(deltaMargin);
        deltaMargin = deltaMargin > 0
            ? deltaMargin.add(spread)
            : deltaMargin.sub(spread);
    }

    function calculateRemovingLiquidityPenalty(
        FundingState storage fundingState,
        RiskParameter storage riskParameter,
        MarginAccount storage ammAccount,
        int256 indexPrice,
        int256 amount
    ) internal view returns (int256 penalty) {
        int256 cashBalance = AMMCommon.availableCashBalance(
            ammAccount,
            fundingState.unitAccFundingLoss
        );
        int256 positionAmount = ammAccount.positionAmount;
        require(
            AMMCommon.isAMMMarginSafe(
                cashBalance,
                positionAmount,
                indexPrice,
                riskParameter.targetLeverage.value,
                riskParameter.beta1.value
            ),
            "unsafe before trade"
        );
        int256 newCashBalance = cashBalance.sub(amount);
        require(
            AMMCommon.isAMMMarginSafe(
                newCashBalance,
                positionAmount,
                indexPrice,
                riskParameter.targetLeverage.value,
                riskParameter.beta1.value
            ),
            "unsafe before trade"
        );
        (, int256 m0) = AMMCommon.regress(
            cashBalance,
            positionAmount,
            indexPrice,
            riskParameter.targetLeverage.value,
            riskParameter.beta1.value
        );
        (, int256 newM0) = AMMCommon.regress(
            newCashBalance,
            positionAmount,
            indexPrice,
            riskParameter.targetLeverage.value,
            riskParameter.beta1.value
        );
        penalty = m0.sub(newM0).sub(
            riskParameter.targetLeverage.value.wmul(amount)
        );
        penalty = penalty < 0 ? 0 : amount;
    }

    function openPosition(
        RiskParameter storage riskParameter,
        int256 mc,
        int256 positionAmount,
        int256 indexPrice,
        int256 tradingAmount,
        bool partialFill
    ) private view returns (int256 deltaMargin, int256 deltaPosition) {
        if (tradingAmount == 0) {
            return (0, 0);
        }
        int256 targetLeverage = riskParameter.targetLeverage.value;
        int256 beta1 = riskParameter.beta1.value;
        if (
            !AMMCommon.isAMMMarginSafe(
                mc,
                positionAmount,
                indexPrice,
                targetLeverage,
                beta1
            )
        ) {
            if (partialFill) {
                return (0, 0);
            } else {
                revert("Unsafe before open position");
            }
        }

        int256 m0;
        int256 ma1;
        {
            int256 mv;
            (mv, m0) = AMMCommon.regress(
                mc,
                positionAmount,
                indexPrice,
                targetLeverage,
                beta1
            );
            ma1 = mc.add(mv);
        }

        int256 newPosition = positionAmount.add(tradingAmount);
        int256 maxPosition;
        if (newPosition > 0) {
            maxPosition = _maxLongPosition(
                m0,
                indexPrice,
                beta1,
                targetLeverage
            );
        } else {
            maxPosition = _maxShortPosition(
                m0,
                indexPrice,
                beta1,
                targetLeverage
            );
        }
        if (
            (newPosition > maxPosition && newPosition > 0) ||
            (newPosition < maxPosition && newPosition < 0)
        ) {
            if (partialFill) {
                deltaPosition = maxPosition.sub(positionAmount);
                newPosition = maxPosition;
            } else {
                revert("Trade amount exceeds max amount");
            }
        } else {
            deltaPosition = tradingAmount;
        }
        if (newPosition > 0) {
            deltaMargin = longDeltaMargin(
                m0,
                ma1,
                positionAmount,
                newPosition,
                indexPrice,
                beta1
            );
        } else {
            deltaMargin = shortDeltaMargin(
                m0,
                positionAmount,
                newPosition,
                indexPrice,
                beta1
            );
        }
    }

    function closePosition(
        RiskParameter storage riskParameter,
        int256 indexPrice,
        int256 mc,
        int256 positionAmount,
        int256 tradingAmount
    ) private view returns (int256 deltaMargin) {
        if (tradingAmount == 0) {
            return 0;
        }
        require(
            positionAmount != 0,
            "Zero position amount before close position"
        );
        int256 targetLeverage = riskParameter.targetLeverage.value;
        int256 closingBeta = riskParameter.beta2.value;
        if (
            AMMCommon.isAMMMarginSafe(
                mc,
                positionAmount,
                indexPrice,
                targetLeverage,
                closingBeta
            )
        ) {
            (int256 mv, int256 m0) = AMMCommon.regress(
                indexPrice,
                targetLeverage,
                mc,
                positionAmount,
                closingBeta
            );
            int256 newPositionAmount = positionAmount.add(tradingAmount);
            if (newPositionAmount == 0) {
                return m0.wdiv(targetLeverage).sub(mc);
            } else {
                if (positionAmount > 0) {
                    deltaMargin = longDeltaMargin(
                        m0,
                        mc.add(mv),
                        positionAmount,
                        newPositionAmount,
                        indexPrice,
                        closingBeta
                    );
                } else {
                    deltaMargin = shortDeltaMargin(
                        m0,
                        positionAmount,
                        newPositionAmount,
                        indexPrice,
                        closingBeta
                    );
                }
            }
        } else {
            deltaMargin = indexPrice.wmul(tradingAmount).neg();
        }
    }

    function longDeltaMargin(
        int256 m0,
        int256 ma,
        int256 positionAmount1,
        int256 positionAmount2,
        int256 indexPrice,
        int256 beta
    ) public pure returns (int256 deltaMargin) {
        int256 a = Constant.SIGNED_ONE.sub(beta).wmul(ma).mul(2);
        int256 b = positionAmount2.sub(positionAmount1).wmul(indexPrice);
        b = a.div(2).sub(b).wmul(ma);
        b = b.sub(beta.wmul(m0).wmul(m0));
        int256 beforeSqrt = beta.wmul(a).wmul(ma).wmul(m0).mul(m0).mul(2);
        beforeSqrt = beforeSqrt.add(b.mul(b));
        deltaMargin = beforeSqrt.sqrt().add(b).wdiv(a).sub(ma);
    }

    function shortDeltaMargin(
        int256 m0,
        int256 positionAmount1,
        int256 positionAmount2,
        int256 indexPrice,
        int256 beta
    ) public pure returns (int256 deltaMargin) {
        deltaMargin = beta.wmul(m0).wmul(m0);
        deltaMargin = deltaMargin.wdiv(
            positionAmount1.wmul(indexPrice).add(m0)
        );
        deltaMargin = deltaMargin.wdiv(
            positionAmount2.wmul(indexPrice).add(m0)
        );
        deltaMargin = deltaMargin.add(Constant.SIGNED_ONE).sub(beta);
        deltaMargin = deltaMargin
            .wmul(indexPrice)
            .wmul(positionAmount2.sub(positionAmount1))
            .neg();
    }

    function _maxLongPosition(
        int256 m0,
        int256 indexPrice,
        int256 beta,
        int256 targetLeverage
    ) private pure returns (int256 maxLongPosition) {
        if (beta.wmul(targetLeverage) == Constant.SIGNED_ONE.sub(beta)) {
            maxLongPosition = beta
                .mul(2)
                .neg()
                .add(Constant.SIGNED_ONE)
                .mul(2)
                .wmul(indexPrice);
            maxLongPosition = m0.wdiv(maxLongPosition);
        } else {
            int256 tmp1 = targetLeverage.sub(Constant.SIGNED_ONE);
            int256 tmp2 = tmp1.add(beta);
            int256 tmp3 = beta.mul(2).sub(Constant.SIGNED_ONE);
            maxLongPosition = beta.mul(tmp2).sqrt();
            maxLongPosition = beta.add(tmp2).sub(Constant.SIGNED_ONE).wmul(
                maxLongPosition
            );
            maxLongPosition = tmp2
                .wmul(tmp3)
                .add(maxLongPosition)
                .wdiv(tmp1)
                .wdiv(beta.wmul(tmp1).add(tmp3));
        }
    }

    function _maxShortPosition(
        int256 m0,
        int256 indexPrice,
        int256 beta,
        int256 targetLeverage
    ) private pure returns (int256 maxShortPosition) {
        maxShortPosition = beta
            .mul(targetLeverage)
            .sqrt()
            .add(Constant.SIGNED_ONE)
            .wmul(indexPrice);
        maxShortPosition = m0.wdiv(maxShortPosition).neg();
    }
}