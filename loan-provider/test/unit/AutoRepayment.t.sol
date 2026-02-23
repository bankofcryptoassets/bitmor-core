// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.30;

import {BaseLoanTest} from "./Loan/BaseLoan.t.sol";
import {DataTypes} from "@bitmor/libraries/types/DataTypes.sol";
import {IERC20} from "@openzeppelin/interfaces/IERC20.sol";
import {AutoRepayment} from "@bitmor/protocol/AutoRepayment.sol";
import {IAutoRepayment} from "@bitmor/interfaces/IAutoRepayment.sol";
import {Errors} from "@bitmor/libraries/helpers/Errors.sol";
import {MockERC20} from "../mock/MockERC20.sol";

/// @title AutoRepaymentTest
/// @author Bitmor Protocol
/// @notice Tests for `AutoRepayment` contract covering creation, execution, cancellation, and access control
contract AutoRepaymentTest is BaseLoanTest {
    // ============ State Variables ============

    AutoRepayment internal autoRepay;
    address internal autoRepaymentExecutor;

    // ============ Setup ============

    function setUp() public override {
        super.setUp();

        autoRepaymentExecutor = makeAddr("autoRepaymentExecutor");

        vm.startPrank(admin);
        // Constructor: AutoRepayment(address _manager, address _loan, address _debtAsset)
        autoRepay = new AutoRepayment(address(manager), address(loan), debtAsset);

        // Configure AutoRepayment roles - grant ARE role and set target selectors
        manager.grantRole(ARE_ID(), autoRepaymentExecutor, 0);
        _setAutoRepaymentTargetSelectors(address(autoRepay));
        vm.stopPrank();
    }

    // ============ Modifiers ============

    /// @notice Modifier to set up auto repayment for user
    modifier setUpAutoRepayment() {
        _setupAutoRepayment();
        _;
    }

    // ============ Tests ============

    /// @notice Tests that user can create auto repayment authorization for their LSA
    /// @dev Covers happy path for createAutoRepayment at lines 66-73
    function test_createAutoRepayment() public setUpLoanForUser {
        uint256 index = 0;
        address lsa = loan.getUserLoanAtIndex(user, index);

        vm.prank(user);
        vm.expectEmit(true, true, false, false);
        emit IAutoRepayment.AutoRepayment__RepaymentCreated(lsa, user);
        autoRepay.createAutoRepayment(lsa);
    }

    /// @notice Tests that createAutoRepayment reverts when lsa is zero address
    /// @dev Covers branch at line 67: `if (lsa == address(0)) revert Errors.ZeroAddress()`
    function test_RevertWhen_CreateAutoRepayment_ZeroAddress() public {
        // Act & Assert
        vm.prank(user);
        vm.expectRevert(Errors.ZeroAddress.selector);
        autoRepay.createAutoRepayment(address(0));
    }

    /// @notice Tests that executor can successfully execute auto repayment
    /// @dev Covers happy path for executeAutoRepayment at lines 87-94, verifies loan duration decreases
    function test_executeAutoRepayment() public setUpAutoRepayment {
        uint256 index = 0;
        address lsa = loan.getUserLoanAtIndex(user, index);

        DataTypes.LoanData memory loanDataBefore = loan.getLoanByLSA(lsa);
        uint256 durationBefore = loanDataBefore.duration;

        vm.prank(autoRepaymentExecutor);
        autoRepay.executeAutoRepayment(lsa, user, loanDataBefore.estimatedMonthlyPayment);

        DataTypes.LoanData memory loanDataAfter = loan.getLoanByLSA(lsa);
        uint256 durationAfter = loanDataAfter.duration;

        assertEq(durationBefore - durationAfter, 1, "Duration should decrease by 1");
    }

    /// @notice Tests that user can cancel auto repayment for their authorized LSA
    /// @dev Covers lines 78-81 of cancelAutoRepayment function
    function test_cancelAutoRepayment() public setUpAutoRepayment {
        // Arrange
        address lsa = loan.getUserLoanAtIndex(user, 0);

        // Verify pre-condition: user is authorized
        assertTrue(autoRepay.isAuthorized(user, lsa), "user should be authorized before cancel");

        // Act
        vm.prank(user);
        vm.expectEmit(true, true, false, false);
        emit IAutoRepayment.AutoRepayment__RepaymentCancelled(lsa, user);
        autoRepay.cancelAutoRepayment(lsa);

        // Assert
        assertFalse(autoRepay.isAuthorized(user, lsa), "user should not be authorized after cancel");
    }

    /// @notice Tests that cancelAutoRepayment reverts when user is not authorized
    /// @dev Covers branch at line 79: `if (!isAuthorized[msg.sender][lsa]) revert Errors.InvalidRepaymentHash()`
    function test_RevertWhen_CancelAutoRepayment_NotAuthorized() public setUpLoanForUser {
        // Arrange
        address lsa = loan.getUserLoanAtIndex(user, 0);

        // Verify pre-condition: user has NOT authorized auto-repayment
        assertFalse(autoRepay.isAuthorized(user, lsa), "user should not be authorized");

        // Act & Assert
        vm.prank(user);
        vm.expectRevert(Errors.InvalidRepaymentHash.selector);
        autoRepay.cancelAutoRepayment(lsa);
    }

    /// @notice Tests that executeAutoRepayment reverts when user has not authorized
    /// @dev Covers branch at line 88: `if (!isAuthorized[user][lsa]) revert Errors.InvalidRepaymentHash()`
    function test_RevertWhen_ExecuteAutoRepayment_NotAuthorized() public setUpLoanForUser {
        // Arrange
        address lsa = loan.getUserLoanAtIndex(user, 0);
        DataTypes.LoanData memory loanData = loan.getLoanByLSA(lsa);

        // Verify pre-condition: user has NOT authorized auto-repayment
        assertFalse(autoRepay.isAuthorized(user, lsa), "user should not be authorized");

        // Act & Assert
        vm.prank(autoRepaymentExecutor);
        vm.expectRevert(Errors.InvalidRepaymentHash.selector);
        autoRepay.executeAutoRepayment(lsa, user, loanData.estimatedMonthlyPayment);
    }

    /// @notice Tests that executeAutoRepayment reverts when called by non-executor
    /// @dev Covers AccessManaged `restricted` modifier on executeAutoRepayment
    function test_RevertWhen_ExecuteAutoRepayment_CallerNotExecutor() public setUpAutoRepayment {
        // Arrange
        address lsa = loan.getUserLoanAtIndex(user, 0);
        DataTypes.LoanData memory loanData = loan.getLoanByLSA(lsa);
        address nonExecutor = makeAddr("nonExecutor");

        // Act & Assert - AccessManaged reverts with AccessManagedUnauthorized
        vm.prank(nonExecutor);
        vm.expectRevert();
        autoRepay.executeAutoRepayment(lsa, user, loanData.estimatedMonthlyPayment);
    }

    /// @notice Tests that executeAutoRepayment emits RepaymentExecuted with correct parameters
    /// @dev Covers event emission at line 94
    function test_executeAutoRepayment_EmitsEvent() public setUpAutoRepayment {
        // Arrange
        address lsa = loan.getUserLoanAtIndex(user, 0);
        DataTypes.LoanData memory loanData = loan.getLoanByLSA(lsa);
        uint256 repayAmount = loanData.estimatedMonthlyPayment;

        // Act & Assert
        vm.prank(autoRepaymentExecutor);
        vm.expectEmit(true, true, false, true);
        emit IAutoRepayment.AutoRepayment__RepaymentExecuted(lsa, user, repayAmount, repayAmount);
        autoRepay.executeAutoRepayment(lsa, user, repayAmount);
    }

    // ============ rescueTokens Tests ============

    /// @notice Tests that executor can rescue stuck USDC from the contract
    function test_rescueTokens_TransfersTokens() public {
        // Arrange - simulate tokens stuck in contract
        uint256 stuckAmount = 1000e6;
        mockUSDC.mint(address(autoRepay), stuckAmount);
        address recipient = makeAddr("recipient");

        uint256 recipientBalanceBefore = IERC20(debtAsset).balanceOf(recipient);

        // Act
        vm.prank(autoRepaymentExecutor);
        autoRepay.rescueTokens(debtAsset, recipient, stuckAmount);

        // Assert
        uint256 recipientBalanceAfter = IERC20(debtAsset).balanceOf(recipient);
        assertEq(recipientBalanceAfter - recipientBalanceBefore, stuckAmount, "recipient should receive stuck tokens");
        assertEq(IERC20(debtAsset).balanceOf(address(autoRepay)), 0, "contract should have zero balance after rescue");
    }

    /// @notice Tests that rescueTokens emits the correct event
    function test_rescueTokens_EmitsEvent() public {
        // Arrange
        uint256 stuckAmount = 500e6;
        mockUSDC.mint(address(autoRepay), stuckAmount);
        address recipient = makeAddr("recipient");

        // Act & Assert
        vm.prank(autoRepaymentExecutor);
        vm.expectEmit(true, true, true, true);
        emit IAutoRepayment.AutoRepayment__TokensRescued(debtAsset, recipient, stuckAmount);
        autoRepay.rescueTokens(debtAsset, recipient, stuckAmount);
    }

    /// @notice Tests that executor can rescue a partial amount, leaving the rest
    function test_rescueTokens_PartialAmount() public {
        // Arrange
        uint256 stuckAmount = 1000e6;
        uint256 rescueAmount = 400e6;
        mockUSDC.mint(address(autoRepay), stuckAmount);
        address recipient = makeAddr("recipient");

        // Act
        vm.prank(autoRepaymentExecutor);
        autoRepay.rescueTokens(debtAsset, recipient, rescueAmount);

        // Assert
        assertEq(IERC20(debtAsset).balanceOf(recipient), rescueAmount, "recipient should receive partial amount");
        assertEq(
            IERC20(debtAsset).balanceOf(address(autoRepay)),
            stuckAmount - rescueAmount,
            "contract should retain remaining balance"
        );
    }

    /// @notice Tests that executor can rescue non-debt tokens (e.g., accidentally sent cbBTC)
    function test_rescueTokens_NonDebtAsset() public {
        // Arrange
        uint256 stuckAmount = 1e8; // 1 BTC
        mockCbBTC.mint(address(autoRepay), stuckAmount);
        address recipient = makeAddr("recipient");

        // Act
        vm.prank(autoRepaymentExecutor);
        autoRepay.rescueTokens(address(mockCbBTC), recipient, stuckAmount);

        // Assert
        assertEq(mockCbBTC.balanceOf(recipient), stuckAmount, "recipient should receive rescued cbBTC");
        assertEq(mockCbBTC.balanceOf(address(autoRepay)), 0, "contract should have zero cbBTC after rescue");
    }

    /// @notice Tests that rescueTokens reverts when token address is zero
    function test_RevertWhen_RescueTokens_ZeroTokenAddress() public {
        // Act & Assert
        vm.prank(autoRepaymentExecutor);
        vm.expectRevert(Errors.ZeroAddress.selector);
        autoRepay.rescueTokens(address(0), makeAddr("recipient"), 1000e6);
    }

    /// @notice Tests that rescueTokens reverts when recipient address is zero
    function test_RevertWhen_RescueTokens_ZeroRecipient() public {
        // Act & Assert
        vm.prank(autoRepaymentExecutor);
        vm.expectRevert(Errors.ZeroAddress.selector);
        autoRepay.rescueTokens(debtAsset, address(0), 1000e6);
    }

    /// @notice Tests that rescueTokens reverts when amount is zero
    function test_RevertWhen_RescueTokens_ZeroAmount() public {
        // Act & Assert
        vm.prank(autoRepaymentExecutor);
        vm.expectRevert(Errors.ZeroAmount.selector);
        autoRepay.rescueTokens(debtAsset, makeAddr("recipient"), 0);
    }

    /// @notice Tests that rescueTokens reverts when called by non-executor
    function test_RevertWhen_RescueTokens_CallerNotAuthorized() public {
        // Arrange
        uint256 stuckAmount = 1000e6;
        mockUSDC.mint(address(autoRepay), stuckAmount);
        address nonExecutor = makeAddr("nonExecutor");

        // Act & Assert - AccessManaged reverts with AccessManagedUnauthorized
        vm.prank(nonExecutor);
        vm.expectRevert();
        autoRepay.rescueTokens(debtAsset, nonExecutor, stuckAmount);
    }

    /// @notice Tests that rescueTokens reverts when contract has insufficient balance
    function test_RevertWhen_RescueTokens_InsufficientBalance() public {
        // Arrange - contract has no tokens
        address recipient = makeAddr("recipient");

        // Act & Assert - ERC20 transfer will revert due to insufficient balance
        vm.prank(autoRepaymentExecutor);
        vm.expectRevert();
        autoRepay.rescueTokens(debtAsset, recipient, 1000e6);
    }

    // ============ Excess Refund Tests ============

    /// @notice Tests that excess repayment funds are refunded directly to the user
    /// @dev Amount must exceed totalDebt to trigger the excess refund branch.
    ///      RepayLogic caps pulls at min(amount, totalDebt), so only amount > totalDebt
    ///      leaves excess in AutoRepayment that needs refunding.
    function test_executeAutoRepayment_RefundsExcessToUser() public setUpAutoRepayment {
        // Arrange
        address lsa = loan.getUserLoanAtIndex(user, 0);

        // Get the actual total debt for this loan
        uint256 totalDebt = _getDebtBalance(lsa);
        // Overpay beyond total debt to trigger the excess refund branch
        uint256 excessAmount = 1000e6;
        uint256 overpayAmount = totalDebt + excessAmount;

        // Ensure user has enough USDC and has approved the autoRepay contract
        _fundUSDC(user, overpayAmount);
        vm.prank(user);
        IERC20(debtAsset).approve(address(autoRepay), overpayAmount);

        uint256 userBalanceBefore = IERC20(debtAsset).balanceOf(user);

        // Act
        vm.prank(autoRepaymentExecutor);
        autoRepay.executeAutoRepayment(lsa, user, overpayAmount);

        // Assert - no tokens stuck in AutoRepayment contract
        assertEq(
            IERC20(debtAsset).balanceOf(address(autoRepay)),
            0,
            "AutoRepayment contract should have zero USDC balance after execution"
        );

        // User should only be debited totalDebt (the excess was refunded)
        uint256 userBalanceAfter = IERC20(debtAsset).balanceOf(user);
        uint256 actualCost = userBalanceBefore - userBalanceAfter;
        assertLe(actualCost, totalDebt, "user should not pay more than totalDebt");
        assertGt(actualCost, 0, "user should pay something");
    }

    /// @notice Tests that ExcessRefunded event is emitted when overpaying beyond totalDebt
    function test_executeAutoRepayment_EmitsExcessRefundedEvent() public setUpAutoRepayment {
        // Arrange
        address lsa = loan.getUserLoanAtIndex(user, 0);
        uint256 totalDebt = _getDebtBalance(lsa);
        uint256 excessAmount = 500e6;
        uint256 overpayAmount = totalDebt + excessAmount;

        _fundUSDC(user, overpayAmount);
        vm.prank(user);
        IERC20(debtAsset).approve(address(autoRepay), overpayAmount);

        // Act & Assert - expect ExcessRefunded event
        vm.prank(autoRepaymentExecutor);
        vm.expectEmit(true, false, false, true);
        emit IAutoRepayment.AutoRepayment__ExcessRefunded(user, excessAmount);
        autoRepay.executeAutoRepayment(lsa, user, overpayAmount);
    }

    /// @notice Tests that Loan approval is cleaned up after executeAutoRepayment
    function test_executeAutoRepayment_CleansUpApproval() public setUpAutoRepayment {
        // Arrange
        address lsa = loan.getUserLoanAtIndex(user, 0);
        DataTypes.LoanData memory loanData = loan.getLoanByLSA(lsa);

        // Act
        vm.prank(autoRepaymentExecutor);
        autoRepay.executeAutoRepayment(lsa, user, loanData.estimatedMonthlyPayment);

        // Assert - approval should be zeroed out
        uint256 allowance = IERC20(debtAsset).allowance(address(autoRepay), address(loan));
        assertEq(allowance, 0, "Loan allowance should be zero after execution");
    }

    // ============ Internal Helper Functions ============

    /// @notice Creates an active loan for `user`, approves USDC spending, and creates auto-repayment authorization
    function _setupAutoRepayment() internal {
        _setUpLoanForUser();
        address lsa = loan.getUserLoanAtIndex(user, 0);

        vm.startPrank(user);
        IERC20(debtAsset).approve(address(autoRepay), USER_USDC_FUNDING);
        autoRepay.createAutoRepayment(lsa);
        vm.stopPrank();
    }
}
