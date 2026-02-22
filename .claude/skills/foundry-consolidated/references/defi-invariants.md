# DeFi Invariant Patterns

A catalog of invariant properties commonly tested in DeFi protocols. Use as a starting checklist when designing invariant test suites.

## ERC-20 Tokens

| Invariant | Expression |
|---|---|
| Supply consistency | `totalSupply == sum(balanceOf[addr])` for all holders |
| No token creation from thin air | `totalSupply` only changes via mint/burn |
| Transfer conservation | sender balance decreases by exactly what receiver gains |
| Zero-address exclusion | `balanceOf(address(0)) == 0` (if enforced) |
| Metadata immutability | `name()`, `symbol()`, `decimals()` never change post-deploy |
| Allowance isolation | `approve(spender, x)` only affects that spender's allowance |

```solidity
function invariant_supplyMatchesBalances() external {
    uint256 sum;
    for (uint256 i; i < handler.actorCount(); i++) {
        sum += token.balanceOf(handler.actors(i));
    }
    assertEq(token.totalSupply(), sum);
}
```

## ERC-4626 Vaults

| Invariant | Expression |
|---|---|
| Solvency | `asset.balanceOf(vault) >= vault.totalAssets()` |
| Share supply | `totalSupply == sum(balanceOf[addr])` for all depositors |
| Deposit increases shares | `deposit(x) -> shares > 0` when `x > 0` |
| Rounding favors vault | `previewRedeem(previewDeposit(x)) <= x` |
| Monotonicity | `assets_a > assets_b -> previewDeposit(a) >= previewDeposit(b)` |
| No stuck funds | After all redemptions, `totalSupply == 0 && totalAssets ~= 0` |
| Exchange rate bounds | `convertToAssets(1e18)` stays within expected range |

```solidity
function invariant_vaultSolvency() external {
    assertGe(
        asset.balanceOf(address(vault)),
        vault.totalAssets(),
        "Vault must hold enough assets to cover totalAssets"
    );
}

function invariant_sharePriceNonZero() external {
    if (vault.totalSupply() > 0) {
        assertGt(vault.convertToAssets(1e18), 0, "Share price must be > 0");
    }
}
```

## ERC-4626 Attack Patterns

These are the most commonly exploited ERC-4626 vulnerabilities. Test for them explicitly.

### Inflation / Donation Attack (First Depositor Manipulation)

The attacker exploits integer rounding in share calculation to steal from the next depositor:

1. Attacker deposits 1 wei, receives 1 share
2. Attacker donates a large amount directly to the vault (via `transfer`, not `deposit`)
3. Next depositor's `deposit(X)` calculates shares as `X * totalSupply / totalAssets` which rounds to 0
4. Depositor gets 0 shares, loses their deposit

```solidity
// Test: first depositor cannot steal from second depositor
function testFuzz_inflationAttack(uint96 donation, uint96 victimDeposit) public {
    donation = bound(donation, 1e8, type(uint96).max);
    victimDeposit = bound(victimDeposit, 1, donation); // victim deposits <= donation

    // Attacker: deposit 1 wei, then donate
    vm.startPrank(attacker);
    deal(address(asset), attacker, 1 + donation);
    asset.approve(address(vault), 1);
    vault.deposit(1, attacker);
    asset.transfer(address(vault), donation); // direct donation
    vm.stopPrank();

    // Victim: should get > 0 shares (vault must be protected)
    vm.startPrank(victim);
    deal(address(asset), victim, victimDeposit);
    asset.approve(address(vault), victimDeposit);
    uint256 shares = vault.deposit(victimDeposit, victim);
    vm.stopPrank();

    assertGt(shares, 0, "victim must receive shares (inflation attack mitigated)");
}
```

### Mitigations to Verify

| Mitigation | How to Test |
|------------|-------------|
| **Virtual shares/offset** (OpenZeppelin) | Verify `totalAssets()` includes a virtual offset; first deposit always gets predictable shares |
| **Minimum deposit** | Verify small deposits revert with a clear error |
| **Dead shares** | Verify initial deposit mints extra shares to `address(0)` or burns them |

### Share Price Manipulation via Direct Transfer

Sending tokens directly to the vault (not through `deposit`) can skew the exchange rate. Test that:

```solidity
// Direct transfer should not disproportionately benefit existing depositors
function testFuzz_directTransferDoesNotInflateShares(uint96 deposit, uint96 donation) public {
    deposit = bound(deposit, 1e6, type(uint96).max / 2);
    donation = bound(donation, 1, type(uint96).max / 2);

    // First user deposits normally
    vault.deposit(deposit, user1);
    uint256 priceBeforeDonation = vault.convertToAssets(1e18);

    // Direct transfer to vault
    deal(address(asset), address(this), donation);
    asset.transfer(address(vault), donation);

    uint256 priceAfterDonation = vault.convertToAssets(1e18);

    // Price change should be bounded (not exploitable for flash loan profit)
    assertGe(priceAfterDonation, priceBeforeDonation, "share price must not decrease");
}
```

## Lending Protocols

| Invariant | Expression |
|---|---|
| Collateral accounting | `sum(userCollateral[i]) == totalCollateralDeposited` |
| Debt accounting | `sum(userDebt[i]) == totalBorrows` |
| Solvency | `totalDeposits >= totalBorrows` (at protocol level) |
| Interest monotonicity | `totalDebt` never decreases without repayment |
| Liquidation threshold | No position with `health < 1.0` survives without liquidation |
| Utilization bounds | `utilization = totalBorrows / totalDeposits <= 100%` |
| Reserve consistency | `reserves >= 0` and only increase from interest spread |

```solidity
function invariant_debtAccounting() external {
    uint256 sumDebt;
    for (uint256 i; i < handler.actorCount(); i++) {
        sumDebt += pool.getUserDebt(handler.actors(i));
    }
    assertEq(pool.totalBorrows(), sumDebt, "Sum of user debts must match totalBorrows");
}

function invariant_noUndercollateralized() external {
    for (uint256 i; i < handler.actorCount(); i++) {
        address user = handler.actors(i);
        if (pool.getUserDebt(user) > 0) {
            assertGe(
                pool.getHealthFactor(user),
                1e18,
                "No position should be undercollateralized without liquidation"
            );
        }
    }
}
```

## AMMs / DEXes

| Invariant | Expression |
|---|---|
| Constant product (Uniswap V2) | `reserve0 * reserve1 >= k` (k only increases from fees) |
| LP token conservation | `totalSupply` of LP token matches sum of LP balances |
| No value extraction | `reserve0 * reserve1` after swap >= before swap |
| Price bounds | Spot price within expected oracle deviation |
| Fee accounting | Protocol fees + LP fees == total fees collected |

```solidity
function invariant_constantProduct() external {
    uint256 r0 = pair.reserve0();
    uint256 r1 = pair.reserve1();
    assertGe(r0 * r1, handler.ghost_initialK(), "xy >= k must hold");
}
```

## Stablecoins / CDPs

| Invariant | Expression |
|---|---|
| Overcollateralization | For every CDP: `collateralValue >= debtValue * minRatio` |
| Supply backing | `totalStablecoinsIssued <= totalCollateralValue / minRatio` |
| Peg mechanism | After arbitrage, price stays within peg band |
| Liquidation completeness | No CDP below liquidation threshold survives a keeper call |

## Staking / Reward Distribution

| Invariant | Expression |
|---|---|
| Reward conservation | `totalRewardsDistributed <= totalRewardsFunded` |
| Proportional distribution | Each user's reward share proportional to their stake |
| No double claiming | User cannot claim same reward epoch twice |
| Stake accounting | `sum(userStake[i]) == totalStaked` |

## State Machine Invariants

Protocols with lifecycle states (e.g., Bitmor loans: Active -> Completed/Liquidated/Defaulted) need state transition invariants.

### Status Only Moves Forward

```solidity
// Ghost: track previous status per entity
mapping(address => uint256) public ghost_previousStatus;

function anyLoanAction(uint256 lsaSeed, ...) external {
    address lsa = _pickLoan(lsaSeed);
    // ... perform action ...
    uint256 currentStatus = uint256(loan.getStatus(lsa));
    ghost_previousStatus[lsa] = currentStatus;
}

// Invariant: no status regression
function invariant_statusOnlyMovesForward() external {
    for (uint256 i; i < handler.loanCount(); i++) {
        address lsa = handler.loans(i);
        uint256 current = uint256(loan.getStatus(lsa));
        uint256 previous = handler.ghost_previousStatus(lsa);
        assertGe(current, previous, "status must not regress");
    }
}
```

### Terminal States are Sticky

```solidity
// Once a loan is Liquidated or Completed, no action should change it
function invariant_terminalStatesAreSticky() external {
    for (uint256 i; i < handler.loanCount(); i++) {
        address lsa = handler.loans(i);
        uint256 status = uint256(loan.getStatus(lsa));
        if (handler.ghost_wasTerminal(lsa)) {
            assertTrue(
                status == uint256(LoanStatus.Liquidated) ||
                status == uint256(LoanStatus.Completed) ||
                status == uint256(LoanStatus.Defaulted),
                "terminal state must be permanent"
            );
        }
    }
}
```

### Valid Transitions Only

Define the allowed transition matrix and verify no illegal transitions occur:

| From | Allowed To |
|------|-----------|
| Active | Completed, Liquidated, Defaulted |
| Completed | (terminal) |
| Liquidated | (terminal) |
| Defaulted | (terminal) |

## Time-Dependent Invariants

Many DeFi properties only break after time passes. Systematically test time as a first-class dimension.

### Interest Accrual

```solidity
// Interest must accrue monotonically with time
function invariant_interestMonotonicity() external {
    for (uint256 i; i < handler.actorCount(); i++) {
        address user = handler.actors(i);
        uint256 currentDebt = pool.getUserDebt(user);
        uint256 previousDebt = handler.ghost_previousDebt(user);
        if (previousDebt > 0 && handler.ghost_timeSinceLastAccrual(user) > 0) {
            assertGe(currentDebt, previousDebt,
                "debt must not decrease without repayment");
        }
    }
}
```

### Grace Period Expiry

```solidity
// After grace period, overdue status must be set
function testFuzz_gracePeriodExpiry(uint256 timeAfterDue) public {
    timeAfterDue = bound(timeAfterDue, GRACE_PERIOD + 1, 365 days);
    address lsa = _createStandardLoan();

    // Warp past payment due date + grace period
    vm.warp(block.timestamp + PAYMENT_INTERVAL + timeAfterDue);

    assertTrue(pool.isOverdue(lsa), "must be overdue after grace period");
}
```

### Time-Weighted Properties

```solidity
// Reward rate * time elapsed == rewards earned (within rounding)
function invariant_rewardAccrualProportionalToTime() external {
    uint256 elapsed = block.timestamp - handler.ghost_lastRewardTimestamp();
    uint256 expectedRewards = rewardRate * elapsed;
    uint256 actualRewards = staking.pendingRewards();
    assertApproxEqAbs(actualRewards, expectedRewards, elapsed,
        "rewards must be proportional to time");
}
```

### vm.warp vs vm.roll

| Cheatcode | What It Changes | When to Use |
|-----------|----------------|-------------|
| `vm.warp(t)` | `block.timestamp` | Interest accrual, time-locked operations, deadlines |
| `vm.roll(n)` | `block.number` | Block-number-based logic (rare in modern contracts) |

For realistic simulation, advance both together:

```solidity
function warpForward(uint256 seconds_) external {
    seconds_ = bound(seconds_, 1, 365 days);
    vm.warp(block.timestamp + seconds_);
    vm.roll(block.number + seconds_ / 12); // ~12s per block
}
```

## General Protocol Invariants

| Invariant | Expression |
|---|---|
| ETH conservation | `address(protocol).balance` accounts for all user deposits/withdrawals |
| Access control | Only authorized roles can call admin functions |
| Reentrancy safety | State is consistent before and after external calls |
| Timestamp monotonicity | Protocol timestamps only move forward |
| No zero-address operations | No tokens sent to or received from address(0) |

## Handler Design for DeFi

### Time Simulation

Many DeFi invariants only break after time passes (interest accrual, reward distribution, oracle updates):

```solidity
function warpForward(uint256 seconds_) external {
    seconds_ = bound(seconds_, 1, 365 days);
    vm.warp(block.timestamp + seconds_);
    vm.roll(block.number + seconds_ / 12); // approximate block progression
}
```

### Price Oracle Simulation

```solidity
function updatePrice(uint256 newPrice) external {
    newPrice = bound(newPrice, minPrice, maxPrice);
    mockOracle.setPrice(newPrice);
}
```

### Multi-Handler Architecture for Complex Protocols

```solidity
function setUp() public {
    depositHandler = new DepositHandler(vault, asset);
    borrowHandler = new BorrowHandler(pool, asset);
    liquidationHandler = new LiquidationHandler(pool, oracle);
    timeHandler = new TimeHandler();

    targetContract(address(depositHandler));
    targetContract(address(borrowHandler));
    targetContract(address(liquidationHandler));
    targetContract(address(timeHandler));
}
```

Be mindful of uniform call distribution across handlers. If `timeHandler` has 1 function and `depositHandler` has 4, time warps get called 5x more often per-function. Adjust by adding dummy or weighted functions, or use `targetSelector` to control distribution.
