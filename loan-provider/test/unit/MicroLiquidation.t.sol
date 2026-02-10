// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.30;

import {BaseLoanTest} from "./Loan/BaseLoan.t.sol";
import {DataTypes} from "@bitmor/libraries/types/DataTypes.sol";
import {IERC20} from "@openzeppelin/interfaces/IERC20.sol";
import {ILendingPool} from "@bitmor/interfaces/ILendingPool.sol";
import {ILendingPoolAddressesProvider} from "@bitmor/interfaces/ILendingPoolAddressesProvider.sol";
import {IPriceOracleGetter} from "@bitmor/interfaces/IPriceOracleGetter.sol";

/// @title MicroLiquidationTest
/// @author Bitmor Protocol
/// @notice Tests for micro-liquidation functionality (`liquidationType == 2`)
/// @dev Micro-liquidation covers one monthly payment when the borrower is overdue but the loan is still healthy.
///      Uses `LiquidationTestState` from `BaseLoanTest` for state management.
contract MicroLiquidationTest is BaseLoanTest {
    // ============ Local Structs ============
    // Note: Uses LiquidationTestState from BaseLoanTest for most state management
    // Extended fields only for micro-liquidation-specific tracking

    /// @notice Extension struct tracking micro-liquidation-specific debt token and remaining debt state
    struct MicroLiquidationExtension {
        uint256 debtATokenBalanceBefore;
        uint256 debtATokenBalanceAfter;
        uint256 remainingDebtBefore;
        uint256 remainingDebtAfter;
    }

    // ============ Test: Core Micro-Liquidation with Full Invariant Coverage ============

    /// @notice Test micro-liquidation when borrower has not paid monthly dues and grace period has passed
    /// @dev Covers core invariants: exact debt paid, debt destination, collateral seized, state updates
    function test_microLiquidation_whenPaymentOverdue() public setUpLoanForUser {
        // Get LSA
        address lsa = loan.getUserLoanAtIndex(user, 0);

        // Setup: Update AddressesProvider (before capturing state)
        _updateAddressesProviderBitmorLoan();

        // Capture state using generic helper
        LiquidationTestState memory state = _captureLiquidationStateBefore(lsa);

        // Capture micro-liquidation specific state
        MicroLiquidationExtension memory ext;
        // Note: Mock transfers debt to pool, not to debt token address
        ext.debtATokenBalanceBefore = IERC20(debtAsset).balanceOf(s_bitmorPool);
        ext.remainingDebtBefore = _getLsaDebtBalance(lsa);

        // Warp time to make loan overdue and fund liquidator
        _warpPastGracePeriod();
        _fundLiquidator();

        // Set up micro-liquidation eligibility (configures mock to return LIQUIDATION_TYPE_MICRO)
        mockBitmorPool.setUserOverdue(lsa, true);
        _setLiquidationType(lsa, LIQUIDATION_TYPE_MICRO);

        // Re-capture liquidator balances after funding (reset for accurate delta)
        state.liquidatorState = _captureLiquidatorSnapshot();

        // Execute micro liquidation
        _executeMicroLiquidation(lsa);

        // Update state after liquidation
        _updateLiquidationStateAfter(state, lsa);

        // Update micro-liquidation specific state
        ext.debtATokenBalanceAfter = IERC20(debtAsset).balanceOf(s_bitmorPool);
        ext.remainingDebtAfter = _getLsaDebtBalance(lsa);

        // ============ CORE INVARIANT ASSERTIONS ============

        // 1. EXACT DEBT PAID: debtPaid == min(estimatedMonthlyPayment, remainingDebt)
        uint256 expectedDebtPaid = _utilMin(state.loanState.estimatedMonthlyPayment, ext.remainingDebtBefore);
        assertEq(state.debtPaid, expectedDebtPaid, "Debt paid should equal min(monthlyPayment, remainingDebt)");

        // 2. DEBT ASSET DESTINATION: debtAsset.balanceOf(pool) increases by exactly debtPaid
        // Note: Mock pool receives debt directly, not via aToken
        uint256 poolDebtIncrease = ext.debtATokenBalanceAfter - ext.debtATokenBalanceBefore;
        assertEq(poolDebtIncrease, state.debtPaid, "Pool balance should increase by exact debtPaid amount");

        // 3. COLLATERAL SEIZED EXACTNESS: verify within rounding tolerance (1 bps)
        uint256 expectedCollateral = _calculateExpectedCollateralSeized(state.debtPaid);
        // Allow 0.5% tolerance for rounding differences
        uint256 tolerance = expectedCollateral / 200;
        assertApproxEqAbs(
            state.collateralReceived,
            expectedCollateral,
            tolerance,
            "Collateral received should match expected with bonus"
        );

        // 4. STATE UPDATES:
        // a. durationAfter == durationBefore - 1
        assertEq(state.loanState.durationAfter, state.loanState.durationBefore - 1, "Duration should decrease by 1");

        // b. lastPaymentTimestampAfter == block.timestamp
        assertEq(
            state.loanState.lastPaymentAfter,
            block.timestamp,
            "Last payment timestamp should be updated to current time"
        );

        // c. status == Active
        assertEq(
            uint256(state.loanState.statusAfter), uint256(DataTypes.LoanStatus.Active), "Loan should remain active"
        );

        // 5. NO-OP SANITY: LSA still exists, debt decreased, collateral decreased
        assertGt(state.debtPaid, 0, "Liquidator should have paid debt");
        assertGt(state.collateralReceived, 0, "Liquidator should have received collateral");
        assertLt(ext.remainingDebtAfter, ext.remainingDebtBefore, "LSA debt should have decreased");

        // 6. LIQUIDATOR PROFIT: collateral value > debt paid (liquidation bonus)
        uint256 collateralValueUSD = (state.collateralReceived * state.btcPriceUSD) / 1e8;
        uint256 debtPaidIn8Decimals = state.debtPaid * 1e2; // Convert 6 decimals to 8 for comparison
        assertGt(collateralValueUSD, debtPaidIn8Decimals, "Liquidator should profit from liquidation bonus");
    }

    // ============ Test: Liquidator Bonus Verification (Micro-Specific) ============

    /// @notice Test that liquidator receives the expected bonus (micro-liquidation)
    function test_microLiquidation_liquidatorReceivesBonus() public setUpLoanForUser {
        address lsa = loan.getUserLoanAtIndex(user, 0);

        // Setup for micro-liquidation using composite helper
        uint256 liquidationType = _setupForMicroLiquidation(lsa);
        assertEq(liquidationType, LIQUIDATION_TYPE_MICRO, "Should be micro-liquidation eligible");

        // Capture state using generic helper
        LiquidationTestState memory state = _captureLiquidationStateBefore(lsa);

        // Execute micro liquidation
        _executeMicroLiquidation(lsa);

        // Update state
        _updateLiquidationStateAfter(state, lsa);

        // Get liquidation bonus
        uint256 liquidationBonusBps = _getLiquidationBonus();

        // Calculate expected collateral without bonus
        uint256 baseCollateral = (state.debtPaid * state.usdcPriceUSD * 1e8) / (state.btcPriceUSD * 1e6);
        uint256 expectedWithBonus = (baseCollateral * liquidationBonusBps) / 10_000;

        // Allow 1% tolerance for rounding
        uint256 tolerance = expectedWithBonus / 100;
        assertApproxEqAbs(state.collateralReceived, expectedWithBonus, tolerance, "Should receive bonus on collateral");
    }

    // ============ Test: Duration Decrements Each Micro-Liquidation ============

    /// @notice Test that duration decrements correctly on each micro-liquidation
    function test_microLiquidation_decrementsDuration() public setUpLoanForUser {
        address lsa = loan.getUserLoanAtIndex(user, 0);

        _updateAddressesProviderBitmorLoan();

        // Get initial duration using generic snapshot
        TestSnapshot memory initialSnapshot = _captureTestSnapshot(lsa);
        uint256 initialDuration = initialSnapshot.durationBefore;

        _warpPastGracePeriod();
        _fundLiquidator();

        // Set up micro-liquidation eligibility
        mockBitmorPool.setUserOverdue(lsa, true);
        _setLiquidationType(lsa, LIQUIDATION_TYPE_MICRO);

        // Execute first micro liquidation
        _executeMicroLiquidation(lsa);

        // Check duration after first
        _updateTestSnapshotAfter(initialSnapshot, lsa);
        assertEq(initialSnapshot.durationAfter, initialDuration - 1, "Duration should decrement by 1");

        // Warp again for next payment period
        vm.warp(block.timestamp + LOAN_REPAYMENT_INTERVAL + s_gracePeriod + 1);

        // Set up micro-liquidation eligibility again (still overdue)
        _setLiquidationType(lsa, LIQUIDATION_TYPE_MICRO);

        // Verify still micro-liquidation eligible
        uint256 liquidationType = _checkLiquidationType(lsa);
        if (liquidationType == LIQUIDATION_TYPE_MICRO) {
            // Capture new state
            TestSnapshot memory secondSnapshot = _captureTestSnapshot(lsa);

            _executeMicroLiquidation(lsa);

            _updateTestSnapshotAfter(secondSnapshot, lsa);
            assertEq(secondSnapshot.durationAfter, initialDuration - 2, "Duration should decrement to initial - 2");
        }
    }

    // ============ Test: Last Payment Timestamp Updates ============

    /// @notice Test that lastPaymentTimestamp is updated on micro-liquidation
    function test_microLiquidation_updatesLastPaymentTimestamp() public setUpLoanForUser {
        address lsa = loan.getUserLoanAtIndex(user, 0);

        // Setup for micro-liquidation using composite helper
        uint256 liquidationType = _setupForMicroLiquidation(lsa);
        assertEq(liquidationType, LIQUIDATION_TYPE_MICRO, "Should be micro-liquidation eligible");

        // Get initial last payment using generic snapshot
        TestSnapshot memory snapshot = _captureTestSnapshot(lsa);
        uint256 initialLastPayment = snapshot.lastPaymentBefore;

        uint256 expectedTimestamp = block.timestamp;

        _executeMicroLiquidation(lsa);

        // Update snapshot
        _updateTestSnapshotAfter(snapshot, lsa);

        assertGt(snapshot.lastPaymentAfter, initialLastPayment, "Last payment should be updated");
        assertEq(snapshot.lastPaymentAfter, expectedTimestamp, "Last payment should be current block timestamp");
    }

    // ============ Test: Repeated Micro-Liquidations Lead to Full Liquidation ============

    /// @notice Test that repeated micro-liquidations eventually lead to full liquidation
    function test_microLiquidation_repeatedLeadsToFullLiquidation() public setUpLoanForUser {
        address lsa = loan.getUserLoanAtIndex(user, 0);

        _updateAddressesProviderBitmorLoan();

        // Use generic state for tracking
        LiquidationTestState memory state = _captureLiquidationStateBefore(lsa);
        state.monthsLiquidated = 0;

        _fundLiquidator();

        // Loop micro-liquidations until full liquidation becomes available
        for (uint256 i = 0; i < 15; i++) {
            // Warp past grace period
            vm.warp(block.timestamp + LOAN_REPAYMENT_INTERVAL + s_gracePeriod + 1);

            // Apply 15% price drop each iteration to reliably reach full liquidation
            _dropOraclePrice(collateralAsset, 15);

            // Set overdue state and determine liquidation type based on health factor
            mockBitmorPool.setUserOverdue(lsa, true);

            // For iterations 0-3, use micro-liquidation; after that, switch to full liquidation
            // (simulating health factor degradation due to price drops)
            if (i < 4) {
                _setLiquidationType(lsa, LIQUIDATION_TYPE_MICRO);
            } else {
                // Health factor has dropped enough for full liquidation
                mockBitmorPool.setHealthFactor(lsa, 0.5e18);
                _setLiquidationType(lsa, LIQUIDATION_TYPE_FULL);
            }

            uint256 liquidationType = _checkLiquidationType(lsa);

            if (liquidationType == LIQUIDATION_TYPE_NONE) {
                // No longer liquidatable, exit
                break;
            } else if (liquidationType == LIQUIDATION_TYPE_FULL) {
                // Full liquidation eligible - capture liquidator state
                state.liquidatorState = _captureLiquidatorSnapshot();

                // Execute full liquidation
                _executeFullLiquidation(lsa, type(uint256).max, false);

                // Update state
                _updateLiquidatorSnapshotAfter(state.liquidatorState);
                state.fullLiqDebtPaid =
                    state.liquidatorState.liquidatorDebtBefore - state.liquidatorState.liquidatorDebtAfter;
                state.fullLiqCollateralReceived =
                    state.liquidatorState.liquidatorCollateralAfter - state.liquidatorState.liquidatorCollateralBefore;
                state.fullLiquidationExecuted = true;
                break;
            } else if (liquidationType == LIQUIDATION_TYPE_MICRO) {
                // Micro liquidation
                state.liquidatorState = _captureLiquidatorSnapshot();

                _executeMicroLiquidation(lsa);

                _updateLiquidatorSnapshotAfter(state.liquidatorState);
                state.totalDebtPaid +=
                    state.liquidatorState.liquidatorDebtBefore - state.liquidatorState.liquidatorDebtAfter;
                state.totalCollateralReceived +=
                    state.liquidatorState.liquidatorCollateralAfter - state.liquidatorState.liquidatorCollateralBefore;
                state.monthsLiquidated++;
            }
        }

        // Update final loan state
        _updateTestSnapshotAfter(state.loanState, lsa);

        // Assert outcomes
        if (state.fullLiquidationExecuted) {
            assertEq(
                uint256(state.loanState.statusAfter),
                uint256(DataTypes.LoanStatus.Liquidated),
                "Loan should be liquidated after full liquidation"
            );
            assertEq(state.loanState.durationAfter, 0, "Duration should be 0 after full liquidation");
        } else {
            // Either completed (all months micro-liquidated) or still active
            assertTrue(
                state.loanState.statusAfter == DataTypes.LoanStatus.Completed
                    || state.loanState.statusAfter == DataTypes.LoanStatus.Active,
                "Loan should be completed or active"
            );
        }

        assertGt(state.monthsLiquidated + (state.fullLiquidationExecuted ? 1 : 0), 0, "At least one liquidation");
    }

    // ============ Test: Mock Setup Verification ============

    /// @notice Verify mock setup correctly simulates liquidation type transitions
    /// @dev This documents expected mock configuration for micro-liquidation scenarios.
    ///      In production, checkTypeOfLiquidation is computed by the lending pool based on
    ///      health factor and payment status. Here we verify mock setup is correct.
    function test_microLiquidation_mockSetup_configuresCorrectly() public setUpLoanForUser {
        address lsa = loan.getUserLoanAtIndex(user, 0);

        _updateAddressesProviderBitmorLoan();

        // Fresh loan: mock defaults to LIQUIDATION_TYPE_NONE
        uint256 liquidationTypeBefore = _checkLiquidationType(lsa);
        assertEq(liquidationTypeBefore, LIQUIDATION_TYPE_NONE, "Mock should default to type 0 for fresh loans");

        // Configure mock for micro-liquidation scenario
        _warpPastGracePeriod();
        mockBitmorPool.setUserOverdue(lsa, true);
        _setLiquidationType(lsa, LIQUIDATION_TYPE_MICRO);

        // Verify mock configuration (this tests mock, not contract logic)
        uint256 liquidationTypeAfter = _checkLiquidationType(lsa);
        assertEq(liquidationTypeAfter, LIQUIDATION_TYPE_MICRO, "Mock should be configured for micro-liquidation");
    }

    // ============ Test: Micro-Liquidation Within Grace Period Should Revert ============

    /// @notice Test that micro-liquidation reverts when called within grace period
    function test_microLiquidation_withinGracePeriod_reverts() public setUpLoanForUser {
        address lsa = loan.getUserLoanAtIndex(user, 0);

        _updateAddressesProviderBitmorLoan();

        // Do NOT warp past grace/interval - loan is still in good standing

        // Fund liquidator
        _fundLiquidator();

        // Check liquidation type - should be 0 (not eligible)
        uint256 liquidationType = _checkLiquidationType(lsa);
        assertEq(liquidationType, LIQUIDATION_TYPE_NONE, "Loan within grace period should not be liquidatable");

        // Attempt micro-liquidation - should revert
        bytes memory liquidationData = abi.encode(collateralAsset, debtAsset, lsa);
        vm.prank(liquidator);
        vm.expectRevert(); // ValidationLogic returns error for typeOfLiquidation != 2
        ILendingPool(s_bitmorPool).microLiquidationCall(liquidationData);
    }

    // ============ Test: Micro-Liquidation Reverts If Liquidator Has No USDC ============

    /// @notice Test that micro-liquidation reverts when liquidator has no USDC
    function test_microLiquidation_revertsIfLiquidatorHasNoUSDC() public setUpLoanForUser {
        address lsa = loan.getUserLoanAtIndex(user, 0);

        _updateAddressesProviderBitmorLoan();

        // Warp to make loan overdue
        _warpPastGracePeriod();

        // Set up micro-liquidation eligibility
        mockBitmorPool.setUserOverdue(lsa, true);
        _setLiquidationType(lsa, LIQUIDATION_TYPE_MICRO);

        // Verify loan is eligible for micro-liquidation
        uint256 liquidationType = _checkLiquidationType(lsa);
        assertEq(liquidationType, LIQUIDATION_TYPE_MICRO, "Should be micro-liquidation eligible");

        // Clear liquidator's balances (reset from base setup) and set approval only
        uint256 liquidatorBalance = IERC20(debtAsset).balanceOf(liquidator);
        if (liquidatorBalance > 0) {
            vm.prank(liquidator);
            IERC20(debtAsset).transfer(address(1), liquidatorBalance);
        }
        vm.prank(liquidator);
        IERC20(debtAsset).approve(s_bitmorPool, type(uint256).max);

        // Verify liquidator has 0 USDC using generic helper
        AccountBalanceSnapshot memory liquidatorBalances = _snapshotAccountBalances(liquidator);
        assertEq(liquidatorBalances.debtAssetBalance, 0, "Liquidator should have 0 USDC");

        // Attempt micro-liquidation - should revert (insufficient balance for safeTransferFrom)
        bytes memory liquidationData = abi.encode(collateralAsset, debtAsset, lsa);
        vm.prank(liquidator);
        vm.expectRevert(); // Will fail at safeTransferFrom due to insufficient balance
        ILendingPool(s_bitmorPool).microLiquidationCall(liquidationData);
    }

    // ============ Test: Micro-Liquidation Reverts If Liquidator Has No Allowance ============

    /// @notice Test that micro-liquidation reverts when liquidator has USDC but no allowance
    function test_microLiquidation_revertsIfLiquidatorHasNoAllowance() public setUpLoanForUser {
        address lsa = loan.getUserLoanAtIndex(user, 0);

        _updateAddressesProviderBitmorLoan();

        // Warp to make loan overdue
        _warpPastGracePeriod();

        // Set up micro-liquidation eligibility
        mockBitmorPool.setUserOverdue(lsa, true);
        _setLiquidationType(lsa, LIQUIDATION_TYPE_MICRO);

        // Verify loan is eligible for micro-liquidation
        uint256 liquidationType = _checkLiquidationType(lsa);
        assertEq(liquidationType, LIQUIDATION_TYPE_MICRO, "Should be micro-liquidation eligible");

        // Reset liquidator's allowance (base setup gave max allowance)
        vm.prank(liquidator);
        IERC20(debtAsset).approve(s_bitmorPool, 0);

        // Verify liquidator has USDC but no allowance using generic helper
        AccountBalanceSnapshot memory liquidatorBalances = _snapshotAccountBalances(liquidator);
        assertGt(liquidatorBalances.debtAssetBalance, 0, "Liquidator should have USDC");
        uint256 allowance = IERC20(debtAsset).allowance(liquidator, s_bitmorPool);
        assertEq(allowance, 0, "Liquidator should have 0 allowance");

        // Attempt micro-liquidation - should revert (insufficient allowance for safeTransferFrom)
        bytes memory liquidationData = abi.encode(collateralAsset, debtAsset, lsa);
        vm.prank(liquidator);
        vm.expectRevert(); // Will fail at safeTransferFrom due to insufficient allowance
        ILendingPool(s_bitmorPool).microLiquidationCall(liquidationData);
    }

    // ============ Test: Micro-Liquidation Caps Debt To Cover At Remaining Debt ============

    /// @notice Test that micro-liquidation caps debtToCover at remainingDebt when monthly payment exceeds it
    function test_microLiquidation_capsDebtToCoverAtRemainingDebt() public setUpLoanForUser {
        address lsa = loan.getUserLoanAtIndex(user, 0);

        _updateAddressesProviderBitmorLoan();

        // Get loan data using generic snapshot
        TestSnapshot memory snapshot = _captureTestSnapshot(lsa);
        uint256 estimatedMonthlyPayment = snapshot.estimatedMonthlyPayment;
        uint256 initialDebt = _getLsaDebtBalance(lsa);

        // Leave a small remaining debt so that it is strictly below the monthly payment even after interest accrues.
        // (Debt tokens accrue interest over time; after warping, the remaining debt can grow slightly.)
        uint256 targetRemainingDebt = estimatedMonthlyPayment / 10;
        require(initialDebt > targetRemainingDebt, "Test setup: initial debt too small");

        uint256 amountToRepay = initialDebt - targetRemainingDebt;
        _utilMintTokenAndApprove(debtAsset, user, address(loan), amountToRepay);

        vm.prank(user);
        loan.repay(lsa, amountToRepay);

        // Verify remaining debt is less than monthly payment (at current timestamp)
        uint256 remainingDebtAfterRepay = _getLsaDebtBalance(lsa);
        assertLt(remainingDebtAfterRepay, estimatedMonthlyPayment, "Remaining debt should be less than monthly payment");
        assertGt(remainingDebtAfterRepay, 0, "Should still have some debt");

        // Warp to make loan overdue
        _warpPastGracePeriod();

        // Set up micro-liquidation eligibility
        mockBitmorPool.setUserOverdue(lsa, true);
        _setLiquidationType(lsa, LIQUIDATION_TYPE_MICRO);

        // Verify still micro-liquidation eligible (may depend on health factor)
        uint256 liquidationType = _checkLiquidationType(lsa);
        if (liquidationType == LIQUIDATION_TYPE_NONE) {
            // If not liquidatable, exit (nothing to micro-liquidate)
            return;
        }
        assertEq(liquidationType, LIQUIDATION_TYPE_MICRO, "Should be micro-liquidation eligible");

        // IMPORTANT: Recompute remaining debt *at liquidation time*.
        // After the warp, variable debt accrues interest and the pool uses the updated debt when capping.
        uint256 remainingDebtAtLiquidation = _getLsaDebtBalance(lsa);
        assertLt(
            remainingDebtAtLiquidation,
            estimatedMonthlyPayment,
            "Test setup: remaining debt should still be < monthly payment at liquidation time"
        );

        // Fund liquidator
        _fundLiquidator();

        // Snapshot liquidator balances using generic helper
        LiquidatorSnapshot memory liquidatorState = _captureLiquidatorSnapshot();

        // Execute micro-liquidation
        _executeMicroLiquidation(lsa);

        // Update liquidator state
        _updateLiquidatorSnapshotAfter(liquidatorState);

        // Calculate actual debt paid
        uint256 debtPaid = liquidatorState.liquidatorDebtBefore - liquidatorState.liquidatorDebtAfter;

        // Assert debtPaid == remainingDebt at liquidation time (capped behavior)
        assertEq(debtPaid, remainingDebtAtLiquidation, "Debt paid should equal remaining debt (capped at remaining)");
        assertLt(debtPaid, estimatedMonthlyPayment, "Debt paid should be less than monthly payment");
    }
}
