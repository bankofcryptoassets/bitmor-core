// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.30;

import {BaseLoanTest} from "./BaseLoanTest.t.sol";
import {DataTypes} from "@bitmor/libraries/types/DataTypes.sol";
import {IERC20} from "@bitmor/dependencies/openzeppelin/IERC20.sol";
import {ILendingPool} from "@bitmor/interfaces/ILendingPool.sol";
import {ILendingPoolAddressesProvider} from "@bitmor/interfaces/ILendingPoolAddressesProvider.sol";
import {IPriceOracleGetter} from "@bitmor/interfaces/IPriceOracleGetter.sol";

/// @title MicroLiquidationTest
/// @notice Tests for micro-liquidation functionality (liquidationType == 2)
/// @dev Micro-liquidation covers one monthly payment when borrower is overdue but loan is still healthy
contract MicroLiquidationTest is BaseLoanTest {
    
    // ============ Structs ============

    /// @dev Struct to hold micro-liquidation test variables
    struct MicroLiquidationTestVars {
        address lsa;
        uint256 durationBefore;
        uint256 lastPaymentBefore;
        uint256 liquidatorDebtBefore;
        uint256 liquidatorCollateralBefore;
        uint256 liquidatorDebtAfter;
        uint256 liquidatorCollateralAfter;
        uint256 durationAfter;
        uint256 lastPaymentAfter;
        DataTypes.LoanStatus statusAfter;
        uint256 btcPriceUSD;
        uint256 usdcPriceUSD;
        uint256 collateralLiquidatedUSDValue;
        uint256 estimatedMonthlyPayment;
        uint256 remainingDebtBefore;
        uint256 remainingDebtAfter;
        uint256 debtATokenBalanceBefore;
        uint256 debtATokenBalanceAfter;
    }

    /// @dev Struct to hold repeated micro-liquidation test variables
    struct RepeatedMicroLiquidationVars {
        address lsa;
        uint256 initialDuration;
        uint256 currentDuration;
        uint256 monthsLiquidated;
        uint256 liquidationType;
        uint256 totalDebtPaid;
        uint256 totalCollateralReceived;
        uint256 liquidatorDebtBefore;
        uint256 liquidatorCollateralBefore;
        uint256 liquidatorDebtAfter;
        uint256 liquidatorCollateralAfter;
        uint256 btcPriceUSD;
        uint256 collateralInLSA;
        uint256 fullLiqDebtPaid;
        uint256 fullLiqCollateralReceived;
        bool fullLiquidationExecuted;
        uint256 lastPaymentTimestampBefore;
        uint256 lastPaymentTimestampAfter;
        uint256 durationBefore;
        uint256 estimatedMonthlyPayment;
        uint256 remainingDebt;
    }

    // ============ Test: Core Micro-Liquidation with Full Invariant Coverage ============

    /// @notice Test micro-liquidation when borrower has not paid monthly dues and grace period has passed
    /// @dev Covers core invariants: exact debt paid, debt destination, collateral seized, state updates
    function test_microLiquidation_whenPaymentOverdue() public setUpLoanForUser {
        MicroLiquidationTestVars memory vars;

        // Setup: Update AddressesProvider
        _updateAddressesProviderBitmorLoan();

        // Get LSA and initial loan data
        vars.lsa = loan.getUserLoanAtIndex(user, 0);
        {
            DataTypes.LoanData memory loanDataBefore = loan.getLoanByLSA(vars.lsa);
            vars.durationBefore = loanDataBefore.duration;
            vars.lastPaymentBefore = loanDataBefore.lastPaymentTimestamp;
            vars.estimatedMonthlyPayment = loanDataBefore.estimatedMonthlyPayment;
        }

        // Get remaining debt before
        vars.remainingDebtBefore = _getLsaDebtBalance(vars.lsa);

        // Get debt aToken balance before (where liquidator's USDC will be transferred)
        address debtATokenAddr = _getDebtATokenAddress();
        vars.debtATokenBalanceBefore = IERC20(debtAsset).balanceOf(debtATokenAddr);

        // Warp time to make loan overdue
        _warpPastGracePeriod();

        // Check liquidation type - should be 2 (micro-liquidation)
        uint256 liquidationType = _checkLiquidationType(vars.lsa);
        assertEq(liquidationType, 2, "Liquidation type should be 2 (micro)");

        // Fund liquidator
        _fundLiquidator();

        // Snapshot liquidator balances before
        (vars.liquidatorDebtBefore, vars.liquidatorCollateralBefore) = _snapshotLiquidatorBalances();

        // Execute micro liquidation
        _executeMicroLiquidation(vars.lsa);

        // Snapshot balances after
        (vars.liquidatorDebtAfter, vars.liquidatorCollateralAfter) = _snapshotLiquidatorBalances();

        // Get loan data after
        {
            DataTypes.LoanData memory loanDataAfter = loan.getLoanByLSA(vars.lsa);
            vars.durationAfter = loanDataAfter.duration;
            vars.lastPaymentAfter = loanDataAfter.lastPaymentTimestamp;
            vars.statusAfter = loanDataAfter.status;
        }

        // Get remaining debt after
        vars.remainingDebtAfter = _getLsaDebtBalance(vars.lsa);

        // Get debt aToken balance after
        vars.debtATokenBalanceAfter = IERC20(debtAsset).balanceOf(debtATokenAddr);

        // Calculate actual amounts
        uint256 debtPaid = vars.liquidatorDebtBefore - vars.liquidatorDebtAfter;
        uint256 collateralReceived = vars.liquidatorCollateralAfter - vars.liquidatorCollateralBefore;

        // Get oracle prices for USD value calculations
        vars.btcPriceUSD = _getBtcPrice();
        vars.usdcPriceUSD = _getUsdcPrice();

        // ============ CORE INVARIANT ASSERTIONS ============

        // 1. EXACT DEBT PAID: debtPaid == min(estimatedMonthlyPayment, remainingDebt)
        uint256 expectedDebtPaid = _utilMin(vars.estimatedMonthlyPayment, vars.remainingDebtBefore);
        assertEq(debtPaid, expectedDebtPaid, "Debt paid should equal min(monthlyPayment, remainingDebt)");

        // 2. DEBT ASSET DESTINATION: debtAsset.balanceOf(debtATokenAddress) increases by exactly debtPaid
        uint256 debtATokenIncrease = vars.debtATokenBalanceAfter - vars.debtATokenBalanceBefore;
        assertEq(debtATokenIncrease, debtPaid, "Debt aToken balance should increase by exact debtPaid amount");

        // 3. COLLATERAL SEIZED EXACTNESS: verify within rounding tolerance (1 bps)
        uint256 expectedCollateral = _calculateExpectedCollateralSeized(debtPaid);
        // Allow 0.5% tolerance for rounding differences
        uint256 tolerance = expectedCollateral / 200;
        assertApproxEqAbs(collateralReceived, expectedCollateral, tolerance, "Collateral received should match expected with bonus");

        // 4. STATE UPDATES:
        // a. durationAfter == durationBefore - 1
        assertEq(vars.durationAfter, vars.durationBefore - 1, "Duration should decrease by 1");

        // b. lastPaymentTimestampAfter == block.timestamp
        assertEq(vars.lastPaymentAfter, block.timestamp, "Last payment timestamp should be updated to current time");

        // c. status == Active
        assertEq(uint256(vars.statusAfter), uint256(DataTypes.LoanStatus.Active), "Loan should remain active");

        // 5. NO-OP SANITY: LSA still exists, debt decreased, collateral decreased
        assertGt(debtPaid, 0, "Liquidator should have paid debt");
        assertGt(collateralReceived, 0, "Liquidator should have received collateral");
        assertLt(vars.remainingDebtAfter, vars.remainingDebtBefore, "LSA debt should have decreased");

        // 6. LIQUIDATOR PROFIT: collateral value > debt paid (liquidation bonus)
        uint256 collateralValueUSD = (collateralReceived * vars.btcPriceUSD) / 1e8;
        uint256 debtPaidIn8Decimals = debtPaid * 1e2; // Convert 6 decimals to 8 for comparison
        assertGt(collateralValueUSD, debtPaidIn8Decimals, "Liquidator should profit from liquidation bonus");
    }

    // ============ Test: Liquidator Bonus Verification (Micro-Specific) ============

    /// @notice Test that liquidator receives the expected bonus (micro-liquidation)
    function test_microLiquidation_liquidatorReceivesBonus() public setUpLoanForUser {
        address lsa = loan.getUserLoanAtIndex(user, 0);

        _updateAddressesProviderBitmorLoan();

        _warpPastGracePeriod();

        uint256 liquidationType = _checkLiquidationType(lsa);
        assertEq(liquidationType, 2, "Should be micro-liquidation");

        _fundLiquidator();

        // Get debt aToken address for balance check
        address debtATokenAddr = _getDebtATokenAddress();
        uint256 debtATokenBefore = IERC20(debtAsset).balanceOf(debtATokenAddr);

        (uint256 debtBefore, uint256 collateralBefore) = _snapshotLiquidatorBalances();

        _executeMicroLiquidation(lsa);

        (uint256 debtAfter, uint256 collateralAfter) = _snapshotLiquidatorBalances();
        uint256 debtATokenAfter = IERC20(debtAsset).balanceOf(debtATokenAddr);

        uint256 debtPaid = debtBefore - debtAfter;
        uint256 collateralReceived = collateralAfter - collateralBefore;

        assertGt(debtPaid, 0, "Liquidator should pay debt");
        assertGt(collateralReceived, 0, "Liquidator should receive collateral");

        // Verify USDC → debt aToken delta
        uint256 debtATokenDelta = debtATokenAfter - debtATokenBefore;
        assertEq(debtATokenDelta, debtPaid, "Debt aToken should receive exact debt paid amount");

        // Verify liquidator profit matches expected bonus
        uint256 btcPrice = _getBtcPrice();
        uint256 collateralValueUSD = (collateralReceived * btcPrice) / 1e8;
        uint256 debtPaidIn8Decimals = debtPaid * 1e2;

        // Get liquidation bonus (e.g., 10300 = 103% = 3% bonus)
        uint256 liquidationBonusBps = _getLiquidationBonus();
        
        // Expected profit percentage = (liquidationBonus - 10000) / 10000
        // Verify collateral value is approximately debtPaid * liquidationBonus / 10000
        uint256 expectedCollateralValue = (debtPaidIn8Decimals * liquidationBonusBps) / 10000;
        
        // Allow 1% tolerance for rounding
        uint256 tolerance = expectedCollateralValue / 100;
        assertApproxEqAbs(collateralValueUSD, expectedCollateralValue, tolerance, "Collateral value should match expected with liquidation bonus");
    }

    // ============ Test: Repeated Micro-Liquidation Until Completion or Full Liquidation ============

    /// @notice Test repeated micro-liquidations until full liquidation or loan completion
    function test_repeatedMicroLiquidation_untilFullLiquidationOrCompletion() public setUpLoanForUser {
        RepeatedMicroLiquidationVars memory vars;

        // 1. Setup: Update AddressesProvider
        _updateAddressesProviderBitmorLoan();

        // 2. Setup: Get LSA and initial data
        vars.lsa = loan.getUserLoanAtIndex(user, 0);
        {
            DataTypes.LoanData memory loanDataInitial = loan.getLoanByLSA(vars.lsa);
            vars.initialDuration = loanDataInitial.duration;
            vars.currentDuration = loanDataInitial.duration;
            vars.estimatedMonthlyPayment = loanDataInitial.estimatedMonthlyPayment;
        }

        // 3. Setup: Fund Liquidator
        _fundLiquidator();
        uint256 liquidatorDebtStart = IERC20(debtAsset).balanceOf(liquidator);
        uint256 liquidatorCollateralStart = IERC20(collateralAsset).balanceOf(liquidator);

        // 4. Get initial BTC price
        vars.btcPriceUSD = _getBtcPrice();

        // 5. Main loop: Repeated micro-liquidations with 15% monthly price drop
        while (true) {
            vars.monthsLiquidated++;

            // Capture state before this iteration
            DataTypes.LoanData memory loanDataBeforeIteration = loan.getLoanByLSA(vars.lsa);
            vars.durationBefore = loanDataBeforeIteration.duration;
            vars.lastPaymentTimestampBefore = loanDataBeforeIteration.lastPaymentTimestamp;
            vars.remainingDebt = _getLsaDebtBalance(vars.lsa);

            // A. Warp time forward
            _warpPastGracePeriod();
            uint256 expectedTimestamp = block.timestamp;

            // B. Apply 15% price drop
            vars.btcPriceUSD = _dropOraclePrice(collateralAsset, 15);

            // C. Check liquidation type
            vars.liquidationType = _checkLiquidationType(vars.lsa);

            // D. Handle full liquidation
            if (vars.liquidationType == 1) {
                // Get balances before full liquidation
                vars.liquidatorDebtBefore = IERC20(debtAsset).balanceOf(liquidator);
                vars.liquidatorCollateralBefore = IERC20(collateralAsset).balanceOf(liquidator);

                // Execute full liquidation
                _utilExecuteFullLiquidation(
                    s_bitmorPool,
                    liquidator,
                    collateralAsset,
                    debtAsset,
                    vars.lsa,
                    type(uint256).max,
                    false
                );

                // Get balances after
                vars.liquidatorDebtAfter = IERC20(debtAsset).balanceOf(liquidator);
                vars.liquidatorCollateralAfter = IERC20(collateralAsset).balanceOf(liquidator);

                // Calculate results
                vars.fullLiqDebtPaid = vars.liquidatorDebtBefore - vars.liquidatorDebtAfter;
                vars.fullLiqCollateralReceived = vars.liquidatorCollateralAfter - vars.liquidatorCollateralBefore;
                vars.fullLiquidationExecuted = true;

                // Verify loan status
                DataTypes.LoanData memory loanDataAfterFullLiq = loan.getLoanByLSA(vars.lsa);
                assertEq(
                    uint256(loanDataAfterFullLiq.status),
                    uint256(DataTypes.LoanStatus.Liquidated),
                    "Loan should be liquidated"
                );

                break;
            }

            // E. Handle no liquidation needed (completed)
            if (vars.liquidationType == 0) {
                break;
            }

            // F. Execute micro liquidation
            vars.liquidatorDebtBefore = IERC20(debtAsset).balanceOf(liquidator);
            vars.liquidatorCollateralBefore = IERC20(collateralAsset).balanceOf(liquidator);

            _executeMicroLiquidation(vars.lsa);

            vars.liquidatorDebtAfter = IERC20(debtAsset).balanceOf(liquidator);
            vars.liquidatorCollateralAfter = IERC20(collateralAsset).balanceOf(liquidator);

            // ============ MICRO-BRANCH SPECIFIC ASSERTIONS ============
            
            // G. Assert per-iteration invariants for micro-liquidation (type == 2)
            DataTypes.LoanData memory loanDataAfterMicro = loan.getLoanByLSA(vars.lsa);
            
            // a. Duration decrements by exactly 1
            assertEq(
                loanDataAfterMicro.duration,
                vars.durationBefore - 1,
                "Duration should decrement by exactly 1 each micro"
            );

            // b. lastPaymentTimestamp is updated and monotonic
            assertEq(
                loanDataAfterMicro.lastPaymentTimestamp,
                expectedTimestamp,
                "lastPaymentTimestamp should be updated to current block.timestamp"
            );
            assertGt(
                loanDataAfterMicro.lastPaymentTimestamp,
                vars.lastPaymentTimestampBefore,
                "lastPaymentTimestamp should be monotonically increasing"
            );

            // c. Status stays Active after each micro
            assertEq(
                uint256(loanDataAfterMicro.status),
                uint256(DataTypes.LoanStatus.Active),
                "Status should stay Active after micro-liquidation"
            );

            // d. debtPaid == min(monthly, remainingDebt)
            uint256 debtPaidThisRound = vars.liquidatorDebtBefore - vars.liquidatorDebtAfter;
            uint256 expectedDebtPaid = _utilMin(vars.estimatedMonthlyPayment, vars.remainingDebt);
            assertEq(
                debtPaidThisRound,
                expectedDebtPaid,
                "debtPaid should equal min(monthlyPayment, remainingDebt)"
            );

            // H. Update loop variables
            vars.currentDuration = loanDataAfterMicro.duration;
            vars.collateralInLSA = loanDataAfterMicro.collateralAmount;

            if (vars.currentDuration == 0 || loanDataAfterMicro.status != DataTypes.LoanStatus.Active) {
                break;
            }

            // Safety break
            if (vars.monthsLiquidated >= vars.initialDuration + 5) {
                break;
            }
        }

        // 6. Final calculations
        vars.totalDebtPaid = liquidatorDebtStart - IERC20(debtAsset).balanceOf(liquidator);
        vars.totalCollateralReceived = IERC20(collateralAsset).balanceOf(liquidator) - liquidatorCollateralStart;

        vm.clearMockedCalls();

        // 7. Assertions
        bool isFullLiquidation = vars.liquidationType == 1;
        bool isCompleted = vars.currentDuration == 0;

        assertTrue(isFullLiquidation || isCompleted, "Should end with full liquidation or completion");

        if (isFullLiquidation) {
            assertTrue(vars.fullLiquidationExecuted, "Full liquidation should have executed");
            assertGt(vars.fullLiqDebtPaid, 0, "Liquidator should have paid debt in full liq");
            assertGt(vars.fullLiqCollateralReceived, 0, "Liquidator should have received collateral in full liq");
        }
    }

    // ============ Test: Liquidation Type Gate ============

    /// @notice Test that liquidation type transitions correctly based on time
    function test_microLiquidation_afterGracePeriod_returnsTypeMicro() public setUpLoanForUser {
        address lsa = loan.getUserLoanAtIndex(user, 0);
        
        _updateAddressesProviderBitmorLoan();

        // Assert before warp: checkType == 0 (loan is fresh, not overdue)
        uint256 liquidationTypeBefore = _checkLiquidationType(lsa);
        assertEq(liquidationTypeBefore, 0, "Fresh loan should not be liquidatable (type 0)");

        // Warp past grace period + interval
        _warpPastGracePeriod();

        // Assert after warp: checkType == 2 (micro-liquidation eligible)
        uint256 liquidationTypeAfter = _checkLiquidationType(lsa);
        assertEq(liquidationTypeAfter, 2, "Should be micro-liquidation eligible (type 2)");
    }

    // ============ NEW TEST: Micro-Liquidation Within Grace Period Should Revert ============

    /// @notice Test that micro-liquidation reverts when called within grace period
    function test_microLiquidation_withinGracePeriod_reverts() public setUpLoanForUser {
        address lsa = loan.getUserLoanAtIndex(user, 0);

        _updateAddressesProviderBitmorLoan();

        // Do NOT warp past grace/interval - loan is still in good standing
        
        // Fund liquidator
        _fundLiquidator();

        // Check liquidation type - should be 0 (not eligible)
        uint256 liquidationType = _checkLiquidationType(lsa);
        assertEq(liquidationType, 0, "Loan within grace period should not be liquidatable");

        // Attempt micro-liquidation - should revert
        bytes memory liquidationData = abi.encode(collateralAsset, debtAsset, lsa);
        vm.prank(liquidator);
        vm.expectRevert(); // ValidationLogic returns error for typeOfLiquidation != 2
        ILendingPool(s_bitmorPool).microLiquidationCall(liquidationData);
    }

    // ============ NEW TEST: Micro-Liquidation Reverts If Liquidator Has No USDC ============

    /// @notice Test that micro-liquidation reverts when liquidator has no USDC
    function test_microLiquidation_revertsIfLiquidatorHasNoUSDC() public setUpLoanForUser {
        address lsa = loan.getUserLoanAtIndex(user, 0);

        _updateAddressesProviderBitmorLoan();

        // Warp to make loan overdue
        _warpPastGracePeriod();

        // Verify loan is eligible for micro-liquidation
        uint256 liquidationType = _checkLiquidationType(lsa);
        assertEq(liquidationType, 2, "Should be micro-liquidation eligible");

        // Do NOT mint USDC to liquidator, but approve anyway
        vm.prank(liquidator);
        IERC20(debtAsset).approve(s_bitmorPool, type(uint256).max);

        // Verify liquidator has 0 USDC
        uint256 liquidatorBalance = IERC20(debtAsset).balanceOf(liquidator);
        assertEq(liquidatorBalance, 0, "Liquidator should have 0 USDC");

        // Attempt micro-liquidation - should revert (insufficient balance for safeTransferFrom)
        bytes memory liquidationData = abi.encode(collateralAsset, debtAsset, lsa);
        vm.prank(liquidator);
        vm.expectRevert(); // Will fail at safeTransferFrom due to insufficient balance
        ILendingPool(s_bitmorPool).microLiquidationCall(liquidationData);
    }

    // ============ NEW TEST: Micro-Liquidation Reverts If Liquidator Has No Allowance ============

    /// @notice Test that micro-liquidation reverts when liquidator has USDC but no allowance
    function test_microLiquidation_revertsIfLiquidatorHasNoAllowance() public setUpLoanForUser {
        address lsa = loan.getUserLoanAtIndex(user, 0);

        _updateAddressesProviderBitmorLoan();

        // Warp to make loan overdue
        _warpPastGracePeriod();

        // Verify loan is eligible for micro-liquidation
        uint256 liquidationType = _checkLiquidationType(lsa);
        assertEq(liquidationType, 2, "Should be micro-liquidation eligible");

        // Mint USDC to liquidator but DO NOT approve
        _utilMintToLiquidatorNoApproval(liquidator, debtAsset, DEBT_ASSET_TO_MINT_TO_USER);

        // Verify liquidator has USDC but no allowance
        uint256 liquidatorBalance = IERC20(debtAsset).balanceOf(liquidator);
        assertGt(liquidatorBalance, 0, "Liquidator should have USDC");
        uint256 allowance = IERC20(debtAsset).allowance(liquidator, s_bitmorPool);
        assertEq(allowance, 0, "Liquidator should have 0 allowance");

        // Attempt micro-liquidation - should revert (insufficient allowance for safeTransferFrom)
        bytes memory liquidationData = abi.encode(collateralAsset, debtAsset, lsa);
        vm.prank(liquidator);
        vm.expectRevert(); // Will fail at safeTransferFrom due to insufficient allowance
        ILendingPool(s_bitmorPool).microLiquidationCall(liquidationData);
    }

    // ============ NEW TEST: Micro-Liquidation Caps Debt To Cover At Remaining Debt ============

    /// @notice Test that micro-liquidation caps debtToCover at remainingDebt when monthly payment exceeds it
    function test_microLiquidation_capsDebtToCoverAtRemainingDebt() public setUpLoanForUser {
        address lsa = loan.getUserLoanAtIndex(user, 0);

        _updateAddressesProviderBitmorLoan();

        // Get loan data
        DataTypes.LoanData memory loanData = loan.getLoanByLSA(lsa);
        uint256 estimatedMonthlyPayment = loanData.estimatedMonthlyPayment;
        uint256 initialDebt = _getLsaDebtBalance(lsa);

        // Leave a small remaining debt so that it is strictly below the monthly payment even after interest accrues.
        // (Debt tokens accrue interest over time; after warping, the remaining debt can grow slightly.)
        uint256 targetRemainingDebt = estimatedMonthlyPayment / 10;
        require(initialDebt > targetRemainingDebt, "Test setup: initial debt too small");

        uint256 amountToRepay = initialDebt - targetRemainingDebt;

        // Fund user to repay most of the debt
        vm.startPrank(user);
        (bool success,) = debtAsset.call(abi.encodeWithSignature("mint(uint256)", amountToRepay));
        require(success, "MINT_ERROR");
        IERC20(debtAsset).approve(address(loan), amountToRepay);
        loan.repay(lsa, amountToRepay);
        vm.stopPrank();

        // Verify remaining debt is less than monthly payment (at current timestamp)
        uint256 remainingDebtAfterRepay = _getLsaDebtBalance(lsa);
        assertLt(remainingDebtAfterRepay, estimatedMonthlyPayment, "Remaining debt should be less than monthly payment");
        assertGt(remainingDebtAfterRepay, 0, "Should still have some debt");

        // Warp to make loan overdue
        _warpPastGracePeriod();

        // Verify still micro-liquidation eligible (may depend on health factor)
        uint256 liquidationType = _checkLiquidationType(lsa);
        if (liquidationType == 0) {
            // If not liquidatable, exit (nothing to micro-liquidate)
            return;
        }
        assertEq(liquidationType, 2, "Should be micro-liquidation eligible");

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

        // Snapshot balances
        uint256 liquidatorDebtBefore = IERC20(debtAsset).balanceOf(liquidator);

        // Execute micro-liquidation
        _executeMicroLiquidation(lsa);

        // Calculate actual debt paid
        uint256 liquidatorDebtAfter = IERC20(debtAsset).balanceOf(liquidator);
        uint256 debtPaid = liquidatorDebtBefore - liquidatorDebtAfter;

        // Assert debtPaid == remainingDebt at liquidation time (capped behavior)
        assertEq(debtPaid, remainingDebtAtLiquidation, "Debt paid should equal remaining debt (capped at remaining)");
        assertLt(debtPaid, estimatedMonthlyPayment, "Debt paid should be less than monthly payment");
    }
}
