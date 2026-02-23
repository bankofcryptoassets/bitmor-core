// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {UnitTestBase} from "../../base/UnitTestBase.sol";
import {FuzzConstants as FC} from "../helpers/FuzzConstants.sol";
import {TestConstants as TC} from "../../helpers/TestConstants.sol";

/**
 * @title FuzzTestBase
 * @author Bitmor Protocol
 * @notice Base contract for fuzz tests with bound helpers
 * @dev Extends UnitTestBase with fuzz-specific utilities for constraining inputs
 *
 * ## Usage
 * ```solidity
 * contract MyFuzzTest is FuzzTestBase {
 *     function testFuzz_Example(uint256 rawAmount) public {
 *         uint256 amount = _boundBtcAmount(rawAmount);
 *         // amount is now within valid BTC range
 *     }
 * }
 * ```
 */
abstract contract FuzzTestBase is UnitTestBase {
    // ============ BTC Amount Bounds ============

    /**
     * @notice Bounds raw input to valid BTC amount range
     * @param raw The raw fuzzed input
     * @return The bounded BTC amount (0.01 - 100 BTC)
     */
    function _boundBtcAmount(uint256 raw) internal pure returns (uint256) {
        return bound(raw, FC.MIN_BTC_AMOUNT, FC.MAX_BTC_AMOUNT);
    }

    /**
     * @notice Bounds raw input to valid collateral range from Loan contract
     * @dev Reads min/max from Loan contract parameters
     * @param raw The raw fuzzed input
     * @return The bounded collateral amount
     */
    function _boundCollateral(uint256 raw) internal view virtual returns (uint256) {
        // Default implementation uses FuzzConstants
        // Override in LoanFuzzTestBase to use loan.getLoanParameters()
        return bound(raw, FC.MIN_BTC_AMOUNT, FC.MAX_BTC_AMOUNT);
    }

    // ============ USDC Amount Bounds ============

    /**
     * @notice Bounds raw input to valid USDC amount range
     * @param raw The raw fuzzed input
     * @return The bounded USDC amount (1 - 10M USDC)
     */
    function _boundUsdcAmount(uint256 raw) internal pure returns (uint256) {
        return bound(raw, FC.MIN_USDC_AMOUNT, FC.MAX_USDC_AMOUNT);
    }

    // ============ Duration Bounds ============

    /**
     * @notice Bounds raw input to valid loan duration range
     * @param raw The raw fuzzed input
     * @return The bounded duration (1 - 60 months)
     */
    function _boundDuration(uint256 raw) internal pure returns (uint256) {
        return bound(raw, FC.MIN_DURATION, FC.MAX_DURATION);
    }

    // ============ Price Bounds ============

    /**
     * @notice Bounds raw input to valid BTC price range
     * @param raw The raw fuzzed input
     * @return The bounded BTC price ($1k - $1M)
     */
    function _boundBtcPrice(uint256 raw) internal pure returns (uint256) {
        return bound(raw, FC.MIN_BTC_PRICE, FC.MAX_BTC_PRICE);
    }

    // ============ Interest Rate Bounds ============

    /**
     * @notice Bounds raw input to valid interest rate range
     * @param raw The raw fuzzed input
     * @return The bounded interest rate (0 - 12% in RAY)
     */
    function _boundInterestRate(uint256 raw) internal pure returns (uint256) {
        return bound(raw, FC.MIN_INTEREST_RATE, FC.MAX_INTEREST_RATE);
    }

    // ============ Deposit Bounds ============

    /**
     * @notice Bounds raw input to valid deposit range based on collateral value
     * @dev Deposit must be between 30% and 100% of collateral value
     * @param collateralValueUsd The collateral value in USD (8 decimals)
     * @param raw The raw fuzzed input
     * @return The bounded deposit amount in USDC (6 decimals)
     */
    function _boundDeposit(uint256 collateralValueUsd, uint256 raw) internal pure returns (uint256) {
        uint256 minDepositUsd = (collateralValueUsd * FC.MIN_DEPOSIT_BPS) / FC.BPS_DENOMINATOR;
        uint256 maxDepositUsd = collateralValueUsd;

        // Convert to USDC (6 decimals) from USD (8 decimals)
        uint256 minDepositUsdc = (minDepositUsd * 1e6) / 1e8;
        uint256 maxDepositUsdc = (maxDepositUsd * 1e6) / 1e8;

        // Ensure min <= max
        if (minDepositUsdc >= maxDepositUsdc) {
            return maxDepositUsdc;
        }

        return bound(raw, minDepositUsdc, maxDepositUsdc);
    }

    /**
     * @notice Bounds deposit to be below minimum (for revert tests)
     * @param collateralValueUsd The collateral value in USD (8 decimals)
     * @param raw The raw fuzzed input
     * @return The bounded insufficient deposit amount
     */
    function _boundInsufficientDeposit(uint256 collateralValueUsd, uint256 raw) internal pure returns (uint256) {
        uint256 minDepositUsd = (collateralValueUsd * FC.MIN_DEPOSIT_BPS) / FC.BPS_DENOMINATOR;
        uint256 minDepositUsdc = (minDepositUsd * 1e6) / 1e8;

        if (minDepositUsdc <= 1) {
            return 0;
        }

        return bound(raw, 1, minDepositUsdc - 1);
    }

    // ============ Exponent Bounds (for LoanMath) ============

    /**
     * @notice Bounds raw input to valid exponent range for rayPow
     * @param raw The raw fuzzed input
     * @return The bounded exponent (0 - 120)
     */
    function _boundExponent(uint256 raw) internal pure returns (uint256) {
        return bound(raw, 0, FC.MAX_EXPONENT);
    }

    /**
     * @notice Bounds raw input to valid base for rayPow (prevents overflow)
     * @param raw The raw fuzzed input
     * @return The bounded base (1 - uint128.max)
     */
    function _boundRayBase(uint256 raw) internal pure returns (uint256) {
        return bound(raw, 1, FC.MAX_RAY_BASE);
    }

    // ============ Helper Functions ============

    /**
     * @notice Calculates collateral value in USD
     * @param btcAmount BTC amount (8 decimals)
     * @param btcPrice BTC price in USD (8 decimals)
     * @return Collateral value in USD (8 decimals)
     */
    function _getCollateralValueUsd(uint256 btcAmount, uint256 btcPrice) internal pure returns (uint256) {
        return (btcAmount * btcPrice) / 1e8;
    }

    /**
     * !TODO: Need to have a USDC price variable instead of using the constant 1 USDC = 1 USD
     * @notice Gets minimum deposit for a collateral amount at a given BTC price
     * @param btcAmount BTC amount (8 decimals)
     * @param btcPrice BTC price in USD (8 decimals)
     * @return Minimum deposit in USDC (6 decimals)
     */
    function _getMinDepositUsdc(uint256 btcAmount, uint256 btcPrice) internal pure returns (uint256) {
        uint256 collateralValueUsd = _getCollateralValueUsd(btcAmount, btcPrice);
        uint256 minDepositUsd = (collateralValueUsd * FC.MIN_DEPOSIT_BPS) / FC.BPS_DENOMINATOR;
        return (minDepositUsd * 1e6) / 1e8;
    }
}
