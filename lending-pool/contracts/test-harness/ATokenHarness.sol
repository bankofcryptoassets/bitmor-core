// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.6.12;

import {WadRayMath} from "../protocol/libraries/math/WadRayMath.sol";

/// @dev Harness that exposes the pure scaling math used in AToken mint/burn/balanceOf.
/// This avoids needing a full LendingPool mock — we only test the math layer.
contract ATokenHarness {
    using WadRayMath for uint256;

    /// @dev Mirrors AToken.mint: amountScaled = amount.rayDiv(index)
    function scaledAmount(uint256 amount, uint256 index) external pure returns (uint256) {
        return amount.rayDiv(index);
    }

    /// @dev Mirrors AToken.balanceOf: balance = scaledBalance.rayMul(index)
    function scaledBalance(uint256 scaledBal, uint256 index) external pure returns (uint256) {
        return scaledBal.rayMul(index);
    }

    /// @dev Round-trip: mint then query balance. Returns the balance for the given amount and index.
    function mintThenBalance(uint256 amount, uint256 mintIndex, uint256 queryIndex) external pure returns (uint256) {
        uint256 scaled = amount.rayDiv(mintIndex);
        return scaled.rayMul(queryIndex);
    }

    /// @dev Tests that minting and burning round-trip correctly.
    /// Returns the difference between original amount and recovered amount.
    function mintBurnRoundTrip(uint256 amount, uint256 index) external pure returns (uint256 diff) {
        uint256 scaled = amount.rayDiv(index);
        uint256 recovered = scaled.rayMul(index);
        diff = amount > recovered ? amount - recovered : recovered - amount;
    }

    function RAY() external pure returns (uint256) {
        return WadRayMath.ray();
    }
}
