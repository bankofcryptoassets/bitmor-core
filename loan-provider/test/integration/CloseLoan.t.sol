// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.30;

import {IntegrationTestBase} from "../base/IntegrationTestBase.sol";
import {TestConstants as TC} from "../helpers/TestConstants.sol";
import {DataTypes} from "@bitmor/libraries/types/DataTypes.sol";
import {IERC20} from "@openzeppelin/interfaces/IERC20.sol";
import {Errors} from "@bitmor/libraries/helpers/Errors.sol";
import {ILoan} from "@bitmor/interfaces/ILoan.sol";

/// @title CloseLoanTest
/// @notice Adversarial integration tests for close loan edge cases and timing attacks.
/// @dev Runs against pre-deployed contracts on local Anvil via `make deploy-local`.
///      A failing test is a FINDING, not a test bug. See plan header for rules.
contract CloseLoanTest is IntegrationTestBase {
    // ============ Constants ============

    uint256 internal constant REPAYMENT_INTERVAL = 30 days;
    uint256 internal constant CLOSE_INSUFFICIENT_PRICE_DROP = 80;
    uint256 internal constant MICRO_LIQ_COUNT = 3;
    uint256 internal constant SIMULATED_YIELD_BPS = 500;

    // ============ Setup ============

    function setUp() public override {
        super.setUp();
        _setupTestUser();
        _setupLiquidator();
    }

    // ============ Close Loan Helpers ============

    /// @notice Closes a loan as the testUser (borrower)
    function _closeLoanAsBorrower(address lsa, bool withdrawInBTC) internal {
        vm.prank(testUser);
        loanContract.closeLoan(lsa, withdrawInBTC);
    }

    /// @notice Fully repays a loan via repay() so status becomes Completed
    /// @dev Passes `type(uint256).max` to avoid stale-read race: _getDebtBalanceUSDC reads VDT
    ///      balance in one call, but by the time repay() executes, Anvil may auto-mine a new block
    ///      accruing interest. type(uint256).max lets RepayLogic read the LIVE VDT balance internally.
    function _fullyRepayLoan(address lsa) internal {
        uint256 totalDebt = _getDebtBalanceUSDC(lsa);
        require(totalDebt > 0, "fullyRepayLoan: no debt to repay");

        uint256 buffer = totalDebt / 100 + 1e6; // 1% + 1 USDC
        uint256 userBal = usdc.balanceOf(testUser);
        if (userBal < totalDebt + buffer) {
            _fundUSDC(testUser, totalDebt + buffer - userBal);
            vm.prank(testUser);
            usdc.approve(address(loanContract), type(uint256).max);
        }

        _repayLoan(lsa, testUser, type(uint256).max);
    }

    /// @notice Executes N micro-liquidations by advancing time and triggering each one
    function _executeMicroLiquidations(address lsa, uint256 count) internal {
        for (uint256 i = 0; i < count; i++) {
            if (i == 0) {
                _makeFirstPaymentOverdue();
            } else {
                vm.warp(block.timestamp + REPAYMENT_INTERVAL + config.getGracePeriod() + 1);
            }

            uint256 liquidationType = _checkTypeOfLiquidation(lsa);
            require(liquidationType == TC.LIQUIDATION_TYPE_MICRO, "not micro-liquidatable");

            bool success = _triggerMicroLiquidation(lsa);
            require(success, "microLiquidationCall failed");
        }
    }

    /// @notice Gets the pre-closure fee in basis points
    function _getPreClosureFeeBps() internal view returns (uint256) {
        return loanContract.getPreClosureFee();
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
        _closeLoanAsBorrower(lsa, true);
        uint256 btcReceivedA = cbBTC.balanceOf(testUser) - userBtcBeforeA;
        uint256 usdcReceivedA = usdc.balanceOf(testUser) - userUsdcBeforeA;
        // Normalize BTC to 6-dec USDC: btc(8d) * price(8d) / 1e8 / 1e2
        uint256 btcValueInUSDC6_A = btcReceivedA * uint256(btcPrice) / TC.PRICE_PRECISION / 1e2;
        uint256 totalValueA = btcValueInUSDC6_A + usdcReceivedA;

        // --- Path B: withdrawInBTC = false ---
        vm.revertTo(snapId);
        uint256 userBtcBeforeB = cbBTC.balanceOf(testUser);
        uint256 userUsdcBeforeB = usdc.balanceOf(testUser);
        _closeLoanAsBorrower(lsa, false);
        uint256 btcReceivedB = cbBTC.balanceOf(testUser) - userBtcBeforeB;
        uint256 usdcReceivedB = usdc.balanceOf(testUser) - userUsdcBeforeB;
        uint256 btcValueInUSDC6_B = btcReceivedB * uint256(btcPrice) / TC.PRICE_PRECISION / 1e2;
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
        uint256 feeFloor = collateralInBTC * feeBps / TC.BPS_DENOMINATOR;

        address premiumCollector = loanContract.getPremiumCollector();
        uint256 collectorBtcBefore = cbBTC.balanceOf(premiumCollector);

        _closeLoanAsBorrower(lsa, true);

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

        vm.expectEmit(true, true, true, true);
        emit ILoan.Loan__ClosedLoan(lsa);

        _closeLoanAsBorrower(lsa, true);

        DataTypes.LoanData memory loanData = loanContract.getLoanByLSA(lsa);
        assertEq(uint256(loanData.status), uint256(DataTypes.LoanStatus.Completed), "loan should be completed");
        assertGe(usdc.balanceOf(aaveV3Pool), aaveBalBefore, "Aave pool should be repaid");
        assertEq(usdc.balanceOf(address(loanContract)), 0, "Loan contract should have zero USDC");
        assertEq(cbBTC.balanceOf(address(loanContract)), 0, "Loan contract should have zero cbBTC");
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
        _closeLoanAsBorrower(lsa, true);

        DataTypes.LoanData memory loanData = loanContract.getLoanByLSA(lsa);
        assertEq(uint256(loanData.status), uint256(DataTypes.LoanStatus.Completed), "loan should be completed");
        assertGt(cbBTC.balanceOf(testUser), userBtcBefore, "user should receive remaining BTC");
        assertEq(usdc.balanceOf(address(loanContract)), 0, "no residual USDC");
        assertEq(cbBTC.balanceOf(address(loanContract)), 0, "no residual cbBTC");
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
            uint256(loanDataAfterMicroLiq.status),
            uint256(DataTypes.LoanStatus.Active),
            "loan should still be active"
        );

        (uint256 collateralAfterMicroLiq, uint256 debtAfterMicroLiq,) = _getUserAccountData(lsa);
        assertGt(collateralAfterMicroLiq, 0, "should still have collateral");
        assertGt(debtAfterMicroLiq, 0, "should still have debt");

        uint256 userBtcBefore = cbBTC.balanceOf(testUser);
        _closeLoanAsBorrower(lsa, true);

        DataTypes.LoanData memory loanDataFinal = loanContract.getLoanByLSA(lsa);
        assertEq(uint256(loanDataFinal.status), uint256(DataTypes.LoanStatus.Completed), "loan should be completed");
        assertGt(cbBTC.balanceOf(testUser), userBtcBefore, "user should receive remaining BTC");
        assertEq(usdc.balanceOf(address(loanContract)), 0, "no residual USDC");
        assertEq(cbBTC.balanceOf(address(loanContract)), 0, "no residual cbBTC");
    }

    // ============ Test 10.7: Zero Debt After Full Repay Reverts ============

    /// @notice 10.7: Close loan reverts after full repayment (loan already Completed)
    function test_CloseLoan_ZeroDebt_AfterFullRepay_Reverts() public {
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
        _closeLoanAsBorrower(lsa, true);
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
            uint256(loanDataAfterLiq.status),
            uint256(DataTypes.LoanStatus.Liquidated),
            "loan should be liquidated"
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
        assertEq(
            uint256(loanDataAfter.status), uint256(DataTypes.LoanStatus.Liquidated), "loan should be liquidated"
        );

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
        address premiumCollector = loanContract.getPremiumCollector();
        uint256 collectorBefore1 = cbBTC.balanceOf(premiumCollector);
        _closeLoanAsBorrower(lsa1, true);
        uint256 feeWithoutYield = cbBTC.balanceOf(premiumCollector) - collectorBefore1;
        assertGt(feeWithoutYield, 0, "baseline fee should be non-zero");

        // --- Test: close loan WITH vault yield ---
        vm.warp(block.timestamp + 1); // Avoid CREATE2 salt collision
        address lsa2 = _createStandardLoan();

        _simulateVaultYield(SIMULATED_YIELD_BPS);
        vm.warp(block.timestamp + 1);

        uint256 collectorBefore2 = cbBTC.balanceOf(premiumCollector);
        _closeLoanAsBorrower(lsa2, true);
        uint256 feeWithYield = cbBTC.balanceOf(premiumCollector) - collectorBefore2;
        assertGt(feeWithYield, 0, "fee with yield should be non-zero");

        DataTypes.LoanData memory loanData = loanContract.getLoanByLSA(lsa2);
        assertEq(uint256(loanData.status), uint256(DataTypes.LoanStatus.Completed), "loan should be completed");

        // Fee with yield > fee without yield proves fee is on appreciated underlying
        assertGt(feeWithYield, feeWithoutYield, "fee with vault yield should exceed baseline fee");

        // Verify increase is ~proportional to yield (within 20% tolerance)
        uint256 expectedIncrease = feeWithoutYield * SIMULATED_YIELD_BPS / TC.BPS_DENOMINATOR;
        uint256 actualIncrease = feeWithYield - feeWithoutYield;
        assertApproxEqRel(
            actualIncrease, expectedIncrease, 0.20e18, "fee increase should be ~proportional to vault yield"
        );

        assertEq(usdc.balanceOf(address(loanContract)), 0, "no residual USDC");
        assertEq(cbBTC.balanceOf(address(loanContract)), 0, "no residual cbBTC");
    }
}
