// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.30;

import {BaseLoanTest} from "./Loan/BaseLoan.t.sol";
import {DataTypes} from "@bitmor/libraries/types/DataTypes.sol";
import {IERC20} from "@openzeppelin/interfaces/IERC20.sol";
import {ILendingPool} from "@bitmor/interfaces/ILendingPool.sol";
import {Errors} from "@bitmor/libraries/helpers/Errors.sol";
import {FixedPointMathLib} from "@solady/utils/FixedPointMathLib.sol";

/// @title LendingPoolTest
/// @notice Tests for Bitmor LendingPool security restrictions and loan payment calculations
contract LendingPoolTest is BaseLoanTest {
    using FixedPointMathLib for uint256;

    address internal liquidityProvider;

    function setUp() public virtual override {
        super.setUp();

        liquidityProvider = makeAddr("liquidityProvider");
        _updateAddressesProviderBitmorLoan();
    }

    /// @notice Seed BTC liquidity into the Bitmor pool
    function _seedBtcLiquidity() internal {
        _utilMintTokenTo(collateralAsset, liquidityProvider, BTC_SEED_AMOUNT);

        vm.startPrank(liquidityProvider);
        IERC20(collateralAsset).approve(s_bitmorPool, BTC_SEED_AMOUNT);
        ILendingPool(s_bitmorPool).deposit(collateralAsset, BTC_SEED_AMOUNT, liquidityProvider, 0);
        vm.stopPrank();
    }

    /// @notice Calculate amortized monthly payment using standard formula
    function _calculateAmortizedPayment(uint256 principal, uint256 annualRateBps, uint256 months)
        internal
        pure
        returns (uint256 monthlyPayment)
    {
        if (principal == 0 || months == 0) return 0;

        // Monthly rate = annual rate / 12, scaled by PRECISION
        uint256 monthlyRateScaled = (annualRateBps * PRECISION) / (BPS_DENOMINATOR * 12);

        // (1 + r) in scaled form
        uint256 onePlusR = PRECISION + monthlyRateScaled;

        // Calculate (1+r)^n iteratively
        uint256 onePlusRPowN = PRECISION;
        for (uint256 i = 0; i < months; i++) {
            onePlusRPowN = (onePlusRPowN * onePlusR) / PRECISION;
        }

        // Numerator: P * r * (1+r)^n
        uint256 numerator = (principal * monthlyRateScaled * onePlusRPowN) / PRECISION;

        // Denominator: (1+r)^n - 1
        uint256 denominator = onePlusRPowN - PRECISION;

        if (denominator == 0) return principal / months;

        monthlyPayment = (numerator * PRECISION) / denominator / PRECISION;
    }

    /// @notice Borrowing USDC directly from the pool reverts for regular users.
    function test_lendingPool_borrowUSDC_revertsForUser() public {
        _utilMintTokenAndApproveMax(debtAsset, user, s_bitmorPool, POOL_DEPOSIT_AMOUNT);

        // User deposits USDC as collateral
        vm.prank(user);
        ILendingPool(s_bitmorPool).deposit(debtAsset, POOL_DEPOSIT_AMOUNT, user, 0);

        // User attempts to borrow USDC - should revert with UnauthorizedCaller
        vm.expectRevert(Errors.UnauthorizedCaller.selector);
        vm.prank(user);
        ILendingPool(s_bitmorPool).borrow(debtAsset, SMALL_BORROW_AMOUNT, 2, 0, user);
    }

    /// @notice Borrowing BTC directly from the pool reverts for regular users.
    function test_lendingPool_borrowBTC_revertsForUser() public {
        // Seed BTC liquidity so revert is from access control, not insufficient liquidity
        _seedBtcLiquidity();

        _utilMintTokenAndApproveMax(debtAsset, user, s_bitmorPool, POOL_DEPOSIT_AMOUNT);

        // User deposits USDC as collateral
        vm.prank(user);
        ILendingPool(s_bitmorPool).deposit(debtAsset, POOL_DEPOSIT_AMOUNT, user, 0);

        uint256 btcBorrowAmount = BTC_SEED_AMOUNT / 10; // 0.01 BTC

        // User attempts to borrow BTC - should revert with UnauthorizedCaller
        vm.expectRevert(Errors.UnauthorizedCaller.selector);
        vm.prank(user);
        ILendingPool(s_bitmorPool).borrow(collateralAsset, btcBorrowAmount, 2, 0, user);
    }

    /// @notice estimatedMonthlyPayment amortizes using the configured APR (MAX_APR_BPS = 20%).
    function test_monthlyPaymentCalculation_amortizesAtMaxRate() public {
        // Mock oracle prices: BTC = $100,000, USDC = $1
        uint256 btcPrice = 100_000e8;
        uint256 usdcPrice = 1e8;

        _utilSetOraclePrice(s_bitmorPool, collateralAsset, btcPrice);
        _utilSetOraclePrice(s_bitmorPool, debtAsset, usdcPrice);

        // Set the variable borrow rate to MAX_APR_BPS (20%)
        // Convert MAX_APR_BPS (2000 = 20%) to RAY (0.20e27)
        uint256 maxRateInRay = (MAX_APR_BPS * 1e27) / BPS_DENOMINATOR;
        mockBitmorPool.setVariableBorrowRate(debtAsset, maxRateInRay);

        // Get loan details for 1 BTC, 12 months
        uint256 collateralAmount = 1e8;
        uint256 duration = 12;

        (uint256 loanAmount, uint256 estimatedMonthlyPayment, uint256 minDepositRequired) =
            loan.getLoanDetails(collateralAmount, duration);

        // Verify intermediate values
        uint256 expectedLoanAmount = 67_000e6;
        uint256 expectedMinDeposit = 33_000e6;

        assertEq(loanAmount, expectedLoanAmount, "Loan amount should be 67% of BTC value");
        assertEq(minDepositRequired, expectedMinDeposit, "Min deposit should be 33% of BTC value");

        // Calculate expected payment at MAX APR (20%)
        uint256 expectedPayment = _calculateAmortizedPayment(expectedLoanAmount, MAX_APR_BPS, duration);

        // Assert monthly payment matches expected (within tolerance)
        assertApproxEqAbs(
            estimatedMonthlyPayment,
            expectedPayment,
            PAYMENT_TOLERANCE,
            "Monthly payment should be calculated at configured APR"
        );
    }

    /// @notice At ~100% utilization, 12 monthly repayments fully repay the loan.
    function test_highUtilization_100pct_12PaymentsFullyRepayLoan() public {
        // Create the main test loan using consolidated helper
        (address lsa, DataTypes.LoanData memory loanData) = _createStandardLoanWithData();
        uint256 estimatedMonthlyPayment = loanData.estimatedMonthlyPayment;

        // Drive utilization high by creating additional loans using consolidated helper
        for (uint256 i = 0; i < 3; i++) {
            address utilizationUser = makeAddr(string(abi.encodePacked("utilizationUser", i)));
            _createStandardLoanForBorrower(utilizationUser);
        }

        // Execute 12 monthly payments
        for (uint256 month = 1; month <= 12; month++) {
            uint256 debtBefore = _getDebtBalance(lsa);

            if (debtBefore == 0) break;

            _utilWarpPastRepaymentInterval();

            _utilMintTokenAndApprove(debtAsset, user, address(loan), estimatedMonthlyPayment);

            vm.prank(user);
            loan.repay(lsa, estimatedMonthlyPayment);

            uint256 debtAfter = _getDebtBalance(lsa);

            assertLt(debtAfter, debtBefore, "Debt should decrease each month");
        }

        // Assert debt is fully repaid
        uint256 finalDebt = _getDebtBalance(lsa);
        assertLe(finalDebt, DEBT_DUST_THRESHOLD, "Debt should be zero or dust after 12 payments");
    }

    /// @notice At ~90% utilization, the final repayment overpays and only remaining debt is taken.
    function test_lowUtilization_90pct_finalPaymentOvercoversDebt() public {
        // Create the test loan using consolidated helper
        (address lsa, DataTypes.LoanData memory loanData) = _createStandardLoanWithData();
        uint256 estimatedMonthlyPayment = loanData.estimatedMonthlyPayment;

        // Keep utilization at ~90% with just 1 additional loan using consolidated helper
        address utilizationUser = makeAddr("utilizationUser");
        _createStandardLoanForBorrower(utilizationUser);

        // Execute payments while ensuring some debt remains
        uint256 totalDebt = _getDebtBalance(lsa);
        uint256 monthsToPay = (totalDebt - 1) / estimatedMonthlyPayment;
        require(monthsToPay > 0, "Test setup: monthly payment exceeds total debt");

        for (uint256 month = 1; month <= monthsToPay; month++) {
            _utilWarpPastRepaymentInterval();

            _utilMintTokenAndApprove(debtAsset, user, address(loan), estimatedMonthlyPayment);

            vm.prank(user);
            loan.repay(lsa, estimatedMonthlyPayment);
        }

        // Check debt before final payment
        uint256 debtRemaining = _getDebtBalance(lsa);

        // At lower utilization, remaining debt should be less than monthly payment
        assertLt(
            debtRemaining,
            estimatedMonthlyPayment,
            "Remaining debt should be less than monthly payment at ~90% utilization"
        );

        // Execute final payment (overpay scenario)
        _utilWarpPastRepaymentInterval();

        _utilMintTokenAndApprove(debtAsset, user, address(loan), estimatedMonthlyPayment);

        vm.prank(user);
        uint256 actualRepaid = loan.repay(lsa, estimatedMonthlyPayment);

        // actualRepaid should be less than or equal to remaining debt (capped at actual debt)
        assertLe(actualRepaid, debtRemaining, "Repay should cap at actual debt remaining");

        // Debt should now be zero
        uint256 finalDebt = _getDebtBalance(lsa);
        assertLe(finalDebt, DEBT_DUST_THRESHOLD, "Debt should be zero after final payment");
    }
}
