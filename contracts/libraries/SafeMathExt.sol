// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.7.4;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/math/SignedSafeMath.sol";

import "./Constant.sol";

library SafeMathExt {

    using SafeMath for uint256;
    using SignedSafeMath for int256;

    function wmul(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = x.mul(y).add(Constant.UNSIGNED_ONE / 2) / Constant.UNSIGNED_ONE;
    }

    function wdiv(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = x.mul(Constant.UNSIGNED_ONE).add(y / 2).div(y);
    }

    function wfrac(uint256 x, uint256 y, uint256 z) internal pure returns (uint256 r) {
        r = x.mul(y).div(z);
    }

    function wmul(int256 x, int256 y) internal pure returns (int256 z) {
        z = roundHalfUp(x.mul(y), Constant.SIGNED_ONE) / Constant.SIGNED_ONE;
    }

    function wdiv(int256 x, int256 y) internal pure returns (int256 z) {
        if (y < 0) {
            y = neg(y);
            x = neg(x);
        }
        z = roundHalfUp(x.mul(Constant.SIGNED_ONE), y).div(y);
    }

    function wfrac(int256 x, int256 y, int256 z) internal pure returns (int256 r) {
        int256 t = x.mul(y);
        if (z < 0) {
            z = neg(z);
            t = neg(t);
        }
        r = roundHalfUp(t, z).div(z);
    }

    function abs(int256 x) internal pure returns (int256) {
        return x >= 0? x: neg(x);
    }

    function neg(int256 a) internal pure returns (int256) {
        return SignedSafeMath.sub(int256(0), a);
    }

    /// @dev ROUND_HALF_UP rule helper.
    ///      You have to call roundHalfUp(x, y) / y to finish the rounding operation
    ///      0.5 ≈ 1, 0.4 ≈ 0, -0.5 ≈ -1, -0.4 ≈ 0
    function roundHalfUp(int256 x, int256 y) internal pure returns (int256) {
        require(y > 0, "roundHalfUp only supports y > 0");
        if (x >= 0) {
            return x.add(y / 2);
        }
        return x.sub(y / 2);
    }

    function max(int256 a, int256 b) internal pure returns (int256) {
        return a >= b ? a : b;
    }

    function min(int256 a, int256 b) internal pure returns (int256) {
        return a < b ? a : b;
    }

}