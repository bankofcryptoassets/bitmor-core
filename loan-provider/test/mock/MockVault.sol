// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/// @title MockVault
/// @notice Minimal vault mock that returns asset address
/// @dev Used for SimpleTokenizedStrategy constructor which queries vault.asset()
contract MockVault {
    address private immutable _asset;

    constructor(address asset_) {
        _asset = asset_;
    }

    function asset() external view returns (address) {
        return _asset;
    }
}
