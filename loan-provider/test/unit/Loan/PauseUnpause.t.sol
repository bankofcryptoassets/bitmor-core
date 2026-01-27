// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.30;

import {BaseLoanTest} from "./BaseLoan.t.sol";
import {Errors} from "@bitmor/libraries/helpers/Errors.sol";
import {Pausable} from "@openzeppelin/utils/Pausable.sol";

/// @title PauseUnpauseTest
/// @notice Tests for Loan contract pause/unpause functionality
contract PauseUnpauseTest is BaseLoanTest {
    function setUp() public override {
        super.setUp();
    }

    // ============ Pause Tests ============

    function test_pause_success() public {
        // Arrange
        uint64 lpmFastRole = LPM_FAST_ID();
        vm.prank(admin);
        manager.grantRole(lpmFastRole, admin, 0);

        assertFalse(loan.paused(), "Should start unpaused");

        // Act & Assert
        vm.prank(admin);
        loan.pause();

        assertTrue(loan.paused(), "Should be paused");
    }

    function test_pause_withoutRole_reverts() public {
        vm.prank(user);
        vm.expectRevert();
        loan.pause();
    }

    function test_pause_whenAlreadyPaused_reverts() public {
        _pauseContract();

        vm.prank(admin);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        loan.pause();
    }

    // ============ Unpause Tests ============

    function test_unpause_success() public {
        _pauseContract();
        assertTrue(loan.paused(), "Should be paused");

        _unpauseContract();

        assertFalse(loan.paused(), "Should be unpaused");
    }

    function test_unpause_withoutRole_reverts() public {
        _pauseContract();

        vm.prank(user);
        vm.expectRevert();
        loan.unpause();
    }

    function test_unpause_whenNotPaused_reverts() public {
        // Try to unpause without being paused - expect revert in schedule
        bytes memory data = abi.encodeCall(loan.unpause, ());

        // Schedule and execute through AccessManager - expect ExpectedPause
        (, uint32 delay,,) = manager.getAccess(LPM_SLOW_ID(), lpm_slow);
        uint48 when = uint48(block.timestamp + delay);

        vm.startPrank(lpm_slow);
        if (delay > 0) {
            manager.schedule(address(loan), data, when);
            vm.warp(when);
        }
        vm.expectRevert(Pausable.ExpectedPause.selector);
        manager.execute(address(loan), data);
        vm.stopPrank();
    }

    // ============ Paused State Blocks User Functions ============

    function test_userFunctions_revertWhenPaused_tableDriven() public {
        // Setup: create a loan first, then pause
        address lsa = _createStandardLoan();
        _pauseContract();

        // Test initializeLoan reverts
        vm.startPrank(user);
        mockUSDC.approve(address(loan), type(uint256).max);

        (,, uint256 minDeposit) = loan.getLoanDetails(STANDARD_COLLATERAL_AMOUNT, STANDARD_DURATION);

        vm.expectRevert(Pausable.EnforcedPause.selector);
        loan.initializeLoan(
            minDeposit,
            PREMIUM_AMOUNT,
            STANDARD_COLLATERAL_AMOUNT,
            STANDARD_DURATION,
            ""
        );

        // Test repay reverts
        vm.expectRevert(Pausable.EnforcedPause.selector);
        loan.repay(lsa, 1000e6);

        // Test closeLoan reverts
        vm.expectRevert(Pausable.EnforcedPause.selector);
        loan.closeLoan(lsa, true);

        vm.stopPrank();
    }
}
