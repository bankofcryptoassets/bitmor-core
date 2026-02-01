---
name: foundry-testing
description: Rigorous Foundry/Solidity testing patterns that avoid common AI testing failures (circular logic, mock cheating, missing negative tests). Use when writing or reviewing smart contract tests.
---

# Foundry Smart Contract Testing

A rigorous testing skill for Solidity smart contracts using Foundry. Addresses common AI-generated test failures and enforces production-grade testing standards.

## When to Activate

- Writing new Foundry tests
- Reviewing existing test coverage
- Implementing fuzz/invariant testing
- Security-focused test development
- Before audit preparation

## AI Testing Anti-Patterns to Avoid

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

## Test Categories & Requirements

### Coverage Thresholds
| Category | Minimum | Target |
|----------|---------|--------|
| Line Coverage | 80% | 95% |
| Branch Coverage | 70% | 90% |
| Core Business Logic | 90% | 100% |

### Test Maturity Phases

**Phase 1 - BASIC**: Unit tests for all public functions
**Phase 2 - INTERMEDIATE**: + Integration tests, access control, events
**Phase 3 - ADVANCED**: + Fuzz testing, invariant testing
**Phase 4 - PRODUCTION**: + Security tests, fork tests, gas benchmarks

## Test Structure Template

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {Contract} from "src/Contract.sol";

contract ContractTest is Test {
    // ============ Constants ============
    uint256 constant INITIAL_BALANCE = 100 ether;
    uint256 constant TEST_AMOUNT = 1 ether;

    // ============ State ============
    Contract public target;
    address public owner;
    address public user;
    address public attacker;

    // ============ Setup ============
    function setUp() public {
        owner = makeAddr("owner");
        user = makeAddr("user");
        attacker = makeAddr("attacker");

        vm.deal(owner, INITIAL_BALANCE);
        vm.deal(user, INITIAL_BALANCE);

        vm.prank(owner);
        target = new Contract();
    }

    // ============ Unit Tests ============
    function test_functionName_whenCondition_shouldResult() public {
        // Arrange
        uint256 input = 100;

        // Act
        vm.prank(user);
        uint256 result = target.function(input);

        // Assert
        assertEq(result, expectedValue, "Descriptive message");
    }

    // ============ Access Control ============
    function test_adminFunction_revertsWhenCalledByNonAdmin() public {
        vm.prank(attacker);
        vm.expectRevert(); // or specific selector
        target.adminFunction();
    }

    // ============ Events ============
    function test_deposit_emitsDepositEvent() public {
        vm.expectEmit(true, true, false, true);
        emit Deposited(user, amount);

        vm.prank(user);
        target.deposit(amount);
    }

    // ============ Edge Cases ============
    function test_function_withZeroInput() public { }
    function test_function_withMaxInput() public { }
    function test_function_atBoundaryCondition() public { }

    // ============ Fuzz Tests ============
    function testFuzz_deposit(uint256 amount) public {
        amount = bound(amount, 1, type(uint128).max);
        vm.deal(user, amount);

        vm.prank(user);
        target.deposit{value: amount}();

        assertEq(target.balanceOf(user), amount);
    }
}
```

## Invariant Testing Pattern

```solidity
contract InvariantTest is Test {
    Handler public handler;
    Target public target;

    function setUp() public {
        target = new Target();
        handler = new Handler(target);

        // Target only the handler
        targetContract(address(handler));

        // Exclude system addresses
        excludeSender(address(0));
        excludeSender(address(target));
    }

    // Core invariants - MUST always hold
    function invariant_totalSupplyMatchesBalances() public view {
        assertEq(
            target.totalSupply(),
            handler.ghost_totalDeposited() - handler.ghost_totalWithdrawn()
        );
    }

    function invariant_noNegativeBalances() public view {
        for (uint i = 0; i < handler.actorCount(); i++) {
            assertGe(target.balanceOf(handler.actors(i)), 0);
        }
    }

    // Debug helper
    function afterInvariant() public view {
        console2.log("Total calls:", handler.totalCalls());
        console2.log("Successful deposits:", handler.depositCount());
    }
}

contract Handler is Test {
    Target public target;

    // Ghost variables for tracking
    uint256 public ghost_totalDeposited;
    uint256 public ghost_totalWithdrawn;
    uint256 public totalCalls;

    address[] public actors;
    mapping(address => bool) public isActor;

    constructor(Target _target) {
        target = _target;
        // Create actor pool
        for (uint i = 0; i < 5; i++) {
            address actor = makeAddr(string(abi.encodePacked("actor", i)));
            actors.push(actor);
            isActor[actor] = true;
            vm.deal(actor, 100 ether);
        }
    }

    function deposit(uint256 amount, uint256 actorSeed) public {
        totalCalls++;
        amount = bound(amount, 0.01 ether, 10 ether);
        address actor = actors[actorSeed % actors.length];

        vm.prank(actor);
        target.deposit{value: amount}();

        ghost_totalDeposited += amount;
    }
}
```

## Security Testing Checklist

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

## Fork Testing Pattern

```solidity
contract ForkTest is Test {
    uint256 mainnetFork;

    function setUp() public {
        mainnetFork = vm.createFork(vm.envString("MAINNET_RPC_URL"));
        vm.selectFork(mainnetFork);
        vm.rollFork(18_000_000); // Pin to specific block
    }

    function test_interactionWithMainnetProtocol() public {
        // Test against real mainnet state
        IPool pool = IPool(AAVE_V3_POOL);
        // ...
    }
}
```

## Test Naming Convention

```
test_<function>_<condition>_<expected>

Examples:
- test_deposit_whenAmountIsZero_reverts
- test_withdraw_whenBalanceSufficient_transfersFunds
- test_liquidate_whenHealthFactorBelow1_liquidatesPosition
- testFuzz_deposit_alwaysIncreasesBalance
- invariant_totalSupplyNeverExceedsCap
```

## Risk-Based Test Priority

When time is limited, prioritize based on contract risk:

| Contract Type | Risk Score | Testing Priority |
|--------------|------------|------------------|
| Token/Value handling | HIGH | Full coverage + invariants + security |
| Access control | HIGH | Full coverage + fuzzing |
| External integrations | MEDIUM-HIGH | Fork tests + failure modes |
| View functions | LOW | Basic unit tests |
| Pure utilities | LOW | Unit tests + edge cases |

## Pre-Commit Checklist

Before committing tests, verify:

1. [ ] `forge test` passes
2. [ ] `forge coverage` meets thresholds
3. [ ] No circular logic in assertions
4. [ ] Mocks test actual logic, not themselves
5. [ ] Negative test cases included
6. [ ] Fuzz tests have meaningful bounds
7. [ ] Each test is independent
8. [ ] Descriptive assertion messages
9. [ ] Events tested where emitted
10. [ ] Access control tested for all restricted functions
