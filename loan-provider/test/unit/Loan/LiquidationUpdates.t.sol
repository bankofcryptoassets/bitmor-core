// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.30;

import {BaseLoanTest} from "./BaseLoan.t.sol";
import {Errors} from "@bitmor/libraries/helpers/Errors.sol";
import {DataTypes} from "@bitmor/libraries/types/DataTypes.sol";

/// @title LiquidationUpdatesTest
/// @notice Tests for Loan contract liquidation update functions
contract LiquidationUpdatesTest is BaseLoanTest {
    address lsa;
    address noRoleUser;

    function setUp() public override {
        super.setUp();
        lsa = _createStandardLoan();
        noRoleUser = makeAddr("noRoleUser");
    }

    // ============ updateInsuranceId Tests ============

    function test_updateInsuranceId_success() public {
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

    function test_updateInsuranceId_loanDoesNotExist_reverts() public {
        address fakeLsa = makeAddr("fakeLsa");

        uint64 executorRole = EXECUTOR_ID();
        vm.prank(admin);
        manager.grantRole(executorRole, admin, 0);

        vm.prank(admin);
        vm.expectRevert(Errors.LoanDoesNotExists.selector);
        loan.updateInsuranceId(fakeLsa, 123);
    }

    // ============ updateLoanDataForMicroLiquidation Tests ============

    function test_updateLoanDataForMicroLiquidation_success() public {
        DataTypes.LoanData memory beforeData = loan.getLoanByLSA(lsa);
        uint256 durationBefore = beforeData.duration;

        // Grant LPCM role (note: already granted to mockBitmorPool in setup)
        // Call from the pool
        vm.prank(address(mockBitmorPool));
        loan.updateLoanDataForMicroLiquidation(lsa);

        DataTypes.LoanData memory afterData = loan.getLoanByLSA(lsa);
        assertEq(afterData.duration, durationBefore - 1, "Duration should decrement by 1");
    }

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

    // ============ updateLoanDataForFullLiquidation Tests ============

    function test_updateLoanDataForFullLiquidation_success() public {
        // Call from the pool which has LPCM role
        vm.prank(address(mockBitmorPool));
        loan.updateLoanDataForFullLiquidation(lsa);

        DataTypes.LoanData memory data = loan.getLoanByLSA(lsa);
        assertEq(data.duration, 0, "Duration should be 0");
        assertEq(uint8(data.status), uint8(DataTypes.LoanStatus.Liquidated), "Status should be Liquidated");
    }

    // ============ Access Control Tests ============

    function test_liquidationUpdates_withoutRole_reverts_tableDriven() public {
        // Use noRoleUser which has no roles assigned

        // updateInsuranceId without EXECUTOR role
        vm.prank(noRoleUser);
        vm.expectRevert();
        loan.updateInsuranceId(lsa, 123);

        // updateLoanDataForMicroLiquidation without LPCM role
        vm.prank(noRoleUser);
        vm.expectRevert();
        loan.updateLoanDataForMicroLiquidation(lsa);

        // updateLoanDataForFullLiquidation without LPCM role
        vm.prank(noRoleUser);
        vm.expectRevert();
        loan.updateLoanDataForFullLiquidation(lsa);
    }

    function test_liquidationUpdates_zeroAddress_reverts_tableDriven() public {
        // Call from the pool which has LPCM role
        vm.startPrank(address(mockBitmorPool));

        vm.expectRevert(Errors.ZeroAddress.selector);
        loan.updateLoanDataForMicroLiquidation(address(0));

        vm.expectRevert(Errors.ZeroAddress.selector);
        loan.updateLoanDataForFullLiquidation(address(0));

        vm.stopPrank();
    }
}
