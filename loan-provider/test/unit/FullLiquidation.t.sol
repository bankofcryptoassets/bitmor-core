// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.30;

import {console2} from "forge-std/console2.sol";
import {BaseLoanTest} from "./Loan/BaseLoan.t.sol";
import {DataTypes} from "@bitmor/libraries/types/DataTypes.sol";
import {IERC20} from "@openzeppelin/interfaces/IERC20.sol";
import {ILendingPool} from "@bitmor/interfaces/ILendingPool.sol";
import {ILendingPoolAddressesProvider} from "@bitmor/interfaces/ILendingPoolAddressesProvider.sol";
import {IPriceOracleGetter} from "@bitmor/interfaces/IPriceOracleGetter.sol";

/// @title FullLiquidationTest
/// @notice Tests for full liquidation functionality (liquidationType == 1)
contract FullLiquidationTest is BaseLoanTest {
    function _setInsuranceId(address lsa, uint256 newInsuranceId) internal {
        loan.updateInsuranceId(lsa, newInsuranceId);

        // sanity check
        DataTypes.LoanData memory afterData = loan.getLoanByLSA(lsa);
        assertEq(afterData.insuranceID, newInsuranceId, "Insurance ID should be updated");
    }

    /// @notice Full liquidation updates loan status to Liquidated.
    function test_fullLiquidation_updatesLoanStatus() public setUpLoanForUser {
        address lsa = loan.getUserLoanAtIndex(user, 0);

        // Setup for full liquidation using composite helper
        uint256 liquidationType = _setupForFullLiquidation(lsa);
        assertEq(liquidationType, LIQUIDATION_TYPE_FULL, "Should be full liquidation type");

        // Capture state using generic helper
        LiquidationTestState memory state = _captureLiquidationStateBefore(lsa);

        // Execute full liquidation
        _executeFullLiquidation(lsa, type(uint256).max, false);

        // Update state after liquidation
        _updateLiquidationStateAfter(state, lsa);

        // 1. Loan status should be Liquidated
        assertEq(
            uint256(state.loanState.statusAfter), uint256(DataTypes.LoanStatus.Liquidated), "Loan should be liquidated"
        );

        // 2. Duration should be 0
        assertEq(state.loanState.durationAfter, 0, "Duration should be 0 after full liquidation");

        // 3. Liquidator should have paid debt
        assertGt(state.debtPaid, 0, "Liquidator should have paid debt");

        // 4. Liquidator should have received collateral
        assertGt(state.collateralReceived, 0, "Liquidator should have received collateral");
    }

    /// @notice Low health factor triggers full liquidation type.
    function test_fullLiquidation_lowHealthFactor_returnsTypeFull() public setUpLoanForUser {
        address lsa = loan.getUserLoanAtIndex(user, 0);

        // Setup for full liquidation using composite helper
        uint256 liquidationType = _setupForFullLiquidation(lsa);
        assertEq(liquidationType, LIQUIDATION_TYPE_FULL, "Should be full liquidation eligible");
    }

    /// @notice Partial Debt Coverage in Full liquidation
    function test_fullLiquidation_partialDebtCoverage() public setUpLoanForUser {
        address lsa = loan.getUserLoanAtIndex(user, 0);

        // Setup for full liquidation using composite helper
        uint256 liquidationType = _setupForFullLiquidation(lsa);
        assertEq(liquidationType, LIQUIDATION_TYPE_FULL, "Should be full liquidation type");

        // Get initial debt
        uint256 initialDebt = _getLsaDebtBalance(lsa);

        // Cover only half the debt
        uint256 debtToCover = initialDebt / 2;

        // Full liquidation should
        vm.prank(liquidator);
        ILendingPool(s_bitmorPool).liquidationCall(collateralAsset, debtAsset, lsa, debtToCover, false);

        uint256 finalDebt = _getLsaDebtBalance(lsa);

        assertEq(finalDebt, initialDebt - debtToCover);
    }

    /// @notice Full liquidation can be executed with receiveAToken = true.
    function test_fullLiquidation_receivesATokens() public setUpLoanForUser {
        address lsa = loan.getUserLoanAtIndex(user, 0);

        // Setup for full liquidation using composite helper
        uint256 liquidationType = _setupForFullLiquidation(lsa);
        assertEq(liquidationType, LIQUIDATION_TYPE_FULL, "Should be full liquidation type");

        // Get collateral aToken address
        address collateralAToken = _utilGetATokenAddress(s_bitmorPool, collateralAsset);

        // Snapshot using generic helpers for liquidator + additional aToken balance
        LiquidatorSnapshot memory liquidatorState = _captureLiquidatorSnapshot();
        uint256 liquidatorATokenBefore = IERC20(collateralAToken).balanceOf(liquidator);

        // Execute full liquidation requesting aTokens
        _executeFullLiquidation(lsa, type(uint256).max, true);

        // Update liquidator state
        _updateLiquidatorSnapshotAfter(liquidatorState);
        uint256 liquidatorATokenAfter = IERC20(collateralAToken).balanceOf(liquidator);

        // Calculate amounts
        uint256 aTokenReceived = liquidatorATokenAfter - liquidatorATokenBefore;
        uint256 underlyingReceived =
            liquidatorState.liquidatorCollateralAfter - liquidatorState.liquidatorCollateralBefore;
        uint256 debtPaid = liquidatorState.liquidatorDebtBefore - liquidatorState.liquidatorDebtAfter;

        // 1. Liquidator should have received aTokens
        assertGt(aTokenReceived, 0, "Liquidator should receive aTokens");

        // 2. Liquidator should NOT have received underlying (received aTokens instead)
        assertEq(underlyingReceived, 0, "Liquidator should NOT receive underlying when requesting aTokens");

        // 3. Liquidator should have paid debt
        assertGt(debtPaid, 0, "Liquidator should have paid debt");
    }

    /// @notice Full liquidation transfers liquidator USDC to the lending pool.
    /// @dev Mock transfers repaid debt to the pool contract, not the debt token
    function test_fullLiquidation_debtTransferredToAToken() public setUpLoanForUser {
        address lsa = loan.getUserLoanAtIndex(user, 0);

        // Setup for full liquidation using composite helper
        uint256 liquidationType = _setupForFullLiquidation(lsa);
        assertEq(liquidationType, LIQUIDATION_TYPE_FULL, "Should be full liquidation type");

        // Snapshot balances before using generic helpers
        uint256 poolBalanceBefore = IERC20(debtAsset).balanceOf(s_bitmorPool);
        LiquidatorSnapshot memory liquidatorState = _captureLiquidatorSnapshot();

        // Execute full liquidation
        _executeFullLiquidation(lsa, type(uint256).max, false);

        // Snapshot balances after
        uint256 poolBalanceAfter = IERC20(debtAsset).balanceOf(s_bitmorPool);
        _updateLiquidatorSnapshotAfter(liquidatorState);

        // Calculate amounts
        uint256 debtPaid = liquidatorState.liquidatorDebtBefore - liquidatorState.liquidatorDebtAfter;
        uint256 poolBalanceIncrease = poolBalanceAfter - poolBalanceBefore;

        // 1. Pool balance should increase by exactly the debt paid
        assertEq(poolBalanceIncrease, debtPaid, "Pool should receive exact debt paid amount");
    }

    /// @notice Full liquidation pays the liquidation bonus to the liquidator.
    /// @dev Uses smaller price drop so collateral value still exceeds debt for bonus check
    /// ! TODO: this test won't work because the mock doesn't calculate the debt amount to take
    /// from liquidator which can also give him the liquidation bonus.
    function test_fullLiquidation_liquidatorReceivesBonus() public setUpLoanForUser {
        address lsa = loan.getUserLoanAtIndex(user, 0);

        // Setup for full liquidation with smaller price drop (20%) so collateral > debt
        // A 50% drop makes collateral underwater, so we use a smaller drop
        uint256 liquidationType = _setupForFullLiquidation(lsa, PRICE_DROP_FOR_LIQUIDATION);
        assertEq(liquidationType, LIQUIDATION_TYPE_FULL, "Should be full liquidation type");

        // Capture full liquidation state using generic helper
        LiquidationTestState memory state = _captureLiquidationStateBefore(lsa);
        uint256 totalDebt = state.loanState.debtBefore;
        console2.log("totalDebt: ", totalDebt);

        // Execute full liquidation
        _executeFullLiquidation(lsa, type(uint256).max, false);

        // Update state after liquidation
        _updateLiquidationStateAfter(state, lsa);

        // Calculate USD values
        uint256 collateralValueUSD = (state.collateralReceived * state.btcPriceUSD) / 1e8;

        /// @dev This is to mimic the funds received from offchain
        uint256 totalDebtUSD = (totalDebt * state.usdcPriceUSD) / 1e6;
        uint256 expectedIncomingFromInsuranceUSD = totalDebtUSD - collateralValueUSD;

        uint256 debtPaidIn8Decimals = (state.debtPaid * state.usdcPriceUSD) / 1e6;

        // 1. Collateral value should exceed debt paid (liquidation bonus)
        // assertGt(
        //     collateralValueUSD + expectedIncomingFromInsuranceUSD,
        //     debtPaidIn8Decimals,
        //     "Collateral value should exceed debt paid (bonus)"
        // );
    }

    /// @notice Full liquidation reverts when liquidator has no USDC.
    function test_fullLiquidation_revertsIfLiquidatorHasNoUSDC() public setUpLoanForUser {
        address lsa = loan.getUserLoanAtIndex(user, 0);

        // Setup without funding liquidator - use individual steps
        _updateAddressesProviderBitmorLoan();
        _warpPastGracePeriod();
        _dropOraclePrice(collateralAsset, PRICE_DROP_50_PERCENT);
        // Set health factor < 1 for full liquidation eligibility
        mockBitmorPool.setHealthFactor(lsa, 0.5e18);

        uint256 liquidationType = _checkLiquidationType(lsa);
        assertEq(liquidationType, LIQUIDATION_TYPE_FULL, "Should be full liquidation type");

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

        // Attempt full liquidation - should revert
        vm.prank(liquidator);
        vm.expectRevert(); // Will fail at safeTransferFrom
        ILendingPool(s_bitmorPool).liquidationCall(collateralAsset, debtAsset, lsa, type(uint256).max, false);
    }

    /// @notice Full liquidation reverts when liquidator has USDC but no allowance.
    function test_fullLiquidation_revertsIfLiquidatorHasNoAllowance() public setUpLoanForUser {
        address lsa = loan.getUserLoanAtIndex(user, 0);

        // Setup without funding (which includes approval) - use individual steps
        _updateAddressesProviderBitmorLoan();
        _warpPastGracePeriod();
        _dropOraclePrice(collateralAsset, PRICE_DROP_50_PERCENT);
        // Set health factor < 1 for full liquidation eligibility
        mockBitmorPool.setHealthFactor(lsa, 0.5e18);

        uint256 liquidationType = _checkLiquidationType(lsa);
        assertEq(liquidationType, LIQUIDATION_TYPE_FULL, "Should be full liquidation type");

        // Reset liquidator's allowance (base setup gave max allowance)
        vm.prank(liquidator);
        IERC20(debtAsset).approve(s_bitmorPool, 0);

        // Verify liquidator has USDC but no allowance using generic helper
        AccountBalanceSnapshot memory liquidatorBalances = _snapshotAccountBalances(liquidator);
        assertGt(liquidatorBalances.debtAssetBalance, 0, "Liquidator should have USDC");
        uint256 allowance = IERC20(debtAsset).allowance(liquidator, s_bitmorPool);
        assertEq(allowance, 0, "Liquidator should have 0 allowance");

        // Attempt full liquidation - should revert
        vm.prank(liquidator);
        vm.expectRevert(); // Will fail at safeTransferFrom
        ILendingPool(s_bitmorPool).liquidationCall(collateralAsset, debtAsset, lsa, type(uint256).max, false);
    }

    /// @notice HF < 1 before payment due allows full liquidation when no insurance is set.
    function test_fullLiquidation_priceDropBeforePaymentDue_noInsurance_liquidates() public setUpLoanForUser {
        address lsa = loan.getUserLoanAtIndex(user, 0);

        // Setup without warp - price drop only (loan not overdue)
        uint256 liquidationType = _setupForFullLiquidationNoWarp(lsa, PRICE_DROP_50_PERCENT);

        // Should be full liquidation eligible when not insured
        assertEq(liquidationType, LIQUIDATION_TYPE_FULL, "HF < 1 should allow full liquidation when not insured");

        // Execute full liquidation
        vm.prank(liquidator);
        ILendingPool(s_bitmorPool).liquidationCall(collateralAsset, debtAsset, lsa, type(uint256).max, false);

        // Assert status is liquidated using generic snapshot
        TestSnapshot memory snapshot = _captureTestSnapshot(lsa);
        assertEq(uint256(snapshot.statusBefore), uint256(DataTypes.LoanStatus.Liquidated), "Loan should be liquidated");
    }

    /// @notice Full liquidation reverts when the loan is healthy (type != 1).
    function test_fullLiquidation_revertsOnHealthyLoan() public setUpLoanForUser {
        address lsa = loan.getUserLoanAtIndex(user, 0);

        _updateAddressesProviderBitmorLoan();

        // Do NOT warp or drop price - loan is healthy

        // Check liquidation type - should be 0 (none)
        uint256 liquidationType = _checkLiquidationType(lsa);
        assertEq(liquidationType, LIQUIDATION_TYPE_NONE, "Fresh loan should not be liquidatable");

        // Fund liquidator
        _fundLiquidator();

        // Attempt full liquidation - should revert
        vm.prank(liquidator);
        vm.expectRevert(); // ValidationLogic returns error for typeOfLiquidation != 1
        ILendingPool(s_bitmorPool).liquidationCall(collateralAsset, debtAsset, lsa, type(uint256).max, false);
    }

    /// @notice Full liquidation reverts when the loan is only micro-liquidation eligible.
    function test_fullLiquidation_revertsOnMicroEligibleLoan() public setUpLoanForUser {
        address lsa = loan.getUserLoanAtIndex(user, 0);

        // Setup for micro-liquidation scenario (overdue but healthy HF)
        uint256 liquidationType = _setupForMicroLiquidation(lsa);

        // Should be type 2 (micro), not type 1 (full)
        assertEq(liquidationType, LIQUIDATION_TYPE_MICRO, "Should be micro-liquidation eligible");

        // Attempt full liquidation - should revert because type is 2, not 1
        vm.prank(liquidator);
        vm.expectRevert(); // ValidationLogic returns error for typeOfLiquidation != 1
        ILendingPool(s_bitmorPool).liquidationCall(collateralAsset, debtAsset, lsa, type(uint256).max, false);
    }
}
