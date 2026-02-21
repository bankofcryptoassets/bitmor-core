# Design: vuln-37 Static loanAmount Drift Fixes

**Date:** 2026-02-21
**Issue:** [#83](https://github.com/bankofcryptoassets/bitmor-core/issues/83)
**Branch:** `fix/vuln-21-stale-collateral-amount`

## Investigation Summary

Deep Trail of Bits-style analysis of `loanAmount` and `estimatedMonthlyPayment` fields in `DataTypes.LoanData` revealed 4 findings:

| # | Finding | Severity | Status |
|---|---------|----------|--------|
| 1 | `loanAmount` never updated after creation | LOW | Informational -- no on-chain logic reads it |
| 2 | `estimatedMonthlyPayment` stale in micro-liq | HIGH | **Kept static** -- max-rate EMI is conservative, self-corrects at `duration == 1` |
| 3 | `RepayLogic` duration underflow risk | MEDIUM | **Already fixed** -- uses `zeroFloorSub` at `RepayLogic.sol:117` |
| 4 | Struct ABI mismatch between lending-pool and loan-provider | CRITICAL | **Needs fix** |

## Decision: Keep `estimatedMonthlyPayment` Static

Rationale:
- EMI is computed using `getMaxVariableBorrowRate()` (worst-case rate) -- conservative by design
- Normal case: actual rate < max rate → EMI overpays → loan completes early
- Micro-liquidation self-corrects at `duration == 1` by using full `userVariableDebt`
- If collateral insufficient at final micro-liq, falls through to full liquidation (`LoanLiquidationLogic.sol:140-143`)
- All critical paths (repayment, closure, full liquidation) read live VDT balance, not stored fields

## Fix A: Struct ABI Mismatch (CRITICAL)

### Problem

Commit `3224d62` added `amountRepaidInCurrentPeriod` to loan-provider's `DataTypes.LoanData` (11 fields) but did not update lending-pool's `DataTypes.LoanData` (10 fields). The field was inserted before `status`:

```
Loan-provider (11 fields):              Lending-pool (10 fields):
 0: borrower                             0: borrower
 1: depositAmount                        1: depositAmount
 2: loanAmount                           2: loanAmount
 3: collateralAmount                     3: collateralAmount
 4: estimatedMonthlyPayment              4: estimatedMonthlyPayment
 5: duration                             5: duration
 6: createdAt                            6: createdAt
 7: insuranceID                          7: insuranceID
 8: lastPaymentTimestamp                 8: lastPaymentTimestamp
 9: amountRepaidInCurrentPeriod      →   9: status  ← MISMATCH
10: status                              (ignored)
```

When `checkTypeOfLiquidation` or `microLiquidationCall` calls `ILoan(bitmorLoan).getLoanByLSA(user)`, the ABI decoder reads 10 slots. Slot 9 contains `amountRepaidInCurrentPeriod` but is decoded as `LoanStatus`. Any loan with partial repayments (`amountRepaidInCurrentPeriod > 0`) has its `status` misread, breaking liquidation.

### Fix

Add `amountRepaidInCurrentPeriod` to lending-pool's `DataTypes.LoanData` at the same position (between `lastPaymentTimestamp` and `status`).

### Files to Change

1. **`lending-pool/contracts/protocol/libraries/types/DataTypes.sol:68-79`** -- Add `uint256 amountRepaidInCurrentPeriod` field to struct
2. **`lending-pool/contracts/mocks/MockLoan.sol:320-331`** -- Add field to `createActiveLoan` struct literal
3. **`lending-pool/contracts/test-harness/LoanLiquidationLogicHarness.sol:44-67`** -- Add field to `setLoanData` function signature and struct literal

No changes needed to:
- `LendingPoolCollateralManager.sol` -- reads `loanData` via `getLoanByLSA()`, auto-decodes correctly
- `LoanLiquidationLogic.sol` -- same, reads via `getLoanByLSA()`
- `ILoan.sol` -- interface uses `DataTypes.LoanData memory` which will pick up the new field

## Fix B: Document `loanAmount` Staleness (LOW)

### Problem

`loanAmount` is a write-once field (set at `LoanLogic.sol:110`). No on-chain logic reads it after creation, but off-chain consumers (UIs, scripts, keepers) may treat it as current outstanding debt.

### Fix

Add NatSpec `@dev` warnings to both struct definitions clarifying that `loanAmount` is a historical record. Also document `estimatedMonthlyPayment` as creation-time-only.

### Files to Change

1. **`loan-provider/src/libraries/types/DataTypes.sol:490-515`** -- Add `@dev` warnings
2. **`lending-pool/contracts/protocol/libraries/types/DataTypes.sol:56-79`** -- Same

## Test Strategy

- **Lending-pool tests**: `npm run test-bitmor` must pass with new struct field
- **Loan-provider tests**: `make test:unit` must pass (no loan-provider code changes)
- No new tests needed -- this is a struct alignment fix, existing tests validate behavior
