// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.7.4;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts-upgradeable/math/SignedSafeMathUpgradeable.sol";

import "../interface/IOracle.sol";

import "../libraries/OrderData.sol";
import "../libraries/SafeMathExt.sol";
import "../libraries/Utils.sol";

import "./AMMModule.sol";
import "./LiquidityPoolModule.sol";
import "./MarginAccountModule.sol";
import "./PerpetualModule.sol";

import "../Type.sol";

library TradeModule {
    using SafeMathExt for int256;
    using SignedSafeMathUpgradeable for int256;
    using OrderData for uint32;

    using AMMModule for LiquidityPoolStorage;
    using LiquidityPoolModule for LiquidityPoolStorage;
    using MarginAccountModule for PerpetualStorage;
    using PerpetualModule for PerpetualStorage;
    using MarginAccountModule for MarginAccount;

    event Trade(
        uint256 perpetualIndex,
        address indexed trader,
        int256 position,
        int256 price,
        int256 fee,
        int256 lpFee
    );
    event Liquidate(
        uint256 perpetualIndex,
        address indexed liquidator,
        address indexed trader,
        int256 amount,
        int256 price,
        int256 penalty,
        int256 penaltyToLP
    );
    event TransferFeeToOperator(address indexed operator, int256 operatorFee);
    event TransferFeeToReferrer(
        uint256 perpetualIndex,
        address indexed trader,
        address indexed referrer,
        int256 referralRebate
    );

    /**
     * @dev     See `trade` in Perpetual.sol for details.
     *
     * @param   liquidityPool   The reference of liquidity pool storage.
     * @param   perpetualIndex  The index of the perpetual in liquidity pool.
     * @param   trader          The address of trader.
     * @param   amount          The amount of position to trader, positive for buying and negative for selling.
     * @param   limitPrice      The worst price the trader accepts.
     * @param   referrer        The address of referrer who will get rebate in the deal.
     * @param   flags           The flags of the trade, contains extra config for trading.
     * @return  tradeAmount     The amount of positions actually traded in the transaction.
     */
    function trade(
        LiquidityPoolStorage storage liquidityPool,
        uint256 perpetualIndex,
        address trader,
        int256 amount,
        int256 limitPrice,
        address referrer,
        uint32 flags
    ) public returns (int256 tradeAmount) {
        (int256 deltaCash, int256 deltaPosition) =
            preTrade(liquidityPool, perpetualIndex, trader, amount, limitPrice, flags);
        doTrade(liquidityPool, perpetualIndex, trader, deltaCash, deltaPosition);
        (int256 lpFee, int256 totalFee) =
            postTrade(
                liquidityPool,
                perpetualIndex,
                trader,
                referrer,
                deltaCash,
                deltaPosition,
                flags
            );
        emit Trade(
            perpetualIndex,
            trader,
            deltaPosition.neg(),
            deltaCash.wdiv(deltaPosition).abs(),
            totalFee,
            lpFee
        );
        tradeAmount = deltaPosition.neg();
    }

    function preTrade(
        LiquidityPoolStorage storage liquidityPool,
        uint256 perpetualIndex,
        address trader,
        int256 amount,
        int256 limitPrice,
        uint32 flags
    ) internal returns (int256 deltaCash, int256 deltaPosition) {
        PerpetualStorage storage perpetual = liquidityPool.perpetuals[perpetualIndex];
        require(!IOracle(perpetual.oracle).isMarketClosed(), "market is closed now");
        // handle close only flag
        if (flags.isCloseOnly()) {
            amount = getMaxPositionToClose(perpetual.getPosition(trader), amount);
            require(amount != 0, "no amount to close");
        }
        // query price from AMM
        (deltaCash, deltaPosition) = liquidityPool.queryTradeWithAMM(
            perpetualIndex,
            amount.neg(),
            false
        );
        // check price
        if (!flags.isMarketOrder()) {
            int256 tradePrice = deltaCash.wdiv(deltaPosition).abs();
            validatePrice(amount >= 0, tradePrice, limitPrice);
        }
    }

    function doTrade(
        LiquidityPoolStorage storage liquidityPool,
        uint256 perpetualIndex,
        address trader,
        int256 deltaCash,
        int256 deltaPosition
    ) internal {
        PerpetualStorage storage perpetual = liquidityPool.perpetuals[perpetualIndex];
        int256 deltaOpenInterest1 = perpetual.updateMargin(address(this), deltaPosition, deltaCash);
        int256 deltaOpenInterest2 =
            perpetual.updateMargin(trader, deltaPosition.neg(), deltaCash.neg());
        require(perpetual.openInterest >= 0, "negative open interest");
        if (deltaOpenInterest1.add(deltaOpenInterest2) > 0) {
            // open interest will increase, check limit
            (int256 poolMargin, ) = liquidityPool.getPoolMargin();
            require(
                perpetual.openInterest <=
                    perpetual.maxOpenInterestRate.wfrac(poolMargin, perpetual.getIndexPrice()),
                "open interest exceeds limit"
            );
        }
    }

    /**
     * @dev Execute the trade. If the trader has opened position in the trade, his account should be
     *          initial margin safe after the trade. If not, his account should be margin safe
     *
     * @param   liquidityPool   The reference of liquidity pool storage.
     * @param   perpetualIndex  The index of pereptual storage.
     * @param   trader          The address of trader.
     * @param   referrer        The address of referrer who will get rebate from the deal.
     * @param   deltaCash       The amount of cash changes in a trade.
     * @param   deltaPosition   The amount of position changes in a trade.
     * @return  lpFee           The amount of fee for lp provider
     * @return  totalFee        The total fee collected from the trader after the trade
     */
    function postTrade(
        LiquidityPoolStorage storage liquidityPool,
        uint256 perpetualIndex,
        address trader,
        address referrer,
        int256 deltaCash,
        int256 deltaPosition,
        uint32 flags
    ) internal returns (int256 lpFee, int256 totalFee) {
        PerpetualStorage storage perpetual = liquidityPool.perpetuals[perpetualIndex];
        // fees
        int256 operatorFee;
        int256 vaultFee;
        int256 referralRebate;
        {
            bool hasOpened =
                Utils.hasOpenedPosition(perpetual.getPosition(trader), deltaPosition.neg());
            (lpFee, operatorFee, vaultFee, referralRebate) = getFees(
                liquidityPool,
                perpetual,
                trader,
                referrer,
                deltaCash.abs(),
                hasOpened
            );
        }
        totalFee = lpFee.add(operatorFee).add(vaultFee).add(referralRebate);
        perpetual.updateCash(trader, totalFee.neg());
        // trader deposit/withdraw
        if (flags.useTargetLeverage()) {
            liquidityPool.adjustMarginLeverage(
                perpetualIndex,
                trader,
                deltaPosition.neg(),
                deltaCash.neg(),
                totalFee
            );
        }
        // send fee
        transferFee(
            liquidityPool,
            perpetualIndex,
            trader,
            referrer,
            lpFee,
            operatorFee,
            vaultFee,
            referralRebate
        );
    }

    /**
     * @dev     Get the fees of the trade. If the margin of the trader is not enough for fee:
     *            1. If trader open position, the trade will be reverted.
     *            2. If trader close position, the fee will be decreasing in proportion according to
     *               the margin left in the trader's account
     *          The rebate of referral will only calculate the lpFee and operatorFee.
     *          The vault fee will not be counted in.
     *
     * @param   liquidityPool   The reference of liquidity pool storage.
     * @param   perpetual       The reference of pereptual storage.
     * @param   trader          The address of trader.
     * @param   referrer        The address of referrer who will get rebate from the deal.
     * @param   tradeValue      The amount of trading value, measured by collateral, abs of deltaCash.
     * @return  lpFee           The amount of fee to the Liquidity provider.
     * @return  operatorFee     The amount of fee to the operator.
     * @return  vaultFee        The amount of fee to the vault.
     * @return  referralRebate  The amount of rebate of the refferral.
     */
    function getFees(
        LiquidityPoolStorage storage liquidityPool,
        PerpetualStorage storage perpetual,
        address trader,
        address referrer,
        int256 tradeValue,
        bool hasOpened
    )
        public
        view
        returns (
            int256 lpFee,
            int256 operatorFee,
            int256 vaultFee,
            int256 referralRebate
        )
    {
        require(tradeValue >= 0, "trade value is negative");
        vaultFee = tradeValue.wmul(liquidityPool.getVaultFeeRate());
        lpFee = tradeValue.wmul(perpetual.lpFeeRate);
        if (liquidityPool.getOperator() != address(0)) {
            operatorFee = tradeValue.wmul(perpetual.operatorFeeRate);
        }
        int256 totalFee = lpFee.add(operatorFee).add(vaultFee);
        int256 availableMargin = perpetual.getAvailableMargin(trader, perpetual.getMarkPrice());
        if (!hasOpened) {
            if (availableMargin <= 0) {
                lpFee = 0;
                operatorFee = 0;
                vaultFee = 0;
                referralRebate = 0;
            } else if (totalFee > availableMargin) {
                // make sure the sum of fees < available margin
                int256 rate = availableMargin.wdiv(totalFee, Round.FLOOR);
                operatorFee = operatorFee.wmul(rate, Round.FLOOR);
                vaultFee = vaultFee.wmul(rate, Round.FLOOR);
                lpFee = availableMargin.sub(operatorFee).sub(vaultFee);
            }
        }
        if (
            referrer != address(0) && perpetual.referralRebateRate > 0 && lpFee.add(operatorFee) > 0
        ) {
            int256 lpFeeRebate = lpFee.wmul(perpetual.referralRebateRate);
            int256 operatorFeeRabate = operatorFee.wmul(perpetual.referralRebateRate);
            referralRebate = lpFeeRebate.add(operatorFeeRabate);
            lpFee = lpFee.sub(lpFeeRebate);
            operatorFee = operatorFee.sub(operatorFeeRabate);
        }
    }

    function transferFee(
        LiquidityPoolStorage storage liquidityPool,
        uint256 perpetualIndex,
        address trader,
        address referrer,
        int256 lpFee,
        int256 operatorFee,
        int256 vaultFee,
        int256 referralRebate
    ) internal {
        PerpetualStorage storage perpetual = liquidityPool.perpetuals[perpetualIndex];
        perpetual.updateCash(address(this), lpFee);
        liquidityPool.transferFromPerpetualToUser(perpetual.id, referrer, referralRebate);
        liquidityPool.transferFromPerpetualToUser(perpetual.id, liquidityPool.getVault(), vaultFee);
        address operator = liquidityPool.getOperator();
        liquidityPool.transferFromPerpetualToUser(perpetual.id, operator, operatorFee);
        emit TransferFeeToOperator(operator, operatorFee);
        emit TransferFeeToReferrer(perpetual.id, trader, referrer, referralRebate);
    }

    /**
     * @dev     See `liquidateByAMM` in Perpetual.sol for details.
     *
     * @param   liquidityPool   The reference of liquidity pool storage.
     * @param   perpetualIndex  The index of the perpetual in liquidity pool.
     * @param   liquidator      The address of the account calling the liquidation method.
     * @param   trader          The address of the liquidated account.
     * @return  liquidatedAmount    The amount of positions actually liquidated in the transaction.
     */
    function liquidateByAMM(
        LiquidityPoolStorage storage liquidityPool,
        uint256 perpetualIndex,
        address liquidator,
        address trader
    ) public returns (int256 liquidatedAmount) {
        PerpetualStorage storage perpetual = liquidityPool.perpetuals[perpetualIndex];
        require(
            !perpetual.isMaintenanceMarginSafe(trader, perpetual.getMarkPrice()),
            "trader is safe"
        );
        int256 position = perpetual.getPosition(trader);
        // 0. price / amount
        (int256 deltaCash, int256 deltaPosition) =
            liquidityPool.queryTradeWithAMM(perpetualIndex, position, true);
        require(deltaPosition != 0, "insufficient liquidity");
        // 2. trade
        int256 liquidatePrice = deltaCash.wdiv(deltaPosition).abs();
        perpetual.updateMargin(address(this), deltaPosition, deltaCash);
        perpetual.updateMargin(
            trader,
            deltaPosition.neg(),
            deltaCash.add(perpetual.keeperGasReward).neg()
        );
        require(perpetual.openInterest >= 0, "negative open interest");
        liquidityPool.transferFromPerpetualToUser(
            perpetual.id,
            liquidator,
            perpetual.keeperGasReward
        );
        // 3. penalty  min(markPrice * liquidationPenaltyRate, margin / position) * deltaPosition
        (int256 penalty, int256 penaltyToLiquidator) =
            postLiquidate(
                liquidityPool,
                perpetual,
                address(this),
                trader,
                position,
                deltaPosition.neg()
            );
        emit Liquidate(
            perpetualIndex,
            address(this),
            trader,
            deltaPosition.neg(),
            liquidatePrice,
            penalty,
            penaltyToLiquidator
        );
        liquidatedAmount = deltaPosition.neg();
    }

    /**
     * @dev     See `liquidateByTrader` in Perpetual.sol for details.
     *
     * @param   liquidityPool   The reference of liquidity pool storage.
     * @param   perpetualIndex  The index of the perpetual in liquidity pool.
     * @param   liquidator          The address of the account calling the liquidation method.
     * @param   trader              The address of the liquidated account.
     * @param   amount              The amount of position to be taken from liquidated trader.
     * @param   limitPrice          The worst price liquidator accepts.
     * @return  liquidatedAmount    The amount of positions actually liquidated in the transaction.
     */
    function liquidateByTrader(
        LiquidityPoolStorage storage liquidityPool,
        uint256 perpetualIndex,
        address liquidator,
        address trader,
        int256 amount,
        int256 limitPrice
    ) public returns (int256 liquidatedAmount) {
        PerpetualStorage storage perpetual = liquidityPool.perpetuals[perpetualIndex];
        int256 markPrice = perpetual.getMarkPrice();
        require(!perpetual.isMaintenanceMarginSafe(trader, markPrice), "trader is safe");
        // 0. price / amount
        validatePrice(amount >= 0, markPrice, limitPrice);
        int256 position = perpetual.getPosition(trader);
        int256 deltaPosition = getMaxPositionToClose(position, amount.neg()).neg();
        int256 deltaCash = markPrice.wmul(deltaPosition).neg();
        // 1. execute
        perpetual.updateMargin(liquidator, deltaPosition, deltaCash);
        perpetual.updateMargin(trader, deltaPosition.neg(), deltaCash.neg());
        require(perpetual.openInterest >= 0, "negative open interest");
        // 2. penalty  min(markPrice * liquidationPenaltyRate, margin / position) * deltaPosition
        (int256 penalty, ) =
            postLiquidate(
                liquidityPool,
                perpetual,
                liquidator,
                trader,
                position,
                deltaPosition.neg()
            );
        liquidatedAmount = deltaPosition.neg();
        require(
            liquidityPool.isTraderMarginSafe(perpetualIndex, liquidator, liquidatedAmount),
            "liquidator margin unsafe"
        );
        emit Liquidate(perpetualIndex, liquidator, trader, liquidatedAmount, markPrice, penalty, 0);
    }

    /**
     * @dev     Handle liquidate penalty / fee.
     *
     * @param   liquidityPool   The reference of liquidity pool storage.
     * @param   perpetual       The reference of perpetual storage.
     * @param   liquidator      The address of the account calling the liquidation method.
     * @param   trader          The address of the liquidated account.
     * @param   position        The amount of position owned by trader before liquidation.
     * @param   deltaPosition   The amount of position to be taken from liquidated trader.
     * @return  penalty             The amount of positions actually liquidated in the transaction.
     * @return  penaltyToLiquidator The amount of positions actually liquidated in the transaction.
     */
    function postLiquidate(
        LiquidityPoolStorage storage liquidityPool,
        PerpetualStorage storage perpetual,
        address liquidator,
        address trader,
        int256 position,
        int256 deltaPosition
    ) public returns (int256 penalty, int256 penaltyToLiquidator) {
        int256 vaultFee = 0;
        {
            int256 markPrice = perpetual.getMarkPrice();
            int256 remainingMargin = perpetual.getMargin(trader, markPrice);
            int256 liquidationValue = markPrice.wmul(deltaPosition).abs();
            penalty = liquidationValue.wmul(perpetual.liquidationPenaltyRate).min(
                remainingMargin.wfrac(deltaPosition.abs(), position.abs())
            );
            remainingMargin = remainingMargin.sub(penalty);
            if (remainingMargin > 0) {
                vaultFee = liquidationValue.wmul(liquidityPool.getVaultFeeRate()).min(
                    remainingMargin
                );
                liquidityPool.transferFromPerpetualToUser(
                    perpetual.id,
                    liquidityPool.getVault(),
                    vaultFee
                );
            }
        }
        int256 penaltyToFund;
        bool isEmergency;
        if (penalty > 0) {
            penaltyToFund = penalty.wmul(perpetual.insuranceFundRate);
            penaltyToLiquidator = penalty.sub(penaltyToFund);
        } else {
            int256 totalInsuranceFund =
                liquidityPool.insuranceFund.add(liquidityPool.donatedInsuranceFund);
            if (totalInsuranceFund.add(penalty) < 0) {
                // ensure donatedInsuranceFund >= 0
                penalty = totalInsuranceFund.neg();
                isEmergency = true;
            }
            penaltyToFund = penalty;
            penaltyToLiquidator = 0;
        }
        int256 penaltyToLP = liquidityPool.updateInsuranceFund(penaltyToFund);
        perpetual.updateCash(address(this), penaltyToLP);
        perpetual.updateCash(liquidator, penaltyToLiquidator);
        perpetual.updateCash(trader, penalty.add(vaultFee).neg());
        if (penaltyToFund >= 0) {
            perpetual.decreaseTotalCollateral(penaltyToFund.sub(penaltyToLP));
        } else {
            // penaltyToLP = 0 when penaltyToFund < 0
            perpetual.increaseTotalCollateral(penaltyToFund.neg());
        }
        if (isEmergency) {
            liquidityPool.setEmergencyState(perpetual.id);
        }
    }

    /**
     * @dev     Get the max position amount of trader will be closed in the trade.
     * @param   position            Current position of trader.
     * @param   amount              The trading amount of position.
     * @return  maxPositionToClose  The max position amount of trader will be closed in the trade.
     */
    function getMaxPositionToClose(int256 position, int256 amount)
        internal
        pure
        returns (int256 maxPositionToClose)
    {
        require(position != 0, "trader has no position to close");
        require(!Utils.hasTheSameSign(position, amount), "trader must be close only");
        maxPositionToClose = amount.abs() > position.abs() ? position.neg() : amount;
    }

    /**
     * @dev     Check if the price is better than the limit price.
     * @param   isLong      True if the side is long.
     * @param   price       The price to be validate.
     * @param   priceLimit  The limit price.
     */
    function validatePrice(
        bool isLong,
        int256 price,
        int256 priceLimit
    ) internal pure {
        require(price > 0, "price must be positive");
        bool isPriceSatisfied = isLong ? price <= priceLimit : price >= priceLimit;
        require(isPriceSatisfied, "price exceeds limit");
    }
}
