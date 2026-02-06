// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.30;

import {console2} from "forge-std/console2.sol";
import {BaseLoanTest} from "./BaseLoan.t.sol";
import {DataTypes} from "@bitmor/libraries/types/DataTypes.sol";
import {IERC20} from "@openzeppelin/interfaces/IERC20.sol";
import {IPool} from "@bitmor/interfaces/IPool.sol";
import {Errors} from "@bitmor/libraries/helpers/Errors.sol";
import {Vm} from "forge-std/Vm.sol";
import {ERC4626} from "@solady/tokens/ERC4626.sol";

/// @title CloseLoanTest
/// @author Bitmor Protocol
/// @notice Tests for `Loan.closeLoan` covering withdrawal modes, pre-closure fees, flash loan security, and edge cases
contract CloseLoanTest is BaseLoanTest {
    // ============ Constants ============

    /// @dev ERC20 `Transfer` event signature hash used for log parsing in transfer verification
    bytes32 private constant TRANSFER_EVENT_SIG = keccak256("Transfer(address,address,uint256)");

    // ============ Local Structs ============
    // Note: Uses TestSnapshot + UserBalanceSnapshot from BaseLoanTest
    // Extended with close-loan-specific fields

    /// @notice Close loan state combining `TestSnapshot` and `UserBalanceSnapshot` for before/after comparison
    struct CloseLoanExtension {
        TestSnapshot loanState;
        UserBalanceSnapshot userBalances;
    }

    /// @notice Parsed ERC20 transfer event data
    struct TransferInfo {
        address from;
        address to;
        uint256 amount;
    }

    // ============ Local Helpers ============

    /// @notice Captures loan and user balance state before `closeLoan` into a `CloseLoanExtension`
    function _captureCloseLoanStateBefore(address lsa) internal view returns (CloseLoanExtension memory state) {
        state.loanState = _captureTestSnapshot(lsa);
        state.userBalances = _captureUserBalanceSnapshot();
    }

    /// @notice Populates "after" fields in `CloseLoanExtension` with current state
    function _updateCloseLoanStateAfter(CloseLoanExtension memory state, address lsa) internal view {
        _updateTestSnapshotAfter(state.loanState, lsa);
        _updateUserBalanceSnapshotAfter(state.userBalances);
    }

    /// @dev Parse ERC20 Transfer logs to find transfers from Loan contract to user
    /// @param logs The recorded logs
    /// @param token The token address to filter by
    /// @param from The sender address to filter by
    /// @param to The recipient address to filter by
    /// @return totalAmount The sum of all matching transfer amounts
    function _parseTransferLogs(Vm.Log[] memory logs, address token, address from, address to)
        internal
        pure
        returns (uint256 totalAmount)
    {
        for (uint256 i = 0; i < logs.length; i++) {
            // Check if this is a Transfer event from the correct token
            if (logs[i].emitter == token && logs[i].topics[0] == TRANSFER_EVENT_SIG) {
                // topics[1] = from (indexed), topics[2] = to (indexed)
                address logFrom = address(uint160(uint256(logs[i].topics[1])));
                address logTo = address(uint160(uint256(logs[i].topics[2])));

                if (logFrom == from && logTo == to) {
                    // data contains the amount (non-indexed)
                    uint256 amount = abi.decode(logs[i].data, (uint256));
                    totalAmount += amount;
                }
            }
        }
    }

    /// @notice Returns the pre-closure fee in basis points from the loan contract
    function _getPreClosureFeeBps() internal view returns (uint256) {
        return loan.getPreClosureFee();
    }

    /// @notice Calculates the expected pre-closure fee in BTC for a given `collateralAmount` of vault shares
    function _calculatePreClosureFee(uint256 collateralAmount) internal view returns (uint256) {
        return (ERC4626(mockBTCVault).previewRedeem(collateralAmount) * _getPreClosureFeeBps()) / 10000;
    }

    // ============ Close Loan Tests ============

    /// @notice Test closing loan and withdrawing in collateral asset (BTC)
    function test_closeLoan_withWithdrawingAssetInCollateralAsset() public setUpLoanForUser {
        address lsa = loan.getUserLoanAtIndex(user, 0);
        bool withdrawInBTC = true;

        // Capture state before using generic helpers
        CloseLoanExtension memory state = _captureCloseLoanStateBefore(lsa);

        assertGt(state.loanState.debtBefore, 0, "Should have debt before close");
        assertGt(state.loanState.collateralBefore, 0, "Should have collateral before close");
        assertEq(uint256(state.loanState.statusBefore), uint256(DataTypes.LoanStatus.Active), "Should be active before");

        // Record logs for transfer parsing
        vm.recordLogs();

        vm.prank(user);
        loan.closeLoan(lsa, withdrawInBTC);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        _updateCloseLoanStateAfter(state, lsa);

        // Status updated
        assertEq(uint256(state.loanState.statusAfter), uint256(DataTypes.LoanStatus.Completed), "Should be completed");

        // LSA position cleared
        assertEq(state.loanState.debtAfter, 0, "LSA debt should be 0 after close");
        assertEq(state.loanState.collateralAfter, 0, "LSA collateral (aToken) should be 0 after close");

        // User should receive BTC (underlying) when withdrawInBTC=true
        uint256 btcReceived = IERC20(btc).balanceOf(user) - state.userBalances.userCollateralBefore;
        assertGt(btcReceived, 0, "User should receive BTC collateral");

        // Verify Loan transferred some BTC to user
        uint256 transferredFromLoan = _parseTransferLogs(logs, btc, address(loan), user);
        assertGt(transferredFromLoan, 0, "Loan should transfer BTC to user");

        // When withdrawing in collateral asset, USDC received should be minimal (dust)
        uint256 usdcReceived = state.userBalances.userDebtAssetAfter - state.userBalances.userDebtAssetBefore;
        // Allow for some dust but should be very small relative to debt
        assertLt(
            usdcReceived,
            state.loanState.debtBefore / 100,
            "USDC received should be dust when withdrawing in collateral"
        );
    }

    /// @notice Test closing loan and withdrawing in debt asset (USDC)
    function test_closeLoan_withoutWithdrawingAssetInCollateralAsset() public setUpLoanForUser {
        address lsa = loan.getUserLoanAtIndex(user, 0);
        bool withdrawInBTC = false;

        // Capture state before using generic helpers
        CloseLoanExtension memory state = _captureCloseLoanStateBefore(lsa);

        assertGt(state.loanState.debtBefore, 0, "Should have debt before close");
        assertGt(state.loanState.collateralBefore, 0, "Should have collateral before close");

        // Record logs for transfer parsing
        vm.recordLogs();

        vm.prank(user);
        loan.closeLoan(lsa, withdrawInBTC);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        _updateCloseLoanStateAfter(state, lsa);

        // Status updated
        assertEq(uint256(state.loanState.statusAfter), uint256(DataTypes.LoanStatus.Completed), "Should be completed");

        // LSA position cleared
        assertEq(state.loanState.debtAfter, 0, "LSA debt should be 0 after close");
        assertEq(state.loanState.collateralAfter, 0, "LSA collateral (aToken) should be 0 after close");

        // User should receive debt asset (USDC)
        uint256 usdcReceived = state.userBalances.userDebtAssetAfter - state.userBalances.userDebtAssetBefore;
        assertGt(usdcReceived, 0, "User should receive debt asset (USDC)");

        // Parse transfer logs to get exact amount transferred from Loan to user
        uint256 transferredUsdc = _parseTransferLogs(logs, debtAsset, address(loan), user);
        assertEq(usdcReceived, transferredUsdc, "USDC received should match transfer log");
    }

    // ============ Pre-Closure Fee Tests ============

    /// @notice Test that pre-closure fee is correctly deducted (withdrawInBTC = true)
    /// @dev Note: Due to mock limitations (collateralAsset == btc using same mockCbBTC),
    ///      token flow accounting is not 1:1 with production. Fee transfer to collector is verified.
    function test_closeLoan_preClosureFee_deducted_withdrawCollateral() public setUpLoanForUser {
        address lsa = loan.getUserLoanAtIndex(user, 0);
        bool withdrawInBTC = true;

        // Capture state before using generic helpers
        CloseLoanExtension memory state = _captureCloseLoanStateBefore(lsa);
        uint256 expectedFee = _calculatePreClosureFee(state.loanState.collateralBefore);

        assertGt(expectedFee, 0, "Pre-closure fee should be non-zero");

        // Get premium collector address for fee verification
        address premiumCollector = loan.getPremiumCollector();
        uint256 collectorBalanceBefore = IERC20(btc).balanceOf(premiumCollector);

        // Record logs
        vm.recordLogs();

        vm.prank(user);
        loan.closeLoan(lsa, withdrawInBTC);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        // Parse BTC transfers to premium collector (fee sink)
        uint256 feeTransferred = _parseTransferLogs(logs, btc, address(loan), premiumCollector);
        uint256 userCollateralReceived = _parseTransferLogs(logs, btc, address(loan), user);

        // Verify fee was transferred to premium collector (allow +-1 for rounding)
        uint256 collectorBalanceAfter = IERC20(btc).balanceOf(premiumCollector);
        uint256 collectorReceived = collectorBalanceAfter - collectorBalanceBefore;
        assertEq(feeTransferred, expectedFee, "Fee transferred should match expected fee");
        assertEq(collectorReceived, expectedFee, "Premium collector should receive expected fee");

        // Verify user received collateral
        assertGt(userCollateralReceived, 0, "User should receive collateral");
    }

    /// @notice Test that pre-closure fee is correctly deducted (withdrawInBTC = false)
    function test_closeLoan_preClosureFee_deducted_withdrawDebt() public setUpLoanForUser {
        address lsa = loan.getUserLoanAtIndex(user, 0);
        bool withdrawInBTC = false;

        // Capture state before using generic helpers
        CloseLoanExtension memory state = _captureCloseLoanStateBefore(lsa);
        uint256 expectedFee = _calculatePreClosureFee(state.loanState.collateralBefore);

        assertGt(expectedFee, 0, "Pre-closure fee should be non-zero");

        // Get premium collector address for fee verification
        address premiumCollector = loan.getPremiumCollector();

        // Record logs
        vm.recordLogs();

        vm.prank(user);
        loan.closeLoan(lsa, withdrawInBTC);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        // Parse BTC transfers to premium collector (fee is in BTC)
        uint256 feeTransferred = _parseTransferLogs(logs, btc, address(loan), premiumCollector);

        // Verify fee was transferred to premium collector (allow +-1 for rounding)
        assertApproxEqAbs(feeTransferred, expectedFee, 1, "Fee transferred should match expected fee");
    }

    /// @notice Test that flash loan is called with the correct debt amount
    function test_closeLoan_flashLoanCalledWithDebtAmount() public setUpLoanForUser {
        address lsa = loan.getUserLoanAtIndex(user, 0);
        bool withdrawInBTC = true;

        // Get debt amount before close
        uint256 debtAmt = _getDebtBalance(lsa);
        assertGt(debtAmt, 0, "Should have debt");

        // Expect the flash loan call on Aave V3 pool
        // The flashLoanSimple signature: flashLoanSimple(address receiverAddress, address asset, uint256 amount, bytes calldata params, uint16 referralCode)
        vm.expectCall(
            aavePool,
            abi.encodeWithSelector(
                IPool.flashLoanSimple.selector,
                address(loan), // receiver
                debtAsset, // asset
                debtAmt // amount - the debt amount
                // params and referralCode are variable, so we only check the key parameters
            )
        );

        vm.prank(user);
        loan.closeLoan(lsa, withdrawInBTC);

        // Verify loan closed successfully
        uint256 debtAfter = _getDebtBalance(lsa);
        assertEq(debtAfter, 0, "Debt should be 0 after successful close");
    }

    /// @notice Test that closing with zero LSA address reverts
    function test_RevertWhen_ZeroLsaAddress() public setUpLoanForUser {
        vm.prank(user);
        vm.expectRevert(Errors.ZeroAddress.selector);
        loan.closeLoan(address(0), true);
    }

    /// @notice Test that closing a non-existent LSA reverts
    function test_RevertWhen_LoanDoesNotExist() public setUpLoanForUser {
        address randomAddress = makeAddr("nonExistentLsa");

        vm.prank(user);
        vm.expectRevert(Errors.LoanDoesNotExists.selector);
        loan.closeLoan(randomAddress, true);
    }

    /// @notice Test that closing with insufficient collateral reverts
    /// @dev Drop BTC price so totalCollateralUSD <= totalDebtUSD + fees
    function test_RevertWhen_InsufficientCollateral() public setUpLoanForUser {
        address lsa = loan.getUserLoanAtIndex(user, 0);

        // Drop collateral price significantly (e.g., 80% drop)
        // This should make collateral value less than debt + fees
        _dropOraclePrice(collateralAsset, 80);

        vm.prank(user);
        vm.expectRevert(Errors.InsufficientCollateral.selector);
        loan.closeLoan(lsa, true);
    }

    /// @notice Test that closing a loan after full repayment reverts
    /// @dev Once debt is fully repaid via repay(), loan status is Completed
    function test_RevertWhen_ClosingAfterFullRepayment() public setUpLoanForUser {
        address lsa = loan.getUserLoanAtIndex(user, 0);
        uint256 totalDebt = _getDebtBalance(lsa);

        console2.log("bvbTC shares in LSA:", IERC20(collateralAsset).balanceOf(lsa));

        // Fully repay the loan
        vm.prank(user);
        loan.repay(lsa, totalDebt);

        console2.log("reached here");

        // Verify loan is completed
        DataTypes.LoanData memory loanData = loan.getLoanByLSA(lsa);
        assertEq(
            uint256(loanData.status), uint256(DataTypes.LoanStatus.Completed), "Should be completed after full repay"
        );
        assertEq(_getDebtBalance(lsa), 0, "Debt should be 0");

        vm.prank(user);
        vm.expectRevert(Errors.LoanIsNotActive.selector);
        loan.closeLoan(lsa, true);
    }

    /// @notice Test that double-closing a loan reverts
    function test_RevertWhen_DoubleClose() public setUpLoanForUser {
        address lsa = loan.getUserLoanAtIndex(user, 0);

        // First close should succeed
        vm.prank(user);
        loan.closeLoan(lsa, true);

        // Verify LSA positions are cleared
        assertEq(_getDebtBalance(lsa), 0, "Debt should be 0 after first close");
        assertEq(_getCollateralBalance(lsa), 0, "Collateral should be 0 after first close");

        vm.prank(user);
        vm.expectRevert(Errors.LoanIsNotActive.selector);
        loan.closeLoan(lsa, true);
    }

    /// @notice Test that non-borrower cannot close someone else's loan
    /// @dev Security test - should revert with access control error
    function test_RevertWhen_CallerNotBorrower() public setUpLoanForUser {
        address lsa = loan.getUserLoanAtIndex(user, 0);
        address attacker = makeAddr("attacker");

        // Verify the loan belongs to user, not attacker
        DataTypes.LoanData memory loanData = loan.getLoanByLSA(lsa);
        assertEq(loanData.borrower, user, "Loan should belong to user");
        assertTrue(attacker != user, "Attacker should be different from user");

        // Non-borrower should not be able to close the loan
        vm.prank(attacker);
        vm.expectRevert(Errors.UnauthorizedCaller.selector);
        loan.closeLoan(lsa, true);
    }

    // ============ Flash Loan Callback Security Tests ============

    /// @notice Test that close loan callback reverts when initiator is not the Loan contract
    /// @dev Covers FlashLoanLogic.sol:182 WrongFLInitiator error
    function test_RevertWhen_CloseLoanWrongFlashLoanInitiator() public {
        // Arrange - prepare flash loan params for close loan with wrong initiator
        address wrongInitiator = makeAddr("wrongInitiator");
        address mockLsa = makeAddr("mockLsa");
        // flData for close: (lsa, withdrawInBTC, totalBTCAmtToSwap, preClosureFeeAmtInBTC)
        bytes memory flData = abi.encode(mockLsa, true, TEST_BTC_SWAP_AMOUNT, TEST_PRECLOSURE_FEE);
        bytes memory params = abi.encode(false, flData); // false = closing loan

        // Act & Assert - call from Aave pool (correct caller) but with wrong initiator
        vm.prank(address(mockAavePool));
        vm.expectRevert(Errors.WrongFLInitiator.selector);
        loan.executeOperation(debtAsset, FLASH_LOAN_AMOUNT, FLASH_LOAN_PREMIUM, wrongInitiator, params);
    }

    /// @notice Test that close loan callback reverts when caller is not Aave pool
    /// @dev Covers FlashLoanLogic.sol:179-180 CallerIsNotAAVEPool error
    /// @dev Note: Init path tested in AccessControls.t.sol, this tests close path
    function test_RevertWhen_CloseLoanCallerNotAavePool() public {
        // Arrange
        address attacker = makeAddr("attacker");
        address mockLsa = makeAddr("mockLsa");
        bytes memory flData = abi.encode(mockLsa, true, TEST_BTC_SWAP_AMOUNT, TEST_PRECLOSURE_FEE);
        bytes memory params = abi.encode(false, flData); // false = closing loan

        // Act & Assert
        vm.prank(attacker);
        vm.expectRevert(Errors.CallerIsNotAAVEPool.selector);
        loan.executeOperation(debtAsset, FLASH_LOAN_AMOUNT, FLASH_LOAN_PREMIUM, address(loan), params);
    }

    /// @notice Test that close loan reverts when collateral withdrawal returns zero
    /// @dev Covers FlashLoanLogic.sol:212 CollateralWithdrawFailed error
    function test_RevertWhen_CloseLoanCollateralWithdrawFails() public setUpLoanForUser {
        // Arrange
        address lsa = loan.getUserLoanAtIndex(user, 0);

        // Set mock to simulate withdrawal failure for the LSA
        mockBitmorPool.setWithdrawalFailure(lsa, true);

        // Act & Assert - close loan should fail when collateral withdrawal fails
        vm.prank(user);
        vm.expectRevert(Errors.CollateralWithdrawFailed.selector);
        loan.closeLoan(lsa, true);

        // Reset for other tests
        mockBitmorPool.setWithdrawalFailure(lsa, false);
    }

    // ============ Edge Case Tests ============

    /// @notice Test close loan with both withdrawal modes produce different results
    function test_closeLoan_withdrawModes_differ() public {
        // Setup two loans to compare both withdrawal modes
        _mintDebtAssetToUser();

        // Create first loan (will close with withdrawInBTC=true)
        (,, uint256 minDeposit1) = loan.getLoanDetails(STANDARD_COLLATERAL_AMOUNT, STANDARD_DURATION);
        vm.prank(user);
        address lsa1 =
            loan.initializeLoan(minDeposit1, PREMIUM_AMOUNT, STANDARD_COLLATERAL_AMOUNT, STANDARD_DURATION, DATA);

        // Capture state before first close
        uint256 userCollateralBefore1 = IERC20(btc).balanceOf(user);
        uint256 userDebtAssetBefore1 = IERC20(debtAsset).balanceOf(user);

        // Close first loan withdrawing in BTC (collateral)
        vm.prank(user);
        loan.closeLoan(lsa1, true);

        uint256 userCollateralAfter1 = IERC20(btc).balanceOf(user);
        uint256 userDebtAssetAfter1 = IERC20(debtAsset).balanceOf(user);

        // Calculate deltas for mode 1 (withdrawInBTC=true)
        uint256 btcReceived1 = userCollateralAfter1 - userCollateralBefore1;
        uint256 usdcReceived1 = userDebtAssetAfter1 - userDebtAssetBefore1;

        // Mode 1 should primarily receive BTC
        assertGt(btcReceived1, 0, "Mode 1 should receive BTC");

        // Warp time to avoid CREATE2 collision (factory uses block.timestamp in salt)
        vm.warp(block.timestamp + 1);

        // Mint more funds for second loan
        _mintDebtAssetToUser();

        // Create second loan (will close with withdrawInBTC=false)
        (,, uint256 minDeposit2) = loan.getLoanDetails(STANDARD_COLLATERAL_AMOUNT, STANDARD_DURATION);
        vm.prank(user);
        address lsa2 =
            loan.initializeLoan(minDeposit2, PREMIUM_AMOUNT, STANDARD_COLLATERAL_AMOUNT, STANDARD_DURATION, DATA);

        // Capture state before second close
        uint256 userCollateralBefore2 = IERC20(btc).balanceOf(user);
        uint256 userDebtAssetBefore2 = IERC20(debtAsset).balanceOf(user);

        // Close second loan withdrawing in USDC (debt asset)
        vm.prank(user);
        loan.closeLoan(lsa2, false);

        uint256 userCollateralAfter2 = IERC20(btc).balanceOf(user);
        uint256 userDebtAssetAfter2 = IERC20(debtAsset).balanceOf(user);

        // Calculate deltas for mode 2 (withdrawInBTC=false)
        uint256 btcReceived2 = userCollateralAfter2 - userCollateralBefore2;
        uint256 usdcReceived2 = userDebtAssetAfter2 - userDebtAssetBefore2;

        // Mode 2 should primarily receive USDC (collateral swapped to debt asset)
        assertGt(usdcReceived2, 0, "Mode 2 should receive USDC");

        // The two modes should produce different token distribution
        // Mode 1: more BTC, less USDC. Mode 2: less BTC, more USDC.
        assertTrue(
            btcReceived1 > btcReceived2 || usdcReceived2 > usdcReceived1,
            "Withdrawal modes should produce different token distributions"
        );
    }

    /// @notice Test close immediately after loan creation
    function test_closeLoan_immediatelyAfterCreation() public setUpLoanForUser {
        address lsa = loan.getUserLoanAtIndex(user, 0);

        // No time warp - close immediately
        CloseLoanExtension memory state = _captureCloseLoanStateBefore(lsa);

        vm.prank(user);
        loan.closeLoan(lsa, true);
        _updateCloseLoanStateAfter(state, lsa);

        assertEq(state.loanState.debtAfter, 0, "Debt should be 0");
        assertEq(state.loanState.collateralAfter, 0, "Collateral should be 0");
    }

    /// @notice Test close after interest accrual
    /// @dev SKIPPED: MockVariableDebtToken doesn't accrue interest over time.
    ///      This test requires real interest accrual logic which is not implemented in mocks.
    ///      See Task 14: Fix RepayLoan interest accrual tests
    function test_closeLoan_afterInterestAccrual() public setUpLoanForUser {
        address lsa = loan.getUserLoanAtIndex(user, 0);

        // Warp 90 days - note: mock doesn't accrue interest
        vm.warp(block.timestamp + 90 days);

        // Skip interest assertion - mock doesn't implement interest accrual
        // Interest accrual tests require real lending pool integration

        // Close should still work (with original debt amount)
        vm.prank(user);
        loan.closeLoan(lsa, true);

        assertEq(_getDebtBalance(lsa), 0, "Debt should be 0 after close");
        assertEq(_getCollateralBalance(lsa), 0, "Collateral should be 0 after close");
    }
}
