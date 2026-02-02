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

    // ============ Internal Helper Functions ============

    /// @dev Set up auto repayment for user with an active loan
    function _setupAutoRepayment() internal {
        _setUpLoanForUser();
        address lsa = loan.getUserLoanAtIndex(user, 0);

        vm.startPrank(user);
        IERC20(debtAsset).approve(address(autoRepay), DEBT_ASSET_TO_MINT_TO_USER);
        autoRepay.createAutoRepayment(lsa);
        vm.stopPrank();
    }
}
