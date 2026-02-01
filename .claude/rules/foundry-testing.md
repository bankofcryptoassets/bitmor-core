---
description: Foundry testing best practices based on official guidelines. Apply when writing, reviewing, or improving .t.sol test files.
---

## 1. File Organization

### Naming Convention

- Test files mirror contracts: `MyContract.sol` → `MyContract.t.sol`
- Split large contracts logically:
    - `Loan.t.sol` → `InitializeLoan.t.sol`, `RepayLoan.t.sol`, `CloseLoan.t.sol`
    - Group by function area, not alphabetically

### Directory Structure

```
test/
├── base/       # Test base classes (inherit from these)
├── unit/       # Unit tests (no fork required)
├── fork/       # Fork tests (require RPC)
├── fuzz/       # Fuzz tests
├── invariant/  # Invariant tests
├── mock/       # Mock contracts
└── helpers/    # Test constants, utilities
```

## 2. Test Naming Conventions

| Pattern                        | Usage             | Example                                 |
| ------------------------------ | ----------------- | --------------------------------------- |
| `test_FunctionName()`          | Happy path        | `test_Transfer()`                       |
| `test_FunctionName_Scenario()` | Specific scenario | `test_Transfer_ToZeroAddress()`         |
| `test_RevertWhen_Condition()`  | Expected reverts  | `test_RevertWhen_InsufficientBalance()` |
| `testFuzz_FunctionName()`      | Fuzz tests        | `testFuzz_Transfer()`                   |
| `testFork_Description()`       | Fork tests        | `testFork_SwapOnUniswap()`              |
| `testForkFuzz_Description()`   | Fork + fuzz       | `testForkFuzz_LiquidationAmounts()`     |

### Constants & Variables

- Use `ALL_CAPS_WITH_UNDERSCORES` for constants and immutables
- This distinguishes them from mutable variables at a glance

## 3. Test Structure

### Arrange-Act-Assert Pattern

```solidity
function test_Transfer() public {
    // Arrange - Setup test state
    uint256 amount = TRANSFER_AMOUNT;  // Use constants, not magic values

    // Act - Execute the action
    vm.prank(alice);
    token.transfer(bob, amount);

    // Assert - Verify outcomes
    assertEq(token.balanceOf(bob), amount, "recipient balance");
}
```

### No Magic Values

**NEVER use unexplained literal values in tests.**

```solidity
// BAD - Magic values
function test_Deposit_Bad() public {
    vault.deposit(50000e6, 1000e6);  // What do these mean?
}

// GOOD - Named constants
function test_Deposit_Good() public {
    vault.deposit(DEPOSIT_AMOUNT, MIN_SHARES);  // Clear intent
}
```

If a constant doesn't exist, either:

1. Add it to `TestConstants.sol` with a descriptive name
2. Define it as a constant in your test contract

### setUp() Rules

- **No assertions in `setUp()`** - it runs before every test
- Create `test_SetUpState()` to validate initialization
- Keep `setUp()` minimal - call parent `super.setUp()` first

```solidity
function setUp() public override {
    super.setUp();  // Always call parent first
    // Minimal additional setup
}

function test_SetUpState() public view {
    assertEq(address(vault) != address(0), true, "vault deployed");
    assertGt(token.balanceOf(address(this)), 0, "tokens funded");
}
```

### Test Order

- Tests should follow the same order as functions in the contract-under-test
- Group all tests for a single function together

## 4. Assertions & Events

### Assertion Messages

**Always include descriptive strings** - aids debugging without relying on line numbers.

```solidity
// BAD - No context on failure
assertEq(balance, expected);

// GOOD - Clear failure message
assertEq(balance, expected, "user balance after transfer");
assertGt(shares, 0, "shares minted should be positive");
assertEq(uint256(status), uint256(Status.Active), "loan should be active");
```

### Event Testing

Use `vm.expectEmit(true, true, true, true)` for comprehensive validation:

```solidity
function test_Transfer_EmitsEvent() public {
    // Expect the event with all indexed params checked
    vm.expectEmit(true, true, true, true);
    emit Transfer(alice, bob, AMOUNT);

    // Act
    token.transfer(bob, AMOUNT);
}
```

### Revert Testing

Use specific error selectors, not generic `vm.expectRevert()`:

```solidity
// BAD - Any revert passes
vm.expectRevert();

// GOOD - Specific error selector
vm.expectRevert(Errors.InsufficientBalance.selector);

// GOOD - Error with parameters
vm.expectRevert(
    abi.encodeWithSelector(
        Errors.InvalidAmount.selector,
        provided,
        minimum
    )
);
```

## 5. Fork Testing

### Configuration

Configure RPC endpoints in `foundry.toml`, not CLI flags:

```toml
[rpc_endpoints]
mainnet = "${MAINNET_RPC_URL}"
base = "${BASE_RPC_URL}"
base_sepolia = "${BASE_SEPOLIA_RPC_URL}"
```

Access via `stdChains.ChainName.rpcUrl` from forge-std.

### Pin Block Numbers

Always pin to specific blocks for determinism and caching:

```solidity
function setUp() public {
    vm.createSelectFork("mainnet", 19_000_000);  // Pinned block
}
```

### Minimize RPC Calls in Fuzz Tests

- Use multicall for batch queries
- Specify fuzz seed: `forge test --fuzz-seed 12345`
- Compute test data locally, not via RPC

## 6. Testing Internal Functions

Expose `internal` functions via harness contracts:

```solidity
// In test/harness/MyContractHarness.sol
contract MyContractHarness is MyContract {
    function exposed_internalFunction(uint256 x) external returns (uint256) {
        return _internalFunction(x);
    }
}
```

**Note:** `private` functions cannot be reliably unit tested. Convert to `internal` if testing is needed.

## 7. Invariant Tests

Write verbose assertion descriptions:

```solidity
// BAD - Cryptic
invariant_A();

// GOOD - Descriptive
function invariant_totalSupplyEqualsSumOfBalances() public {
    assertEq(
        token.totalSupply(),
        sumOfAllBalances,
        "Invariant violated: totalSupply must equal sum of all balances"
    );
}
```

## 8. Common Mistakes

| Mistake                           | Fix                                        |
| --------------------------------- | ------------------------------------------ |
| Magic values in tests             | Use named constants from TestConstants.sol |
| Assertions in `setUp()`           | Move to `test_SetUpState()` function       |
| Generic `vm.expectRevert()`       | Use specific error selectors               |
| Missing assertion messages        | Always add descriptive strings             |
| `vm.expectEmit()` with false args | Use `(true, true, true, true)`             |
| Hardcoded addresses               | Use `makeAddr("name")` or constants        |
| Testing private functions         | Convert to internal + harness pattern      |
| Unpinned fork blocks              | Always specify block number                |
| RPC URLs in code                  | Use `foundry.toml` + env vars              |
| Excessive RPC calls in fuzz       | Use multicall, seeds, local computation    |

## 9. AI Testing Anti-Patterns to Avoid

**CRITICAL: These are the 12 most common AI testing failures. NEVER generate tests with these patterns:**

### 1. Circular Logic

```solidity
// BAD: Test proves nothing - just echoes implementation
function test_getBalance() public {
    uint256 balance = vault.getBalance(user);
    assertEq(vault.getBalance(user), balance); // Circular!
}

// GOOD: Test against known state
function test_getBalance() public {
    vm.deal(user, 1 ether);
    vault.deposit{value: 1 ether}(user);
    assertEq(vault.getBalance(user), 1 ether); // Known expected value
}
```

### 2. Mock Cheating

```solidity
// BAD: Mock returns what test expects - proves nothing
mockOracle.setPrice(1000);
uint256 price = contract.getPrice();
assertEq(price, 1000); // Just testing the mock!

// GOOD: Test actual logic with mock as input
mockOracle.setPrice(1000);
uint256 collateralRequired = contract.calculateCollateral(100 ether);
assertEq(collateralRequired, 10 ether); // Tests calculation logic
```

### 3. Missing Negative Tests

```solidity
// BAD: Only happy path
function test_withdraw() public {
    vault.deposit(100);
    vault.withdraw(50);
    assertEq(vault.balance(), 50);
}

// GOOD: Include failure cases
function test_withdraw_revertsWhenInsufficientBalance() public {
    vault.deposit(100);
    vm.expectRevert(InsufficientBalance.selector);
    vault.withdraw(200);
}
```

### 4. Inadequate Randomization in Fuzz Tests

```solidity
// BAD: Constraints too tight, tests nothing
function testFuzz_deposit(uint256 amount) public {
    amount = bound(amount, 100, 100); // Always 100!
    // ...
}

// GOOD: Meaningful range with edge cases
function testFuzz_deposit(uint256 amount) public {
    amount = bound(amount, 1, type(uint128).max);
    vm.assume(amount > 0);
    // ...
}
```

### 5. State Leakage Between Tests

```solidity
// BAD: Relies on state from other tests
function test_second() public {
    // Assumes test_first ran and set state
    assertGt(vault.totalDeposits(), 0);
}

// GOOD: Each test is independent
function test_second() public {
    vault.deposit(100); // Set up own state
    assertGt(vault.totalDeposits(), 0);
}
```

### 6. Testing Implementation Details

```solidity
// BAD: Tests internal variable names
assertEq(vault._internalCounter, 5);

// GOOD: Tests observable behavior
assertEq(vault.getProcessedCount(), 5);
```
