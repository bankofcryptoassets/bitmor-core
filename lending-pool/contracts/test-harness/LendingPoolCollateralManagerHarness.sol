// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.6.12;

import {SafeMath} from "../dependencies/openzeppelin/contracts/SafeMath.sol";
import {PercentageMath} from "../protocol/libraries/math/PercentageMath.sol";

/// @dev Harness that exposes the pure liquidation math from LendingPoolCollateralManager.
/// Extracts _calculateAvailableCollateralToLiquidate as a pure function.
/// Split into two functions to avoid stack-too-deep in Solidity 0.6.12.
contract LendingPoolCollateralManagerHarness {
    using SafeMath for uint256;
    using PercentageMath for uint256;

    /// @dev Computes maxAmountCollateralToLiquidate (uncapped by user balance).
    /// maxCollateral = debtAssetPrice * debtToCover * 10^collateralDecimals * liquidationBonus
    ///                 / (collateralPrice * 10^debtAssetDecimals)
    function calculateMaxCollateral(
        uint256 collateralPrice,
        uint256 debtAssetPrice,
        uint256 debtToCover,
        uint256 collateralDecimals,
        uint256 debtAssetDecimals,
        uint256 liquidationBonus
    ) public pure returns (uint256) {
        return debtAssetPrice
            .mul(debtToCover)
            .mul(10 ** collateralDecimals)
            .percentMul(liquidationBonus)
            .div(collateralPrice.mul(10 ** debtAssetDecimals));
    }

    /// @dev Computes reverse: given collateral amount, how much debt is needed?
    /// debtNeeded = collateralPrice * collateralAmount * 10^debtDecimals
    ///              / (debtAssetPrice * 10^collateralDecimals) / liquidationBonus
    function calculateDebtFromCollateral(
        uint256 collateralPrice,
        uint256 debtAssetPrice,
        uint256 collateralAmount,
        uint256 collateralDecimals,
        uint256 debtAssetDecimals,
        uint256 liquidationBonus
    ) public pure returns (uint256) {
        return collateralPrice
            .mul(collateralAmount)
            .mul(10 ** debtAssetDecimals)
            .div(debtAssetPrice.mul(10 ** collateralDecimals))
            .percentDiv(liquidationBonus);
    }

    /// @dev Full calculation with user balance cap.
    /// Uses the two functions above.
    function calculateAvailableCollateralToLiquidate(
        uint256 collateralPrice,
        uint256 debtAssetPrice,
        uint256 debtToCover,
        uint256 userCollateralBalance,
        uint256 collateralDecimals,
        uint256 debtAssetDecimals,
        uint256 liquidationBonus
    ) external pure returns (uint256 collateralAmount, uint256 debtAmountNeeded) {
        uint256 maxCol = calculateMaxCollateral(
            collateralPrice, debtAssetPrice, debtToCover,
            collateralDecimals, debtAssetDecimals, liquidationBonus
        );

        if (maxCol > userCollateralBalance) {
            collateralAmount = userCollateralBalance;
            debtAmountNeeded = calculateDebtFromCollateral(
                collateralPrice, debtAssetPrice, collateralAmount,
                collateralDecimals, debtAssetDecimals, liquidationBonus
            );
        } else {
            collateralAmount = maxCol;
            debtAmountNeeded = debtToCover;
        }
    }
}
