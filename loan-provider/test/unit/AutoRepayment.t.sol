// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.30;

import {BaseLoanTest} from "./Loan/BaseLoan.t.sol";
import {DataTypes} from "@bitmor/libraries/types/DataTypes.sol";
import {IERC20} from "@openzeppelin/interfaces/IERC20.sol";
import {AutoRepayment} from "@bitmor/protocol/AutoRepayment.sol";
import {IAutoRepayment} from "@bitmor/interfaces/IAutoRepayment.sol";
import {Errors} from "@bitmor/libraries/helpers/Errors.sol";

/// @title AutoRepaymentTest
/// @notice Tests for AutoRepayment contract functionality
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

    // ============ Internal Helper Functions ============

    /// @dev Set up auto repayment for user with an active loan
    function _setupAutoRepayment() internal {
        _setUpLoanForUser();
        address lsa = loan.getUserLoanAtIndex(user, 0);

        vm.startPrank(user);
        IERC20(debtAsset).approve(address(autoRepay), USER_USDC_FUNDING);
        autoRepay.createAutoRepayment(lsa);
        vm.stopPrank();
    }
}
