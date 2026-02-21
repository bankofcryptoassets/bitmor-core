// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.30;

import {ERC20} from "@solady/tokens/ERC20.sol";

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

        // Clean up supply queue
        uint256[] memory newSupplyQueue = new uint256[](1);
        newSupplyQueue[0] = 0;
        _scheduleAndExecute(bva_slow, bva_slow_id(), abi.encodeCall(BTCVault.updateSupplyQueue, (newSupplyQueue)));

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
        vm.expectRevert();
        vm.prank(bva_fast);
        manager.execute(address(vault), data);
    }

    /// @notice Deposits work even with stale supplyQueue entries after strategy removal
    function test_SupplyQueue_StaleEntry_SkippedSafely() public {
        MockTokenizedStrategy stratA = new MockTokenizedStrategy(address(yieldSource), address(vault));
        MockTokenizedStrategy stratB = new MockTokenizedStrategy(address(yieldSource), address(vault));

        _scheduleAndExecute(
            bvc, bvc_id(), abi.encodeCall(BTCVault.addStrategy, (address(stratA), STANDARD_STRATEGY_CAP))
        );
        _scheduleAndExecute(
            bvc, bvc_id(), abi.encodeCall(BTCVault.addStrategy, (address(stratB), STANDARD_STRATEGY_CAP))
        );

        // Remove strategyB from withdraw queue only (supplyQueue stays stale)
        _scheduleAndExecute(bvc, bvc_id(), abi.encodeCall(BTCVault.changeStrategyCap, (address(stratB), 0)));
        uint256[] memory keepFirst = new uint256[](1);
        keepFirst[0] = 0;
        _scheduleAndExecute(bva_slow, bva_slow_id(), abi.encodeCall(BTCVault.updateWithdrawQueue, (keepFirst)));

        // supplyQueue still has stale entry
        assertEq(vault.getSupplyQueueLength(), 2, "supply queue should still have stale entry");

        // Deposit should succeed — stale entry skipped via cap == 0
        uint256 depositAmount = DEPOSIT_AMOUNT;
        vm.startPrank(user);
        mockUSDC.approve(address(vault), depositAmount);
        uint256 shares = vault.deposit(depositAmount, user);
        vm.stopPrank();

        assertGt(shares, 0, "deposit should succeed with stale supply queue entry");
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
