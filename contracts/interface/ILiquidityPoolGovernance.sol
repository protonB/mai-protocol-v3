// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.7.4;

interface ILiquidityPoolGovernance {
    function setPerpetualParameter(bytes32 key, int256 newValue) external;

    function setPerpetualRiskParameter(
        bytes32 key,
        int256 newValue,
        int256 minValue,
        int256 maxValue
    ) external;

    function updatePerpetualRiskParameter(bytes32 key, int256 newValue) external;
}
