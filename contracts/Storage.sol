// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.7.4;

import "@openzeppelin/contracts-upgradeable/GSN/ContextUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/EnumerableSetUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";

import "./interface/IAccessControll.sol";

import "./module/LiquidityPoolModule.sol";

import "./Type.sol";

contract Storage is ContextUpgradeable {
    using SafeMathUpgradeable for uint256;
    using LiquidityPoolModule for LiquidityPoolStorage;

    LiquidityPoolStorage internal _liquidityPool;
    // TODO: to be remove
    address internal __dummy1;
    address internal __dummy2;

    modifier onlyNotPaused(uint256 perpetualIndex) {
        require(
            !IOracle(_liquidityPool.perpetuals[perpetualIndex].oracle).isMarketClosed(),
            "market is closed now"
        );
        _;
    }

    modifier onlyExistedPerpetual(uint256 perpetualIndex) {
        require(perpetualIndex < _liquidityPool.perpetuals.length, "perpetual not exist");
        _;
    }

    modifier syncState() {
        uint256 currentTime = block.timestamp;
        _liquidityPool.updateFundingState(currentTime);
        _liquidityPool.updatePrice(currentTime);
        _;
        _liquidityPool.updateFundingRate();
    }

    modifier onlyWhen(uint256 perpetualIndex, PerpetualState allowedState) {
        require(
            _liquidityPool.perpetuals[perpetualIndex].state == allowedState,
            "operation is disallowed now"
        );
        _;
    }

    modifier onlyNotWhen(uint256 perpetualIndex, PerpetualState disallowedState) {
        require(
            _liquidityPool.perpetuals[perpetualIndex].state != disallowedState,
            "operation is disallow now"
        );
        _;
    }

    modifier onlyAuthorized(address trader, uint256 privilege) {
        require(
            trader == msg.sender ||
                IAccessControll(_liquidityPool.accessController).isGranted(
                    trader,
                    msg.sender,
                    privilege
                ),
            "unauthorized operation"
        );
        _;
    }

    // TODO: bytes => bytes32
    bytes[50] private __gap;
}
