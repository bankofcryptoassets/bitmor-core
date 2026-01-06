// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.30;

import {BaseLoanTest} from "./BaseLoan.t.sol";
import {DataTypes} from "@bitmor/libraries/types/DataTypes.sol";
import {IERC20} from "@bitmor/dependencies/openzeppelin/IERC20.sol";
import {ILendingPool} from "@bitmor/interfaces/ILendingPool.sol";
import {Errors} from "@bitmor/libraries/helpers/Errors.sol";

/// @title RepayLoanTest
/// @notice Tests for loan repayment functionality
contract RepayLoanTest is BaseLoanTest {
    // ============ Local Structs ============

    /// @dev Struct to hold repayment test state for cleaner assertions
    struct RepaymentState {
        address lsa;
        uint256 durationBefore;
        uint256 durationAfter;
        uint256 debtBefore;
        uint256 debtAfter;
        uint256 estimatedMonthlyPayment;
        uint256 repayAmount;
        uint256 finalAmountRepaid;
        DataTypes.LoanStatus statusAfter;
    }

    // ============ Local Helpers ============

    /// @dev Execute repayment and return state snapshot
    function _repayAndFetch(address lsa, uint256 repayAmount) internal returns (RepaymentState memory state) {
        DataTypes.LoanData memory loanDataBefore = loan.getLoanByLSA(lsa);

        state.lsa = lsa;
        state.durationBefore = loanDataBefore.duration;
        state.estimatedMonthlyPayment = loanDataBefore.estimatedMonthlyPayment;
        state.debtBefore = _getDebtBalance(lsa);
        state.repayAmount = repayAmount;

        vm.prank(user);
        state.finalAmountRepaid = loan.repay(lsa, repayAmount);

        DataTypes.LoanData memory loanDataAfter = loan.getLoanByLSA(lsa);
        state.durationAfter = loanDataAfter.duration;
        state.debtAfter = _getDebtBalance(lsa);
        state.statusAfter = loanDataAfter.status;
    }

    /// @dev Assert duration was reduced by expected periods
    function _assertDurationReduced(RepaymentState memory state, uint256 expectedPeriodsPaid) internal pure {
        uint256 actualPeriodsPaid = state.durationBefore - state.durationAfter;
        assertEq(actualPeriodsPaid, expectedPeriodsPaid, "Duration reduction mismatch");
    }

    /// @dev Assert debt delta matches repaid amount
    function _assertDebtDelta(RepaymentState memory state) internal pure {
        uint256 debtReduction = state.debtBefore - state.debtAfter;
        assertEq(debtReduction, state.finalAmountRepaid, "Debt delta mismatch");
    }

    /// @dev Assert loan is still active
    function _assertLoanActive(RepaymentState memory state) internal pure {
        assertEq(uint256(state.statusAfter), uint256(DataTypes.LoanStatus.Active), "Loan should be active");
    }

    /// @dev Assert loan is completed
    function _assertLoanCompleted(RepaymentState memory state) internal pure {
        assertEq(uint256(state.statusAfter), uint256(DataTypes.LoanStatus.Completed), "Loan should be completed");
    }

    // ============ Loan Repayment Tests ============

    /// @notice Test repaying exactly one month's estimated payment
    function test_repay_exactlyEstimatedMonthlyAmount() public setUpLoanForUser {
        address lsa = loan.getUserLoanAtIndex(user, 0);
        DataTypes.LoanData memory loanData = loan.getLoanByLSA(lsa);

        RepaymentState memory state = _repayAndFetch(lsa, loanData.estimatedMonthlyPayment);
        uint256 periodsPaidFor = state.finalAmountRepaid / state.estimatedMonthlyPayment;

        _assertDurationReduced(state, periodsPaidFor);
        assertEq(state.finalAmountRepaid, state.repayAmount, "Should repay exact amount");
        assertLt(state.debtAfter, state.debtBefore, "Debt should decrease");
        _assertDebtDelta(state);
        _assertLoanActive(state);
    }

    /// @notice Test repaying less than one month's estimated payment
    function test_repay_lessThanEstimatedMonthlyAmount() public setUpLoanForUser {
        address lsa = loan.getUserLoanAtIndex(user, 0);
        DataTypes.LoanData memory loanData = loan.getLoanByLSA(lsa);
        uint256 repayAmount = loanData.estimatedMonthlyPayment - 1;

        RepaymentState memory state = _repayAndFetch(lsa, repayAmount);
        uint256 periodsPaidFor = state.finalAmountRepaid / state.estimatedMonthlyPayment;

        assertEq(periodsPaidFor, 0, "Should pay for 0 periods");
        _assertDurationReduced(state, 0);
        assertLt(state.debtAfter, state.debtBefore, "Debt should still decrease");
        _assertDebtDelta(state);
        _assertLoanActive(state);
    }

    /// @notice Test repaying more than one month's estimated payment (2x)
    function test_repay_moreThanEstimatedMonthlyAmount() public setUpLoanForUser {
        address lsa = loan.getUserLoanAtIndex(user, 0);
        DataTypes.LoanData memory loanData = loan.getLoanByLSA(lsa);
        uint256 repayAmount = loanData.estimatedMonthlyPayment * 2;

        RepaymentState memory state = _repayAndFetch(lsa, repayAmount);
        uint256 periodsPaidFor = state.finalAmountRepaid / state.estimatedMonthlyPayment;

        assertEq(periodsPaidFor, 2, "Should pay for 2 periods");
        _assertDurationReduced(state, 2);
        _assertDebtDelta(state);
        _assertLoanActive(state);
    }

    /// @notice Test paying 4 months in a single transaction
    function test_repay_multipleMonthsAtOnce() public setUpLoanForUser {
        address lsa = loan.getUserLoanAtIndex(user, 0);
        DataTypes.LoanData memory loanData = loan.getLoanByLSA(lsa);
        uint256 monthsToPay = 4;
        uint256 repayAmount = loanData.estimatedMonthlyPayment * monthsToPay;

        RepaymentState memory state = _repayAndFetch(lsa, repayAmount);
        uint256 periodsPaidFor = state.finalAmountRepaid / state.estimatedMonthlyPayment;

        assertEq(periodsPaidFor, monthsToPay, "Should pay for 4 periods");
        _assertDurationReduced(state, monthsToPay);
        assertEq(state.durationAfter, 8, "Should have 8 months remaining");
        _assertDebtDelta(state);
        _assertLoanActive(state);
    }

    /// @notice Test paying 3.5 months worth - verifies floor division behavior
    function test_repay_multipleMonthsWithRemainder() public setUpLoanForUser {
        address lsa = loan.getUserLoanAtIndex(user, 0);
        DataTypes.LoanData memory loanData = loan.getLoanByLSA(lsa);
        uint256 repayAmount = (loanData.estimatedMonthlyPayment * 7) / 2; // 3.5 months

        RepaymentState memory state = _repayAndFetch(lsa, repayAmount);
        uint256 periodsPaidFor = state.finalAmountRepaid / state.estimatedMonthlyPayment;

        assertEq(periodsPaidFor, 3, "Should pay for 3 periods (floor of 3.5)");
        _assertDurationReduced(state, 3);
        assertEq(state.durationAfter, 9, "Should have 9 months remaining");
        _assertDebtDelta(state);
        _assertLoanActive(state);
    }

    /// @notice Test pre-paying the entire loan early
    function test_repay_entireLoanEarly() public setUpLoanForUser {
        address lsa = loan.getUserLoanAtIndex(user, 0);
        uint256 debtBalanceBefore = _getDebtBalance(lsa);
        uint256 collateralBalanceBefore = _getCollateralBalance(lsa);
        uint256 userCollateralBefore = IERC20(collateralAsset).balanceOf(user);

        assertGt(debtBalanceBefore, 0, "Should have debt before repayment");
        assertGt(collateralBalanceBefore, 0, "LSA should have collateral");

        RepaymentState memory state = _repayAndFetch(lsa, debtBalanceBefore);

        uint256 collateralBalanceAfter = _getCollateralBalance(lsa);
        uint256 userCollateralAfter = IERC20(collateralAsset).balanceOf(user);

        _assertLoanCompleted(state);
        assertEq(state.durationAfter, 0, "Duration should be 0");
        assertEq(state.debtAfter, 0, "Debt should be 0");
        assertEq(collateralBalanceAfter, 0, "LSA collateral should be 0");
        assertGt(userCollateralAfter, userCollateralBefore, "User should receive collateral");
        assertEq(
            userCollateralAfter - userCollateralBefore,
            collateralBalanceBefore,
            "User should receive all LSA collateral"
        );
    }

    /// @notice Test attempting to repay more than total debt
    function test_repay_moreThanTotalDebt() public setUpLoanForUser {
        address lsa = loan.getUserLoanAtIndex(user, 0);
        uint256 debtBalanceBefore = _getDebtBalance(lsa);
        uint256 userDebtAssetBefore = IERC20(debtAsset).balanceOf(user);
        uint256 excessiveRepayAmount = debtBalanceBefore * 2;

        RepaymentState memory state = _repayAndFetch(lsa, excessiveRepayAmount);
        uint256 userDebtAssetAfter = IERC20(debtAsset).balanceOf(user);

        assertEq(state.finalAmountRepaid, debtBalanceBefore, "Should cap at actual debt");
        assertLt(state.finalAmountRepaid, excessiveRepayAmount, "Should repay less than requested");
        assertEq(state.debtAfter, 0, "Debt should be 0");
        _assertLoanCompleted(state);
        assertEq(
            userDebtAssetBefore - userDebtAssetAfter, debtBalanceBefore, "User should only spend actual debt amount"
        );
    }

    /// @notice Test utilization-based interest accrual
    function test_repay_utilizationBasedInterest() public setUpLoanForUser {
        address lsa = loan.getUserLoanAtIndex(user, 0);
        uint256 debtBalanceAtStart = _getDebtBalance(lsa);

        // Get initial interest rate
        DataTypes.ReserveData memory reserveData = ILendingPool(s_bitmorPool).getReserveData(debtAsset);
        uint256 initialBorrowRate = reserveData.currentVariableBorrowRate;

        // Warp 30 days
        uint256 timeElapsed = 30 days;
        vm.warp(block.timestamp + timeElapsed);

        uint256 debtBalanceAfterTime = _getDebtBalance(lsa);

        assertGt(debtBalanceAfterTime, debtBalanceAtStart, "Debt should increase due to interest");

        uint256 interestAccrued = debtBalanceAfterTime - debtBalanceAtStart;
        assertGt(interestAccrued, 0, "Interest should be non-zero");

        // Verify interest approximates expected rate
        uint256 expectedInterestApprox = (debtBalanceAtStart * initialBorrowRate * timeElapsed) / (365 days * RAY);
        uint256 tolerance = expectedInterestApprox / 10 + 1;
        assertApproxEqAbs(interestAccrued, expectedInterestApprox, tolerance, "Interest should match expected");

        // Repay full debt including interest
        RepaymentState memory state = _repayAndFetch(lsa, debtBalanceAfterTime);

        assertGt(state.finalAmountRepaid, debtBalanceAtStart, "Repaid should exceed original principal");
        _assertLoanCompleted(state);
    }

    /// @notice Test final month reconciliation
    function test_repay_finalMonthReconciliation() public setUpLoanForUser {
        address lsa = loan.getUserLoanAtIndex(user, 0);
        DataTypes.LoanData memory loanData = loan.getLoanByLSA(lsa);

        uint256 estimatedMonthly = loanData.estimatedMonthlyPayment;
        uint256 initialDuration = loanData.duration;

        // Pay for 11 months (leave 1 month remaining)
        uint256 monthsToPay = initialDuration - 1;
        uint256 repayAmount = estimatedMonthly * monthsToPay;

        vm.prank(user);
        loan.repay(lsa, repayAmount);

        uint256 remainingDebt = _getDebtBalance(lsa);
        DataTypes.LoanData memory loanDataMid = loan.getLoanByLSA(lsa);

        assertEq(loanDataMid.duration, 1, "Should have 1 month remaining");
        assertEq(uint256(loanDataMid.status), uint256(DataTypes.LoanStatus.Active), "Should be active");

        uint256 userBalanceBefore = IERC20(debtAsset).balanceOf(user);

        // Final payment
        vm.prank(user);
        uint256 finalAmountRepaid = loan.repay(lsa, remainingDebt);

        uint256 userBalanceAfter = IERC20(debtAsset).balanceOf(user);
        DataTypes.LoanData memory loanDataAfter = loan.getLoanByLSA(lsa);

        assertEq(uint256(loanDataAfter.status), uint256(DataTypes.LoanStatus.Completed), "Should be completed");
        assertEq(_getDebtBalance(lsa), 0, "No debt should remain");
        assertEq(userBalanceBefore - userBalanceAfter, finalAmountRepaid, "User should pay exact remaining debt");
        assertEq(finalAmountRepaid, remainingDebt, "Final payment should equal remaining debt");
    }

    /// @notice Test repay after grace period but before liquidation
    function test_repay_afterGracePeriod() public setUpLoanForUser {
        address lsa = loan.getUserLoanAtIndex(user, 0);
        DataTypes.LoanData memory loanDataBefore = loan.getLoanByLSA(lsa);

        assertEq(uint256(loanDataBefore.status), uint256(DataTypes.LoanStatus.Active), "Should be active");

        uint256 debtBalanceBefore = _getDebtBalance(lsa);

        _warpPastGracePeriod();

        // Verify still active (liquidation not triggered)
        DataTypes.LoanData memory loanDataAfterWarp = loan.getLoanByLSA(lsa);
        assertEq(uint256(loanDataAfterWarp.status), uint256(DataTypes.LoanStatus.Active), "Should still be active");

        // Interest should have accrued
        uint256 debtBalanceAfterWarp = _getDebtBalance(lsa);
        assertGt(debtBalanceAfterWarp, debtBalanceBefore, "Debt should increase due to interest");

        // Repayment should still work
        uint256 repayAmount = loanDataBefore.estimatedMonthlyPayment;

        vm.prank(user);
        uint256 finalAmountRepaid = loan.repay(lsa, repayAmount);

        assertEq(finalAmountRepaid, repayAmount, "Repayment should succeed");

        DataTypes.LoanData memory loanDataAfterRepay = loan.getLoanByLSA(lsa);
        assertLt(loanDataAfterRepay.duration, loanDataAfterWarp.duration, "Duration should decrease");
        assertEq(uint256(loanDataAfterRepay.status), uint256(DataTypes.LoanStatus.Active), "Should still be active");
    }

    // ============ Zero Amount Reverts ============

    /// @notice Test that zero repayment amount reverts
    function test_repay_zeroAmount_reverts() public setUpLoanForUser {
        address lsa = loan.getUserLoanAtIndex(user, 0);

        DataTypes.LoanData memory loanData = loan.getLoanByLSA(lsa);
        assertEq(uint256(loanData.status), uint256(DataTypes.LoanStatus.Active), "Should be active");

        vm.prank(user);
        vm.expectRevert(Errors.ZeroAmount.selector);
        loan.repay(lsa, 0);
    }

    // ============ Completed/Liquidated Loan Reverts ============

    /// @notice Test that repaying a completed loan reverts
    function test_repay_completedLoan_reverts() public setUpLoanForUser {
        address lsa = loan.getUserLoanAtIndex(user, 0);
        uint256 totalDebt = _getDebtBalance(lsa);

        vm.prank(user);
        loan.repay(lsa, totalDebt);

        DataTypes.LoanData memory loanDataAfter = loan.getLoanByLSA(lsa);
        assertEq(uint256(loanDataAfter.status), uint256(DataTypes.LoanStatus.Completed), "Should be completed");

        vm.prank(user);
        vm.expectRevert(Errors.LoanIsNotActive.selector);
        loan.repay(lsa, 1000e6);
    }

    /// @notice Test that repaying a liquidated loan reverts
    function test_repay_liquidatedLoan_reverts() public setUpLoanForUser {
        address lsa = loan.getUserLoanAtIndex(user, 0);

        DataTypes.LoanData memory loanDataBefore = loan.getLoanByLSA(lsa);
        assertEq(uint256(loanDataBefore.status), uint256(DataTypes.LoanStatus.Active), "Should be active");

        _updateAddressesProviderBitmorLoan();
        _warpPastGracePeriod();
        _fundLiquidator();
        _dropOraclePrice(collateralAsset, 50);
        _executeFullLiquidation(lsa, type(uint256).max, false);

        DataTypes.LoanData memory loanDataAfterLiq = loan.getLoanByLSA(lsa);
        assertEq(uint256(loanDataAfterLiq.status), uint256(DataTypes.LoanStatus.Liquidated), "Should be liquidated");

        vm.prank(user);
        vm.expectRevert(Errors.LoanIsNotActive.selector);
        loan.repay(lsa, 1000e6);
    }
}
