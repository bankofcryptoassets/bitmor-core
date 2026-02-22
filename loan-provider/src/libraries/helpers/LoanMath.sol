// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.30;

import {Errors} from "./Errors.sol";
import {DataTypes} from "../types/DataTypes.sol";
import {FixedPointMathLib} from "@solady/utils/FixedPointMathLib.sol";

/**
 * @title LoanMath
 * @author Bitmor Protocol
 * @notice Library for loan calculation mathematics
 * @dev Contains pure mathematical functions for interest rate calculations, loan amortization,
 * and EMI (Equated Monthly Installment) computation using RAY precision (27 decimals).
 *
 * ## Key Formulas
 *
 * ### EMI Calculation (Standard Amortization)
 * ```
 * EMI = P * r * (1 + r)^n / ((1 + r)^n - 1)
 * ```
 * Where:
 * - P = Principal (loan amount)
 * - r = Monthly interest rate (annual rate / 12)
 * - n = Number of monthly payments (duration)
 *
 * ### Strike Price Calculation
 * ```
 * strikePrice = btcPrice * loanAmount / (loanAmount + deposit) * 1.1
 * ```
 *
 * ## Precision
 * - Interest rates use RAY precision (27 decimals) for maximum accuracy
 * - Loan amounts use 6 decimals (USDC)
 * - Collateral amounts use 8 decimals (cbBTC)
 * - USD prices use 8 decimals (Chainlink standard)
 *
 * @custom:security Uses Solady's FixedPointMathLib for overflow-safe operations
 */
library LoanMath {
    using FixedPointMathLib for uint256;

    /**
     * @dev RAY precision for interest rate calculations (27 decimals)
     */
    uint256 private constant RAY = 1e27;

    /**
     * @dev Number of months in a year for rate conversion
     */
    uint256 private constant MONTHS_PER_YEAR = 12;

    /**
     * @dev Basis points denominator (100% = 10000)
     */
    uint256 private constant BASIS_POINTS = 100_00;

    /**
     * @notice Calculates power of a number with fixed-point precision using RAY
     * @dev Implements exponentiation by squaring algorithm for efficient computation.
     * Time complexity: O(log n) where n is the exponent.
     *
     * ## Algorithm
     * Uses binary exponentiation: if exponent bit is set, multiply result by current base.
     * Each iteration squares the base and shifts exponent right.
     *
     * @param base The base number in RAY precision (27 decimals)
     * @param exponent The exponent (whole number, not RAY-scaled)
     * @return result The result in RAY precision
     */
    //! TODO: Consider replacing with a cleaner, more precise implementation
    function rayPow(uint256 base, uint256 exponent) internal pure returns (uint256 result) {
        result = RAY;

        if (exponent == 0) {
            return result;
        }

        uint256 tempBase = base;
        uint256 tempExponent = exponent;

        // Exponentiation by squaring
        while (tempExponent > 0) {
            if (tempExponent & 1 != 0) {
                result = (result * tempBase) / (RAY);
            }
            tempBase = (tempBase * tempBase) / (RAY);
            tempExponent >>= 1;
        }

        return result;
    }

    /**
     * @notice Calculates the loan amount and monthly payment based on collateral and deposit
     * @dev Performs the following calculations:
     * 1. Converts collateral to USD value using oracle price
     * 2. Validates deposit meets minimum deposit
     * 3. Calculates loan amount as: collateralValue - depositValue
     * 4. Includes flash loan premium in total debt before EMI computation
     * 5. Computes EMI using standard amortization formula
     *
     * ## Validation
     * - Reverts with `InsufficientCollateral` if deposit exceeds collateral value
     * - Reverts with `InsufficientDeposit` if deposit is below 33% of collateral
     *
     * @param data Struct containing all calculation parameters
     * @return loanAmount The calculated loan amount in debt asset decimals
     * @return monthlyPayAmt The monthly payment amount in debt asset decimals
     * @return minDepositRequired Minimum deposit required in debt asset decimals
     */
    function calculateLoanAmt(DataTypes.CalculateLoanAmt memory data)
        internal
        pure
        returns (uint256 loanAmount, uint256 monthlyPayAmt, uint256 minDepositRequired)
    {
        // Convert collateral amount to USD value
        uint256 collateralValueUSD =
            data.collateralAmount.fullMulDivUp(data.collateralPriceUSD, (10 ** data.collateralAssetDecimals));

        // Convert deposit amount to USD value
        uint256 depositValueUSD = data.depositAmount.fullMulDiv(data.debtPriceUSD, (10 ** data.debtAssetDecimals));

        // Ensure collateral value exceeds deposit
        if (depositValueUSD > collateralValueUSD) revert Errors.InsufficientCollateral();

        uint256 minDepositRequiredUSD = collateralValueUSD.fullMulDivUp(data.minDepositBps, BASIS_POINTS);

        if (minDepositRequiredUSD > depositValueUSD) revert Errors.InsufficientDeposit();

        minDepositRequired = minDepositRequiredUSD.fullMulDivUp((10 ** data.debtAssetDecimals), data.debtPriceUSD);

        // Calculate loan amount in USD
        uint256 loanValueUSD = collateralValueUSD - depositValueUSD;

        // Convert loan value back to USDC
        loanAmount = loanValueUSD.fullMulDivUp((10 ** data.debtAssetDecimals), data.debtPriceUSD);

        // A zero loan amount means the deposit covers the full collateral value — no loan needed
        if (loanAmount == 0) revert Errors.ZeroAmount();

        // Include flash loan premium in EMI principal (matches CloseLoanLogic pattern)
        uint256 flashLoanPremiumAmt = loanAmount.mulDivUp(data.flashLoanPremiumBps, BASIS_POINTS);
        uint256 totalDebt = loanAmount + flashLoanPremiumAmt;

        // Calculate monthly payment on total debt (loanAmount + flash loan premium)
        monthlyPayAmt = _calculateEMI(totalDebt, data.interestRate, data.duration);
    }

    /**
     * @notice Calculates loan details for a given collateral amount (used for previewing)
     * @dev Similar to `calculateLoanAmt` but assumes minimum deposit as deposit amount.
     * Used by `Loan.getLoanDetails()` to preview loan terms before creation.
     *
     * ## Calculation Flow
     * 1. Convert collateral to USD value
     * 2. Calculate minimum deposit
     * 3. Loan amount = collateral value - minimum deposit value
     * 4. Include flash loan premium in total debt
     * 5. Calculate monthly payment using EMI formula
     *
     * @param data Struct containing collateral amount, prices, decimals, interest rate, duration, and deposit/premium params
     * @return loanAmount The calculated loan amount in USDC (6 decimals)
     * @return monthlyPayAmt The monthly payment amount in USDC (6 decimals)
     * @return minDepositRequired Minimum deposit required amount in USDC (6 decimals)
     */
    function calculateLoanDetails(DataTypes.CalculateLoanAmt memory data)
        internal
        pure
        returns (uint256 loanAmount, uint256 monthlyPayAmt, uint256 minDepositRequired)
    {
        // Convert collateral amount to USD value
        uint256 collateralValueUSD =
            data.collateralAmount.fullMulDivUp(data.collateralPriceUSD, (10 ** data.collateralAssetDecimals));

        uint256 minDepositRequiredUSD = collateralValueUSD.fullMulDivUp(data.minDepositBps, BASIS_POINTS);

        uint256 depositValueUSD = minDepositRequiredUSD;

        minDepositRequired = minDepositRequiredUSD.fullMulDivUp((10 ** data.debtAssetDecimals), data.debtPriceUSD);

        // Calculate loan amount in USD
        uint256 loanValueUSD = collateralValueUSD - depositValueUSD;

        // Convert loan value back to USDC
        loanAmount = loanValueUSD.fullMulDivUp((10 ** data.debtAssetDecimals), data.debtPriceUSD);

        // Include flash loan premium in EMI principal (matches CloseLoanLogic pattern)
        uint256 flashLoanPremiumAmt = loanAmount.mulDivUp(data.flashLoanPremiumBps, BASIS_POINTS);
        uint256 totalDebt = loanAmount + flashLoanPremiumAmt;

        // Calculate monthly payment on total debt (loanAmount + flash loan premium)
        monthlyPayAmt = _calculateEMI(totalDebt, data.interestRate, data.duration);
    }

    /**
     * @notice Returns the minimum of two uint256 values
     * @param a The first value
     * @param b The second value
     * @return The minimum of the two values
     */
    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    /**
     * @notice Calculates the strike price for options based on loan parameters
     * @dev Formula: `strikePrice = btcPrice * loanAmount / (loanAmount + deposit) * 1.1`
     *
     * The 1.1 multiplier (110%) provides a 10% buffer above the break-even price,
     * ensuring the strike price accounts for potential price appreciation.
     *
     * @param btcPriceUSD Current BTC price in USD (8 decimals)
     * @param loanAmount The loan amount in debt asset (6 decimals for USDC)
     * @param deposit The deposit amount in debt asset (6 decimals for USDC)
     * @return strikePrice The calculated strike price in USD (8 decimals)
     */
    function calculateStrikePrice(uint256 btcPriceUSD, uint256 loanAmount, uint256 deposit)
        internal
        pure
        returns (uint256 strikePrice)
    {
        uint256 totalAmount = loanAmount + deposit;

        strikePrice = (btcPriceUSD * loanAmount * 110) / (totalAmount * 100);

        return strikePrice;
    }

    /**
     * @notice Calculates the Equated Monthly Installment (EMI)
     * @dev Shared implementation used by both `calculateLoanAmt` and `calculateLoanDetails`.
     * Uses Solady's `mulDivUp` throughout to prevent truncation to zero for small amounts.
     *
     * Formula: `EMI = P * r * (1 + r)^n / ((1 + r)^n - 1)`
     *
     * For zero interest rate, returns `ceil(loanAmount / duration)`.
     *
     * @param loanAmount The loan principal in debt asset decimals (e.g., 6 for USDC)
     * @param interestRate Annual interest rate in RAY (27 decimals)
     * @param duration Loan duration in months
     * @return monthlyPayAmt Monthly payment amount in debt asset decimals
     */
    function _calculateEMI(uint256 loanAmount, uint256 interestRate, uint256 duration)
        private
        pure
        returns (uint256 monthlyPayAmt)
    {
        // Zero interest rate: equal division rounded up
        if (interestRate == 0) {
            return loanAmount.fullMulDivUp(1, duration);
        }

        // Convert annual rate (RAY) to monthly rate (RAY), rounded up
        uint256 monthlyRate = interestRate.mulDivUp(1, MONTHS_PER_YEAR);

        // (1 + r) in RAY precision
        uint256 onePlusRate = RAY.rawAdd(monthlyRate);

        // (1 + r)^n via binary exponentiation
        uint256 onePlusRatePowN = rayPow(onePlusRate, duration);

        // Numerator: P * r * (1 + r)^n
        uint256 numerator = loanAmount.mulDivUp(monthlyRate, RAY);
        numerator = numerator.mulDivUp(onePlusRatePowN, RAY);

        // Denominator: (1 + r)^n - 1
        uint256 denominator = onePlusRatePowN.rawSub(RAY);

        // EMI = numerator / denominator (rounded up)
        monthlyPayAmt = numerator.mulDivUp(RAY, denominator);
    }
}
