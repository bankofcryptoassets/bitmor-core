# Issue #71: Supply Queue Auto-Clean Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Auto-clean stale supply queue entries when strategies are removed via `updateWithdrawQueue`, eliminating the admin two-step footgun.

**Architecture:** Add a two-pass filter inside `StrategyStateLogic.updateWithdrawQueue` that removes supply queue entries pointing to deleted strategies. Return a `bool` so `BTCVault` can emit the supply queue event. Update one existing test that relied on manual supply queue cleanup.

**Tech Stack:** Foundry (Solidity 0.8.30), forge test

---

### Task 1: Modify `StrategyStateLogic.updateWithdrawQueue` to return `bool` and auto-clean supply queue

**Files:**
- Modify: `loan-provider/src/libraries/logic/StrategyStateLogic.sol:90-144`

**Step 1: Update the function signature and add supply queue cleanup**

Replace lines 90-145 with:

```solidity
/**
 * @notice Updates the withdraw queue and removes strategies not included in the new queue
 * @dev Validates that removed strategies have zero cap and balance before deletion.
 *      Revokes token approval for removed strategies to prevent unauthorized asset transfers.
 *      Clears `strategyToIndex` for removed strategies to allow re-addition.
 *      Automatically removes stale entries from the supply queue when strategies are deleted.
 * @param s The strategy state storage reference
 * @param newQueue Array of indices referencing positions in current withdraw queue
 * @param asset The underlying asset address used to revoke approval for removed strategies
 * @return supplyQueueCleaned True if the supply queue was modified during cleanup
 */
function updateWithdrawQueue(DataTypes.StrategyState storage s, uint256[] memory newQueue, address asset)
    internal
    returns (bool supplyQueueCleaned)
{
    uint256[] memory currentWithdrawQueue = s.withdrawQueue;
    uint256 newLength = newQueue.length;
    uint256 currLength = currentWithdrawQueue.length;

    // Track which strategies from current queue are included in new queue
    bool[] memory seen = new bool[](currLength);
    uint256[] memory newWithdrawQueue = new uint256[](newLength);

    // Build new queue and mark included strategies
    for (uint256 i; i < newLength; ++i) {
        uint256 prevIndex = newQueue[i];

        // Get strategy ID from current queue at the specified index
        uint256 id = currentWithdrawQueue[prevIndex];
        if (seen[prevIndex]) revert Errors.DuplicateStrategy(id);
        seen[prevIndex] = true;

        newWithdrawQueue[i] = id;
    }

    // Remove strategies not included in the new queue
    for (uint256 i; i < currLength; ++i) {
        if (!seen[i]) {
            uint256 id = currentWithdrawQueue[i];
            DataTypes.Strategy memory strategy = s.strategies[id];

            // Validate strategy can be safely removed
            if (strategy.cap != 0) revert Errors.InvalidStrategyRemovalWithNonZeroCap(id);

            if (strategy.strategy.getAssetBalanceInStrategy() != 0) {
                revert Errors.InvalidStrategyRemovalWithNonZeroAssetBalance(id);
            }

            asset.safeApprove(strategy.strategy, 0);
            delete s.strategyToIndex[strategy.strategy];
            delete s.strategies[id];
        }
    }

    s.withdrawQueue = newWithdrawQueue;

    // Auto-clean supply queue: remove entries pointing to deleted strategies
    if (newLength < currLength) {
        uint256[] memory currentSupplyQueue = s.supplyQueue;
        uint256 supplyLen = currentSupplyQueue.length;

        // Count survivors
        uint256 survivors;
        for (uint256 j; j < supplyLen; ++j) {
            if (s.strategies[currentSupplyQueue[j]].strategy != address(0)) {
                ++survivors;
            }
        }

        // Only rebuild if entries were actually removed
        if (survivors < supplyLen) {
            uint256[] memory cleanedSupplyQueue = new uint256[](survivors);
            uint256 writeIdx;
            for (uint256 j; j < supplyLen; ++j) {
                if (s.strategies[currentSupplyQueue[j]].strategy != address(0)) {
                    cleanedSupplyQueue[writeIdx++] = currentSupplyQueue[j];
                }
            }
            s.supplyQueue = cleanedSupplyQueue;
            supplyQueueCleaned = true;
        }
    }
}
```

**Step 2: Verify build passes**

Run: `cd loan-provider && forge build`
Expected: FAIL — `BTCVault.sol` still calls the old signature (no return capture). That's expected and fixed in Task 2.

**Step 3: Commit (skip — combined with Task 2)**

---

### Task 2: Update `BTCVault.updateWithdrawQueue` to capture return and emit event

**Files:**
- Modify: `loan-provider/src/vaults/btc-vault/BTCVault.sol:292-306`

**Step 1: Update the function to capture return and conditionally emit**

Replace lines 292-306 with:

```solidity
/**
 * @notice Updates the order in which strategies are drained for withdrawals
 * @dev Queue determines priority for fund withdrawal. Strategies excluded from `newWithdrawQueue`
 *      are deleted (requires cap = 0 and balance = 0). Automatically cleans stale entries from
 *      the supply queue when strategies are removed.
 * @param newWithdrawQueue Array of strategy indices in desired withdrawal order
 * @custom:access Requires BVA_SLOW role (1-day delay)
 */
function updateWithdrawQueue(uint256[] memory newWithdrawQueue) external restricted {
    s_strategy.validateNewWithdrawQueue(newWithdrawQueue);

    bool supplyQueueCleaned = s_strategy.updateWithdrawQueue(newWithdrawQueue, i_asset);

    emit BTCVault__WithdrawQueueUpdated(newWithdrawQueue);

    if (supplyQueueCleaned) {
        emit BTCVault__SupplyQueueUpdated(s_strategy.supplyQueue);
    }
}
```

**Step 2: Add comment on `_depositFunds` cap guard**

In `BTCVault.sol`, find the `if (strategy.cap == 0) continue;` line (~729) and replace:

```solidity
// Skip strategies with zero cap
if (strategy.cap == 0) continue;
```

with:

```solidity
// Skip strategies with zero cap (defense-in-depth: also handles any
// stale supply queue entries pointing to deleted strategies)
if (strategy.cap == 0) continue;
```

**Step 3: Verify build passes**

Run: `cd loan-provider && forge build`
Expected: PASS (compiler run successful)

**Step 4: Run existing tests to verify no regressions**

Run: `cd loan-provider && forge test --match-contract WithdrawQueue -vvv`
Expected: All 16 existing tests PASS

**Step 5: Commit**

```bash
git add loan-provider/src/libraries/logic/StrategyStateLogic.sol loan-provider/src/vaults/btc-vault/BTCVault.sol
git commit -n -m "fix: auto-clean supply queue on strategy removal (issue #71)"
```

---

### Task 3: Update `test_SupplyQueue_StaleEntry_SkippedSafely` — supply queue is now auto-cleaned

**Files:**
- Modify: `loan-provider/test/unit/Vault/BTC/WithdrawQueue.t.sol:313-342`

**Step 1: Update the test to verify auto-cleanup instead of stale entry**

The existing test asserts `vault.getSupplyQueueLength() == 2` (stale entry present). After the fix, the supply queue is auto-cleaned, so it should be 1. Replace lines 313-342:

```solidity
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
```

**Step 2: Update `test_DepositAndWithdraw_AfterStrategyRemoval` — remove manual supply queue cleanup**

Replace lines 196-229. The manual `updateSupplyQueue` call (lines 213-216) is no longer needed:

```solidity
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
```

**Step 3: Run tests**

Run: `cd loan-provider && forge test --match-contract WithdrawQueue -vvv`
Expected: All 16 tests PASS (test names changed but count same)

**Step 4: Commit**

```bash
git add loan-provider/test/unit/Vault/BTC/WithdrawQueue.t.sol
git commit -n -m "test: update existing tests for supply queue auto-clean behavior"
```

---

### Task 4: Add 5 new auto-clean tests

**Files:**
- Modify: `loan-provider/test/unit/Vault/BTC/WithdrawQueue.t.sol`

**Step 1: Add tests after the updated `test_SupplyQueue_AutoCleanedOnStrategyRemoval`**

Add these 5 tests after the auto-clean test (after the `assertGt(shares, 0, ...)` closing brace):

```solidity
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

    // Expect SupplyQueueUpdated event
    uint256[] memory expectedSupplyQueue = new uint256[](0);
    vm.expectEmit(true, true, true, true);
    emit BTCVault__SupplyQueueUpdated(expectedSupplyQueue);

    uint256[] memory emptyQueue = new uint256[](0);
    _scheduleAndExecute(bva_slow, bva_slow_id(), abi.encodeCall(BTCVault.updateWithdrawQueue, (emptyQueue)));
}
```

**Step 2: Run all WithdrawQueue tests**

Run: `cd loan-provider && forge test --match-contract WithdrawQueue -vvv`
Expected: All 21 tests PASS (16 existing + 5 new)

**Step 3: Commit**

```bash
git add loan-provider/test/unit/Vault/BTC/WithdrawQueue.t.sol
git commit -n -m "test: add 5 auto-clean tests for supply queue (issue #71)"
```

---

### Task 5: Run full test suite and verify

**Step 1: Run all unit tests**

Run: `cd loan-provider && make test`
Expected: ALL PASS

**Step 2: Run invariant tests**

Run: `cd loan-provider && FOUNDRY_PROFILE=invariant forge test --match-contract BTCVaultInvariantTest`
Expected: ALL PASS

**Step 3: Run format check**

Run: `cd loan-provider && forge fmt --check`
Expected: PASS (or fix and re-commit)
