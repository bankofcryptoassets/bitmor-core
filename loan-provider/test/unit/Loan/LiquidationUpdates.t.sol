// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.30;

import {BaseLoanTest} from "./BaseLoan.t.sol";
import {Errors} from "@bitmor/libraries/helpers/Errors.sol";
import {DataTypes} from "@bitmor/libraries/types/DataTypes.sol";
import {IAccessManaged} from "@openzeppelin/access/manager/IAccessManaged.sol";

/// @title LiquidationUpdatesTest
/// @author Bitmor Protocol
/// @notice Tests for `Loan.updateLoanDataForMicroLiquidation`, `updateLoanDataForFullLiquidation`, and `updateInsuranceId`
contract LiquidationUpdatesTest is BaseLoanTest {
    address lsa;
    address noRoleUser;

    function setUp() public override {
        super.setUp();
        lsa = _createStandardLoan();
        noRoleUser = makeAddr("noRoleUser");
    }

    // ============ updateInsuranceId Tests ============

    /// @notice Test successfully updating the insurance ID for a loan
    function test_updateInsuranceId() public {
        uint256 insuranceId = 12345;

        // Grant EXECUTOR role and call
        uint64 executorRole = EXECUTOR_ID();
        vm.prank(admin);
        manager.grantRole(executorRole, admin, 0);

        vm.prank(admin);
        loan.updateInsuranceId(lsa, insuranceId);

        DataTypes.LoanData memory data = loan.getLoanByLSA(lsa);
        assertEq(data.insuranceID, insuranceId, "Insurance ID should be updated");
    }

    /// @notice Test that updating insurance ID reverts for non-existent loan
    function test_updateInsuranceId_RevertWhen_LoanDoesNotExist() public {
        address fakeLsa = makeAddr("fakeLsa");

        uint64 executorRole = EXECUTOR_ID();
        vm.prank(admin);
        manager.grantRole(executorRole, admin, 0);

        vm.prank(admin);
        vm.expectRevert(Errors.LoanDoesNotExists.selector);
        loan.updateInsuranceId(fakeLsa, 123);
    }

    // ============ updateLoanDataForMicroLiquidation Tests ============

    /// @notice Test successfully updating loan data for micro liquidation
    function test_updateLoanDataForMicroLiquidation() public {
        DataTypes.LoanData memory beforeData = loan.getLoanByLSA(lsa);
        uint256 durationBefore = beforeData.duration;

        // Grant LPCM role (note: already granted to mockBitmorPool in setup)
        // Call from the pool
        vm.prank(address(mockBitmorPool));
        loan.updateLoanDataForMicroLiquidation(lsa);

        DataTypes.LoanData memory afterData = loan.getLoanByLSA(lsa);
        assertEq(afterData.duration, durationBefore - 1, "Duration should decrement by 1");
    }

    /// @notice Test micro liquidation when duration is 1 becomes 0
    function test_updateLoanDataForMicroLiquidation_durationOne_becomesZero() public {
        // Create a loan with duration 1 for a different borrower to avoid CREATE2 collision
        address borrower2 = makeAddr("borrower2");
        address lsaDuration1 = _createLoanForBorrower(borrower2, STANDARD_COLLATERAL_AMOUNT, 1, PREMIUM_AMOUNT);

        // Call micro liquidation
        vm.prank(address(mockBitmorPool));
        loan.updateLoanDataForMicroLiquidation(lsaDuration1);

        DataTypes.LoanData memory data = loan.getLoanByLSA(lsaDuration1);
        assertEq(data.duration, 0, "Duration should be 0 after micro liquidation");
    }

    /// @notice Test micro liquidation when duration is already 0 stays at 0
    function test_updateLoanDataForMicroLiquidation_durationZero_staysZero() public {
        // Create a loan with duration 1
        address borrower2 = makeAddr("borrower2");
        address lsaDuration1 = _createLoanForBorrower(borrower2, STANDARD_COLLATERAL_AMOUNT, 1, PREMIUM_AMOUNT);

        // First micro liquidation brings duration to 0
        vm.prank(address(mockBitmorPool));
        loan.updateLoanDataForMicroLiquidation(lsaDuration1);

        DataTypes.LoanData memory data = loan.getLoanByLSA(lsaDuration1);
        assertEq(data.duration, 0, "Duration should be 0");

        // Second micro liquidation on duration=0 - uses zeroFloorSub so stays at 0
        vm.prank(address(mockBitmorPool));
        loan.updateLoanDataForMicroLiquidation(lsaDuration1);

        data = loan.getLoanByLSA(lsaDuration1);
        assertEq(data.duration, 0, "Duration should stay at 0 (zeroFloorSub)");
    }

    // ============ updateLoanDataForFullLiquidation Tests ============

    /// @notice Test successfully updating loan data for full liquidation
    function test_updateLoanDataForFullLiquidation() public {
        // Call from the pool which has LPCM role
        vm.prank(address(mockBitmorPool));
        loan.updateLoanDataForFullLiquidation(lsa);

        DataTypes.LoanData memory data = loan.getLoanByLSA(lsa);
        assertEq(data.duration, 0, "Duration should be 0");
        assertEq(uint8(data.status), uint8(DataTypes.LoanStatus.Liquidated), "Status should be Liquidated");
    }

    /// @notice Test that full liquidation updates the last payment timestamp
    function test_updateLoanDataForFullLiquidation_UpdatesTimestamp() public {
        DataTypes.LoanData memory beforeData = loan.getLoanByLSA(lsa);
        uint256 timestampBefore = beforeData.lastPaymentTimestamp;

        // Warp time forward
        vm.warp(block.timestamp + 30 days);

        // Call from the pool which has LPCM role
        vm.prank(address(mockBitmorPool));
        loan.updateLoanDataForFullLiquidation(lsa);

        DataTypes.LoanData memory afterData = loan.getLoanByLSA(lsa);
        assertGt(afterData.lastPaymentTimestamp, timestampBefore, "Timestamp should be updated");
        assertEq(afterData.lastPaymentTimestamp, block.timestamp, "Timestamp should be current block");
    }

    // ============ Access Control Tests ============

    /// @notice Test that liquidation update functions revert without required role
    function test_liquidationUpdates_RevertWhen_CalledWithoutRole() public {
        // Use noRoleUser which has no roles assigned

        // updateInsuranceId without EXECUTOR role
        vm.prank(noRoleUser);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, noRoleUser));
        loan.updateInsuranceId(lsa, 123);

        // updateLoanDataForMicroLiquidation without LPCM role
        vm.prank(noRoleUser);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, noRoleUser));
        loan.updateLoanDataForMicroLiquidation(lsa);

        // updateLoanDataForFullLiquidation without LPCM role
        vm.prank(noRoleUser);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, noRoleUser));
        loan.updateLoanDataForFullLiquidation(lsa);
    }

    /// @notice Test that liquidation update functions revert with zero address
    function test_liquidationUpdates_RevertWhen_ZeroAddress() public {
        // Call from the pool which has LPCM role
        vm.startPrank(address(mockBitmorPool));

        vm.expectRevert(Errors.ZeroAddress.selector);
        loan.updateLoanDataForMicroLiquidation(address(0));

        vm.expectRevert(Errors.ZeroAddress.selector);
        loan.updateLoanDataForFullLiquidation(address(0));

        vm.stopPrank();
    }
}
