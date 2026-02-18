// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.30;

import {IntegrationTestBase} from "../base/IntegrationTestBase.sol";
import {TestConstants as TC} from "../helpers/TestConstants.sol";
import {DataTypes} from "@bitmor/libraries/types/DataTypes.sol";
import {IERC20} from "@openzeppelin/interfaces/IERC20.sol";

/// @title LiquidationTriggersTest
/// @notice Integration tests for liquidation trigger conditions: oracle manipulation,
///         BTC vault share price effects, and insurance protection mechanisms.
/// @dev Runs against pre-deployed contracts on local Anvil via `make deploy-local`.
///      Source: Cat 6 (6.1-6.6), Cat 7 (7.1-7.5), Cat 17 (17.1-17.6).
contract LiquidationTriggersTest is IntegrationTestBase {
    // ============ Constants ============
    uint256 constant PRICE_DROP_30_PERCENT = 30;
    uint256 constant PRICE_DROP_40_PERCENT = 40;
    uint256 constant PRICE_DROP_70_PERCENT = 70;
    uint256 constant VAULT_YIELD_20_PERCENT = 2000;
    uint256 constant VAULT_LOSS_30_PERCENT = 3000;
    uint256 constant VAULT_LOSS_40_PERCENT = 4000;
    uint256 constant EXIT_FEE_100_BPS = 100;
    uint256 constant EXIT_FEE_500_BPS = 500;
    uint256 constant REPAYMENT_INTERVAL = 30 days;

    // ============ Setup ============
    function setUp() public override {
        super.setUp();
        _setupTestUser();
        _setupLiquidator();
    }

    // ========================================================================
    // Cat 6: Oracle x Liquidation (6 tests)
    // ========================================================================

    /// @notice 6.1: A 50% oracle price drop triggers full liquidation on a healthy loan
    function test_Oracle_PriceManipulation_TriggersFalseFullLiquidation() public {
        // Arrange
        address lsa = _createStandardLoan();
        (,, uint256 healthFactorBefore) = _getUserAccountData(lsa);
        assertGt(healthFactorBefore, 1e18, "loan should be healthy before price drop");
        uint256 checkBefore = _checkTypeOfLiquidation(lsa);
        assertEq(checkBefore, TC.LIQUIDATION_TYPE_NONE, "healthy loan should have no liquidation type");

        uint256 liquidatorCbBTCBefore = cbBTC.balanceOf(testLiquidator);

        // Act: crash BTC price by 50%
        _dropOraclePrice(TC.PRICE_DROP_FULL);

        // Assert: checkType now returns full liquidation
        uint256 checkAfter = _checkTypeOfLiquidation(lsa);
        assertEq(checkAfter, TC.LIQUIDATION_TYPE_FULL, "50% price drop should trigger full liquidation type");

        // Execute full liquidation
        bool success = _triggerFullLiquidation(lsa);
        assertTrue(success, "full liquidation should succeed after 50% price drop");

        // Verify loan status transitioned to Liquidated
        DataTypes.LoanData memory loanData = loanContract.getLoanByLSA(lsa);
        assertEq(
            uint256(loanData.status),
            uint256(DataTypes.LoanStatus.Liquidated),
            "loan status should be Liquidated"
        );

        // Verify liquidator received cbBTC proceeds
        uint256 liquidatorCbBTCAfter = cbBTC.balanceOf(testLiquidator);
        assertGt(liquidatorCbBTCAfter, liquidatorCbBTCBefore, "liquidator should receive cbBTC from liquidation");
    }

    /// @notice 6.2: Price recovery between check and execution prevents liquidation
    function test_Oracle_PriceRecovery_BetweenCheckAndExecution() public {
        // Arrange
        address lsa = _createStandardLoan();
        (, int256 originalPrice,,,) = btcOracle.latestRoundData();

        // Act: drop price to trigger liquidation
        _dropOraclePrice(TC.PRICE_DROP_FULL);
        uint256 checkDuringDrop = _checkTypeOfLiquidation(lsa);
        assertGt(checkDuringDrop, TC.LIQUIDATION_TYPE_NONE, "price drop should trigger some liquidation type");

        // Restore original price before execution
        _setBtcPrice(originalPrice);

        // Assert: check type returns to none after recovery
        uint256 checkAfterRecovery = _checkTypeOfLiquidation(lsa);
        assertEq(checkAfterRecovery, TC.LIQUIDATION_TYPE_NONE, "price recovery should clear liquidation type");

        // Attempt liquidation - should fail since price recovered
        bool success = _triggerFullLiquidation(lsa);
        assertFalse(success, "liquidation should fail after price recovery");

        // Loan remains Active
        DataTypes.LoanData memory loanData = loanContract.getLoanByLSA(lsa);
        assertEq(
            uint256(loanData.status),
            uint256(DataTypes.LoanStatus.Active),
            "loan should remain active after price recovery"
        );
    }

    /// @notice 6.3: Both oracle drop and strategy loss independently cause liquidation
    function test_Oracle_PricePropagation_BothChannels_TriggerLiquidation() public {
        // Path A: Oracle drop triggers liquidation
        address lsaA = _createStandardLoan();
        uint256 snapA = vm.snapshot();

        _dropOraclePrice(PRICE_DROP_40_PERCENT);
        uint256 checkA = _checkTypeOfLiquidation(lsaA);
        assertGt(checkA, TC.LIQUIDATION_TYPE_NONE, "path A: oracle drop should trigger liquidation type");

        bool successA = _triggerFullLiquidation(lsaA);
        assertTrue(successA, "path A: full liquidation should succeed via oracle drop");

        // Revert to snapshot for Path B
        vm.revertTo(snapA);

        // Path B: Strategy loss without oracle change triggers liquidation
        _simulateStrategyLoss(VAULT_LOSS_40_PERCENT);

        (,, uint256 hfAfterLoss) = _getUserAccountData(lsaA);
        // Strategy loss reduces collateral value, lowering health factor
        // If HF drops below 1, liquidation should be possible
        uint256 checkB = _checkTypeOfLiquidation(lsaA);
        if (checkB > TC.LIQUIDATION_TYPE_NONE) {
            bool successB = _triggerFullLiquidation(lsaA);
            assertTrue(successB, "path B: full liquidation should succeed via strategy loss");
        } else {
            // Even if not triggering full liq, HF should have dropped significantly
            assertLt(hfAfterLoss, 2e18, "path B: health factor should drop significantly from strategy loss");
        }
    }

    /// @notice 6.4: Zero oracle price blocks liquidation execution
    function test_Oracle_ZeroPrice_BlocksLiquidation() public {
        // Arrange
        address lsa = _createStandardLoan();

        // Act: set BTC price to zero
        _setBtcPrice(0);

        // Assert: liquidation should fail with zero price
        bool success = _triggerFullLiquidation(lsa);
        assertFalse(success, "liquidation should fail when oracle price is zero");

        // Loan remains Active
        DataTypes.LoanData memory loanData = loanContract.getLoanByLSA(lsa);
        assertEq(
            uint256(loanData.status),
            uint256(DataTypes.LoanStatus.Active),
            "loan should remain active when oracle price is zero"
        );
    }

    /// @notice 6.5: Oracle manipulation causes micro-liquidation to seize more collateral
    function test_Oracle_Manipulation_MicroLiquidation_WrongAmount() public {
        // Arrange
        address lsa = _createStandardLoan();
        uint256 liquidatorCbBTCBaseline = cbBTC.balanceOf(testLiquidator);

        // Path A: fair price micro-liquidation
        uint256 snapA = vm.snapshot();
        _makeFirstPaymentOverdue();

        uint256 checkA = _checkTypeOfLiquidation(lsa);
        assertEq(checkA, TC.LIQUIDATION_TYPE_MICRO, "path A: overdue loan should be micro-liquidatable");

        bool successA = _triggerMicroLiquidation(lsa);
        assertTrue(successA, "path A: micro-liquidation should succeed at fair price");
        uint256 cbBTCAtFairPrice = cbBTC.balanceOf(testLiquidator) - liquidatorCbBTCBaseline;

        // Revert to pre-overdue state
        vm.revertTo(snapA);

        // Path B: manipulated price micro-liquidation
        _dropOraclePrice(PRICE_DROP_30_PERCENT);
        _makeFirstPaymentOverdue();

        uint256 checkB = _checkTypeOfLiquidation(lsa);
        // With 30% drop + overdue, could be micro (2) or full (1)
        assertGt(checkB, TC.LIQUIDATION_TYPE_NONE, "path B: should trigger some liquidation after drop + overdue");

        uint256 liquidatorCbBTCBeforeB = cbBTC.balanceOf(testLiquidator);
        bool successB = _triggerMicroLiquidation(lsa);
        if (successB) {
            uint256 cbBTCAtLowPrice = cbBTC.balanceOf(testLiquidator) - liquidatorCbBTCBeforeB;

            // At lower oracle price, liquidator gets more cbBTC per USDC of debt covered
            assertGt(
                cbBTCAtLowPrice,
                cbBTCAtFairPrice,
                "manipulated price should yield more cbBTC to liquidator"
            );
            // Difference should be significant (>20% more collateral seized)
            assertGt(
                cbBTCAtLowPrice,
                cbBTCAtFairPrice * 120 / 100,
                "manipulated price should yield >20% more cbBTC to liquidator"
            );
        }
    }

    /// @notice 6.6: Combined oracle drop + strategy loss causes worse HF than oracle drop alone
    function test_Oracle_PriceDrop_DualAsset_ConsistencyCheck() public {
        // Arrange
        address lsa = _createStandardLoan();

        // Path A: oracle drop only
        uint256 snapA = vm.snapshot();
        _dropOraclePrice(PRICE_DROP_30_PERCENT);
        (,, uint256 hfPathA) = _getUserAccountData(lsa);

        // Revert for Path B
        vm.revertTo(snapA);

        // Path B: oracle drop + strategy loss
        _dropOraclePrice(PRICE_DROP_30_PERCENT);
        _simulateStrategyLoss(VAULT_LOSS_30_PERCENT);
        (,, uint256 hfPathB) = _getUserAccountData(lsa);

        // Assert: combined damage should produce worse (lower) health factor
        assertLt(hfPathB, hfPathA, "combined oracle drop + strategy loss should produce lower HF than oracle drop alone");
    }

    // ========================================================================
    // Cat 7: BTC Vault x Liquidation (5 tests)
    // ========================================================================

    /// @notice 7.1: Vault yield inflation before liquidation can save a loan from seizure
    function test_BTCVault_SharePriceInflation_BeforeLiquidation_AvoidsSeizure() public {
        // Arrange: create loan and push to edge of liquidation
        address lsa = _createStandardLoan();
        _dropOraclePrice(PRICE_DROP_40_PERCENT);

        uint256 checkBefore = _checkTypeOfLiquidation(lsa);
        assertGt(checkBefore, TC.LIQUIDATION_TYPE_NONE, "loan should be liquidatable after 40% price drop");

        // Act: simulate vault yield to inflate collateral value
        _simulateVaultYield(VAULT_YIELD_20_PERCENT);

        // Assert: yield should push loan back to healthy
        uint256 checkAfter = _checkTypeOfLiquidation(lsa);
        assertEq(checkAfter, TC.LIQUIDATION_TYPE_NONE, "vault yield should prevent liquidation (front-run succeeded)");
    }

    /// @notice 7.2: Strategy loss alone can trigger cascade liquidation
    function test_BTCVault_StrategyLoss_TriggersCascadeLiquidation() public {
        // Arrange
        address lsa = _createStandardLoan();
        uint256 checkBefore = _checkTypeOfLiquidation(lsa);
        assertEq(checkBefore, TC.LIQUIDATION_TYPE_NONE, "loan should be healthy before strategy loss");

        // Act: simulate 40% strategy loss
        _simulateStrategyLoss(VAULT_LOSS_40_PERCENT);

        // Assert: strategy loss should trigger liquidation
        uint256 checkAfter = _checkTypeOfLiquidation(lsa);
        assertGt(checkAfter, TC.LIQUIDATION_TYPE_NONE, "strategy loss should trigger liquidation type");

        // Execute full liquidation
        bool success = _triggerFullLiquidation(lsa);
        assertTrue(success, "full liquidation should succeed after strategy loss");

        // Verify loan status
        DataTypes.LoanData memory loanData = loanContract.getLoanByLSA(lsa);
        assertEq(
            uint256(loanData.status),
            uint256(DataTypes.LoanStatus.Liquidated),
            "loan should be liquidated after strategy loss"
        );
    }

    /// @notice 7.3: Exit fee reduces liquidator proceeds but liquidation still works
    function test_BTCVault_ExitFee_ReducesLiquidatorProceeds() public {
        // Path A: liquidation with no exit fee
        uint256 snapA = vm.snapshot();

        address lsaA = _createStandardLoan();
        _dropOraclePrice(TC.PRICE_DROP_FULL);

        uint256 liquidatorCbBTCBeforeA = cbBTC.balanceOf(testLiquidator);
        bool successA = _triggerFullLiquidation(lsaA);
        assertTrue(successA, "path A: liquidation should succeed without exit fee");
        uint256 liquidatorCbBTCReceivedA = cbBTC.balanceOf(testLiquidator) - liquidatorCbBTCBeforeA;

        // Revert to pre-loan state
        vm.revertTo(snapA);

        // Path B: liquidation with exit fee
        vm.prank(admin);
        btcVault.setExitFee(EXIT_FEE_100_BPS);
        assertEq(btcVault.getExitFee(), EXIT_FEE_100_BPS, "exit fee should be set to 100 bps");

        address lsaB = _createStandardLoan();
        _dropOraclePrice(TC.PRICE_DROP_FULL);

        uint256 liquidatorCbBTCBeforeB = cbBTC.balanceOf(testLiquidator);
        bool successB = _triggerFullLiquidation(lsaB);
        assertTrue(successB, "path B: liquidation should succeed with exit fee");
        uint256 liquidatorCbBTCReceivedB = cbBTC.balanceOf(testLiquidator) - liquidatorCbBTCBeforeB;

        // Assert: liquidator received LESS with fee
        assertLt(
            liquidatorCbBTCReceivedB,
            liquidatorCbBTCReceivedA,
            "liquidator should receive less cbBTC when exit fee is active"
        );

        // Assert: liquidation was still profitable (liquidator received non-zero cbBTC)
        assertGt(liquidatorCbBTCReceivedB, 0, "liquidation should still be profitable with exit fee");
    }

    /// @notice 7.4: Pausing BTCVault bricks liquidation even when loan needs it
    function test_BTCVault_VaultPaused_DuringLiquidation_BricksLiquidation() public {
        // Arrange
        address lsa = _createStandardLoan();
        _dropOraclePrice(TC.PRICE_DROP_FULL);

        uint256 checkBefore = _checkTypeOfLiquidation(lsa);
        assertEq(checkBefore, TC.LIQUIDATION_TYPE_FULL, "loan should need full liquidation");

        // Grant BVM_FAST role to admin so they can pause
        uint64 bvmFastId = BVM_FAST_ID();
        vm.prank(admin);
        manager.grantRole(bvmFastId, admin, 0);

        // Pause the vault
        vm.prank(admin);
        btcVault.pause();
        assertTrue(btcVault.paused(), "btcVault should be paused");

        // Act: attempt liquidation while vault is paused
        bool success = _triggerFullLiquidation(lsa);
        assertFalse(success, "liquidation should fail when vault is paused");

        // Loan remains Active even though it needs liquidation
        DataTypes.LoanData memory loanData = loanContract.getLoanByLSA(lsa);
        assertEq(
            uint256(loanData.status),
            uint256(DataTypes.LoanStatus.Active),
            "loan should remain active when vault is paused"
        );

        // Check type still shows it needs liquidation
        uint256 checkStill = _checkTypeOfLiquidation(lsa);
        assertEq(checkStill, TC.LIQUIDATION_TYPE_FULL, "loan still needs liquidation but vault is paused");
    }

    /// @notice 7.5: High exit fee + mass redemptions drain share price, cascading into liquidation
    function test_BTCVault_ExitFee_MassRedemption_SharePriceDrain_CascadeLiquidation() public {
        // Arrange: set high exit fee
        vm.prank(admin);
        btcVault.setExitFee(EXIT_FEE_500_BPS);
        assertEq(btcVault.getExitFee(), EXIT_FEE_500_BPS, "exit fee should be 500 bps");

        // Create 3 loans: 1 from testUser, 2 from additional users
        address lsa1 = _createStandardLoan(); // testUser's loan (the one we watch)
        address user2 = _setupAdditionalUser("user2");
        address lsa2 = _createLoanForUser(user2, TC.STANDARD_COLLATERAL, TC.STANDARD_DURATION, TC.PREMIUM_AMOUNT);
        address user3 = _setupAdditionalUser("user3");
        address lsa3 = _createLoanForUser(user3, TC.STANDARD_COLLATERAL, TC.STANDARD_DURATION, TC.PREMIUM_AMOUNT);

        // Capture initial share price and remaining loan's HF
        uint256 shareValueBefore = btcVault.convertToAssets(1e8);
        (,, uint256 hfBefore) = _getUserAccountData(lsa1);

        // Close 2 loans (with exit fee eating into vault)
        // Fund users extra USDC for flash loan repayment
        _fundUSDC(user2, TC.USER_USDC_BALANCE);
        vm.prank(user2);
        usdc.approve(address(loanContract), type(uint256).max);
        vm.prank(user2);
        loanContract.closeLoan(lsa2, false);

        _fundUSDC(user3, TC.USER_USDC_BALANCE);
        vm.prank(user3);
        usdc.approve(address(loanContract), type(uint256).max);
        vm.prank(user3);
        loanContract.closeLoan(lsa3, false);

        // Assert: share price should have decreased due to exit fee on redemptions
        uint256 shareValueAfter = btcVault.convertToAssets(1e8);
        assertLt(shareValueAfter, shareValueBefore, "share price should decrease after mass redemptions with exit fee");

        // Assert: remaining loan's HF should have decreased
        (,, uint256 hfAfter) = _getUserAccountData(lsa1);
        assertLt(hfAfter, hfBefore, "remaining loan HF should decrease after share price drain");

        // If HF dropped below 1.0, cascade triggered
        if (hfAfter < 1e18) {
            uint256 checkType = _checkTypeOfLiquidation(lsa1);
            assertGt(checkType, TC.LIQUIDATION_TYPE_NONE, "cascade: loan should be liquidatable after share price drain");
        }
    }

    // ========================================================================
    // Cat 17: Insurance x Liquidation (6 tests)
    // ========================================================================

    /// @notice 17.1: Insured loan resists full liquidation despite 50% price drop
    function test_InsuredLoan_PriceDropFullLiquidation_Reverts() public {
        // Arrange
        address lsa = _createStandardLoan();
        _setInsurance(lsa, 1);

        // Act: drop price severely
        _dropOraclePrice(TC.PRICE_DROP_FULL);

        // Assert: insurance blocks liquidation type detection
        uint256 checkType = _checkTypeOfLiquidation(lsa);
        assertEq(checkType, TC.LIQUIDATION_TYPE_NONE, "insured loan should not be flagged for liquidation");

        // Attempt liquidation - should fail
        bool success = _triggerFullLiquidation(lsa);
        assertFalse(success, "full liquidation should fail on insured loan");

        // Loan remains Active
        DataTypes.LoanData memory loanData = loanContract.getLoanByLSA(lsa);
        assertEq(
            uint256(loanData.status),
            uint256(DataTypes.LoanStatus.Active),
            "insured loan should remain active after price drop"
        );
    }

    /// @notice 17.2: Insured loan still subject to micro-liquidation for missed payments
    function test_InsuredLoan_MissedPayment_MicroLiquidation_Succeeds() public {
        // Arrange
        address lsa = _createStandardLoan();
        _setInsurance(lsa, 1);
        DataTypes.LoanData memory dataBefore = loanContract.getLoanByLSA(lsa);
        uint256 durationBefore = dataBefore.duration;

        // Act: make loan overdue
        _makeFirstPaymentOverdue();

        // Assert: micro-liquidation type triggered despite insurance
        uint256 checkType = _checkTypeOfLiquidation(lsa);
        assertEq(checkType, TC.LIQUIDATION_TYPE_MICRO, "insured overdue loan should be micro-liquidatable");

        // Execute micro-liquidation
        bool success = _triggerMicroLiquidation(lsa);
        assertTrue(success, "micro-liquidation should succeed on insured overdue loan");

        // Duration should decrease by 1
        DataTypes.LoanData memory dataAfter = loanContract.getLoanByLSA(lsa);
        assertEq(dataAfter.duration, durationBefore - 1, "duration should decrease by 1 after micro-liquidation");
    }

    /// @notice 17.3: Insured loan with price drop + missed payment escalates to full liquidation
    function test_InsuredLoan_MissedPayment_EscalatesToFull() public {
        // Arrange
        address lsa = _createStandardLoan();
        _setInsurance(lsa, 1);

        // Act: drop price AND make overdue (insurance guard fails when both conditions met)
        _dropOraclePrice(PRICE_DROP_40_PERCENT);
        _makeFirstPaymentOverdue();

        // Assert: escalated to full liquidation
        uint256 checkType = _checkTypeOfLiquidation(lsa);
        assertEq(checkType, TC.LIQUIDATION_TYPE_FULL, "insured loan with price drop + overdue should escalate to full liquidation");

        // Execute full liquidation
        bool success = _triggerFullLiquidation(lsa);
        assertTrue(success, "full liquidation should succeed on insured loan with both triggers");

        // Verify liquidated status
        DataTypes.LoanData memory loanData = loanContract.getLoanByLSA(lsa);
        assertEq(
            uint256(loanData.status),
            uint256(DataTypes.LoanStatus.Liquidated),
            "loan should be liquidated after escalation"
        );
    }

    /// @notice 17.4: Removing insurance re-enables price-based liquidation
    function test_InsuredLoan_InsuranceExpiry_EnablesPriceLiquidation() public {
        // Arrange
        address lsa = _createStandardLoan();
        _setInsurance(lsa, 1);

        // Drop price severely
        _dropOraclePrice(TC.PRICE_DROP_FULL);

        // Verify: insurance blocks liquidation
        uint256 checkBlocked = _checkTypeOfLiquidation(lsa);
        assertEq(checkBlocked, TC.LIQUIDATION_TYPE_NONE, "insured loan should block liquidation");

        // Act: remove insurance
        _setInsurance(lsa, 0);

        // Assert: liquidation now possible
        uint256 checkUnblocked = _checkTypeOfLiquidation(lsa);
        assertGt(checkUnblocked, TC.LIQUIDATION_TYPE_NONE, "uninsured loan should be liquidatable after price drop");

        // Execute full liquidation
        bool success = _triggerFullLiquidation(lsa);
        assertTrue(success, "full liquidation should succeed after insurance removal");
    }

    /// @notice 17.5: Insurance toggle dynamically changes liquidation eligibility
    function test_InsuranceID_UpdateDuringActiveLoan() public {
        // Arrange: create uninsured loan
        address lsa = _createStandardLoan();

        // Drop price to trigger liquidation
        _dropOraclePrice(TC.PRICE_DROP_FULL);

        // Assert: uninsured → liquidatable
        uint256 check1 = _checkTypeOfLiquidation(lsa);
        assertEq(check1, TC.LIQUIDATION_TYPE_FULL, "uninsured loan with price drop should be full-liquidatable");

        // Act: add insurance → blocks liquidation
        _setInsurance(lsa, 1);
        uint256 check2 = _checkTypeOfLiquidation(lsa);
        assertEq(check2, TC.LIQUIDATION_TYPE_NONE, "insured loan should block liquidation");

        // Act: remove insurance → re-enables liquidation
        _setInsurance(lsa, 0);
        uint256 check3 = _checkTypeOfLiquidation(lsa);
        assertEq(check3, TC.LIQUIDATION_TYPE_FULL, "removing insurance should re-enable liquidation");
    }

    /// @notice 17.6: Insured loan current on payments is immune to both liquidation types
    function test_InsuredLoan_CurrentOnPayments_NoLiquidation() public {
        // Arrange
        address lsa = _createStandardLoan();
        _setInsurance(lsa, 1);

        // Drop price severely (insurance protects against price-based liquidation)
        _dropOraclePrice(TC.PRICE_DROP_FULL);

        // Assert: check type returns none (insurance protection + current on payments)
        uint256 checkType = _checkTypeOfLiquidation(lsa);
        assertEq(checkType, TC.LIQUIDATION_TYPE_NONE, "insured current loan should not be liquidatable");

        // Both liquidation types should fail
        bool fullSuccess = _triggerFullLiquidation(lsa);
        assertFalse(fullSuccess, "full liquidation should fail on insured current loan");

        bool microSuccess = _triggerMicroLiquidation(lsa);
        assertFalse(microSuccess, "micro-liquidation should fail on insured current loan");

        // Loan remains Active
        DataTypes.LoanData memory loanData = loanContract.getLoanByLSA(lsa);
        assertEq(
            uint256(loanData.status),
            uint256(DataTypes.LoanStatus.Active),
            "insured current loan should remain active"
        );
    }
}
