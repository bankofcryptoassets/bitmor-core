# Fuzz Testing Reference

## How It Works

Forge treats any test function with at least one parameter as a fuzz test. It generates random inputs for each parameter across configurable runs. The function's assertions are checked for each generated input set.

## Input Constraining Strategies

### `bound()` vs `vm.assume()`

**Prefer `bound()`** -- maps any input to a valid range. No wasted runs.

```solidity
function testFuzz_deposit(uint256 amount) public {
    amount = bound(amount, 1 ether, 100 ether); // always valid
    vault.deposit{value: amount}();
    assertEq(vault.balanceOf(address(this)), amount);
}
```

**Use `vm.assume()` sparingly** -- discards the entire input set and retries. Too many discards waste fuzzer budget and can hit the `max_test_rejects` limit (default: 65536).

```solidity
function testFuzz_transfer(address to, uint256 amount) public {
    vm.assume(to != address(0));        // simple exclusion: ok
    vm.assume(amount > 0);
    // avoid: vm.assume(amount > 1e18 && amount < 2e18); // too narrow, use bound()
}
```

### Type Narrowing

Use smaller integer types to naturally constrain value ranges. Test contracts receive `2**96 wei` by default:

```solidity
function testFuzz_smallAmounts(uint96 amount) public { ... }   // max ~79 ETH
function testFuzz_percentages(uint8 pct) public {               // 0-255
    pct = uint8(bound(pct, 1, 100));
}
```

### Combining Constraints

```solidity
function testFuzz_complexSetup(
    uint256 depositAmount,
    uint256 withdrawAmount,
    uint256 actorSeed
) public {
    depositAmount = bound(depositAmount, 1, 1e30);
    withdrawAmount = bound(withdrawAmount, 0, depositAmount); // withdraw <= deposit
    address actor = actors[bound(actorSeed, 0, actors.length - 1)];

    vm.startPrank(actor);
    deal(address(token), actor, depositAmount);
    token.approve(address(vault), depositAmount);
    vault.deposit(depositAmount, actor);
    vault.withdraw(withdrawAmount, actor, actor);
    vm.stopPrank();

    assertGe(vault.balanceOf(actor), 0);
}
```

## Fixtures

Fixtures ensure specific values appear in the fuzz corpus, useful for known edge cases.

### Storage Array Fixtures

Prefix with `fixture` + parameter name. Type must match:

```solidity
uint32[] public fixtureAmount = [0, 1, type(uint32).max];
address[] public fixtureRecipient = [address(0), address(1)];
```

### Function Fixtures

Return a dynamic or fixed-size array:

```solidity
function fixtureOwner() public returns (address[] memory) {
    address[] memory addrs = new address[](3);
    addrs[0] = makeAddr("alice");
    addrs[1] = makeAddr("bob");
    addrs[2] = address(this);
    return addrs;
}
```

### Correlated Fixtures

When two parameters must be related (e.g., a hash derived from an address):

```solidity
address[] public fixtureYay = [
    makeAddr("yay1"), makeAddr("yay2")
];
bytes32[] public fixtureSlate = [
    keccak256(abi.encodePacked(makeAddr("yay1"))),
    keccak256(abi.encodePacked(makeAddr("yay2")))
];
```

## Configuration

```toml
[fuzz]
runs = 256                 # number of fuzz inputs per test (default: 256)
seed = '0x1'               # fixed seed for reproducibility
max_test_rejects = 65536   # max vm.assume() rejections before failure
dictionary_weight = 40     # % of inputs from contract storage values
include_storage = true     # sample values from storage
include_push_bytes = true  # sample values from bytecode PUSH ops
show_logs = false           # show console.log in fuzz tests (needs -vv)
```

Per-test inline override:

```solidity
/// forge-config: default.fuzz.runs = 10000
/// forge-config: default.fuzz.seed = 0xdeadbeef
function testFuzz_critical(uint256 x) external { ... }
```

## Fuzz Strategy Framework

Six named property categories for systematic fuzz test design. Use this as a decision table when planning which properties to fuzz.

| Strategy | Property | Template | Example |
|----------|----------|----------|---------|
| **Round-trip** | `f_inv(f(x)) ≈ x` | Apply operation, then its inverse, verify original state | deposit then withdraw returns original assets (within rounding) |
| **Monotonicity** | `x > y ⇒ f(x) ≥ f(y)` | Larger input produces larger-or-equal output | more assets deposited => more shares minted |
| **Conservation** | `sum_before == sum_after` | Total tokens/value unchanged across an operation | user balance + vault balance = constant after deposit |
| **Equivalence** | `f_batch(xs) == Σf(xi)` | Batch operation equals sum of individual operations | one deposit of 100 == two deposits of 50 |
| **Commutativity** | `f(g(x)) == g(f(x))` | Order of operations doesn't affect final result | deposit then price change == price change then deposit (for share count) |
| **Idempotency** | `f(f(x)) == f(x)` | Applying operation twice has same effect as once | claiming rewards twice doesn't double-pay |

### Applying the Framework

For each function under test, walk through the table and ask: "Does this strategy apply?" Not every function has all six, but most have at least two.

```solidity
// Round-trip: deposit/withdraw
function testFuzz_roundtrip(uint96 amount) public {
    amount = bound(amount, 1, type(uint96).max);
    uint256 before = token.balanceOf(user);
    uint256 shares = vault.deposit(amount, user);
    vault.redeem(shares, user, user);
    assertApproxEqAbs(token.balanceOf(user), before, 1, "roundtrip within 1 wei");
}

// Conservation: no tokens leak
function testFuzz_conservation(uint96 amount) public {
    amount = bound(amount, 1, type(uint96).max);
    uint256 totalBefore = token.balanceOf(user) + token.balanceOf(address(vault));
    vault.deposit(amount, user);
    uint256 totalAfter = token.balanceOf(user) + token.balanceOf(address(vault));
    assertEq(totalAfter, totalBefore, "tokens must be conserved");
}

// Equivalence: batch vs individual
function testFuzz_equivalence(uint96 a, uint96 b) public {
    a = bound(a, 1, type(uint96).max / 2);
    b = bound(b, 1, type(uint96).max / 2);

    uint256 snap = vm.snapshot();
    uint256 sharesBatch = vault.deposit(uint256(a) + b, user);
    vm.revertTo(snap);

    uint256 sharesA = vault.deposit(a, user);
    uint256 sharesB = vault.deposit(b, user);
    assertApproxEqAbs(sharesBatch, sharesA + sharesB, 1, "batch == individual");
}
```

## Fuzz Testing Patterns for DeFi

### Deposit/Withdraw Symmetry
```solidity
function testFuzz_depositWithdrawRoundtrip(uint96 amount) public {
    vm.assume(amount > 0);
    uint256 balBefore = token.balanceOf(address(this));
    vault.deposit(amount);
    vault.withdraw(amount);
    assertEq(token.balanceOf(address(this)), balBefore);
}
```

### Monotonicity (shares increase with assets)
```solidity
function testFuzz_sharesMonotonic(uint96 a, uint96 b) public {
    vm.assume(a > 0 && b > a);
    uint256 sharesA = vault.previewDeposit(a);
    uint256 sharesB = vault.previewDeposit(b);
    assertGe(sharesB, sharesA, "More assets must yield >= shares");
}
```

### Rounding Direction
```solidity
function testFuzz_roundingFavorsVault(uint96 assets) public {
    vm.assume(assets > 0);
    uint256 shares = vault.previewDeposit(assets);
    uint256 redeemable = vault.previewRedeem(shares);
    assertLe(redeemable, assets, "Rounding must favor vault");
}
```

## Debugging Fuzz Failures

1. **Read the counterexample** -- Forge prints the failing args and calldata
2. **Reproduce** -- Copy counterexample into a unit test for deterministic debugging
3. **Replay** -- `forge test --replay` replays saved failure sequences from `cache/`
4. **Increase verbosity** -- `forge test -vvvv` shows full traces including internal calls
5. **Pin the seed** -- Set `seed` in config after finding a failure to reproduce across runs
