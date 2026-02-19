// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.30;

import {BaseLoanTest} from "./BaseLoan.t.sol";
import {Errors} from "@bitmor/libraries/helpers/Errors.sol";
import {Pausable} from "@openzeppelin/utils/Pausable.sol";
import {IAccessManaged} from "@openzeppelin/access/manager/IAccessManaged.sol";
import {DataTypes} from "@bitmor/libraries/types/DataTypes.sol";

/// @title PauseUnpauseTest
/// @author Bitmor Protocol
/// @notice Tests for Loan contract pause/unpause lifecycle including role enforcement and operation blocking
contract PauseUnpauseTest is BaseLoanTest {
    function setUp() public override {
        super.setUp();
    }

    // ============ Pause Tests ============

    /// @notice Test successfully pausing the contract
    function test_pause() public {
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

    /// @notice Test that pause reverts when caller lacks required role
    function test_pause_RevertWhen_CalledWithoutRole() public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, user));
        loan.pause();
    }

    /// @notice Test that pause reverts when contract is already paused
    function test_pause_RevertWhen_AlreadyPaused() public {
        _pauseContract();

        vm.prank(admin);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        loan.pause();
    }

    /// @notice Test that pause emits the Paused event
    function test_pause_EmitsPausedEvent() public {
        uint64 lpmFastRole = LPM_FAST_ID();
        vm.prank(admin);
        manager.grantRole(lpmFastRole, admin, 0);

        vm.expectEmit(true, false, false, false);
        emit Pausable.Paused(admin);

        vm.prank(admin);
        loan.pause();
    }

    /// @notice Test that pause reverts when caller has wrong role (LPM_SLOW instead of LPM_FAST)
    function test_pause_RevertWhen_CalledWithWrongRole() public {
        // Grant LPM_SLOW (delayed role) instead of LPM_FAST (immediate pause role)
        // lpm_slow already has LPM_SLOW role from setup, but not LPM_FAST
        // LPM_SLOW holder cannot call pause directly (pause requires LPM_FAST)
        vm.prank(lpm_slow);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, lpm_slow));
        loan.pause();
    }

    // ============ Unpause Tests ============

    /// @notice Test successfully unpausing the contract
    function test_unpause() public {
        _pauseContract();
        assertTrue(loan.paused(), "Should be paused");

        _unpauseContract();

        assertFalse(loan.paused(), "Should be unpaused");
    }

    /// @notice Test that unpause reverts when caller lacks required role
    function test_unpause_RevertWhen_CalledWithoutRole() public {
        _pauseContract();

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, user));
        loan.unpause();
    }

    /// @notice Test that unpause reverts when contract is not paused
    function test_unpause_RevertWhen_NotPaused() public {
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

    /// @notice Test that unpause emits the Unpaused event
    function test_unpause_EmitsUnpausedEvent() public {
        _pauseContract();

        bytes memory data = abi.encodeCall(loan.unpause, ());
        (, uint32 delay,,) = manager.getAccess(LPM_SLOW_ID(), lpm_slow);
        uint48 when = uint48(block.timestamp + delay);

        vm.startPrank(lpm_slow);
        if (delay > 0) {
            manager.schedule(address(loan), data, when);
            vm.warp(when);
        }

        // The event is emitted by the Loan contract, but called via AccessManager.execute
        // The account in Unpaused event will be the AccessManager, not lpm_slow
        vm.expectEmit(true, false, false, false);
        emit Pausable.Unpaused(address(manager));

        manager.execute(address(loan), data);
        vm.stopPrank();
    }

    // ============ Paused State Blocks User Functions ============

    /// @notice Test that user functions revert when contract is paused
    function test_userFunctions_revertWhenPaused_tableDriven() public {
        // Setup: create a loan first, then pause
        address lsa = _createStandardLoan();
        _pauseContract();

        // Test initializeLoan reverts
        vm.startPrank(user);
        mockUSDC.approve(address(loan), type(uint256).max);

        (,, uint256 minDeposit) = loan.getLoanDetails(STANDARD_COLLATERAL_AMOUNT, STANDARD_DURATION);

        vm.expectRevert(Pausable.EnforcedPause.selector);
        loan.initializeLoan(minDeposit, PREMIUM_AMOUNT, STANDARD_COLLATERAL_AMOUNT, STANDARD_DURATION, "");

        // Test repay reverts
        vm.expectRevert(Pausable.EnforcedPause.selector);
        loan.repay(lsa, 1000e6);

        // Test closeLoan reverts
        vm.expectRevert(Pausable.EnforcedPause.selector);
        loan.closeLoan(lsa, true);

        vm.stopPrank();
    }

    // ============ Lifecycle Tests ============

    /// @notice Test that operations are blocked when paused and restored when unpaused
    function test_pauseUnpause_OperationsBlockedThenRestored() public {
        // 1. Create a loan while unpaused
        address lsa = _createStandardLoan();
        assertFalse(loan.paused(), "Should start unpaused");

        // 2. Pause the contract
        _pauseContract();
        assertTrue(loan.paused(), "Should be paused");

        // 3. Verify repay is blocked
        vm.prank(user);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        loan.repay(lsa, 1000e6);

        // 4. Unpause
        _unpauseContract();
        assertFalse(loan.paused(), "Should be unpaused");

        // 5. Verify repay works again (warp time to next payment period first)
        DataTypes.LoanData memory data = loan.getLoanByLSA(lsa);
        vm.warp(block.timestamp + 30 days);

        // Fund user for repayment and approve
        _fundUSDC(user, data.estimatedMonthlyPayment);
        vm.prank(user);
        mockUSDC.approve(address(loan), type(uint256).max);

        // This should succeed (not revert with EnforcedPause)
        vm.prank(user);
        loan.repay(lsa, data.estimatedMonthlyPayment);

        // Verify repayment was processed (duration decreased)
        DataTypes.LoanData memory afterData = loan.getLoanByLSA(lsa);
        assertEq(afterData.duration, data.duration - 1, "Duration should decrease after repayment");
    }
}
