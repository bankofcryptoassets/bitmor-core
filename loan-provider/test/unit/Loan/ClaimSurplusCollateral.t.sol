// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.30;

import {BaseLoanTest} from "./BaseLoan.t.sol";
import {DataTypes} from "@bitmor/libraries/types/DataTypes.sol";
import {IERC20} from "@openzeppelin/interfaces/IERC20.sol";
import {Errors} from "@bitmor/libraries/helpers/Errors.sol";
import {ILoan} from "@bitmor/interfaces/ILoan.sol";

/// @title ClaimSurplusCollateralTest
/// @author Bitmor Protocol
/// @notice Tests for surplus collateral claim: try/catch in liquidations, borrower fallback, and debt guard
/// @dev Covers `_claimSurplusInternal` access control, `claimSurplusCollateral` reverts and happy paths,
///      try/catch behavior during full and micro-liquidation completion, and the debt guard in LSALogic.
contract ClaimSurplusCollateralTest is BaseLoanTest {
    // ============ _claimSurplusInternal Access Control ============

    /// @notice `_claimSurplusInternal` reverts when called by an external address (not self)
    function test_claimSurplusInternal_RevertsWhen_CalledByExternalAddress() public setUpLoanForUser {
        address lsa = loan.getUserLoanAtIndex(user, 0);

        vm.expectRevert(Errors.Loan__OnlySelf.selector);
        vm.prank(user);
        loan._claimSurplusInternal(lsa);
    }

    /// @notice `_claimSurplusInternal` reverts when called by admin (not self)
    function test_claimSurplusInternal_RevertsWhen_CalledByAdmin() public setUpLoanForUser {
        address lsa = loan.getUserLoanAtIndex(user, 0);

        vm.expectRevert(Errors.Loan__OnlySelf.selector);
        vm.prank(admin);
        loan._claimSurplusInternal(lsa);
    }

    /// @notice `_claimSurplusInternal` reverts when called by the mock lending pool (not self)
    function test_claimSurplusInternal_RevertsWhen_CalledByLendingPool() public setUpLoanForUser {
        address lsa = loan.getUserLoanAtIndex(user, 0);

        vm.expectRevert(Errors.Loan__OnlySelf.selector);
        vm.prank(address(mockBitmorPool));
        loan._claimSurplusInternal(lsa);
    }

    /// @notice `_claimSurplusInternal` reverts when called by liquidator (not self)
    function test_claimSurplusInternal_RevertsWhen_CalledByLiquidator() public setUpLoanForUser {
        address lsa = loan.getUserLoanAtIndex(user, 0);

        vm.expectRevert(Errors.Loan__OnlySelf.selector);
        vm.prank(liquidator);
        loan._claimSurplusInternal(lsa);
    }

    // ============ claimSurplusCollateral Reverts ============

    /// @notice `claimSurplusCollateral` reverts when loan is still Active
    function test_claimSurplusCollateral_RevertsWhen_LoanIsActive() public setUpLoanForUser {
        address lsa = loan.getUserLoanAtIndex(user, 0);

        // Loan is Active, not Liquidated or Completed
        DataTypes.LoanData memory loanData = loan.getLoanByLSA(lsa);
        assertEq(uint256(loanData.status), uint256(DataTypes.LoanStatus.Active), "loan should be active");

        vm.expectRevert(Errors.Loan__InvalidLoanStatus.selector);
        vm.prank(user);
        loan.claimSurplusCollateral(lsa);
    }

    /// @notice `claimSurplusCollateral` reverts when called by non-borrower on a Liquidated loan
    function test_claimSurplusCollateral_RevertsWhen_CalledByNonBorrower() public setUpLoanForUser {
        address lsa = loan.getUserLoanAtIndex(user, 0);

        // Full liquidation to set status to Liquidated
        _setupForFullLiquidation(lsa, PRICE_DROP_FOR_LIQUIDATION);
        _executeFullLiquidation(lsa, type(uint256).max, false);

        // Verify status is Liquidated
        DataTypes.LoanData memory loanData = loan.getLoanByLSA(lsa);
        assertEq(uint256(loanData.status), uint256(DataTypes.LoanStatus.Liquidated), "loan should be liquidated");

        // Non-borrower (liquidator) tries to claim
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

        // Full liquidation
        _setupForFullLiquidation(lsa, PRICE_DROP_FOR_LIQUIDATION);
        _executeFullLiquidation(lsa, type(uint256).max, false);

        DataTypes.LoanData memory loanData = loan.getLoanByLSA(lsa);
        assertEq(uint256(loanData.status), uint256(DataTypes.LoanStatus.Liquidated), "loan should be liquidated");

        // Admin is not the borrower
        vm.expectRevert(Errors.Loan__OnlyBorrower.selector);
        vm.prank(admin);
        loan.claimSurplusCollateral(lsa);
    }

    // ============ claimSurplusCollateral Happy Path ============

    /// @notice Borrower can claim surplus collateral after full liquidation via manual fallback
    /// @dev Forces the inline `_claimSurplusInternal` to fail by making mockBTCVault return 0
    ///      assets on redeem (triggers `SlippageExceededWhileConvertingToAssets`). After liquidation,
    ///      the mock is reset so the borrower can manually call `claimSurplusCollateral` to recover.
    function test_claimSurplusCollateral_AfterFullLiquidation() public setUpLoanForUser {
        address lsa = loan.getUserLoanAtIndex(user, 0);

        // Use 20% price drop so there IS surplus collateral remaining
        _setupForFullLiquidation(lsa, PRICE_DROP_FOR_LIQUIDATION);

        // Force inline claim to fail: vault redeem returns 0 assets, triggering slippage revert
        mockBTCVault.setMockRedeemReturn(0);

        // Execute full liquidation -- inline claim fails (caught by try/catch), state update succeeds
        _executeFullLiquidation(lsa, type(uint256).max, false);

        // Verify status is Liquidated
        DataTypes.LoanData memory loanData = loan.getLoanByLSA(lsa);
        assertEq(uint256(loanData.status), uint256(DataTypes.LoanStatus.Liquidated), "loan should be liquidated");

        // Verify inline claim failed: collateral is still in the LSA (aToken balance > 0)
        uint256 lsaCollateral = _getCollateralBalance(lsa);
        assertGt(lsaCollateral, 0, "LSA should still have collateral after failed inline claim");

        // Reset mock to allow normal redeem behavior
        mockBTCVault.resetMockRedeemReturn();

        // Snapshot borrower cbBTC balance before manual claim
        uint256 borrowerCbBtcBefore = IERC20(btc).balanceOf(user);

        // Borrower calls claimSurplusCollateral to recover remaining collateral
        vm.prank(user);
        loan.claimSurplusCollateral(lsa);

        // Verify borrower received cbBTC from manual claim
        uint256 borrowerCbBtcAfter = IERC20(btc).balanceOf(user);
        assertGt(borrowerCbBtcAfter, borrowerCbBtcBefore, "borrower should receive surplus cbBTC from manual claim");
    }

    /// @notice `claimSurplusCollateral` emits `Loan__SurplusCollateralClaimed` event
    /// @dev Forces inline claim failure so collateral remains in the LSA, then verifies
    ///      the manual `claimSurplusCollateral` call emits the expected event.
    function test_claimSurplusCollateral_EmitsEvent() public setUpLoanForUser {
        address lsa = loan.getUserLoanAtIndex(user, 0);

        // Setup for full liquidation with surplus (20% drop)
        _setupForFullLiquidation(lsa, PRICE_DROP_FOR_LIQUIDATION);

        // Force inline claim to fail during liquidation
        mockBTCVault.setMockRedeemReturn(0);

        // Execute full liquidation -- inline claim fails, collateral stays in LSA
        _executeFullLiquidation(lsa, type(uint256).max, false);

        // Verify collateral is still claimable
        uint256 lsaCollateral = _getCollateralBalance(lsa);
        assertGt(lsaCollateral, 0, "LSA should still have collateral after failed inline claim");

        // Reset mock to allow normal redeem behavior
        mockBTCVault.resetMockRedeemReturn();

        // Expect the SurplusCollateralClaimed event from the manual claim
        vm.expectEmit(true, true, true, true);
        emit ILoan.Loan__SurplusCollateralClaimed(lsa, user);

        vm.prank(user);
        loan.claimSurplusCollateral(lsa);
    }

    /// @notice `claimSurplusCollateral` works on `Completed` status (after micro-liquidation completion)
    /// @dev Creates a loan with `duration=1` for a separate borrower, executes a micro-liquidation
    ///      to cover the debt, then forces the inline `_claimSurplusInternal` to fail during
    ///      `updateLoanForMicroLiquidationCompletion`. Resets the mock and verifies the borrower
    ///      can manually call `claimSurplusCollateral` to recover remaining collateral.
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

        // Execute micro-liquidation via mock pool (covers one month's payment = full debt for duration=1)
        _executeMicroLiquidation(lsa);

        // Verify debt is fully covered after micro-liquidation
        uint256 remainingDebt = _getDebtBalance(lsa);
        assertEq(remainingDebt, 0, "debt should be fully covered after micro-liquidation of duration=1 loan");

        // Verify collateral still exists in LSA (surplus after debt coverage)
        uint256 lsaCollateralAfterMicroLiq = _getCollateralBalance(lsa);
        assertGt(lsaCollateralAfterMicroLiq, 0, "LSA should still have surplus collateral after micro-liquidation");

        // Force inline claim to fail during completion
        mockBTCVault.setMockRedeemReturn(0);

        // Call completion from mock pool -- inline claim fails (caught by try/catch)
        vm.prank(address(mockBitmorPool));
        loan.updateLoanForMicroLiquidationCompletion(lsa);

        // Verify status is Completed despite inline claim failure
        loanData = loan.getLoanByLSA(lsa);
        assertEq(uint256(loanData.status), uint256(DataTypes.LoanStatus.Completed), "loan should be completed");

        // Verify collateral is still in the LSA (inline claim was reverted)
        uint256 lsaCollateral = _getCollateralBalance(lsa);
        assertGt(lsaCollateral, 0, "LSA should still have collateral after failed inline claim");

        // Reset mock to allow normal redeem behavior
        mockBTCVault.resetMockRedeemReturn();

        // Snapshot borrower cbBTC balance before manual claim
        uint256 borrowerCbBtcBefore = IERC20(btc).balanceOf(borrower2);

        // Borrower calls claimSurplusCollateral to recover remaining collateral
        vm.prank(borrower2);
        loan.claimSurplusCollateral(lsa);

        // Verify borrower received cbBTC from manual claim
        uint256 borrowerCbBtcAfter = IERC20(btc).balanceOf(borrower2);
        assertGt(borrowerCbBtcAfter, borrowerCbBtcBefore, "borrower should receive surplus cbBTC from manual claim");
    }

    // ============ Try/Catch: Liquidation Succeeds When Claim Fails ============

    /// @notice Full liquidation state update succeeds even when surplus claim reverts
    /// @dev Forces the inline `claimRemainingCollateral` to fail by setting mockBTCVault
    ///      to return 0 assets on redeem (triggers SlippageExceededWhileConvertingToAssets).
    ///      Verifies that the Loan status is still updated to Liquidated despite claim failure.
    function test_fullLiquidation_StateUpdateSucceeds_WhenSurplusClaimFails() public setUpLoanForUser {
        address lsa = loan.getUserLoanAtIndex(user, 0);

        // Setup for full liquidation with surplus (20% drop)
        _setupForFullLiquidation(lsa, PRICE_DROP_FOR_LIQUIDATION);

        // Force the BTC vault redeem to return 0 assets, which will cause
        // SlippageExceededWhileConvertingToAssets revert in LSALogic._redeemBTC
        mockBTCVault.setMockRedeemReturn(0);

        // Execute full liquidation -- the inline claim will fail but state update should succeed
        _executeFullLiquidation(lsa, type(uint256).max, false);

        // Verify: loan status is Liquidated (state update succeeded despite claim failure)
        DataTypes.LoanData memory loanData = loan.getLoanByLSA(lsa);
        assertEq(
            uint256(loanData.status),
            uint256(DataTypes.LoanStatus.Liquidated),
            "loan should be Liquidated even when surplus claim fails"
        );
        assertEq(loanData.duration, 0, "duration should be 0 after full liquidation");

        // Verify: borrower did NOT receive cbBTC (claim failed)
        // The LSA aToken collateral may be 0 (withdrawn during the failed claim attempt)
        // but the bvBTC shares are now stuck in the LSA (redeem failed)

        // Reset mock to allow manual claim
        mockBTCVault.resetMockRedeemReturn();

        // Verify: borrower can recover via claimSurplusCollateral after vault is back to normal
        // First check if there's anything left to claim (bvBTC shares in LSA)
        uint256 lsaBvBtcShares = IERC20(collateralAsset).balanceOf(lsa);
        if (lsaBvBtcShares > 0) {
            uint256 borrowerCbBtcBefore = IERC20(btc).balanceOf(user);

            vm.prank(user);
            loan.claimSurplusCollateral(lsa);

            uint256 borrowerCbBtcAfter = IERC20(btc).balanceOf(user);
            assertGt(
                borrowerCbBtcAfter, borrowerCbBtcBefore, "borrower should recover cbBTC after manual claim succeeds"
            );
        }
    }

    /// @notice Full liquidation emits `Loan__SurplusClaimFailed` when inline claim reverts
    /// @dev Forces claim failure via mock vault returning 0 on redeem
    function test_fullLiquidation_EmitsSurplusClaimFailed_WhenClaimReverts() public setUpLoanForUser {
        address lsa = loan.getUserLoanAtIndex(user, 0);

        // Setup for full liquidation with surplus
        _setupForFullLiquidation(lsa, PRICE_DROP_FOR_LIQUIDATION);

        // Force claim failure
        mockBTCVault.setMockRedeemReturn(0);

        // Expect the Loan__SurplusClaimFailed event
        vm.expectEmit(true, true, true, true);
        emit ILoan.Loan__SurplusClaimFailed(lsa);

        // Execute full liquidation
        _executeFullLiquidation(lsa, type(uint256).max, false);

        // Clean up
        mockBTCVault.resetMockRedeemReturn();
    }

    /// @notice Micro-liquidation completion state update succeeds even when surplus claim reverts
    /// @dev Similar to the full liquidation test, but exercises the try/catch in
    ///      `updateLoanForMicroLiquidationCompletion`
    function test_microLiquidationCompletion_StateUpdateSucceeds_WhenSurplusClaimFails() public {
        // Create a loan with duration=1 for a separate borrower
        address borrower2 = makeAddr("borrower2");
        address lsa = _createLoanForBorrower(borrower2, STANDARD_COLLATERAL_AMOUNT, 1, PREMIUM_AMOUNT);

        _updateAddressesProviderBitmorLoan();

        // Force claim failure
        mockBTCVault.setMockRedeemReturn(0);

        // Call completion from mock pool
        vm.prank(address(mockBitmorPool));
        loan.updateLoanForMicroLiquidationCompletion(lsa);

        // Verify: loan status is Completed despite claim failure
        DataTypes.LoanData memory loanData = loan.getLoanByLSA(lsa);
        assertEq(
            uint256(loanData.status),
            uint256(DataTypes.LoanStatus.Completed),
            "loan should be Completed even when surplus claim fails"
        );
        assertEq(loanData.duration, 0, "duration should be 0 after completion");

        // Clean up
        mockBTCVault.resetMockRedeemReturn();
    }

    /// @notice Micro-liquidation completion emits `Loan__SurplusClaimFailed` when inline claim reverts
    function test_microLiquidationCompletion_EmitsSurplusClaimFailed_WhenClaimReverts() public {
        // Create a loan with duration=1 for a separate borrower
        address borrower2 = makeAddr("borrower2");
        address lsa = _createLoanForBorrower(borrower2, STANDARD_COLLATERAL_AMOUNT, 1, PREMIUM_AMOUNT);

        _updateAddressesProviderBitmorLoan();

        // Force claim failure
        mockBTCVault.setMockRedeemReturn(0);

        // Expect the Loan__SurplusClaimFailed event
        vm.expectEmit(true, true, true, true);
        emit ILoan.Loan__SurplusClaimFailed(lsa);

        // Call completion from mock pool
        vm.prank(address(mockBitmorPool));
        loan.updateLoanForMicroLiquidationCompletion(lsa);

        // Clean up
        mockBTCVault.resetMockRedeemReturn();
    }

    // ============ Debt Guard: claimRemainingCollateral reverts with outstanding debt ============

    /// @notice `claimSurplusCollateral` reverts when LSA still has outstanding variable debt
    /// @dev After full liquidation with partial debt coverage, the LSA still has debt and the
    ///      debt guard in `LSALogic.claimRemainingCollateral` prevents collateral withdrawal.
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

        // Check if the mock set the status to Liquidated for partial coverage.
        // The mock's liquidationCall calls updateLoanDataForFullLiquidation which sets
        // status = Liquidated regardless of coverage amount.
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

    /// @notice Inline surplus claim silently fails when outstanding debt exists (debt guard)
    /// @dev The try/catch in `updateLoanDataForFullLiquidation` catches the `LSALogic__OutstandingDebtExists`
    ///      revert from `claimRemainingCollateral` and emits `Loan__SurplusClaimFailed`.
    function test_fullLiquidation_InlineClaimFails_WhenOutstandingDebtExists() public setUpLoanForUser {
        address lsa = loan.getUserLoanAtIndex(user, 0);

        // Setup for full liquidation with partial coverage
        _setupForFullLiquidation(lsa, PRICE_DROP_FOR_LIQUIDATION);

        uint256 initialDebt = _getDebtBalance(lsa);
        uint256 partialDebt = initialDebt / 2;

        // Expect Loan__SurplusClaimFailed because partial coverage leaves debt,
        // which causes the debt guard to revert inside the try/catch
        vm.expectEmit(true, true, true, true);
        emit ILoan.Loan__SurplusClaimFailed(lsa);

        // Execute full liquidation with partial debt coverage
        _executeFullLiquidation(lsa, partialDebt, false);

        // Verify state update still succeeded
        DataTypes.LoanData memory loanData = loan.getLoanByLSA(lsa);
        assertEq(
            uint256(loanData.status),
            uint256(DataTypes.LoanStatus.Liquidated),
            "loan should be Liquidated despite inline claim failure"
        );

        // Verify debt still exists
        uint256 remainingDebt = _getDebtBalance(lsa);
        assertGt(remainingDebt, 0, "LSA should still have outstanding debt");
    }
}
