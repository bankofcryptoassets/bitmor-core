// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.30;

import {IntegrationTestBase} from "../base/IntegrationTestBase.sol";
import {TestConstants as TC} from "../helpers/TestConstants.sol";
import {DataTypes} from "@bitmor/libraries/types/DataTypes.sol";
import {Errors} from "@bitmor/libraries/helpers/Errors.sol";

/// @title LoanLifecycleTest
/// @notice Integration tests for the full loan lifecycle: init -> repay -> close
contract LoanLifecycleTest is IntegrationTestBase {
    function setUp() public override {
        super.setUp();
        _setupTestUser();
    }

    // ============ Loan Initialization ============

    function test_InitializeLoan_CreatesLSA() public {
        address lsa = _createStandardLoan();
        assertTrue(lsa != address(0), "LSA should be deployed");
        assertGt(lsa.code.length, 0, "LSA should have code");
    }

    function test_InitializeLoan_StoresLoanData() public {
        (address lsa, DataTypes.LoanData memory loanData) =
            _createLoanWithData(TC.STANDARD_COLLATERAL, TC.STANDARD_DURATION, TC.PREMIUM_AMOUNT);

        assertEq(loanData.borrower, testUser, "borrower should be testUser");
        assertEq(uint256(loanData.status), uint256(DataTypes.LoanStatus.Active), "loan should be active");
        assertGt(loanData.loanAmount, 0, "loan amount should be > 0");
        assertEq(loanData.duration, TC.STANDARD_DURATION, "duration should match");
    }

    function test_InitializeLoan_TransfersUserDeposit() public {
        uint256 balanceBefore = usdc.balanceOf(testUser);

        _createStandardLoan();

        uint256 balanceAfter = usdc.balanceOf(testUser);
        assertLt(balanceAfter, balanceBefore, "user USDC should decrease after loan init");
    }

    function test_InitializeLoan_MultipleLoansSameUser() public {
        address lsa1 = _createStandardLoan();
        // Advance 1 second so CREATE2 salt (borrower + timestamp) differs
        vm.warp(block.timestamp + 1);
        address lsa2 = _createStandardLoan();

        assertTrue(lsa1 != lsa2, "LSAs should be different addresses");

        DataTypes.LoanData[] memory userLoans = loanContract.getUserAllLoans(testUser);
        assertEq(userLoans.length, 2, "user should have 2 loans");
    }

    // ============ Repayment ============

    function test_Repay_DecreasesRemainingDuration() public {
        (address lsa, DataTypes.LoanData memory loanData) =
            _createLoanWithData(TC.STANDARD_COLLATERAL, TC.STANDARD_DURATION, TC.PREMIUM_AMOUNT);

        // Advance time to next payment window
        _advanceDays(30);

        // Repay one month
        vm.prank(testUser);
        loanContract.repay(lsa, loanData.estimatedMonthlyPayment);

        DataTypes.LoanData memory updatedData = loanContract.getLoanByLSA(lsa);
        assertEq(updatedData.duration, TC.STANDARD_DURATION - 1, "duration should decrease by 1");
    }

    // ============ Reverts ============

    function test_InitializeLoan_RevertWhen_InsufficientDeposit() public {
        (,, uint256 minDeposit) = loanContract.getLoanDetails(TC.STANDARD_COLLATERAL, TC.STANDARD_DURATION);
        uint256 tooSmallDeposit = minDeposit - 1;

        vm.expectRevert(Errors.InsufficientDeposit.selector);
        vm.prank(testUser);
        loanContract.initializeLoan(
            tooSmallDeposit, TC.PREMIUM_AMOUNT, TC.STANDARD_COLLATERAL, TC.STANDARD_DURATION, ""
        );
    }

    // ============ Full Lifecycle ============

    /// @notice Full repayment over `duration` months should complete the loan
    /// @dev Uses upfront funding check instead of per-iteration minting to preserve economic realism
    function test_FullRepaymentCycle_CompletesLoan() public {
        (address lsa, DataTypes.LoanData memory loanData) =
            _createLoanWithData(TC.STANDARD_COLLATERAL, TC.STANDARD_DURATION, TC.PREMIUM_AMOUNT);

        uint256 duration = loanData.duration;
        uint256 monthlyPayment = loanData.estimatedMonthlyPayment;

        // Ensure user has enough USDC for all repayments upfront (no per-loop minting)
        uint256 totalNeeded = monthlyPayment * duration;
        uint256 currentBalance = usdc.balanceOf(testUser);
        if (currentBalance < totalNeeded) {
            _fundUSDC(testUser, totalNeeded - currentBalance);
        }

        for (uint256 i = 0; i < duration; i++) {
            _advanceDays(30);

            vm.prank(testUser);
            loanContract.repay(lsa, monthlyPayment);
        }

        DataTypes.LoanData memory finalData = loanContract.getLoanByLSA(lsa);
        assertEq(uint256(finalData.status), uint256(DataTypes.LoanStatus.Completed), "loan should be completed");
        assertEq(finalData.duration, 0, "remaining duration should be 0");
    }

    /// @notice Early close via flash loan should complete the loan
    /// @dev Calculates needed funds from `loanData.loanAmount` instead of using a magic number
    function test_CloseLoan_EarlyClose() public {
        address lsa = _createStandardLoan();

        // Advance a bit so we're not closing immediately
        _advanceDays(30);

        // Calculate actual debt to determine needed funds (2x buffer for flash loan fees + swap slippage)
        DataTypes.LoanData memory loanData = loanContract.getLoanByLSA(lsa);
        uint256 closeAmount = loanData.loanAmount * 2;
        uint256 currentBalance = usdc.balanceOf(testUser);
        if (currentBalance < closeAmount) {
            _fundUSDC(testUser, closeAmount - currentBalance);
        }

        vm.prank(testUser);
        usdc.approve(address(loanContract), type(uint256).max);

        vm.prank(testUser);
        loanContract.closeLoan(lsa, false);

        DataTypes.LoanData memory finalData = loanContract.getLoanByLSA(lsa);
        assertEq(
            uint256(finalData.status), uint256(DataTypes.LoanStatus.Completed), "loan should be completed after close"
        );
    }
}
