// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.30;

import {IntegrationTestBase} from "../base/IntegrationTestBase.sol";
import {TestConstants as TC} from "../helpers/TestConstants.sol";
import {DataTypes} from "@bitmor/libraries/types/DataTypes.sol";
import {IERC20} from "@openzeppelin/interfaces/IERC20.sol";
import {Errors} from "@bitmor/libraries/helpers/Errors.sol";
import {Pausable} from "@openzeppelin/utils/Pausable.sol";

/// @title RepayTest
/// @author Bitmor Protocol
/// @notice Integration tests for repayment scenarios, edge cases,
///         interest accrual, race conditions, and index invariants.
/// @dev Covers edge cases, interest accrual, race conditions,
///      and BLP index invariants. Run against local Anvil with --fork-url.
contract RepayTest is IntegrationTestBase {
    // ============ Test-Specific Constants ============

    uint256 constant DUST_REPAY_AMOUNT = 1; // 1 wei USDC
    uint256 constant LARGE_OVERPAY_AMOUNT = 10_000e6; // 10,000 USDC
    uint256 constant PARTIAL_REPAY_PERCENT_60 = 60;

    // ============ Setup ============

    function setUp() public override {
        super.setUp();
        _setupLiquidator();
    }

    // ============ Edge Cases (Tests 11-19) ============

    /// @notice Test 11: A 1-wei USDC repayment must not advance the loan period
    function test_DustRepayment_DoesNotAdvancePeriod() public {
        // Arrange
        (address lsa, DataTypes.LoanData memory loanData) = _createStandardLoanWithData();
        uint256 durationBefore = loanData.duration;
        uint256 tsBefore = loanData.lastPaymentTimestamp;

        // Act
        _repayLoan(lsa, testUser, DUST_REPAY_AMOUNT);

        // Assert
        DataTypes.LoanData memory loanDataAfter = loanContract.getLoanByLSA(lsa);
        assertEq(loanDataAfter.duration, durationBefore, "dust repayment must not advance period");
        assertEq(loanDataAfter.amountRepaidInCurrentPeriod, DUST_REPAY_AMOUNT, "accumulator must track 1 wei");
        assertEq(loanDataAfter.lastPaymentTimestamp, tsBefore, "lastPaymentTimestamp must not update for dust");
    }

    /// @notice Test 12: Overpayment beyond total debt must refund excess and complete loan
    function test_OverpaymentRefund_ExactAmount() public {
        // Arrange
        address lsa = _createStandardLoan();
        uint256 totalDebt = _getDebtBalanceUSDC(lsa);

        // Fund extra to cover overpayment
        _fundUSDC(testUser, totalDebt + LARGE_OVERPAY_AMOUNT);

        uint256 usdcBefore = usdc.balanceOf(testUser);

        // Act
        _repayLoan(lsa, testUser, totalDebt + LARGE_OVERPAY_AMOUNT);

        // Assert
        uint256 usdcAfter = usdc.balanceOf(testUser);
        uint256 usdcSpent = usdcBefore - usdcAfter;

        assertApproxEqAbs(
            usdcSpent, totalDebt, TC.MAX_ROUNDING_LOSS_USDC, "user must only spend approximately the debt amount"
        );

        DataTypes.LoanData memory loanData = loanContract.getLoanByLSA(lsa);
        assertEq(uint256(loanData.status), uint256(DataTypes.LoanStatus.Completed), "loan must be completed");
        assertGt(cbBTC.balanceOf(testUser), 0, "collateral must be returned on full repay");
    }

    /// @notice Test 13: Third-party repayment must send collateral to borrower, not payer
    function test_ThirdPartyRepay_CollateralGoesToBorrower() public {
        // Arrange
        address lsa = _createStandardLoan();
        address thirdParty = _setupAdditionalUser("thirdParty");

        uint256 borrowerBTCBefore = cbBTC.balanceOf(testUser);
        uint256 payerBTCBefore = cbBTC.balanceOf(thirdParty);
        uint256 totalDebt = _getDebtBalanceUSDC(lsa);

        // Fund third party with enough to cover debt
        _fundUSDC(thirdParty, totalDebt);
        vm.prank(thirdParty);
        usdc.approve(address(loanContract), type(uint256).max);

        // Act
        _repayLoan(lsa, thirdParty, totalDebt);

        // Assert
        assertGt(cbBTC.balanceOf(testUser), borrowerBTCBefore, "collateral must go to borrower, not payer");
        assertEq(cbBTC.balanceOf(thirdParty), payerBTCBefore, "payer must not receive any collateral");
        assertLt(usdc.balanceOf(thirdParty), TC.USER_USDC_BALANCE + totalDebt, "USDC must be pulled from payer");
    }

    /// @notice Test 14: After micro-liquidation, repayment must correctly track periods
    function test_RepayAfterMicroLiquidation_AccumulatorReset() public {
        // Arrange
        address lsa = _createStandardLoan();

        // Make the first payment overdue (30 days + grace + 1)
        _makeFirstPaymentOverdue();

        bool success = _triggerMicroLiquidation(lsa);
        assertTrue(success, "micro-liquidation must succeed");

        DataTypes.LoanData memory loanDataAfterLiq = loanContract.getLoanByLSA(lsa);
        uint256 tsAfterLiq = loanDataAfterLiq.lastPaymentTimestamp;
        uint256 durationAfterLiq = loanDataAfterLiq.duration;

        assertEq(durationAfterLiq, TC.STANDARD_DURATION - 1, "micro-liq must decrement duration by 1");

        // Advance past next payment interval + grace period
        vm.warp(block.timestamp + TC.REPAYMENT_INTERVAL + config.getGracePeriod() + 1);

        // Act - repay one EMI
        DataTypes.LoanData memory loanDataForRepay = loanContract.getLoanByLSA(lsa);
        _repayLoan(lsa, testUser, loanDataForRepay.estimatedMonthlyPayment);

        // Assert
        DataTypes.LoanData memory loanDataAfterRepay = loanContract.getLoanByLSA(lsa);
        assertEq(loanDataAfterRepay.duration, durationAfterLiq - 1, "repay after micro-liq must correctly decrement");
        assertGt(loanDataAfterRepay.lastPaymentTimestamp, tsAfterLiq, "timestamp must update after repay");
    }

    /// @notice Test 15: Exact monthly payment must advance exactly one period
    function test_RepayExactMonthlyPayment_AdvancesExactlyOnePeriod() public {
        // Arrange
        (address lsa, DataTypes.LoanData memory loanData) = _createStandardLoanWithData();
        uint256 emi = loanData.estimatedMonthlyPayment;
        uint256 durationBefore = loanData.duration;

        // Act
        _repayLoan(lsa, testUser, emi);

        // Assert
        DataTypes.LoanData memory loanDataAfter = loanContract.getLoanByLSA(lsa);
        assertEq(loanDataAfter.duration, durationBefore - 1, "exact monthly payment must decrease duration by 1");
        assertLe(
            loanDataAfter.amountRepaidInCurrentPeriod,
            TC.MAX_ROUNDING_LOSS_USDC,
            "accumulator must be near-zero after full period"
        );
        assertEq(loanDataAfter.lastPaymentTimestamp, block.timestamp, "timestamp must update");
    }

    /// @notice Test 16: Accumulated partial payments crossing period boundary must advance one period with carryover
    function test_AccumulatedPartialPayments_CrossPeriodBoundary() public {
        // Arrange
        (address lsa, DataTypes.LoanData memory loanData) = _createStandardLoanWithData();
        uint256 emi = loanData.estimatedMonthlyPayment;
        uint256 durationBefore = loanData.duration;
        uint256 sixtyPercent = emi * PARTIAL_REPAY_PERCENT_60 / 100;

        // Act - Pay 60%
        _repayLoan(lsa, testUser, sixtyPercent);

        // Assert - 60% must not advance period
        DataTypes.LoanData memory loanDataAfter1 = loanContract.getLoanByLSA(lsa);
        assertEq(loanDataAfter1.duration, durationBefore, "60% must not advance period");

        // Act - Pay another 60% (total 120%)
        _repayLoan(lsa, testUser, sixtyPercent);

        // Assert - 120% accumulated must advance 1 period
        DataTypes.LoanData memory loanDataAfter2 = loanContract.getLoanByLSA(lsa);
        assertEq(loanDataAfter2.duration, durationBefore - 1, "120% accumulated must advance 1 period");

        // Expected carryover is approximately 20% of EMI
        uint256 expectedCarryover = emi * 20 / 100;
        assertApproxEqAbs(
            loanDataAfter2.amountRepaidInCurrentPeriod, expectedCarryover, TC.DEBT_DUST_THRESHOLD, "20% must carry over"
        );
    }

    /// @notice Test 17: Repay while contract is paused must revert; works after unpause
    function test_Repay_RevertWhen_Paused() public {
        // Arrange
        (address lsa, DataTypes.LoanData memory loanData) = _createStandardLoanWithData();

        // Pause (LPM_FAST role - admin has this)
        vm.prank(admin);
        loanContract.pause();

        uint256 usdcBefore = usdc.balanceOf(testUser);

        // Act + Assert - repay must revert while paused
        vm.expectRevert(Pausable.EnforcedPause.selector);
        _repayLoan(lsa, testUser, loanData.estimatedMonthlyPayment);

        assertEq(usdc.balanceOf(testUser), usdcBefore, "USDC must not be spent during paused state");

        // Unpause (LPM_SLOW role - 1-day delay, use _scheduleAndExecute)
        uint64 lpmSlowId = LPM_SLOW_ID();
        bytes memory unpauseData = abi.encodeCall(loanContract.unpause, ());
        _scheduleAndExecute(address(loanContract), admin, lpmSlowId, unpauseData);

        // Act - repay now works
        _repayLoan(lsa, testUser, loanData.estimatedMonthlyPayment);

        // Assert
        DataTypes.LoanData memory loanDataAfter = loanContract.getLoanByLSA(lsa);
        assertEq(loanDataAfter.duration, TC.STANDARD_DURATION - 1, "repay must work after unpause");
    }

    /// @notice Test 18: Full lump-sum repay must return collateral and complete loan
    function test_FullRepay_SingleLumpSum_ReturnsCollateralAndCompletes() public {
        // Arrange
        (address lsa, DataTypes.LoanData memory loanData) = _createStandardLoanWithData();
        uint256 originalCollateral = loanData.btcAmount;
        uint256 totalDebt = _getDebtBalanceUSDC(lsa);

        // Fund extra for full repay
        _fundUSDC(testUser, totalDebt);

        // Act
        uint256 cbBTCBefore = cbBTC.balanceOf(testUser);
        _repayLoan(lsa, testUser, totalDebt);

        // Assert
        DataTypes.LoanData memory loanDataAfter = loanContract.getLoanByLSA(lsa);
        assertEq(uint256(loanDataAfter.status), uint256(DataTypes.LoanStatus.Completed), "loan must be completed");
        assertEq(loanDataAfter.duration, 0, "duration must be zero");
        uint256 cbBTCReturned = cbBTC.balanceOf(testUser) - cbBTCBefore;
        assertGt(cbBTCReturned, 0, "borrower must receive collateral back");
        assertApproxEqRel(
            cbBTCReturned, originalCollateral, 0.02e18, "collateral return must approximate original amount within 2%"
        );
        _assertLoanContractIsEmpty("after full lump-sum repay");
    }

    /// @notice Test 19a: Full repay (total debt) on a 3-month loan after 3 months succeeds
    function test_LargeRepay_FullDebt_CompletesLoan() public {
        // Arrange - 3-month loan
        (address lsa,) = _createLoanWithData(TC.STANDARD_COLLATERAL, 3, TC.PREMIUM_AMOUNT);

        // Advance 3 months
        vm.warp(block.timestamp + TC.THREE_MONTHS);

        // Act - repay full debt
        _fullyRepayLoan(lsa);

        // Assert
        assertEq(
            uint256(loanContract.getLoanByLSA(lsa).status),
            uint256(DataTypes.LoanStatus.Completed),
            "loan must be completed after full debt repay"
        );
    }

    /// @notice Test 19b: Overshoot payment (4x EMI on 3-month loan after 3 months) completes the loan
    /// @dev The protocol caps repayment at total debt rather than reverting on overshoot.
    ///      Excess USDC is refunded to the payer.
    function test_LargePartialRepay_ExceedingRemainingPeriods_CompletesLoan() public {
        // Arrange - 3-month loan
        (address lsa, DataTypes.LoanData memory loanData) =
            _createLoanWithData(TC.STANDARD_COLLATERAL, 3, TC.PREMIUM_AMOUNT);

        // Advance 3 months
        vm.warp(block.timestamp + TC.THREE_MONTHS);

        uint256 emi = loanData.estimatedMonthlyPayment;
        uint256 overshootPayment = 4 * emi;

        // Fund enough for overshoot
        _fundUSDC(testUser, overshootPayment);
        uint256 usdcBefore = usdc.balanceOf(testUser);

        // Act - overshoot payment completes the loan gracefully
        vm.prank(testUser);
        loanContract.repay(lsa, overshootPayment);

        // Assert - loan should be completed (not reverted)
        DataTypes.LoanData memory loanDataAfter = loanContract.getLoanByLSA(lsa);
        assertEq(
            uint256(loanDataAfter.status),
            uint256(DataTypes.LoanStatus.Completed),
            "overshoot payment should complete the loan"
        );

        // Assert - user should not spend more than the actual debt
        uint256 usdcSpent = usdcBefore - usdc.balanceOf(testUser);
        assertLt(usdcSpent, overshootPayment, "user should not spend the full overshoot amount");
    }

    // ============ Interest Accrual (Tests 20-23) ============

    /// @notice Test 20: Debt must grow monotonically over time due to interest
    function test_InterestAccrual_DebtGrows_OverTime() public {
        // Arrange
        address lsa = _createStandardLoan();
        uint256 debtAtInit = _getDebtBalanceUSDC(lsa);
        DataTypes.LoanData memory loanData = loanContract.getLoanByLSA(lsa);

        uint256 prevDebt = debtAtInit;

        // Act + Assert - debt must grow monotonically over 6 months
        for (uint256 i = 0; i < 6; i++) {
            vm.warp(block.timestamp + TC.REPAYMENT_INTERVAL);
            uint256 currentDebt = _getDebtBalanceUSDC(lsa);
            assertGe(currentDebt, prevDebt, "debt must monotonically increase over time");
            prevDebt = currentDebt;
        }

        assertGt(prevDebt, debtAtInit, "6 months of interest must grow debt");
        assertGt(prevDebt, loanData.loanAmount, "actual debt must exceed initial loan amount after 6 months");
    }

    /// @notice Test 21: Late repayment of 3x EMI after 90 days must cover 3 periods (may fail = finding)
    function test_LateRepayment_InterestAccumulation() public {
        // Arrange
        (address lsa, DataTypes.LoanData memory loanData) = _createStandardLoanWithData();
        uint256 emi = loanData.estimatedMonthlyPayment;
        uint256 durationBefore = loanData.duration;

        // Advance 90 days (3 months)
        vm.warp(block.timestamp + TC.THREE_MONTHS);

        // Act - pay 3x EMI
        uint256 tripleEmi = 3 * emi;
        _repayLoan(lsa, testUser, tripleEmi);

        // Assert - 3x EMI must cover 3 periods even after interest growth
        // NOTE: This may FAIL because interest grows debt beyond EMI coverage = security finding
        DataTypes.LoanData memory loanDataAfter = loanContract.getLoanByLSA(lsa);
        assertEq(loanDataAfter.duration, durationBefore - 3, "3x EMI must cover 3 periods even after interest growth");
        assertLe(loanDataAfter.amountRepaidInCurrentPeriod, TC.DEBT_DUST_THRESHOLD, "carryover should be negligible");
    }

    /// @notice Test 22: Micro-liquidation must fail before grace period and succeed after
    function test_GracePeriod_Boundary_MicroLiquidationTiming() public {
        // Arrange
        (address lsa, DataTypes.LoanData memory loanData) = _createStandardLoanWithData();
        uint256 initTs = loanData.lastPaymentTimestamp;

        // Advance to exactly 30 days (end of repayment interval, but before grace)
        vm.warp(initTs + TC.REPAYMENT_INTERVAL);

        // Act - attempt micro-liq before grace period expires
        bool earlySuccess = _triggerMicroLiquidation(lsa);

        // Assert
        assertFalse(earlySuccess, "micro-liquidation must fail before grace period expires");
        assertEq(
            loanContract.getLoanByLSA(lsa).duration,
            TC.STANDARD_DURATION,
            "duration must not change before grace period"
        );

        // Advance past grace period
        vm.warp(initTs + TC.REPAYMENT_INTERVAL + config.getGracePeriod() + 1);

        // Act - micro-liq after grace period
        bool lateSuccess = _triggerMicroLiquidation(lsa);

        // Assert
        assertTrue(lateSuccess, "micro-liquidation must succeed after grace period");
        assertEq(loanContract.getLoanByLSA(lsa).duration, TC.STANDARD_DURATION - 1, "must decrement by 1");
    }

    /// @notice Test 23: Sequential micro-liquidations require new grace period each time
    function test_MicroLiquidation_AfterLongDelinquency() public {
        // Arrange
        address lsa = _createStandardLoan();

        // Advance 6 months
        vm.warp(block.timestamp + TC.SIX_MONTHS);

        // Act - trigger first micro-liq
        bool success1 = _triggerMicroLiquidation(lsa);

        // Assert
        assertTrue(success1, "first must succeed");
        assertEq(loanContract.getLoanByLSA(lsa).duration, TC.STANDARD_DURATION - 1, "first must decrement by 1");

        // Attempt second immediately - should fail (loan is now current after timestamp reset)
        bool success2 = _triggerMicroLiquidation(lsa);
        assertFalse(success2, "second must fail - loan current after timestamp reset");

        // Advance past next grace period
        vm.warp(block.timestamp + TC.REPAYMENT_INTERVAL + config.getGracePeriod() + 1);

        // Act - trigger second micro-liq
        bool success3 = _triggerMicroLiquidation(lsa);

        // Assert
        assertTrue(success3, "second must succeed after new grace");
        assertEq(loanContract.getLoanByLSA(lsa).duration, TC.STANDARD_DURATION - 2, "second must decrement to 10");
    }

    // ============ Race Conditions (Tests 24-26) ============

    /// @notice Test 24: Repay vs micro-liquidation in same block - ordering matters
    function test_RaceCondition_RepayAndMicroLiquidation_SameBlock() public {
        // Arrange
        (address lsa, DataTypes.LoanData memory loanData) = _createStandardLoanWithData();
        uint256 emi = loanData.estimatedMonthlyPayment;

        // Make first payment overdue
        _makeFirstPaymentOverdue();

        uint256 snap = vm.snapshot();

        // --- Order 1: Repay first, then micro-liq ---
        _repayLoan(lsa, testUser, emi);
        bool mlAfterRepay = _triggerMicroLiquidation(lsa);

        DataTypes.LoanData memory dataOrder1 = loanContract.getLoanByLSA(lsa);
        uint256 durationOrder1 = dataOrder1.duration;

        // Repay should advance 1 period; micro-liq should fail (loan is now current)
        assertFalse(mlAfterRepay, "micro-liq must fail after repay brings loan current");
        assertEq(durationOrder1, TC.STANDARD_DURATION - 1, "order 1: only 1 period deducted from repay");

        // --- Order 2: Micro-liq first, then repay ---
        vm.revertTo(snap);

        bool mlFirst = _triggerMicroLiquidation(lsa);
        assertTrue(mlFirst, "micro-liq must succeed when overdue");

        _repayLoan(lsa, testUser, emi);

        DataTypes.LoanData memory dataOrder2 = loanContract.getLoanByLSA(lsa);
        uint256 durationOrder2 = dataOrder2.duration;

        // Micro-liq deducts 1, then repay deducts 1 = 2 total
        assertEq(durationOrder2, TC.STANDARD_DURATION - 2, "order 2: 2 total periods deducted (micro-liq + repay)");
    }

    /// @notice Test 25: Full repay vs full liquidation race - exclusive outcomes
    function test_RaceCondition_RepayAndFullLiquidation_SameBlock() public {
        // Arrange
        address lsa = _createStandardLoan();
        uint256 totalDebt = _getDebtBalanceUSDC(lsa);

        // Fund extra for full repay
        _fundUSDC(testUser, totalDebt);

        // Make loan eligible for full liquidation
        _makeFirstPaymentOverdue();
        _dropOraclePrice(TC.PRICE_DROP_FULL);

        uint256 snap = vm.snapshot();

        // --- Order 1: Full repay first, then liquidation fails ---
        // Recalculate debt after time warp (interest accrued)
        uint256 currentDebt = _getDebtBalanceUSDC(lsa);
        _fundUSDC(testUser, currentDebt);

        _repayLoan(lsa, testUser, currentDebt);

        DataTypes.LoanData memory dataAfterRepay = loanContract.getLoanByLSA(lsa);
        assertEq(
            uint256(dataAfterRepay.status),
            uint256(DataTypes.LoanStatus.Completed),
            "order 1: loan must be completed after full repay"
        );

        bool liqAfterRepay = _triggerFullLiquidation(lsa);
        assertFalse(liqAfterRepay, "order 1: liquidation must fail on completed loan");

        // --- Order 2: Liquidation first, then repay fails ---
        vm.revertTo(snap);

        bool liqFirst = _triggerFullLiquidation(lsa);
        assertTrue(liqFirst, "order 2: liquidation must succeed on undercollateralized loan");

        DataTypes.LoanData memory dataAfterLiq = loanContract.getLoanByLSA(lsa);
        assertEq(
            uint256(dataAfterLiq.status), uint256(DataTypes.LoanStatus.Liquidated), "order 2: loan must be liquidated"
        );

        // Repay must fail on liquidated loan
        vm.expectRevert(Errors.LoanIsNotActive.selector);
        _repayLoan(lsa, testUser, currentDebt);
    }

    /// @notice Test 26: Micro-liquidation must fail immediately after loan init
    function test_MicroLiquidation_ImmediatelyAfterLoanInit() public {
        // Arrange
        address lsa = _createStandardLoan();

        // Advance 1 block + 1 second (minimal time after init)
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 1);

        // Act - attempt micro-liq immediately
        bool immediateMlSuccess = _triggerMicroLiquidation(lsa);

        // Assert
        assertFalse(immediateMlSuccess, "must fail immediately after init");
        assertEq(loanContract.getLoanByLSA(lsa).duration, TC.STANDARD_DURATION, "duration must not change");

        // Advance past grace period
        _makeFirstPaymentOverdue();

        // Act - micro-liq after grace period
        bool lateMlSuccess = _triggerMicroLiquidation(lsa);

        // Assert
        assertTrue(lateMlSuccess, "must succeed after grace period");
        assertEq(loanContract.getLoanByLSA(lsa).duration, TC.STANDARD_DURATION - 1, "must decrement");
    }

    // ============ Index Invariants (Tests 27-29) ============

    /// @notice Test 27: Borrow index must monotonically increase over time and across operations
    function test_BorrowIndex_MonotonicallyIncreases() public {
        // Arrange
        address lsa = _createStandardLoan();
        uint256 index0 = _getVariableBorrowIndex();

        // Advance 1 day
        _advanceDays(1);
        uint256 index1 = _getVariableBorrowIndex();
        assertGe(index1, index0, "index must not decrease after 1 day");

        // Repay
        DataTypes.LoanData memory loanData = loanContract.getLoanByLSA(lsa);
        _repayLoan(lsa, testUser, loanData.estimatedMonthlyPayment);
        uint256 index2 = _getVariableBorrowIndex();
        assertGe(index2, index1, "index must not decrease after repay");

        // Advance 7 days
        _advanceDays(7);
        uint256 index3 = _getVariableBorrowIndex();
        assertGe(index3, index2, "index must not decrease after 7 days");

        // Advance 30 days
        _advanceDays(30);
        uint256 index4 = _getVariableBorrowIndex();
        assertGe(index4, index3, "index must not decrease after 30 days");
    }

    /// @notice Test 28: Scaled debt must only decrease via repayment, never by time passage alone
    function test_ScaledDebt_OnlyDecreases_AfterOrigination() public {
        // Arrange
        address lsa = _createStandardLoan();
        uint256 scaledDebtInit = _getScaledDebtBalance(lsa);

        // Advance 30 days - scaled debt must not change with time
        vm.warp(block.timestamp + TC.REPAYMENT_INTERVAL);
        uint256 scaledDebtAfterTime = _getScaledDebtBalance(lsa);
        assertEq(scaledDebtAfterTime, scaledDebtInit, "time must not change scaled debt");

        // Repay - scaled debt must decrease
        DataTypes.LoanData memory loanData = loanContract.getLoanByLSA(lsa);
        _repayLoan(lsa, testUser, loanData.estimatedMonthlyPayment);
        uint256 scaledDebtAfterRepay = _getScaledDebtBalance(lsa);
        assertLt(scaledDebtAfterRepay, scaledDebtInit, "repayment must decrease scaled debt");

        // Advance 30 more days - scaled debt must remain unchanged
        vm.warp(block.timestamp + TC.REPAYMENT_INTERVAL);
        uint256 scaledDebtAfterTime2 = _getScaledDebtBalance(lsa);
        assertEq(scaledDebtAfterTime2, scaledDebtAfterRepay, "scaled debt must not change between repays");
    }

    /// @notice Test 29: Loan contract must never hold tokens after any repayment operation
    function test_LoanContract_NeverHoldsTokensAfterRepay() public {
        // Arrange
        (address lsa, DataTypes.LoanData memory loanData) = _createStandardLoanWithData();
        address bvBTC = address(btcVault);

        // Act - partial repay
        _repayLoan(lsa, testUser, loanData.estimatedMonthlyPayment);

        // Assert - Loan contract must hold zero of all tokens
        assertEq(usdc.balanceOf(address(loanContract)), 0, "Loan contract must hold zero USDC after partial repay");
        assertEq(cbBTC.balanceOf(address(loanContract)), 0, "Loan contract must hold zero cbBTC after partial repay");
        assertEq(
            IERC20(bvBTC).balanceOf(address(loanContract)), 0, "Loan contract must hold zero bvBTC after partial repay"
        );

        // Act - full repay
        _fullyRepayLoan(lsa);

        // Assert - Loan contract must still hold zero
        assertEq(usdc.balanceOf(address(loanContract)), 0, "Loan contract must hold zero USDC after full repay");
        assertEq(cbBTC.balanceOf(address(loanContract)), 0, "Loan contract must hold zero cbBTC after full repay");
        assertEq(
            IERC20(bvBTC).balanceOf(address(loanContract)), 0, "Loan contract must hold zero bvBTC after full repay"
        );
    }

    // ============ BLP Index Invariants ============

    /// @notice 22.2: USDC liquidity and borrow indices never decrease after any action
    /// @dev bvBTC indices only checked at real interaction checkpoints (init, close).
    ///      Time-based bvBTC index growth requires a bvBTC-specific poke — out of scope.
    ///      Uses prevLiq/prevBorrow tracking pattern to avoid stack-too-deep.
    function test_USDCIndices_MonotonicallyIncrease() public {
        // Track monotonically increasing indices via prev/current pattern
        uint256 prevLiq;
        uint256 prevBorrow;
        uint256 curLiq;
        uint256 curBorrow;

        // --- Checkpoint 0: Initial state ---
        uint256 startLiq = _getLiquidityIndex(address(usdc));
        uint256 startBorrow = _getVariableBorrowIndex();
        assertGt(startLiq, 0, "USDC liquidity index must be positive at start");
        assertGt(_getLiquidityIndex(address(btcVault)), 0, "bvBTC liquidity index must be positive at start");
        prevLiq = startLiq;
        prevBorrow = startBorrow;

        // --- Checkpoint 1: After loan init ---
        (address lsa, DataTypes.LoanData memory loanData) = _createStandardLoanWithData();

        curLiq = _getLiquidityIndex(address(usdc));
        curBorrow = _getVariableBorrowIndex();
        assertGe(curLiq, prevLiq, "USDC liq index must not decrease after loan init");
        assertGe(curBorrow, prevBorrow, "USDC borrow index must not decrease after loan init");
        prevLiq = curLiq;
        prevBorrow = curBorrow;

        // --- Checkpoint 2: After 7 days + forced index update ---
        _advanceDays(7);
        _pokeReserveIndex();

        curLiq = _getLiquidityIndex(address(usdc));
        curBorrow = _getVariableBorrowIndex();
        assertGt(curLiq, prevLiq, "USDC liq index should increase with outstanding debt + time");
        assertGt(curBorrow, prevBorrow, "USDC borrow index should increase with outstanding debt + time");
        prevLiq = curLiq;
        prevBorrow = curBorrow;

        // --- Checkpoint 3: After ~30 days + forced index update ---
        _advanceDays(23);
        _pokeReserveIndex();

        curLiq = _getLiquidityIndex(address(usdc));
        curBorrow = _getVariableBorrowIndex();
        assertGt(curLiq, prevLiq, "USDC liq index must increase after 30d + poke");
        assertGt(curBorrow, prevBorrow, "USDC borrow index must increase after 30d + poke");
        prevLiq = curLiq;
        prevBorrow = curBorrow;

        // --- Checkpoint 4: After repayment ---
        _repayLoan(lsa, testUser, loanData.estimatedMonthlyPayment);

        curLiq = _getLiquidityIndex(address(usdc));
        curBorrow = _getVariableBorrowIndex();
        assertGe(curLiq, prevLiq, "USDC liq index must not decrease after repay");
        assertGe(curBorrow, prevBorrow, "USDC borrow index must not decrease after repay");
        prevLiq = curLiq;
        prevBorrow = curBorrow;

        // --- Checkpoint 5: After second month + forced update ---
        _advanceDays(30);
        _pokeReserveIndex();

        curLiq = _getLiquidityIndex(address(usdc));
        curBorrow = _getVariableBorrowIndex();
        assertGt(curLiq, prevLiq, "USDC liq index must increase after 2nd month + poke");
        assertGt(curBorrow, prevBorrow, "USDC borrow index must increase after 2nd month + poke");
        prevLiq = curLiq;
        prevBorrow = curBorrow;

        // --- Checkpoint 6: After second repayment ---
        _repayLoan(lsa, testUser, loanData.estimatedMonthlyPayment);

        curLiq = _getLiquidityIndex(address(usdc));
        curBorrow = _getVariableBorrowIndex();
        assertGe(curLiq, prevLiq, "USDC liq index must not decrease after 2nd repay");
        assertGe(curBorrow, prevBorrow, "USDC borrow index must not decrease after 2nd repay");
        prevLiq = curLiq;
        prevBorrow = curBorrow;

        // --- Checkpoint 7: After close ---
        _closeLoanEarly(lsa, testUser, false);

        curLiq = _getLiquidityIndex(address(usdc));
        curBorrow = _getVariableBorrowIndex();
        assertGe(curLiq, prevLiq, "USDC liq index must not decrease after close");
        assertGe(curBorrow, prevBorrow, "USDC borrow index must not decrease after close");

        // --- Final: verify net increase over entire lifecycle ---
        assertGt(curLiq, startLiq, "USDC liq index must be higher at end than start");
        assertGt(curBorrow, startBorrow, "USDC borrow index must be higher at end than start");
    }
}
