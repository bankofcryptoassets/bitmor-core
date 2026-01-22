// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/// @title DeploymentConstants
/// @notice Shared constants for deployment scripts
/// @dev Centralizes magic values to avoid duplication and improve maintainability
library DeploymentConstants {
    // ============ Oracle Prices ============
    /// @notice BTC price in USD with 8 decimals ($100,000)
    int256 public constant BTC_USD_PRICE = 100_000e8;

    /// @notice USDC price in USD with 8 decimals ($1.00)
    int256 public constant USDC_USD_PRICE = 1e8;

    /// @notice Oracle price decimals (Chainlink standard)
    uint8 public constant ORACLE_DECIMALS = 8;

    // ============ Token Decimals ============
    /// @notice USDC decimals
    uint8 public constant USDC_DECIMALS = 6;

    /// @notice cbBTC decimals
    uint8 public constant CBBTC_DECIMALS = 8;

    // ============ Oracle Descriptions ============
    /// @notice BTC/USD oracle description
    string public constant BTC_USD_DESCRIPTION = "BTC/USD";

    /// @notice USDC/USD oracle description
    string public constant USDC_USD_DESCRIPTION = "USDC/USD";

    // ============ Time Delays ============
    /// @notice Execution delay for scheduled operations (1 day)
    uint256 public constant EXECUTION_DELAY = 1 days;

    /// @notice Buffer added to schedule `when` to account for block.timestamp drift
    /// @dev Foundry computes `when` during simulation but block.timestamp advances during broadcast
    uint256 public constant SCHEDULE_BUFFER = 10 minutes;

    /// @notice Buffer added to execution delay for safety (1 second)
    uint256 public constant EXECUTION_BUFFER = 1;

    /// @notice Total time to advance for execute phase (delay + buffer + schedule buffer)
    uint256 public constant TIME_ADVANCE_SECONDS = EXECUTION_DELAY + SCHEDULE_BUFFER + EXECUTION_BUFFER;

    // ============ Chain IDs ============
    /// @notice Local Anvil chain ID
    uint256 public constant LOCAL_CHAIN_ID = 31337;

    /// @notice Base Sepolia chain ID
    uint256 public constant BASE_SEPOLIA_CHAIN_ID = 84532;

    /// @notice Base mainnet chain ID
    uint256 public constant BASE_MAINNET_CHAIN_ID = 8453;
}
