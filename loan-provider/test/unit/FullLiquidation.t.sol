// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.30;

import {BaseLoanTest} from "./BaseLoanTest.t.sol";
import {DataTypes} from "@bitmor/libraries/types/DataTypes.sol";
import {IERC20} from "@bitmor/dependencies/openzeppelin/IERC20.sol";
import {ILendingPool} from "@bitmor/interfaces/ILendingPool.sol";
import {ILendingPoolAddressesProvider} from "@bitmor/interfaces/ILendingPoolAddressesProvider.sol";
import {IPriceOracleGetter} from "@bitmor/interfaces/IPriceOracleGetter.sol";

/// @title FullLiquidationTest
/// @notice Tests for full liquidation functionality (liquidationType == 1)
/// @dev Full liquidation occurs when health factor drops below 1 or collateral can't cover micro-liq
contract FullLiquidationTest is BaseLoanTest {
    
    // ============ Structs ============

    /// @dev Struct to hold full liquidation test variables
    struct FullLiquidationTestVars {
        address lsa;
        uint256 liquidatorDebtBefore;
        uint256 liquidatorCollateralBefore;
        uint256 liquidatorDebtAfter;
        uint256 liquidatorCollateralAfter;
        uint256 debtPaid;
        uint256 collateralReceived;
        uint256 btcPriceUSD;
        uint256 usdcPriceUSD;
        DataTypes.LoanStatus statusAfter;
        uint256 durationAfter;
    }

    // ============ Local Test Helpers ============

    /// @dev Setup loan for full liquidation scenario (drop price to trigger HF < 1)
    function _setupForFullLiquidation(address lsa) internal returns (uint256 liquidationType) {
        _warpPastGracePeriod();
        
        // Drop price significantly to push health factor < 1
        _dropOraclePrice(collateralAsset, 50);

        liquidationType = _checkLiquidationType(lsa);
    }

    // Helper: mutate stored loanData to simulate an insurance activation
    function _setInsuranceId(address lsa, uint256 newInsuranceId) internal {
        DataTypes.LoanData memory data = loan.getLoanByLSA(lsa);
        data.insuranceID = newInsuranceId;

        loan.updateLoanData(abi.encode(data), lsa);

        // sanity check
        DataTypes.LoanData memory afterData = loan.getLoanByLSA(lsa);
        assertEq(afterData.insuranceID, newInsuranceId, "Insurance ID should be updated");
    }

    // ============ Test: Full Liquidation Updates Loan Status ============

    /// @notice Test that full liquidation correctly updates loan status to Liquidated
    function test_fullLiquidation_updatesLoanStatus() public setUpLoanForUser {
        FullLiquidationTestVars memory vars;
        
        vars.lsa = loan.getUserLoanAtIndex(user, 0);

        _updateAddressesProviderBitmorLoan();

        // Setup for full liquidation
        uint256 liquidationType = _setupForFullLiquidation(vars.lsa);
        assertEq(liquidationType, 1, "Should be full liquidation type");

        // Fund liquidator
        _fundLiquidator();

        // Snapshot balances before
        (vars.liquidatorDebtBefore, vars.liquidatorCollateralBefore) = _snapshotLiquidatorBalances();

        // Execute full liquidation
        _executeFullLiquidation(vars.lsa, type(uint256).max, false);

        // Snapshot balances after
        (vars.liquidatorDebtAfter, vars.liquidatorCollateralAfter) = _snapshotLiquidatorBalances();

        // Get loan data after
        DataTypes.LoanData memory loanDataAfter = loan.getLoanByLSA(vars.lsa);
        vars.statusAfter = loanDataAfter.status;
        vars.durationAfter = loanDataAfter.duration;

        // ============ ASSERTIONS ============

        // 1. Loan status should be Liquidated
        assertEq(
            uint256(vars.statusAfter),
            uint256(DataTypes.LoanStatus.Liquidated),
            "Loan should be liquidated"
        );

        // 2. Duration should be 0
        assertEq(vars.durationAfter, 0, "Duration should be 0 after full liquidation");

        // 3. Liquidator should have paid debt
        vars.debtPaid = vars.liquidatorDebtBefore - vars.liquidatorDebtAfter;
        assertGt(vars.debtPaid, 0, "Liquidator should have paid debt");

        // 4. Liquidator should have received collateral
        vars.collateralReceived = vars.liquidatorCollateralAfter - vars.liquidatorCollateralBefore;
        assertGt(vars.collateralReceived, 0, "Liquidator should have received collateral");
    }

    // ============ Test: Full Liquidation Triggered by Low Health Factor ============

    /// @notice Test that low health factor triggers full liquidation type
    function test_fullLiquidation_lowHealthFactor_returnsTypeFull() public setUpLoanForUser {
        address lsa = loan.getUserLoanAtIndex(user, 0);
        
        _updateAddressesProviderBitmorLoan();

        _warpPastGracePeriod();
        
        // Drop price significantly to push health factor < 1
        _dropOraclePrice(collateralAsset, 50);

        uint256 liquidationType = _checkLiquidationType(lsa);
        assertEq(liquidationType, 1, "Should be full liquidation eligible");
    }

    // ============ Test: Full Liquidation With Partial Debt Coverage ============

    /// @notice Test full liquidation with specified debt amount (not max)
    function test_fullLiquidation_partialDebtCoverage() public setUpLoanForUser {
        FullLiquidationTestVars memory vars;

        vars.lsa = loan.getUserLoanAtIndex(user, 0);

        _updateAddressesProviderBitmorLoan();

        // Setup for full liquidation
        uint256 liquidationType = _setupForFullLiquidation(vars.lsa);
        assertEq(liquidationType, 1, "Should be full liquidation type");

        // Get initial debt
        uint256 initialDebt = _getLsaDebtBalance(vars.lsa);

        // Cover only half the debt
        uint256 debtToCover = initialDebt / 2;

        // Fund liquidator
        _fundLiquidator();

        // Full liquidation should NOT allow partial debt coverage
        vm.prank(liquidator);
        vm.expectRevert();
        ILendingPool(s_bitmorPool).liquidationCall(
            collateralAsset,
            debtAsset,
            vars.lsa,
            debtToCover,
            false
        );
    }


    // ============ Test: Full Liquidation Receives aTokens ============

    /// @notice Test full liquidation with receiveAToken = true
    function test_fullLiquidation_receivesATokens() public setUpLoanForUser {
        FullLiquidationTestVars memory vars;
        
        vars.lsa = loan.getUserLoanAtIndex(user, 0);

        _updateAddressesProviderBitmorLoan();

        // Setup for full liquidation
        uint256 liquidationType = _setupForFullLiquidation(vars.lsa);
        assertEq(liquidationType, 1, "Should be full liquidation type");

        // Fund liquidator
        _fundLiquidator();

        // Get collateral aToken address
        address collateralAToken = _utilGetATokenAddress(s_bitmorPool, collateralAsset);
        
        // Snapshot aToken balance before
        uint256 liquidatorATokenBefore = IERC20(collateralAToken).balanceOf(liquidator);
        uint256 liquidatorCollateralBefore = IERC20(collateralAsset).balanceOf(liquidator);
        uint256 liquidatorDebtBefore = IERC20(debtAsset).balanceOf(liquidator);

        // Execute full liquidation requesting aTokens
        _executeFullLiquidation(vars.lsa, type(uint256).max, true);

        // Snapshot balances after
        uint256 liquidatorATokenAfter = IERC20(collateralAToken).balanceOf(liquidator);
        uint256 liquidatorCollateralAfter = IERC20(collateralAsset).balanceOf(liquidator);
        uint256 liquidatorDebtAfter = IERC20(debtAsset).balanceOf(liquidator);

        // Calculate amounts
        uint256 aTokenReceived = liquidatorATokenAfter - liquidatorATokenBefore;
        uint256 underlyingReceived = liquidatorCollateralAfter - liquidatorCollateralBefore;
        vars.debtPaid = liquidatorDebtBefore - liquidatorDebtAfter;

        // ============ ASSERTIONS ============

        // 1. Liquidator should have received aTokens
        assertGt(aTokenReceived, 0, "Liquidator should have received aTokens");

        // 2. Liquidator should NOT have received underlying collateral
        assertEq(underlyingReceived, 0, "Liquidator should not receive underlying when receiveAToken=true");

        // 3. Liquidator should have paid debt
        assertGt(vars.debtPaid, 0, "Liquidator should have paid debt");

        // 4. Loan status should be Liquidated
        DataTypes.LoanData memory loanDataAfter = loan.getLoanByLSA(vars.lsa);
        assertEq(
            uint256(loanDataAfter.status),
            uint256(DataTypes.LoanStatus.Liquidated),
            "Loan should be liquidated"
        );
    }

    // ============ Test: Full Liquidation Reverts on Healthy Loan ============

    /// @notice Test that full liquidation reverts when loan is healthy (type != 1)
    function test_fullLiquidation_revertsOnHealthyLoan() public setUpLoanForUser {
        address lsa = loan.getUserLoanAtIndex(user, 0);

        _updateAddressesProviderBitmorLoan();

        // Do NOT warp or drop price - loan is healthy
        
        // Check liquidation type - should be 0
        uint256 liquidationType = _checkLiquidationType(lsa);
        assertEq(liquidationType, 0, "Fresh loan should not be liquidatable");

        // Fund liquidator
        _fundLiquidator();

        // Attempt full liquidation - should revert
        vm.prank(liquidator);
        vm.expectRevert(); // ValidationLogic returns error for typeOfLiquidation != 1
        ILendingPool(s_bitmorPool).liquidationCall(
            collateralAsset,
            debtAsset,
            lsa,
            type(uint256).max,
            false
        );
    }

    // ============ Test: Full Liquidation Reverts on Micro-Liquidation Eligible Loan ============

    /// @notice Test that full liquidation reverts when loan is only micro-liquidation eligible
    function test_fullLiquidation_revertsOnMicroEligibleLoan() public setUpLoanForUser {
        address lsa = loan.getUserLoanAtIndex(user, 0);

        _updateAddressesProviderBitmorLoan();

        // Warp to make overdue but don't drop price (stay at type 2)
        _warpPastGracePeriod();

        // Check liquidation type - should be 2 (micro)
        uint256 liquidationType = _checkLiquidationType(lsa);
        assertEq(liquidationType, 2, "Should be micro-liquidation eligible");

        // Fund liquidator
        _fundLiquidator();

        // Attempt full liquidation - should revert
        vm.prank(liquidator);
        vm.expectRevert(); // ValidationLogic returns error for typeOfLiquidation != 1
        ILendingPool(s_bitmorPool).liquidationCall(
            collateralAsset,
            debtAsset,
            lsa,
            type(uint256).max,
            false
        );
    }

    // ============ Test: Full Liquidation USDC Goes to Debt aToken ============

    /// @notice Test that USDC from liquidator is transferred to debt aToken
    function test_fullLiquidation_debtTransferredToAToken() public setUpLoanForUser {
        FullLiquidationTestVars memory vars;
        
        vars.lsa = loan.getUserLoanAtIndex(user, 0);

        _updateAddressesProviderBitmorLoan();

        // Setup for full liquidation
        uint256 liquidationType = _setupForFullLiquidation(vars.lsa);
        assertEq(liquidationType, 1, "Should be full liquidation type");

        // Get debt aToken address
        address debtATokenAddr = _getDebtATokenAddress();

        // Fund liquidator
        _fundLiquidator();

        // Snapshot balances before
        uint256 debtATokenBefore = IERC20(debtAsset).balanceOf(debtATokenAddr);
        (vars.liquidatorDebtBefore,) = _snapshotLiquidatorBalances();

        // Execute full liquidation
        _executeFullLiquidation(vars.lsa, type(uint256).max, false);

        // Snapshot balances after
        uint256 debtATokenAfter = IERC20(debtAsset).balanceOf(debtATokenAddr);
        (vars.liquidatorDebtAfter,) = _snapshotLiquidatorBalances();

        // Calculate amounts
        vars.debtPaid = vars.liquidatorDebtBefore - vars.liquidatorDebtAfter;
        uint256 debtATokenIncrease = debtATokenAfter - debtATokenBefore;

        // ============ ASSERTIONS ============

        // 1. Debt aToken balance should increase by exactly the debt paid
        assertEq(debtATokenIncrease, vars.debtPaid, "Debt aToken should receive exact debt paid amount");
    }

    // ============ Test: Full Liquidation Liquidator Receives Bonus ============

    /// @notice Test that liquidator receives liquidation bonus on full liquidation
    function test_fullLiquidation_liquidatorReceivesBonus() public setUpLoanForUser {
        FullLiquidationTestVars memory vars;
        
        vars.lsa = loan.getUserLoanAtIndex(user, 0);

        _updateAddressesProviderBitmorLoan();

        // Setup for full liquidation
        uint256 liquidationType = _setupForFullLiquidation(vars.lsa);
        assertEq(liquidationType, 1, "Should be full liquidation type");

        // Fund liquidator
        _fundLiquidator();

        // Snapshot balances before
        (vars.liquidatorDebtBefore, vars.liquidatorCollateralBefore) = _snapshotLiquidatorBalances();

        // Execute full liquidation
        _executeFullLiquidation(vars.lsa, type(uint256).max, false);

        // Snapshot balances after
        (vars.liquidatorDebtAfter, vars.liquidatorCollateralAfter) = _snapshotLiquidatorBalances();

        // Calculate amounts
        vars.debtPaid = vars.liquidatorDebtBefore - vars.liquidatorDebtAfter;
        vars.collateralReceived = vars.liquidatorCollateralAfter - vars.liquidatorCollateralBefore;

        // Get prices
        vars.btcPriceUSD = _getBtcPrice();
        vars.usdcPriceUSD = _getUsdcPrice();

        // Calculate USD values
        uint256 collateralValueUSD = (vars.collateralReceived * vars.btcPriceUSD) / 1e8;
        uint256 debtPaidIn8Decimals = vars.debtPaid * 1e2; // Convert 6 decimals to 8

        // ============ ASSERTIONS ============

        // 1. Collateral value should exceed debt paid (liquidation bonus)
        assertGt(collateralValueUSD, debtPaidIn8Decimals, "Collateral value should exceed debt paid (bonus)");
    }

    // ============ Test: Full Liquidation Reverts If Liquidator Has No USDC ============

    /// @notice Test that full liquidation reverts when liquidator has no USDC
    function test_fullLiquidation_revertsIfLiquidatorHasNoUSDC() public setUpLoanForUser {
        address lsa = loan.getUserLoanAtIndex(user, 0);

        _updateAddressesProviderBitmorLoan();

        // Setup for full liquidation
        uint256 liquidationType = _setupForFullLiquidation(lsa);
        assertEq(liquidationType, 1, "Should be full liquidation type");

        // Do NOT fund liquidator, but approve
        vm.prank(liquidator);
        IERC20(debtAsset).approve(s_bitmorPool, type(uint256).max);

        // Verify liquidator has 0 USDC
        uint256 liquidatorBalance = IERC20(debtAsset).balanceOf(liquidator);
        assertEq(liquidatorBalance, 0, "Liquidator should have 0 USDC");

        // Attempt full liquidation - should revert
        vm.prank(liquidator);
        vm.expectRevert(); // Will fail at safeTransferFrom
        ILendingPool(s_bitmorPool).liquidationCall(
            collateralAsset,
            debtAsset,
            lsa,
            type(uint256).max,
            false
        );
    }

    // ============ Test: Full Liquidation Reverts If Liquidator Has No Allowance ============

    /// @notice Test that full liquidation reverts when liquidator has USDC but no allowance
    function test_fullLiquidation_revertsIfLiquidatorHasNoAllowance() public setUpLoanForUser {
        address lsa = loan.getUserLoanAtIndex(user, 0);

        _updateAddressesProviderBitmorLoan();

        // Setup for full liquidation
        uint256 liquidationType = _setupForFullLiquidation(lsa);
        assertEq(liquidationType, 1, "Should be full liquidation type");

        // Mint USDC to liquidator but DO NOT approve
        _utilMintToLiquidatorNoApproval(liquidator, debtAsset, DEBT_ASSET_TO_MINT_TO_USER);

        // Verify liquidator has USDC but no allowance
        uint256 liquidatorBalance = IERC20(debtAsset).balanceOf(liquidator);
        assertGt(liquidatorBalance, 0, "Liquidator should have USDC");
        uint256 allowance = IERC20(debtAsset).allowance(liquidator, s_bitmorPool);
        assertEq(allowance, 0, "Liquidator should have 0 allowance");

        // Attempt full liquidation - should revert
        vm.prank(liquidator);
        vm.expectRevert(); // Will fail at safeTransferFrom
        ILendingPool(s_bitmorPool).liquidationCall(
            collateralAsset,
            debtAsset,
            lsa,
            type(uint256).max,
            false
        );
    }


    /// @notice If HF < 1 due to price drop, and payment is NOT due yet, the loan should be
    ///         full-liquidatable when there is NO insurance ID.
    function test_fullLiquidation_priceDropBeforePaymentDue_noInsurance_liquidates() public setUpLoanForUser {
        address lsa = loan.getUserLoanAtIndex(user, 0);

        _updateAddressesProviderBitmorLoan();

        // IMPORTANT: Do NOT warp — payment is not due yet (fresh loan).
        // Force HF < 1 via a sharp collateral price drop
        _dropOraclePrice(collateralAsset, 50);

        // Should be full liquidation eligible when not insured
        uint256 liquidationType = _checkLiquidationType(lsa);
        assertEq(liquidationType, 1, "HF < 1 should allow full liquidation when not insured");

        // Fund liquidator and execute full liquidation
        _fundLiquidator();

        vm.prank(liquidator);
        ILendingPool(s_bitmorPool).liquidationCall(
            collateralAsset,
            debtAsset,
            lsa,
            type(uint256).max,
            false
        );

        // Assert status is liquidated
        DataTypes.LoanData memory loanDataAfter = loan.getLoanByLSA(lsa);
        assertEq(
            uint256(loanDataAfter.status),
            uint256(DataTypes.LoanStatus.Liquidated),
            "Loan should be liquidated"
        );
    }

    /// @notice If HF < 1 due to price drop, and payment is NOT due yet, the loan should NOT be
    ///         liquidatable when there IS an insurance ID.
    function test_fullLiquidation_priceDropBeforePaymentDue_withInsurance_doesNotLiquidate() public setUpLoanForUser {
        address lsa = loan.getUserLoanAtIndex(user, 0);

        _updateAddressesProviderBitmorLoan();

        // Simulate an insured position by setting a non-zero insuranceID
        _setInsuranceId(lsa, 1);

        // Do NOT warp — payment is not due yet (fresh loan).
        // Force HF < 1 via a sharp collateral price drop
        _dropOraclePrice(collateralAsset, 50);

        // Should NOT be liquidatable when insured (pre-due)
        uint256 liquidationType = _checkLiquidationType(lsa);
        assertEq(liquidationType, 0, "HF < 1 should NOT be liquidatable pre-due when insured");

        // Even if liquidator is funded, liquidationCall should revert
        _fundLiquidator();

        vm.prank(liquidator);
        vm.expectRevert(); // ValidationLogic should block since type != 1
        ILendingPool(s_bitmorPool).liquidationCall(
            collateralAsset,
            debtAsset,
            lsa,
            type(uint256).max,
            false
        );
    }




}
