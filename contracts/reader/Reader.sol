// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.7.4;
pragma experimental ABIEncoderV2;

import "../Type.sol";
import "../interface/ILiquidityPool.sol";
import "../interface/IOracle.sol";
import "../interface/IPoolCreator.sol";
import "../interface/ISymbolService.sol";
import "../interface/ISymbolService.sol";
import "../libraries/SafeMathExt.sol";

contract Reader {
    using SafeMathExt for uint256;

    struct LiquidityPoolReaderResult {
        bool isRunning;
        bool isFastCreationEnabled;
        // check Getter.sol for detail
        address[7] addresses;
        int256[5] intNums;
        uint256[4] uintNums;
        PerpetualReaderResult[] perpetuals;
    }

    struct PerpetualReaderResult {
        PerpetualState state;
        address oracle;
        // check Getter.sol for detail
        int256[39] nums;
        uint256 symbol; // minimum number in the symbol service
        string underlyingAsset;
        bool isMarketClosed;
        int256 ammCashBalance;
        int256 ammPositionAmount;
    }

    struct AccountReaderResult {
        int256 cash;
        int256 position;
        int256 availableMargin;
        int256 margin;
        int256 settleableMargin;
        bool isInitialMarginSafe;
        bool isMaintenanceMarginSafe;
        bool isMarginSafe;
        int256 targetLeverage;
    }

    struct AccountsResult {
        address account;
        int256 position;
        int256 margin;
        bool isSafe;
    }

    address public immutable poolCreator;

    constructor(address _poolCreator) {
        poolCreator = _poolCreator;
    }

    /**
     * @notice Get the storage of the account in the perpetual
     * @param liquidityPool The address of the liquidity pool
     * @param perpetualIndex The index of the perpetual in the liquidity pool
     * @param account The address of the account
     *                Note: When account == liquidityPool, is*Safe are meanless. Do not forget to sum
     *                      poolCash and availableCash of all perpetuals in a liquidityPool when
     *                      calculating AMM margin
     * @return isSynced True if the funding state is synced to real-time data. False if
     *                  error happens (oracle error, zero price etc.). In this case,
     *                  trading, withdraw (if position != 0), addLiquidity, removeLiquidity
     *                  will fail
     * @return accountStorage The storage of the account in the perpetual
     */
    function getAccountStorage(
        address liquidityPool,
        uint256 perpetualIndex,
        address account
    ) public returns (bool isSynced, AccountReaderResult memory accountStorage) {
        try ILiquidityPool(liquidityPool).forceToSyncState() {
            isSynced = true;
        } catch {
            isSynced = false;
        }
        (bool success, bytes memory data) =
            liquidityPool.call(
                abi.encodeWithSignature(
                    "getMarginAccount(uint256,address)",
                    perpetualIndex,
                    account
                )
            );
        require(success, "fail to retrieve margin account");
        accountStorage = _parseMarginAccount(data);
    }

    function _parseMarginAccount(bytes memory data)
        internal
        pure
        returns (AccountReaderResult memory accountStorage)
    {
        require(data.length % 0x20 == 0, "malform input data");
        assembly {
            let len := mload(data)
            let src := add(data, 0x20)
            let dst := accountStorage
            for {
                let end := add(src, len)
            } lt(src, end) {
                src := add(src, 0x20)
                dst := add(dst, 0x20)
            } {
                mstore(dst, mload(src))
            }
        }
    }

    /**
     * @notice Get the pool margin of the liquidity pool
     * @param liquidityPool The address of the liquidity pool
     * @return isSynced True if the funding state is synced to real-time data. False if
     *                  error happens (oracle error, zero price etc.). In this case,
     *                  trading, withdraw (if position != 0), addLiquidity, removeLiquidity
     *                  will fail
     * @return poolMargin The pool margin of the liquidity pool
     */
    function getPoolMargin(address liquidityPool)
        public
        returns (
            bool isSynced,
            int256 poolMargin,
            bool isSafe
        )
    {
        try ILiquidityPool(liquidityPool).forceToSyncState() {
            isSynced = true;
        } catch {
            isSynced = false;
        }
        (poolMargin, isSafe) = ILiquidityPool(liquidityPool).getPoolMargin();
    }

    /**
     * @notice  Query the cost and position amount that amm could afford based on current liquidity.
     *          Trading fee is not included.
     * @param   liquidityPool   The address of the liquidity pool
     * @param   perpetualIndex  The index of the perpetual in liquidity pool.
     * @param   amount          The expected(max) amoun of position to trade.
     * @return  isSynced        True if the funding state is synced to real-time data. False if
     *                          error happens (oracle error, zero price etc.). In this case,
     *                          trading, withdraw (if position != 0), addLiquidity, removeLiquidity
     *                          will fail
     * @return  deltaCash       The cost of cash of trade.
     * @return  deltaPosition   The update position of the trader after the trade
     */
    function queryTradeWithAMM(
        address liquidityPool,
        uint256 perpetualIndex,
        int256 amount
    )
        public
        returns (
            bool isSynced,
            int256 deltaCash,
            int256 deltaPosition
        )
    {
        try ILiquidityPool(liquidityPool).forceToSyncState() {
            isSynced = true;
        } catch {
            isSynced = false;
        }
        (deltaCash, deltaPosition) = ILiquidityPool(liquidityPool).queryTradeWithAMM(
            perpetualIndex,
            amount
        );
    }

    /**
     * @notice Get the status of the liquidity pool
     * @param liquidityPool The address of the liquidity pool
     * @return isSynced True if the funding state is synced to real-time data. False if
     *                  error happens (oracle error, zero price etc.). In this case,
     *                  trading, withdraw (if position != 0), addLiquidity, removeLiquidity
     *                  will fail
     * @return pool The status of the liquidity pool
     */
    function getLiquidityPoolStorage(address liquidityPool)
        public
        returns (bool isSynced, LiquidityPoolReaderResult memory pool)
    {
        try ILiquidityPool(liquidityPool).forceToSyncState() {
            isSynced = true;
        } catch {
            isSynced = false;
        }
        // pool
        (
            pool.isRunning,
            pool.isFastCreationEnabled,
            pool.addresses,
            pool.intNums,
            pool.uintNums
        ) = ILiquidityPool(liquidityPool).getLiquidityPoolInfo();
        // perpetual
        uint256 perpetualCount = pool.uintNums[1];
        address symbolService = IPoolCreator(pool.addresses[0]).getSymbolService();
        pool.perpetuals = new PerpetualReaderResult[](perpetualCount);
        for (uint256 i = 0; i < perpetualCount; i++) {
            getPerpetual(pool.perpetuals[i], symbolService, liquidityPool, i);
        }
    }

    function getPerpetual(
        PerpetualReaderResult memory perp,
        address symbolService,
        address liquidityPool,
        uint256 perpetualIndex
    ) private {
        // perpetual
        (perp.state, perp.oracle, perp.nums) = ILiquidityPool(liquidityPool).getPerpetualInfo(
            perpetualIndex
        );
        // read more from symbol service
        perp.symbol = getMinSymbol(symbolService, liquidityPool, perpetualIndex);
        // read more from oracle
        perp.underlyingAsset = IOracle(perp.oracle).underlyingAsset();
        perp.isMarketClosed = IOracle(perp.oracle).isMarketClosed();
        // read more from account
        (perp.ammCashBalance, perp.ammPositionAmount, , , , , , , ) = ILiquidityPool(liquidityPool)
            .getMarginAccount(perpetualIndex, liquidityPool);
    }

    function getMinSymbol(
        address symbolService,
        address liquidityPool,
        uint256 perpetualIndex
    ) private view returns (uint256) {
        uint256[] memory symbols;
        symbols = ISymbolService(symbolService).getSymbols(liquidityPool, perpetualIndex);
        uint256 symbolLength = symbols.length;
        require(symbolLength >= 1, "symbol not found");
        uint256 minSymbol = type(uint256).max;
        for (uint256 i = 0; i < symbolLength; i++) {
            minSymbol = minSymbol.min(symbols[i]);
        }
        return minSymbol;
    }

    ////////////////////////////////////////////////////////////////////////////////////
    // back-compatible: beta0.0.4

    function getImplementation(address proxy) public view returns (address) {
        IProxyAdmin proxyAdmin = IPoolCreator(poolCreator).upgradeAdmin();
        return proxyAdmin.getProxyImplementation(proxy);
    }

    function isV004(address imp) private pure returns (bool) {
        // kovan
        if (
            imp == 0xBE190440CDaC7F82089C17DA73974aC8a5864Ef8 ||
            imp == 0xEBB6C33196047c79d2ABc405022054A6cD7bB95C
        ) {
            return true;
        }
        return false;
    }

    function getPoolMarginV004(address liquidityPool)
        private
        view
        returns (int256 poolMargin, bool isSafe)
    {
        poolMargin = ILiquidityPool004(liquidityPool).getPoolMargin();
        isSafe = true;
    }

    function getPerpetualV004(
        PerpetualReaderResult memory perp,
        address symbolService,
        address liquidityPool,
        uint256 perpetualIndex
    )
        private
        returns (
            int256 insuranceFundCap,
            int256 insuranceFund,
            int256 donatedInsuranceFund
        )
    {
        // perpetual
        int256[34] memory nums;
        (perp.state, perp.oracle, nums) = ILiquidityPool004(liquidityPool).getPerpetualInfo(
            perpetualIndex
        );
        insuranceFundCap = nums[13];
        insuranceFund = nums[14];
        donatedInsuranceFund = nums[15];
        for (uint256 i = 0; i < 31; i++) {
            if (i >= 13) {
                // insuranceFundCap, insuranceFund, donatedInsuranceFund are moved to liquidityPoolStorage
                perp.nums[i] = nums[i + 3];
            } else {
                // 0-12, unchanged
                perp.nums[i] = nums[i];
            }
        }
        perp.nums[31] = 0; // [31] openInterest
        perp.nums[32] = 100 * 10**18; // [32] maxOpenInterestRate
        perp.nums[33] = perp.nums[22]; // [22-24] fundingRateLimit value, min, max [33-35] fundingRateFactor value, min, max
        perp.nums[34] = perp.nums[23];
        perp.nums[35] = perp.nums[24];
        // read more from symbol service
        perp.symbol = getMinSymbol(symbolService, liquidityPool, perpetualIndex);
        // read more from oracle
        perp.underlyingAsset = IOracle(perp.oracle).underlyingAsset();
        perp.isMarketClosed = IOracle(perp.oracle).isMarketClosed();
        // read more from account
        (perp.ammCashBalance, perp.ammPositionAmount, , , , , , , ) = ILiquidityPool(liquidityPool)
            .getMarginAccount(perpetualIndex, liquidityPool);
    }

    /**
     * @notice  Get the info of active accounts in the perpetual whose index with range [begin, end).
     * @param   liquidityPool   The address of the liquidity pool
     * @param   perpetualIndex  The index of the perpetual in the liquidity pool.
     * @param   begin           The begin index of account to retrieve.
     * @param   end             The end index of account, exclusive.
     * @return  isSynced        True if the funding state is synced to real-time data. False if
     *                          error happens (oracle error, zero price etc.). In this case,
     *                          trading, withdraw (if position != 0), addLiquidity, removeLiquidity
     *                          will fail
     * @return  result          An array of active accounts' info.
     */
    function getAccountsInfo(
        address liquidityPool,
        uint256 perpetualIndex,
        uint256 begin,
        uint256 end
    ) public returns (bool isSynced, AccountsResult[] memory result) {
        address[] memory accounts =
            ILiquidityPool(liquidityPool).listActiveAccounts(perpetualIndex, begin, end);
        try ILiquidityPool(liquidityPool).forceToSyncState() {
            isSynced = true;
        } catch {
            isSynced = false;
        }
        result = new AccountsResult[](accounts.length);
        for (uint256 i = 0; i < accounts.length; i++) {
            int256 margin;
            int256 position;
            bool isMaintenanceMarginSafe;
            (, position, , margin, , , isMaintenanceMarginSafe, , ) = ILiquidityPool(liquidityPool)
                .getMarginAccount(perpetualIndex, accounts[i]);
            result[i].account = accounts[i];
            result[i].position = position;
            result[i].margin = margin;
            result[i].isSafe = isMaintenanceMarginSafe;
        }
    }

    /**
     * @notice  Query cash to add / share to mint when adding liquidity to the liquidity pool.
     *          Only one of cashToAdd or shareToMint may be non-zero.
     *
     * @param   liquidityPool     The address of the liquidity pool
     * @param   cashToAdd         The amount of cash to add, always use decimals 18.
     * @param   shareToMint       The amount of share token to mint, always use decimals 18.
     * @return  isSynced          True if the funding state is synced to real-time data. False if
     *                            error happens (oracle error, zero price etc.). In this case,
     *                            trading, withdraw (if position != 0), addLiquidity, removeLiquidity
     *                            will fail
     * @return  cashToAddResult   The amount of cash to add, always use decimals 18. Equal to cashToAdd if cashToAdd is non-zero.
     * @return  shareToMintResult The amount of cash to add, always use decimals 18. Equal to shareToMint if shareToMint is non-zero.
     */
    function queryAddLiquidity(
        address liquidityPool,
        int256 cashToAdd,
        int256 shareToMint
    )
        public
        returns (
            bool isSynced,
            int256 cashToAddResult,
            int256 shareToMintResult
        )
    {
        try ILiquidityPool(liquidityPool).forceToSyncState() {
            isSynced = true;
        } catch {
            isSynced = false;
        }
        (cashToAddResult, shareToMintResult) = ILiquidityPool(liquidityPool).queryAddLiquidity(
            cashToAdd,
            shareToMint
        );
    }

    /**
     * @notice  Query cash to return / share to redeem when removing liquidity from the liquidity pool.
     *          Only one of shareToRemove or cashToReturn may be non-zero.
     *
     * @param   liquidityPool       The address of the liquidity pool
     * @param   cashToReturn        The amount of cash to return, always use decimals 18.
     * @param   shareToRemove       The amount of share token to redeem, always use decimals 18.
     * @return  isSynced            True if the funding state is synced to real-time data. False if
     *                              error happens (oracle error, zero price etc.). In this case,
     *                              trading, withdraw (if position != 0), addLiquidity, removeLiquidity
     *                              will fail
     * @return  shareToRemoveResult The amount of share token to redeem, always use decimals 18. Equal to shareToRemove if shareToRemove is non-zero.
     * @return  cashToReturnResult  The amount of cash to return, always use decimals 18. Equal to cashToReturn if cashToReturn is non-zero.
     */
    function queryRemoveLiquidity(
        address liquidityPool,
        int256 shareToRemove,
        int256 cashToReturn
    )
        public
        returns (
            bool isSynced,
            int256 shareToRemoveResult,
            int256 cashToReturnResult
        )
    {
        try ILiquidityPool(liquidityPool).forceToSyncState() {
            isSynced = true;
        } catch {
            isSynced = false;
        }
        (shareToRemoveResult, cashToReturnResult) = ILiquidityPool(liquidityPool)
            .queryRemoveLiquidity(shareToRemove, cashToReturn);
    }
}

////////////////////////////////////////////////////////////////////////////////////
// back-compatible: beta0.0.4

interface ILiquidityPool004 {
    function getLiquidityPoolInfo()
        external
        view
        returns (
            bool isRunning,
            bool isFastCreationEnabled,
            address[7] memory addresses,
            int256 vaultFeeRate,
            int256 poolCash,
            uint256[4] memory nums
        );

    function getPerpetualInfo(uint256 perpetualIndex)
        external
        view
        returns (
            PerpetualState state,
            address oracle,
            int256[34] memory nums
        );

    function getPoolMargin() external view returns (int256 poolMargin);
}
