# Differential Security Review Report

**Branch:** `fix/bvbtc-naming`
**Date:** 2026-02-22
**Reviewer:** Claude Opus 4.6 (Trail of Bits methodology)
**Scope:** Variable naming changes in `loan-provider/` (unstaged changes on HEAD)

---

## Triage Summary

| File | Risk Level | Changes |
|------|-----------|---------|
| `src/libraries/types/DataTypes.sol` | **HIGH** | Struct field renames (`collateralAsset`→`btc`, `collateralPriceUSD`→`btcPriceUSD`, `collateralAssetDecimals`→`btcAssetDecimals`) |
| `src/libraries/logic/LoanLogic.sol` | **HIGH** | Oracle query target changed from `data.collateralAsset` to `data.btc`, `using AavePoolLogic for address` added, named struct init |
| `src/protocol/Loan.sol` | **HIGH** | `ctx.collateralAsset` → `ctx.btc` in `InitializeLoanContext`, `using` declarations added, positional→named struct init, `using-for` call patterns |
| `src/libraries/helpers/LoanMath.sol` | **MEDIUM** | Struct field access renames (cosmetic, compile-time safe) |
| `src/protocol/LoanStorage.sol` | **LOW** | Comment update, formatting |
| `test/fuzz/pure/LoanMath.fuzz.t.sol` | **MEDIUM** | Struct field renames in test data builders |
| `test/unit/Loan/InitializeLoan.t.sol` | **HIGH** | Oracle mock target fix + formatting |

**Strategy:** DEEP (< 20 files changed, all are security-critical)

---

## Finding #1: CONFIRMED BUG — `test_initializeLoan_slippageProtection` Oracle Mock Target Mismatch

**Severity:** Test failure (functional correctness)
**File:** `test/unit/Loan/InitializeLoan.t.sol:307-329`
**Status:** BROKEN — test passes when it should catch real slippage violations

### Description

The test mocks the oracle price for `collateralAsset` (`address(mockBTCVault)` = bvBTC vault), but the production code now queries `ctx.btc` (`i_BTC` = `address(mockCbBTC)` = underlying cbBTC).

```solidity
// Line 315 — reads price for wrong asset
uint256 realBtcPrice = IPriceOracleGetter(oracle).getAssetPrice(collateralAsset);
//                                                               ^^^^^^^^^^^^^^
//                                                               mockBTCVault (bvBTC)

// Line 320-323 — mocks wrong asset
vm.mockCall(
    oracle,
    abi.encodeWithSelector(IPriceOracleGetter.getAssetPrice.selector, collateralAsset),
    //                                                                 ^^^^^^^^^^^^^^
    //                                                                 mockBTCVault — NOT what code queries
    abi.encode(mockedBtcPrice)
);
```

The production code path:
1. `Loan.initializeLoan()` → `LoanLogic.executeInitializeLoan()` → `_calculateLoanAmountAndMonthlyPayment()`
2. At `LoanLogic.sol:277`: `oracle.getAssetPrice(data.btc)` — queries **cbBTC** price
3. The mock intercepts **bvBTC** oracle calls, not cbBTC
4. The real cbBTC price is returned unchanged → no slippage → no revert

### Fix

Replace `collateralAsset` with `btc` (which is `address(mockCbBTC)`) in both the price read and the `vm.mockCall`:

```solidity
// Line 315: Read the CORRECT asset price
uint256 realBtcPrice = IPriceOracleGetter(oracle).getAssetPrice(btc);

// Lines 320-323: Mock the CORRECT asset
vm.mockCall(
    oracle,
    abi.encodeWithSelector(IPriceOracleGetter.getAssetPrice.selector, btc),
    abi.encode(mockedBtcPrice)
);
```

### Blast Radius

This test was the ONLY slippage protection regression test for `initializeLoan`. With this test broken, there is no coverage for oracle price manipulation during loan initialization.

---

## Finding #2: INFORMATIONAL — `calculateStrikePrice` Still Queries `i_COLLATERAL_ASSET` (bvBTC) Not `i_BTC` (cbBTC)

**Severity:** Informational (pre-existing, not introduced by this PR)
**File:** `src/protocol/Loan.sol:403`

### Description

```solidity
function calculateStrikePrice(...) {
    uint256 btcPriceUSD = oracle.getAssetPrice(i_COLLATERAL_ASSET);
    //                                          ^^^^^^^^^^^^^^^^^^
    //                                          bvBTC vault price, NOT cbBTC price
```

All other loan calculation paths (`getLoanDetails`, `initializeLoan`) now correctly query `i_BTC` (cbBTC). But `calculateStrikePrice` still queries `i_COLLATERAL_ASSET` (bvBTC).

The variable is named `btcPriceUSD` but actually holds the **bvBTC share price**. This is semantically inconsistent with the rest of the codebase after this rename.

**Note:** The bvBTC share price should approximate cbBTC price (1:1 ratio in vault), so this may be functionally correct. However, if the vault accrues yield and shares become worth >1 cbBTC, the strike price calculation would use an inflated price.

### Recommendation

Evaluate whether `calculateStrikePrice` should use `i_BTC` instead of `i_COLLATERAL_ASSET` for consistency. If bvBTC share price is intentional, rename the local variable to `bvBtcPriceUSD` and add a comment explaining why.

---

## Finding #3: CONFIRMED CORRECT — Oracle Mock Fix in `test_calculateLoanDetails_RevertWhen_CollateralPriceIsZero`

**Severity:** Test improvement (already fixed in diff)
**File:** `test/unit/Loan/InitializeLoan.t.sol:459`

The diff correctly changes:
```diff
-        mockOracle.setAssetPrice(address(mockBTCVault), 0);
+        mockOracle.setAssetPrice(address(mockCbBTC), 0);
```

This is correct because `getLoanDetails` → `_fetchPricesAndCalculate` → `oracle.getAssetPrice(ctx.btc)` now queries cbBTC.

---

## Finding #4: SAFE — Positional to Named Struct Initialization

**Severity:** Informational (security improvement)
**Files:** `Loan.sol:292-302, 294-302, 420-430`

All struct initializations in `Loan.sol` were converted from positional to named:

```diff
-DataTypes.ExecuteFLOperationContext memory ctx = DataTypes.ExecuteFLOperationContext(
-    i_AAVE_V3_POOL, i_BITMOR_POOL, s_swapper, ...
-);
+DataTypes.ExecuteFLOperationContext memory ctx = DataTypes.ExecuteFLOperationContext({
+    aavePool: i_AAVE_V3_POOL,
+    bitmorPool: i_BITMOR_POOL,
+    swapper: s_swapper,
+    ...
+});
```

**Verified all field mappings are correct:**

| Struct | Fields | Verification |
|--------|--------|-------------|
| `ExecuteFLOperationContext` | 9 fields | All match: `collateralAsset: i_COLLATERAL_ASSET`, `btc: i_BTC` |
| `ExecuteFLOperationParams` | 6 fields | All match |
| `CalculateLoanDetailsContext` | 9 fields | `btc: i_BTC` (correctly uses underlying) |
| `ExecuteInitializeLoanParams` | 7 fields | All match |
| `ExecuteCloseLoanParams` | 2 fields | All match |

This is a **security improvement** — named initialization prevents accidental field reordering bugs.

---

## Finding #5: SAFE — `using-for` Pattern Changes

**Severity:** Informational (code style)
**Files:** `Loan.sol:266-268`, `LoanLogic.sol:49`

New `using` declarations:
```solidity
using FlashLoanLogic for DataTypes.ExecuteFLOperationContext;
using CloseLoanLogic for DataTypes.ExecuteCloseLoanContext;
using LoanLogic for DataTypes.CalculateLoanDetailsContext;
using AavePoolLogic for address;
```

Call pattern changes:
```diff
-FlashLoanLogic.executeFLOperationInitiailizingLoan(ctx, flOpParams, s_loansByLSA);
+ctx.executeFLOperationInitiailizingLoan(flOpParams, s_loansByLSA);

-AavePoolLogic.executeFlashLoan(ctx.aavePool, ...);
+ctx.aavePool.executeFlashLoan(...);
```

**Verified:** These are syntactic sugar only. The compiled bytecode is identical — `using X for Y` simply allows calling `X.foo(y, ...)` as `y.foo(...)`. No behavioral change.

---

## Finding #6: SAFE — DataTypes Struct Renames (Semantic)

**Severity:** Informational (naming improvement)
**File:** `src/libraries/types/DataTypes.sol`

| Struct | Old Field | New Field | Impact |
|--------|-----------|-----------|--------|
| `InitializeLoanContext` | `collateralAsset` | `btc` | Address now refers to cbBTC (underlying) |
| `CalculateLoanDetailsContext` | `collateralAsset` | `btc` | Same |
| `CalculateLoanAmountAndMonthlyPayment` | `collateralAsset` | `btc` | Same |
| `CalculateLoanAmountAndMonthlyPayment` | `collateralAssetDecimals` | `btcAssetDecimals` | Same |
| `CalculateLoanAmt` | `collateralPriceUSD` | `btcPriceUSD` | Same |
| `CalculateLoanAmt` | `collateralAssetDecimals` | `btcAssetDecimals` | Same |

**Semantic correctness verified:** These structs are used in loan calculation paths where the underlying BTC (cbBTC) price and decimals are needed, NOT the vault share (bvBTC) price. The rename correctly disambiguates this.

---

## Finding #7: WARNING — Dirty Submodule

**File:** `loan-provider/lib/solady`

```diff
-Subproject commit acd959aa4bd04720d640bf4e6a5c71037510cc4b
+Subproject commit acd959aa4bd04720d640bf4e6a5c71037510cc4b-dirty
```

The `solady` submodule has uncommitted local changes. This should be cleaned up before merging.

---

## Blast Radius Analysis

| Change | Direct Callers | Transitive Callers |
|--------|---------------|-------------------|
| `InitializeLoanContext.btc` | `Loan.initializeLoan` | All loan initialization paths |
| `CalculateLoanDetailsContext.btc` | `Loan.getLoanDetails` | All loan preview/quoting paths |
| `CalculateLoanAmountAndMonthlyPayment.btc` | `LoanLogic._calculateLoanAmountAndMonthlyPayment` | `initializeLoan` |
| `CalculateLoanAmt.btcPriceUSD` | `LoanMath.calculateLoanAmt`, `LoanMath.calculateLoanDetails` | All EMI calculations |

All callers verified correct. The rename propagates consistently through the call graph.

---

## Coverage Assessment

| Path | Unit Tests | Status |
|------|-----------|--------|
| `initializeLoan` happy path | 12 tests | PASS |
| `initializeLoan` slippage | 1 test | **FAIL** (Finding #1) |
| `getLoanDetails` | 8+ tests | PASS |
| `calculateStrikePrice` | 2 tests | PASS (but see Finding #2) |
| `repay` | 17 tests | PASS |
| `closeLoan` | 30 tests | PASS |
| `liquidation` | 15 tests | PASS |
| Fuzz: `LoanMath` | 5+ tests | Updated correctly |

**579/580 tests pass.** The single failure is explained by Finding #1.

---

## Summary of Findings

| # | Severity | Finding | Action Required |
|---|----------|---------|-----------------|
| 1 | **HIGH** | `test_initializeLoan_slippageProtection` oracle mock targets wrong asset | Fix mock target from `collateralAsset` to `btc` |
| 2 | **INFO** | `calculateStrikePrice` uses `i_COLLATERAL_ASSET` inconsistently | Evaluate and document |
| 3 | **SAFE** | `test_calculateLoanDetails_RevertWhen_CollateralPriceIsZero` already fixed | No action |
| 4 | **SAFE** | Positional → named struct init | Security improvement |
| 5 | **SAFE** | `using-for` pattern changes | Code style improvement |
| 6 | **SAFE** | DataTypes struct field renames | Correctly disambiguates naming |
| 7 | **LOW** | Dirty solady submodule | Clean before merge |

---

## Verdict

The variable naming refactor is **semantically correct** and **improves code safety**. The only actionable finding is the broken slippage test (Finding #1), which needs a one-line fix to mock the correct asset address. The `calculateStrikePrice` inconsistency (Finding #2) is pre-existing and should be evaluated separately.

No new security vulnerabilities were introduced by these changes.
