// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.7.4;

import "./IProxyAdmin.sol";

interface IPoolCreator {
    function activatePerpetualFor(address trader, uint256 perpetualIndex) external;

    function deactivatePerpetualFor(address trader, uint256 perpetualIndex) external;

    function registerOperatorOfLiquidityPool(address liquidityPool, address operator) external;

    function getVault() external view returns (address);

    function getVaultFeeRate() external view returns (int256);

    function getWeth() external view returns (address);

    function getAccessController() external view returns (address);

    function getSymbolService() external view returns (address);

    function getLatestVersion() external view returns (bytes32 latestVersionKey);

    function getVersion(bytes32 versionKey)
        external
        view
        returns (
            address liquidityPoolTemplate,
            address governorTemplate,
            uint256 compatibility
        );

    function getAppliedVersionKey(address liquidityPool, address governor)
        external
        view
        returns (bytes32 appliedVersionKey);

    function isVersionKeyValid(bytes32 versionKey) external view returns (bool isValid);

    function isVersionCompatible(bytes32 targetVersionKey, bytes32 baseVersionKey)
        external
        view
        returns (bool isCompatible);

    function upgradeAdmin() external view returns (IProxyAdmin proxyAdmin);
}
