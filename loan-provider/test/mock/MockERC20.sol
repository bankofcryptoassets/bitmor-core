// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title MockERC20
/// @author Bitmor Protocol
/// @notice Mock ERC20 token for testing with configurable decimals
/// @dev Allows unrestricted minting for test scenarios
contract MockERC20 is ERC20 {
    uint8 private immutable _decimals;

    /// @notice Creates a new MockERC20 token
    /// @param name_ Token name
    /// @param symbol_ Token symbol
    /// @param decimals_ Number of decimals (e.g., 8 for BTC, 6 for USDC)
    constructor(string memory name_, string memory symbol_, uint8 decimals_) ERC20(name_, symbol_) {
        _decimals = decimals_;
    }

    /// @notice Returns the number of decimals
    /// @return The decimals value set at construction
    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    /// @notice Mints tokens to the specified address
    /// @dev No access control - intended for testing only. Virtual to allow overrides.
    /// @param to Recipient address
    /// @param amount Amount to mint
    function mint(address to, uint256 amount) external virtual {
        _mint(to, amount);
    }

    /// @notice Burns tokens from the specified address
    /// @dev No access control - intended for testing only. Virtual to allow overrides.
    /// @param from Address to burn from
    /// @param amount Amount to burn
    function burn(address from, uint256 amount) external virtual {
        _burn(from, amount);
    }

    /// @notice Mock ERC-4626 deposit function for testing
    /// @dev Returns 1:1 shares without any actual vault logic
    /// @param assets Amount of assets to deposit
    /// @param receiver Address to receive shares
    /// @return shares Amount of shares received (same as assets for 1:1 mock)
    function deposit(uint256 assets, address receiver) external virtual returns (uint256 shares) {
        shares = assets;
        // Just mint shares to receiver (1:1 ratio)
        _mint(receiver, shares);
    }

    /// @notice Mock ERC-4626 withdraw function for testing
    /// @dev Burns shares and returns assets (1:1 ratio)
    /// @param assets Amount of assets to withdraw
    /// @param receiver Address to receive assets
    /// @param owner Address whose shares to burn
    /// @return shares Amount of shares burned
    function withdraw(uint256 assets, address receiver, address owner) external virtual returns (uint256 shares) {
        shares = assets;
        _burn(owner, shares);
        _mint(receiver, assets);
    }

    /// @notice Mock ERC-4626 redeem function for testing
    /// @param shares Amount of shares to redeem
    /// @param receiver Address to receive assets
    /// @param owner Address whose shares to burn
    /// @return assets Amount of assets received
    function redeem(uint256 shares, address receiver, address owner) external virtual returns (uint256 assets) {
        assets = shares;
        _burn(owner, shares);
        _mint(receiver, assets);
    }

    /// @notice Mock ERC-4626 convertToAssets function for testing
    /// @dev Returns 1:1 conversion (shares == assets)
    /// @param shares Amount of shares to convert
    /// @return assets The equivalent amount of assets
    function convertToAssets(uint256 shares) external pure virtual returns (uint256 assets) {
        return shares;
    }

    /// @notice Mock ERC-4626 convertToShares function for testing
    /// @dev Returns 1:1 conversion (assets == shares)
    /// @param assets Amount of assets to convert
    /// @return shares The equivalent amount of shares
    function convertToShares(uint256 assets) external pure virtual returns (uint256 shares) {
        return assets;
    }
}
