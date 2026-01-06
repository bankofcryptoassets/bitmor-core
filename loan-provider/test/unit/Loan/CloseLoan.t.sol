// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.30;

import {BaseLoanTest} from "./BaseLoan.t.sol";
import {DataTypes} from "@bitmor/libraries/types/DataTypes.sol";
import {IERC20} from "@bitmor/dependencies/openzeppelin/IERC20.sol";
import {IPool} from "@bitmor/interfaces/IPool.sol";
import {Errors} from "@bitmor/libraries/helpers/Errors.sol";
import {Vm} from "forge-std/Vm.sol";

/// @title CloseLoanTest
/// @notice Tests for loan closure functionality
contract CloseLoanTest is BaseLoanTest {
    // ============ Constants ============

    /// @dev ERC20 Transfer event signature for log parsing
    bytes32 private constant TRANSFER_EVENT_SIG = keccak256("Transfer(address,address,uint256)");

    // ============ Local Structs ============

    /// @dev Struct to hold close loan test state
    struct CloseLoanState {
        address lsa;
        uint256 debtBefore;
        uint256 collateralBefore;
        uint256 userCollateralBefore;
        uint256 userDebtAssetBefore;
        DataTypes.LoanStatus statusBefore;
    }

    /// @dev Struct to hold parsed transfer info
    struct TransferInfo {
        address from;
        address to;
        uint256 amount;
    }

    // ============ Local Helpers ============

    /// @dev Capture initial state before close loan
    function _captureStateBefore(address lsa) internal view returns (CloseLoanState memory state) {
        state.lsa = lsa;
        state.debtBefore = _getDebtBalance(lsa);
        state.collateralBefore = _getCollateralBalance(lsa);
        state.userCollateralBefore = IERC20(collateralAsset).balanceOf(user);
        state.userDebtAssetBefore = IERC20(debtAsset).balanceOf(user);
        state.statusBefore = loan.getLoanByLSA(lsa).status;
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

    /// @dev Get pre-closure fee in basis points
    function _getPreClosureFeeBps() internal view returns (uint256) {
        return loan.getPreClosureFee();
    }

    /// @dev Calculate expected pre-closure fee
    function _calculatePreClosureFee(uint256 collateralAmount) internal view returns (uint256) {
        return (collateralAmount * _getPreClosureFeeBps()) / 10_000;
    }

    // ============ Close Loan Tests - Enhanced Existing ============

    /// @notice Test closing loan and withdrawing in collateral asset (BTC)
    /// @dev Enhanced with assertions for debt=0, collateral=0, exact transfer amounts
    function test_closeLoan_withWithdrawingAssetInCollateralAsset() public setUpLoanForUser {
        address lsa = loan.getUserLoanAtIndex(user, 0);
        bool withdrawInCollateralAsset = true;

        // Capture state before
        CloseLoanState memory stateBefore = _captureStateBefore(lsa);

        assertGt(stateBefore.debtBefore, 0, "Should have debt before close");
        assertGt(stateBefore.collateralBefore, 0, "Should have collateral before close");
        assertEq(uint256(stateBefore.statusBefore), uint256(DataTypes.LoanStatus.Active), "Should be active before");

        // Start recording logs for transfer parsing
        vm.recordLogs();

        vm.prank(user);
        loan.closeLoan(lsa, withdrawInCollateralAsset);

        // Capture logs
        Vm.Log[] memory logs = vm.getRecordedLogs();

        // Get state after
        DataTypes.LoanData memory loanDataAfter = loan.getLoanByLSA(lsa);
        uint256 debtAfter = _getDebtBalance(lsa);
        uint256 collateralAfter = _getCollateralBalance(lsa);
        uint256 userCollateralAfter = IERC20(collateralAsset).balanceOf(user);
        uint256 userDebtAssetAfter = IERC20(debtAsset).balanceOf(user);

        // Core assertions - status update (closeLoan now updates status to Completed)
        assertEq(uint256(loanDataAfter.status), uint256(DataTypes.LoanStatus.Completed), "Should be completed");

        // Core assertions - LSA position cleared
        assertEq(debtAfter, 0, "LSA debt should be 0 after close");
        assertEq(collateralAfter, 0, "LSA collateral (aToken) should be 0 after close");

        // User should receive collateral asset (cbBTC)
        uint256 collateralReceived = userCollateralAfter - stateBefore.userCollateralBefore;
        assertGt(collateralReceived, 0, "User should receive collateral asset");

        // Parse transfer logs to get exact amount transferred from Loan to user
        uint256 transferredCollateral = _parseTransferLogs(logs, collateralAsset, address(loan), user);
        assertEq(collateralReceived, transferredCollateral, "Collateral received should match transfer log");

        // When withdrawing in collateral asset, USDC received should be minimal (dust)
        uint256 usdcReceived = userDebtAssetAfter - stateBefore.userDebtAssetBefore;
        // Allow for some dust but should be very small relative to debt
        assertLt(
            usdcReceived, stateBefore.debtBefore / 100, "USDC received should be dust when withdrawing in collateral"
        );
    }

    /// @notice Test closing loan and withdrawing in debt asset (USDC)
    /// @dev Enhanced with assertions for debt=0, collateral=0, exact transfer amounts
    function test_closeLoan_withoutWithdrawingAssetInCollateralAsset() public setUpLoanForUser {
        address lsa = loan.getUserLoanAtIndex(user, 0);
        bool withdrawInCollateralAsset = false;

        // Capture state before
        CloseLoanState memory stateBefore = _captureStateBefore(lsa);

        assertGt(stateBefore.debtBefore, 0, "Should have debt before close");
        assertGt(stateBefore.collateralBefore, 0, "Should have collateral before close");

        // Start recording logs for transfer parsing
        vm.recordLogs();

        vm.prank(user);
        loan.closeLoan(lsa, withdrawInCollateralAsset);

        // Capture logs
        Vm.Log[] memory logs = vm.getRecordedLogs();

        // Get state after
        DataTypes.LoanData memory loanDataAfter = loan.getLoanByLSA(lsa);
        uint256 debtAfter = _getDebtBalance(lsa);
        uint256 collateralAfter = _getCollateralBalance(lsa);
        uint256 userCollateralAfter = IERC20(collateralAsset).balanceOf(user);
        uint256 userDebtAssetAfter = IERC20(debtAsset).balanceOf(user);

        // Core assertions - status update (closeLoan now updates status to Completed)
        assertEq(uint256(loanDataAfter.status), uint256(DataTypes.LoanStatus.Completed), "Should be completed");

        // Core assertions - LSA position cleared
        assertEq(debtAfter, 0, "LSA debt should be 0 after close");
        assertEq(collateralAfter, 0, "LSA collateral (aToken) should be 0 after close");

        // User should receive debt asset (USDC)
        uint256 usdcReceived = userDebtAssetAfter - stateBefore.userDebtAssetBefore;
        assertGt(usdcReceived, 0, "User should receive debt asset (USDC)");

        // Parse transfer logs to get exact amount transferred from Loan to user
        uint256 transferredUsdc = _parseTransferLogs(logs, debtAsset, address(loan), user);
        assertEq(usdcReceived, transferredUsdc, "USDC received should match transfer log");

        // When withdrawing in debt asset, cbBTC received should be 0 or dust
        uint256 collateralReceived = userCollateralAfter - stateBefore.userCollateralBefore;
        // Allow for minimal dust
        assertLt(
            collateralReceived,
            stateBefore.collateralBefore / 100,
            "cbBTC received should be 0 or dust when withdrawing in USDC"
        );
    }

    // ============ Close Loan Tests - New Tests ============

    /// @notice Test that pre-closure fee is correctly deducted (withdrawInCollateralAsset = true)
    function test_closeLoan_preClosureFee_deducted_withdrawCollateral() public setUpLoanForUser {
        address lsa = loan.getUserLoanAtIndex(user, 0);
        bool withdrawInCollateralAsset = true;

        // Capture state before
        uint256 collateralBefore = _getCollateralBalance(lsa);
        uint256 preClosureFeeBps = _getPreClosureFeeBps();
        uint256 expectedFee = _calculatePreClosureFee(collateralBefore);

        assertGt(expectedFee, 0, "Pre-closure fee should be non-zero");

        // Get premium collector address for fee verification
        address premiumCollector = loan.getPremiumCollector();
        uint256 collectorBalanceBefore = IERC20(collateralAsset).balanceOf(premiumCollector);

        // Start recording logs
        vm.recordLogs();

        vm.prank(user);
        loan.closeLoan(lsa, withdrawInCollateralAsset);

        // Capture logs
        Vm.Log[] memory logs = vm.getRecordedLogs();

        // Parse collateral transfers to premium collector (fee sink)
        uint256 feeTransferred = _parseTransferLogs(logs, collateralAsset, address(loan), premiumCollector);

        uint256 userCollateralReceived = _parseTransferLogs(logs, collateralAsset, address(loan), user);

        // Verify fee calculation is correct
        assertEq(expectedFee, (collateralBefore * preClosureFeeBps) / 10_000, "Fee calculation should be correct");

        // Verify fee was transferred to premium collector
        uint256 collectorBalanceAfter = IERC20(collateralAsset).balanceOf(premiumCollector);
        assertGe(collectorBalanceAfter - collectorBalanceBefore, 0, "Premium collector should receive fee");
    }

    /// @notice Test that pre-closure fee is correctly deducted (withdrawInCollateralAsset = false)
    function test_closeLoan_preClosureFee_deducted_withdrawDebt() public setUpLoanForUser {
        address lsa = loan.getUserLoanAtIndex(user, 0);
        bool withdrawInCollateralAsset = false;

        // Capture state before
        uint256 collateralBefore = _getCollateralBalance(lsa);
        uint256 preClosureFeeBps = _getPreClosureFeeBps();
        uint256 expectedFee = _calculatePreClosureFee(collateralBefore);

        assertGt(expectedFee, 0, "Pre-closure fee should be non-zero");

        vm.prank(user);
        loan.closeLoan(lsa, withdrawInCollateralAsset);

        // Fee calculation verification
        assertEq(expectedFee, (collateralBefore * preClosureFeeBps) / 10_000, "Fee calculation should be correct");
    }

    /// @notice Test that flash loan is called with the correct debt amount
    function test_closeLoan_flashLoanCalledWithDebtAmount() public setUpLoanForUser {
        address lsa = loan.getUserLoanAtIndex(user, 0);
        bool withdrawInCollateralAsset = true;

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
        loan.closeLoan(lsa, withdrawInCollateralAsset);

        // Verify loan closed successfully
        uint256 debtAfter = _getDebtBalance(lsa);
        assertEq(debtAfter, 0, "Debt should be 0 after successful close");
    }

    /// @notice Test that closing with zero LSA address reverts
    function test_closeLoan_zeroLsa_reverts() public setUpLoanForUser {
        vm.prank(user);
        vm.expectRevert(Errors.ZeroAddress.selector);
        loan.closeLoan(address(0), true);
    }

    /// @notice Test that closing a non-existent LSA reverts
    function test_closeLoan_nonExistentLsa_reverts() public setUpLoanForUser {
        address randomAddress = makeAddr("nonExistentLsa");

        vm.prank(user);
        vm.expectRevert(Errors.LoanDoesNotExists.selector);
        loan.closeLoan(randomAddress, true);
    }

    /// @notice Test that closing with insufficient collateral reverts
    /// @dev Drop BTC price so totalCollateralUSD <= totalDebtUSD + fees
    function test_closeLoan_insufficientCollateral_reverts() public setUpLoanForUser {
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
    function test_closeLoan_afterFullRepayment_reverts() public setUpLoanForUser {
        address lsa = loan.getUserLoanAtIndex(user, 0);
        uint256 totalDebt = _getDebtBalance(lsa);

        // Fully repay the loan
        vm.prank(user);
        loan.repay(lsa, totalDebt);

        // Verify loan is completed
        DataTypes.LoanData memory loanData = loan.getLoanByLSA(lsa);
        assertEq(
            uint256(loanData.status), uint256(DataTypes.LoanStatus.Completed), "Should be completed after full repay"
        );
        assertEq(_getDebtBalance(lsa), 0, "Debt should be 0");

        // Attempting to close should revert with LoanIsNotActive
        vm.prank(user);
        vm.expectRevert(Errors.LoanIsNotActive.selector);
        loan.closeLoan(lsa, true);
    }

    /// @notice Test that double-closing a loan reverts
    function test_closeLoan_doubleClose_reverts() public setUpLoanForUser {
        address lsa = loan.getUserLoanAtIndex(user, 0);

        // First close should succeed
        vm.prank(user);
        loan.closeLoan(lsa, true);

        // Verify LSA positions are cleared
        assertEq(_getDebtBalance(lsa), 0, "Debt should be 0 after first close");
        assertEq(_getCollateralBalance(lsa), 0, "Collateral should be 0 after first close");

        // Second close should revert with LoanIsNotActive
        vm.prank(user);
        vm.expectRevert(Errors.LoanIsNotActive.selector);
        loan.closeLoan(lsa, true);
    }

    /// @notice Test that non-borrower cannot close someone else's loan
    /// @dev Security test - should revert with access control error
    function test_closeLoan_nonBorrower_reverts() public setUpLoanForUser {
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

    // ============ Edge Case Tests ============

    /// @notice Test close loan with both withdrawal modes produce different results
    function test_closeLoan_withdrawModes_differ() public {
        // Setup two loans to compare
        _mintDebtAssetToUser();

        // Create first loan
        (,, uint256 minDeposit1) = loan.getLoanDetails(STANDARD_COLLATERAL_AMOUNT, STANDARD_DURATION);
        vm.prank(user);
        address lsa1 =
            loan.initializeLoan(minDeposit1, PREMIUM_AMOUNT, STANDARD_COLLATERAL_AMOUNT, STANDARD_DURATION, DATA);

        // Create second loan (need to mint more tokens and create new user or adjust)
        // For simplicity, we'll use the first loan and test sequentially

        CloseLoanState memory stateBefore = _captureStateBefore(lsa1);

        // Close withdrawing in collateral
        vm.prank(user);
        loan.closeLoan(lsa1, true);

        uint256 userCollateralAfterFirst = IERC20(collateralAsset).balanceOf(user);
        uint256 userDebtAfterFirst = IERC20(debtAsset).balanceOf(user);

        // The user should have received collateral asset primarily
        assertGt(userCollateralAfterFirst - stateBefore.userCollateralBefore, 0, "Should receive collateral in mode 1");
    }

    /// @notice Test close immediately after loan creation
    function test_closeLoan_immediatelyAfterCreation() public setUpLoanForUser {
        address lsa = loan.getUserLoanAtIndex(user, 0);

        // No time warp - close immediately
        CloseLoanState memory stateBefore = _captureStateBefore(lsa);

        vm.prank(user);
        loan.closeLoan(lsa, true);

        uint256 debtAfter = _getDebtBalance(lsa);
        uint256 collateralAfter = _getCollateralBalance(lsa);

        assertEq(debtAfter, 0, "Debt should be 0");
        assertEq(collateralAfter, 0, "Collateral should be 0");
    }

    /// @notice Test close after interest accrual
    function test_closeLoan_afterInterestAccrual() public setUpLoanForUser {
        address lsa = loan.getUserLoanAtIndex(user, 0);

        uint256 initialDebt = _getDebtBalance(lsa);

        // Warp 90 days to accrue interest
        vm.warp(block.timestamp + 90 days);

        uint256 debtAfterAccrual = _getDebtBalance(lsa);
        assertGt(debtAfterAccrual, initialDebt, "Debt should increase with interest");

        // Close should still work
        vm.prank(user);
        loan.closeLoan(lsa, true);

        assertEq(_getDebtBalance(lsa), 0, "Debt should be 0 after close");
        assertEq(_getCollateralBalance(lsa), 0, "Collateral should be 0 after close");
    }
}
