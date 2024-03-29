// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.7.4;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts-upgradeable/math/SignedSafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/SafeCastUpgradeable.sol";

import "../interface/IAccessControl.sol";
import "../interface/IPoolCreator.sol";
import "../interface/IGovernor.sol";
import "../interface/ISymbolService.sol";

import "../libraries/SafeMathExt.sol";
import "../libraries/OrderData.sol";
import "../libraries/Utils.sol";

import "./AMMModule.sol";
import "./CollateralModule.sol";
import "./MarginAccountModule.sol";
import "./PerpetualModule.sol";

import "../Type.sol";

library LiquidityPoolModule {
    using SafeCastUpgradeable for uint256;
    using SafeCastUpgradeable for int256;
    using SafeMathExt for int256;
    using SafeMathUpgradeable for uint256;
    using SignedSafeMathUpgradeable for int256;
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;

    using OrderData for uint32;
    using AMMModule for LiquidityPoolStorage;
    using CollateralModule for LiquidityPoolStorage;
    using MarginAccountModule for PerpetualStorage;
    using PerpetualModule for PerpetualStorage;

    uint256 public constant OPERATOR_CHECK_IN_TIMEOUT = 10 days;
    uint256 public constant MAX_PERPETUAL_COUNT = 48;

    event AddLiquidity(
        address indexed trader,
        int256 addedCash,
        int256 mintedShare,
        int256 addedPoolMargin
    );
    event RemoveLiquidity(
        address indexed trader,
        int256 returnedCash,
        int256 burnedShare,
        int256 removedPoolMargin
    );
    event UpdatePoolMargin(int256 poolMargin);
    event TransferOperatorTo(address indexed newOperator);
    event ClaimOperator(address indexed newOperator);
    event RevokeOperator();
    event SetLiquidityPoolParameter(int256[2] value);
    event CreatePerpetual(
        uint256 perpetualIndex,
        address governor,
        address shareToken,
        address operator,
        address oracle,
        address collateral,
        int256[9] baseParams,
        int256[8] riskParams
    );
    event RunLiquidityPool();
    event OperatorCheckIn(address indexed operator);
    event DonateInsuranceFund(int256 amount);
    event TransferExcessInsuranceFundToLP(int256 amount);
    event SetTargetLeverage(address indexed trader, int256 targetLeverage);
    event SetKeeper(address indexed previousKeeper, address indexed newKeeper);

    /**
     * @dev     Get the vault's address of the liquidity pool
     *
     * @param   liquidityPool   The reference of liquidity pool storage.
     * @return  vault           The vault's address of the liquidity pool
     */
    function getVault(LiquidityPoolStorage storage liquidityPool)
        public
        view
        returns (address vault)
    {
        vault = IPoolCreator(liquidityPool.creator).getVault();
    }

    function getOperator(LiquidityPoolStorage storage liquidityPool)
        internal
        view
        returns (address operator)
    {
        return
            block.timestamp <= liquidityPool.operatorExpiration
                ? liquidityPool.operator
                : address(0);
    }

    /**
     * @dev     Get the vault fee rate of the liquidity pool
     *
     * @param   liquidityPool   The reference of liquidity pool storage.
     * @return  vaultFeeRate    The vault fee rate.
     */
    function getVaultFeeRate(LiquidityPoolStorage storage liquidityPool)
        public
        view
        returns (int256 vaultFeeRate)
    {
        vaultFeeRate = IPoolCreator(liquidityPool.creator).getVaultFeeRate();
    }

    /**
     * @dev     Get the available pool cash(collateral) of the liquidity pool excluding the specific perpetual. Available cash
     *          in a perpetual means: margin - initial margin
     *
     * @param   liquidityPool       The reference of liquidity pool storage.
     * @param   exclusiveIndex      The index of perpetual in the liquidity pool to exclude,
     *                              set to liquidityPool.perpetualCount to skip excluding.
     * @return  availablePoolCash   The available pool cash(collateral) of the liquidity pool excluding the specific perpetual
     */
    function getAvailablePoolCash(
        LiquidityPoolStorage storage liquidityPool,
        uint256 exclusiveIndex
    ) public view returns (int256 availablePoolCash) {
        uint256 length = liquidityPool.perpetualCount;
        for (uint256 i = 0; i < length; i++) {
            PerpetualStorage storage perpetual = liquidityPool.perpetuals[i];
            if (i == exclusiveIndex || perpetual.state != PerpetualState.NORMAL) {
                continue;
            }
            int256 markPrice = perpetual.getMarkPrice();
            availablePoolCash = availablePoolCash.add(
                perpetual.getMargin(address(this), markPrice).sub(
                    perpetual.getInitialMargin(address(this), markPrice)
                )
            );
        }
        return availablePoolCash.add(liquidityPool.poolCash);
    }

    /**
     * @dev     Get the available pool cash(collateral) of the liquidity pool.
     *          Sum of available cash of AMM in every perpetual in the liquidity pool, and add the pool cash.
     *
     * @param   liquidityPool       The reference of liquidity pool storage.
     * @return  availablePoolCash   The available pool cash(collateral) of the liquidity pool
     */
    function getAvailablePoolCash(LiquidityPoolStorage storage liquidityPool)
        public
        view
        returns (int256 availablePoolCash)
    {
        return getAvailablePoolCash(liquidityPool, liquidityPool.perpetualCount);
    }

    /**
     * @dev     Check if AMM is maintenance margin safe in the perpetual, need to rebalance before checking.
     *
     * @param   liquidityPool   The reference of liquidity pool storage.
     * @param   perpetualIndex  The index of the perpetual in the liquidity pool.
     * @return  isSafe          True if AMM is maintenance margin safe in the perpetual.
     */
    function isAMMMaintenanceMarginSafe(
        LiquidityPoolStorage storage liquidityPool,
        uint256 perpetualIndex
    ) public returns (bool isSafe) {
        rebalance(liquidityPool, perpetualIndex);
        PerpetualStorage storage perpetual = liquidityPool.perpetuals[perpetualIndex];
        isSafe = liquidityPool.perpetuals[perpetualIndex].isMaintenanceMarginSafe(
            address(this),
            perpetual.getMarkPrice()
        );
    }

    /**
     * @dev     Check if Trader is maintenance margin safe in the perpetual, need to rebalance before checking.
     *
     * @param   liquidityPool   The reference of liquidity pool storage.
     * @param   perpetualIndex  The index of the perpetual in the liquidity pool.
     * @param   trader          The address of the trader
     * @param   tradeAmount     The amount of positions actually traded in the transaction
     * @return  isSafe          True if Trader is maintenance margin safe in the perpetual.
     */
    function isTraderMarginSafe(
        LiquidityPoolStorage storage liquidityPool,
        uint256 perpetualIndex,
        address trader,
        int256 tradeAmount
    ) public view returns (bool isSafe) {
        PerpetualStorage storage perpetual = liquidityPool.perpetuals[perpetualIndex];
        bool hasOpened = Utils.hasOpenedPosition(perpetual.getPosition(trader), tradeAmount);
        int256 markPrice = perpetual.getMarkPrice();
        return
            hasOpened
                ? perpetual.isInitialMarginSafe(trader, markPrice)
                : perpetual.isMarginSafe(trader, markPrice);
    }

    /**
     * @dev     Initialize the liquidity pool and set up its configuration.
     *
     * @param   liquidityPool       The reference of liquidity pool storage.
     * @param   collateral          The collateral's address of the liquidity pool.
     * @param   collateralDecimals  The collateral's decimals of the liquidity pool.
     * @param   operator            The operator's address of the liquidity pool.
     * @param   governor            The governor's address of the liquidity pool.
     * @param   initData            The byte array contains data to initialze new created liquidity pool.
     */
    function initialize(
        LiquidityPoolStorage storage liquidityPool,
        address creator,
        address collateral,
        uint256 collateralDecimals,
        address operator,
        address governor,
        bytes memory initData
    ) public {
        require(collateral != address(0), "collateral is invalid");
        require(governor != address(0), "governor is invalid");

        (bool isFastCreationEnabled, int256 insuranceFundCap) =
            abi.decode(initData, (bool, int256));

        liquidityPool.initializeCollateral(collateral, collateralDecimals);
        liquidityPool.creator = creator;
        IPoolCreator poolCreator = IPoolCreator(creator);
        liquidityPool.accessController = poolCreator.getAccessController();

        liquidityPool.operator = operator;
        liquidityPool.operatorExpiration = block.timestamp.add(OPERATOR_CHECK_IN_TIMEOUT);
        liquidityPool.governor = governor;
        liquidityPool.shareToken = governor;
        liquidityPool.isFastCreationEnabled = isFastCreationEnabled;
        liquidityPool.insuranceFundCap = insuranceFundCap;
    }

    /**
     * @dev     Create and initialize new perpetual in the liquidity pool. Can only called by the operator
     *          if the liquidity pool is running or isFastCreationEnabled is set to true.
     *          Otherwise can only called by the governor
     * @param   liquidityPool       The reference of liquidity pool storage.
     * @param   oracle              The oracle's address of the perpetual
     * @param   baseParams          The base parameters of the perpetual
     * @param   riskParams          The risk parameters of the perpetual, must between minimum value and maximum value
     * @param   minRiskParamValues  The risk parameters' minimum values of the perpetual
     * @param   maxRiskParamValues  The risk parameters' maximum values of the perpetual
     */
    function createPerpetual(
        LiquidityPoolStorage storage liquidityPool,
        address oracle,
        int256[9] calldata baseParams,
        int256[8] calldata riskParams,
        int256[8] calldata minRiskParamValues,
        int256[8] calldata maxRiskParamValues
    ) public {
        require(
            liquidityPool.perpetualCount < MAX_PERPETUAL_COUNT,
            "perpetual count exceeds limit"
        );
        uint256 perpetualIndex = liquidityPool.perpetualCount;
        PerpetualStorage storage perpetual = liquidityPool.perpetuals[perpetualIndex];
        perpetual.initialize(
            perpetualIndex,
            oracle,
            baseParams,
            riskParams,
            minRiskParamValues,
            maxRiskParamValues
        );
        ISymbolService service =
            ISymbolService(IPoolCreator(liquidityPool.creator).getSymbolService());
        service.allocateSymbol(address(this), perpetualIndex);
        if (liquidityPool.isRunning) {
            perpetual.setNormalState();
        }
        liquidityPool.perpetualCount++;

        emit CreatePerpetual(
            perpetualIndex,
            liquidityPool.governor,
            liquidityPool.shareToken,
            getOperator(liquidityPool),
            oracle,
            liquidityPool.collateralToken,
            baseParams,
            riskParams
        );
    }

    /**
     * @dev     Run the liquidity pool. Can only called by the operator. The operator can create new perpetual before running
     *          or after running if isFastCreationEnabled is set to true
     *
     * @param   liquidityPool   The reference of liquidity pool storage.
     */
    function runLiquidityPool(LiquidityPoolStorage storage liquidityPool) public {
        uint256 length = liquidityPool.perpetualCount;
        require(length > 0, "there should be at least 1 perpetual to run");
        for (uint256 i = 0; i < length; i++) {
            liquidityPool.perpetuals[i].setNormalState();
        }
        liquidityPool.isRunning = true;
        emit RunLiquidityPool();
    }

    /**
     * @dev     Set the parameter of the liquidity pool. Can only called by the governor.
     *
     * @param   liquidityPool  The reference of liquidity pool storage.
     * @param   params         The new value of the parameter
     */
    function setLiquidityPoolParameter(
        LiquidityPoolStorage storage liquidityPool,
        int256[2] memory params
    ) public {
        validateLiquidityPoolParameter(params);
        liquidityPool.isFastCreationEnabled = (params[0] != 0);
        liquidityPool.insuranceFundCap = params[1];
        emit SetLiquidityPoolParameter(params);
    }

    /**
     * @dev     Validate the liquidity pool parameter:
     *            1. insurance fund cap >= 0
     * @param   liquidityPoolParams  The parameters of the liquidity pool.
     */
    function validateLiquidityPoolParameter(int256[2] memory liquidityPoolParams) public pure {
        require(liquidityPoolParams[1] >= 0, "insuranceFundCap < 0");
    }

    /**
     * @dev     Set an account as new keeper of liquidit pool.
     *          Keeper is the role to be able to call liquidateByAMM.
     *          When keeper is set to zero address, any one is able to call liquidateByAMM.
     *
     * @param   newKeeper   The account of keeper.
     */
    function setKeeper(LiquidityPoolStorage storage liquidityPool, address newKeeper) public {
        require(newKeeper != liquidityPool.keeper, "new keeper is current keeper");
        emit SetKeeper(liquidityPool.keeper, newKeeper);
        liquidityPool.keeper = newKeeper;
    }

    function setPerpetualOracle(
        LiquidityPoolStorage storage liquidityPool,
        uint256 perpetualIndex,
        address newOracle
    ) public {
        require(perpetualIndex < liquidityPool.perpetualCount, "perpetual index out of range");
        PerpetualStorage storage perpetual = liquidityPool.perpetuals[perpetualIndex];
        perpetual.setOracle(newOracle);
    }

    /**
     * @dev     Set the base parameter of the perpetual. Can only called by the governor
     * @param   liquidityPool   The reference of liquidity pool storage.
     * @param   perpetualIndex  The index of perpetual in the liquidity pool
     * @param   baseParams      The new value of the base parameter
     */
    function setPerpetualBaseParameter(
        LiquidityPoolStorage storage liquidityPool,
        uint256 perpetualIndex,
        int256[9] memory baseParams
    ) public {
        require(perpetualIndex < liquidityPool.perpetualCount, "perpetual index out of range");
        PerpetualStorage storage perpetual = liquidityPool.perpetuals[perpetualIndex];
        perpetual.setBaseParameter(baseParams);
    }

    /**
     * @dev     Set the risk parameter of the perpetual, including minimum value and maximum value.
     *          Can only called by the governor
     * @param   liquidityPool       The reference of liquidity pool storage.
     * @param   perpetualIndex      The index of perpetual in the liquidity pool
     * @param   riskParams          The new value of the risk parameter, must between minimum value and maximum value
     * @param   minRiskParamValues  The minimum value of the risk parameter
     * @param   maxRiskParamValues  The maximum value of the risk parameter
     */
    function setPerpetualRiskParameter(
        LiquidityPoolStorage storage liquidityPool,
        uint256 perpetualIndex,
        int256[8] memory riskParams,
        int256[8] memory minRiskParamValues,
        int256[8] memory maxRiskParamValues
    ) public {
        require(perpetualIndex < liquidityPool.perpetualCount, "perpetual index out of range");
        PerpetualStorage storage perpetual = liquidityPool.perpetuals[perpetualIndex];
        perpetual.setRiskParameter(riskParams, minRiskParamValues, maxRiskParamValues);
    }

    /**
     * @dev     Set the risk parameter of the perpetual. Can only called by the governor
     * @param   liquidityPool   The reference of liquidity pool storage.
     * @param   perpetualIndex  The index of perpetual in the liquidity pool
     * @param   riskParams      The new value of the risk parameter, must between minimum value and maximum value
     */
    function updatePerpetualRiskParameter(
        LiquidityPoolStorage storage liquidityPool,
        uint256 perpetualIndex,
        int256[8] memory riskParams
    ) public {
        require(perpetualIndex < liquidityPool.perpetualCount, "perpetual index out of range");
        PerpetualStorage storage perpetual = liquidityPool.perpetuals[perpetualIndex];
        perpetual.updateRiskParameter(riskParams);
    }

    /**
     * @dev     Set the state of the perpetual to "EMERGENCY". Must rebalance first.
     *          After that the perpetual is not allowed to trade, deposit and withdraw.
     *          The price of the perpetual is freezed to the settlement price
     * @param   liquidityPool   The reference of liquidity pool storage.
     * @param   perpetualIndex  The index of the perpetual in the liquidity pool
     */
    function setEmergencyState(LiquidityPoolStorage storage liquidityPool, uint256 perpetualIndex)
        public
    {
        require(perpetualIndex < liquidityPool.perpetualCount, "perpetual index out of range");
        rebalance(liquidityPool, perpetualIndex);
        liquidityPool.perpetuals[perpetualIndex].setEmergencyState();
    }

    /**
     * @dev     Set the state of all the perpetuals to "EMERGENCY". Use special type of rebalance.
     *          After rebalance, pool cash >= 0 and margin / initialMargin is the same in all perpetuals.
     *          Can only called when AMM is not maintenance margin safe in all perpetuals.
     *          After that all the perpetuals are not allowed to trade, deposit and withdraw.
     *          The price of every perpetual is freezed to the settlement price
     * @param   liquidityPool   The reference of liquidity pool storage.
     */
    function setAllPerpetualsToEmergencyState(LiquidityPoolStorage storage liquidityPool) public {
        int256 margin;
        int256 maintenanceMargin;
        int256 initialMargin;
        uint256 length = liquidityPool.perpetualCount;
        for (uint256 i = 0; i < length; i++) {
            PerpetualStorage storage perpetual = liquidityPool.perpetuals[i];
            if (perpetual.state != PerpetualState.NORMAL) {
                continue;
            }
            int256 markPrice = perpetual.getMarkPrice();
            maintenanceMargin = maintenanceMargin.add(
                perpetual.getMaintenanceMargin(address(this), markPrice)
            );
            initialMargin = initialMargin.add(perpetual.getInitialMargin(address(this), markPrice));
            margin = margin.add(perpetual.getMargin(address(this), markPrice));
        }
        margin = margin.add(liquidityPool.poolCash);
        require(margin < maintenanceMargin, "AMM's margin >= maintenance margin");
        // rebalance for settle all perps
        // Floor to make poolCash >= 0
        int256 rate = margin.wdiv(initialMargin, Round.FLOOR);
        for (uint256 i = 0; i < length; i++) {
            PerpetualStorage storage perpetual = liquidityPool.perpetuals[i];
            if (perpetual.state != PerpetualState.NORMAL) {
                continue;
            }
            int256 markPrice = perpetual.getMarkPrice();
            // Floor to make poolCash >= 0
            int256 newMargin =
                perpetual.getInitialMargin(address(this), markPrice).wmul(rate, Round.FLOOR);
            margin = perpetual.getMargin(address(this), markPrice);
            int256 deltaMargin = newMargin.sub(margin);
            if (deltaMargin > 0) {
                // from pool to perp
                perpetual.updateCash(address(this), deltaMargin);
                transferFromPoolToPerpetual(liquidityPool, i, deltaMargin);
            } else if (deltaMargin < 0) {
                // from perp to pool
                perpetual.updateCash(address(this), deltaMargin);
                transferFromPerpetualToPool(liquidityPool, i, deltaMargin.neg());
            }
            liquidityPool.perpetuals[i].setEmergencyState();
        }
        require(liquidityPool.poolCash >= 0, "negative poolCash after settle all");
    }

    /**
     * @dev     Set the state of the perpetual to "CLEARED". Add the collateral of AMM in the perpetual to the pool cash.
     *          Can only called when all the active accounts in the perpetual are cleared
     * @param   liquidityPool   The reference of liquidity pool storage.
     * @param   perpetualIndex  The index of the perpetual in the liquidity pool
     */
    function setClearedState(LiquidityPoolStorage storage liquidityPool, uint256 perpetualIndex)
        public
    {
        require(perpetualIndex < liquidityPool.perpetualCount, "perpetual index out of range");
        PerpetualStorage storage perpetual = liquidityPool.perpetuals[perpetualIndex];
        perpetual.countMargin(address(this));
        perpetual.setClearedState();
        int256 marginToReturn = perpetual.settle(address(this));
        transferFromPerpetualToPool(liquidityPool, perpetualIndex, marginToReturn);
    }

    /**
     * @dev     Specify a new address to be operator. See transferOperator in Governance.sol.
     * @param   liquidityPool    The liquidity pool storage.
     * @param   newOperator      The address of new operator to transfer to
     */
    function transferOperator(LiquidityPoolStorage storage liquidityPool, address newOperator)
        public
    {
        require(newOperator != address(0), "new operator is invalid");
        require(newOperator != getOperator(liquidityPool), "cannot transfer to current operator");
        liquidityPool.transferringOperator = newOperator;
        emit TransferOperatorTo(newOperator);
    }

    /**
     * @dev     A lease mechanism to check if the operator is alive as the pool manager.
     *          After OPERATOR_CHECK_IN_TIMEOUT, the operator will no longer be the operator.
     *          New operator will only be raised by voting.
     *          Transfer operator to another account will renew the expiration.
     *
     * @param   liquidityPool   The liquidity pool storage.
     */
    function checkIn(LiquidityPoolStorage storage liquidityPool) public {
        liquidityPool.operatorExpiration = block.timestamp.add(OPERATOR_CHECK_IN_TIMEOUT);
        emit OperatorCheckIn(getOperator(liquidityPool));
    }

    /**
     * @dev  Claim the ownership of the liquidity pool to claimer. See `transferOperator` in Governance.sol.
     * @param   liquidityPool   The liquidity pool storage.
     * @param   claimer         The address of claimer
     */
    function claimOperator(LiquidityPoolStorage storage liquidityPool, address claimer) public {
        require(claimer == liquidityPool.transferringOperator, "caller is not qualified");
        liquidityPool.operator = claimer;
        liquidityPool.operatorExpiration = block.timestamp.add(OPERATOR_CHECK_IN_TIMEOUT);
        liquidityPool.transferringOperator = address(0);
        IPoolCreator(liquidityPool.creator).registerOperatorOfLiquidityPool(address(this), claimer);
        emit ClaimOperator(claimer);
    }

    /**
     * @dev  Revoke operatorship of the liquidity pool.
     * @param   liquidityPool   The liquidity pool object
     */
    function revokeOperator(LiquidityPoolStorage storage liquidityPool) public {
        liquidityPool.operator = address(0);
        IPoolCreator(liquidityPool.creator).registerOperatorOfLiquidityPool(
            address(this),
            address(0)
        );
        emit RevokeOperator();
    }

    /**
     * @dev     Update the funding state of each perpetual of the liquidity pool. Funding payment of every account in the
     *          liquidity pool is updated
     * @param   liquidityPool   The reference of liquidity pool storage.
     * @param   currentTime     The current timestamp
     */
    function updateFundingState(LiquidityPoolStorage storage liquidityPool, uint256 currentTime)
        public
    {
        if (liquidityPool.fundingTime >= currentTime) {
            // invalid time
            return;
        }
        int256 timeElapsed = currentTime.sub(liquidityPool.fundingTime).toInt256();
        uint256 length = liquidityPool.perpetualCount;
        for (uint256 i = 0; i < length; i++) {
            PerpetualStorage storage perpetual = liquidityPool.perpetuals[i];
            if (perpetual.state != PerpetualState.NORMAL) {
                continue;
            }
            perpetual.updateFundingState(timeElapsed);
        }
        liquidityPool.fundingTime = currentTime;
    }

    /**
     * @dev     Update the funding rate of each perpetual of the liquidity pool
     * @param   liquidityPool   The reference of liquidity pool storage.
     */
    function updateFundingRate(LiquidityPoolStorage storage liquidityPool) public {
        (int256 poolMargin, bool isAMMSafe) = liquidityPool.getPoolMargin();
        emit UpdatePoolMargin(poolMargin);
        if (!isAMMSafe) {
            poolMargin = 0;
        }
        uint256 length = liquidityPool.perpetualCount;
        for (uint256 i = 0; i < length; i++) {
            PerpetualStorage storage perpetual = liquidityPool.perpetuals[i];
            if (perpetual.state != PerpetualState.NORMAL) {
                continue;
            }
            perpetual.updateFundingRate(poolMargin);
        }
    }

    /**
     * @dev     Update the oracle price of each perpetual of the liquidity pool.
     *          If oracle is terminated, set market to EMERGENCY.
     *
     * @param   liquidityPool   The liquidity pool object
     * @param   currentTime     The current timestamp
     */
    function updatePrice(
        LiquidityPoolStorage storage liquidityPool,
        uint256 currentTime,
        bool ignoreTerminated
    ) public {
        if (liquidityPool.priceUpdateTime >= currentTime) {
            return;
        }
        uint256 length = liquidityPool.perpetualCount;
        for (uint256 i = 0; i < length; i++) {
            PerpetualStorage storage perpetual = liquidityPool.perpetuals[i];
            if (perpetual.state != PerpetualState.NORMAL) {
                continue;
            }
            perpetual.updatePrice();
            if (IOracle(perpetual.oracle).isTerminated() && !ignoreTerminated) {
                setEmergencyState(liquidityPool, perpetual.id);
            }
        }
        liquidityPool.priceUpdateTime = currentTime;
    }

    /**
     * @dev     Donate collateral to the insurance fund of the liquidity pool to make the liquidity pool safe.
     *
     * @param   liquidityPool   The liquidity pool object
     * @param   amount          The amount of collateral to donate
     */
    function donateInsuranceFund(
        LiquidityPoolStorage storage liquidityPool,
        address donator,
        int256 amount
    ) public {
        require(amount > 0, "invalid amount");
        liquidityPool.transferFromUser(donator, amount);
        liquidityPool.donatedInsuranceFund = liquidityPool.donatedInsuranceFund.add(amount);
        emit DonateInsuranceFund(amount);
    }

    /**
     * @dev     Update the collateral of the insurance fund in the liquidity pool.
     *          If the collateral of the insurance fund exceeds the cap, the extra part of collateral belongs to LP.
     *          If the collateral of the insurance fund < 0, the donated insurance fund will cover it.
     *
     * @param   liquidityPool   The liquidity pool object
     * @param   deltaFund       The update collateral amount of the insurance fund in the perpetual
     * @return  penaltyToLP     The extra part of collateral if the collateral of the insurance fund exceeds the cap
     */
    function updateInsuranceFund(LiquidityPoolStorage storage liquidityPool, int256 deltaFund)
        public
        returns (int256 penaltyToLP)
    {
        if (deltaFund != 0) {
            int256 newInsuranceFund = liquidityPool.insuranceFund.add(deltaFund);
            if (deltaFund > 0) {
                if (newInsuranceFund > liquidityPool.insuranceFundCap) {
                    penaltyToLP = newInsuranceFund.sub(liquidityPool.insuranceFundCap);
                    newInsuranceFund = liquidityPool.insuranceFundCap;
                    emit TransferExcessInsuranceFundToLP(penaltyToLP);
                }
            } else {
                if (newInsuranceFund < 0) {
                    liquidityPool.donatedInsuranceFund = liquidityPool.donatedInsuranceFund.add(
                        newInsuranceFund
                    );
                    require(
                        liquidityPool.donatedInsuranceFund >= 0,
                        "negative donated insurance fund"
                    );
                    newInsuranceFund = 0;
                }
            }
            liquidityPool.insuranceFund = newInsuranceFund;
        }
    }

    /**
     * @dev     Deposit collateral to the trader's account of the perpetual. The trader's cash will increase.
     *          Activate the perpetual for the trader if the account in the perpetual is empty before depositing.
     *          Empty means cash and position are zero.
     *
     * @param   liquidityPool   The liquidity pool object
     * @param   perpetualIndex  The index of the perpetual in the liquidity pool
     * @param   trader          The address of the trader
     * @param   amount          The amount of collateral to deposit
     */
    function deposit(
        LiquidityPoolStorage storage liquidityPool,
        uint256 perpetualIndex,
        address trader,
        int256 amount
    ) public {
        require(perpetualIndex < liquidityPool.perpetualCount, "perpetual index out of range");
        transferFromUserToPerpetual(liquidityPool, perpetualIndex, trader, amount);
        if (liquidityPool.perpetuals[perpetualIndex].deposit(trader, amount)) {
            IPoolCreator(liquidityPool.creator).activatePerpetualFor(trader, perpetualIndex);
        }
    }

    /**
     * @dev     Withdraw collateral from the trader's account of the perpetual. The trader's cash will decrease.
     *          Trader must be initial margin safe in the perpetual after withdrawing.
     *          Deactivate the perpetual for the trader if the account in the perpetual is empty after withdrawing.
     *          Empty means cash and position are zero.
     *
     * @param   liquidityPool   The liquidity pool object
     * @param   perpetualIndex  The index of the perpetual in the liquidity pool
     * @param   trader          The address of the trader
     * @param   amount          The amount of collateral to withdraw
     */
    function withdraw(
        LiquidityPoolStorage storage liquidityPool,
        uint256 perpetualIndex,
        address trader,
        int256 amount
    ) public {
        require(perpetualIndex < liquidityPool.perpetualCount, "perpetual index out of range");
        PerpetualStorage storage perpetual = liquidityPool.perpetuals[perpetualIndex];
        rebalance(liquidityPool, perpetualIndex);
        if (perpetual.withdraw(trader, amount)) {
            IPoolCreator(liquidityPool.creator).deactivatePerpetualFor(trader, perpetualIndex);
        }
        transferFromPerpetualToUser(liquidityPool, perpetualIndex, trader, amount);
    }

    /**
     * @dev     If the state of the perpetual is "CLEARED", anyone authorized withdraw privilege by trader can settle
     *          trader's account in the perpetual. Which means to calculate how much the collateral should be returned
     *          to the trader, return it to trader's wallet and clear the trader's cash and position in the perpetual.
     *
     * @param   liquidityPool   The reference of liquidity pool storage.
     * @param   perpetualIndex  The index of the perpetual in the liquidity pool.
     * @param   trader          The address of the trader.
     */
    function settle(
        LiquidityPoolStorage storage liquidityPool,
        uint256 perpetualIndex,
        address trader
    ) public {
        require(trader != address(0), "invalid trader");
        int256 marginToReturn = liquidityPool.perpetuals[perpetualIndex].settle(trader);
        require(marginToReturn > 0, "no margin to settle");
        transferFromPerpetualToUser(liquidityPool, perpetualIndex, trader, marginToReturn);
    }

    /**
     * @dev     Clear the next active account of the perpetual which state is "EMERGENCY" and send gas reward of collateral
     *          to sender. If all active accounts are cleared, the clear progress is done and the perpetual's state will
     *          change to "CLEARED". Active means the trader's account is not empty in the perpetual.
     *          Empty means cash and position are zero.
     *
     * @param   liquidityPool   The reference of liquidity pool storage.
     * @param   perpetualIndex  The index of the perpetual in the liquidity pool
     */
    function clear(
        LiquidityPoolStorage storage liquidityPool,
        uint256 perpetualIndex,
        address trader
    ) public {
        PerpetualStorage storage perpetual = liquidityPool.perpetuals[perpetualIndex];
        if (
            perpetual.keeperGasReward > 0 && perpetual.totalCollateral >= perpetual.keeperGasReward
        ) {
            transferFromPerpetualToUser(
                liquidityPool,
                perpetualIndex,
                trader,
                perpetual.keeperGasReward
            );
        }
        if (
            perpetual.activeAccounts.length() == 0 ||
            perpetual.clear(perpetual.getNextActiveAccount())
        ) {
            setClearedState(liquidityPool, perpetualIndex);
        }
    }

    /**
     * @dev Add collateral to the liquidity pool and get the minted share tokens.
     *      The share token is the credential and use to get the collateral back when removing liquidity.
     *      Can only called when at least 1 perpetual is in NORMAL state.
     *
     * @param   liquidityPool   The reference of liquidity pool storage.
     * @param trader The address of the trader that adding liquidity
     * @param cashToAdd The cash(collateral) to add
     */
    function addLiquidity(
        LiquidityPoolStorage storage liquidityPool,
        address trader,
        int256 cashToAdd
    ) public {
        require(cashToAdd > 0, "cash amount must be positive");
        uint256 length = liquidityPool.perpetualCount;
        bool allowAdd;
        for (uint256 i = 0; i < length; i++) {
            if (liquidityPool.perpetuals[i].state == PerpetualState.NORMAL) {
                allowAdd = true;
                break;
            }
        }

        require(allowAdd, "not all perpetuals are in NORMAL state");
        liquidityPool.transferFromUser(trader, cashToAdd);

        IGovernor shareToken = IGovernor(liquidityPool.shareToken);
        int256 shareTotalSupply = shareToken.totalSupply().toInt256();

        (int256 shareToMint, int256 addedPoolMargin) =
            liquidityPool.getShareToMint(shareTotalSupply, cashToAdd);
        require(shareToMint > 0, "received share must be positive");
        // pool cash cannot be added before calculation, DO NOT use transferFromUserToPool

        increasePoolCash(liquidityPool, cashToAdd);
        shareToken.mint(trader, shareToMint.toUint256());

        emit AddLiquidity(trader, cashToAdd, shareToMint, addedPoolMargin);
    }

    /**
     * @dev     Remove collateral from the liquidity pool and redeem the share tokens when the liquidity pool is running.
     *          Only one of shareToRemove or cashToReturn may be non-zero.
     *
     * @param   liquidityPool   The reference of liquidity pool storage.
     * @param   trader          The address of the trader that removing liquidity.
     * @param   shareToRemove   The amount of the share token to redeem.
     * @param   cashToReturn    The amount of cash(collateral) to return.
     */
    function removeLiquidity(
        LiquidityPoolStorage storage liquidityPool,
        address trader,
        int256 shareToRemove,
        int256 cashToReturn
    ) public {
        IGovernor shareToken = IGovernor(liquidityPool.shareToken);
        int256 shareTotalSupply = shareToken.totalSupply().toInt256();
        int256 removedInsuranceFund;
        int256 removedDonatedInsuranceFund;
        int256 removedPoolMargin;
        if (cashToReturn == 0 && shareToRemove > 0) {
            (
                cashToReturn,
                removedInsuranceFund,
                removedDonatedInsuranceFund,
                removedPoolMargin
            ) = liquidityPool.getCashToReturn(shareTotalSupply, shareToRemove);
            require(cashToReturn > 0, "cash to return must be positive");
        } else if (cashToReturn > 0 && shareToRemove == 0) {
            (
                shareToRemove,
                removedInsuranceFund,
                removedDonatedInsuranceFund,
                removedPoolMargin
            ) = liquidityPool.getShareToRemove(shareTotalSupply, cashToReturn);
            require(shareToRemove > 0, "share to remove must be positive");
        } else {
            revert("invalid parameter");
        }
        require(
            shareToRemove.toUint256() <= shareToken.balanceOf(trader),
            "insufficient share balance"
        );
        int256 removedCashFromPool =
            cashToReturn.sub(removedInsuranceFund).sub(removedDonatedInsuranceFund);
        require(
            removedCashFromPool <= getAvailablePoolCash(liquidityPool),
            "insufficient pool cash"
        );
        shareToken.burn(trader, shareToRemove.toUint256());

        liquidityPool.transferToUser(trader, cashToReturn);
        liquidityPool.insuranceFund = liquidityPool.insuranceFund.sub(removedInsuranceFund);
        liquidityPool.donatedInsuranceFund = liquidityPool.donatedInsuranceFund.sub(
            removedDonatedInsuranceFund
        );
        decreasePoolCash(liquidityPool, removedCashFromPool);
        emit RemoveLiquidity(trader, cashToReturn, shareToRemove, removedPoolMargin);
    }

    /**
     * @dev     Add collateral to the liquidity pool without getting share tokens.
     *
     * @param   liquidityPool   The reference of liquidity pool storage.
     * @param   trader          The address of the trader that adding liquidity
     * @param   cashToAdd       The cash(collateral) to add
     */
    function donateLiquidity(
        LiquidityPoolStorage storage liquidityPool,
        address trader,
        int256 cashToAdd
    ) public {
        require(cashToAdd > 0, "cash amount must be positive");
        (, int256 addedPoolMargin) = liquidityPool.getShareToMint(0, cashToAdd);
        liquidityPool.transferFromUser(trader, cashToAdd);
        // pool cash cannot be added before calculation, DO NOT use transferFromUserToPool
        increasePoolCash(liquidityPool, cashToAdd);
        emit AddLiquidity(trader, cashToAdd, 0, addedPoolMargin);
    }

    /**
     * @dev     To keep the AMM's margin equal to initial margin in the perpetual as posiible.
     *          Transfer collateral between the perpetual and the liquidity pool's cash, then
     *          update the AMM's cash in perpetual. The liquidity pool's cash can be negative,
     *          but the available cash can't. If AMM need to transfer and the available cash
     *          is not enough, transfer all the rest available cash of collateral.
     *
     * @param   liquidityPool   The reference of liquidity pool storage.
     * @param   perpetualIndex  The index of the perpetual in the liquidity pool
     * @return  The amount of rebalanced margin. A positive amount indicates the collaterals
     *          are moved from perpetual to pool, and a negative amount indicates the opposite.
     *          0 means no rebalance happened.
     */
    function rebalance(LiquidityPoolStorage storage liquidityPool, uint256 perpetualIndex)
        public
        returns (int256)
    {
        require(perpetualIndex < liquidityPool.perpetualCount, "perpetual index out of range");
        PerpetualStorage storage perpetual = liquidityPool.perpetuals[perpetualIndex];
        if (perpetual.state != PerpetualState.NORMAL) {
            return 0;
        }
        int256 rebalanceMargin = perpetual.getRebalanceMargin();
        if (rebalanceMargin == 0) {
            // nothing to rebalance
            return 0;
        } else if (rebalanceMargin > 0) {
            // from perp to pool
            perpetual.updateCash(address(this), rebalanceMargin.neg());
            transferFromPerpetualToPool(liquidityPool, perpetualIndex, rebalanceMargin);
        } else {
            // from pool to perp
            int256 availablePoolCash = getAvailablePoolCash(liquidityPool, perpetualIndex);
            if (availablePoolCash <= 0) {
                // pool has no more collateral, nothing to rebalance
                return 0;
            }
            rebalanceMargin = rebalanceMargin.abs().min(availablePoolCash);
            perpetual.updateCash(address(this), rebalanceMargin);
            transferFromPoolToPerpetual(liquidityPool, perpetualIndex, rebalanceMargin);
        }
        return rebalanceMargin;
    }

    /**
     * @dev     Increase the liquidity pool's cash(collateral).
     * @param   liquidityPool   The reference of liquidity pool storage.
     * @param   amount          The amount of cash(collateral) to increase.
     */
    function increasePoolCash(LiquidityPoolStorage storage liquidityPool, int256 amount) internal {
        require(amount >= 0, "increase negative pool cash");
        liquidityPool.poolCash = liquidityPool.poolCash.add(amount);
    }

    /**
     * @dev     Decrease the liquidity pool's cash(collateral).
     * @param   liquidityPool   The reference of liquidity pool storage.
     * @param   amount          The amount of cash(collateral) to decrease.
     */
    function decreasePoolCash(LiquidityPoolStorage storage liquidityPool, int256 amount) internal {
        require(amount >= 0, "decrease negative pool cash");
        liquidityPool.poolCash = liquidityPool.poolCash.sub(amount);
    }

    // user <=> pool (addLiquidity/removeLiquidity)
    function transferFromUserToPool(
        LiquidityPoolStorage storage liquidityPool,
        address account,
        int256 amount
    ) public {
        liquidityPool.transferFromUser(account, amount);
        increasePoolCash(liquidityPool, amount);
    }

    function transferFromPoolToUser(
        LiquidityPoolStorage storage liquidityPool,
        address account,
        int256 amount
    ) public {
        if (amount == 0) {
            return;
        }
        liquidityPool.transferToUser(account, amount);
        decreasePoolCash(liquidityPool, amount);
    }

    // user <=> perpetual (deposit/withdraw)
    function transferFromUserToPerpetual(
        LiquidityPoolStorage storage liquidityPool,
        uint256 perpetualIndex,
        address account,
        int256 amount
    ) public {
        liquidityPool.transferFromUser(account, amount);
        liquidityPool.perpetuals[perpetualIndex].increaseTotalCollateral(amount);
    }

    function transferFromPerpetualToUser(
        LiquidityPoolStorage storage liquidityPool,
        uint256 perpetualIndex,
        address account,
        int256 amount
    ) public {
        if (amount == 0) {
            return;
        }
        liquidityPool.transferToUser(account, amount);
        liquidityPool.perpetuals[perpetualIndex].decreaseTotalCollateral(amount);
    }

    // pool <=> perpetual (fee/rebalance)
    function transferFromPerpetualToPool(
        LiquidityPoolStorage storage liquidityPool,
        uint256 perpetualIndex,
        int256 amount
    ) public {
        if (amount == 0) {
            return;
        }
        liquidityPool.perpetuals[perpetualIndex].decreaseTotalCollateral(amount);
        increasePoolCash(liquidityPool, amount);
    }

    function transferFromPoolToPerpetual(
        LiquidityPoolStorage storage liquidityPool,
        uint256 perpetualIndex,
        int256 amount
    ) public {
        if (amount == 0) {
            return;
        }
        liquidityPool.perpetuals[perpetualIndex].increaseTotalCollateral(amount);
        decreasePoolCash(liquidityPool, amount);
    }

    /**
     * @dev Check if the trader is authorized the privilege by the grantee. Any trader is authorized by himself
     * @param liquidityPool The reference of liquidity pool storage.
     * @param trader The address of the trader
     * @param grantee The address of the grantee
     * @param privilege The privilege
     * @return isGranted True if the trader is authorized
     */
    function isAuthorized(
        LiquidityPoolStorage storage liquidityPool,
        address trader,
        address grantee,
        uint256 privilege
    ) public view returns (bool isGranted) {
        isGranted =
            trader == grantee ||
            IAccessControl(liquidityPool.accessController).isGranted(trader, grantee, privilege);
    }

    /**
     * @dev     Deposit or withdraw to let effective leverage == target leverage
     *
     * @param   liquidityPool   The reference of liquidity pool storage.
     * @param   perpetualIndex  The index of the perpetual in the liquidity pool.
     * @param   trader          The address of the trader.
     * @param   deltaPosition   The update position of the trader's account in the perpetual.
     * @param   deltaCash       The update cash(collateral) of the trader's account in the perpetual.
     * @param   totalFee        The total fee collected from the trader after the trade.
     */
    function adjustMarginLeverage(
        LiquidityPoolStorage storage liquidityPool,
        uint256 perpetualIndex,
        address trader,
        int256 deltaPosition,
        int256 deltaCash,
        int256 totalFee
    ) public {
        PerpetualStorage storage perpetual = liquidityPool.perpetuals[perpetualIndex];
        // read perp
        int256 position = perpetual.getPosition(trader);
        int256 adjustCollateral;
        (int256 closePosition, int256 openPosition) =
            Utils.splitAmount(position.sub(deltaPosition), deltaPosition);
        if (closePosition != 0 && openPosition == 0) {
            // close only
            adjustCollateral = adjustClosedMargin(
                perpetual,
                trader,
                closePosition,
                deltaCash,
                totalFee
            );
        } else {
            // open only or close + open
            adjustCollateral = adjustOpenedMargin(
                perpetual,
                trader,
                deltaPosition,
                deltaCash,
                closePosition,
                openPosition,
                totalFee
            );
        }
        // real deposit/withdraw
        if (adjustCollateral > 0) {
            deposit(liquidityPool, perpetualIndex, trader, adjustCollateral);
        } else if (adjustCollateral < 0) {
            withdraw(liquidityPool, perpetualIndex, trader, adjustCollateral.neg());
        }
    }

    function adjustClosedMargin(
        PerpetualStorage storage perpetual,
        address trader,
        int256 closePosition,
        int256 deltaCash,
        int256 totalFee
    ) public view returns (int256 adjustCollateral) {
        int256 markPrice = perpetual.getMarkPrice();
        int256 position2 = perpetual.getPosition(trader);
        // when close, keep the margin ratio
        // -withdraw == (availableCash2 * close - (deltaCash - fee) * position2 + reservedValue) / position1
        // reservedValue = 0 if position2 == 0 else keeperGasReward * (-deltaPos)
        adjustCollateral = perpetual.getAvailableCash(trader).wmul(closePosition);
        adjustCollateral = adjustCollateral.sub(deltaCash.sub(totalFee).wmul(position2));
        if (position2 != 0) {
            adjustCollateral = adjustCollateral.sub(perpetual.keeperGasReward.wmul(closePosition));
        }
        adjustCollateral = adjustCollateral.wdiv(position2.sub(closePosition));
        // withdraw only when IM is satisfied
        adjustCollateral = adjustCollateral.max(
            perpetual.getAvailableMargin(trader, markPrice).neg()
        );
        // never deposit when close positions
        adjustCollateral = adjustCollateral.min(0);
    }

    // open only or close + open
    function adjustOpenedMargin(
        PerpetualStorage storage perpetual,
        address trader,
        int256 deltaPosition,
        int256 deltaCash,
        int256 closePosition,
        int256 openPosition,
        int256 totalFee
    ) public view returns (int256 adjustCollateral) {
        int256 markPrice = perpetual.getMarkPrice();
        int256 oldMargin = perpetual.getMargin(trader, markPrice);
        int256 leverage = perpetual.getTargetLeverage(trader);
        require(leverage > 0, "target leverage = 0");
        // openPositionMargin
        adjustCollateral = openPosition.abs().wfrac(markPrice, leverage);
        if (perpetual.getPosition(trader).sub(deltaPosition) != 0 && closePosition == 0) {
            // open from non-zero position
            // adjustCollateral = openPositionMargin + fee - pnl
            adjustCollateral = adjustCollateral
                .add(totalFee)
                .sub(markPrice.wmul(deltaPosition))
                .sub(deltaCash);
        } else {
            // open from 0 or close + open
            adjustCollateral = adjustCollateral.sub(oldMargin);
        }
        // make sure after adjust: trader is initial margin safe
        adjustCollateral = adjustCollateral.max(
            perpetual.getAvailableMargin(trader, markPrice).neg()
        );
    }

    function setTargetLeverage(
        LiquidityPoolStorage storage liquidityPool,
        uint256 perpetualIndex,
        address trader,
        int256 targetLeverage
    ) public {
        PerpetualStorage storage perpetual = liquidityPool.perpetuals[perpetualIndex];
        require(perpetual.initialMarginRate != 0, "initialMarginRate is not set");
        require(
            targetLeverage != perpetual.marginAccounts[trader].targetLeverage,
            "targetLeverage is already set"
        );
        int256 maxLeverage = Constant.SIGNED_ONE.wdiv(perpetual.initialMarginRate);
        require(targetLeverage <= maxLeverage, "targetLeverage exceeds maxLeverage");
        perpetual.setTargetLeverage(trader, targetLeverage);
        emit SetTargetLeverage(trader, targetLeverage);
    }
}
