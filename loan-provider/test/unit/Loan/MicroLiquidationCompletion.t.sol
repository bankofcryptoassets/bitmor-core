// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.30;

import {BaseLoanTest} from "./BaseLoan.t.sol";
import {TestConstants as TC} from "../../helpers/TestConstants.sol";
import {DataTypes} from "@bitmor/libraries/types/DataTypes.sol";
import {Errors} from "@bitmor/libraries/helpers/Errors.sol";
import {ILoan} from "@bitmor/interfaces/ILoan.sol";
import {IAccessManaged} from "@openzeppelin/access/manager/IAccessManaged.sol";

/// @title MicroLiquidationCompletionTest
/// @author Bitmor Protocol
/// @notice Tests for `Loan.updateLoanForMicroLiquidationCompletion`
/// @dev Validates that the function correctly completes a loan after the final micro-liquidation,
///      setting `duration` to 0, `status` to `Completed`, updating `lastPaymentTimestamp`,
///      and emitting the `Loan__Completed` event. Also verifies revert conditions for
///      zero address, non-existent loan, and unauthorized caller.
contract MicroLiquidationCompletionTest is BaseLoanTest {
    /// @notice LSA address for the duration-1 loan used across tests
    address internal lsaDuration1;

    /// @notice Separate borrower for the duration-1 loan (avoids CREATE2 collision with default user)
    address internal borrower2;

    function setUp() public override {
        super.setUp();

        // Create a loan with duration=1 for a separate borrower to test completion
        borrower2 = makeAddr("borrower2");
        lsaDuration1 = _createLoanForBorrower(borrower2, STANDARD_COLLATERAL_AMOUNT, 1, PREMIUM_AMOUNT);

        // Register loan in addresses provider so claimRemainingCollateral works
        _updateAddressesProviderBitmorLoan();
    }

    // ============ Happy Path Tests ============

    /// @notice Verify that `updateLoanForMicroLiquidationCompletion` sets loan status to `Completed`
    function test_UpdateLoanForMicroLiquidationCompletion_SetsStatusToCompleted() public {
        // Arrange
        DataTypes.LoanData memory beforeData = loan.getLoanByLSA(lsaDuration1);
        assertEq(
            uint256(beforeData.status), uint256(DataTypes.LoanStatus.Active), "loan should be Active before completion"
        );

        // Act
        vm.prank(address(mockBitmorPool));
        loan.updateLoanForMicroLiquidationCompletion(lsaDuration1);

        // Assert
        DataTypes.LoanData memory afterData = loan.getLoanByLSA(lsaDuration1);
        assertEq(
            uint256(afterData.status),
            uint256(DataTypes.LoanStatus.Completed),
            "loan status should be Completed after micro-liquidation completion"
        );
    }

    /// @notice Verify that `updateLoanForMicroLiquidationCompletion` sets duration to 0
    function test_UpdateLoanForMicroLiquidationCompletion_SetsDurationToZero() public {
        // Arrange
        DataTypes.LoanData memory beforeData = loan.getLoanByLSA(lsaDuration1);
        assertEq(beforeData.duration, 1, "loan duration should be 1 before completion");

        // Act
        vm.prank(address(mockBitmorPool));
        loan.updateLoanForMicroLiquidationCompletion(lsaDuration1);

        // Assert
        DataTypes.LoanData memory afterData = loan.getLoanByLSA(lsaDuration1);
        assertEq(afterData.duration, 0, "loan duration should be 0 after micro-liquidation completion");
    }

    /// @notice Verify that `updateLoanForMicroLiquidationCompletion` updates `lastPaymentTimestamp` to current block
    function test_UpdateLoanForMicroLiquidationCompletion_UpdatesTimestamp() public {
        // Arrange
        DataTypes.LoanData memory beforeData = loan.getLoanByLSA(lsaDuration1);
        uint256 timestampBefore = beforeData.lastPaymentTimestamp;

        // Warp forward to ensure timestamp changes
        vm.warp(block.timestamp + TC.ONE_MONTH);

        // Act
        vm.prank(address(mockBitmorPool));
        loan.updateLoanForMicroLiquidationCompletion(lsaDuration1);

        // Assert
        DataTypes.LoanData memory afterData = loan.getLoanByLSA(lsaDuration1);
        assertGt(afterData.lastPaymentTimestamp, timestampBefore, "lastPaymentTimestamp should be greater than before");
        assertEq(
            afterData.lastPaymentTimestamp, block.timestamp, "lastPaymentTimestamp should equal current block.timestamp"
        );
    }

    /// @notice Verify that `updateLoanForMicroLiquidationCompletion` emits the `Loan__Completed` event
    function test_UpdateLoanForMicroLiquidationCompletion_EmitsLoanCompleted() public {
        // Arrange & Assert: expect the Loan__Completed event with the lsa address
        vm.expectEmit(true, true, true, true);
        emit ILoan.Loan__Completed(lsaDuration1);

        // Act
        vm.prank(address(mockBitmorPool));
        loan.updateLoanForMicroLiquidationCompletion(lsaDuration1);
    }

    // ============ Revert Tests ============

    /// @notice Verify that `updateLoanForMicroLiquidationCompletion` reverts with zero address
    function test_UpdateLoanForMicroLiquidationCompletion_RevertWhen_ZeroAddress() public {
        vm.prank(address(mockBitmorPool));
        vm.expectRevert(Errors.ZeroAddress.selector);
        loan.updateLoanForMicroLiquidationCompletion(address(0));
    }

    /// @notice Verify that `updateLoanForMicroLiquidationCompletion` reverts for a non-existent loan
    function test_UpdateLoanForMicroLiquidationCompletion_RevertWhen_LoanDoesNotExist() public {
        address fakeLsa = makeAddr("fakeLsa");

        vm.prank(address(mockBitmorPool));
        vm.expectRevert(Errors.LoanDoesNotExists.selector);
        loan.updateLoanForMicroLiquidationCompletion(fakeLsa);
    }

    /// @notice Verify that `updateLoanForMicroLiquidationCompletion` reverts when called by unauthorized address
    function test_UpdateLoanForMicroLiquidationCompletion_RevertWhen_UnauthorizedCaller() public {
        address noRoleUser = makeAddr("noRoleUser");

        vm.prank(noRoleUser);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, noRoleUser));
        loan.updateLoanForMicroLiquidationCompletion(lsaDuration1);
    }
}
