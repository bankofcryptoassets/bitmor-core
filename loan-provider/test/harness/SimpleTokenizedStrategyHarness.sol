// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {SimpleTokenizedStrategy} from "@btcVault/TokenizedStrategy/SimpleTokenizedStrategy.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

/// @title SimpleTokenizedStrategyHarness
/// @author Bitmor Protocol
/// @notice Test harness exposing internal functions of the abstract `SimpleTokenizedStrategy`
/// @dev Provides minimal concrete implementations for `name()` and `symbol()` so the abstract
///      contract can be instantiated, then exposes internal helpers for direct unit testing.
/// @custom:security FOR TESTING ONLY - Never deploy to production.
contract SimpleTokenizedStrategyHarness is SimpleTokenizedStrategy {
    /// @notice Initializes the harness with required strategy dependencies
    /// @param yieldSource_ The yield source address (e.g., Aave pool)
    /// @param vault_ The vault address this strategy serves
    constructor(address yieldSource_, address vault_) SimpleTokenizedStrategy(yieldSource_, vault_) {}

    /// @notice Returns the name of the harness token
    function name() public pure override(ERC20, IERC20Metadata) returns (string memory) {
        return "StrategyHarness";
    }

    /// @notice Returns the symbol of the harness token
    function symbol() public pure override(ERC20, IERC20Metadata) returns (string memory) {
        return "sHRNS";
    }

    /// @notice Returns the underlying asset's decimals for testing
    /// @dev After migrating from Solady to OZ ERC4626, decimals are exposed via `decimals()`.
    /// @return The number of decimals used by the underlying asset
    function exposed_underlyingDecimals() external view returns (uint8) {
        return decimals();
    }
}
