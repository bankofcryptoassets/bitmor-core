// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {BaseLoanTest} from "./BaseLoan.t.sol";
import {DataTypes} from "@bitmor/libraries/types/DataTypes.sol";
import {IERC20} from "@openzeppelin/interfaces/IERC20.sol";
import {Errors} from "@bitmor/libraries/helpers/Errors.sol";
import {ILoan} from "@bitmor/interfaces/ILoan.sol";
import {Constants} from "@bitmor/libraries/helpers/Constants.sol";
import {MockVariableDebtToken} from "../../mock/MockVariableDebtToken.sol";

/// @title ClaimSurplusCollateralTest
/// @author Bitmor Protocol
/// @notice Tests for explicit borrower surplus collateral claim after liquidation or completion
/// @dev Covers `claimSurplusCollateral` reverts, happy paths, and the debt guard in LSALogic.
contract ClaimSurplusCollateralTest is BaseLoanTest {
    // ============ claimSurplusCollateral Reverts ============

    /// @notice `claimSurplusCollateral` reverts when loan is still Active
    function test_claimSurplusCollateral_RevertsWhen_LoanIsActive() public setUpLoanForUser {
        address lsa = loan.getUserLoanAtIndex(user, 0);

        DataTypes.LoanData memory loanData = loan.getLoanByLSA(lsa);
        assertEq(uint256(loanData.status), uint256(DataTypes.LoanStatus.Active), "loan should be active");

        vm.expectRevert(Errors.Loan__InvalidLoanStatus.selector);
        vm.prank(user);
        loan.claimSurplusCollateral(lsa);
    }

    /// @notice `claimSurplusCollateral` reverts when called by non-borrower on a Liquidated loan
    function test_claimSurplusCollateral_RevertsWhen_CalledByNonBorrower() public setUpLoanForUser {
        address lsa = loan.getUserLoanAtIndex(user, 0);

        _setupForFullLiquidation(lsa, PRICE_DROP_FOR_LIQUIDATION);
        _executeFullLiquidation(lsa, type(uint256).max, false);

        DataTypes.LoanData memory loanData = loan.getLoanByLSA(lsa);
        assertEq(uint256(loanData.status), uint256(DataTypes.LoanStatus.Liquidated), "loan should be liquidated");

        vm.expectRevert(Errors.Loan__OnlyBorrower.selector);
        vm.prank(liquidator);
        loan.claimSurplusCollateral(lsa);
    }

    /// @notice `claimSurplusCollateral` reverts for zero address
    function test_claimSurplusCollateral_RevertsWhen_ZeroAddress() public {
        vm.expectRevert(Errors.ZeroAddress.selector);
        vm.prank(user);
        loan.claimSurplusCollateral(address(0));
    }

    /// @notice `claimSurplusCollateral` reverts when loan does not exist
    function test_claimSurplusCollateral_RevertsWhen_LoanDoesNotExist() public {
        address fakeLsa = makeAddr("fakeLsa");

        vm.expectRevert(Errors.LoanDoesNotExists.selector);
        vm.prank(user);
        loan.claimSurplusCollateral(fakeLsa);
    }

    /// @notice `claimSurplusCollateral` reverts when called by admin on a Liquidated loan
    function test_claimSurplusCollateral_RevertsWhen_CalledByAdmin() public setUpLoanForUser {
        address lsa = loan.getUserLoanAtIndex(user, 0);

        _setupForFullLiquidation(lsa, PRICE_DROP_FOR_LIQUIDATION);
        _executeFullLiquidation(lsa, type(uint256).max, false);

        DataTypes.LoanData memory loanData = loan.getLoanByLSA(lsa);
        assertEq(uint256(loanData.status), uint256(DataTypes.LoanStatus.Liquidated), "loan should be liquidated");

        vm.expectRevert(Errors.Loan__OnlyBorrower.selector);
        vm.prank(admin);
        loan.claimSurplusCollateral(lsa);
    }

    // ============ claimSurplusCollateral Happy Path ============

    /// @notice Borrower can claim surplus collateral after full liquidation
    function test_claimSurplusCollateral_AfterFullLiquidation() public setUpLoanForUser {
        address lsa = loan.getUserLoanAtIndex(user, 0);

        // Use 20% price drop so there IS surplus collateral remaining
        _setupForFullLiquidation(lsa, PRICE_DROP_FOR_LIQUIDATION);
        _executeFullLiquidation(lsa, type(uint256).max, false);

        // Verify status is Liquidated
        DataTypes.LoanData memory loanData = loan.getLoanByLSA(lsa);
        assertEq(uint256(loanData.status), uint256(DataTypes.LoanStatus.Liquidated), "loan should be liquidated");

        // Verify surplus collateral exists in BLP
        uint256 lsaCollateral = _getCollateralBalance(lsa);
        assertGt(lsaCollateral, 0, "LSA should have surplus collateral in BLP");

        // Snapshot borrower cbBTC balance before claim
        uint256 borrowerCbBtcBefore = IERC20(btc).balanceOf(user);

        // Borrower claims surplus collateral
        vm.prank(user);
        loan.claimSurplusCollateral(lsa);

        // Verify borrower received cbBTC
        uint256 borrowerCbBtcAfter = IERC20(btc).balanceOf(user);
        assertGt(borrowerCbBtcAfter, borrowerCbBtcBefore, "borrower should receive surplus cbBTC");
    }

    /// @notice `claimSurplusCollateral` emits `Loan__SurplusCollateralClaimed` event
    function test_claimSurplusCollateral_EmitsEvent() public setUpLoanForUser {
        address lsa = loan.getUserLoanAtIndex(user, 0);

        _setupForFullLiquidation(lsa, PRICE_DROP_FOR_LIQUIDATION);
        _executeFullLiquidation(lsa, type(uint256).max, false);

        // Verify surplus collateral exists
        uint256 lsaCollateral = _getCollateralBalance(lsa);
        assertGt(lsaCollateral, 0, "LSA should have surplus collateral");

        // Expect the SurplusCollateralClaimed event (check indexed params, don't check data since amount is dynamic)
        vm.expectEmit(true, true, false, false);
        emit ILoan.Loan__SurplusCollateralClaimed(lsa, user, 0);

        vm.prank(user);
        loan.claimSurplusCollateral(lsa);
    }

    /// @notice Borrower can claim surplus after micro-liquidation completion (duration=1)
    function test_claimSurplusCollateral_AfterMicroLiquidationCompletion() public {
        // Create a loan with duration=1 for a separate borrower (avoids CREATE2 collision)
        address borrower2 = makeAddr("borrower2");
        address lsa = _createLoanForBorrower(borrower2, STANDARD_COLLATERAL_AMOUNT, 1, PREMIUM_AMOUNT);

        // Register loan in addresses provider
        _updateAddressesProviderBitmorLoan();

        // Verify loan is Active with duration 1
        DataTypes.LoanData memory loanData = loan.getLoanByLSA(lsa);
        assertEq(uint256(loanData.status), uint256(DataTypes.LoanStatus.Active), "loan should start active");
        assertEq(loanData.duration, 1, "duration should be 1");

        // Fund liquidator and set up micro-liquidation conditions
        _fundLiquidator();
        _warpPastGracePeriod();
        mockBitmorPool.setUserOverdue(lsa, true);
        _setLiquidationType(lsa, LIQUIDATION_TYPE_MICRO);

        // Execute micro-liquidation (covers full debt for duration=1)
        _executeMicroLiquidation(lsa);

        // Verify debt is fully covered
        uint256 remainingDebt = _getDebtBalance(lsa);
        assertEq(remainingDebt, 0, "debt should be fully covered after micro-liquidation of duration=1 loan");

        // Verify surplus collateral exists
        uint256 lsaCollateralAfterMicroLiq = _getCollateralBalance(lsa);
        assertGt(lsaCollateralAfterMicroLiq, 0, "LSA should have surplus collateral after micro-liquidation");

        // Complete the micro-liquidation (sets status to Completed)
        vm.prank(address(mockBitmorPool));
        loan.updateLoanForMicroLiquidationCompletion(lsa);

        // Verify status is Completed
        loanData = loan.getLoanByLSA(lsa);
        assertEq(uint256(loanData.status), uint256(DataTypes.LoanStatus.Completed), "loan should be completed");

        // Snapshot borrower cbBTC balance before manual claim
        uint256 borrowerCbBtcBefore = IERC20(btc).balanceOf(borrower2);

        // Borrower claims surplus collateral
        vm.prank(borrower2);
        loan.claimSurplusCollateral(lsa);

        // Verify borrower received cbBTC
        uint256 borrowerCbBtcAfter = IERC20(btc).balanceOf(borrower2);
        assertGt(borrowerCbBtcAfter, borrowerCbBtcBefore, "borrower should receive surplus cbBTC from manual claim");
    }

    // ============ Debt Guard: claimRemainingCollateral reverts with outstanding debt ============

    /// @notice `claimSurplusCollateral` reverts when LSA still has outstanding variable debt
    function test_claimSurplusCollateral_RevertsWhen_OutstandingDebtExists() public setUpLoanForUser {
        address lsa = loan.getUserLoanAtIndex(user, 0);

        // Setup for full liquidation
        _setupForFullLiquidation(lsa, PRICE_DROP_FOR_LIQUIDATION);

        // Execute full liquidation with partial debt coverage (half the debt)
        uint256 initialDebt = _getDebtBalance(lsa);
        uint256 partialDebt = initialDebt / 2;
        _executeFullLiquidation(lsa, partialDebt, false);

        // Verify LSA still has outstanding debt
        uint256 remainingDebt = _getDebtBalance(lsa);
        assertGt(remainingDebt, 0, "LSA should still have outstanding debt after partial liquidation");

        DataTypes.LoanData memory loanData = loan.getLoanByLSA(lsa);
        assertEq(
            uint256(loanData.status),
            uint256(DataTypes.LoanStatus.Liquidated),
            "loan should be Liquidated after full liquidation call"
        );

        // Attempt to claim surplus -- should revert because debt is non-zero
        vm.expectRevert(Errors.LSALogic__OutstandingDebtExists.selector);
        vm.prank(user);
        loan.claimSurplusCollateral(lsa);
    }

    /// @notice Second call to `claimSurplusCollateral` reverts when collateral already claimed
    function test_claimSurplusCollateral_RevertsWhen_AlreadyClaimed() public setUpLoanForUser {
        address lsa = loan.getUserLoanAtIndex(user, 0);

        _setupForFullLiquidation(lsa, PRICE_DROP_FOR_LIQUIDATION);
        _executeFullLiquidation(lsa, type(uint256).max, false);

        // First claim succeeds
        vm.prank(user);
        loan.claimSurplusCollateral(lsa);

        // Second claim should revert (no collateral left)
        vm.expectRevert(Errors.Loan__ClaimingSurplusCollateralFailed.selector);
        vm.prank(user);
        loan.claimSurplusCollateral(lsa);
    }

    // ============ Liquidation No Longer Auto-Claims ============

    /// @notice Full liquidation does NOT automatically claim surplus — collateral stays in BLP
    function test_fullLiquidation_DoesNotAutoClaimSurplus() public setUpLoanForUser {
        address lsa = loan.getUserLoanAtIndex(user, 0);

        _setupForFullLiquidation(lsa, PRICE_DROP_FOR_LIQUIDATION);

        // Snapshot borrower balance before liquidation
        uint256 borrowerCbBtcBefore = IERC20(btc).balanceOf(user);

        // Execute full liquidation
        _executeFullLiquidation(lsa, type(uint256).max, false);

        // Verify status is Liquidated
        DataTypes.LoanData memory loanData = loan.getLoanByLSA(lsa);
        assertEq(uint256(loanData.status), uint256(DataTypes.LoanStatus.Liquidated), "loan should be liquidated");

        // Verify borrower did NOT receive cbBTC automatically
        uint256 borrowerCbBtcAfter = IERC20(btc).balanceOf(user);
        assertEq(borrowerCbBtcAfter, borrowerCbBtcBefore, "borrower should NOT receive cbBTC during liquidation");

        // Verify surplus collateral still exists in BLP for the LSA
        uint256 lsaCollateral = _getCollateralBalance(lsa);
        assertGt(lsaCollateral, 0, "surplus collateral should remain in BLP after liquidation");
    }

    // ============ Dust Debt Edge Cases ============

    /// @notice `claimSurplusCollateral` reverts when borrower has not approved USDC for dust debt repayment
    function test_claimSurplusCollateral_RevertsWhen_NoBorrowerApproval_DustDebt() public setUpLoanForUser {
        address lsa = loan.getUserLoanAtIndex(user, 0);
        uint256 dustAmount = 5; // 5 wei of USDC dust debt

        // Execute full liquidation to clear debt and set status to Liquidated
        _setupForFullLiquidation(lsa, PRICE_DROP_FOR_LIQUIDATION);
        _executeFullLiquidation(lsa, type(uint256).max, false);

        DataTypes.LoanData memory loanData = loan.getLoanByLSA(lsa);
        assertEq(uint256(loanData.status), uint256(DataTypes.LoanStatus.Liquidated), "loan should be liquidated");

        // Simulate Aave V2 rayDiv rounding leaving dust debt
        vm.prank(address(mockBitmorPool));
        mockDebtTokenUSDC.mint(lsa, dustAmount);

        uint256 remainingDebt = _getDebtBalance(lsa);
        assertEq(remainingDebt, dustAmount, "LSA should have dust debt");

        // Revoke any existing approval so transfer will fail
        vm.prank(user);
        mockUSDC.approve(address(loan), 0);

        // claimSurplusCollateral should revert because borrower has no USDC approval for dust repayment
        vm.expectRevert();
        vm.prank(user);
        loan.claimSurplusCollateral(lsa);
    }

    /// @notice `claimSurplusCollateral` succeeds when borrower approves dust amount and emits DustDebtAbsorbed
    function test_claimSurplusCollateral_SucceedsWithDustDebt_BorrowerApproves() public setUpLoanForUser {
        address lsa = loan.getUserLoanAtIndex(user, 0);
        uint256 dustAmount = 5; // 5 wei of USDC dust debt

        // Execute full liquidation to clear debt and set status to Liquidated
        _setupForFullLiquidation(lsa, PRICE_DROP_FOR_LIQUIDATION);
        _executeFullLiquidation(lsa, type(uint256).max, false);

        DataTypes.LoanData memory loanData = loan.getLoanByLSA(lsa);
        assertEq(uint256(loanData.status), uint256(DataTypes.LoanStatus.Liquidated), "loan should be liquidated");

        // Verify surplus collateral exists
        uint256 lsaCollateral = _getCollateralBalance(lsa);
        assertGt(lsaCollateral, 0, "LSA should have surplus collateral");

        // Simulate Aave V2 rayDiv rounding leaving dust debt
        vm.prank(address(mockBitmorPool));
        mockDebtTokenUSDC.mint(lsa, dustAmount);

        uint256 remainingDebt = _getDebtBalance(lsa);
        assertEq(remainingDebt, dustAmount, "LSA should have dust debt");

        // Fund borrower with USDC for dust repayment and approve Loan contract
        _fundUSDC(user, dustAmount);
        vm.prank(user);
        mockUSDC.approve(address(loan), dustAmount);

        // Snapshot borrower cbBTC balance before claim
        uint256 borrowerCbBtcBefore = IERC20(btc).balanceOf(user);

        // Expect DustDebtAbsorbed event
        vm.expectEmit(true, false, false, true);
        emit ILoan.Loan__DustDebtAbsorbed(lsa, dustAmount);

        // Borrower claims surplus collateral — dust repayment happens automatically
        vm.prank(user);
        uint256 assetsClaimed = loan.claimSurplusCollateral(lsa);

        // Verify debt is now zero
        uint256 debtAfter = _getDebtBalance(lsa);
        assertEq(debtAfter, 0, "debt should be zero after dust repayment");

        // Verify borrower received cbBTC
        uint256 borrowerCbBtcAfter = IERC20(btc).balanceOf(user);
        assertGt(borrowerCbBtcAfter, borrowerCbBtcBefore, "borrower should receive surplus cbBTC");
        assertGt(assetsClaimed, 0, "assetsClaimed should be positive");
    }

    /// @notice Micro-liquidation completion does NOT automatically claim surplus — collateral stays in BLP
    function test_microLiquidationCompletion_DoesNotAutoClaimSurplus() public {
        address borrower2 = makeAddr("borrower2");
        address lsa = _createLoanForBorrower(borrower2, STANDARD_COLLATERAL_AMOUNT, 1, PREMIUM_AMOUNT);

        _updateAddressesProviderBitmorLoan();

        // Fund liquidator and set up micro-liquidation
        _fundLiquidator();
        _warpPastGracePeriod();
        mockBitmorPool.setUserOverdue(lsa, true);
        _setLiquidationType(lsa, LIQUIDATION_TYPE_MICRO);

        _executeMicroLiquidation(lsa);

        // Snapshot borrower balance before completion
        uint256 borrowerCbBtcBefore = IERC20(btc).balanceOf(borrower2);

        // Complete micro-liquidation
        vm.prank(address(mockBitmorPool));
        loan.updateLoanForMicroLiquidationCompletion(lsa);

        // Verify status is Completed
        DataTypes.LoanData memory loanData = loan.getLoanByLSA(lsa);
        assertEq(uint256(loanData.status), uint256(DataTypes.LoanStatus.Completed), "loan should be completed");

        // Verify borrower did NOT receive cbBTC automatically
        uint256 borrowerCbBtcAfter = IERC20(btc).balanceOf(borrower2);
        assertEq(borrowerCbBtcAfter, borrowerCbBtcBefore, "borrower should NOT receive cbBTC during completion");

        // Verify surplus collateral still exists in BLP
        uint256 lsaCollateral = _getCollateralBalance(lsa);
        assertGt(lsaCollateral, 0, "surplus collateral should remain in BLP after completion");
    }

    // ============ Dust Debt Tests (vuln-27) ============

    /// @notice `claimSurplusCollateral` succeeds when LSA has dust debt within threshold
    /// @dev Exercises the LSALogic threshold path: `> DEBT_DUST_THRESHOLD` instead of `!= 0`.
    ///      After full liquidation covers all debt, we mint 5 wei of dust debt to simulate
    ///      Aave V2 rounding residuals.
    function test_claimSurplusCollateral_succeedsWithDustDebt() public setUpLoanForUser {
        address lsa = loan.getUserLoanAtIndex(user, 0);

        // Full liquidation covers all debt
        _setupForFullLiquidation(lsa, PRICE_DROP_FOR_LIQUIDATION);
        _executeFullLiquidation(lsa, type(uint256).max, false);

        DataTypes.LoanData memory loanData = loan.getLoanByLSA(lsa);
        assertEq(uint256(loanData.status), uint256(DataTypes.LoanStatus.Liquidated), "loan should be liquidated");
        assertEq(_getDebtBalance(lsa), 0, "debt should be fully covered by liquidation");

        // Simulate Aave V2 rounding: mint 5 wei dust debt onto LSA
        uint256 dustAmount = 5;
        vm.prank(address(mockBitmorPool));
        mockDebtTokenUSDC.mint(lsa, dustAmount);
        assertEq(_getDebtBalance(lsa), dustAmount, "LSA should have dust debt");

        // Verify surplus collateral exists
        uint256 lsaCollateral = _getCollateralBalance(lsa);
        assertGt(lsaCollateral, 0, "LSA should have surplus collateral");

        // Snapshot borrower cbBTC balance before claim
        uint256 borrowerCbBtcBefore = IERC20(btc).balanceOf(user);

        // Claim should succeed despite dust debt (within threshold)
        vm.prank(user);
        loan.claimSurplusCollateral(lsa);

        // Verify borrower received surplus cbBTC
        uint256 borrowerCbBtcAfter = IERC20(btc).balanceOf(user);
        assertGt(borrowerCbBtcAfter, borrowerCbBtcBefore, "borrower should receive surplus cbBTC despite dust debt");
    }

    /// @notice `claimSurplusCollateral` succeeds at exact dust threshold boundary
    /// @dev 10 wei == DEBT_DUST_THRESHOLD — should pass the `> threshold` check
    function test_claimSurplusCollateral_succeedsAtExactThreshold() public setUpLoanForUser {
        address lsa = loan.getUserLoanAtIndex(user, 0);

        _setupForFullLiquidation(lsa, PRICE_DROP_FOR_LIQUIDATION);
        _executeFullLiquidation(lsa, type(uint256).max, false);

        // Mint exactly DEBT_DUST_THRESHOLD (10 wei) of dust debt
        vm.prank(address(mockBitmorPool));
        mockDebtTokenUSDC.mint(lsa, Constants.DEBT_DUST_THRESHOLD);
        assertEq(_getDebtBalance(lsa), Constants.DEBT_DUST_THRESHOLD, "LSA should have threshold dust debt");

        // Claim should succeed at exact threshold
        vm.prank(user);
        loan.claimSurplusCollateral(lsa);

        // Verify borrower received surplus
        assertGt(IERC20(btc).balanceOf(user), 0, "borrower should receive surplus cbBTC at threshold");
    }

    /// @notice `claimSurplusCollateral` reverts when dust debt exceeds threshold
    /// @dev 11 wei > DEBT_DUST_THRESHOLD — should trigger `LSALogic__OutstandingDebtExists`
    function test_claimSurplusCollateral_revertsWhenDustDebtExceedsThreshold() public setUpLoanForUser {
        address lsa = loan.getUserLoanAtIndex(user, 0);

        _setupForFullLiquidation(lsa, PRICE_DROP_FOR_LIQUIDATION);
        _executeFullLiquidation(lsa, type(uint256).max, false);

        // Mint 11 wei — just above the threshold
        uint256 aboveThreshold = Constants.DEBT_DUST_THRESHOLD + 1;
        vm.prank(address(mockBitmorPool));
        mockDebtTokenUSDC.mint(lsa, aboveThreshold);
        assertEq(_getDebtBalance(lsa), aboveThreshold, "LSA should have above-threshold debt");

        // Claim should revert with OutstandingDebtExists
        vm.expectRevert(Errors.LSALogic__OutstandingDebtExists.selector);
        vm.prank(user);
        loan.claimSurplusCollateral(lsa);
    }
}
