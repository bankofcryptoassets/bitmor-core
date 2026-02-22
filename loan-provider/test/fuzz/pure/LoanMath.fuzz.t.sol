// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {FuzzConstants as FC} from "../helpers/FuzzConstants.sol";
import {LoanMathHarness} from "../../harness/LoanMathHarness.sol";
import {DataTypes} from "@bitmor/libraries/types/DataTypes.sol";

/**
 * @title LoanMathFuzzTest
 * @author Bitmor Protocol
 * @notice Fuzz tests for LoanMath library pure functions
 * @dev Tests mathematical properties without requiring contract state
 *
 * ## Test Coverage
 * - rayPow: Identity properties (x^0=1, 1^n=1, x^1=x), monotonicity
 * - calculateStrikePrice: Output validity, price correlation
 * - calculateLoanDetails: Financial soundness, monotonicity properties
 * - min: Correctness property
 *
 * @custom:audit-category Mathematical Correctness, Financial Soundness
 */
contract LoanMathFuzzTest is Test {
    LoanMathHarness public harness;

    uint256 constant RAY = 1e27;
    uint256 constant CBBTC_DECIMALS = 8;
    uint256 constant USDC_DECIMALS = 6;

    /// @dev Safe maximum base for rayPow to avoid overflow
    /// @dev Using 1.1 * RAY (10% above RAY) allows testing monotonicity within MAX_EXPONENT
    uint256 constant SAFE_MAX_RAY_BASE = 1.1e27;

    /// @dev Minimum meaningful interest rate for monotonicity tests: 1% APR
    /// @dev Ordering tests require this floor because mulDivUp rounding dominates at sub-atomic rates.
    /// The positivity property (MATH-11) is tested down to rate=1 via testFuzz_MonthlyPayment_AlwaysPositive.
    uint256 constant MIN_MEANINGFUL_INTEREST_RATE = 0.01e27;

    /// @dev Minimum price difference to avoid rounding issues in strike price calculation
    uint256 constant MIN_PRICE_DIFFERENCE = 1e8;

    /// @dev Flash loan premium in basis points (matches MockAaveV3Pool default: 5 = 0.05%)
    uint256 constant FLASH_LOAN_PREMIUM_BPS = 5;

    function setUp() public {
        harness = new LoanMathHarness();
    }

    /// @dev Helper to build LoanDetailsParams struct for harness calls
    function _buildParams(uint256 collateral, uint256 btcPrice, uint256 interestRate, uint256 duration)
        internal
        pure
        returns (DataTypes.LoanDetailsParams memory)
    {
        return DataTypes.LoanDetailsParams({
            btcAmount: collateral,
            collateralPriceUSD: btcPrice,
            collateralAssetDecimals: CBBTC_DECIMALS,
            debtPriceUSD: FC.USDC_PRICE,
            debtAssetDecimals: USDC_DECIMALS,
            interestRate: interestRate,
            duration: duration,
            minDepositBps: FC.MIN_DEPOSIT_BPS,
            flashLoanPremiumBps: FLASH_LOAN_PREMIUM_BPS
        });
    }

    // ============ rayPow Tests ============

    /**
     * @notice Verifies that any base raised to power 0 equals RAY (which represents 1)
     * @dev Mathematical identity: x^0 = 1 for all x
     * @param baseSeed Seed for bounded base value
     * @custom:audit-property MATH-01: rayPow(base, 0) == RAY (identity property)
     * @custom:audit-category Mathematical Identity
     * @custom:audit-severity Critical
     */
    function testFuzz_RayPow_ExponentZero(uint256 baseSeed) public view {
        uint256 base = bound(baseSeed, 1, SAFE_MAX_RAY_BASE);

        uint256 result = harness.exposed_rayPow(base, 0);

        assertEq(result, RAY, "x^0 should equal 1 (RAY)");
    }

    /**
     * @notice Verifies that RAY (representing 1) raised to any power equals RAY
     * @dev Mathematical identity: 1^n = 1 for all n
     * @param exponentSeed Seed for bounded exponent value
     * @custom:audit-property MATH-02: rayPow(RAY, n) == RAY (1^n == 1)
     * @custom:audit-category Mathematical Identity
     * @custom:audit-severity Critical
     */
    function testFuzz_RayPow_BaseOne(uint256 exponentSeed) public view {
        uint256 exponent = bound(exponentSeed, 0, FC.MAX_EXPONENT);

        uint256 result = harness.exposed_rayPow(RAY, exponent);

        assertEq(result, RAY, "1^n should equal 1 (RAY)");
    }

    /**
     * @notice Verifies that any base raised to power 1 equals itself
     * @dev Mathematical identity: x^1 = x for all x
     * @param baseSeed Seed for bounded base value
     * @custom:audit-property MATH-03: rayPow(base, 1) == base (identity)
     * @custom:audit-category Mathematical Identity
     * @custom:audit-severity High
     */
    function testFuzz_RayPow_ExponentOne(uint256 baseSeed) public view {
        uint256 base = bound(baseSeed, 1, SAFE_MAX_RAY_BASE);

        uint256 result = harness.exposed_rayPow(base, 1);

        assertEq(result, base, "x^1 should equal x");
    }

    /**
     * @notice Verifies that rayPow is monotonically increasing for base > RAY
     * @dev For base > 1, higher exponents should produce larger results
     * @param baseSeed Seed for bounded base value (must be > RAY)
     * @param exp1Seed Seed for first exponent
     * @param exp2Seed Seed for second exponent (must be > exp1)
     * @custom:audit-property MATH-04: rayPow monotonically increasing for base > RAY
     * @custom:audit-category Monotonicity
     * @custom:audit-severity High
     */
    function testFuzz_RayPow_Monotonic(uint256 baseSeed, uint256 exp1Seed, uint256 exp2Seed) public view {
        // Base must be > RAY for increasing behavior, but within safe bounds to avoid overflow
        uint256 base = bound(baseSeed, RAY + 1, SAFE_MAX_RAY_BASE);
        uint256 exp1 = bound(exp1Seed, 0, FC.MAX_EXPONENT / 2);
        uint256 exp2 = bound(exp2Seed, exp1 + 1, FC.MAX_EXPONENT);

        uint256 result1 = harness.exposed_rayPow(base, exp1);
        uint256 result2 = harness.exposed_rayPow(base, exp2);

        assertLe(result1, result2, "rayPow should be monotonically increasing for base > 1");
    }

    // ============ calculateStrikePrice Tests ============

    /**
     * @notice Verifies that strike price is always positive for valid inputs
     * @dev Strike price formula should never produce zero for non-zero inputs
     * @param btcPriceSeed Seed for bounded BTC price
     * @param loanAmountSeed Seed for bounded loan amount
     * @param depositSeed Seed for bounded deposit amount
     * @custom:audit-property MATH-05: Strike price always > 0 for valid inputs
     * @custom:audit-category Output Validity
     * @custom:audit-severity Critical
     */
    function testFuzz_StrikePrice_AlwaysPositive(uint256 btcPriceSeed, uint256 loanAmountSeed, uint256 depositSeed)
        public
        view
    {
        uint256 btcPrice = bound(btcPriceSeed, FC.MIN_BTC_PRICE, FC.MAX_BTC_PRICE);
        uint256 loanAmount = bound(loanAmountSeed, FC.MIN_USDC_AMOUNT, FC.MAX_USDC_AMOUNT);
        uint256 deposit = bound(depositSeed, FC.MIN_USDC_AMOUNT, FC.MAX_USDC_AMOUNT);

        uint256 strikePrice = harness.exposed_calculateStrikePrice(btcPrice, loanAmount, deposit);

        assertGt(strikePrice, 0, "strike price should always be positive");
    }

    /**
     * @notice Verifies that strike price increases with higher BTC price
     * @dev Higher BTC price should result in higher strike price. Uses meaningful price difference
     *      to avoid integer division rounding issues.
     * @param price1Seed Seed for first BTC price
     * @param price2Seed Seed for second BTC price (must be > price1 + MIN_PRICE_DIFFERENCE)
     * @param loanAmountSeed Seed for bounded loan amount
     * @param depositSeed Seed for bounded deposit amount
     * @custom:audit-property MATH-06: Strike price increases with BTC price
     * @custom:audit-category Monotonicity
     * @custom:audit-severity High
     */
    function testFuzz_StrikePrice_IncreasesWithBtcPrice(
        uint256 price1Seed,
        uint256 price2Seed,
        uint256 loanAmountSeed,
        uint256 depositSeed
    ) public view {
        // Use meaningful price difference to avoid rounding issues
        uint256 price1 = bound(price1Seed, FC.MIN_BTC_PRICE, FC.MAX_BTC_PRICE / 2);
        uint256 price2 = bound(price2Seed, price1 + MIN_PRICE_DIFFERENCE, FC.MAX_BTC_PRICE);
        uint256 loanAmount = bound(loanAmountSeed, FC.MIN_USDC_AMOUNT, FC.MAX_USDC_AMOUNT);
        uint256 deposit = bound(depositSeed, FC.MIN_USDC_AMOUNT, FC.MAX_USDC_AMOUNT);

        uint256 strike1 = harness.exposed_calculateStrikePrice(price1, loanAmount, deposit);
        uint256 strike2 = harness.exposed_calculateStrikePrice(price2, loanAmount, deposit);

        assertLt(strike1, strike2, "higher BTC price should result in higher strike price");
    }

    // ============ calculateLoanDetails Tests ============

    /**
     * @notice Verifies that total monthly payments cover the loan amount
     * @dev Financial soundness: total payments must be >= loan to avoid negative amortization.
     *      Uses minimum meaningful interest rate to avoid precision loss in EMI calculation.
     * @param collateralSeed Seed for bounded collateral amount
     * @param btcPriceSeed Seed for bounded BTC price
     * @param interestRateSeed Seed for bounded interest rate
     * @param durationSeed Seed for bounded duration
     * @custom:audit-property MATH-07: Monthly payment * duration >= loan amount (no negative amortization)
     * @custom:audit-category Financial Soundness
     * @custom:audit-severity Critical
     */
    function testFuzz_MonthlyPayment_CoversLoan(
        uint256 collateralSeed,
        uint256 btcPriceSeed,
        uint256 interestRateSeed,
        uint256 durationSeed
    ) public view {
        uint256 collateral = bound(collateralSeed, FC.MIN_BTC_AMOUNT, FC.MAX_BTC_AMOUNT);
        uint256 btcPrice = bound(btcPriceSeed, FC.MIN_BTC_PRICE, FC.MAX_BTC_PRICE);
        // Use minimum meaningful interest rate to avoid precision loss in EMI calculation
        uint256 interestRate = bound(interestRateSeed, MIN_MEANINGFUL_INTEREST_RATE, FC.MAX_INTEREST_RATE);
        uint256 duration = bound(durationSeed, FC.MIN_DURATION, FC.MAX_DURATION);

        (uint256 loanAmount, uint256 monthlyPayment,) =
            harness.exposed_calculateLoanDetails(_buildParams(collateral, btcPrice, interestRate, duration));

        // Total payments should cover at least the loan amount
        uint256 totalPayments = monthlyPayment * duration;
        assertGe(totalPayments, loanAmount, "total payments should cover loan amount");
    }

    /**
     * @notice Verifies that higher interest rate results in higher monthly payment
     * @dev Economic invariant: higher borrowing cost means higher payments.
     *      Uses minimum meaningful interest rate to avoid precision loss.
     * @param collateralSeed Seed for bounded collateral amount
     * @param btcPriceSeed Seed for bounded BTC price
     * @param rate1Seed Seed for first interest rate
     * @param rate2Seed Seed for second interest rate (must be > rate1)
     * @param durationSeed Seed for bounded duration
     * @custom:audit-property MATH-08: Higher interest rate results in higher monthly payment
     * @custom:audit-category Monotonicity
     * @custom:audit-severity High
     */
    function testFuzz_MonthlyPayment_IncreasesWithRate(
        uint256 collateralSeed,
        uint256 btcPriceSeed,
        uint256 rate1Seed,
        uint256 rate2Seed,
        uint256 durationSeed
    ) public view {
        uint256 collateral = bound(collateralSeed, FC.MIN_BTC_AMOUNT, FC.MAX_BTC_AMOUNT);
        uint256 btcPrice = bound(btcPriceSeed, FC.MIN_BTC_PRICE, FC.MAX_BTC_PRICE);
        uint256 duration = bound(durationSeed, FC.MIN_DURATION, FC.MAX_DURATION);

        // Ensure rate1 < rate2 with meaningful difference, starting from meaningful minimum
        uint256 rate1 = bound(rate1Seed, MIN_MEANINGFUL_INTEREST_RATE, FC.MAX_INTEREST_RATE / 2);
        uint256 rate2 = bound(rate2Seed, rate1 + MIN_MEANINGFUL_INTEREST_RATE, FC.MAX_INTEREST_RATE);

        (, uint256 payment1,) =
            harness.exposed_calculateLoanDetails(_buildParams(collateral, btcPrice, rate1, duration));

        (, uint256 payment2,) =
            harness.exposed_calculateLoanDetails(_buildParams(collateral, btcPrice, rate2, duration));

        assertLe(payment1, payment2, "higher interest rate should result in higher payment");
    }

    /**
     * @notice Verifies that longer duration results in lower monthly payment
     * @dev Economic invariant: spreading payments over more months reduces each payment.
     *      Uses minimum meaningful interest rate to avoid precision loss.
     * @param collateralSeed Seed for bounded collateral amount
     * @param btcPriceSeed Seed for bounded BTC price
     * @param interestRateSeed Seed for bounded interest rate
     * @param duration1Seed Seed for first duration
     * @param duration2Seed Seed for second duration (must be > duration1)
     * @custom:audit-property MATH-09: Longer duration results in lower monthly payment
     * @custom:audit-category Monotonicity
     * @custom:audit-severity High
     */
    function testFuzz_MonthlyPayment_DecreasesWithDuration(
        uint256 collateralSeed,
        uint256 btcPriceSeed,
        uint256 interestRateSeed,
        uint256 duration1Seed,
        uint256 duration2Seed
    ) public view {
        uint256 collateral = bound(collateralSeed, FC.MIN_BTC_AMOUNT, FC.MAX_BTC_AMOUNT);
        uint256 btcPrice = bound(btcPriceSeed, FC.MIN_BTC_PRICE, FC.MAX_BTC_PRICE);
        // Use minimum meaningful interest rate to avoid precision loss
        uint256 interestRate = bound(interestRateSeed, MIN_MEANINGFUL_INTEREST_RATE, FC.MAX_INTEREST_RATE);

        // Ensure duration1 < duration2
        uint256 duration1 = bound(duration1Seed, FC.MIN_DURATION, FC.MAX_DURATION / 2);
        uint256 duration2 = bound(duration2Seed, duration1 + 1, FC.MAX_DURATION);

        (, uint256 payment1,) =
            harness.exposed_calculateLoanDetails(_buildParams(collateral, btcPrice, interestRate, duration1));

        (, uint256 payment2,) =
            harness.exposed_calculateLoanDetails(_buildParams(collateral, btcPrice, interestRate, duration2));

        assertGe(payment1, payment2, "longer duration should result in lower monthly payment");
    }

    // ============ Regression: Zero Monthly Payment Bug ============

    /**
     * @notice Regression test: monthlyPayAmt must never be 0 when loanAmount > 0
     * @dev Previously, calculateLoanDetails used plain division that truncated to 0
     *      for small collateral + low interest rate combinations.
     *      Reproduction: 0.01 BTC at $1,000, interest rate = 1 wei RAY, 12 months
     * @custom:audit-property MATH-11: monthlyPayAmt > 0 whenever loanAmount > 0
     * @custom:audit-category Financial Soundness
     * @custom:audit-severity Critical
     */
    function test_MonthlyPayment_NeverZero_SmallCollateralLowRate() public view {
        // Minimum collateral at minimum price → smallest possible loan
        uint256 collateral = FC.MIN_BTC_AMOUNT; // 0.01e8
        uint256 btcPrice = FC.MIN_BTC_PRICE; // 1000e8 ($1,000)
        uint256 interestRate = 1; // 1 wei RAY (smallest non-zero rate)
        uint256 duration = FC.MAX_DURATION; // 60 months (worst case)

        (uint256 loanAmount, uint256 monthlyPayment,) =
            harness.exposed_calculateLoanDetails(_buildParams(collateral, btcPrice, interestRate, duration));

        assertGt(loanAmount, 0, "loan amount should be positive for valid collateral");
        assertGt(monthlyPayment, 0, "monthly payment must never be zero when loan exists");
    }

    /**
     * @notice Fuzz test: monthlyPayAmt is always positive for any valid loan
     * @dev Covers the full interest rate range (1 wei to 12% APR) now that
     *      calculateLoanDetails uses mulDivUp via _calculateEMI.
     * @param collateralSeed Seed for bounded collateral amount
     * @param btcPriceSeed Seed for bounded BTC price
     * @param interestRateSeed Seed for bounded interest rate (any non-zero value)
     * @param durationSeed Seed for bounded duration
     * @custom:audit-property MATH-11: monthlyPayAmt > 0 for all valid inputs
     * @custom:audit-category Financial Soundness
     * @custom:audit-severity Critical
     */
    function testFuzz_MonthlyPayment_AlwaysPositive(
        uint256 collateralSeed,
        uint256 btcPriceSeed,
        uint256 interestRateSeed,
        uint256 durationSeed
    ) public view {
        uint256 collateral = bound(collateralSeed, FC.MIN_BTC_AMOUNT, FC.MAX_BTC_AMOUNT);
        uint256 btcPrice = bound(btcPriceSeed, FC.MIN_BTC_PRICE, FC.MAX_BTC_PRICE);
        uint256 interestRate = bound(interestRateSeed, 1, FC.MAX_INTEREST_RATE);
        uint256 duration = bound(durationSeed, FC.MIN_DURATION, FC.MAX_DURATION);

        (uint256 loanAmount, uint256 monthlyPayment,) =
            harness.exposed_calculateLoanDetails(_buildParams(collateral, btcPrice, interestRate, duration));

        if (loanAmount > 0) {
            assertGt(monthlyPayment, 0, "monthly payment must be positive when loan exists");
        }
    }

    // ============ min Tests ============

    /**
     * @notice Verifies that min returns the smaller of two values
     * @dev Basic mathematical property: min(a,b) <= a AND min(a,b) <= b
     * @param a First value
     * @param b Second value
     * @custom:audit-property MATH-10: min returns smaller value
     * @custom:audit-category Mathematical Correctness
     * @custom:audit-severity Low
     */
    function testFuzz_Min_ReturnsSmaller(uint256 a, uint256 b) public view {
        uint256 result = harness.exposed_min(a, b);

        assertLe(result, a, "min should be <= a");
        assertLe(result, b, "min should be <= b");
        assertTrue(result == a || result == b, "min should equal one of the inputs");
    }
}
