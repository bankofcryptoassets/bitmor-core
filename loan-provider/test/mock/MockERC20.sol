// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.30;

import {ERC20} from "@openzeppelin/token/ERC20/ERC20.sol";

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
    /// @dev No access control - intended for testing only
    /// @param to Recipient address
    /// @param amount Amount to mint
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    /// @notice Burns tokens from the specified address
    /// @dev No access control - intended for testing only
    /// @param from Address to burn from
    /// @param amount Amount to burn
    function burn(address from, uint256 amount) external {
        _burn(from, amount);
    }
}
