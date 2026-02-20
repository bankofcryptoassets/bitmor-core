// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.6.12;

import {MathUtils} from "../protocol/libraries/math/MathUtils.sol";

contract MathUtilsHarness {
    function SECONDS_PER_YEAR() external pure returns (uint256) {
        return MathUtils.SECONDS_PER_YEAR;
    }

    function calculateLinearInterest(
        uint256 rate,
        uint40 lastUpdateTimestamp
    ) external view returns (uint256) {
        return MathUtils.calculateLinearInterest(rate, lastUpdateTimestamp);
    }

    function calculateCompoundedInterest(
        uint256 rate,
        uint40 lastUpdateTimestamp,
        uint256 currentTimestamp
    ) external pure returns (uint256) {
        return MathUtils.calculateCompoundedInterest(rate, lastUpdateTimestamp, currentTimestamp);
    }
}
