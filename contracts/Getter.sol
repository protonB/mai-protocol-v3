// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.7.4;

import "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/EnumerableSetUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/SafeCastUpgradeable.sol";

import "./libraries/SafeMathExt.sol";
import "./libraries/Utils.sol";

import "./module/MarginAccountModule.sol";
import "./module/PerpetualModule.sol";
import "./module/LiquidityPoolModule.sol";
import "./module/AMMModule.sol";

import "./Type.sol";
import "./Storage.sol";

/**
 * @notice  Getter is a helper to help getting status of liquidity from external.
 */
contract Getter is Storage {
    using SafeMathUpgradeable for uint256;
    using SafeCastUpgradeable for uint256;
    using SafeMathExt for int256;
    using SafeMathExt for uint256;
    using Utils for EnumerableSetUpgradeable.AddressSet;
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;
    using MarginAccountModule for PerpetualStorage;
    using PerpetualModule for PerpetualStorage;
    using LiquidityPoolModule for LiquidityPoolStorage;
    using AMMModule for LiquidityPoolStorage;

    /**
     * @notice  Get the info of the liquidity pool.
     *          WARN: the result of this function is base on current storage of liquidityPool, not the latest.
     *          To get the latest status, call `syncState` first.
     *
     * @return  isRunning               True if the liquidity pool is running.
     * @return  isFastCreationEnabled   True if the operator of the liquidity pool is allowed to create new perpetual
     *                                  when the liquidity pool is running.
     * @return  addresses               The related addresses of the liquidity pool.
     * @return  intNums                 An fixed length array of int type properties, see comments for details.
     * @return  uintNums                An fixed length array of uint type properties, see comments for details.
     */
    function getLiquidityPoolInfo()
        public
        view
        returns (
            bool isRunning,
            bool isFastCreationEnabled,
            // [0] creator,
            // [1] operator,
            // [2] transferringOperator,
            // [3] governor,
            // [4] shareToken,
            // [5] collateralToken,
            // [6] vault,
            address[7] memory addresses,
            // [0] vaultFeeRate,
            // [1] poolCash,
            // [2] insuranceFundCap,
            // [3] insuranceFund,
            // [4] donatedInsuranceFund,
            int256[5] memory intNums,
            // [0] collateralDecimals,
            // [1] perpetualCount,
            // [2] fundingTime,
            // [3] operatorExpiration,
            uint256[4] memory uintNums
        )
    {
        isRunning = _liquidityPool.isRunning;
        isFastCreationEnabled = _liquidityPool.isFastCreationEnabled;
        addresses = [
            _liquidityPool.creator,
            _liquidityPool.getOperator(),
            _liquidityPool.transferringOperator,
            _liquidityPool.governor,
            _liquidityPool.shareToken,
            _liquidityPool.collateralToken,
            _liquidityPool.getVault()
        ];
        intNums[0] = _liquidityPool.getVaultFeeRate();
        intNums[1] = _liquidityPool.poolCash;
        intNums[2] = _liquidityPool.insuranceFundCap;
        intNums[3] = _liquidityPool.insuranceFund;
        intNums[4] = _liquidityPool.donatedInsuranceFund;
        uintNums[0] = _liquidityPool.collateralDecimals;
        uintNums[1] = _liquidityPool.perpetualCount;
        uintNums[2] = _liquidityPool.fundingTime;
        uintNums[3] = _liquidityPool.operatorExpiration;
    }

    /**
     * @notice  Get the info of the perpetual. Need to update the funding state and the oracle price
     *          of each perpetual before and update the funding rate of each perpetual after.
     *          WARN: the result of this function is base on current storage of liquidityPool, not the latest.
     *          To get the latest status, call `syncState` first.
     *
     * @param   perpetualIndex  The index of the perpetual in the liquidity pool.
     * @return  state           The state of the perpetual.
     * @return  oracle          The address of the current oracle in perpetual.
     * @return  nums            An fixed length array of uint type properties, see comments for details.
     */
    function getPerpetualInfo(uint256 perpetualIndex)
        public
        view
        onlyExistedPerpetual(perpetualIndex)
        returns (
            PerpetualState state,
            address oracle,
            // [0] totalCollateral
            // [1] markPrice, (return settlementPrice if it is in EMERGENCY state)
            // [2] indexPrice,
            // [3] fundingRate,
            // [4] unitAccumulativeFunding,
            // [5] initialMarginRate,
            // [6] maintenanceMarginRate,
            // [7] operatorFeeRate,
            // [8] lpFeeRate,
            // [9] referralRebateRate,
            // [10] liquidationPenaltyRate,
            // [11] keeperGasReward,
            // [12] insuranceFundRate,
            // [13-15] halfSpread value, min, max,
            // [16-18] openSlippageFactor value, min, max,
            // [19-21] closeSlippageFactor value, min, max,
            // [22-24] fundingRateLimit value, min, max,
            // [25-27] ammMaxLeverage value, min, max,
            // [28-30] maxClosePriceDiscount value, min, max,
            // [31] openInterest,
            // [32] maxOpenInterestRate,
            // [33-35] fundingRateFactor value, min, max,
            // [36-38] defaultTargetLeverage value, min, max,
            int256[39] memory nums
        )
    {
        PerpetualStorage storage perpetual = _liquidityPool.perpetuals[perpetualIndex];
        state = perpetual.state;
        oracle = perpetual.oracle;
        nums = [
            // [0]
            perpetual.totalCollateral,
            perpetual.getMarkPrice(),
            perpetual.getIndexPrice(),
            perpetual.fundingRate,
            perpetual.unitAccumulativeFunding,
            perpetual.initialMarginRate,
            perpetual.maintenanceMarginRate,
            perpetual.operatorFeeRate,
            perpetual.lpFeeRate,
            perpetual.referralRebateRate,
            // [10]
            perpetual.liquidationPenaltyRate,
            perpetual.keeperGasReward,
            perpetual.insuranceFundRate,
            perpetual.halfSpread.value,
            perpetual.halfSpread.minValue,
            perpetual.halfSpread.maxValue,
            perpetual.openSlippageFactor.value,
            perpetual.openSlippageFactor.minValue,
            perpetual.openSlippageFactor.maxValue,
            perpetual.closeSlippageFactor.value,
            // [20]
            perpetual.closeSlippageFactor.minValue,
            perpetual.closeSlippageFactor.maxValue,
            perpetual.fundingRateLimit.value,
            perpetual.fundingRateLimit.minValue,
            perpetual.fundingRateLimit.maxValue,
            perpetual.ammMaxLeverage.value,
            perpetual.ammMaxLeverage.minValue,
            perpetual.ammMaxLeverage.maxValue,
            perpetual.maxClosePriceDiscount.value,
            perpetual.maxClosePriceDiscount.minValue,
            // [30]
            perpetual.maxClosePriceDiscount.maxValue,
            perpetual.openInterest,
            perpetual.maxOpenInterestRate,
            perpetual.fundingRateFactor.value,
            perpetual.fundingRateFactor.minValue,
            perpetual.fundingRateFactor.maxValue,
            perpetual.defaultTargetLeverage.value,
            perpetual.defaultTargetLeverage.minValue,
            perpetual.defaultTargetLeverage.maxValue
        ];
    }

    /**
     * @notice  Get the account info of the trader. Need to update the funding state and the oracle price
     *          of each perpetual before and update the funding rate of each perpetual after
     *          WARN: the result of this function is base on current storage of liquidityPool, not the latest.
     *          To get the latest status, call `syncState` first.
     *
     * @param perpetualIndex    The index of the perpetual in the liquidity pool.
     * @param trader            The address of the trader.
     *                          When trader == liquidityPool, isSafe are meanless. Do not forget to sum
     *                          poolCash and availableCash of all perpetuals in a liquidityPool when
     *                          calculating AMM margin
     * @return cash                     The cash of the account.
     * @return position                 The position of the account.
     * @return availableMargin          The available margin of the account.
     * @return margin                   The margin of the account.
     * @return settleableMargin         The settleable margin of the account.
     * @return isInitialMarginSafe      True if the account is initial margin safe.
     * @return isMaintenanceMarginSafe  True if the account is maintenance margin safe.
     * @return isMarginSafe             True if the total value of margin account is beyond 0.
     * @return targetLeverage           The target leverage for openning position.
     */
    function getMarginAccount(uint256 perpetualIndex, address trader)
        public
        view
        onlyExistedPerpetual(perpetualIndex)
        returns (
            int256 cash,
            int256 position,
            int256 availableMargin,
            int256 margin,
            int256 settleableMargin,
            bool isInitialMarginSafe,
            bool isMaintenanceMarginSafe,
            bool isMarginSafe,
            int256 targetLeverage
        )
    {
        PerpetualStorage storage perpetual = _liquidityPool.perpetuals[perpetualIndex];
        MarginAccount storage account = perpetual.marginAccounts[trader];
        int256 markPrice = perpetual.getMarkPrice();
        cash = account.cash;
        position = account.position;
        availableMargin = perpetual.getAvailableMargin(trader, markPrice);
        margin = perpetual.getMargin(trader, markPrice);
        settleableMargin = perpetual.getSettleableMargin(trader, markPrice);
        isInitialMarginSafe = perpetual.isInitialMarginSafe(trader, markPrice);
        isMaintenanceMarginSafe = perpetual.isMaintenanceMarginSafe(trader, markPrice);
        isMarginSafe = perpetual.isMarginSafe(trader, markPrice);
        targetLeverage = perpetual.getTargetLeverage(trader);
    }

    /**
     * @notice  Get the number of active accounts in the given perpetual.
     *          Active means the trader has margin (margin != 0) in the margin account.
     * @param   perpetualIndex      The index of the perpetual in liquidity pool.
     * @return  activeAccountCount  The number of active accounts in the perpetual.
     */
    function getActiveAccountCount(uint256 perpetualIndex)
        public
        view
        onlyExistedPerpetual(perpetualIndex)
        returns (uint256 activeAccountCount)
    {
        activeAccountCount = _liquidityPool.perpetuals[perpetualIndex].activeAccounts.length();
    }

    /**
     * @notice  Get the active accounts in the perpetual whose index with range [begin, end).
     * @param   perpetualIndex  The index of the perpetual in the liquidity pool.
     * @param   begin           The begin index of account to retrieve.
     * @param   end             The end index of account, exclusive.
     * @return  result          An array of active addresses.
     */
    function listActiveAccounts(
        uint256 perpetualIndex,
        uint256 begin,
        uint256 end
    ) public view onlyExistedPerpetual(perpetualIndex) returns (address[] memory result) {
        PerpetualStorage storage perpetual = _liquidityPool.perpetuals[perpetualIndex];
        result = perpetual.activeAccounts.toArray(begin, end);
    }

    /**
     * @notice  Get the progress of clearing active accounts.
     * @param   perpetualIndex  The index of the perpetual in the liquidity pool
     * @return  left            Number of left active accounts.
     * @return  total           Number of total active accounts.
     */
    function getClearProgress(uint256 perpetualIndex)
        public
        view
        onlyExistedPerpetual(perpetualIndex)
        returns (uint256 left, uint256 total)
    {
        PerpetualStorage storage perpetual = _liquidityPool.perpetuals[perpetualIndex];
        left = perpetual.activeAccounts.length();
        total = perpetual.state == PerpetualState.NORMAL
            ? perpetual.activeAccounts.length()
            : perpetual.totalAccount;
    }

    /**
     * @notice  Get the pool margin of the liquidity pool.
     *          Pool margin is how much collateral of the pool considering the AMM's positions of perpetuals
     *          WARN: the result of this function is base on current storage of liquidityPool, not the latest.
     *          To get the latest status, call `syncState` first.
     * @return  poolMargin  The pool margin of the liquidity pool
     * @return  isAMMSafe   True if AMM is safe
     */
    function getPoolMargin() public view returns (int256 poolMargin, bool isAMMSafe) {
        (poolMargin, isAMMSafe) = _liquidityPool.getPoolMargin();
    }

    /**
     * @notice  Query the cost and position amount that amm could afford based on current liquidity.
     *          This method should returns the same result as a 'read-only' trade, and trading fee is not included.
     *          WARN: the result of this function is base on current storage of liquidityPool, not the latest.
     *          To get the latest status, call `syncState` first.
     *
     * @param   perpetualIndex  The index of the perpetual in liquidity pool.
     * @param   amount          The expected(max) amount of position to trade.
     * @return  deltaCash       The cost of cash of trade.
     * @return  deltaPosition   The update position of the trader after the trade
     */
    function queryTradeWithAMM(uint256 perpetualIndex, int256 amount)
        public
        view
        returns (int256 deltaCash, int256 deltaPosition)
    {
        (deltaCash, deltaPosition) = _liquidityPool.queryTradeWithAMM(
            perpetualIndex,
            amount.neg(),
            false
        );
        deltaCash = deltaCash.neg();
        deltaPosition = deltaPosition.neg();
    }

    bytes32[50] private __gap;
}
