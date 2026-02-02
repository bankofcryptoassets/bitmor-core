// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {BaseTestForBTCVault} from "../BaseTestForBTCVault.t.sol";
import {BTCVault} from "@btcVault/BTCVault.sol";
import {MockTokenizedStrategy} from "../../../mock/MockTokenizedStrategy.sol";
import {MockYieldSource} from "../../../mock/MockYieldSource.sol";
import {Errors} from "@bitmor/libraries/helpers/Errors.sol";

/// @title EmergencyOpsTest
/// @notice Tests for BTCVault emergency operations and pause functionality
/// @dev Hunts for incomplete emergency withdrawals, pause bypass, state corruption
contract EmergencyOpsTest is BaseTestForBTCVault {
    // ============ Additional Strategies ============
    MockTokenizedStrategy strategy2;
    MockYieldSource yieldSource2;

    // ============ Constants ============
    uint256 constant EMERGENCY_STRATEGY_CAP = 10000e6;
    uint256 constant EMERGENCY_DEPOSIT_AMOUNT = 5000e6;

    // ============ Setup ============

    function setUp() public override {
        super.setUp();

        yieldSource2 = new MockYieldSource();
        strategy2 = new MockTokenizedStrategy(address(yieldSource2), address(vault));

        // Add emergencyWithdrawFunds selector to BVM_FAST role
        // (missing from BaseTestForBTCVault._setTargetSelectorsLocal)
        bytes4[] memory emergencySelector = new bytes4[](1);
        emergencySelector[0] = BTCVault.emergencyWithdrawFunds.selector;
        manager.setTargetFunctionRole(address(vault), emergencySelector, BVM_FAST_ID());
    }

    /// @notice Helper to add strategy via proper access control
    function _addStrategy(address strat, uint256 cap) internal {
        _scheduleAndExecuteLocal(bvc, BVC_ID(), abi.encodeCall(BTCVault.addStrategy, (strat, cap)));
    }

    /// @notice Helper to deposit as user with proper approval
    function _depositAsUser(uint256 amount) internal returns (uint256 shares) {
        vm.startPrank(user);
        mockUSDC.approve(address(vault), amount);
        shares = vault.deposit(amount, user);
        vm.stopPrank();
    }

    /// @notice Helper to pause the vault
    function _pause() internal {
        _scheduleAndExecuteLocal(bvm_fast, BVM_FAST_ID(), abi.encodeCall(BTCVault.pause, ()));
    }

    /// @notice Helper to unpause the vault
    function _unpause() internal {
        _scheduleAndExecuteLocal(bvm_slow, BVM_SLOW_ID(), abi.encodeCall(BTCVault.unpause, ()));
    }

    // ============ Emergency Withdraw Tests ============

    /// @notice Emergency withdraw should extract all funds from all strategies
    function test_emergencyWithdrawFunds_WithdrawsFromAllStrategies() public {
        // Arrange
        _addStrategy(address(strategy), EMERGENCY_STRATEGY_CAP);
        _addStrategy(address(strategy2), EMERGENCY_STRATEGY_CAP);

        _depositAsUser(EMERGENCY_STRATEGY_CAP * 2); // Fill both strategies

        uint256 inStrategy1Before = vault.getAssetInStrategy(address(strategy));
        uint256 inStrategy2Before = vault.getAssetInStrategy(address(strategy2));
        assertGt(inStrategy1Before, 0, "strategy1 should have funds before emergency");
        assertGt(inStrategy2Before, 0, "strategy2 should have funds before emergency");

        // Act - Emergency withdraw
        _scheduleAndExecuteLocal(bvm_fast, BVM_FAST_ID(), abi.encodeCall(BTCVault.emergencyWithdrawFunds, ()));

        // Assert
        uint256 inStrategy1After = vault.getAssetInStrategy(address(strategy));
        uint256 inStrategy2After = vault.getAssetInStrategy(address(strategy2));

        assertEq(inStrategy1After, 0, "strategy1 should be empty after emergency withdraw");
        assertEq(inStrategy2After, 0, "strategy2 should be empty after emergency withdraw");
    }

    /// @notice Emergency withdraw with single strategy
    function test_emergencyWithdrawFunds_SingleStrategy_WithdrawsAll() public {
        // Arrange
        _addStrategy(address(strategy), EMERGENCY_STRATEGY_CAP);
        _depositAsUser(EMERGENCY_DEPOSIT_AMOUNT);

        uint256 strategyBalanceBefore = vault.getAssetInStrategy(address(strategy));
        assertGt(strategyBalanceBefore, 0, "strategy should have funds before emergency");

        // Act
        _scheduleAndExecuteLocal(bvm_fast, BVM_FAST_ID(), abi.encodeCall(BTCVault.emergencyWithdrawFunds, ()));

        // Assert
        uint256 strategyBalanceAfter = vault.getAssetInStrategy(address(strategy));
        assertEq(strategyBalanceAfter, 0, "strategy should be empty after emergency");
    }

    /// @notice Emergency withdraw with no strategies should not revert
    function test_emergencyWithdrawFunds_NoStrategies_DoesNotRevert() public {
        // Arrange - No strategies added

        // Act & Assert - should succeed without doing anything
        _scheduleAndExecuteLocal(bvm_fast, BVM_FAST_ID(), abi.encodeCall(BTCVault.emergencyWithdrawFunds, ()));

        // Verify vault state is still valid
        assertEq(vault.totalAssets(), 0, "totalAssets should be 0 with no strategies");
    }

    /// @notice After emergency withdraw, totalAssets should be zero
    function test_emergencyWithdrawFunds_TotalAssetsBecomesZero() public {
        // Arrange
        _addStrategy(address(strategy), EMERGENCY_STRATEGY_CAP);
        _depositAsUser(EMERGENCY_DEPOSIT_AMOUNT);

        uint256 totalBefore = vault.totalAssets();
        assertGt(totalBefore, 0, "should have assets before emergency");

        // Act
        _scheduleAndExecuteLocal(bvm_fast, BVM_FAST_ID(), abi.encodeCall(BTCVault.emergencyWithdrawFunds, ()));

        // Assert
        uint256 totalAfter = vault.totalAssets();
        assertEq(totalAfter, 0, "totalAssets should be 0 after emergency withdraw");
    }

    // ============ Pause Tests ============

    /// @notice Pause should block deposits
    /// @dev BUG DISCOVERED: BTCVault.deposit() does NOT have whenNotPaused modifier
    ///      This test documents the ACTUAL behavior - deposit works when paused
    ///      Expected: Should revert with EnforcedPause
    ///      Actual: Does NOT revert, deposit proceeds
    ///      Location: BTCVault.sol line 457 - missing whenNotPaused modifier
    function test_pause_DepositWorksWhenPaused_BUG() public {
        // Arrange
        _addStrategy(address(strategy), EMERGENCY_STRATEGY_CAP);
        _pause();

        // Act - BUG: This should revert but doesn't
        vm.startPrank(user);
        mockUSDC.approve(address(vault), EMERGENCY_DEPOSIT_AMOUNT);
        uint256 shares = vault.deposit(EMERGENCY_DEPOSIT_AMOUNT, user);
        vm.stopPrank();

        // Assert - documenting actual (buggy) behavior
        assertGt(shares, 0, "BUG: deposit works when paused, should be blocked");
    }

    /// @notice Pause should block mint
    /// @dev BUG DISCOVERED: BTCVault.mint() does NOT have whenNotPaused modifier
    ///      This test documents the ACTUAL behavior - mint works when paused
    ///      Expected: Should revert with EnforcedPause
    ///      Actual: Does NOT revert, mint proceeds
    ///      Location: BTCVault.sol line 468 - missing whenNotPaused modifier
    ///      Note: mint also requires BVD role, which is not granted by default.
    ///      Setting up mint role to test the pause behavior.
    function test_pause_MintWorksWhenPaused_BUG() public {
        // Arrange - add mint to BVD selectors so user can mint
        bytes4[] memory mintSelector = new bytes4[](1);
        mintSelector[0] = BTCVault.mint.selector;
        manager.setTargetFunctionRole(address(vault), mintSelector, BVD_ID());

        _addStrategy(address(strategy), EMERGENCY_STRATEGY_CAP);
        _pause();

        // Act - BUG: This should revert but doesn't
        vm.startPrank(user);
        mockUSDC.approve(address(vault), EMERGENCY_DEPOSIT_AMOUNT);
        uint256 assets = vault.mint(TEST_AMOUNT, user);
        vm.stopPrank();

        // Assert - documenting actual (buggy) behavior
        assertGt(assets, 0, "BUG: mint works when paused, should be blocked");
    }

    /// @notice Withdraw should still work when paused (users can exit)
    function test_pause_AllowsWithdraw_UsersCanExit() public {
        // Arrange
        _addStrategy(address(strategy), EMERGENCY_STRATEGY_CAP);
        _depositAsUser(EMERGENCY_DEPOSIT_AMOUNT);

        uint256 userSharesBefore = vault.balanceOf(user);
        assertGt(userSharesBefore, 0, "user should have shares");

        _pause();

        uint256 maxWithdrawable = vault.maxWithdraw(user);
        assertGt(maxWithdrawable, 0, "should have withdrawable amount");

        // Act - Withdraw should work even when paused
        vm.prank(user);
        uint256 sharesBurned = vault.withdraw(maxWithdrawable / 2, user, user);

        // Assert
        assertGt(sharesBurned, 0, "withdraw should burn shares when paused");
        assertLt(vault.balanceOf(user), userSharesBefore, "user shares should decrease");
    }

    /// @notice Redeem should still work when paused (users can exit)
    function test_pause_AllowsRedeem_UsersCanExit() public {
        // Arrange
        _addStrategy(address(strategy), EMERGENCY_STRATEGY_CAP);
        uint256 shares = _depositAsUser(EMERGENCY_DEPOSIT_AMOUNT);

        _pause();

        uint256 userBalanceBefore = mockUSDC.balanceOf(user);

        // Act - Redeem should work even when paused
        vm.prank(user);
        uint256 assetsReceived = vault.redeem(shares / 2, user, user);

        // Assert
        assertGt(assetsReceived, 0, "redeem should return assets when paused");
        assertGt(mockUSDC.balanceOf(user), userBalanceBefore, "user USDC balance should increase");
    }

    /// @notice Unpause should restore deposit capability
    function test_unpause_RestoresDepositCapability() public {
        // Arrange
        _addStrategy(address(strategy), EMERGENCY_STRATEGY_CAP);

        _pause();
        _unpause();

        // Act - Should be able to deposit again
        uint256 shares = _depositAsUser(EMERGENCY_DEPOSIT_AMOUNT);

        // Assert
        assertGt(shares, 0, "should have minted shares after unpause");
        assertGt(vault.totalAssets(), 0, "vault should have assets after deposit");
    }

    /// @notice Double pause should revert with EnforcedPause
    function test_pause_revertWhen_AlreadyPaused() public {
        // Arrange
        _pause();

        // Act & Assert - Second pause should fail
        // Note: Using direct call via prank since _scheduleAndExecuteLocal doesn't propagate reverts
        vm.prank(bvm_fast);
        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        manager.execute(address(vault), abi.encodeCall(BTCVault.pause, ()));
    }

    /// @notice Unpause when not paused should revert with ExpectedPause
    function test_unpause_revertWhen_NotPaused() public {
        // Act & Assert
        // Note: Need to skip scheduling and go straight to execute for immediate roles
        // For BVM_SLOW with delay, we need to check if the operation itself would revert
        (, uint32 delay,,) = manager.getAccess(BVM_SLOW_ID(), bvm_slow);
        uint48 when = uint48(block.timestamp + delay);

        vm.startPrank(bvm_slow);
        if (delay > 0) {
            manager.schedule(address(vault), abi.encodeCall(BTCVault.unpause, ()), when);
            vm.warp(when);
        }
        vm.expectRevert(abi.encodeWithSignature("ExpectedPause()"));
        manager.execute(address(vault), abi.encodeCall(BTCVault.unpause, ()));
        vm.stopPrank();
    }
}
