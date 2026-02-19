// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.6.12;

import {WadRayMath} from "../protocol/libraries/math/WadRayMath.sol";

contract WadRayMathHarness {
    using WadRayMath for uint256;

    function RAY() external pure returns (uint256) {
        return WadRayMath.RAY;
    }

    function WAD() external pure returns (uint256) {
        return WadRayMath.WAD;
    }

    function WAD_RAY_RATIO() external pure returns (uint256) {
        return WadRayMath.WAD_RAY_RATIO;
    }

    function rayMul(uint256 a, uint256 b) external pure returns (uint256) {
        return a.rayMul(b);
    }

    function rayDiv(uint256 a, uint256 b) external pure returns (uint256) {
        return a.rayDiv(b);
    }

    function wadDiv(uint256 a, uint256 b) external pure returns (uint256) {
        return a.wadDiv(b);
    }

    function wadToRay(uint256 a) external pure returns (uint256) {
        return a.wadToRay();
    }
}
