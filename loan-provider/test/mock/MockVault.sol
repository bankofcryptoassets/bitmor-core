// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/// @title MockVault
/// @author Bitmor Protocol
/// @notice Minimal vault mock that returns an asset address
/// @dev Used for SimpleTokenizedStrategy constructor which queries `vault.asset()`
contract MockVault {
    /// @dev The underlying asset address returned by `asset()`
    address private immutable _asset;

    /// @notice Creates a new MockVault
    /// @param asset_ The underlying asset address to return from `asset()`
    constructor(address asset_) {
        _asset = asset_;
    }

    /// @notice Returns the underlying asset address
    /// @return The asset address set at construction
    function asset() external view returns (address) {
        return _asset;
    }
}
