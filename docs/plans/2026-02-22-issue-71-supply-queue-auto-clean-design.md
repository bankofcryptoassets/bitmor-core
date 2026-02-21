# Issue #71: Supply Queue Auto-Clean on Strategy Removal

## Problem

When a strategy is removed via `updateWithdrawQueue`, the supply queue retains stale entries pointing to the deleted strategy. The `cap == 0` guard in `_depositFunds` (BTCVault.sol:729) prevents functional breakage, but stale entries waste gas on every user deposit and create an admin footgun (two-step cleanup requirement).

MetaMorpho has the same design pattern and tolerates stale entries, but Bitmor uses index-based supply queue entries (harder to reason about than MetaMorpho's stable market IDs), making auto-cleanup more valuable.

## Approach

**Auto-clean inside `StrategyStateLogic.updateWithdrawQueue`**: After the deletion loop removes strategies, filter the supply queue to remove entries pointing to deleted (`address(0)`) strategies. This makes the cleanup atomic with the removal operation.

## Production Code Changes

### 1. `StrategyStateLogic.updateWithdrawQueue` (StrategyStateLogic.sol)

After the deletion loop (line 141) and before `s.withdrawQueue = newWithdrawQueue` (line 143):

- Two-pass filter: count survivors in supply queue, then build a cleaned array
- Check `s.strategies[supplyQueue[j]].strategy != address(0)` (accurate because `delete s.strategies[id]` just ran)
- Assign `s.supplyQueue = cleanedSupplyQueue`
- Return `bool supplyQueueCleaned` so the caller knows whether to emit an event

Update NatSpec: replace the "IMPORTANT: does NOT clean supply queue" warning with documentation that auto-cleanup is performed.

### 2. `BTCVault.updateWithdrawQueue` (BTCVault.sol)

- Capture the `bool` return from the library call
- Conditionally emit `BTCVault__SupplyQueueUpdated` when the supply queue was modified
- Update NatSpec to reflect automatic supply queue cleanup

### 3. `BTCVault._depositFunds` comment (BTCVault.sol:729)

Add clarifying comment on the `cap == 0` guard explaining it as a defense-in-depth safety fallback.

## Event Handling

The library cannot emit `BTCVault__SupplyQueueUpdated` (defined in `BTCVault__Storage`). The return-bool pattern lets `BTCVault.sol` handle event emission. The event is important for off-chain indexers tracking queue state.

## Tests (WithdrawQueue.t.sol)

### New tests (5)

1. `test_updateWithdrawQueue_AutoCleansSupplyQueue` -- supply queue shrinks after removal
2. `test_updateWithdrawQueue_AutoCleansSupplyQueue_MultipleRemovals` -- remove 2/3 strategies
3. `test_updateWithdrawQueue_SupplyQueueOrderPreserved` -- surviving entries keep relative order
4. `test_updateWithdrawQueue_NoRemoval_SupplyQueueUnchanged` -- reorder-only leaves supply queue intact
5. `test_updateWithdrawQueue_EmitsSupplyQueueUpdated` -- event emitted on auto-clean

### Existing test update (1)

- `test_DepositAndWithdraw_AfterStrategyRemoval` -- remove manual `updateSupplyQueue` call, verify deposits work without it

## Gas Impact

Two extra iterations over `supplyQueue` inside an admin-only, time-delayed function. Negligible cost; user-facing `_depositFunds` actually saves gas by having fewer entries to iterate.

## Security Considerations

- No external calls during cleanup (no reentrancy risk)
- Filtering uses `address(0)` check which is set by `delete s.strategies[id]` in the same function
- The `cap == 0` guard in `_depositFunds` remains as defense-in-depth
- `maxStrategies` already bounds queue length
