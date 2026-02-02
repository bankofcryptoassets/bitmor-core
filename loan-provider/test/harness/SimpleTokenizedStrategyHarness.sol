// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {SimpleTokenizedStrategy} from "@btcVault/TokenizedStrategy/SimpleTokenizedStrategy.sol";

/// @title SimpleTokenizedStrategyHarness
/// @notice Test harness to expose internals of abstract SimpleTokenizedStrategy
/// @dev Provides minimal implementation of abstract functions for testing
contract SimpleTokenizedStrategyHarness is SimpleTokenizedStrategy {
    constructor(address yieldSource_, address vault_) SimpleTokenizedStrategy(yieldSource_, vault_) {}

    /// @notice Returns the name of the harness token
    function name() public pure override returns (string memory) {
        return "StrategyHarness";
    }

    /// @notice Returns the symbol of the harness token
    function symbol() public pure override returns (string memory) {
        return "sHRNS";
    }

    /// @notice Expose internal _underlyingDecimals for testing
    function exposed_underlyingDecimals() external view returns (uint8) {
        return _underlyingDecimals();
    }
}
