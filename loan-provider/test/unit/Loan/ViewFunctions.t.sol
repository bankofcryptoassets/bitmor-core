// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.30;

import {BaseLoanTest} from "./BaseLoan.t.sol";
import {Errors} from "@bitmor/libraries/helpers/Errors.sol";
import {DataTypes} from "@bitmor/libraries/types/DataTypes.sol";
import {TestConstants as TC} from "../../helpers/TestConstants.sol";

/// @title ViewFunctionsTest
/// @notice Tests for Loan contract view/getter functions
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
        assertEq(loan.getPremiumCollector(), premiumCollector, "Premium collector mismatch");

        // Verify against exact config values from HelperConfig
        assertEq(loan.getGracePeriod(), config.getGracePeriod(), "Grace period should match config");
        assertEq(loan.getLiquidationBuffer(), config.getLiquidationBuffer(), "Liquidation buffer should match config");
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
        assertEq(data.collateralAmount, collateral, "Collateral should match exact input");
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
        assertEq(userLoans[0].collateralAmount, STANDARD_COLLATERAL_AMOUNT, "Collateral should match");

        // Verify borrower2's loans
        DataTypes.LoanData[] memory borrower2Loans = loan.getUserAllLoans(borrower2);
        assertEq(borrower2Loans.length, 1, "Borrower2 should have 1 loan");
        assertEq(borrower2Loans[0].borrower, borrower2, "Loan borrower should match borrower2");
        assertEq(borrower2Loans[0].collateralAmount, STANDARD_COLLATERAL_AMOUNT / 2, "Collateral should match");
    }
}
