// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {LoanUnitTestBase} from "../../base/LoanUnitTestBase.sol";
import {FuzzConstants as FC} from "../helpers/FuzzConstants.sol";
import {TestConstants as TC} from "../../helpers/TestConstants.sol";
import {DataTypes} from "@bitmor/libraries/types/DataTypes.sol";
import {Errors} from "@bitmor/libraries/helpers/Errors.sol";

/**
 * @title CloseLoanFuzzTest
 * @author Bitmor Protocol
 * @notice Stateless fuzz tests for `Loan.closeLoan()` via `CloseLoanLogic.executeCloseLoan()`
 *         and `FlashLoanLogic.executeFLOperationCloseLoan()`
 * @dev Tests 4 properties covering state transition invariants, insufficient collateral revert,
 *      fee independence from repayment history, and cross-lifecycle integrity after partial
 *      repayment.
 *
 *      Three additional tests from the original plan were dropped during review:
 *      - WithdrawalModeEquivalence: Mock swap's 0.5% discount makes USD equivalence unprovable
 *      - EquityConservation: Cross-denomination USD conservation fails with mock swap pricing
 *      - CombinedParameters: BTC conservation trivially true; dust check needs tolerance
 *      See FUZZ_TESTS.md for full rationale.
 *
 * @custom:audit-category State Machine, Financial Safety, Cross-Lifecycle Integrity
 */
contract CloseLoanFuzzTest is LoanUnitTestBase {
    // ============ Bound Helpers ============

    /**
     * @notice Bounds collateral to the Loan contract's configured min/max range
     * @param raw Raw fuzz input to bound
     */
    function _boundCollateral(uint256 raw) internal view returns (uint256) {
        return bound(raw, loan.getMinBTCAmount(), loan.getMaxBTCAmount());
    }

    /**
     * @notice Bounds duration to valid range (1-60 months)
     * @param raw Raw fuzz input to bound
     */
    function _boundDuration(uint256 raw) internal pure returns (uint256) {
        return bound(raw, FC.MIN_DURATION, FC.MAX_DURATION);
    }

    /**
     * @notice Funds user with USDC and approves the loan contract for max spending
     * @param amount Amount of USDC to fund
     */
    function _fundAndApprove(uint256 amount) internal {
        _fundUSDC(user, amount);
        vm.prank(user);
        mockUSDC.approve(address(loan), type(uint256).max);
    }

    /**
     * @notice Creates a loan with specified collateral and duration using minimum deposit
     * @param collateral Collateral amount in cbBTC (8 decimals)
     * @param duration Loan duration in months
     * @return lsa The deployed Loan Smart Account address
     */
    function _createLoanWithParams(uint256 collateral, uint256 duration) internal returns (address lsa) {
        (,, uint256 minDeposit) = loan.getLoanDetails(collateral, duration);
        _fundAndApprove(minDeposit + TC.USER_USDC_BALANCE);
        vm.prank(user);
        lsa = loan.initializeLoan(minDeposit, 0, collateral, duration, "");
    }

    /**
     * @notice Returns the minimum of two values
     */
    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    // ============ Tests ============

    /**
     * @notice Closing an active loan — with any combination of collateral size, duration,
     *         withdrawal mode, and elapsed time — must always produce Completed status
     *         with zero debt, zero collateral, and zero duration. A completed loan must
     *         reject any subsequent repay attempt.
     * @dev Explores the full parameter cube that unit tests only cover at 1 BTC / 12 months.
     *      Catches arithmetic overflow/underflow in the close flow at extreme parameter
     *      combinations.
     * @param collateralSeed Seed for bounded collateral amount
     * @param durationSeed Seed for bounded duration
     * @param withdrawInBTC Whether to withdraw in BTC or USDC
     * @param elapsedDaysSeed Seed for bounded elapsed days before closing
     * @custom:audit-property State transition invariants on close
     * @custom:audit-category State Machine
     * @custom:audit-severity Critical
     */
    function testFuzz_closeLoan_StateTransitionInvariants(
        uint256 collateralSeed,
        uint256 durationSeed,
        bool withdrawInBTC,
        uint256 elapsedDaysSeed
    ) public {
        uint256 collateral = _boundCollateral(collateralSeed);
        uint256 duration = _boundDuration(durationSeed);
        uint256 elapsedDays = bound(elapsedDaysSeed, 0, 365);

        address lsa = _createLoanWithParams(collateral, duration);

        // Warp forward by fuzzed elapsed time
        if (elapsedDays > 0) {
            vm.warp(block.timestamp + elapsedDays * 1 days);
        }

        // Close the loan
        vm.prank(user);
        loan.closeLoan(lsa, withdrawInBTC);

        // Assert terminal state
        DataTypes.LoanData memory loanData = loan.getLoanByLSA(lsa);
        assertEq(uint256(loanData.status), uint256(DataTypes.LoanStatus.Completed), "status must be Completed");
        assertEq(loanData.duration, 0, "duration must be zero after close");

        uint256 debtAfter = mockDebtTokenUSDC.balanceOf(lsa);
        assertEq(debtAfter, 0, "debt must be zero after close");

        uint256 collateralAfter = mockATokenBvBTC.balanceOf(lsa);
        assertEq(collateralAfter, 0, "collateral (aTokens) must be zero after close");

        // Completed loan must reject subsequent repay
        _fundUSDC(user, 1e6);
        vm.expectRevert(Errors.LoanIsNotActive.selector);
        vm.prank(user);
        loan.repay(lsa, 1e6);
    }

    /**
     * @notice When BTC price drops by 72–95%, the remaining collateral value falls below
     *         total debt + fees + flash loan premium, making it impossible to close.
     *         The call must always revert with `InsufficientCollateral`.
     * @dev The 72% lower bound is justified because the 30% minimum deposit means debt is
     *      ~70% of collateral value. A 72% price drop leaves collateral at ~28% of original,
     *      well below the ~70% debt. The 72% margin (vs exact 70%) avoids boundary flakiness
     *      from the pre-closure fee and flash loan premium that sit on top of the debt.
     * @param collateralSeed Seed for bounded collateral amount
     * @param durationSeed Seed for bounded duration
     * @param priceDropSeed Seed for bounded price drop percentage (72–95%)
     * @custom:audit-property Insufficient collateral revert
     * @custom:audit-category Financial Safety
     * @custom:audit-severity Critical
     */
    function testFuzz_closeLoan_RevertWhen_InsufficientCollateral(
        uint256 collateralSeed,
        uint256 durationSeed,
        uint256 priceDropSeed
    ) public {
        uint256 collateral = _boundCollateral(collateralSeed);
        uint256 duration = _boundDuration(durationSeed);
        uint256 priceDrop = bound(priceDropSeed, 72, 95);

        address lsa = _createLoanWithParams(collateral, duration);

        // Drop collateral asset (bvBTC) oracle price
        mockOracle.dropPrice(address(mockBTCVault), priceDrop);

        vm.expectRevert(Errors.InsufficientCollateral.selector);
        vm.prank(user);
        loan.closeLoan(lsa, true);
    }

    /**
     * @notice The pre-closure fee is computed from the collateral aToken balance (via
     *         `previewRedeem`), not from the debt. Since `repay()` only reduces debt tokens
     *         and never touches collateral aTokens, the fee must be identical whether you
     *         close immediately or after several monthly payments.
     * @dev Uses `vm.snapshotState` to compare two paths on identical initial state:
     *      Path A closes immediately, Path B makes N repayments then closes.
     *      Fee is measured as the cbBTC balance increase of the premium collector.
     * @param durationSeed Seed for bounded duration (>= 2 for at least 1 repayment)
     * @param numRepaymentsSeed Seed for bounded number of repayments before closing
     * @custom:audit-property Fee independent of repayment history
     * @custom:audit-category Financial Safety
     * @custom:audit-severity High
     */
    function testFuzz_closeLoan_FeeIndependentOfRepaymentHistory(uint256 durationSeed, uint256 numRepaymentsSeed)
        public
    {
        // Need duration >= 2 to allow at least 1 partial repayment before close
        uint256 duration = bound(durationSeed, 2, FC.MAX_DURATION);
        uint256 numRepayments = bound(numRepaymentsSeed, 1, _min(3, duration - 1));

        address lsa = _createLoanWithParams(TC.STANDARD_COLLATERAL, duration);

        DataTypes.LoanData memory loanData = loan.getLoanByLSA(lsa);
        uint256 monthlyPayment = loanData.estimatedMonthlyPayment;
        address collector = loan.getPremiumCollector();

        // Snapshot state after loan creation
        uint256 snapId = vm.snapshotState();

        // --- Path A: Close immediately ---
        uint256 collectorBefore_A = mockCbBTC.balanceOf(collector);

        vm.prank(user);
        loan.closeLoan(lsa, true);

        uint256 fee_A = mockCbBTC.balanceOf(collector) - collectorBefore_A;

        // --- Path B: Make N repayments, then close ---
        vm.revertToState(snapId);

        for (uint256 i = 0; i < numRepayments; i++) {
            _fundUSDC(user, monthlyPayment);
            vm.prank(user);
            loan.repay(lsa, monthlyPayment);
        }

        uint256 collectorBefore_B = mockCbBTC.balanceOf(collector);

        vm.prank(user);
        loan.closeLoan(lsa, true);

        uint256 fee_B = mockCbBTC.balanceOf(collector) - collectorBefore_B;

        assertEq(fee_A, fee_B, "pre-closure fee must be identical regardless of repayment history");
    }

    /**
     * @notice A loan must remain closable after any number of partial repayments
     *         (1 to min(3, duration−1)). After closing, the loan must be in a clean state:
     *         zero debt, zero collateral, Completed status, zero duration.
     * @dev Tests cross-lifecycle state integrity: `repay()` must not leave the loan in a
     *      state that prevents `closeLoan()` from executing correctly. This is the key
     *      interaction test between RepayLogic and CloseLoanLogic/FlashLoanLogic.
     * @param durationSeed Seed for bounded duration (>= 2 for at least 1 repayment)
     * @param numRepaymentsSeed Seed for bounded number of repayments before closing
     * @param withdrawInBTC Whether to withdraw in BTC or USDC
     * @custom:audit-property Cross-lifecycle closability after partial repayment
     * @custom:audit-category Cross-Lifecycle Integrity
     * @custom:audit-severity High
     */
    function testFuzz_closeLoan_AfterPartialRepayment(
        uint256 durationSeed,
        uint256 numRepaymentsSeed,
        bool withdrawInBTC
    ) public {
        uint256 duration = bound(durationSeed, 2, FC.MAX_DURATION);
        uint256 numRepayments = bound(numRepaymentsSeed, 1, _min(3, duration - 1));

        address lsa = _createLoanWithParams(TC.STANDARD_COLLATERAL, duration);

        DataTypes.LoanData memory loanData = loan.getLoanByLSA(lsa);
        uint256 monthlyPayment = loanData.estimatedMonthlyPayment;

        // Make N partial repayments
        for (uint256 i = 0; i < numRepayments; i++) {
            _fundUSDC(user, monthlyPayment);
            vm.prank(user);
            loan.repay(lsa, monthlyPayment);
        }

        // Verify loan is still active after partial repayments
        DataTypes.LoanData memory loanAfterRepay = loan.getLoanByLSA(lsa);
        assertEq(
            uint256(loanAfterRepay.status),
            uint256(DataTypes.LoanStatus.Active),
            "loan must still be Active after partial repayments"
        );

        // Close the loan
        vm.prank(user);
        loan.closeLoan(lsa, withdrawInBTC);

        // Assert clean terminal state
        DataTypes.LoanData memory finalData = loan.getLoanByLSA(lsa);
        assertEq(uint256(finalData.status), uint256(DataTypes.LoanStatus.Completed), "status must be Completed");
        assertEq(finalData.duration, 0, "duration must be zero after close");

        uint256 debtAfter = mockDebtTokenUSDC.balanceOf(lsa);
        assertEq(debtAfter, 0, "debt must be zero after close");

        uint256 collateralAfter = mockATokenBvBTC.balanceOf(lsa);
        assertEq(collateralAfter, 0, "collateral must be zero after close");
    }
}
