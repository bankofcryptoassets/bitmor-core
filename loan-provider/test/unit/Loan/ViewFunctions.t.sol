// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.30;

import {BaseLoanTest} from "./BaseLoan.t.sol";
import {Errors} from "@bitmor/libraries/helpers/Errors.sol";
import {DataTypes} from "@bitmor/libraries/types/DataTypes.sol";

/// @title ViewFunctionsTest
/// @notice Tests for Loan contract view/getter functions
contract ViewFunctionsTest is BaseLoanTest {
    function setUp() public override {
        super.setUp();
    }

    // ============ Getter Verification ============

    function test_getters_returnConstructorValues() public view {
        assertEq(loan.getCollateralAsset(), address(mockBTCVault));
        assertEq(loan.getDebtAsset(), address(mockUSDC));
        assertGt(loan.getGracePeriod(), 0);
        assertEq(loan.getPremiumCollector(), premiumCollector);
        assertEq(loan.getRepaymentInterval(), 30 days);
        assertGt(loan.getPreClosureFee(), 0);
        assertGt(loan.getLiquidationBuffer(), 0);
        assertGt(loan.getSlippageForSwap(), 0);
        assertGt(loan.getMaxBTCAmount(), 0);
        assertGt(loan.getMinBTCAmount(), 0);
        assertGt(loan.getMinDepositBps(), 0);
        // This getter was missing coverage - ensure it's callable
        loan.getSlippageForSharesToAsset();
    }

    // ============ User Loan Functions ============

    function test_getUserLoanAtIndex_outOfBounds_reverts() public {
        // User has no loans
        vm.expectRevert(Errors.IndexOutOfBounds.selector);
        loan.getUserLoanAtIndex(user, 0);

        // Create a loan
        _createStandardLoan();

        // Index 1 is out of bounds (only index 0 exists)
        vm.expectRevert(Errors.IndexOutOfBounds.selector);
        loan.getUserLoanAtIndex(user, 1);
    }

    function test_getUserLoanCount_noLoans_returnsZero() public view {
        uint256 count = loan.getUserLoanCount(address(0xdead));
        assertEq(count, 0, "User with no loans should return 0");
    }

    function test_getUserAllLoans_noLoans_returnsEmptyArray() public view {
        DataTypes.LoanData[] memory loans = loan.getUserAllLoans(address(0xdead));
        assertEq(loans.length, 0, "Should return empty array");
    }

    // ============ Loan Data Verification ============

    function test_getLoanByLSA_returnsCompleteData() public {
        address lsa = _createStandardLoan();

        DataTypes.LoanData memory data = loan.getLoanByLSA(lsa);

        assertEq(data.borrower, user, "Borrower should match");
        assertGt(data.collateralAmount, 0, "Collateral should be set");
        assertGt(data.loanAmount, 0, "Loan amount should be set");
        assertGt(data.duration, 0, "Duration should be set");
        assertGt(data.estimatedMonthlyPayment, 0, "Monthly payment should be set");
        assertEq(uint8(data.status), uint8(DataTypes.LoanStatus.Active), "Status should be Active");
    }
}
