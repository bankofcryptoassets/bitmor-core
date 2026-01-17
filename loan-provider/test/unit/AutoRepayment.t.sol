// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.30;

import {BaseLoanTest} from "./Loan/BaseLoan.t.sol";
import {DataTypes} from "@bitmor/libraries/types/DataTypes.sol";
import {IERC20} from "@bitmor/dependencies/openzeppelin/IERC20.sol";
import {AutoRepayment} from "@bitmor/protocol/AutoRepayment.sol";
import {IAutoRepayment} from "@bitmor/interfaces/IAutoRepayment.sol";

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

        vm.prank(owner);
        autoRepay = new AutoRepayment(address(loan), debtAsset, autoRepaymentExecutor);
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
