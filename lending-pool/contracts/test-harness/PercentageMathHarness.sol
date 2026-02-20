// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.6.12;

import {PercentageMath} from "../protocol/libraries/math/PercentageMath.sol";

contract PercentageMathHarness {
    using PercentageMath for uint256;

    function PERCENTAGE_FACTOR() external pure returns (uint256) {
        return PercentageMath.PERCENTAGE_FACTOR;
    }

    function HALF_PERCENT() external pure returns (uint256) {
        return PercentageMath.HALF_PERCENT;
    }

    function percentMul(uint256 value, uint256 percentage) external pure returns (uint256) {
        return value.percentMul(percentage);
    }

    function percentDiv(uint256 value, uint256 percentage) external pure returns (uint256) {
        return value.percentDiv(percentage);
    }
}
