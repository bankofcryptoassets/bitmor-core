// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {BaseTestForBTCVault} from "../BaseTestForBTCVault.t.sol";
import {BTCVault} from "@btcVault/BTCVault.sol";
import {MockTokenizedStrategy} from "../../../mock/MockTokenizedStrategy.sol";
import {MockYieldSource} from "../../../mock/MockYieldSource.sol";
import {Errors} from "@bitmor/libraries/helpers/Errors.sol";

/// @title EdgeCasesTest
/// @notice Tests for BTCVault edge cases and boundary conditions
/// @dev Hunts for zero-amount bugs, overflow issues, empty state handling
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

    /// @notice Deposit with zero amount - ERC4626 allows this but mints 0 shares
    function test_deposit_ZeroAssets_MintsZeroShares() public {
        // Arrange
        _addStrategy(address(strategy), EDGE_STRATEGY_CAP);

        // Act
        vm.startPrank(user);
        mockUSDC.approve(address(vault), 0);
        uint256 shares = vault.deposit(0, user);
        vm.stopPrank();

        // Assert - ERC4626 spec allows 0 deposit, returns 0 shares
        assertEq(shares, 0, "zero deposit should return zero shares");
    }

    /// @notice Withdraw with zero amount should revert or no-op
    function test_withdraw_ZeroAmount_HandlesCorrectly() public {
        // Arrange
        _addStrategy(address(strategy), EDGE_STRATEGY_CAP);
        _depositAsUser(EDGE_DEPOSIT_AMOUNT);

        // Act - Try zero withdraw
        vm.prank(user);
        try vault.withdraw(0, user, user) returns (uint256 shares) {
            // If it succeeds, should have burned zero shares
            assertEq(shares, 0, "zero withdraw should burn zero shares");
        } catch {
            // Reverting on zero withdraw is also acceptable
            assertTrue(true, "reverting on zero withdraw is acceptable");
        }
    }

    /// @notice Mint with zero shares - ERC4626 allows this but takes 0 assets
    function test_mint_ZeroShares_TakesZeroAssets() public {
        // Arrange - add mint to BVD selectors so user can mint
        bytes4[] memory mintSelector = new bytes4[](1);
        mintSelector[0] = BTCVault.mint.selector;
        manager.setTargetFunctionRole(address(vault), mintSelector, BVD_ID());

        _addStrategy(address(strategy), EDGE_STRATEGY_CAP);

        // Act
        vm.startPrank(user);
        mockUSDC.approve(address(vault), EDGE_DEPOSIT_AMOUNT);
        uint256 assets = vault.mint(0, user);
        vm.stopPrank();

        // Assert - ERC4626 spec allows 0 mint, takes 0 assets
        assertEq(assets, 0, "zero mint should take zero assets");
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

    /// @notice getTotalStrategies should return correct count
    function test_getTotalStrategies_ReturnsCorrectCount() public {
        // Assert initial state
        assertEq(vault.getTotalStrategies(), 0, "should start with 0 strategies");

        // Add first strategy
        _addStrategy(address(strategy), EDGE_STRATEGY_CAP);
        assertEq(vault.getTotalStrategies(), 1, "should have 1 strategy after adding");

        // Add second strategy
        MockYieldSource ys2 = new MockYieldSource();
        MockTokenizedStrategy strat2 = new MockTokenizedStrategy(address(ys2), address(vault));
        _addStrategy(address(strat2), EDGE_STRATEGY_CAP);
        assertEq(vault.getTotalStrategies(), 2, "should have 2 strategies");
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
}
