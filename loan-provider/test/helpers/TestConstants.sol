// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/// @title TestConstants
/// @notice Centralized test-specific magic values (not protocol configuration)
/// @dev Protocol configuration belongs in HelperConfig.s.sol
library TestConstants {
    // ============ Test Funding Amounts ============
    uint256 internal constant USER_USDC_BALANCE = 1_000_000e6;      // 1M USDC
    uint256 internal constant USER_CBBTC_BALANCE = 10e8;            // 10 BTC
    uint256 internal constant POOL_USDC_LIQUIDITY = 10_000_000e6;   // 10M USDC
    uint256 internal constant POOL_CBBTC_LIQUIDITY = 100e8;         // 100 BTC

    // ============ Standard Test Scenarios ============
    uint256 internal constant STANDARD_COLLATERAL = 1e8;            // 1 BTC
    uint256 internal constant MIN_COLLATERAL = 0.01e8;              // 0.01 BTC
    uint256 internal constant MAX_COLLATERAL = 10e8;                // 10 BTC
    uint256 internal constant STANDARD_DURATION = 12;               // 12 months
    uint256 internal constant MIN_DURATION = 1;                     // 1 month
    uint256 internal constant MAX_DURATION = 12;                    // 12 months
    uint256 internal constant PREMIUM_AMOUNT = 1000e6;              // 1000 USDC
    uint256 internal constant OVERPAY_AMOUNT = 500e6;               // 500 USDC

    // ============ Liquidation Test Parameters ============
    uint256 internal constant PRICE_DROP_MICRO = 15;                // 15%
    uint256 internal constant PRICE_DROP_FULL = 50;                 // 50%

    // ============ Time Helpers ============
    uint256 internal constant ONE_DAY = 1 days;
    uint256 internal constant ONE_MONTH = 30 days;
    uint256 internal constant ONE_YEAR = 365 days;

    // ============ Precision Constants ============
    uint256 internal constant RAY = 1e27;
    uint256 internal constant BPS_DENOMINATOR = 10_000;
    uint256 internal constant PRECISION = 1e18;
}
