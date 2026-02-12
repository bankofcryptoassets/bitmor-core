// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.6.12;

import {PercentageMath} from "../protocol/libraries/math/PercentageMath.sol";

/// @dev Harness that exposes the collateral configuration validation logic
/// from LendingPoolConfigurator.configureReserveAsCollateral().
contract LendingPoolConfiguratorHarness {
    using PercentageMath for uint256;

    /// @dev Validates collateral configuration parameters.
    /// Mirrors the require checks from configureReserveAsCollateral:
    ///   1. ltv <= liquidationThreshold
    ///   2. If threshold != 0: liquidationBonus > 10000
    ///   3. If threshold != 0: threshold * bonus <= 10000 (percentMul)
    ///   4. If threshold == 0: liquidationBonus == 0
    /// Returns true if all checks pass, reverts otherwise.
    function validateCollateralConfig(
        uint256 ltv,
        uint256 liquidationThreshold,
        uint256 liquidationBonus
    ) external pure returns (bool) {
        require(ltv <= liquidationThreshold, "LTV_GT_THRESHOLD");

        if (liquidationThreshold != 0) {
            require(
                liquidationBonus > PercentageMath.PERCENTAGE_FACTOR,
                "BONUS_NOT_GT_100"
            );
            require(
                liquidationThreshold.percentMul(liquidationBonus) <= PercentageMath.PERCENTAGE_FACTOR,
                "THRESHOLD_TIMES_BONUS_GT_100"
            );
        } else {
            require(liquidationBonus == 0, "BONUS_NOT_ZERO");
        }

        return true;
    }

    function PERCENTAGE_FACTOR() external pure returns (uint256) {
        return PercentageMath.PERCENTAGE_FACTOR;
    }
}
