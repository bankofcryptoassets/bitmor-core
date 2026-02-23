---
name: foundry-consolidated
description: Consolidated Foundry testing skill for writing production-grade smart contract tests. Use when writing unit tests, fuzz tests (testFuzz_ prefix), invariant tests (invariant_ prefix), handler contracts, or reviewing test quality. Covers test type selection, workflow, assertion quality, security testing, and fuzz/invariant configuration. For naming conventions, Arrange-Act-Assert, base classes, helpers, TC constants, mock infrastructure, and common patterns, see the always-loaded rules files.
---

# Foundry Testing (Consolidated)

> **Note:** Naming conventions, Arrange-Act-Assert, setUp rules, assertion messages, event/revert testing, base class hierarchy, TC constants, mock infrastructure, test helpers, access control patterns, common test patterns, and AI anti-patterns 1-6 are covered by the always-loaded rules files (`bitmor-testing.md` and `foundry-testing.md`). This skill covers everything else.

> **Testing Objective:** Tests exist to break things. Your job is to find defects in the contract code, not to confirm that the code works by writing assertions that mirror it. A passing test suite is not a success metric — a test suite that would catch real bugs is.

## 1. Test Type Decision Framework

```
Unit test:  "Does f(42) == expected?"            -> spot-check a specific input
Fuzz test:  "Does property P hold for all x?"    -> generalize to full input space
Invariant:  "Does property P hold across ALL     -> stateful generalized check
             sequences of operations?"
```

- **Single function, many inputs** -> Fuzz test (`testFuzz_` prefix)
- **System-wide property, random call sequences** -> Invariant test (`invariant_` prefix)
- **Both** -> Fuzz for per-function properties, invariant for cross-function/system invariants

### When Fuzz Testing Adds Value Over Unit Tests

Fuzz tests **generalize** unit test properties to the full input space. If a property holds for one input, it should hold for all valid inputs.

**Fuzz these:**
- Any property that holds across a range of inputs (amounts, durations, prices)
- Continuous spaces between the specific points unit tests sample
- Arithmetic that could overflow, underflow, or round incorrectly at edge cases

**Don't fuzz these (unit test territory):**
- Deterministic checks: zero is zero, paused is paused -- no input space to explore
- Access control: either you have the role or you don't -- boolean, not a range
- Exact boundary values: `minBTC - 1` is always `minBTC - 1` -- no fuzz value
- Specific error messages with specific inputs

**Unit tests remain valuable for:**
- Regression tests for specific bugs found during audits
- Documentation of known edge cases with exact inputs/outputs
- Speed -- faster than 256+ fuzz runs for quick CI feedback
- Exact error selectors with exact parameter values

## 2. Test Writing Workflow

Five phases. For project-specific details (base classes, helpers, TC constants), see the rules files.

1. **UNDERSTAND** -- Read the contract source. List all public/external functions, access control, custom errors, events.
2. **PLAN** -- For each function, list test scenarios: happy path, reverts, edge cases, fuzz candidates. Output a checklist of test names.
3. **SETUP** -- Choose the correct base class (see rules: Tier system table). Identify which helpers you need.
4. **WRITE** -- Arrange-Act-Assert. Use TC constants, specific error selectors, descriptive assertion messages. One behavior per test.
5. **VERIFY** -- Run tests (`forge test --match-path ... -vvv`), check coverage, fix failures. Loop back to WRITE if needed.

## 3. Assertion Quality

### Mirror Test Anti-Pattern (CRITICAL)

**Never re-implement the production formula in your assertion.** If `RepayLogic` computes `periods = amount / monthly` and your test asserts `duration_change == amount / monthly`, you've written `x == x`. This test can never fail.

```solidity
// BAD: mirrors RepayLogic exactly -- this is x == x
uint256 expectedPeriods = repaidAmount / monthlyPayment;
assertEq(loan.remainingPeriods(), originalPeriods - expectedPeriods);

// GOOD: tests a business property that doesn't depend on the formula
assertLe(loanAfter.remainingDuration, loanBefore.remainingDuration,
    "duration must not increase after repayment");
assertEq(mockCbBTC.balanceOf(lsa), collateralBefore,
    "collateral must not change on partial repayment");
```

**Validation question:** For every fuzz test, ask: *"If I changed the production formula to something subtly wrong (e.g., ceiling instead of floor division), would this test still pass?"* If yes, the test is circular and must be rewritten.

This applies equally to ghost variables in invariant tests. If both the protocol and the ghost compute the same formula, bugs in the formula pass both. Prefer querying on-chain contract state directly.

### Red Flags Checklist

If any of these apply, rewrite the assertion:

- Assertion contains the same math operator as the code under test
- Test would pass even if the code was completely wrong (e.g., returned 0)
- Fuzz input only varies the magnitude, not the scenario
- Mock is configured to return exactly what the test expects
- Test name says "invariant" but the assertion is just `x == f(x)` where f mirrors production code

## 3b. Approximate Assertions for DeFi

DeFi math involves rounding, so exact equality often fails on valid results. Use approximate assertions:

### `assertApproxEqAbs` -- Absolute Tolerance

Use when the expected rounding error is a fixed number of units (e.g., 1 wei, 1 unit of token dust):

```solidity
// ERC-4626 deposit/redeem roundtrip -- rounding may lose up to 1 unit
uint256 shares = vault.deposit(assets, user);
uint256 redeemed = vault.redeem(shares, user, user);
assertApproxEqAbs(redeemed, assets, 1, "roundtrip loss must be at most 1 wei");

// Lending math -- interest accrual may have minor rounding
uint256 actualDebt = pool.getUserDebt(borrower);
assertApproxEqAbs(actualDebt, expectedDebt, 1e2, "debt within 100 wei of expected");
```

### `assertApproxEqRel` -- Relative Tolerance (Percentage)

Use when acceptable error scales with the value (e.g., "within 0.01%"). The tolerance is in WAD (1e18 = 100%):

```solidity
// Share price should stay within 1% of expected after yield accrual
uint256 sharePrice = vault.convertToAssets(1e18);
assertApproxEqRel(sharePrice, expectedPrice, 0.01e18, "share price within 1%");

// Oracle price deviation check
uint256 oraclePrice = oracle.getAssetPrice(asset);
assertApproxEqRel(oraclePrice, expectedPrice, 0.005e18, "oracle within 0.5%");
```

### When to Use Which

| Scenario | Assertion | Tolerance |
|----------|-----------|-----------|
| Token rounding (small fixed error) | `assertApproxEqAbs` | 1-10 wei |
| Interest accrual math | `assertApproxEqAbs` | Scale with decimals |
| Share price after many operations | `assertApproxEqRel` | 0.01e18 (1%) |
| Fuzz test roundtrip properties | `assertApproxEqAbs` | 1-2 units |
| Price feed comparisons | `assertApproxEqRel` | 0.005e18 (0.5%) |

**Anti-pattern:** Don't use `>=`/`<=` as a loose substitute. It hides whether the error is 1 wei or 1 million. Approximate assertions report the *actual* delta on failure.

## 4. Business Invariant Categories

Write tests from an auditor's perspective. Six categories of properties that make strong fuzz/invariant assertions:

1. **State integrity** -- Variables that should never change during an operation
   - "Collateral must not change during partial repayment"
   - "Total supply must equal sum of all balances"

2. **Token flow integrity** -- No tokens should leak or accumulate
   - "Contract must hold zero residual tokens after operation"
   - "Payer balance + contract balance + pool balance = constant"

3. **Economic properties** -- Financial guarantees
   - "Health ratio must improve when debt decreases"
   - "Cumulative extraction must never exceed original obligation"

4. **Transition safety** -- State changes are correct and irreversible
   - "Completed loan must reject further repayments"
   - "Status can only move forward, never backward"

5. **Path equivalence** -- Different execution paths yield consistent results
   - Use `vm.snapshot()`/`vm.revertTo()` to compare alternative paths
   - "Lump payment vs split payment should credit >= periods"
   - "Order of operations should not affect final state"

6. **Edge case resistance** -- Extreme inputs don't corrupt state
   - "Dust amounts must not change loan status"
   - "Max uint128 input must be handled gracefully"

## 5. Security Testing Checklist

Before considering tests complete, verify coverage for:

### Access Control
- [ ] All admin functions revert for non-admins
- [ ] Role-based permissions enforced correctly
- [ ] Ownership transfer works and is protected

### Reentrancy
- [ ] External calls tested with malicious callbacks
- [ ] State changes before external calls
- [ ] Cross-function reentrancy considered

### Economic Attacks
- [ ] Flash loan attack scenarios
- [ ] Price manipulation resistance
- [ ] Front-running protection tested

### Input Validation
- [ ] Zero address handling
- [ ] Zero amount handling
- [ ] Overflow/underflow (even with Solidity 0.8+)
- [ ] Array length limits

### Oracle Dependencies
- [ ] Stale price handling
- [ ] Price deviation limits
- [ ] Oracle failure graceful handling

## 6. Quality Standards

### Coverage Thresholds

| Category | Minimum | Target |
|----------|---------|--------|
| Line Coverage | 80% | 95% |
| Branch Coverage | 70% | 90% |
| Core Business Logic | 90% | 100% |

### Test Maturity Phases

1. **BASIC** -- Unit tests for all public functions
2. **INTERMEDIATE** -- + Integration tests, access control, events
3. **ADVANCED** -- + Fuzz testing, invariant testing
4. **PRODUCTION** -- + Security tests, fork tests, gas benchmarks

### Risk-Based Test Priority

When time is limited, prioritize based on contract risk:

| Contract Type | Risk | Testing Priority |
|--------------|------|------------------|
| Token/Value handling | HIGH | Full coverage + invariants + security |
| Access control | HIGH | Full coverage + fuzzing |
| External integrations | MEDIUM-HIGH | Fork tests + failure modes |
| View functions | LOW | Basic unit tests |
| Pure utilities | LOW | Unit tests + edge cases |

### Pre-Commit Checklist

1. [ ] `forge test` passes
2. [ ] `forge coverage` meets thresholds
3. [ ] No circular logic in assertions (mirror test check)
4. [ ] Mocks test actual logic, not themselves
5. [ ] Negative test cases included
6. [ ] Fuzz tests have meaningful bounds
7. [ ] Each test is independent (no state leakage)
8. [ ] Descriptive assertion messages on all asserts
9. [ ] Events tested where emitted
10. [ ] Access control tested for all restricted functions

## 7. Fuzz & Invariant Testing

### Fuzz Testing (Stateless)

Any test function with parameters is automatically fuzzed. Forge generates random inputs across configurable runs.

Key patterns: `bound()` for constraining inputs (preferred), `vm.assume()` for simple exclusions (use sparingly), narrower types for natural range limits, fixture arrays/functions for targeted edge cases.

For detailed patterns (bound vs assume, type narrowing, fixtures, DeFi fuzz patterns, fuzz strategy framework, debugging), see [references/fuzz-testing.md](references/fuzz-testing.md).

### Invariant Testing (Stateful)

Invariant tests assert conditions that must hold after *any* random sequence of function calls. Two campaign dimensions: `runs` (number of call sequences) x `depth` (calls per sequence).

**Critical:** Each `invariant_*` function gets its own EVM executor -- they do NOT share state. Group related assertions in one function.

For complex contracts, use **handler-based testing**: wrap protocol calls in a Handler that sets up preconditions, bounds inputs, and tracks ghost variables. Register the handler via `targetContract()`.

For detailed patterns (handlers, ghost variables, actor management, bounded/unbounded, time handlers, afterInvariant, coverage-guided fuzzing, optimization, anti-patterns), see [references/invariant-testing.md](references/invariant-testing.md).

### Configuration

```toml
[fuzz]
runs = 1000            # scenarios per fuzz test (default: 256)
seed = '0x1'           # reproducible runs
dictionary_weight = 40 # % chance to pull values from storage

[invariant]
runs = 256             # call sequences (default: 256)
depth = 50             # calls per sequence (default: 15)
fail_on_revert = false # set true with bounded handlers
show_metrics = true    # show selector call distribution
# corpus_dir = "invariant-corpus"  # enable coverage-guided fuzzing
```

### Inline Config (Per-Test Override)

```solidity
/// forge-config: default.fuzz.runs = 10000
function testFuzz_critical(uint256 x) external { ... }

/// forge-config: default.invariant.runs = 500
/// forge-config: default.invariant.depth = 100
function invariant_critical() external { ... }
```

### DeFi Invariants Catalog

For a comprehensive catalog of DeFi invariant patterns (ERC-20, ERC-4626, ERC-4626 attack patterns, lending, AMMs, stablecoins, staking, state machines, time-dependent properties), see [references/defi-invariants.md](references/defi-invariants.md).

## 8. Fuzz/Invariant Suite Checklist

1. **Identify invariants** -- list all properties that must always hold, using the 6 business invariant categories as a thinking framework
2. **Validate against the mirror test** -- for each assertion, ask: "Would this catch a subtle formula bug?" If not, rewrite
3. **Choose test type** -- fuzz for per-function, invariant for system-wide
4. **Design handlers** -- one handler per domain; bound inputs; track ghost variables
5. **Manage actors** -- use `prank` + actor arrays for multi-user simulation
6. **Configure runs/depth** -- balance thoroughness vs CI time; use `show_metrics = true`
7. **Enable coverage-guided fuzzing** for critical invariants via `corpus_dir`
8. **Use `afterInvariant()`** to assert exit conditions (e.g., all positions closeable)
9. **Check red flags** -- review assertions for circular logic, mock cheating, missing scenarios
