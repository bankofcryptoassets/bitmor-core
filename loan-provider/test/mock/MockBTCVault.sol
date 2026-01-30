// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ERC4626} from "@solady/tokens/ERC4626.sol";

/// @title MockBTCVault
/// @notice Simplified ERC-4626 vault for testing - wraps cbBTC → bvBTC shares
/// @dev No strategies, no fees, 1:1 share ratio for testing simplicity
contract MockBTCVault is ERC4626 {
    address private immutable _underlying;
    string private _name;
    string private _symbol;
    uint8 private immutable _decimals;

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

    /// @notice Test helper - mint shares directly without deposit
    function mint(address to, uint256 shares) external {
        _mint(to, shares);
    }

    /// @notice Test helper - burn shares directly
    function burn(address from, uint256 shares) external {
        _burn(from, shares);
    }
}
