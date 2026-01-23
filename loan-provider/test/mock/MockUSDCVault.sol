// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ERC4626} from "@solady/tokens/ERC4626.sol";

/// @title MockUSDCVault
/// @notice Minimal ERC-4626 vault for USDC interest rate strategy testing
contract MockUSDCVault is ERC4626 {
    address private immutable _underlying;
    string private _name;
    string private _symbol;
    uint8 private immutable _decimals;

    uint256 private _mockTotalAssets;

    constructor(address underlying_, string memory name_, string memory symbol_, uint8 decimals_) {
        _underlying = underlying_;
        _name = name_;
        _symbol = symbol_;
        _decimals = decimals_;
    }

    function name() public view override returns (string memory) {
        return _name;
    }

    function symbol() public view override returns (string memory) {
        return _symbol;
    }

    function asset() public view override returns (address) {
        return _underlying;
    }

    function _underlyingDecimals() internal view override returns (uint8) {
        return _decimals;
    }

    /// @notice Override to allow manual control for testing
    function totalAssets() public view override returns (uint256) {
        return _mockTotalAssets > 0 ? _mockTotalAssets : super.totalAssets();
    }

    /// @notice Test helper - set mock total assets for interest rate testing
    function setMockTotalAssets(uint256 amount) external {
        _mockTotalAssets = amount;
    }

    /// @notice Test helper - mint shares directly
    function mint(address to, uint256 shares) external {
        _mint(to, shares);
    }
}
