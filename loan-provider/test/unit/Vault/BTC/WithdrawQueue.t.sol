// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.30;

import {ERC20} from "@solady/tokens/ERC20.sol";
import {Vm} from "forge-std/Vm.sol";

import {BTCVault} from "@btcVault/BTCVault.sol";
import {Errors} from "@bitmor/libraries/helpers/Errors.sol";
import {DataTypes} from "@bitmor/libraries/types/DataTypes.sol";
import {MockTokenizedStrategy, BaseTestForBTCVault} from "../BaseTestForBTCVault.t.sol";
import {MockYieldSource} from "../../../mock/MockYieldSource.sol";

/// @title WithdrawQueue
/// @author Bitmor Protocol
/// @notice Tests for BTCVault withdraw queue update, validation, and approval revocation
/// @dev Verifies queue reordering, revert conditions, and that strategy token approvals
///      are properly revoked when strategies are removed from the withdraw queue
contract WithdrawQueue is BaseTestForBTCVault {
    event BTCVault__SupplyQueueUpdated(uint256[] indexed newSupplyQueue);

    modifier addStrategies() {
        _addStrategies();
        _;
    }

    function test_updateWithdrawQueue() public addStrategies {
        uint256[] memory newWithdrawQueue = new uint256[](5);
        newWithdrawQueue[0] = 3;
        newWithdrawQueue[1] = 2;
        newWithdrawQueue[2] = 1;
        newWithdrawQueue[3] = 4;
        newWithdrawQueue[4] = 0;

        _scheduleAndExecute(bva_slow, bva_slow_id(), abi.encodeCall(BTCVault.updateWithdrawQueue, (newWithdrawQueue)));

        uint256[] memory withdrawQueue = vault.getWithdrawQueue();

        assertEq(withdrawQueue, newWithdrawQueue);
    }

    function test_RevertWhen_newWithdrawLengthIsGreaterThanCurrentQueueLength() public addStrategies {
        uint256[] memory newWithdrawQueue = new uint256[](vault.getWithdrawQueueLength() + 1);
        bytes memory data = abi.encodeCall(BTCVault.updateWithdrawQueue, (newWithdrawQueue));

        _scheduleAndExpectRevert(bva_slow, bva_slow_id(), data, abi.encodeWithSelector(Errors.WrongLength.selector));
    }

    /// @notice Verifies that removing a strategy via updateWithdrawQueue revokes its token approval
    function test_updateWithdrawQueue_RevokesApprovalOnRemoval() public {
        // Arrange — add a single strategy
        MockTokenizedStrategy removableStrategy = new MockTokenizedStrategy(address(yieldSource), address(vault));
        _scheduleAndExecute(
            bvc, bvc_id(), abi.encodeCall(BTCVault.addStrategy, (address(removableStrategy), STANDARD_STRATEGY_CAP))
        );

        // Verify approval was granted
        uint256 approvalBefore = ERC20(vault.asset()).allowance(address(vault), address(removableStrategy));
        assertEq(approvalBefore, type(uint256).max, "approval should be max after addStrategy");

        // Set cap to 0 (required before removal)
        _scheduleAndExecute(bvc, bvc_id(), abi.encodeCall(BTCVault.changeStrategyCap, (address(removableStrategy), 0)));

        // Act — remove strategy by passing empty withdraw queue
        uint256[] memory emptyQueue = new uint256[](0);
        _scheduleAndExecute(bva_slow, bva_slow_id(), abi.encodeCall(BTCVault.updateWithdrawQueue, (emptyQueue)));

        // Assert — approval must be revoked
        uint256 approvalAfter = ERC20(vault.asset()).allowance(address(vault), address(removableStrategy));
        assertEq(approvalAfter, 0, "approval should be 0 after strategy removal");
    }

    /// @notice Verifies that strategies remaining in the queue retain their approval
    function test_updateWithdrawQueue_RetainedStrategiesKeepApproval() public {
        // Arrange — add two strategies
        MockTokenizedStrategy strategyA = new MockTokenizedStrategy(address(yieldSource), address(vault));
        MockTokenizedStrategy strategyB = new MockTokenizedStrategy(address(yieldSource), address(vault));

        _scheduleAndExecute(
            bvc, bvc_id(), abi.encodeCall(BTCVault.addStrategy, (address(strategyA), STANDARD_STRATEGY_CAP))
        );
        _scheduleAndExecute(
            bvc, bvc_id(), abi.encodeCall(BTCVault.addStrategy, (address(strategyB), STANDARD_STRATEGY_CAP))
        );

        // Set cap to 0 for strategyB (index 1 in withdraw queue)
        _scheduleAndExecute(bvc, bvc_id(), abi.encodeCall(BTCVault.changeStrategyCap, (address(strategyB), 0)));

        // Act — keep only strategyA (index 0 in current withdraw queue)
        uint256[] memory keepFirst = new uint256[](1);
        keepFirst[0] = 0;
        _scheduleAndExecute(bva_slow, bva_slow_id(), abi.encodeCall(BTCVault.updateWithdrawQueue, (keepFirst)));

        // Assert — strategyA still has max approval
        uint256 approvalA = ERC20(vault.asset()).allowance(address(vault), address(strategyA));
        assertEq(approvalA, type(uint256).max, "retained strategy should keep max approval");

        // Assert — strategyB has zero approval
        uint256 approvalB = ERC20(vault.asset()).allowance(address(vault), address(strategyB));
        assertEq(approvalB, 0, "removed strategy should have zero approval");
    }

    /// @notice Verifies that removing multiple strategies revokes all their approvals
    function test_updateWithdrawQueue_MultipleRemovalsRevokeAllApprovals() public {
        // Arrange — add three strategies
        MockTokenizedStrategy strategyA = new MockTokenizedStrategy(address(yieldSource), address(vault));
        MockTokenizedStrategy strategyB = new MockTokenizedStrategy(address(yieldSource), address(vault));
        MockTokenizedStrategy strategyC = new MockTokenizedStrategy(address(yieldSource), address(vault));

        _scheduleAndExecute(
            bvc, bvc_id(), abi.encodeCall(BTCVault.addStrategy, (address(strategyA), STANDARD_STRATEGY_CAP))
        );
        _scheduleAndExecute(
            bvc, bvc_id(), abi.encodeCall(BTCVault.addStrategy, (address(strategyB), STANDARD_STRATEGY_CAP))
        );
        _scheduleAndExecute(
            bvc, bvc_id(), abi.encodeCall(BTCVault.addStrategy, (address(strategyC), STANDARD_STRATEGY_CAP))
        );

        // Set caps to 0 for all three
        _scheduleAndExecute(bvc, bvc_id(), abi.encodeCall(BTCVault.changeStrategyCap, (address(strategyA), 0)));
        _scheduleAndExecute(bvc, bvc_id(), abi.encodeCall(BTCVault.changeStrategyCap, (address(strategyB), 0)));
        _scheduleAndExecute(bvc, bvc_id(), abi.encodeCall(BTCVault.changeStrategyCap, (address(strategyC), 0)));

        // Act — remove all strategies
        uint256[] memory emptyQueue = new uint256[](0);
        _scheduleAndExecute(bva_slow, bva_slow_id(), abi.encodeCall(BTCVault.updateWithdrawQueue, (emptyQueue)));

        // Assert — all approvals revoked
        assertEq(
            ERC20(vault.asset()).allowance(address(vault), address(strategyA)), 0, "strategyA approval should be 0"
        );
        assertEq(
            ERC20(vault.asset()).allowance(address(vault), address(strategyB)), 0, "strategyB approval should be 0"
        );
        assertEq(
            ERC20(vault.asset()).allowance(address(vault), address(strategyC)), 0, "strategyC approval should be 0"
        );
    }

    // ============ Strategy Removal Scenario Tests ============

    /// @notice totalAssets() returns correct value after removing a strategy
    function test_TotalAssets_AfterStrategyRemoval() public {
        // Arrange — add two strategies
        MockTokenizedStrategy strategyA = new MockTokenizedStrategy(address(yieldSource), address(vault));
        MockTokenizedStrategy strategyB = new MockTokenizedStrategy(address(yieldSource), address(vault));

        _scheduleAndExecute(
            bvc, bvc_id(), abi.encodeCall(BTCVault.addStrategy, (address(strategyA), STANDARD_STRATEGY_CAP))
        );
        _scheduleAndExecute(
            bvc, bvc_id(), abi.encodeCall(BTCVault.addStrategy, (address(strategyB), STANDARD_STRATEGY_CAP))
        );

        uint256 totalBefore = vault.totalAssets();

        // Remove strategyB
        _scheduleAndExecute(bvc, bvc_id(), abi.encodeCall(BTCVault.changeStrategyCap, (address(strategyB), 0)));
        uint256[] memory keepFirst = new uint256[](1);
        keepFirst[0] = 0;
        _scheduleAndExecute(bva_slow, bva_slow_id(), abi.encodeCall(BTCVault.updateWithdrawQueue, (keepFirst)));

        // Assert — totalAssets still works
        uint256 totalAfter = vault.totalAssets();
        assertEq(totalAfter, totalBefore, "totalAssets should be unchanged after removing empty strategy");
    }

    /// @notice totalAssets() works after removing multiple strategies
    function test_TotalAssets_AfterMultipleRemovals() public {
        MockTokenizedStrategy stratA = new MockTokenizedStrategy(address(yieldSource), address(vault));
        MockTokenizedStrategy stratB = new MockTokenizedStrategy(address(yieldSource), address(vault));
        MockTokenizedStrategy stratC = new MockTokenizedStrategy(address(yieldSource), address(vault));

        _scheduleAndExecute(
            bvc, bvc_id(), abi.encodeCall(BTCVault.addStrategy, (address(stratA), STANDARD_STRATEGY_CAP))
        );
        _scheduleAndExecute(
            bvc, bvc_id(), abi.encodeCall(BTCVault.addStrategy, (address(stratB), STANDARD_STRATEGY_CAP))
        );
        _scheduleAndExecute(
            bvc, bvc_id(), abi.encodeCall(BTCVault.addStrategy, (address(stratC), STANDARD_STRATEGY_CAP))
        );

        // Remove B and C
        _scheduleAndExecute(bvc, bvc_id(), abi.encodeCall(BTCVault.changeStrategyCap, (address(stratB), 0)));
        _scheduleAndExecute(bvc, bvc_id(), abi.encodeCall(BTCVault.changeStrategyCap, (address(stratC), 0)));

        uint256[] memory keepFirst = new uint256[](1);
        keepFirst[0] = 0;
        _scheduleAndExecute(bva_slow, bva_slow_id(), abi.encodeCall(BTCVault.updateWithdrawQueue, (keepFirst)));

        // Assert
        uint256 totalAfter = vault.totalAssets();
        assertEq(totalAfter, 0, "totalAssets should be 0 with no deposits");
        assertEq(vault.getWithdrawQueueLength(), 1, "withdraw queue should have 1 entry");
    }

    /// @notice Full ERC-4626 deposit/withdraw cycle works after strategy removal
    function test_DepositAndWithdraw_AfterStrategyRemoval() public {
        MockTokenizedStrategy stratA = new MockTokenizedStrategy(address(yieldSource), address(vault));
        MockTokenizedStrategy stratB = new MockTokenizedStrategy(address(yieldSource), address(vault));

        _scheduleAndExecute(
            bvc, bvc_id(), abi.encodeCall(BTCVault.addStrategy, (address(stratA), STANDARD_STRATEGY_CAP))
        );
        _scheduleAndExecute(
            bvc, bvc_id(), abi.encodeCall(BTCVault.addStrategy, (address(stratB), STANDARD_STRATEGY_CAP))
        );

        // Remove stratB
        _scheduleAndExecute(bvc, bvc_id(), abi.encodeCall(BTCVault.changeStrategyCap, (address(stratB), 0)));
        uint256[] memory keepFirst = new uint256[](1);
        keepFirst[0] = 0;
        _scheduleAndExecute(bva_slow, bva_slow_id(), abi.encodeCall(BTCVault.updateWithdrawQueue, (keepFirst)));

        // No manual updateSupplyQueue needed — auto-cleaned

        // Deposit and redeem
        uint256 depositAmount = DEPOSIT_AMOUNT;
        vm.startPrank(user);
        mockUSDC.approve(address(vault), depositAmount);
        uint256 shares = vault.deposit(depositAmount, user);
        assertGt(shares, 0, "should receive shares on deposit");

        uint256 redeemed = vault.redeem(shares, user, user);
        vm.stopPrank();

        assertGt(redeemed, 0, "should receive assets on redeem");
    }

    /// @notice Re-adding a previously removed strategy address works
    function test_AddStrategy_AfterRemoval_SameAddress() public {
        MockTokenizedStrategy strat = new MockTokenizedStrategy(address(yieldSource), address(vault));

        _scheduleAndExecute(
            bvc, bvc_id(), abi.encodeCall(BTCVault.addStrategy, (address(strat), STANDARD_STRATEGY_CAP))
        );

        // Remove it
        _scheduleAndExecute(bvc, bvc_id(), abi.encodeCall(BTCVault.changeStrategyCap, (address(strat), 0)));
        uint256[] memory emptyQueue = new uint256[](0);
        _scheduleAndExecute(bva_slow, bva_slow_id(), abi.encodeCall(BTCVault.updateWithdrawQueue, (emptyQueue)));

        // Re-add same address
        _scheduleAndExecute(
            bvc, bvc_id(), abi.encodeCall(BTCVault.addStrategy, (address(strat), STANDARD_STRATEGY_CAP))
        );

        // Assert — new index, not old
        uint256 newIndex = vault.getStrategyIndex(address(strat));
        assertEq(newIndex, 1, "re-added strategy should get next index (1), not old index (0)");
        assertEq(vault.getWithdrawQueueLength(), 1, "withdraw queue should have 1 entry");
        assertEq(vault.getNextStrategyIndex(), 2, "nextStrategyIndex should be 2");
    }

    /// @notice Adding a new strategy after removal doesn't hit MaxStrategiesReached
    function test_AddStrategy_AfterRemoval_CapacityRestored() public {
        // Fill to MAX_STRATEGIES
        MockTokenizedStrategy[] memory strats = new MockTokenizedStrategy[](MAX_STRATEGIES);
        for (uint256 i = 0; i < MAX_STRATEGIES; i++) {
            MockYieldSource ys = new MockYieldSource();
            strats[i] = new MockTokenizedStrategy(address(ys), address(vault));
            _scheduleAndExecute(
                bvc, bvc_id(), abi.encodeCall(BTCVault.addStrategy, (address(strats[i]), STANDARD_STRATEGY_CAP))
            );
        }

        // Remove last strategy
        _scheduleAndExecute(
            bvc, bvc_id(), abi.encodeCall(BTCVault.changeStrategyCap, (address(strats[MAX_STRATEGIES - 1]), 0))
        );
        uint256[] memory keepQueue = new uint256[](MAX_STRATEGIES - 1);
        for (uint256 i = 0; i < MAX_STRATEGIES - 1; i++) {
            keepQueue[i] = i;
        }
        _scheduleAndExecute(bva_slow, bva_slow_id(), abi.encodeCall(BTCVault.updateWithdrawQueue, (keepQueue)));

        // Add a new strategy — should succeed
        MockYieldSource newYs = new MockYieldSource();
        MockTokenizedStrategy newStrat = new MockTokenizedStrategy(address(newYs), address(vault));
        _scheduleAndExecute(
            bvc, bvc_id(), abi.encodeCall(BTCVault.addStrategy, (address(newStrat), STANDARD_STRATEGY_CAP))
        );

        assertEq(vault.getWithdrawQueueLength(), MAX_STRATEGIES, "should be at max strategies again");
    }

    /// @notice Reallocating to a removed strategy index reverts
    /// @dev After deletion, strategy.strategy is address(0), so getAssetBalanceInStrategy()
    ///      reverts with a low-level "call to non-contract address" error
    function test_ReallocateFunds_RemovedStrategyIndex_Reverts() public {
        MockTokenizedStrategy strat = new MockTokenizedStrategy(address(yieldSource), address(vault));
        _scheduleAndExecute(
            bvc, bvc_id(), abi.encodeCall(BTCVault.addStrategy, (address(strat), STANDARD_STRATEGY_CAP))
        );

        _scheduleAndExecute(bvc, bvc_id(), abi.encodeCall(BTCVault.changeStrategyCap, (address(strat), 0)));
        uint256[] memory emptyQueue = new uint256[](0);
        _scheduleAndExecute(bva_slow, bva_slow_id(), abi.encodeCall(BTCVault.updateWithdrawQueue, (emptyQueue)));

        // Try to reallocate to removed index 0
        DataTypes.Allocation[] memory allocs = new DataTypes.Allocation[](1);
        allocs[0] = DataTypes.Allocation({index: 0, amount: 1000e6});

        bytes memory data = abi.encodeCall(BTCVault.reallocateFunds, (allocs));
        // Generic revert: call to address(0) triggers a low-level EVM revert
        // with no custom Solidity error selector
        vm.expectRevert();
        vm.prank(bva_fast);
        manager.execute(address(vault), data);
    }

    /// @notice Supply queue is auto-cleaned when strategy is removed via updateWithdrawQueue
    function test_SupplyQueue_AutoCleanedOnStrategyRemoval() public {
        MockTokenizedStrategy stratA = new MockTokenizedStrategy(address(yieldSource), address(vault));
        MockTokenizedStrategy stratB = new MockTokenizedStrategy(address(yieldSource), address(vault));

        _scheduleAndExecute(
            bvc, bvc_id(), abi.encodeCall(BTCVault.addStrategy, (address(stratA), STANDARD_STRATEGY_CAP))
        );
        _scheduleAndExecute(
            bvc, bvc_id(), abi.encodeCall(BTCVault.addStrategy, (address(stratB), STANDARD_STRATEGY_CAP))
        );

        // Remove strategyB from withdraw queue
        _scheduleAndExecute(bvc, bvc_id(), abi.encodeCall(BTCVault.changeStrategyCap, (address(stratB), 0)));
        uint256[] memory keepFirst = new uint256[](1);
        keepFirst[0] = 0;
        _scheduleAndExecute(bva_slow, bva_slow_id(), abi.encodeCall(BTCVault.updateWithdrawQueue, (keepFirst)));

        // Supply queue should be auto-cleaned (no stale entry)
        assertEq(vault.getSupplyQueueLength(), 1, "supply queue should be auto-cleaned after removal");

        // Deposit should still succeed

        uint256 depositAmount = DEPOSIT_AMOUNT;
        vm.startPrank(user);
        mockUSDC.approve(address(vault), depositAmount);
        uint256 shares = vault.deposit(depositAmount, user);
        vm.stopPrank();

        assertGt(shares, 0, "deposit should succeed after auto-cleaned supply queue");
    }

    /// @notice Auto-clean removes multiple stale entries from supply queue
    function test_updateWithdrawQueue_AutoCleansSupplyQueue_MultipleRemovals() public {
        MockTokenizedStrategy stratA = new MockTokenizedStrategy(address(yieldSource), address(vault));
        MockYieldSource ysB = new MockYieldSource();
        MockTokenizedStrategy stratB = new MockTokenizedStrategy(address(ysB), address(vault));
        MockYieldSource ysC = new MockYieldSource();
        MockTokenizedStrategy stratC = new MockTokenizedStrategy(address(ysC), address(vault));

        _scheduleAndExecute(
            bvc, bvc_id(), abi.encodeCall(BTCVault.addStrategy, (address(stratA), STANDARD_STRATEGY_CAP))
        );
        _scheduleAndExecute(
            bvc, bvc_id(), abi.encodeCall(BTCVault.addStrategy, (address(stratB), STANDARD_STRATEGY_CAP))
        );
        _scheduleAndExecute(
            bvc, bvc_id(), abi.encodeCall(BTCVault.addStrategy, (address(stratC), STANDARD_STRATEGY_CAP))
        );

        assertEq(vault.getSupplyQueueLength(), 3, "supply queue should have 3 entries");

        // Remove B and C
        _scheduleAndExecute(bvc, bvc_id(), abi.encodeCall(BTCVault.changeStrategyCap, (address(stratB), 0)));
        _scheduleAndExecute(bvc, bvc_id(), abi.encodeCall(BTCVault.changeStrategyCap, (address(stratC), 0)));
        uint256[] memory keepFirst = new uint256[](1);
        keepFirst[0] = 0;
        _scheduleAndExecute(bva_slow, bva_slow_id(), abi.encodeCall(BTCVault.updateWithdrawQueue, (keepFirst)));

        // Assert — supply queue should have only stratA
        assertEq(vault.getSupplyQueueLength(), 1, "supply queue should be auto-cleaned to 1 entry");
    }

    /// @notice Auto-clean preserves relative order of surviving supply queue entries
    function test_updateWithdrawQueue_SupplyQueueOrderPreserved() public {
        MockTokenizedStrategy stratA = new MockTokenizedStrategy(address(yieldSource), address(vault));
        MockYieldSource ysB = new MockYieldSource();
        MockTokenizedStrategy stratB = new MockTokenizedStrategy(address(ysB), address(vault));
        MockYieldSource ysC = new MockYieldSource();
        MockTokenizedStrategy stratC = new MockTokenizedStrategy(address(ysC), address(vault));

        _scheduleAndExecute(
            bvc, bvc_id(), abi.encodeCall(BTCVault.addStrategy, (address(stratA), STANDARD_STRATEGY_CAP))
        );
        _scheduleAndExecute(
            bvc, bvc_id(), abi.encodeCall(BTCVault.addStrategy, (address(stratB), STANDARD_STRATEGY_CAP))
        );
        _scheduleAndExecute(
            bvc, bvc_id(), abi.encodeCall(BTCVault.addStrategy, (address(stratC), STANDARD_STRATEGY_CAP))
        );

        // Supply queue is [0, 1, 2] (stratA, stratB, stratC)
        uint256[] memory sqBefore = vault.getSupplyQueue();
        assertEq(sqBefore.length, 3, "supply queue should have 3 entries");

        // Remove stratB (index 1 in withdraw queue)
        _scheduleAndExecute(bvc, bvc_id(), abi.encodeCall(BTCVault.changeStrategyCap, (address(stratB), 0)));
        uint256[] memory keepAC = new uint256[](2);
        keepAC[0] = 0; // stratA
        keepAC[1] = 2; // stratC
        _scheduleAndExecute(bva_slow, bva_slow_id(), abi.encodeCall(BTCVault.updateWithdrawQueue, (keepAC)));

        // Supply queue should be [0, 2] — stratA first, then stratC (order preserved)
        uint256[] memory sqAfter = vault.getSupplyQueue();
        assertEq(sqAfter.length, 2, "supply queue should have 2 entries");
        assertEq(sqAfter[0], sqBefore[0], "first supply queue entry should be stratA index");
        assertEq(sqAfter[1], sqBefore[2], "second supply queue entry should be stratC index");
    }

    /// @notice Reorder-only updateWithdrawQueue does not touch supply queue
    function test_updateWithdrawQueue_NoRemoval_SupplyQueueUnchanged() public {
        MockTokenizedStrategy stratA = new MockTokenizedStrategy(address(yieldSource), address(vault));
        MockYieldSource ysB = new MockYieldSource();
        MockTokenizedStrategy stratB = new MockTokenizedStrategy(address(ysB), address(vault));

        _scheduleAndExecute(
            bvc, bvc_id(), abi.encodeCall(BTCVault.addStrategy, (address(stratA), STANDARD_STRATEGY_CAP))
        );
        _scheduleAndExecute(
            bvc, bvc_id(), abi.encodeCall(BTCVault.addStrategy, (address(stratB), STANDARD_STRATEGY_CAP))
        );

        uint256[] memory sqBefore = vault.getSupplyQueue();

        // Reorder withdraw queue (swap positions, no removal)
        uint256[] memory reversed = new uint256[](2);
        reversed[0] = 1; // stratB first
        reversed[1] = 0; // stratA second
        _scheduleAndExecute(bva_slow, bva_slow_id(), abi.encodeCall(BTCVault.updateWithdrawQueue, (reversed)));

        // Supply queue should be unchanged
        uint256[] memory sqAfter = vault.getSupplyQueue();
        assertEq(sqAfter.length, sqBefore.length, "supply queue length should be unchanged");
        for (uint256 i = 0; i < sqAfter.length; i++) {
            assertEq(sqAfter[i], sqBefore[i], "supply queue entry should be unchanged");
        }
    }

    /// @notice Deposits work without manual supply queue cleanup after removal
    function test_updateWithdrawQueue_DepositWorksWithoutManualCleanup() public {
        MockTokenizedStrategy stratA = new MockTokenizedStrategy(address(yieldSource), address(vault));
        MockYieldSource ysB = new MockYieldSource();
        MockTokenizedStrategy stratB = new MockTokenizedStrategy(address(ysB), address(vault));

        _scheduleAndExecute(
            bvc, bvc_id(), abi.encodeCall(BTCVault.addStrategy, (address(stratA), STANDARD_STRATEGY_CAP))
        );
        _scheduleAndExecute(
            bvc, bvc_id(), abi.encodeCall(BTCVault.addStrategy, (address(stratB), STANDARD_STRATEGY_CAP))
        );

        // Remove stratB
        _scheduleAndExecute(bvc, bvc_id(), abi.encodeCall(BTCVault.changeStrategyCap, (address(stratB), 0)));
        uint256[] memory keepFirst = new uint256[](1);
        keepFirst[0] = 0;
        _scheduleAndExecute(bva_slow, bva_slow_id(), abi.encodeCall(BTCVault.updateWithdrawQueue, (keepFirst)));

        // NO manual updateSupplyQueue call — auto-clean should handle it

        // Deposit should succeed and all assets go to stratA
        uint256 depositAmount = DEPOSIT_AMOUNT;
        vm.startPrank(user);
        mockUSDC.approve(address(vault), depositAmount);
        uint256 shares = vault.deposit(depositAmount, user);
        vm.stopPrank();

        assertGt(shares, 0, "deposit should succeed without manual supply queue cleanup");
        assertEq(vault.getSupplyQueueLength(), 1, "supply queue should have 1 entry after auto-clean");
    }

    /// @notice BTCVault__SupplyQueueUpdated event is emitted when supply queue is auto-cleaned
    function test_updateWithdrawQueue_EmitsSupplyQueueUpdated() public {
        MockTokenizedStrategy strat = new MockTokenizedStrategy(address(yieldSource), address(vault));
        _scheduleAndExecute(
            bvc, bvc_id(), abi.encodeCall(BTCVault.addStrategy, (address(strat), STANDARD_STRATEGY_CAP))
        );

        // Remove strategy
        _scheduleAndExecute(bvc, bvc_id(), abi.encodeCall(BTCVault.changeStrategyCap, (address(strat), 0)));

        // Record logs to check for SupplyQueueUpdated event
        // (vm.expectEmit doesn't work here because _scheduleAndExecute emits OperationScheduled first)
        vm.recordLogs();

        uint256[] memory emptyQueue = new uint256[](0);
        _scheduleAndExecute(bva_slow, bva_slow_id(), abi.encodeCall(BTCVault.updateWithdrawQueue, (emptyQueue)));

        // Check that BTCVault__SupplyQueueUpdated was emitted
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 supplyQueueUpdatedTopic = keccak256("BTCVault__SupplyQueueUpdated(uint256[])");
        bool found = false;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == supplyQueueUpdatedTopic) {
                found = true;
                break;
            }
        }
        assertTrue(found, "BTCVault__SupplyQueueUpdated event should be emitted");
    }

    /// @notice Removing a strategy with non-zero asset balance reverts
    function test_RevertWhen_RemovingStrategyWithNonZeroBalance() public {
        // Arrange — add strategy and deposit funds into it
        MockTokenizedStrategy strat = new MockTokenizedStrategy(address(yieldSource), address(vault));
        _scheduleAndExecute(
            bvc, bvc_id(), abi.encodeCall(BTCVault.addStrategy, (address(strat), STANDARD_STRATEGY_CAP))
        );

        // Deposit funds that will flow into the strategy
        uint256 depositAmount = DEPOSIT_AMOUNT;
        vm.startPrank(user);
        mockUSDC.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, user);
        vm.stopPrank();

        // Set cap to 0 (pre-requisite for removal)
        _scheduleAndExecute(bvc, bvc_id(), abi.encodeCall(BTCVault.changeStrategyCap, (address(strat), 0)));

        // Act + Assert — removal must revert because strategy still has assets
        uint256[] memory emptyQueue = new uint256[](0);
        bytes memory data = abi.encodeCall(BTCVault.updateWithdrawQueue, (emptyQueue));
        _scheduleAndExpectRevert(
            bva_slow,
            bva_slow_id(),
            data,
            abi.encodeWithSelector(Errors.InvalidStrategyRemovalWithNonZeroAssetBalance.selector, uint256(0))
        );
    }

    /// @notice Removing a strategy with non-zero cap reverts
    function test_RevertWhen_RemovingStrategyWithNonZeroCap() public {
        // Arrange — add strategy but do NOT set cap to 0
        MockTokenizedStrategy strat = new MockTokenizedStrategy(address(yieldSource), address(vault));
        _scheduleAndExecute(
            bvc, bvc_id(), abi.encodeCall(BTCVault.addStrategy, (address(strat), STANDARD_STRATEGY_CAP))
        );

        // Act + Assert — removal must revert because cap is still non-zero
        uint256[] memory emptyQueue = new uint256[](0);
        bytes memory data = abi.encodeCall(BTCVault.updateWithdrawQueue, (emptyQueue));
        _scheduleAndExpectRevert(
            bva_slow,
            bva_slow_id(),
            data,
            abi.encodeWithSelector(Errors.InvalidStrategyRemovalWithNonZeroCap.selector, uint256(0))
        );
    }

    /// @notice emergencyWithdrawFunds works correctly after a strategy has been removed
    function test_EmergencyWithdrawFunds_AfterStrategyRemoval() public {
        // Arrange — add two strategies, deposit into first
        MockTokenizedStrategy stratA = new MockTokenizedStrategy(address(yieldSource), address(vault));
        MockYieldSource ysB = new MockYieldSource();
        MockTokenizedStrategy stratB = new MockTokenizedStrategy(address(ysB), address(vault));

        _scheduleAndExecute(
            bvc, bvc_id(), abi.encodeCall(BTCVault.addStrategy, (address(stratA), STANDARD_STRATEGY_CAP))
        );
        _scheduleAndExecute(
            bvc, bvc_id(), abi.encodeCall(BTCVault.addStrategy, (address(stratB), STANDARD_STRATEGY_CAP))
        );

        // Deposit funds that will flow into stratA via supply queue
        uint256 depositAmount = DEPOSIT_AMOUNT;
        vm.startPrank(user);
        mockUSDC.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, user);
        vm.stopPrank();

        // Remove stratB (empty, cap=0)
        _scheduleAndExecute(bvc, bvc_id(), abi.encodeCall(BTCVault.changeStrategyCap, (address(stratB), 0)));
        uint256[] memory keepFirst = new uint256[](1);
        keepFirst[0] = 0;
        _scheduleAndExecute(bva_slow, bva_slow_id(), abi.encodeCall(BTCVault.updateWithdrawQueue, (keepFirst)));

        // Act — emergency withdraw should recover funds from remaining strategy
        vm.prank(bvm_fast);
        manager.execute(address(vault), abi.encodeCall(BTCVault.emergencyWithdrawFunds, ()));

        // Assert — vault should hold all assets idle now
        uint256 vaultBalance = mockUSDC.balanceOf(address(vault));
        assertGt(vaultBalance, 0, "vault should hold recovered assets after emergency withdraw");
    }

    /// @notice maxWithdraw and maxRedeem return correct values after strategy removal
    function test_MaxWithdrawAndMaxRedeem_AfterStrategyRemoval() public {
        // Arrange — add two strategies, deposit
        MockTokenizedStrategy stratA = new MockTokenizedStrategy(address(yieldSource), address(vault));
        MockYieldSource ysB = new MockYieldSource();
        MockTokenizedStrategy stratB = new MockTokenizedStrategy(address(ysB), address(vault));

        _scheduleAndExecute(
            bvc, bvc_id(), abi.encodeCall(BTCVault.addStrategy, (address(stratA), STANDARD_STRATEGY_CAP))
        );
        _scheduleAndExecute(
            bvc, bvc_id(), abi.encodeCall(BTCVault.addStrategy, (address(stratB), STANDARD_STRATEGY_CAP))
        );

        uint256 depositAmount = DEPOSIT_AMOUNT;
        vm.startPrank(user);
        mockUSDC.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, user);
        vm.stopPrank();

        // Remove stratB
        _scheduleAndExecute(bvc, bvc_id(), abi.encodeCall(BTCVault.changeStrategyCap, (address(stratB), 0)));
        uint256[] memory keepFirst = new uint256[](1);
        keepFirst[0] = 0;
        _scheduleAndExecute(bva_slow, bva_slow_id(), abi.encodeCall(BTCVault.updateWithdrawQueue, (keepFirst)));

        // Assert — maxWithdraw and maxRedeem should be non-zero for user with shares
        uint256 maxW = vault.maxWithdraw(user);
        uint256 maxR = vault.maxRedeem(user);
        assertGt(maxW, 0, "maxWithdraw should be non-zero after strategy removal");
        assertGt(maxR, 0, "maxRedeem should be non-zero after strategy removal");

        // Verify user can actually withdraw the reported max
        vm.prank(user);
        vault.withdraw(maxW, user, user);
    }

    /// @notice Deploys and adds 5 strategies with `STANDARD_STRATEGY_CAP` to the vault
    function _addStrategies() public {
        for (uint256 i = 0; i < 5; i++) {
            MockTokenizedStrategy newStrategy = new MockTokenizedStrategy(address(yieldSource), address(vault));

            _scheduleAndExecute(
                bvc, bvc_id(), abi.encodeCall(BTCVault.addStrategy, (address(newStrategy), STANDARD_STRATEGY_CAP))
            );
        }
    }
}
