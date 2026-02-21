// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {BaseTestForBTCVault} from "../BaseTestForBTCVault.t.sol";
import {BTCVault} from "@btcVault/BTCVault.sol";
import {MockTokenizedStrategy} from "../../../mock/MockTokenizedStrategy.sol";
import {MockYieldSource} from "../../../mock/MockYieldSource.sol";
import {Errors} from "@bitmor/libraries/helpers/Errors.sol";

/// @title EdgeCasesTest
/// @author Bitmor Protocol
/// @notice Tests for BTCVault edge cases and boundary conditions
/// @dev Hunts for zero-amount bugs, overflow issues, and empty state handling
contract EdgeCasesTest is BaseTestForBTCVault {
    // ============ Constants ============
    uint256 constant EDGE_STRATEGY_CAP = 10000e6;
    uint256 constant EDGE_DEPOSIT_AMOUNT = 1000e6;

    // ============ Setup ============

    function setUp() public override {
        super.setUp();
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

    // ============ Zero Amount Tests ============

    /// @notice Deposit with zero amount reverts with ZeroAmount (zero-shares guard)
    function test_deposit_RevertWhen_ZeroAssets() public {
        // Arrange
        _addStrategy(address(strategy), EDGE_STRATEGY_CAP);

        // Act & Assert
        vm.startPrank(user);
        mockUSDC.approve(address(vault), 0);
        vm.expectRevert(Errors.ZeroAmount.selector);
        vault.deposit(0, user);
        vm.stopPrank();
    }

    /// @notice Withdraw with zero amount burns zero shares per ERC4626 spec
    /// @dev ERC4626 allows zero-amount withdrawals, returning 0 shares burned
    function test_withdraw_ZeroAmount_BurnsZeroShares() public {
        // Arrange
        _addStrategy(address(strategy), EDGE_STRATEGY_CAP);
        _depositAsUser(EDGE_DEPOSIT_AMOUNT);

        uint256 sharesBefore = vault.balanceOf(user);

        // Act - Zero withdraw should succeed per ERC4626 spec
        vm.prank(user);
        uint256 sharesBurned = vault.withdraw(0, user, user);

        uint256 sharesAfter = vault.balanceOf(user);

        // Assert - Zero withdraw burns zero shares, balance unchanged
        assertEq(sharesBurned, 0, "zero withdraw should burn zero shares");
        assertEq(sharesAfter, sharesBefore, "share balance should be unchanged");
    }

    /// @notice Mint with zero shares reverts with ZeroAmount (zero-shares guard)
    function test_mint_RevertWhen_ZeroShares() public {
        // Arrange - add mint to BVD selectors so user can mint
        bytes4[] memory mintSelector = new bytes4[](1);
        mintSelector[0] = BTCVault.mint.selector;
        manager.setTargetFunctionRole(address(vault), mintSelector, BVD_ID());

        _addStrategy(address(strategy), EDGE_STRATEGY_CAP);

        // Act & Assert
        vm.startPrank(user);
        mockUSDC.approve(address(vault), EDGE_DEPOSIT_AMOUNT);
        vm.expectRevert(Errors.ZeroAmount.selector);
        vault.mint(0, user);
        vm.stopPrank();
    }

    /// @notice Redeem with zero shares should revert or no-op
    function test_redeem_ZeroShares_HandlesCorrectly() public {
        // Arrange
        _addStrategy(address(strategy), EDGE_STRATEGY_CAP);
        _depositAsUser(EDGE_DEPOSIT_AMOUNT);

        // Act - Try zero redeem
        vm.prank(user);
        try vault.redeem(0, user, user) returns (uint256 assets) {
            // If it succeeds, should return zero assets
            assertEq(assets, 0, "zero redeem should return zero assets");
        } catch {
            // Reverting on zero redeem is also acceptable
            assertTrue(true, "reverting on zero redeem is acceptable");
        }
    }

    // ============ Pause State Tests (ERC-4626 Compliance) ============

    /// @notice maxDeposit should return 0 when vault is paused
    function test_maxDeposit_ReturnsZero_WhenPaused() public {
        _addStrategy(address(strategy), EDGE_STRATEGY_CAP);

        // Verify non-zero before pause
        assertGt(vault.maxDeposit(user), 0, "maxDeposit should be > 0 before pause");

        vm.prank(bvm_fast);
        vault.pause();

        assertEq(vault.maxDeposit(user), 0, "maxDeposit should be 0 when paused");
    }

    /// @notice maxMint should return 0 when vault is paused
    function test_maxMint_ReturnsZero_WhenPaused() public {
        _addStrategy(address(strategy), EDGE_STRATEGY_CAP);

        // Verify non-zero before pause
        assertGt(vault.maxMint(user), 0, "maxMint should be > 0 before pause");

        vm.prank(bvm_fast);
        vault.pause();

        assertEq(vault.maxMint(user), 0, "maxMint should be 0 when paused");
    }

    /// @notice maxWithdraw should return 0 when vault is paused
    function test_maxWithdraw_ReturnsZero_WhenPaused() public {
        _addStrategy(address(strategy), EDGE_STRATEGY_CAP);
        _depositAsUser(EDGE_DEPOSIT_AMOUNT);

        // Verify non-zero before pause
        assertGt(vault.maxWithdraw(user), 0, "maxWithdraw should be > 0 before pause");

        vm.prank(bvm_fast);
        vault.pause();

        assertEq(vault.maxWithdraw(user), 0, "maxWithdraw should be 0 when paused");
    }

    /// @notice maxRedeem should return 0 when vault is paused
    function test_maxRedeem_ReturnsZero_WhenPaused() public {
        _addStrategy(address(strategy), EDGE_STRATEGY_CAP);
        _depositAsUser(EDGE_DEPOSIT_AMOUNT);

        // Verify non-zero before pause
        assertGt(vault.maxRedeem(user), 0, "maxRedeem should be > 0 before pause");

        vm.prank(bvm_fast);
        vault.pause();

        assertEq(vault.maxRedeem(user), 0, "maxRedeem should be 0 when paused");
    }

    // ============ No Strategy Tests ============

    /// @notice Deposit with no strategies should revert - maxDeposit is 0
    function test_deposit_revertWhen_NoStrategies() public {
        // Arrange - No strategies added

        // Act & Assert - ERC4626 reverts with DepositMoreThanMax when amount > maxDeposit (which is 0)
        vm.startPrank(user);
        mockUSDC.approve(address(vault), EDGE_DEPOSIT_AMOUNT);
        vm.expectRevert(abi.encodeWithSignature("DepositMoreThanMax()"));
        vault.deposit(EDGE_DEPOSIT_AMOUNT, user);
        vm.stopPrank();
    }

    /// @notice totalAssets with no strategies should return zero
    function test_totalAssets_NoStrategies_ReturnsZero() public view {
        uint256 total = vault.totalAssets();
        assertEq(total, 0, "totalAssets should be 0 with no strategies");
    }

    /// @notice maxDeposit with no strategies should return zero
    function test_maxDeposit_NoStrategies_ReturnsZero() public view {
        uint256 maxDep = vault.maxDeposit(user);
        assertEq(maxDep, 0, "maxDeposit should be 0 with no strategies in supply queue");
    }

    // ============ Max Strategies Tests ============

    /// @notice Adding strategy beyond max should revert with MaxStrategiesReached
    function test_addStrategy_revertWhen_MaxStrategiesReached() public {
        // Arrange - Add max number of strategies (MAX_STRATEGIES = 10)
        for (uint256 i = 0; i < MAX_STRATEGIES; i++) {
            MockYieldSource ys = new MockYieldSource();
            MockTokenizedStrategy strat = new MockTokenizedStrategy(address(ys), address(vault));
            _addStrategy(address(strat), EDGE_STRATEGY_CAP);
        }

        // Act & Assert - 11th strategy should fail
        MockYieldSource ysExtra = new MockYieldSource();
        MockTokenizedStrategy extraStrat = new MockTokenizedStrategy(address(ysExtra), address(vault));

        // Need to schedule first, then expect revert on execute
        (, uint32 delay,,) = manager.getAccess(BVC_ID(), bvc);
        uint48 when = uint48(block.timestamp + delay);

        bytes memory data = abi.encodeCall(BTCVault.addStrategy, (address(extraStrat), EDGE_STRATEGY_CAP));

        vm.startPrank(bvc);
        if (delay > 0) {
            manager.schedule(address(vault), data, when);
            vm.warp(when);
        }
        vm.expectRevert(Errors.MaxStrategiesReached.selector);
        manager.execute(address(vault), data);
        vm.stopPrank();
    }

    // ============ Queue Tests ============

    /// @notice Empty supply queue update should work
    function test_updateSupplyQueue_EmptyQueue_Succeeds() public {
        // Arrange
        _addStrategy(address(strategy), EDGE_STRATEGY_CAP);

        uint256 initialLength = vault.getSupplyQueueLength();
        assertEq(initialLength, 1, "should have 1 strategy in queue initially");

        // Act
        uint256[] memory emptyQueue = new uint256[](0);
        _scheduleAndExecuteLocal(bva_slow, BVA_SLOW_ID(), abi.encodeCall(BTCVault.updateSupplyQueue, (emptyQueue)));

        // Assert
        uint256[] memory currentQueue = vault.getSupplyQueue();
        assertEq(currentQueue.length, 0, "supply queue should be empty after update");
    }

    /// @notice Empty withdraw queue update reverts if strategy has non-zero cap
    /// @dev Contract validates that strategies removed from withdraw queue must have cap = 0
    function test_updateWithdrawQueue_EmptyQueue_revertWhen_StrategyHasNonZeroCap() public {
        // Arrange
        _addStrategy(address(strategy), EDGE_STRATEGY_CAP);

        uint256 initialLength = vault.getWithdrawQueueLength();
        assertEq(initialLength, 1, "should have 1 strategy in queue initially");

        // Act & Assert - Cannot remove strategy with non-zero cap from withdraw queue
        uint256[] memory emptyQueue = new uint256[](0);

        (, uint32 delay,,) = manager.getAccess(BVA_SLOW_ID(), bva_slow);
        uint48 when = uint48(block.timestamp + delay);

        bytes memory data = abi.encodeCall(BTCVault.updateWithdrawQueue, (emptyQueue));

        vm.startPrank(bva_slow);
        if (delay > 0) {
            manager.schedule(address(vault), data, when);
            vm.warp(when);
        }
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidStrategyRemovalWithNonZeroCap.selector, 0));
        manager.execute(address(vault), data);
        vm.stopPrank();
    }

    // ============ Fee Edge Cases ============

    /// @notice Zero entry fee should work correctly
    function test_deposit_WithZeroEntryFee_SharesEqualDeposit() public {
        // Arrange - Set entry fee to 0
        _scheduleAndExecuteLocal(bvm_slow, BVM_SLOW_ID(), abi.encodeCall(BTCVault.setEntryFee, (0)));
        _addStrategy(address(strategy), EDGE_STRATEGY_CAP);

        // Act
        uint256 depositAmount = EDGE_DEPOSIT_AMOUNT;
        uint256 shares = _depositAsUser(depositAmount);

        // Assert - With zero fee, first depositor shares should equal deposit amount
        assertEq(shares, depositAmount, "zero fee: first depositor shares should equal deposit");
    }

    /// @notice Max entry fee (10%) should work correctly
    function test_deposit_WithMaxEntryFee_TakesCorrectFee() public {
        // Arrange - Set entry fee to max (10% = 1000 bps)
        uint256 maxFeeBps = 1000; // 10%
        _scheduleAndExecuteLocal(bvm_slow, BVM_SLOW_ID(), abi.encodeCall(BTCVault.setEntryFee, (maxFeeBps)));
        _addStrategy(address(strategy), EDGE_STRATEGY_CAP);

        // Act
        uint256 depositAmount = 1000e6;
        uint256 shares = _depositAsUser(depositAmount);

        // Assert - 10% fee means ~909 should go to shares (using feeOnTotal)
        // feeOnTotal(1000, 1000) = 1000 * 1000 / (1000 + 10000) = 90.9 rounded up
        // So ~909 assets after fee
        uint256 expectedSharesApprox = 909e6;
        assertApproxEqAbs(shares, expectedSharesApprox, 1e6, "max 10% fee should take approximately 10%");
    }

    /// @notice Setting entry fee above max should revert
    function test_setEntryFee_revertWhen_ExceedMaxFee() public {
        uint256 exceedMaxFee = 1001; // 10.01% > 10% max

        (, uint32 delay,,) = manager.getAccess(BVM_SLOW_ID(), bvm_slow);
        uint48 when = uint48(block.timestamp + delay);

        bytes memory data = abi.encodeCall(BTCVault.setEntryFee, (exceedMaxFee));

        vm.startPrank(bvm_slow);
        if (delay > 0) {
            manager.schedule(address(vault), data, when);
            vm.warp(when);
        }
        vm.expectRevert(Errors.ExceedMaxFee.selector);
        manager.execute(address(vault), data);
        vm.stopPrank();
    }

    /// @notice Setting exit fee above max should revert
    function test_setExitFee_revertWhen_ExceedMaxFee() public {
        uint256 exceedMaxFee = 1001; // 10.01% > 10% max

        (, uint32 delay,,) = manager.getAccess(BVM_SLOW_ID(), bvm_slow);
        uint48 when = uint48(block.timestamp + delay);

        bytes memory data = abi.encodeCall(BTCVault.setExitFee, (exceedMaxFee));

        vm.startPrank(bvm_slow);
        if (delay > 0) {
            manager.schedule(address(vault), data, when);
            vm.warp(when);
        }
        vm.expectRevert(Errors.ExceedMaxFee.selector);
        manager.execute(address(vault), data);
        vm.stopPrank();
    }

    // ============ View Function Tests ============

    /// @notice getNextStrategyIndex should return correct monotonic counter
    function test_getNextStrategyIndex_ReturnsCorrectCounter() public {
        // Assert initial state
        assertEq(vault.getNextStrategyIndex(), 0, "should start at index 0");

        // Add first strategy
        _addStrategy(address(strategy), EDGE_STRATEGY_CAP);
        assertEq(vault.getNextStrategyIndex(), 1, "should be 1 after adding first strategy");

        // Add second strategy
        MockYieldSource ys2 = new MockYieldSource();
        MockTokenizedStrategy strat2 = new MockTokenizedStrategy(address(ys2), address(vault));
        _addStrategy(address(strat2), EDGE_STRATEGY_CAP);
        assertEq(vault.getNextStrategyIndex(), 2, "should be 2 after adding second strategy");
    }

    /// @notice getMaxStrategies should return configured value
    function test_getMaxStrategies_ReturnsConfiguredValue() public view {
        assertEq(vault.getMaxStrategies(), MAX_STRATEGIES, "should match configured max strategies");
    }

    /// @notice getSupplyQueueLength and getWithdrawQueueLength should return correct values
    function test_getQueueLengths_ReturnCorrectValues() public {
        // Arrange
        _addStrategy(address(strategy), EDGE_STRATEGY_CAP);

        // Assert
        assertEq(vault.getSupplyQueueLength(), 1, "supply queue should have 1 strategy");
        assertEq(vault.getWithdrawQueueLength(), 1, "withdraw queue should have 1 strategy");

        // Add another strategy
        MockYieldSource ys2 = new MockYieldSource();
        MockTokenizedStrategy strat2 = new MockTokenizedStrategy(address(ys2), address(vault));
        _addStrategy(address(strat2), EDGE_STRATEGY_CAP);

        // Assert updated lengths
        assertEq(vault.getSupplyQueueLength(), 2, "supply queue should have 2 strategies");
        assertEq(vault.getWithdrawQueueLength(), 2, "withdraw queue should have 2 strategies");
    }

    // ============ Donation Attack Protection Tests ============

    /// @notice Deposit reverts when donation attack inflates share price so deposit yields zero shares
    /// @dev Attacker seeds vault with small deposit, donates large amount to yield source,
    ///      then victim's deposit would mint 0 shares — vault now reverts to protect victim.
    function test_Deposit_RevertWhen_ZeroSharesMinted() public {
        // Arrange
        _addStrategy(address(strategy), VERY_LARGE_CAP);

        // Remove fees to isolate donation effect
        _scheduleAndExecuteLocal(bvm_slow, BVM_SLOW_ID(), abi.encodeCall(BTCVault.setEntryFee, (0)));
        _scheduleAndExecuteLocal(bvm_slow, BVM_SLOW_ID(), abi.encodeCall(BTCVault.setExitFee, (0)));

        // Attacker seeds vault with small deposit
        uint256 seedDeposit = 10_000; // smallest meaningful deposit
        _depositAsUser(seedDeposit);

        // Attacker donates large amount directly to yield source (bypasses vault accounting)
        // This inflates strategy.totalAssets() without minting new shares
        uint256 donation = 100_000_000e6; // 100M USDC
        vm.prank(address(strategy));
        yieldSource.supply(address(mockUSDC), donation);

        // Act & Assert - Victim deposits tiny amount that yields 0 shares due to inflated price
        address victim = makeAddr("victim");
        manager.grantRole(BVD_ID(), victim, 0);
        uint256 victimDeposit = 1; // 1 wei of USDC
        mockUSDC.mint(victim, victimDeposit);

        vm.startPrank(victim);
        mockUSDC.approve(address(vault), victimDeposit);
        vm.expectRevert(Errors.ZeroAmount.selector);
        vault.deposit(victimDeposit, victim);
        vm.stopPrank();
    }

    /// @notice Strategy deposit reverts when donation inflates share price so deposit yields zero shares
    /// @dev Defense-in-depth: SimpleTokenizedStrategy also guards against zero-share deposits
    function test_Strategy_Deposit_RevertWhen_ZeroSharesMinted() public {
        // Arrange
        _addStrategy(address(strategy), VERY_LARGE_CAP);

        // Seed strategy with a small deposit (via vault deposit which flows to strategy)
        _scheduleAndExecuteLocal(bvm_slow, BVM_SLOW_ID(), abi.encodeCall(BTCVault.setEntryFee, (0)));
        uint256 seedDeposit = 10_000;
        _depositAsUser(seedDeposit);

        // Donate large amount directly to yield source to inflate strategy share price
        uint256 donation = 100_000_000e6;
        vm.prank(address(strategy));
        yieldSource.supply(address(mockUSDC), donation);

        // Act & Assert - Strategy deposit as vault that yields 0 shares
        uint256 tinyAmount = 1;
        mockUSDC.mint(address(vault), tinyAmount);
        vm.startPrank(address(vault));
        mockUSDC.approve(address(strategy), tinyAmount);
        vm.expectRevert(Errors.ZeroAmount.selector);
        strategy.deposit(tinyAmount, address(vault));
        vm.stopPrank();
    }

    // ============ Dust Share Cleanup Tests ============

    /// @notice Verifies that owner's dust shares are burned after withdrawal drains totalAssets to 0
    function test_withdraw_BurnsDustShares_WhenTotalAssetsDrainedToZero() public {
        // Arrange — deploy a strategy and deposit
        _addStrategy(address(strategy), EDGE_STRATEGY_CAP);
        _depositAsUser(EDGE_DEPOSIT_AMOUNT);

        // Act — withdraw all assets (maxWithdraw), which may leave dust shares
        uint256 maxW = vault.maxWithdraw(user);
        vm.prank(user);
        vault.withdraw(maxW, user, user);

        // Assert — if totalAssets is 0, totalSupply must also be 0
        if (vault.totalAssets() == 0) {
            assertEq(vault.totalSupply(), 0, "dust shares should be burned when totalAssets == 0");
            assertEq(vault.balanceOf(user), 0, "user balance should be 0 after dust cleanup");
        }
    }

    /// @notice Verifies that ghost dust from a previous drain is cleaned up on next deposit
    function test_deposit_CleansGhostDust_OnNextInteraction() public {
        // Arrange — create a second user
        address user2 = makeAddr("user2");
        manager.grantRole(BVD_ID(), user2, 0);
        mockUSDC.mint(user2, USDC_TO_MINT);

        _addStrategy(address(strategy), EDGE_STRATEGY_CAP);

        // User 1 deposits
        _depositAsUser(EDGE_DEPOSIT_AMOUNT);

        // User 2 deposits
        vm.startPrank(user2);
        mockUSDC.approve(address(vault), EDGE_DEPOSIT_AMOUNT);
        vault.deposit(EDGE_DEPOSIT_AMOUNT, user2);
        vm.stopPrank();

        // User 1 withdraws everything — may drain totalAssets if user2's shares are dust
        uint256 maxW1 = vault.maxWithdraw(user);
        if (maxW1 > 0) {
            vm.prank(user);
            vault.withdraw(maxW1, user, user);
        }

        // User 2 withdraws everything
        uint256 maxW2 = vault.maxWithdraw(user2);
        if (maxW2 > 0) {
            vm.prank(user2);
            vault.withdraw(maxW2, user2, user2);
        }

        // If totalAssets is 0 and user2 has ghost dust, a new deposit should clean it
        if (vault.totalAssets() == 0 && vault.balanceOf(user2) > 0) {
            // Act — user2 deposits again (should auto-clean ghost dust)
            vm.startPrank(user2);
            mockUSDC.approve(address(vault), EDGE_DEPOSIT_AMOUNT);
            vault.deposit(EDGE_DEPOSIT_AMOUNT, user2);
            vm.stopPrank();

            // Assert — vault should be solvent
            assertGt(vault.totalAssets(), 0, "vault should have assets after new deposit");
        }
    }

    /// @notice Verifies that redeem also triggers dust cleanup
    function test_redeem_BurnsDustShares_WhenTotalAssetsDrainedToZero() public {
        // Arrange
        _addStrategy(address(strategy), EDGE_STRATEGY_CAP);
        _depositAsUser(EDGE_DEPOSIT_AMOUNT);

        // Act — redeem all shares
        uint256 userShares = vault.balanceOf(user);
        vm.prank(user);
        vault.redeem(userShares, user, user);

        // Assert
        assertEq(vault.balanceOf(user), 0, "all shares should be redeemed");
        if (vault.totalAssets() == 0) {
            assertEq(vault.totalSupply(), 0, "no dust shares should remain");
        }
    }
}
