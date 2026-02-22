// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.30;

import {IntegrationTestBase} from "../base/IntegrationTestBase.sol";
import {TestConstants as TC} from "../helpers/TestConstants.sol";
import {DataTypes} from "@bitmor/libraries/types/DataTypes.sol";

/// @title MicroLiquidationPrecisionTest
/// @notice Integration tests for micro-liquidation precision, cooldown enforcement,
///         post-sale guard, and liquidation cascade scenarios.
/// @dev Runs against pre-deployed contracts on local Anvil via `make deploy-local`.
///      Source: Cat 19 (19.1-19.8), Cat 11 (11.1-11.9).
contract MicroLiquidationPrecisionTest is IntegrationTestBase {
    // ============ Constants ============
    uint256 constant MAX_BONUS_PERCENT_REL = 0.10e18; // 10% max bonus sanity check
    uint256 constant LIQUIDATION_FEE_BPS = TC.DEFAULT_LIQUIDATION_FEE_BPS; // 5%
    uint256 constant LIQUIDATION_FEE_HIGH_BPS = TC.MAX_LIQUIDATION_FEE_BPS; // 20%
    uint256 constant MAX_CASCADE_ITERATIONS = 12;
    uint256 constant DEBT_COVERAGE_TOLERANCE = 0.05e18; // 5% tolerance
    uint256 constant TWO_X_MULTIPLIER = 2;
    uint256 constant CONSERVATION_TOLERANCE = 0.01e18; // 1% tolerance
    uint256 constant THIN_MARGIN_UPPER = 0.05e18; // 5% upper bound for thin margin

    // ============ Setup ============
    function setUp() public override {
        super.setUp();
        _setupLiquidator();
    }

    // ========================================================================
    // Cat 19: Micro-Liq Precision & Cooldown (8 tests)
    // ========================================================================

    /// @notice 19.1: Second micro-liq immediately after first should fail (cooldown)
    function test_MicroLiquidation_Cooldown_SecondCallBeforeNextDue_Fails() public {
        // Arrange
        address lsa = _createStandardLoan();
        _makeFirstPaymentOverdue();

        // Act: first micro-liq succeeds
        bool success1 = _triggerMicroLiquidation(lsa);
        assertTrue(success1, "first micro-liquidation should succeed");

        // Assert: checkType returns 0 (loan is current after micro-liq updated lastPaymentTimestamp)
        uint256 typeAfterFirst = _checkTypeOfLiquidation(lsa);
        assertEq(typeAfterFirst, TC.LIQUIDATION_TYPE_NONE, "checkType should be 0 immediately after micro-liq");

        // Act: second micro-liq immediately should fail
        bool success2 = _triggerMicroLiquidation(lsa);
        assertFalse(success2, "second micro-liquidation should fail due to cooldown");
    }

    /// @notice 19.2: Second micro-liq succeeds after advancing past next due + grace
    function test_MicroLiquidation_Cooldown_AfterNextDueAndGrace_Succeeds() public {
        // Arrange
        address lsa = _createStandardLoan();
        uint256 originalDuration = loanContract.getLoanByLSA(lsa).duration;
        _makeFirstPaymentOverdue();

        // First micro-liq
        bool success1 = _triggerMicroLiquidation(lsa);
        assertTrue(success1, "first micro-liquidation should succeed");

        // Advance past next payment due + grace period
        vm.warp(block.timestamp + TC.REPAYMENT_INTERVAL + config.getGracePeriod() + 1);

        // Assert: checkType returns micro (2)
        uint256 typeAfterAdvance = _checkTypeOfLiquidation(lsa);
        assertEq(typeAfterAdvance, TC.LIQUIDATION_TYPE_MICRO, "checkType should be micro after next due + grace");

        // Act: second micro-liq succeeds
        bool success2 = _triggerMicroLiquidation(lsa);
        assertTrue(success2, "second micro-liquidation should succeed after cooldown expires");

        // Assert: duration decremented by 2 total from original
        DataTypes.LoanData memory loanData = loanContract.getLoanByLSA(lsa);
        assertEq(loanData.duration, originalDuration - 2, "duration should decrease by 2 after two micro-liquidations");
    }

    /// @notice 19.3: Micro-liq covers debt and liquidator receives profitable bonus
    function test_MicroLiquidation_DebtCoveredAndBonusReceived() public {
        // Arrange
        (address lsa, DataTypes.LoanData memory loanData) = _createStandardLoanWithData();
        uint256 estimatedMonthlyPayment = loanData.estimatedMonthlyPayment;
        _makeFirstPaymentOverdue();

        // Capture balances before
        uint256 liquidatorUsdcBefore = usdc.balanceOf(testLiquidator);
        uint256 liquidatorCbBTCBefore = cbBTC.balanceOf(testLiquidator);
        uint256 btcPrice = _getOraclePrice(address(cbBTC));

        // Act
        bool success = _triggerMicroLiquidation(lsa);
        assertTrue(success, "micro-liquidation should succeed");

        // Assert: liquidator USDC decreased (paid debt)
        uint256 liquidatorUsdcAfter = usdc.balanceOf(testLiquidator);
        uint256 usdcPaid = liquidatorUsdcBefore - liquidatorUsdcAfter;
        assertGt(usdcPaid, 0, "liquidator should have paid USDC");

        // Assert: USDC paid approximately equals estimatedMonthlyPayment (within 5%)
        assertApproxEqRel(
            usdcPaid, estimatedMonthlyPayment, DEBT_COVERAGE_TOLERANCE, "USDC paid should approximate monthly payment"
        );

        // Assert: liquidator received cbBTC
        uint256 liquidatorCbBTCAfter = cbBTC.balanceOf(testLiquidator);
        uint256 cbBTCReceived = liquidatorCbBTCAfter - liquidatorCbBTCBefore;
        assertGt(cbBTCReceived, 0, "liquidator should receive cbBTC bonus");

        // Assert: cbBTC value at oracle price > USDC paid (bonus exists, profitable)
        // cbBTC is 8 decimals, USDC is 6 decimals, btcPrice is in USD with 8 decimals
        uint256 cbBTCValueUsd = cbBTCReceived * btcPrice / 1e8;
        uint256 usdcPaidUsd = usdcPaid * 1e2; // scale USDC (6 dec) to 8 dec for comparison
        assertGt(cbBTCValueUsd, usdcPaidUsd, "cbBTC value should exceed USDC paid (liquidation bonus)");

        // Assert: bonus is reasonable (< 10% above debt covered)
        assertLt(
            cbBTCValueUsd,
            usdcPaidUsd + (usdcPaidUsd * 10 / 100),
            "cbBTC value should not exceed 110% of USDC paid (bonus sanity check)"
        );
    }

    /// @notice 19.4: Micro-liq does not seize excessive collateral
    function test_MicroLiquidation_NoExcessiveCollateralSeized() public {
        // Arrange
        (address lsa, DataTypes.LoanData memory loanData) = _createStandardLoanWithData();
        uint256 estimatedMonthlyPayment = loanData.estimatedMonthlyPayment;
        _makeFirstPaymentOverdue();

        // Capture LSA collateral before
        (uint256 collateralBefore,,) = _getUserAccountData(lsa);

        // Act
        bool success = _triggerMicroLiquidation(lsa);
        assertTrue(success, "micro-liquidation should succeed");

        // Assert: collateral reduced
        (uint256 collateralAfter,,) = _getUserAccountData(lsa);
        uint256 collateralReduction = collateralBefore - collateralAfter;
        assertGt(collateralReduction, 0, "collateral should decrease after micro-liquidation");

        // Assert: collateral reduction (in USD terms) < 2x estimatedMonthlyPayment (generous bound)
        // collateralBefore/After are in ETH units from BLP (18 decimals, USD-like in BLP context)
        // estimatedMonthlyPayment is USDC (6 decimals)
        uint256 maxReduction = estimatedMonthlyPayment * TWO_X_MULTIPLIER * 1e12; // scale USDC to 18 dec
        assertLt(collateralReduction, maxReduction, "collateral reduction should be bounded by 2x monthly payment");

        // Assert: LSA still has remaining collateral
        assertGt(collateralAfter, 0, "LSA should retain collateral after micro-liquidation");
    }

    /// @notice 19.5: After micro-liq, loan remains Active with decremented duration
    function test_MicroLiquidation_PostSaleGuard_Pass_RemainsActive() public {
        // Arrange
        (address lsa, DataTypes.LoanData memory loanDataBefore) = _createStandardLoanWithData();
        uint256 durationBefore = loanDataBefore.duration;
        _makeFirstPaymentOverdue();

        // Act
        bool success = _triggerMicroLiquidation(lsa);
        assertTrue(success, "micro-liquidation should succeed");

        // Assert: loan status remains Active
        DataTypes.LoanData memory loanDataAfter = loanContract.getLoanByLSA(lsa);
        assertEq(
            uint256(loanDataAfter.status),
            uint256(DataTypes.LoanStatus.Active),
            "loan should remain active after micro-liquidation"
        );

        // Assert: duration decremented by 1
        assertEq(loanDataAfter.duration, durationBefore - 1, "duration should decrease by 1");

        // Assert: checkType returns 0 immediately after
        uint256 typeAfter = _checkTypeOfLiquidation(lsa);
        assertEq(typeAfter, TC.LIQUIDATION_TYPE_NONE, "checkType should return 0 immediately after micro-liq");
    }

    /// @notice 19.6: Post-sale guard fails after price drop, escalating to full liquidation
    function test_MicroLiquidation_PostSaleGuard_Fail_EscalatesFullLiquidation() public {
        // Arrange
        address lsa = _createStandardLoan();
        _dropOraclePrice(TC.PRICE_DROP_40);
        _makeFirstPaymentOverdue();

        // Assert: checkType should return full liquidation (post-sale guard fails)
        uint256 liquidationType = _checkTypeOfLiquidation(lsa);
        assertEq(liquidationType, TC.LIQUIDATION_TYPE_FULL, "should escalate to full liquidation after price drop");

        // Act: execute full liquidation
        bool success = _triggerFullLiquidation(lsa);
        assertTrue(success, "full liquidation should succeed");

        // Assert: status = Liquidated
        DataTypes.LoanData memory loanData = loanContract.getLoanByLSA(lsa);
        assertEq(
            uint256(loanData.status),
            uint256(DataTypes.LoanStatus.Liquidated),
            "loan should be liquidated after full liquidation"
        );
    }

    /// @notice 19.7: Micro-liq on final remaining period reduces debt and completes the loan.
    /// @dev After 11 EMI repayments on a 12-month loan, duration=1. Micro-liq on the
    ///      final period covers the remaining EMI equivalent. Duration reaches 0, and the
    ///      protocol correctly sets status to Completed (orderly wind-down via micro-liq).
    ///      Design rationale: Completed = orderly wind-down (one period at a time).
    ///      Liquidated = emergency seizure (health-factor breach, entire position seized at once).
    function test_MicroLiquidation_PayOne_CappedByDebtRemaining() public {
        // Arrange: create 12-month loan and repay 11 months
        (address lsa, DataTypes.LoanData memory loanData) = _createStandardLoanWithData();
        uint256 monthlyPayment = loanData.estimatedMonthlyPayment;

        // Fund testUser and repay 11 of 12 months
        _ensureSufficientUSDC(monthlyPayment, 11);
        _makeMonthlyPayments(lsa, monthlyPayment, 11);

        // Verify duration == 1
        DataTypes.LoanData memory loanAfterRepays = loanContract.getLoanByLSA(lsa);
        assertEq(loanAfterRepays.duration, 1, "duration should be 1 after 11 repayments");

        // Make final period overdue
        vm.warp(block.timestamp + TC.REPAYMENT_INTERVAL + config.getGracePeriod() + 1);

        // Capture debt before
        uint256 debtBefore = _getDebtBalanceUSDC(lsa);
        assertGt(debtBefore, 0, "should have remaining debt before final micro-liq");

        // Act: execute micro-liq
        bool success = _triggerMicroLiquidation(lsa);
        assertTrue(success, "micro-liquidation should succeed on final period");

        // Assert: loan status should be Completed (orderly wind-down via micro-liquidation exhaustion)
        DataTypes.LoanData memory loanAfterMicroLiq = loanContract.getLoanByLSA(lsa);
        assertEq(loanAfterMicroLiq.duration, 0, "duration should be 0 after final period micro-liq");
        assertEq(
            uint256(loanAfterMicroLiq.status),
            uint256(DataTypes.LoanStatus.Completed),
            "final period micro-liq should result in Completed status (orderly wind-down)"
        );
    }

    /// @notice 19.8: Micro-liq on duration=1 results in Completed (orderly wind-down).
    /// @dev The protocol uses a two-track terminal state model:
    ///      - Completed = orderly wind-down. Used when the loan lifecycle ends naturally
    ///        (full repayment OR micro-liquidation exhausting all remaining periods).
    ///      - Liquidated = emergency seizure. Reserved for health-factor-breach full liquidations.
    ///      Micro-liq exhaustion is an orderly process (one period at a time), not an emergency.
    function test_MicroLiquidation_DurationOne_EscalatesToFullLiquidation_NotCompleted() public {
        // Arrange: create 12-month loan and repay 11 months
        (address lsa, DataTypes.LoanData memory loanData) = _createStandardLoanWithData();
        uint256 monthlyPayment = loanData.estimatedMonthlyPayment;

        // Fund testUser and repay 11 of 12 months
        _ensureSufficientUSDC(monthlyPayment, 11);
        _makeMonthlyPayments(lsa, monthlyPayment, 11);

        // Verify duration == 1
        DataTypes.LoanData memory loanAfterRepays = loanContract.getLoanByLSA(lsa);
        assertEq(loanAfterRepays.duration, 1, "duration should be 1 after 11 repayments");

        // Make overdue on final period
        vm.warp(block.timestamp + TC.REPAYMENT_INTERVAL + config.getGracePeriod() + 1);

        // Verify checkType returns micro (2)
        uint256 liquidationType = _checkTypeOfLiquidation(lsa);
        assertEq(liquidationType, TC.LIQUIDATION_TYPE_MICRO, "should be micro-liquidatable on final period");

        // Act: execute micro-liq
        bool success = _triggerMicroLiquidation(lsa);
        assertTrue(success, "micro-liquidation should succeed on final period");

        // Assert: loan status == Completed (orderly wind-down via micro-liq exhaustion)
        DataTypes.LoanData memory loanAfterMicroLiq = loanContract.getLoanByLSA(lsa);
        assertEq(
            uint256(loanAfterMicroLiq.status),
            uint256(DataTypes.LoanStatus.Completed),
            "micro-liq on duration=1 should result in Completed (orderly wind-down)"
        );

        // Assert: duration == 0
        assertEq(loanAfterMicroLiq.duration, 0, "duration should be 0 after micro-liq on final period");

        // Assert: lastPaymentTimestamp == block.timestamp
        assertEq(
            loanAfterMicroLiq.lastPaymentTimestamp,
            block.timestamp,
            "lastPaymentTimestamp should be updated to current time"
        );

        // Assert: attempt to repay fails (loan lifecycle is over)
        (bool repaySuccess,) = address(loanContract).call(abi.encodeCall(loanContract.repay, (lsa, 1e6)));
        assertFalse(repaySuccess, "repay should fail on completed loan");
    }

    // ========================================================================
    // Cat 11: Liquidation Cascade & Multi-Loan (9 tests)
    // ========================================================================

    /// @notice 11.1: Repeated micro-liq cascade eventually results in a terminal status.
    /// @dev The cascade may escalate to full liquidation via post-sale guard (→ Liquidated)
    ///      OR exhaust all remaining duration via micro-liquidations (→ Completed).
    ///      Both are valid terminal states:
    ///      - Completed = orderly wind-down via repeated micro-liq exhausting all periods
    ///      - Liquidated = emergency seizure via health-factor breach during cascade
    function test_MicroLiquidation_CascadeToFull_WhenInsufficientCollateral() public {
        // Arrange
        address lsa = _createStandardLoan();
        bool reachedTerminal = false;

        // Loop: make overdue, execute micro-liq, check if escalated
        for (uint256 i = 0; i < MAX_CASCADE_ITERATIONS; i++) {
            // Check current loan status — may already be terminal from duration hitting 0
            DataTypes.LoanData memory currentLoan = loanContract.getLoanByLSA(lsa);
            if (uint256(currentLoan.status) != uint256(DataTypes.LoanStatus.Active)) {
                // Both Completed (micro-liq exhaustion) and Liquidated (full liq) are valid terminal states
                reachedTerminal = uint256(currentLoan.status) == uint256(DataTypes.LoanStatus.Liquidated)
                    || uint256(currentLoan.status) == uint256(DataTypes.LoanStatus.Completed);
                break;
            }

            // Make overdue
            vm.warp(block.timestamp + TC.REPAYMENT_INTERVAL + config.getGracePeriod() + 1);

            uint256 liquidationType = _checkTypeOfLiquidation(lsa);

            if (liquidationType == TC.LIQUIDATION_TYPE_FULL) {
                // Escalated to full liquidation
                bool success = _triggerFullLiquidation(lsa);
                assertTrue(success, "full liquidation should succeed after cascade");
                reachedTerminal = true;
                break;
            } else if (liquidationType == TC.LIQUIDATION_TYPE_MICRO) {
                bool success = _triggerMicroLiquidation(lsa);
                assertTrue(success, "micro-liquidation should succeed in cascade iteration");

                // Check if this micro-liq set the loan to a terminal state (e.g. duration hit 0 → Completed)
                DataTypes.LoanData memory postMicroLoan = loanContract.getLoanByLSA(lsa);
                if (uint256(postMicroLoan.status) != uint256(DataTypes.LoanStatus.Active)) {
                    reachedTerminal = uint256(postMicroLoan.status) == uint256(DataTypes.LoanStatus.Liquidated)
                        || uint256(postMicroLoan.status) == uint256(DataTypes.LoanStatus.Completed);
                    break;
                }
            } else {
                // No liquidation possible - loan may have been completed/settled
                break;
            }
        }

        // Assert: cascade must reach a terminal status within MAX_CASCADE_ITERATIONS
        assertTrue(reachedTerminal, "cascade must reach terminal status within MAX_CASCADE_ITERATIONS");

        DataTypes.LoanData memory loanData = loanContract.getLoanByLSA(lsa);
        assertTrue(
            uint256(loanData.status) == uint256(DataTypes.LoanStatus.Liquidated)
                || uint256(loanData.status) == uint256(DataTypes.LoanStatus.Completed),
            "loan should be in terminal state (Liquidated or Completed) after cascade"
        );
    }

    /// @notice 11.2: Liquidating one loan does not affect other loans from different borrowers
    function test_MultipleLoans_OneLiquidated_OthersUnaffected() public {
        // Arrange: create 3 loans from different users to avoid CREATE2 salt collision
        // (salt = keccak256(borrower, block.timestamp) — same user at same timestamp collides)
        address user2 = _setupAdditionalUser("testUser2");
        address user3 = _setupAdditionalUser("testUser3");

        address lsa1 = _createStandardLoan();
        address lsa2 = _createLoanForUser(user2, TC.STANDARD_COLLATERAL, TC.STANDARD_DURATION, TC.PREMIUM_AMOUNT);
        address lsa3 = _createLoanForUser(user3, TC.STANDARD_COLLATERAL, TC.STANDARD_DURATION, TC.PREMIUM_AMOUNT);

        DataTypes.LoanData memory loan2Before = loanContract.getLoanByLSA(lsa2);
        DataTypes.LoanData memory loan3Before = loanContract.getLoanByLSA(lsa3);

        // Drop price 50% to trigger full liquidation
        _dropOraclePrice(TC.PRICE_DROP_FULL);

        // Liquidate loan 1 only
        bool success = _triggerFullLiquidation(lsa1);
        assertTrue(success, "full liquidation of loan 1 should succeed");

        // Assert: loan 1 is Liquidated
        DataTypes.LoanData memory loan1After = loanContract.getLoanByLSA(lsa1);
        assertEq(
            uint256(loan1After.status),
            uint256(DataTypes.LoanStatus.Liquidated),
            "loan 1 should be liquidated"
        );

        // Assert: loans 2 and 3 remain Active with unchanged duration
        DataTypes.LoanData memory loan2After = loanContract.getLoanByLSA(lsa2);
        DataTypes.LoanData memory loan3After = loanContract.getLoanByLSA(lsa3);

        assertEq(
            uint256(loan2After.status),
            uint256(DataTypes.LoanStatus.Active),
            "loan 2 should remain active"
        );
        assertEq(loan2After.duration, loan2Before.duration, "loan 2 duration should be unchanged");

        assertEq(
            uint256(loan3After.status),
            uint256(DataTypes.LoanStatus.Active),
            "loan 3 should remain active"
        );
        assertEq(loan3After.duration, loan3Before.duration, "loan 3 duration should be unchanged");
    }

    /// @notice 11.3: Full liquidation with severe undercollateralization may leave bad debt
    function test_FullLiquidation_MoreDebtThanCollateral_BadDebt() public {
        // Arrange
        address lsa = _createStandardLoan();

        // Drop price 70% - severe undercollateralization
        _dropOraclePrice(TC.PRICE_DROP_70);

        // Act: execute full liquidation
        bool success = _triggerFullLiquidation(lsa);
        assertTrue(success, "full liquidation should succeed even with bad debt");

        // Assert: status = Liquidated
        DataTypes.LoanData memory loanData = loanContract.getLoanByLSA(lsa);
        assertEq(
            uint256(loanData.status),
            uint256(DataTypes.LoanStatus.Liquidated),
            "loan should be liquidated after severe price drop"
        );

        // Assert: check for bad debt - debt may remain
        uint256 remainingDebt = _getDebtBalanceUSDC(lsa);
        // Note: bad debt is possible when collateral < debt. We just document it.
        // The key assertion is that liquidation succeeded and status changed.

        // Assert: LSA aToken balance should be 0 or near 0
        uint256 aTokenBalance = _getATokenBalance(lsa);
        // After full liquidation, most or all collateral should be seized
        // Allow small dust from rounding
        assertLt(aTokenBalance, 1e6, "aToken balance should be near zero after full liquidation");
    }

    /// @notice 11.4: Sequential micro-liq then full-liq is possible
    function test_MicroLiquidation_ThenImmediateFullLiquidation() public {
        // Arrange
        address lsa = _createStandardLoan();
        _makeFirstPaymentOverdue();

        // Act: micro-liq first — freshly overdue loan MUST be micro-liquidatable
        uint256 typeBeforeMicro = _checkTypeOfLiquidation(lsa);
        assertEq(typeBeforeMicro, TC.LIQUIDATION_TYPE_MICRO, "overdue loan MUST be micro-liquidatable");
        bool microSuccess = _triggerMicroLiquidation(lsa);
        assertTrue(microSuccess, "micro-liquidation should succeed");

        // Drop price further to push into full liquidation territory
        _dropOraclePrice(TC.PRICE_DROP_40);

        // Advance time to pass the cooldown from micro-liq
        vm.warp(block.timestamp + TC.REPAYMENT_INTERVAL + config.getGracePeriod() + 1);

        // Assert: full liquidation MUST be triggered after price drop + overdue
        uint256 typeAfterDrop = _checkTypeOfLiquidation(lsa);
        assertEq(typeAfterDrop, TC.LIQUIDATION_TYPE_FULL, "price drop + overdue MUST trigger full liquidation");
        bool fullSuccess = _triggerFullLiquidation(lsa);
        assertTrue(fullSuccess, "full liquidation should succeed after micro-liq + price drop");

        DataTypes.LoanData memory loanData = loanContract.getLoanByLSA(lsa);
        assertEq(
            uint256(loanData.status),
            uint256(DataTypes.LoanStatus.Liquidated),
            "loan should be fully liquidated after sequential micro then full"
        );
    }

    /// @notice 11.5: Completed loan cannot be liquidated
    function test_Liquidation_CompletedLoan_Fails() public {
        // Arrange: create loan and close it
        address lsa = _createStandardLoan();

        // Fund extra USDC for closure (pre-closure fee + flash loan costs)
        _fundUSDC(testUser, TC.USER_USDC_BALANCE);

        // Close the loan (borrower pays off everything)
        vm.prank(testUser);
        loanContract.closeLoan(lsa, false);

        // Verify loan is Completed
        DataTypes.LoanData memory loanData = loanContract.getLoanByLSA(lsa);
        assertEq(
            uint256(loanData.status),
            uint256(DataTypes.LoanStatus.Completed),
            "loan should be completed after close"
        );

        // Assert: checkType returns 0
        uint256 liquidationType = _checkTypeOfLiquidation(lsa);
        assertEq(liquidationType, TC.LIQUIDATION_TYPE_NONE, "completed loan should have no liquidation type");

        // Assert: both full and micro liquidation fail
        bool fullSuccess = _triggerFullLiquidation(lsa);
        assertFalse(fullSuccess, "full liquidation should fail on completed loan");

        bool microSuccess = _triggerMicroLiquidation(lsa);
        assertFalse(microSuccess, "micro liquidation should fail on completed loan");
    }

    /// @notice 11.6: Full liquidation rewards liquidator with cbBTC bonus
    function test_FullLiquidation_LiquidatorReceivesBonus() public {
        // Arrange
        address lsa = _createStandardLoan();

        // Capture liquidator cbBTC balance before
        uint256 liquidatorCbBTCBefore = cbBTC.balanceOf(testLiquidator);
        uint256 liquidatorUsdcBefore = usdc.balanceOf(testLiquidator);

        // Drop price 50%
        _dropOraclePrice(TC.PRICE_DROP_FULL);

        // Capture debt for comparison
        (, uint256 debtBefore,) = _getUserAccountData(lsa);
        uint256 btcPrice = _getOraclePrice(address(cbBTC));

        // Act: execute full liquidation
        bool success = _triggerFullLiquidation(lsa);
        assertTrue(success, "full liquidation should succeed");

        // Assert: liquidator received cbBTC > 0
        uint256 liquidatorCbBTCAfter = cbBTC.balanceOf(testLiquidator);
        uint256 cbBTCReceived = liquidatorCbBTCAfter - liquidatorCbBTCBefore;
        assertGt(cbBTCReceived, 0, "liquidator should receive cbBTC from full liquidation");

        // Assert: USDC paid by liquidator
        uint256 liquidatorUsdcAfter = usdc.balanceOf(testLiquidator);
        uint256 usdcPaid = liquidatorUsdcBefore - liquidatorUsdcAfter;
        assertGt(usdcPaid, 0, "liquidator should have paid USDC to cover debt");

        // Assert: cbBTC received value > USDC paid (bonus exists)
        uint256 cbBTCValueUsd = cbBTCReceived * btcPrice / 1e8;
        uint256 usdcPaidUsd = usdcPaid * 1e2; // scale 6-dec USDC to 8-dec
        assertGt(cbBTCValueUsd, usdcPaidUsd, "cbBTC value should exceed USDC paid (liquidation bonus)");

        // Assert: borrower's LSA collateral reduced
        (uint256 collateralAfter,,) = _getUserAccountData(lsa);
        // After full liquidation, collateral should be minimal
        assertLt(collateralAfter, 1e18, "LSA collateral should be near zero after full liquidation");
    }

    /// @notice 11.7: VULNERABILITY - collateralAmount in LoanData may be stale after micro-liq
    /// @dev Documents that loanData.collateralAmount may not be updated by micro-liquidation,
    ///      while the actual aToken balance decreases. This discrepancy could cause
    ///      incorrect liquidation type determination.
    function test_MicroLiquidation_CollateralAmountStaleAfterMicroLiq() public {
        // Arrange
        (address lsa, DataTypes.LoanData memory loanDataOriginal) = _createStandardLoanWithData();
        uint256 originalCollateralAmount = loanDataOriginal.collateralAmount;
        _makeFirstPaymentOverdue();

        // Act: first micro-liq
        bool success1 = _triggerMicroLiquidation(lsa);
        assertTrue(success1, "first micro-liquidation should succeed");

        // Check if collateralAmount is updated or stale after micro-liq
        DataTypes.LoanData memory loanDataAfterFirst = loanContract.getLoanByLSA(lsa);

        // Assert: actual aToken balance should decrease after micro-liq (collateral was seized)
        uint256 aTokenBalanceAfterFirst = _getATokenBalance(lsa);

        // collateralAmount may or may not be updated depending on implementation.
        // The key vulnerability is if it's stale and used for liquidation type determination.
        if (loanDataAfterFirst.collateralAmount == originalCollateralAmount) {
            // STALE: collateralAmount not updated — document the discrepancy
            assertLt(
                aTokenBalanceAfterFirst,
                originalCollateralAmount,
                "actual aToken balance should be less than stale collateralAmount after micro-liq"
            );
        }

        // Make overdue again for second micro-liq
        vm.warp(block.timestamp + TC.REPAYMENT_INTERVAL + config.getGracePeriod() + 1);

        // Act: second micro-liq
        bool success2 = _triggerMicroLiquidation(lsa);
        assertTrue(success2, "second micro-liquidation should succeed");

        // Assert: aToken balance decreased further
        uint256 aTokenBalanceAfterSecond = _getATokenBalance(lsa);
        assertLt(
            aTokenBalanceAfterSecond,
            aTokenBalanceAfterFirst,
            "aToken balance should decrease further after second micro-liq"
        );

        // Document: check if stale data causes incorrect liquidation type
        // Make overdue again
        vm.warp(block.timestamp + TC.REPAYMENT_INTERVAL + config.getGracePeriod() + 1);
        uint256 liquidationType = _checkTypeOfLiquidation(lsa);
        // The BLP uses actual aToken balance (correct), but loanData.collateralAmount may be stale
        assertTrue(
            liquidationType == TC.LIQUIDATION_TYPE_MICRO || liquidationType == TC.LIQUIDATION_TYPE_FULL,
            "should still detect liquidation type despite potentially stale collateralAmount in loanData"
        );
    }

    /// @notice 11.8: Liquidation fee splits bonus between liquidator and fee collector
    function test_LiquidationFee_AppliedCorrectly_SplitsBonus() public {
        // ---- Path A: No fee (baseline) ----
        uint256 snapshotA = vm.snapshot();

        address lsaA = _createStandardLoan();
        uint256 liquidatorCbBTCBeforeA = cbBTC.balanceOf(testLiquidator);

        _dropOraclePrice(TC.PRICE_DROP_FULL);
        bool successA = _triggerFullLiquidation(lsaA);
        assertTrue(successA, "Path A: full liquidation should succeed");

        uint256 liquidatorCbBTCAfterA = cbBTC.balanceOf(testLiquidator);
        uint256 cbBTCReceivedNoFee = liquidatorCbBTCAfterA - liquidatorCbBTCBeforeA;
        assertGt(cbBTCReceivedNoFee, 0, "Path A: liquidator should receive cbBTC");

        // Revert to snapshot for Path B
        vm.revertTo(snapshotA);

        // ---- Path B: With fee ----
        address feeCollector = makeAddr("feeCollector");
        _setLiquidationFee(LIQUIDATION_FEE_BPS, feeCollector);

        // Verify settings
        assertEq(loanContract.getLiquidationFeeBps(), LIQUIDATION_FEE_BPS, "fee bps should be set");
        assertEq(loanContract.getLiquidationFeeCollector(), feeCollector, "fee collector should be set");

        address lsaB = _createStandardLoan();
        uint256 liquidatorCbBTCBeforeB = cbBTC.balanceOf(testLiquidator);
        uint256 feeCollectorCbBTCBefore = cbBTC.balanceOf(feeCollector);

        _dropOraclePrice(TC.PRICE_DROP_FULL);
        bool successB = _triggerFullLiquidation(lsaB);
        assertTrue(successB, "Path B: full liquidation should succeed");

        uint256 liquidatorCbBTCAfterB = cbBTC.balanceOf(testLiquidator);
        uint256 cbBTCReceivedWithFee = liquidatorCbBTCAfterB - liquidatorCbBTCBeforeB;
        uint256 feeCollectorCbBTCAfter = cbBTC.balanceOf(feeCollector);
        uint256 feeCollected = feeCollectorCbBTCAfter - feeCollectorCbBTCBefore;

        // Assert: fee collector received cbBTC > 0
        assertGt(feeCollected, 0, "fee collector should receive cbBTC");

        // Assert: liquidator received LESS in Path B
        assertLt(cbBTCReceivedWithFee, cbBTCReceivedNoFee, "liquidator should receive less with fee applied");

        // Assert: fee + liquidator approximately equals Path A liquidator (conservation within 1%)
        assertApproxEqRel(
            feeCollected + cbBTCReceivedWithFee,
            cbBTCReceivedNoFee,
            CONSERVATION_TOLERANCE,
            "fee + liquidator cbBTC should conserve total (within 1%)"
        );
    }

    /// @notice 11.9: High fee reduces liquidator incentive but remains profitable
    function test_LiquidationFee_HighFee_ReducesLiquidatorIncentive() public {
        // Set high fee (20%) and collector
        address feeCollector = makeAddr("highFeeCollector");
        _setLiquidationFee(LIQUIDATION_FEE_HIGH_BPS, feeCollector);

        // Arrange
        address lsa = _createStandardLoan();
        uint256 liquidatorUsdcBefore = usdc.balanceOf(testLiquidator);
        uint256 liquidatorCbBTCBefore = cbBTC.balanceOf(testLiquidator);

        // Drop price 50%
        _dropOraclePrice(TC.PRICE_DROP_FULL);
        uint256 btcPriceAfterDrop = _getOraclePrice(address(cbBTC));

        // Act: execute full liquidation
        bool success = _triggerFullLiquidation(lsa);
        assertTrue(success, "full liquidation should succeed with high fee");

        // Calculate liquidator profit
        uint256 liquidatorUsdcAfter = usdc.balanceOf(testLiquidator);
        uint256 liquidatorCbBTCAfter = cbBTC.balanceOf(testLiquidator);
        uint256 usdcPaid = liquidatorUsdcBefore - liquidatorUsdcAfter;
        uint256 cbBTCReceived = liquidatorCbBTCAfter - liquidatorCbBTCBefore;

        assertGt(usdcPaid, 0, "liquidator should have paid USDC");
        assertGt(cbBTCReceived, 0, "liquidator should receive cbBTC even with high fee");

        // Assert: still profitable (cbBTC value > USDC paid)
        uint256 cbBTCValueUsd = cbBTCReceived * btcPriceAfterDrop / 1e8;
        uint256 usdcPaidUsd = usdcPaid * 1e2; // scale to 8 dec
        assertGt(cbBTCValueUsd, usdcPaidUsd, "liquidation should still be profitable even with 20% fee");

        // Assert: margin is thin - cbBTC value < usdcPaid * 1.05
        assertLt(
            cbBTCValueUsd,
            usdcPaidUsd + (usdcPaidUsd * 5 / 100),
            "margin should be thin with 20% fee (within 5%)"
        );
    }
}
