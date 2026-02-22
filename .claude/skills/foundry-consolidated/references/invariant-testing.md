# Invariant Testing Reference

## Table of Contents
- [Core Concepts](#core-concepts)
- [Handler Pattern](#handler-pattern)
- [Ghost Variables](#ghost-variables)
- [Actor Management](#actor-management)
- [Time Handler Pattern](#time-handler-pattern)
- [Bounded vs Unbounded Handlers](#bounded-vs-unbounded-handlers)
- [Target Configuration](#target-configuration)
- [afterInvariant Hook](#afterinvariant-hook)
- [Coverage-Guided Fuzzing](#coverage-guided-fuzzing)
- [Optimization Mode](#optimization-mode)
- [Configuration Reference](#configuration-reference)
- [Debugging Invariant Failures](#debugging-invariant-failures)
- [Anti-Patterns](#anti-patterns)

## Core Concepts

Invariant tests run randomized sequences of function calls against target contracts. After *each* call in the sequence, all `invariant_*` functions are asserted.

**Campaign dimensions:**
- `runs` -- number of independent call sequences (default: 256)
- `depth` -- function calls per sequence (default: 15). Reverts still increment depth.
- `timeout` -- optional time-based limit (seconds) for long campaigns

**Critical:** Each `invariant_*` function spawns a separate EVM executor. `invariant_A()` and `invariant_B()` never share state. Group related assertions:

```solidity
function invariant_allProperties() external {
    _assertSolvency();
    _assertSupplyConsistency();
    _assertNoNegativeBalances();
}
```

Or use multiple jobs for parallelism:

```solidity
function invariant_job1() public { assertInvariants(); }
function invariant_job2() public { assertInvariants(); }
```

## Handler Pattern

Handlers sit between the fuzzer and protocol contracts to ensure meaningful calls.

### Why Handlers?

Without handlers (open testing), the fuzzer calls protocol functions directly with random inputs. For complex contracts this causes most calls to revert (missing approvals, zero balances, invalid state), wasting the fuzzer's budget.

**Handler goals:**
1. Setup preconditions so calls succeed (mint tokens, approve, set valid state)
2. Track ghost variables for invariant assertions
3. Bound inputs to realistic ranges
4. Manage multiple actors

### Basic Handler Structure

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {MyVault} from "../src/MyVault.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract VaultHandler is Test {
    MyVault public vault;
    MockERC20 public asset;

    // Ghost variables
    uint256 public ghost_totalDeposited;
    uint256 public ghost_totalWithdrawn;

    constructor(MyVault _vault, MockERC20 _asset) {
        vault = _vault;
        asset = _asset;
    }

    function deposit(uint256 amount) external {
        amount = bound(amount, 1, 1e30);

        asset.mint(address(this), amount);
        asset.approve(address(vault), amount);

        uint256 sharesBefore = vault.balanceOf(address(this));
        vault.deposit(amount, address(this));
        uint256 sharesAfter = vault.balanceOf(address(this));

        // Function-level assertion
        assertGt(sharesAfter, sharesBefore, "shares must increase on deposit");

        ghost_totalDeposited += amount;
    }

    function withdraw(uint256 amount) external {
        uint256 maxWithdrawable = vault.maxWithdraw(address(this));
        amount = bound(amount, 0, maxWithdrawable);
        if (amount == 0) return;

        vault.withdraw(amount, address(this), address(this));
        ghost_totalWithdrawn += amount;
    }
}
```

### Registering the Handler

```solidity
contract VaultInvariantTest is Test {
    MyVault vault;
    MockERC20 asset;
    VaultHandler handler;

    function setUp() public {
        asset = new MockERC20("Token", "TKN", 18);
        vault = new MyVault(address(asset));
        handler = new VaultHandler(vault, asset);

        // CRITICAL: only the handler is targeted
        targetContract(address(handler));
    }

    function invariant_solvency() external {
        assertGe(
            asset.balanceOf(address(vault)),
            handler.ghost_totalDeposited() - handler.ghost_totalWithdrawn()
        );
    }
}
```

## Ghost Variables

Ghost variables track derived state across function calls that isn't directly queryable from the protocol. They bridge the gap between what the protocol stores and what the invariant needs to assert.

### Common Ghost Variable Patterns

```solidity
contract Handler is Test {
    // Running totals
    uint256 public ghost_depositSum;
    uint256 public ghost_withdrawSum;

    // Per-actor tracking
    mapping(address => uint256) public ghost_userDeposits;

    // Aggregate tracking
    uint256 public ghost_sumBalanceOf; // sum of all LP token balances
    address[] public ghost_actors;     // all addresses that have interacted

    function deposit(uint256 assets, uint256 actorSeed) external {
        address actor = _getActor(actorSeed);
        assets = bound(assets, 1, 1e30);

        // ... setup and call ...

        uint256 shares = vault.deposit(assets, actor);
        ghost_depositSum += assets;
        ghost_userDeposits[actor] += assets;
        ghost_sumBalanceOf += shares;
    }
}
```

### Warning About Ghost Variables

Avoid replicating protocol logic in ghost variables. If both the protocol and the ghost have the same bug, your test won't catch it. Prefer querying external state from the contract under test when possible:

```solidity
// PREFER: query actual contract state
function invariant_balanceSumMatchesSupply() external {
    uint256 sum;
    for (uint256 i; i < handler.actorCount(); i++) {
        sum += vault.balanceOf(handler.actors(i));
    }
    assertEq(sum, vault.totalSupply());
}

// AVOID: relying solely on ghost replication of the same logic
```

## Actor Management

Simulate multiple users with a `useActor` modifier:

```solidity
contract Handler is Test {
    address[] public actors;
    address internal currentActor;

    modifier useActor(uint256 actorIndexSeed) {
        currentActor = actors[bound(actorIndexSeed, 0, actors.length - 1)];
        vm.startPrank(currentActor);
        _;
        vm.stopPrank();
    }

    constructor() {
        actors.push(makeAddr("alice"));
        actors.push(makeAddr("bob"));
        actors.push(makeAddr("charlie"));
    }

    function deposit(uint256 amount, uint256 actorSeed) external useActor(actorSeed) {
        amount = bound(amount, 1, 1e30);
        deal(address(asset), currentActor, amount);
        asset.approve(address(vault), amount);
        vault.deposit(amount, currentActor);
        ghost_userDeposits[currentActor] += amount;
    }

    function actorCount() external view returns (uint256) {
        return actors.length;
    }
}
```

## Time Handler Pattern

Time is a first-class dimension in DeFi testing. Use a dedicated time handler to systematically test time-dependent behavior.

### Basic Time Handler

```solidity
contract TimeHandler is Test {
    uint256 public ghost_totalTimeAdvanced;
    uint256 public ghost_warpCount;

    // Small time jumps (minutes to hours) -- most common in practice
    function warpShort(uint256 seconds_) external {
        seconds_ = bound(seconds_, 1 minutes, 24 hours);
        vm.warp(block.timestamp + seconds_);
        vm.roll(block.number + seconds_ / 12);
        ghost_totalTimeAdvanced += seconds_;
        ghost_warpCount++;
    }

    // Medium time jumps (days to weeks) -- payment intervals, grace periods
    function warpMedium(uint256 seconds_) external {
        seconds_ = bound(seconds_, 1 days, 30 days);
        vm.warp(block.timestamp + seconds_);
        vm.roll(block.number + seconds_ / 12);
        ghost_totalTimeAdvanced += seconds_;
        ghost_warpCount++;
    }

    // Large time jumps (months) -- loan durations, staking periods
    function warpLong(uint256 seconds_) external {
        seconds_ = bound(seconds_, 30 days, 365 days);
        vm.warp(block.timestamp + seconds_);
        vm.roll(block.number + seconds_ / 12);
        ghost_totalTimeAdvanced += seconds_;
        ghost_warpCount++;
    }
}
```

### Why Multiple Warp Functions?

Having 3 warp functions (instead of 1) gives each function equal call probability in the fuzzer, so time-related actions get called more frequently. This also ensures a mix of short and long time jumps, which is more realistic than uniformly random intervals.

### Time Handler for Lending Protocols

```solidity
contract LendingTimeHandler is Test {
    IPool pool;
    uint256 public ghost_totalTimeAdvanced;

    constructor(IPool _pool) {
        pool = _pool;
    }

    // Advance to next payment due date
    function warpToNextPayment(uint256 lsaSeed) external {
        address lsa = _pickActiveLoan(lsaSeed);
        if (lsa == address(0)) return;

        uint256 nextDue = pool.getNextPaymentDue(lsa);
        if (nextDue > block.timestamp) {
            uint256 advance = nextDue - block.timestamp;
            vm.warp(nextDue);
            vm.roll(block.number + advance / 12);
            ghost_totalTimeAdvanced += advance;
        }
    }

    // Advance past grace period (triggers overdue state)
    function warpPastGracePeriod(uint256 lsaSeed) external {
        address lsa = _pickActiveLoan(lsaSeed);
        if (lsa == address(0)) return;

        uint256 nextDue = pool.getNextPaymentDue(lsa);
        uint256 gracePeriod = pool.getGracePeriod();
        uint256 target = nextDue + gracePeriod + 1;
        if (target > block.timestamp) {
            uint256 advance = target - block.timestamp;
            vm.warp(target);
            vm.roll(block.number + advance / 12);
            ghost_totalTimeAdvanced += advance;
        }
    }
}
```

### Balancing Time Handler Call Distribution

The fuzzer distributes calls uniformly across all handler functions. If your time handler has 3 functions and your main handler has 6, time functions get called ~33% of the time total. Tune this ratio by:

1. **Adding more functions** to the handler you want called more often
2. **Using `targetSelector`** to explicitly weight function selection
3. **Splitting into separate handlers** with different function counts

```solidity
// Example: ensure time advances happen ~20% of the time
// Main handler: 8 functions (deposit, withdraw, borrow, repay, ...)
// Time handler: 2 functions (warpShort, warpLong)
// Result: each time function = 10% of calls = 20% total for time
```

Monitor actual distribution with `show_metrics = true` in config.

## Bounded vs Unbounded Handlers

Use inheritance to maintain both testing modes:

```solidity
// Unbounded: for fail_on_revert = false testing
contract HandlerUnbounded is Test {
    function deposit(uint256 assets) public virtual {
        asset.mint(address(this), assets);
        asset.approve(address(vault), assets);
        uint256 shares = vault.deposit(assets, address(this));
        ghost_sumBalanceOf += shares;
    }
}

// Bounded: for fail_on_revert = true testing
contract HandlerBounded is HandlerUnbounded {
    function deposit(uint256 assets) public override {
        assets = bound(assets, 0, 1e30);
        super.deposit(assets);
    }
}
```

**When to use which:**
- `fail_on_revert = false` + unbounded -- explore what *can* go wrong, including unexpected reverts
- `fail_on_revert = true` + bounded -- every call must succeed; high confidence in test quality

## Target Configuration

### Helper Functions (from forge-std)

| Function | Purpose |
|---|---|
| `targetContract(address)` | Add to targeted contracts (overrides auto-detection) |
| `excludeContract(address)` | Remove from targets |
| `targetSelector(FuzzSelector)` | Target specific functions only |
| `excludeSelector(FuzzSelector)` | Exclude specific functions |
| `targetSender(address)` | Restrict msg.sender values |
| `excludeSender(address)` | Exclude specific senders |
| `targetInterface(FuzzInterface)` | Target non-deployed addresses (proxies, forked contracts) |

### Selector Targeting

```solidity
function setUp() public {
    // Only fuzz deposit and withdraw, not admin functions
    bytes4[] memory selectors = new bytes4[](2);
    selectors[0] = Handler.deposit.selector;
    selectors[1] = Handler.withdraw.selector;
    targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
}
```

### Call Distribution

Functions are called with uniform probability across all target contracts:

```
handler1 (2 functions): deposit 25%, withdraw 25%
handler2 (2 functions): borrow 25%,  repay 25%
```

Contracts with fewer functions get higher per-function call rates. Design handlers accordingly.

**Tuning distribution:** If you need non-uniform call weights, you have three options:

1. **Add wrapper functions** that call the same underlying function (gives 2x weight)
2. **Use `targetSelector`** to include/exclude specific selectors per handler
3. **Split handlers** so the handler with more important functions has fewer total functions

Always verify actual distribution with `show_metrics = true`:
```
[METRICS] handler1::deposit - calls: 127, reverts: 3
[METRICS] handler1::withdraw - calls: 125, reverts: 12
[METRICS] timeHandler::warp - calls: 124, reverts: 0
```

If any handler function shows >80% revert rate, the handler needs better precondition setup.

## afterInvariant Hook

Called at the end of each invariant run. Use for:

```solidity
function afterInvariant() public {
    // 1. Log campaign metrics
    console.log("Total deposits:", handler.ghost_depositSum());
    console.log("Total withdraws:", handler.ghost_withdrawSum());

    // 2. Assert exit conditions (all funds withdrawable)
    for (uint256 i; i < handler.actorCount(); i++) {
        address actor = handler.actors(i);
        uint256 balance = vault.balanceOf(actor);
        if (balance > 0) {
            vm.prank(actor);
            vault.redeem(balance, actor, actor);
        }
    }
    assertEq(vault.totalSupply(), 0, "All positions must be closeable");
}
```

## Coverage-Guided Fuzzing

Enabled via `corpus_dir` config. Foundry v1.3.0+. Stores and mutates call sequences that produce new code coverage.

```toml
[invariant]
corpus_dir = "invariant-corpus"  # persistence path
```

Also available for regular fuzz tests:

```toml
[fuzz]
corpus_dir = "fuzz-corpus"  # persistence path for fuzz test inputs
```

**Mutation strategies:** splice, interleave, prefix, suffix, mutate-args.

**Progress metrics displayed:**
- `cumulative edges seen` -- unique code branches hit
- `cumulative features seen` -- unique coverage features
- `corpus count` -- active corpus entries
- `favored items` -- entries producing unique coverage

**Enable storage layout for smarter fuzzing:**
```toml
extra_output = ["storageLayout"]
```

## Optimization Mode

Find the call sequence that maximizes a return value. Useful for worst-case rounding errors, max gas, edge cases.

Return `int256` from an invariant function:

```solidity
function invariant_maxRoundingError() public view returns (int256) {
    return int256(vault.totalAssets()) - int256(vault.totalSupply());
}
```

Foundry automatically detects the return type and optimizes. Output shows the best value and shrunk sequence.

## Configuration Reference

```toml
[invariant]
runs = 256                   # call sequences to generate
depth = 15                   # calls per sequence
fail_on_revert = false       # fail if any call reverts
call_override = false        # override unsafe external calls (reentrancy checks)
dictionary_weight = 80       # % of inputs from dictionary
include_storage = true       # sample from contract storage
include_push_bytes = true    # sample from bytecode
shrink_run_limit = 5000      # max attempts to shrink failing sequence
max_assume_rejects = 65536   # max vm.assume() rejects per run
gas_report_samples = 256     # samples for gas reports
corpus_dir = ""              # enable coverage-guided fuzzing
show_metrics = false         # show selector call breakdown
```

## Debugging Invariant Failures

1. **Read the failing sequence** -- Forge prints the exact calls that broke the invariant
2. **Check `show_metrics`** -- are handlers being called? Are most calls reverting?
3. **Increase verbosity** -- `forge test -vvvv` shows internal call traces
4. **Shrinking** -- Forge automatically shrinks failing sequences to the minimal reproducing case
5. **Replay** -- use `fail_dir` config to persist and replay failures
6. **Unit test the sequence** -- copy the counterexample into a deterministic test

## Anti-Patterns

### Conditional Invariants (False Positives)

```solidity
// BAD: if condition is always true, invariant is never checked
function invariant_bad() external {
    if (someCondition) return;
    assertEq(a, b);
}

// GOOD: assert something for every code path
function invariant_good() external {
    if (someCondition) {
        assertLe(a, b);
    } else {
        assertEq(a, b);
    }
}
```

### Unbounded Open Testing on Complex Contracts

If most fuzz calls revert (>80%), the test provides false confidence. Use handlers with bounded inputs and check `show_metrics` output.

### Ghost Variables Replicating Protocol Logic

If your ghost variable computes the same formula as the protocol, bugs in the formula pass both. Query on-chain state instead.

### Too Low Depth

Default `depth = 15` is often too shallow for multi-step DeFi flows (deposit -> borrow -> time passes -> liquidate). Increase to 50-100+ for complex protocols.

### Not Using afterInvariant for Exit Assertions

The fuzzer tests *during* operation. Use `afterInvariant()` to verify the system can also unwind cleanly (e.g., all LPs can exit, all loans can be repaid).
