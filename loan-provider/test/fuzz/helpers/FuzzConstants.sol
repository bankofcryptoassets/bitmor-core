// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/**
 * @title FuzzConstants
 * @author Bitmor Protocol
 * @notice Constants and bounds for fuzz testing
 * @dev Import as FC: `import {FuzzConstants as FC} from "./FuzzConstants.sol";`
 */
library FuzzConstants {
    // ============ Price Bounds (8 decimals) ============

    /// @dev Minimum BTC price: $1,000
    uint256 constant MIN_BTC_PRICE = 1000e8;

    /// @dev Maximum BTC price: $1,000,000
    uint256 constant MAX_BTC_PRICE = 1_000_000e8;

    /// @dev USDC price (stable): $1
    uint256 constant USDC_PRICE = 1e8;

    // ============ Interest Rate Bounds (RAY - 27 decimals) ============

    /// @dev Minimum interest rate: 0%
    uint256 constant MIN_INTEREST_RATE = 0;

    /// @dev Maximum interest rate: 12% APR
    uint256 constant MAX_INTEREST_RATE = 0.12e27;

    // ============ Duration Bounds ============

    /// @dev Minimum loan duration: 1 month
    uint256 constant MIN_DURATION = 1;

    /// @dev Maximum loan duration: 60 months
    uint256 constant MAX_DURATION = 60;

    // ============ BTC Amount Bounds (8 decimals) ============

    /// @dev Minimum BTC amount: 0.01 BTC
    uint256 constant MIN_BTC_AMOUNT = 0.01e8;

    /// @dev Maximum BTC amount: 100 BTC
    uint256 constant MAX_BTC_AMOUNT = 100e8;

    // ============ USDC Amount Bounds (6 decimals) ============

    /// @dev Minimum USDC amount: 1 USDC
    uint256 constant MIN_USDC_AMOUNT = 1e6;

    /// @dev Maximum USDC amount: 10M USDC
    uint256 constant MAX_USDC_AMOUNT = 10_000_000e6;

    // ============ Premium Bounds (6 decimals) ============

    /// @dev Maximum premium for fuzz testing: 100k USDC
    uint256 constant MAX_PREMIUM = 100_000e6;

    // ============ Deposit Bounds ============

    /// @dev Minimum deposit: 30% (in basis points)
    uint256 constant MIN_DEPOSIT_BPS = 30_00;

    /// @dev Maximum deposit: 100% (in basis points)
    uint256 constant MAX_DEPOSIT_BPS = 100_00;

    /// @dev Basis points denominator
    uint256 constant BPS_DENOMINATOR = 100_00;

    // ============ Precision Constants ============

    /// @dev RAY precision (27 decimals)
    uint256 constant RAY = 1e27;

    /// @dev Maximum roundtrip slippage: 1% (in WAD for assertApproxEqRel)
    uint256 constant MAX_ROUNDTRIP_SLIPPAGE = 0.01e18;

    /// @dev Maximum yield buffer for invariant checks
    uint256 constant MAX_YIELD_BUFFER = 1000e6;

    // ============ Exponent Bounds ============

    /// @dev Maximum exponent for rayPow (prevents overflow)
    uint256 constant MAX_EXPONENT = 120;

    /// @dev Maximum base for rayPow (prevents overflow)
    uint256 constant MAX_RAY_BASE = type(uint128).max;

    // ============ Allocation Bounds (basis points) ============

    /// @dev Minimum allocation to Aave: 0%
    uint256 constant MIN_ALLOCATION_BPS = 0;

    /// @dev Maximum allocation to Aave: 100%
    uint256 constant MAX_ALLOCATION_BPS = 10_000;

    /// @dev Default Aave allocation: 80%
    uint256 constant DEFAULT_AAVE_ALLOCATION_BPS = 8_000;

    /// @dev Tolerance for allocation ratio checks: 2%
    uint256 constant ALLOCATION_TOLERANCE_BPS = 200;

    // ============ Delta Threshold Bounds ============

    /// @dev Minimum delta threshold for reallocation: 0%
    uint256 constant MIN_DELTA_THRESHOLD_BPS = 0;

    /// @dev Maximum delta threshold for reallocation: 50%
    uint256 constant MAX_DELTA_THRESHOLD_BPS = 5_000;

    /// @dev Default minimum delta for reallocation: 5%
    uint256 constant DEFAULT_MIN_DELTA_BPS = 500;

    // ============ Pool Liquidity ============

    /// @dev Pool liquidity for mock pools: 100M USDC
    uint256 constant POOL_LIQUIDITY = 100_000_000e6;

    // ============ BTC Vault Fee Bounds ============

    /// @dev Minimum fee for fuzz testing: 0 bps (no fee)
    uint256 constant MIN_FEE_BPS = 0;

    /// @dev Maximum fee for fuzz testing: 1000 bps (10%)
    uint256 constant MAX_FEE_BPS = 10_00;

    /// @dev Default entry fee for tests: 10 bps (0.1%)
    uint256 constant DEFAULT_ENTRY_FEE = 10;

    /// @dev Default exit fee for tests: 10 bps (0.1%)
    uint256 constant DEFAULT_EXIT_FEE = 10;

    /// @dev Default strategy cap: 1000 BTC
    uint256 constant DEFAULT_STRATEGY_CAP = 1000e8;

    /// @dev Small strategy cap for multi-strategy tests: 50 BTC
    uint256 constant SMALL_STRATEGY_CAP = 50e8;

    /// @dev Max strategies for testing
    uint256 constant MAX_STRATEGIES = 10;

    /// @dev Maximum rounding error tolerance (in wei of asset)
    uint256 constant MAX_ROUNDING_ERROR = 2;

    /// @dev Minimum deposit amount matching BTCVault.MIN_STRATEGY_DEPOSIT
    uint256 constant MIN_STRATEGY_DEPOSIT = 10_000;
}
