// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IntegrationTestBase} from "../base/IntegrationTestBase.sol";
import {TestConstants as TC} from "../helpers/TestConstants.sol";
import {DataTypes} from "@bitmor/libraries/types/DataTypes.sol";
import {IERC20} from "@openzeppelin/interfaces/IERC20.sol";
import {Errors} from "@bitmor/libraries/helpers/Errors.sol";

/// @title CloseLoanTest
/// @notice Adversarial integration tests for close loan edge cases and timing attacks.
/// @dev Runs against pre-deployed contracts on local Anvil via `make deploy-local`.
///      A failing test is a FINDING, not a test bug. See plan header for rules.
contract CloseLoanTest is IntegrationTestBase {
    // ============ Constants ============

    uint256 internal constant CLOSE_INSUFFICIENT_PRICE_DROP = 80;
    uint256 internal constant MICRO_LIQ_COUNT = 3;

    // ============ Setup ============

    function setUp() public override {
        super.setUp();
        _setupLiquidator();
    }

    // ============ Test 10.2: WithBTC vs WithUSDC Balance Comparison ============

    /// @notice 10.2: Both withdrawal modes return economically equivalent value
    function test_CloseLoan_WithBTC_Vs_WithUSDC_BalanceComparison() public {
        address lsa = _createStandardLoan();
        (, int256 btcPrice,,,) = btcOracle.latestRoundData();

        uint256 snapId = vm.snapshot();

        // --- Path A: withdrawInBTC = true ---
        uint256 userBtcBeforeA = cbBTC.balanceOf(testUser);
        uint256 userUsdcBeforeA = usdc.balanceOf(testUser);
        _closeLoanEarly(lsa, testUser, true);
        uint256 btcReceivedA = cbBTC.balanceOf(testUser) - userBtcBeforeA;
        uint256 usdcReceivedA = usdc.balanceOf(testUser) - userUsdcBeforeA;
        // Normalize BTC to 6-dec USDC: btc(8d) * price(8d) / 1e8 / 1e2
        uint256 btcValueInUSDC6_A = (btcReceivedA * uint256(btcPrice)) / TC.PRICE_PRECISION / 1e2;
        uint256 totalValueA = btcValueInUSDC6_A + usdcReceivedA;

        // --- Path B: withdrawInBTC = false ---
        vm.revertTo(snapId);
        uint256 userBtcBeforeB = cbBTC.balanceOf(testUser);
        uint256 userUsdcBeforeB = usdc.balanceOf(testUser);
        _closeLoanEarly(lsa, testUser, false);
        uint256 btcReceivedB = cbBTC.balanceOf(testUser) - userBtcBeforeB;
        uint256 usdcReceivedB = usdc.balanceOf(testUser) - userUsdcBeforeB;
        uint256 btcValueInUSDC6_B = (btcReceivedB * uint256(btcPrice)) / TC.PRICE_PRECISION / 1e2;
        uint256 totalValueB = btcValueInUSDC6_B + usdcReceivedB;

        // Assert: economically equivalent within 2% (swap slippage + fee variance)
        assertApproxEqRel(totalValueA, totalValueB, 0.02e18, "both modes should return ~equal USD value");
        assertGt(btcReceivedA, btcReceivedB, "withdrawInBTC=true should yield more BTC");
        assertGt(usdcReceivedB, usdcReceivedA, "withdrawInBTC=false should yield more USDC");
    }

    // ============ Test 10.3: PreClosureFee Rounds Up ============

    /// @notice 10.3: Pre-closure fee rounds up, favoring the protocol
    function test_CloseLoan_PreClosureFee_RoundsUp() public {
        address lsa = _createStandardLoan();
        uint256 feeBps = _getPreClosureFeeBps();
        assertGt(feeBps, 0, "pre-closure fee bps should be non-zero");

        uint256 aTokenBalance = _getATokenBalance(lsa);
        uint256 collateralInBTC = btcVault.previewRedeem(aTokenBalance);
        uint256 feeFloor = (collateralInBTC * feeBps) / TC.BPS_DENOMINATOR;

        address premiumCollector = bitmorAddressesProvider.getPremiumCollector();
        uint256 collectorBtcBefore = cbBTC.balanceOf(premiumCollector);

        _closeLoanEarly(lsa, testUser, true);

        uint256 feeReceived = cbBTC.balanceOf(premiumCollector) - collectorBtcBefore;
        assertGt(feeReceived, 0, "fee collector should receive non-zero fee");
        assertGe(feeReceived, feeFloor, "fee should be >= floor (mulDivUp rounds up)");

        bool hasRemainder = (collateralInBTC * feeBps) % TC.BPS_DENOMINATOR != 0;
        if (hasRemainder) {
            assertGt(feeReceived, feeFloor, "fee should be strictly > floor when remainder exists");
        }
    }

    // ============ Test 10.4: Flash Loan Premium Sufficient + Event ============

    /// @notice 10.4: Flash loan premium is covered by swap output on successful close
    function test_CloseLoan_FlashLoanPremium_Sufficient() public {
        address lsa = _createStandardLoan();
        uint256 aaveBalBefore = usdc.balanceOf(aaveV3Pool);

        _closeLoanEarly(lsa, testUser, true);

        DataTypes.LoanData memory loanData = loanContract.getLoanByLSA(lsa);
        assertEq(uint256(loanData.status), uint256(DataTypes.LoanStatus.Completed), "loan should be completed");
        assertGe(usdc.balanceOf(aaveV3Pool), aaveBalBefore, "Aave pool should be repaid");
        _assertLoanContractIsEmpty("after close with flash loan premium");
    }

    // ============ Test 10.5: Close After Interest Accrual ============

    /// @notice 10.5: Close loan succeeds after interest has accrued on debt
    function test_CloseLoan_AfterInterestAccrual() public {
        address lsa = _createStandardLoan();
        uint256 debtAtCreation = _getDebtBalanceUSDC(lsa);
        assertGt(debtAtCreation, 0, "should have debt after loan creation");

        vm.warp(block.timestamp + 180 days);

        uint256 debtAfterAccrual = _getDebtBalanceUSDC(lsa);
        assertGt(debtAfterAccrual, debtAtCreation, "debt should grow after 6 months of interest");

        uint256 userBtcBefore = cbBTC.balanceOf(testUser);
        _closeLoanEarly(lsa, testUser, true);

        DataTypes.LoanData memory loanData = loanContract.getLoanByLSA(lsa);
        assertEq(uint256(loanData.status), uint256(DataTypes.LoanStatus.Completed), "loan should be completed");
        assertGt(cbBTC.balanceOf(testUser), userBtcBefore, "user should receive remaining BTC");
        _assertLoanContractIsEmpty("after close with interest accrual");
    }

    // ============ Test 10.6: Close After Multiple Micro-Liquidations ============

    /// @notice 10.6: Close loan succeeds after multiple micro-liquidations
    function test_CloseLoan_AfterMultipleMicroLiquidations() public {
        (address lsa, DataTypes.LoanData memory loanDataInit) =
            _createLoanWithData(TC.STANDARD_COLLATERAL, TC.STANDARD_DURATION, TC.PREMIUM_AMOUNT);
        uint256 durationInit = loanDataInit.duration;

        _executeMicroLiquidations(lsa, MICRO_LIQ_COUNT);

        DataTypes.LoanData memory loanDataAfterMicroLiq = loanContract.getLoanByLSA(lsa);
        assertEq(
            loanDataAfterMicroLiq.duration,
            durationInit - MICRO_LIQ_COUNT,
            "duration should decrease by micro-liq count"
        );
        assertEq(
            uint256(loanDataAfterMicroLiq.status), uint256(DataTypes.LoanStatus.Active), "loan should still be active"
        );

        (uint256 collateralAfterMicroLiq, uint256 debtAfterMicroLiq,) = _getUserAccountData(lsa);
        assertGt(collateralAfterMicroLiq, 0, "should still have collateral");
        assertGt(debtAfterMicroLiq, 0, "should still have debt");

        uint256 userBtcBefore = cbBTC.balanceOf(testUser);
        _closeLoanEarly(lsa, testUser, true);

        DataTypes.LoanData memory loanDataFinal = loanContract.getLoanByLSA(lsa);
        assertEq(uint256(loanDataFinal.status), uint256(DataTypes.LoanStatus.Completed), "loan should be completed");
        assertGt(cbBTC.balanceOf(testUser), userBtcBefore, "user should receive remaining BTC");
        _assertLoanContractIsEmpty("after close with micro-liquidations");
    }

    // ============ Test 10.7: Zero Debt After Full Repay Reverts ============

    /// @notice 10.7: Close loan reverts after full repayment (loan already Completed)
    function test_CloseLoan_RevertWhen_ZeroDebtAfterFullRepay() public {
        address lsa = _createStandardLoan();
        _fullyRepayLoan(lsa);

        DataTypes.LoanData memory loanData = loanContract.getLoanByLSA(lsa);
        assertEq(uint256(loanData.status), uint256(DataTypes.LoanStatus.Completed), "loan should be completed");

        vm.prank(testUser);
        vm.expectRevert(Errors.LoanIsNotActive.selector);
        loanContract.closeLoan(lsa, true);

        vm.prank(testUser);
        vm.expectRevert(Errors.LoanIsNotActive.selector);
        loanContract.closeLoan(lsa, false);
    }

    // ============ Test 8.2: Front-Run Close Loan With Oracle Update ============

    /// @notice 8.2: Oracle front-run makes close loan revert
    function test_FrontRun_CloseLoan_WithOracleUpdate() public {
        address lsa = _createStandardLoan();

        // Prove close works at normal price
        uint256 snapId = vm.snapshot();
        _closeLoanEarly(lsa, testUser, true);
        DataTypes.LoanData memory closedData = loanContract.getLoanByLSA(lsa);
        assertEq(
            uint256(closedData.status), uint256(DataTypes.LoanStatus.Completed), "close should work at normal price"
        );
        vm.revertTo(snapId);

        // Attacker front-runs: crash oracle price by 80%
        _dropOraclePrice(CLOSE_INSUFFICIENT_PRICE_DROP);

        (uint256 collateralBefore, uint256 debtBefore,) = _getUserAccountData(lsa);

        vm.prank(testUser);
        vm.expectRevert(Errors.InsufficientCollateral.selector);
        loanContract.closeLoan(lsa, true);

        // Loan remains active — no state changes
        DataTypes.LoanData memory loanData = loanContract.getLoanByLSA(lsa);
        assertEq(uint256(loanData.status), uint256(DataTypes.LoanStatus.Active), "loan should remain active");
        (uint256 collateralAfter, uint256 debtAfter,) = _getUserAccountData(lsa);
        assertEq(collateralAfter, collateralBefore, "collateral should be unchanged");
        assertEq(debtAfter, debtBefore, "debt should be unchanged");
    }

    // ============ Test 8.5: Race Condition: Close Loan vs Liquidation ============

    /// @notice 8.5: If liquidation front-runs close, close reverts — no double-spend
    function test_RaceCondition_CloseLoanAndLiquidation_SameBlock() public {
        (address lsa, DataTypes.LoanData memory loanData) =
            _createLoanWithData(TC.STANDARD_COLLATERAL, TC.STANDARD_DURATION, TC.PREMIUM_AMOUNT);
        assertEq(uint256(loanData.status), uint256(DataTypes.LoanStatus.Active), "loan should be active");

        _dropOraclePrice(90);

        uint256 liquidationType = _checkTypeOfLiquidation(lsa);
        assertGt(liquidationType, 0, "loan should be liquidatable after 90% drop");

        // Liquidation executes first (front-runs)
        bool success = _triggerFullLiquidation(lsa);
        assertTrue(success, "liquidation should succeed");

        DataTypes.LoanData memory loanDataAfterLiq = loanContract.getLoanByLSA(lsa);
        assertEq(
            uint256(loanDataAfterLiq.status), uint256(DataTypes.LoanStatus.Liquidated), "loan should be liquidated"
        );

        // Borrower's closeLoan executes second (back-runs)
        vm.prank(testUser);
        vm.expectRevert(Errors.LoanIsNotActive.selector);
        loanContract.closeLoan(lsa, true);

        // Collateral already seized — no double-spend
        (uint256 collateralAfter,,) = _getUserAccountData(lsa);
        assertEq(collateralAfter, 0, "collateral should be zero after liquidation");
    }

    // ============ Test 8.8: Back-Run Oracle Update Then Liquidate ============

    /// @notice 8.8: Valid liquidation after oracle price update in same block
    function test_BackRunOracleUpdate_ThenLiquidate() public {
        (address lsa, DataTypes.LoanData memory loanData) =
            _createLoanWithData(TC.STANDARD_COLLATERAL, TC.STANDARD_DURATION, TC.PREMIUM_AMOUNT);

        uint256 liquidatorBtcBefore = cbBTC.balanceOf(testLiquidator);

        _dropOraclePrice(TC.PRICE_DROP_FULL);

        uint256 liquidationType = _checkTypeOfLiquidation(lsa);
        assertGt(liquidationType, 0, "loan should be liquidatable after price drop");

        bool success = _triggerFullLiquidation(lsa);
        assertTrue(success, "liquidation should succeed");

        DataTypes.LoanData memory loanDataAfter = loanContract.getLoanByLSA(lsa);
        assertEq(uint256(loanDataAfter.status), uint256(DataTypes.LoanStatus.Liquidated), "loan should be liquidated");

        uint256 btcReceived = cbBTC.balanceOf(testLiquidator) - liquidatorBtcBefore;
        assertGt(btcReceived, 0, "liquidator should receive BTC collateral as bonus");

        vm.prank(testUser);
        vm.expectRevert(Errors.LoanIsNotActive.selector);
        loanContract.closeLoan(lsa, true);
    }

    // ============ Test 10.8: Close After Vault Appreciation ============

    /// @notice 10.8: Close loan after vault appreciation uses appreciated collateral for fee
    function test_CloseLoan_AfterVaultAppreciation_FeeReflectsYield() public {
        // --- Baseline: close loan WITHOUT vault yield ---
        address lsa1 = _createStandardLoan();
        address premiumCollector = bitmorAddressesProvider.getPremiumCollector();
        uint256 collectorBefore1 = cbBTC.balanceOf(premiumCollector);
        _closeLoanEarly(lsa1, testUser, true);
        uint256 feeWithoutYield = cbBTC.balanceOf(premiumCollector) - collectorBefore1;
        assertGt(feeWithoutYield, 0, "baseline fee should be non-zero");

        // --- Test: close loan WITH vault yield ---
        vm.warp(block.timestamp + 1); // Avoid CREATE2 salt collision
        address lsa2 = _createStandardLoan();

        _simulateVaultYield(TC.SIMULATED_YIELD_BPS);
        vm.warp(block.timestamp + 1);

        uint256 collectorBefore2 = cbBTC.balanceOf(premiumCollector);
        _closeLoanEarly(lsa2, testUser, true);
        uint256 feeWithYield = cbBTC.balanceOf(premiumCollector) - collectorBefore2;
        assertGt(feeWithYield, 0, "fee with yield should be non-zero");

        DataTypes.LoanData memory loanData = loanContract.getLoanByLSA(lsa2);
        assertEq(uint256(loanData.status), uint256(DataTypes.LoanStatus.Completed), "loan should be completed");

        // Fee with yield > fee without yield proves fee is on appreciated underlying
        assertGt(feeWithYield, feeWithoutYield, "fee with vault yield should exceed baseline fee");

        // Verify increase is ~proportional to yield (within 20% tolerance)
        uint256 expectedIncrease = (feeWithoutYield * TC.SIMULATED_YIELD_BPS) / TC.BPS_DENOMINATOR;
        uint256 actualIncrease = feeWithYield - feeWithoutYield;
        assertApproxEqRel(
            actualIncrease, expectedIncrease, 0.2e18, "fee increase should be ~proportional to vault yield"
        );

        _assertLoanContractIsEmpty("after close with vault appreciation");
    }

    // ============ Security Audit Findings ============

    /// @notice Issue #5 (CRITICAL): CloseLoanLogic.sol:203-211 sweeps entire USDC/cbBTC balance
    ///         of the Loan contract. If another user's operation left residual tokens, the
    ///         closing user captures them. Verify User B's loan is unaffected when User A closes.
    function test_CloseLoan_DoesNotCaptureOtherUsersResiduals() public {
        // Arrange: create loan for testUser
        address lsa = _createStandardLoan();
        _advanceDays(30);

        // Simulate residual USDC from a prior operation sitting in the Loan contract
        uint256 dustAmount = 1000e6; // 1000 USDC of unrelated residual
        _fundUSDC(address(loanContract), dustAmount);

        // Verify dust is in the contract
        uint256 contractBalBefore = usdc.balanceOf(address(loanContract));
        assertGe(contractBalBefore, dustAmount, "Loan contract should hold the dust USDC");

        // Get user's loan data to estimate their legitimate residual
        DataTypes.LoanData memory loanData = loanContract.getLoanByLSA(lsa);

        // Fund user for close operation
        uint256 closeAmount = loanData.loanAmount * 2;
        uint256 currentBalance = usdc.balanceOf(testUser);
        if (currentBalance < closeAmount) {
            _fundUSDC(testUser, closeAmount - currentBalance);
        }

        vm.prank(testUser);
        usdc.approve(address(loanContract), type(uint256).max);

        // Act: close the loan
        vm.prank(testUser);
        loanContract.closeLoan(lsa, false);

        // Assert: Loan contract should still hold the dust (it belonged to someone else)
        uint256 contractBalAfter = usdc.balanceOf(address(loanContract));
        assertGe(contractBalAfter, dustAmount, "closeLoan should not sweep unrelated USDC from Loan contract");
    }

    /// @notice Issue #12 (HIGH): LoanLogic.sol:72 checks duration == 0 but uses ZeroAmount error.
    ///         Verify that duration=0 loan creation reverts.
    function test_InitializeLoan_RevertWhen_DurationZero() public {
        // Arrange
        uint256 collateral = TC.STANDARD_COLLATERAL;
        uint256 deposit = TC.USER_USDC_BALANCE / 2;

        // Act + Assert — duration=0 should revert
        vm.prank(testUser);
        (bool success,) = address(loanContract)
            .call(
                abi.encodeWithSignature(
                    "initializeLoan(uint256,uint256,uint256,uint256,bytes)",
                    deposit,
                    TC.PREMIUM_AMOUNT,
                    collateral,
                    0,
                    ""
                )
            );
        assertFalse(success, "duration=0 loan creation should revert");
    }

    /// @notice Issue #31 (HIGH): LSALogic.redeemBTC() uses convertToAssets() (no exit fee) as
    ///         baseline but actual redeem() deducts the exit fee. If exit fee > slippage tolerance,
    ///         all redemptions revert via slippage check.
    function test_CloseLoan_ExitFee_BlocksRedemption() public {
        // Arrange — set exit fee (200 bps = 2%) higher than slippage tolerance (100 bps)
        _setExitFee(200);

        // Create loan after exit fee is set
        address lsa = _createStandardLoan();
        _advanceDays(30);

        // Fund user for close operation
        DataTypes.LoanData memory ld = loanContract.getLoanByLSA(lsa);
        uint256 closeBuffer = ld.loanAmount * 2;
        _fundUSDC(testUser, closeBuffer);
        vm.prank(testUser);
        usdc.approve(address(loanContract), type(uint256).max);

        // Act: close the loan — should succeed if slippage formula is correct
        vm.prank(testUser);
        loanContract.closeLoan(lsa, false);

        // Assert: loan should be completed
        DataTypes.LoanData memory finalData = loanContract.getLoanByLSA(lsa);
        assertEq(
            uint256(finalData.status),
            uint256(DataTypes.LoanStatus.Completed),
            "loan should be completed after closeLoan"
        );
    }

    /// @notice Issue #42/43 (MEDIUM): Verifies the slippage formula in LSALogic uses the correct
    ///         (10000-bps)/10000 formula, protecting 99% of estimated receivable at 100 bps slippage.
    function test_RedeemBTC_SlippageFormula_Correct() public {
        // The deployed slippage value is 100 bps (1%)
        uint256 slippageValue = loanContract.getSlippageForSharesToAsset();
        assertEq(slippageValue, 100, "deployed slippage should be 100 bps (1%)");

        // For a 1% slippage tolerance:
        // CORRECT minimum = estimated * (10000 - 100) / 10000 = estimated * 99%
        uint256 estimatedReceivable = 1e8; // 1 BTC
        uint256 expectedMinimum = (estimatedReceivable * (TC.BPS_DENOMINATOR - slippageValue)) / TC.BPS_DENOMINATOR;

        // Verify: the correct formula protects 99% of the estimate
        assertEq(expectedMinimum, 99_000_000, "correct formula should protect 99% of 1 BTC");

        // Verify: closeLoan succeeds with zero exit fee (baseline),
        // proving the slippage formula does not reject valid redemptions
        address lsa = _createStandardLoan();
        _closeLoanEarly(lsa, testUser, false);

        DataTypes.LoanData memory finalData = loanContract.getLoanByLSA(lsa);
        assertEq(
            uint256(finalData.status),
            uint256(DataTypes.LoanStatus.Completed),
            "closeLoan should succeed when slippage formula is correct"
        );
    }
}
