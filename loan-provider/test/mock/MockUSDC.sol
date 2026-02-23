// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ERC20} from "@solady/tokens/ERC20.sol";

/// @title MockUSDC
/// @author Bitmor Protocol
/// @notice Mock USDC token using Solady ERC20 for deployment script testing
/// @dev Mints 1 billion USDC to the deployer on construction. Uses Solady ERC20 (not OZ).
///      For unit tests, prefer MockERC20 which has configurable decimals and name.
contract MockUSDC is ERC20 {
    /// @notice Creates a new MockUSDC and mints 1 billion tokens to the deployer
    constructor() {
        _mint(msg.sender, 1_000_000_000e6);
    }

    /// @notice Returns the token name
    function name() public pure override returns (string memory) {
        return "mUSDC";
    }

    /// @notice Returns the token symbol
    function symbol() public pure override returns (string memory) {
        return "mUSDC";
    }

    /// @notice Returns the number of decimals (6, matching real USDC)
    function decimals() public pure override returns (uint8) {
        return 6;
    }

    /// @notice Mints `amount` tokens to `to` (unrestricted, for testing only)
    /// @param to Recipient address
    /// @param amount Amount to mint
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
