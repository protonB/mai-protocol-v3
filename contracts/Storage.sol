// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.7.4;

import "@openzeppelin/contracts-upgradeable/GSN/ContextUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/EnumerableSetUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";

import "./interface/IAccessControl.sol";
import "./module/LiquidityPoolModule.sol";
import "./Type.sol";

contract Storage is ContextUpgradeable {
    using SafeMathUpgradeable for uint256;
    using LiquidityPoolModule for LiquidityPoolStorage;

    LiquidityPoolStorage internal _liquidityPool;

    modifier onlyExistedPerpetual(uint256 perpetualIndex) {
        require(perpetualIndex < _liquidityPool.perpetualCount, "perpetual not exist");
        _;
    }

    modifier onlyKeeper() {
        require(
            _liquidityPool.keeper == address(0) || _liquidityPool.keeper == _msgSender(),
            "caller must be keeper"
        );
        _;
    }

    modifier syncState(bool ignoreTerminated) {
        uint256 currentTime = block.timestamp;
        _liquidityPool.updateFundingState(currentTime);
        _liquidityPool.updatePrice(currentTime, ignoreTerminated);
        _;
        _liquidityPool.updateFundingRate();
    }

    modifier onlyAuthorized(address trader, uint256 privilege) {
        require(
            _liquidityPool.isAuthorized(trader, _msgSender(), privilege),
            "unauthorized caller"
        );
        _;
    }

    bytes32[28] private __gap;
}
