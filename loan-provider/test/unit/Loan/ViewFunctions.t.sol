// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {BaseLoanTest} from "./BaseLoan.t.sol";
import {Errors} from "@bitmor/libraries/helpers/Errors.sol";
import {DataTypes} from "@bitmor/libraries/types/DataTypes.sol";
import {TestConstants as TC} from "../../helpers/TestConstants.sol";

/// @title ViewFunctionsTest
/// @author Bitmor Protocol
/// @notice Tests for Loan contract view/getter functions including configuration values and user loan queries
contract ViewFunctionsTest is BaseLoanTest {
    function setUp() public override {
        super.setUp();
    }

    // ============ Getter Verification ============

    /// @notice Test that all getters return expected configuration values
    function test_getters_ReturnExpectedConfigValues() public view {
        // Verify addresses against known mock addresses
        assertEq(loan.getCollateralAsset(), address(mockBTCVault), "Collateral asset mismatch");
        assertEq(loan.getDebtAsset(), address(mockUSDC), "Debt asset mismatch");
        assertEq(bitmorAddressesProvider.getPremiumCollector(), premiumCollector, "Premium collector mismatch");

        // Verify against exact config values from HelperConfig
        assertEq(loan.getGracePeriod(), config.getGracePeriod(), "Grace period should match config");
        assertEq(loan.getPreClosureFee(), config.getPreClosureFee(), "Pre-closure fee should match config");

        // Verify against TestConstants configuration
        assertEq(loan.getSlippageForSwap(), TC.SLIPPAGE_SWAP, "Slippage should match test config");
        assertEq(loan.getMaxBTCAmount(), TC.MAX_COLLATERAL, "Max BTC should match test config");
        assertEq(loan.getMinBTCAmount(), TC.MIN_COLLATERAL, "Min BTC should match test config");
        assertEq(loan.getMinDepositBps(), TC.MIN_DEPOSIT, "Min deposit BPS should match test config");
        assertEq(
            loan.getSlippageForSharesToAsset(),
            TC.SLIPPAGE_SHARES_TO_ASSET,
            "Slippage for shares should match test config"
        );

        // Verify constant values
        assertEq(loan.getRepaymentInterval(), 30 days, "Repayment interval should be exactly 30 days");

        // Verify liquidation fee defaults (uninitialized = 0)
        assertEq(loan.getLiquidationFeeBps(), 0, "Liquidation fee should default to 0");
        assertEq(
            bitmorAddressesProvider.getLiquidationFeeCollector(),
            address(0),
            "Liquidation fee collector should default to address(0)"
        );
    }

    // ============ User Loan Functions ============

    /// @notice Test that getUserLoanAtIndex reverts with out of bounds index
    function test_getUserLoanAtIndex_RevertWhen_OutOfBounds() public {
        // User has no loans
        vm.expectRevert(Errors.IndexOutOfBounds.selector);
        loan.getUserLoanAtIndex(user, 0);

        // Create a loan
        _createStandardLoan();

        // Index 1 is out of bounds (only index 0 exists)
        vm.expectRevert(Errors.IndexOutOfBounds.selector);
        loan.getUserLoanAtIndex(user, 1);
    }

    /// @notice Test that getUserLoanCount returns zero for user with no loans
    function test_getUserLoanCount_ReturnsZeroWhenNoLoans() public view {
        uint256 count = loan.getUserLoanCount(address(0xdead));
        assertEq(count, 0, "User with no loans should return 0");
    }

    /// @notice Test that getUserAllLoans returns empty array for user with no loans
    function test_getUserAllLoans_ReturnsEmptyArrayWhenNoLoans() public view {
        DataTypes.LoanData[] memory loans = loan.getUserAllLoans(address(0xdead));
        assertEq(loans.length, 0, "Should return empty array");
    }

    // ============ Loan Data Verification ============

    /// @notice Test that getLoanByLSA returns exact input values used during creation
    function test_getLoanByLSA_ReturnsExactInputValues() public {
        uint256 collateral = STANDARD_COLLATERAL_AMOUNT;
        uint256 duration = STANDARD_DURATION;

        // Pre-calculate expected loan amount for verification
        (uint256 expectedLoanAmt,, uint256 minDeposit) = loan.getLoanDetails(collateral, duration);

        _mintDebtAssetToUser();
        vm.prank(user);
        address lsa = loan.initializeLoan(minDeposit, PREMIUM_AMOUNT, collateral, duration, "");

        DataTypes.LoanData memory data = loan.getLoanByLSA(lsa);

        // Verify exact values for inputs
        assertEq(data.borrower, user, "Borrower should match");
        assertEq(data.btcAmount, collateral, "Collateral should match exact input");
        assertEq(data.loanAmount, expectedLoanAmt, "Loan amount should match calculation");
        assertEq(data.duration, duration, "Duration should match exact input");
        // Monthly payment is recalculated based on actual borrowed amount, so just verify it's positive
        assertGt(data.estimatedMonthlyPayment, 0, "Monthly payment should be positive");
        assertEq(data.insuranceID, 0, "Insurance ID should be 0 initially");
        assertEq(uint8(data.status), uint8(DataTypes.LoanStatus.Active), "Status should be Active");
    }

    /// @notice Test that getUserLoanCount returns correct count after creating loans
    function test_getUserLoanCount_AfterCreatingLoans() public {
        // Create first loan for user
        _createStandardLoan();
        assertEq(loan.getUserLoanCount(user), 1, "Should have 1 loan");

        // Create second loan for different borrower to avoid CREATE2 collision
        address borrower2 = makeAddr("borrower2");
        _createLoanForBorrower(borrower2, STANDARD_COLLATERAL_AMOUNT, STANDARD_DURATION, PREMIUM_AMOUNT);
        assertEq(loan.getUserLoanCount(borrower2), 1, "Borrower2 should have 1 loan");
        assertEq(loan.getUserLoanCount(user), 1, "User should still have 1 loan");
    }

    // ============ Preview vs Actual Rate Consistency ============

    /// @notice Test that getLoanDetails preview monthly payment matches the actual loan's estimatedMonthlyPayment
    /// @dev Regression test for vuln-38: getLoanDetails previously used currentVariableBorrowRate
    ///      while initializeLoan used getMaxVariableBorrowRate, causing preview < actual
    function test_getLoanDetails_MonthlyPaymentMatchesActualLoan() public {
        uint256 collateral = STANDARD_COLLATERAL_AMOUNT;
        uint256 duration = STANDARD_DURATION;

        // Get preview values
        (uint256 previewLoanAmt, uint256 previewMonthlyPay, uint256 minDeposit) =
            loan.getLoanDetails(collateral, duration);

        // Create the actual loan
        _mintDebtAssetToUser();
        vm.prank(user);
        address lsa = loan.initializeLoan(minDeposit, PREMIUM_AMOUNT, collateral, duration, "");

        DataTypes.LoanData memory loanData = loan.getLoanByLSA(lsa);

        // Preview loan amount must match actual loan amount
        assertEq(previewLoanAmt, loanData.loanAmount, "preview loanAmount should equal actual loanAmount");

        // Preview monthly payment must match actual monthly payment
        assertEq(
            previewMonthlyPay,
            loanData.estimatedMonthlyPayment,
            "preview monthlyPayment should equal actual estimatedMonthlyPayment"
        );
    }

    /// @notice Test that getLoanDetails uses getMaxVariableBorrowRate, not currentVariableBorrowRate
    /// @dev Sets divergent rates in mock to prove the preview reads from the strategy, not reserve data
    function test_getLoanDetails_UsesMaxVariableBorrowRate() public {
        uint256 collateral = STANDARD_COLLATERAL_AMOUNT;
        uint256 duration = STANDARD_DURATION;

        // Set a low currentVariableBorrowRate in the reserve (1%) — preview should NOT use this
        mockBitmorPool.setVariableBorrowRate(address(mockUSDC), 0.01e27);

        // Get preview with the default strategy max rate
        (, uint256 previewMonthlyPayHigh,) = loan.getLoanDetails(collateral, duration);

        // Lower the strategy's base rate, reducing getMaxVariableBorrowRate()
        mockUSDCInterestRateStrategy.setBaseVariableBorrowRate(0.001e27);

        (, uint256 previewMonthlyPayLow,) = loan.getLoanDetails(collateral, duration);

        // Higher max rate must produce higher monthly payment (proving preview uses strategy, not reserve)
        assertGt(previewMonthlyPayHigh, previewMonthlyPayLow, "higher max rate should produce higher monthly payment");
    }

    /// @notice Test that getUserAllLoans returns correct loan data for each user
    function test_getUserAllLoans_ReturnsCorrectData() public {
        // Create loan for user
        _createStandardLoan();

        // Create loan for different borrower
        address borrower2 = makeAddr("borrower2");
        _createLoanForBorrower(borrower2, STANDARD_COLLATERAL_AMOUNT / 2, STANDARD_DURATION, PREMIUM_AMOUNT);

        // Verify user's loans
        DataTypes.LoanData[] memory userLoans = loan.getUserAllLoans(user);
        assertEq(userLoans.length, 1, "User should have 1 loan");
        assertEq(userLoans[0].borrower, user, "Loan borrower should match user");
        assertEq(userLoans[0].btcAmount, STANDARD_COLLATERAL_AMOUNT, "Collateral should match");

        // Verify borrower2's loans
        DataTypes.LoanData[] memory borrower2Loans = loan.getUserAllLoans(borrower2);
        assertEq(borrower2Loans.length, 1, "Borrower2 should have 1 loan");
        assertEq(borrower2Loans[0].borrower, borrower2, "Loan borrower should match borrower2");
        assertEq(borrower2Loans[0].btcAmount, STANDARD_COLLATERAL_AMOUNT / 2, "Collateral should match");
    }

    // ============ Flash Loan Premium in EMI (vuln-22) ============

    /// @notice Test that estimatedMonthlyPayment * duration covers the actual Bitmor Pool debt
    /// @dev Regression test for vuln-22: EMI was previously computed on loanAmount only,
    ///      but actual debt is loanAmount + flashLoanPremium
    function test_estimatedMonthlyPayment_CoversActualDebt() public {
        // Arrange
        (address lsa, DataTypes.LoanData memory loanData) = _createStandardLoanWithData();
        uint256 actualDebt = _getDebtBalance(lsa);

        // Assert: total scheduled payments must cover the actual debt
        // EMI * duration >= actualDebt (EMI includes interest, so it will exceed principal)
        uint256 totalScheduledPayments = loanData.estimatedMonthlyPayment * loanData.duration;
        assertGe(
            totalScheduledPayments,
            actualDebt,
            "total scheduled payments (EMI * duration) must cover actual Bitmor Pool debt"
        );
    }

    /// @notice Test that EMI is higher when flash loan premium is higher
    /// @dev Proves the flash loan premium is factored into the EMI calculation
    function test_estimatedMonthlyPayment_IncreasesWithHigherFlashLoanPremium() public {
        // Arrange: create loan with default premium (5 bps)
        (address lsa1, DataTypes.LoanData memory loanData1) = _createStandardLoanWithData();

        // Increase flash loan premium to 100 bps (1%)
        mockAavePool.setPremium(100);

        // Create second loan for different borrower (avoid CREATE2 collision)
        address borrower2 = makeAddr("borrower2_premium_test");
        address lsa2 = _createLoanForBorrower(borrower2, STANDARD_COLLATERAL_AMOUNT, STANDARD_DURATION, PREMIUM_AMOUNT);
        DataTypes.LoanData memory loanData2 = loan.getLoanByLSA(lsa2);

        // Assert: higher flash loan premium produces higher EMI
        assertGt(
            loanData2.estimatedMonthlyPayment,
            loanData1.estimatedMonthlyPayment,
            "higher flash loan premium should produce higher EMI"
        );
    }

    /// @notice Test that getLoanDetails preview EMI accounts for flash loan premium
    /// @dev Verifies the preview path also includes the flash loan premium
    function test_getLoanDetails_EMI_IncludesFlashLoanPremium() public {
        uint256 collateral = STANDARD_COLLATERAL_AMOUNT;
        uint256 duration = STANDARD_DURATION;

        // Get preview with default premium (5 bps)
        (, uint256 emiLowPremium,) = loan.getLoanDetails(collateral, duration);

        // Increase flash loan premium to 100 bps (1%)
        mockAavePool.setPremium(100);

        (, uint256 emiHighPremium,) = loan.getLoanDetails(collateral, duration);

        // Assert: higher premium produces higher preview EMI
        assertGt(emiHighPremium, emiLowPremium, "preview EMI should increase with higher flash loan premium");
    }
}
