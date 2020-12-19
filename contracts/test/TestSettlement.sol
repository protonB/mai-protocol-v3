// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.7.4;
pragma experimental ABIEncoderV2;

import "../module/SettlementModule.sol";
import "../module/PerpetualModule.sol";

import "../Type.sol";
import "../Settlement.sol";
import "./TestMargin.sol";

contract TestSettlement is TestMargin, Settlement {
    using SettlementModule for PerpetualStorage;
    using PerpetualModule for PerpetualStorage;

    function setCollateral(address collateral) public {
        _liquidityPool.collateral = collateral;
        _liquidityPool.scaler = 1;
    }

    function setPoolCollateralAmount(int256 amount) public {
        _liquidityPool.poolCollateralAmount = amount;
    }

    function setPerpetualCollateralAmount(uint256 perpetualIndex, int256 amount) public {
        _liquidityPool.perpetuals[perpetualIndex].collateralAmount = amount;
    }

    function setFee(int256 fee) public {
        _liquidityPool.totalClaimableFee = fee;
    }

    function registerActiveAccount(uint256 perpetualIndex, address trader) public {
        _liquidityPool.perpetuals[perpetualIndex].registerActiveAccount(trader);
    }

    function deregisterActiveAccount(uint256 perpetualIndex, address trader) public {
        _liquidityPool.perpetuals[perpetualIndex].deregisterActiveAccount(trader);
    }

    function setEmergency(uint256 perpetualIndex) public {
        _liquidityPool.perpetuals[perpetualIndex].enterEmergencyState();
    }

    function setClearedState(uint256 perpetualIndex) public {
        _liquidityPool.perpetuals[perpetualIndex].enterClearedState();
    }

    function totalMarginWithoutPosition(uint256 perpetualIndex) public view returns (int256) {
        return _liquidityPool.perpetuals[perpetualIndex].totalMarginWithoutPosition;
    }

    function totalMarginWithPosition(uint256 perpetualIndex) public view returns (int256) {
        return _liquidityPool.perpetuals[perpetualIndex].totalMarginWithPosition;
    }

    function redemptionRateWithoutPosition(uint256 perpetualIndex) public view returns (int256) {
        return _liquidityPool.perpetuals[perpetualIndex].redemptionRateWithoutPosition;
    }

    function redemptionRateWithPosition(uint256 perpetualIndex) public view returns (int256) {
        return _liquidityPool.perpetuals[perpetualIndex].redemptionRateWithPosition;
    }
}
