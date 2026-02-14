// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {LoanUnitTestBase} from "../../base/LoanUnitTestBase.sol";
import {DataTypes} from "@bitmor/libraries/types/DataTypes.sol";
import {Errors} from "@bitmor/libraries/helpers/Errors.sol";

/**
 * @title RepayLoanFuzzTest
 * @author Bitmor Protocol
 * @notice Stateless fuzz tests for `Loan.repay()` via `RepayLogic.executeRepay()`
 * @dev Tests 9 properties covering collateral safety, token accounting, full repayment,
 *      completion sealing, payment splitting, cumulative extraction, ordering independence,
 *      dust resilience, and refund precision.
 *
 * @custom:audit-category Financial Safety, Storage Integrity, Token Accounting
 */
contract RepayLoanFuzzTest is LoanUnitTestBase {
    // ============ Helpers ============

    /**
     * @notice Funds user with USDC and approves the Loan contract for repayment
     * @param amount Amount of USDC to fund
     */
    function _fundUserForRepay(uint256 amount) internal {
        _fundUSDC(user, amount);
        vm.prank(user);
        mockUSDC.approve(address(loan), type(uint256).max);
    }

    // ============ Tests ============

    /**
     * @notice A partial repayment must never modify the collateral aToken balance,
     *         and the loan must remain in Active status.
     * @dev Guards against the partial-repay branch accidentally entering the
     *      full-repay code path (totalDebtRemaining == 0 check at RepayLogic.sol:89).
     * @param repayAmountSeed Seed for bounded partial repay amount
     * @custom:audit-property Collateral untouched for partial repay
     * @custom:audit-category Financial Safety
     * @custom:audit-severity Critical
     */
    function testFuzz_repay_CollateralUntouchedForPartialRepay(uint256 repayAmountSeed) public {
        address lsa = _createStandardLoan();
        uint256 totalDebt = _getDebtBalance(lsa);
        uint256 collateralBefore = _getCollateralBalance(lsa);

        uint256 repayAmount = bound(repayAmountSeed, 1, totalDebt - 1);

        _fundUserForRepay(repayAmount);
        vm.prank(user);
        loan.repay(lsa, repayAmount);

        uint256 collateralAfter = _getCollateralBalance(lsa);
        DataTypes.LoanData memory loanData = loan.getLoanByLSA(lsa);

        assertEq(collateralAfter, collateralBefore, "collateral must not change on partial repay");
        assertEq(uint256(loanData.status), uint256(DataTypes.LoanStatus.Active), "loan must remain Active");
    }

    /**
     * @notice The Loan contract's USDC balance must be unchanged after any repay call,
     *         including amounts that exceed total debt. All tokens must flow through
     *         to the pool or be refunded to the payer.
     * @dev Catches token leak or fund locking from off-by-one in the refund logic
     *      at RepayLogic.sol:114-117.
     * @param repayAmountSeed Seed for bounded repay amount (includes overpayment range)
     * @custom:audit-property No tokens stuck in Loan contract
     * @custom:audit-category Token Accounting
     * @custom:audit-severity Critical
     */
    function testFuzz_repay_NoTokensStuckInLoanContract(uint256 repayAmountSeed) public {
        address lsa = _createStandardLoan();
        uint256 totalDebt = _getDebtBalance(lsa);

        // Include overpayment range to test the cap + refund path
        uint256 repayAmount = bound(repayAmountSeed, 1, totalDebt * 2);

        uint256 loanBalanceBefore = mockUSDC.balanceOf(address(loan));

        _fundUserForRepay(repayAmount);
        vm.prank(user);
        loan.repay(lsa, repayAmount);

        uint256 loanBalanceAfter = mockUSDC.balanceOf(address(loan));

        assertEq(loanBalanceAfter, loanBalanceBefore, "Loan contract must not retain any USDC");
    }

    /**
     * @notice Any repayment amount >= total debt must result in Completed status, zero
     *         duration, zero remaining debt, zero LSA collateral, and BTC returned to borrower.
     * @dev Fuzzed excess above debt tests that over-payment is handled gracefully.
     *      The cap at RepayLogic.sol:74 ensures only actual debt is pulled.
     * @param excessSeed Seed for bounded excess above total debt
     * @custom:audit-property Full repayment always completes cleanly
     * @custom:audit-category Financial Safety
     * @custom:audit-severity Critical
     */
    function testFuzz_repay_FullRepaymentAlwaysCompletes(uint256 excessSeed) public {
        address lsa = _createStandardLoan();
        uint256 totalDebt = _getDebtBalance(lsa);
        uint256 userBtcBefore = mockCbBTC.balanceOf(user);

        uint256 excess = bound(excessSeed, 0, totalDebt);
        uint256 repayAmount = totalDebt + excess;

        _fundUserForRepay(repayAmount);
        vm.prank(user);
        loan.repay(lsa, repayAmount);

        DataTypes.LoanData memory loanData = loan.getLoanByLSA(lsa);

        assertEq(uint256(loanData.status), uint256(DataTypes.LoanStatus.Completed), "status must be Completed");
        assertEq(loanData.duration, 0, "duration must be 0");
        assertEq(_getDebtBalance(lsa), 0, "remaining debt must be 0");
        assertEq(_getCollateralBalance(lsa), 0, "LSA collateral must be 0");
        assertGt(mockCbBTC.balanceOf(user), userBtcBefore, "user must receive BTC collateral back");
    }

    /**
     * @notice Once a loan is fully repaid and marked Completed, any subsequent repay
     *         attempt must revert with LoanIsNotActive. A completed loan must be
     *         permanently sealed against re-entry.
     * @dev Tests the status gate at RepayLogic.sol:70.
     * @param secondAmountSeed Seed for bounded second repay attempt amount
     * @custom:audit-property Completed loan is permanently sealed
     * @custom:audit-category Storage Integrity
     * @custom:audit-severity Critical
     */
    function testFuzz_repay_RevertsAfterCompletion(uint256 secondAmountSeed) public {
        address lsa = _createStandardLoan();
        uint256 totalDebt = _getDebtBalance(lsa);

        // First: fully repay the loan
        _fundUserForRepay(totalDebt);
        vm.prank(user);
        loan.repay(lsa, totalDebt);

        // Verify precondition
        DataTypes.LoanData memory loanData = loan.getLoanByLSA(lsa);
        assertEq(
            uint256(loanData.status), uint256(DataTypes.LoanStatus.Completed), "precondition: loan must be Completed"
        );

        // Second: any fuzzed amount must revert
        uint256 secondAmount = bound(secondAmountSeed, 1, totalDebt);
        _fundUserForRepay(secondAmount);

        vm.expectRevert(Errors.LoanIsNotActive.selector);
        vm.prank(user);
        loan.repay(lsa, secondAmount);
    }

    /**
     * @notice A single lump payment of amount X must always credit at least as many
     *         periods as splitting X into two separate payments.
     * @dev Tests floor-division sub-additivity: floor((A+B)/m) >= floor(A/m) + floor(B/m).
     *      In practice, the accumulator carry-over means they are always equal, but the
     *      weaker >= property is the safety-critical invariant.
     *      Uses vm.snapshot to compare both paths on identical initial state.
     * @param totalAmountSeed Seed for bounded total repay amount
     * @param splitSeed Seed for bounded split point
     * @custom:audit-property Splitting never credits more periods than lump
     * @custom:audit-category Financial Safety
     * @custom:audit-severity High
     */
    function testFuzz_repay_SplittingNeverCreditsMorePeriods(uint256 totalAmountSeed, uint256 splitSeed) public {
        address lsa = _createStandardLoan();
        DataTypes.LoanData memory loanData = loan.getLoanByLSA(lsa);
        uint256 totalDebt = _getDebtBalance(lsa);
        uint256 initialDuration = loanData.duration;

        // Total must be >= 2 (splittable) and < totalDebt (both paths stay partial)
        uint256 totalAmount = bound(totalAmountSeed, 2, totalDebt - 1);
        uint256 firstPayment = bound(splitSeed, 1, totalAmount - 1);
        uint256 secondPayment = totalAmount - firstPayment;

        uint256 snapId = vm.snapshotState();

        // Path A: Lump payment
        _fundUserForRepay(totalAmount);
        vm.prank(user);
        loan.repay(lsa, totalAmount);
        uint256 periodsLump = initialDuration - loan.getLoanByLSA(lsa).duration;

        vm.revertToState(snapId);

        // Path B: Split payment
        _fundUserForRepay(totalAmount);
        vm.prank(user);
        loan.repay(lsa, firstPayment);
        vm.prank(user);
        loan.repay(lsa, secondPayment);
        uint256 periodsSplit = initialDuration - loan.getLoanByLSA(lsa).duration;

        assertGe(periodsLump, periodsSplit, "lump payment must credit >= periods than split payment");
    }

    /**
     * @notice The total USDC extracted from the payer across two sequential repayments
     *         must never exceed the original debt. This is the core solvency invariant.
     * @dev The first repay is always partial. The second may trigger full repayment
     *      (and collateral withdrawal), which is acceptable. RepayLogic.sol:74 caps
     *      each repay to remaining debt.
     * @param amount1Seed Seed for first repay amount
     * @param amount2Seed Seed for second repay amount
     * @custom:audit-property Cumulative extraction never exceeds debt
     * @custom:audit-category Financial Safety
     * @custom:audit-severity Critical
     */
    function testFuzz_repay_CumulativeExtractionNeverExceedsDebt(uint256 amount1Seed, uint256 amount2Seed) public {
        address lsa = _createStandardLoan();
        uint256 initialDebt = _getDebtBalance(lsa);

        // First repay: always partial
        uint256 amount1 = bound(amount1Seed, 1, initialDebt - 1);
        // Second repay: any amount (capped to remaining debt by RepayLogic)
        uint256 amount2 = bound(amount2Seed, 1, initialDebt);

        _fundUserForRepay(amount1 + amount2);
        uint256 userBalanceBefore = mockUSDC.balanceOf(user);

        vm.prank(user);
        loan.repay(lsa, amount1);

        // Second repay may trigger full repayment
        vm.prank(user);
        loan.repay(lsa, amount2);

        uint256 userBalanceAfter = mockUSDC.balanceOf(user);
        uint256 totalExtracted = userBalanceBefore - userBalanceAfter;

        assertLe(totalExtracted, initialDebt, "cumulative extraction must not exceed initial debt");
    }

    /**
     * @notice Paying amount A then B must produce the exact same final debt, duration,
     *         and accumulator as paying B then A.
     * @dev Order-dependent behavior would indicate hidden side effects between calls.
     *      Uses vm.snapshot to compare both orderings on identical initial state.
     *      Both amounts bounded to totalDebt/3 to guarantee both paths stay fully partial.
     * @param amount1Seed Seed for first repay amount
     * @param amount2Seed Seed for second repay amount
     * @custom:audit-property Repayment ordering independence
     * @custom:audit-category Storage Integrity
     * @custom:audit-severity High
     */
    function testFuzz_repay_OrderingIndependence(uint256 amount1Seed, uint256 amount2Seed) public {
        address lsa = _createStandardLoan();
        uint256 totalDebt = _getDebtBalance(lsa);

        // Both amounts < totalDebt/3 ensures sum < 2/3 debt, both orderings stay partial
        uint256 maxEach = totalDebt / 3;
        uint256 amount1 = bound(amount1Seed, 1, maxEach);
        uint256 amount2 = bound(amount2Seed, 1, maxEach);

        uint256 snapId = vm.snapshotState();

        // Path A: amount1 then amount2
        _fundUserForRepay(amount1 + amount2);
        vm.prank(user);
        loan.repay(lsa, amount1);
        vm.prank(user);
        loan.repay(lsa, amount2);

        DataTypes.LoanData memory afterAB = loan.getLoanByLSA(lsa);
        uint256 debtAfterAB = _getDebtBalance(lsa);

        vm.revertToState(snapId);

        // Path B: amount2 then amount1
        _fundUserForRepay(amount1 + amount2);
        vm.prank(user);
        loan.repay(lsa, amount2);
        vm.prank(user);
        loan.repay(lsa, amount1);

        DataTypes.LoanData memory afterBA = loan.getLoanByLSA(lsa);
        uint256 debtAfterBA = _getDebtBalance(lsa);

        assertEq(debtAfterAB, debtAfterBA, "final debt must be order-independent");
        assertEq(afterAB.duration, afterBA.duration, "final duration must be order-independent");
        assertEq(
            afterAB.amountRepaidInCurrentPeriod,
            afterBA.amountRepaidInCurrentPeriod,
            "accumulator must be order-independent"
        );
    }

    /**
     * @notice Very small repayments (1-256 wei USDC) must not corrupt loan status,
     *         collateral, or duration. With floor division, dust amounts credit zero
     *         periods, so duration must stay unchanged.
     * @dev Tests edge case where floor(dust / estimatedMonthlyPayment) == 0.
     * @param dustSeed Seed for bounded dust amount (1-256 wei)
     * @custom:audit-property Dust repayment does not corrupt state
     * @custom:audit-category Storage Integrity
     * @custom:audit-severity Medium
     */
    function testFuzz_repay_DustRepaymentDoesNotCorruptState(uint256 dustSeed) public {
        address lsa = _createStandardLoan();
        DataTypes.LoanData memory before_ = loan.getLoanByLSA(lsa);
        uint256 collateralBefore = _getCollateralBalance(lsa);
        uint256 loanBalanceBefore = mockUSDC.balanceOf(address(loan));

        uint256 dust = bound(dustSeed, 1, 256);

        _fundUserForRepay(dust);
        vm.prank(user);
        loan.repay(lsa, dust);

        DataTypes.LoanData memory after_ = loan.getLoanByLSA(lsa);

        assertEq(uint256(after_.status), uint256(DataTypes.LoanStatus.Active), "loan must remain Active");
        assertEq(_getCollateralBalance(lsa), collateralBefore, "collateral must not change");
        assertEq(after_.duration, before_.duration, "duration must not change for dust payment");
        assertEq(mockUSDC.balanceOf(address(loan)), loanBalanceBefore, "no tokens stuck in Loan contract");
    }

    /**
     * @notice When the lending pool accepts less than the requested repayment (shortfall),
     *         the payer must only be charged `finalAmountRepaid`, and no tokens should
     *         leak into the Loan contract.
     * @dev Exercises the rarely-hit refund branch at RepayLogic.sol:114-117.
     *      Uses MockBitmorLendingPool.setRepaymentShortfall() to simulate pool shortfall.
     * @param shortfallSeed Seed for bounded shortfall amount
     * @custom:audit-property Refund precision with shortfall
     * @custom:audit-category Token Accounting
     * @custom:audit-severity High
     */
    function testFuzz_repay_RefundPrecisionWithShortfall(uint256 shortfallSeed) public {
        address lsa = _createStandardLoan();
        DataTypes.LoanData memory loanData = loan.getLoanByLSA(lsa);
        uint256 repayAmount = loanData.estimatedMonthlyPayment;

        // Shortfall must be < repayAmount for the mock condition to trigger
        uint256 shortfall = bound(shortfallSeed, 1, repayAmount - 1);

        mockBitmorPool.setRepaymentShortfall(shortfall);

        _fundUserForRepay(repayAmount);
        uint256 userBalanceBefore = mockUSDC.balanceOf(user);
        uint256 loanBalanceBefore = mockUSDC.balanceOf(address(loan));

        vm.prank(user);
        uint256 finalAmountRepaid = loan.repay(lsa, repayAmount);

        uint256 userBalanceAfter = mockUSDC.balanceOf(user);
        uint256 actualTokensSpent = userBalanceBefore - userBalanceAfter;

        assertEq(actualTokensSpent, finalAmountRepaid, "user must only pay what pool accepted");
        assertEq(finalAmountRepaid, repayAmount - shortfall, "finalAmountRepaid must reflect shortfall");
        assertEq(mockUSDC.balanceOf(address(loan)), loanBalanceBefore, "no tokens stuck in Loan contract");

        // Reset shortfall
        mockBitmorPool.setRepaymentShortfall(0);
    }
}
