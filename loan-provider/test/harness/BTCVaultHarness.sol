// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {BTCVault} from "@btcVault/BTCVault.sol";

/// @title BTCVaultHarness
/// @notice Test harness for BTCVault contract that exposes internal functions for testing
/// @dev Extends BTCVault to make internal functions public for unit testing purposes.
///      Uses the same UUPS upgradeable pattern as BTCVault (initialize instead of constructor).
/// @author Bitmor Protocol
contract BTCVaultHarness is BTCVault {
    /// @notice Exposes the internal _feeOnRaw function for testing fee calculations
    /// @param assets The base amount of assets (without fees)
    /// @param feeBasisPoints The fee rate in basis points
    /// @return The calculated fee amount that should be added to assets
    function feeOnRaw(uint256 assets, uint256 feeBasisPoints) external pure returns (uint256) {
        return _feeOnRaw(assets, feeBasisPoints);
    }

    /// @notice Exposes the internal _feeOnTotal function for testing fee calculations
    /// @param assets The total amount of assets (including fees)
    /// @param feeOnBasisPoints The fee rate in basis points
    /// @return The calculated fee portion of the total assets
    function feeOnTotal(uint256 assets, uint256 feeOnBasisPoints) external pure returns (uint256) {
        return _feeOnTotal(assets, feeOnBasisPoints);
    }
}
