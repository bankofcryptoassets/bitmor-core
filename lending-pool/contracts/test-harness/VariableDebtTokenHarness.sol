// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.6.12;

import {WadRayMath} from "../protocol/libraries/math/WadRayMath.sol";

/// @dev Harness that exposes the pure scaling math used in VariableDebtToken mint/burn/balanceOf.
/// Identical to AToken scaling but named separately for clarity.
contract VariableDebtTokenHarness {
    using WadRayMath for uint256;

    /// @dev Mirrors VariableDebtToken.mint: amountScaled = amount.rayDiv(index)
    function scaledAmount(uint256 amount, uint256 index) external pure returns (uint256) {
        return amount.rayDiv(index);
    }

    /// @dev Mirrors VariableDebtToken.balanceOf: balance = scaledBalance.rayMul(normalizedDebt)
    function scaledBalance(uint256 scaledBal, uint256 normalizedDebt) external pure returns (uint256) {
        return scaledBal.rayMul(normalizedDebt);
    }

    /// @dev Round-trip: mint amount at mintIndex, then query balance at queryIndex.
    function mintThenBalance(uint256 amount, uint256 mintIndex, uint256 queryIndex) external pure returns (uint256) {
        uint256 scaled = amount.rayDiv(mintIndex);
        return scaled.rayMul(queryIndex);
    }

    /// @dev Tests that minting and burning round-trip correctly (same index).
    function mintBurnRoundTrip(uint256 amount, uint256 index) external pure returns (uint256 diff) {
        uint256 scaled = amount.rayDiv(index);
        uint256 recovered = scaled.rayMul(index);
        diff = amount > recovered ? amount - recovered : recovered - amount;
    }

    function RAY() external pure returns (uint256) {
        return WadRayMath.ray();
    }
}
