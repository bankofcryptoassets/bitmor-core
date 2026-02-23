// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/// @title TestConstants
/// @author Bitmor Protocol
/// @notice Centralized test-specific constants eliminating magic values across all test files
/// @dev Protocol configuration belongs in HelperConfig.s.sol. Import as `TestConstants as TC`.
library TestConstants {
    // ============ Test Funding Amounts ============
    uint256 internal constant USER_USDC_BALANCE = 1_000_000e6; // 1M USDC
    uint256 internal constant USER_CBBTC_BALANCE = 10e8; // 10 BTC
    uint256 internal constant POOL_USDC_LIQUIDITY = 10_000_000e6; // 10M USDC
    uint256 internal constant POOL_CBBTC_LIQUIDITY = 100e8; // 100 BTC

    // ============ Standard Test Scenarios ============
    uint256 internal constant STANDARD_COLLATERAL = 1e8; // 1 BTC
    uint256 internal constant MIN_COLLATERAL = 0.01e8; // 0.01 BTC
    uint256 internal constant MAX_COLLATERAL = 10e8; // 10 BTC
    uint256 internal constant STANDARD_DURATION = 12; // 12 months
    uint256 internal constant MIN_DURATION = 1; // 1 month
    uint256 internal constant MAX_DURATION = 60; // 60 months (5 years)
    uint256 internal constant PREMIUM_AMOUNT = 1000e6; // 1000 USDC
    uint256 internal constant OVERPAY_AMOUNT = 500e6; // 500 USDC

    // ============ Liquidation Test Parameters ============
    uint256 internal constant PRICE_DROP_MICRO = 15; // 15%
    uint256 internal constant PRICE_DROP_30 = 30; // 30%
    uint256 internal constant PRICE_DROP_40 = 40; // 40%
    uint256 internal constant PRICE_DROP_FULL = 50; // 50%
    uint256 internal constant PRICE_DROP_70 = 70; // 70%

    // ============ Liquidation Type Constants ============
    uint256 internal constant LIQUIDATION_TYPE_NONE = 0;
    uint256 internal constant LIQUIDATION_TYPE_FULL = 1;
    uint256 internal constant LIQUIDATION_TYPE_MICRO = 2;

    // ============ Liquidation Fee ============
    uint256 internal constant MAX_LIQUIDATION_FEE_BPS = 20_00;
    uint256 internal constant DEFAULT_LIQUIDATION_FEE_BPS = 500;

    // ============ Basis Point Scale ============
    uint256 internal constant BASIS_POINT_SCALE = 100_00;

    // ============ Grace Period ============
    uint256 internal constant MAX_GRACE_PERIOD = 45 days;

    // ============ Insurance Constants ============
    uint256 internal constant DEFAULT_INSURANCE_ID = 1;
    uint256 internal constant INSURANCE_BONUS_BPS = 300; // 3% bonus

    // ============ Mock Infrastructure Balances ============
    uint256 internal constant SWAP_ADAPTER_CBBTC_BALANCE = 1000e8; // 1000 BTC for swaps
    uint256 internal constant SWAP_ADAPTER_USDC_BALANCE = 100_000_000e6; // 100M USDC for swaps
    uint256 internal constant LENDING_POOL_CBBTC_BALANCE = 1000e8; // 1000 BTC for pool
    uint256 internal constant LENDING_POOL_USDC_BALANCE = 100_000_000e6; // 100M USDC for pool

    // ============ Vault Configuration ============
    uint256 internal constant BTC_VAULT_INITIAL_BALANCE = 1000e8; // 1000 cbBTC for vault
    uint256 internal constant USDC_VAULT_INITIAL_LIQUIDITY = 100_000_000e6; // 100M USDC

    // ============ LendingPool Test Constants ============
    uint256 internal constant BTC_SEED_AMOUNT = 10e8; // 10 BTC
    uint256 internal constant POOL_DEPOSIT_AMOUNT = 100_000e6; // 100k USDC
    uint256 internal constant SMALL_BORROW_AMOUNT = 10_000e6; // 10k USDC
    uint256 internal constant MAX_APR_BPS = 1200; // 12% APR max
    uint256 internal constant PAYMENT_TOLERANCE = 100e6; // 100 USDC tolerance
    uint256 internal constant DEBT_DUST_THRESHOLD = 1e6; // 1 USDC dust

    // ============ Time Helpers ============
    uint256 internal constant ONE_DAY = 1 days;
    uint256 internal constant ONE_MONTH = 30 days;
    uint256 internal constant ONE_YEAR = 365 days;
    uint256 internal constant REPAYMENT_INTERVAL = 30 days;

    // ============ Precision Constants ============
    uint256 internal constant RAY = 1e27;
    uint256 internal constant BPS_DENOMINATOR = 10_000;
    uint256 internal constant PRECISION = 1e18;

    uint256 internal constant SLIPPAGE_SWAP = 50; // 50bps
    uint256 internal constant SLIPPAGE_SHARES_TO_ASSET = 100; // 100bps
    uint256 internal constant MIN_DEPOSIT = 30_00; // 30%

    uint256 internal constant PRICE_PRECISION = 1e8;

    // ============ Flash Loan Test Parameters ============
    uint256 internal constant FLASH_LOAN_AMOUNT = 1000e6; // 1000 USDC flash loan for callback tests
    uint256 internal constant FLASH_LOAN_PREMIUM = 10e6; // 10 USDC premium (1%)
    uint256 internal constant TEST_BTC_SWAP_AMOUNT = 1e8; // 1 BTC for swap params
    uint256 internal constant TEST_PRECLOSURE_FEE = 0.01e8; // 0.01 BTC pre-closure fee

    // ============ Repayment Test Parameters ============
    uint256 internal constant TEST_REPAYMENT_SHORTFALL = 100e6; // 100 USDC shortfall for refund tests

    // ============ Integration Test Tolerances ============
    uint256 internal constant SHARE_PRICE_IMPACT_TOLERANCE = 0.01e18; // 1%
    uint256 internal constant MAX_ROUNDING_LOSS_USDC = 1e6; // 1 USDC
    uint256 internal constant MAX_ROUNDING_LOSS_SATOSHI = 100; // 100 sats

    // ============ Extended Time Helpers ============
    uint256 internal constant THREE_MONTHS = 90 days;
    uint256 internal constant SIX_MONTHS = 180 days;

    // ============ Integration Test Shared Constants ============
    uint256 internal constant SIMULATED_YIELD_BPS = 500; // 5% yield simulation
    uint256 internal constant DONATION_AMOUNT_USDC = 10_000_000e6; // 10M USDC donation
    uint256 internal constant DONATION_AMOUNT_CBBTC = 10e8; // 10 BTC donation
    uint256 internal constant EXIT_FEE_LOW_BPS = 10; // 0.1% exit fee
    uint256 internal constant EXIT_FEE_MEDIUM_BPS = 100; // 1% exit fee
    uint256 internal constant EXIT_FEE_HIGH_BPS = 500; // 5% exit fee
    uint256 internal constant DUST_TOLERANCE_USDC = 100; // 100 units USDC dust
    uint256 internal constant DUST_TOLERANCE_BTC = 10; // 10 sats dust

    // ============ Oracle Staleness Parameters ============
    uint256 internal constant DEFAULT_MAX_ORACLE_STALENESS = 3600; // 1 hour
    uint256 internal constant STALE_PRICE_AGE = 7200; // 2 hours
}
