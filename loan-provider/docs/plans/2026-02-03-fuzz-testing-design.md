# Fuzz Testing Infrastructure Design

> **Created:** 2026-02-03
> **Status:** Approved
> **Branch:** feat/fuzzTests

## Overview

Comprehensive fuzz testing infrastructure for the loan-provider module covering:
1. **Bug discovery** - Target high-risk math functions and edge cases
2. **Coverage completeness** - Systematic parameter exploration
3. **Security audit preparation** - Documented properties with audit tags

## Directory Structure

```
test/fuzz/
├── base/
│   └── FuzzTestBase.sol          # Extends UnitTestBase with fuzz helpers
├── pure/
│   └── LoanMath.fuzz.t.sol       # Pure function fuzz tests
├── stateful/
│   ├── Loan.fuzz.t.sol           # Loan contract fuzz tests
│   ├── BTCVault.fuzz.t.sol       # BTC vault fuzz tests
│   └── USDCVault.fuzz.t.sol      # USDC vault fuzz tests
├── handlers/
│   ├── LoanHandler.sol           # Wraps Loan operations for fuzzer
│   └── VaultHandler.sol          # Wraps Vault operations
└── helpers/
    └── FuzzConstants.sol         # Fuzz-specific bounds and constants

test/harness/
└── LoanMathHarness.sol           # Exposes internal LoanMath functions
```

## Constants & Bounds

| Parameter | Min | Max |
|-----------|-----|-----|
| Deposit | 30% of collateral | 100% of collateral |
| Duration | 1 month | 60 months |
| Interest Rate | 0% | 12% APR |
| Collateral | Dynamic (from Loan) | Dynamic (from Loan) |
| BTC Price | $1,000 | $1,000,000 |
| BTC Amount | 0.01 BTC | 100 BTC |
| USDC Amount | 1 USDC | 10M USDC |

## Base Class Design

**FuzzTestBase** extends `UnitTestBase` and provides:
- `_boundCollateral(uint256 raw)` - Constrain to valid collateral range
- `_boundDuration(uint256 raw)` - Constrain to 1-60 months
- `_boundDeposit(uint256 collateralValue, uint256 raw)` - Constrain to 30-100%
- `_boundPrice(uint256 raw)` - Constrain to $1k-$1M
- `_boundInterestRate(uint256 raw)` - Constrain to 0-12%

## Fuzz Test Properties

### LoanMath (Pure Functions)
| Property ID | Description |
|-------------|-------------|
| MATH-01 | `rayPow(base, 0) == RAY` (identity) |
| MATH-02 | `rayPow(RAY, n) == RAY` (base one) |
| MATH-03 | `monthlyPayment * duration >= loanAmount` (no negative amortization) |
| MATH-04 | Strike price > 0 for valid inputs |
| MATH-05 | Higher interest rate → higher monthly payment |

### Loan Contract (Stateful)
| Property ID | Description |
|-------------|-------------|
| LOAN-01 | Loan initialization creates valid LSA |
| LOAN-02 | Insufficient deposit reverts |
| LOAN-03 | Zero collateral reverts |
| LOAN-04 | Repayment reduces debt |
| LOAN-05 | Full repayment allows closure |
| LOAN-06 | Collateral always backs debt |

### BTCVault (ERC-4626)
| Property ID | Description |
|-------------|-------------|
| BTC-01 | Deposit/withdraw roundtrip within slippage |
| BTC-02 | Shares minted proportional to deposit |
| BTC-03 | Total assets >= total supply * min share price |
| BTC-04 | Strategy allocation never exceeds cap |

### USDCVault
| Property ID | Description |
|-------------|-------------|
| USDC-01 | Deposit/withdraw roundtrip preserves value |
| USDC-02 | Yield accrual never decreases share value |
| USDC-03 | Withdrawal respects available liquidity |

## Handler Pattern

Handlers wrap contract operations for stateful fuzzing:
- Track state across calls (activeLSAs, totalRepaid, etc.)
- Graceful handling of invalid states (early returns)
- Enable invariant verification across random call sequences

## Parallel Agent Implementation

| Agent | Branch | Files |
|-------|--------|-------|
| Agent 1 | `fuzz/base-infrastructure` | FuzzTestBase.sol, FuzzConstants.sol |
| Agent 2 | `fuzz/loan-tests` | Loan.fuzz.t.sol, LoanHandler.sol |
| Agent 3 | `fuzz/btcvault-tests` | BTCVault.fuzz.t.sol, VaultHandler.sol |
| Agent 4 | `fuzz/usdcvault-tests` | USDCVault.fuzz.t.sol |
| Agent 5 | `fuzz/loanmath-tests` | LoanMath.fuzz.t.sol, LoanMathHarness.sol |

## Execution Phases

1. **Phase 1 (Sequential):** Agent 1 creates base infrastructure
2. **Phase 2 (Parallel):** Agents 2-5 work concurrently in git worktrees
3. **Phase 3 (Sequential):** Merge all branches to feat/fuzzTests
