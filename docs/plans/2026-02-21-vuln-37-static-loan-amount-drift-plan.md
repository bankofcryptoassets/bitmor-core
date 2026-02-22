# vuln-37 Static loanAmount Drift — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Fix the CRITICAL struct ABI mismatch between lending-pool and loan-provider `DataTypes.LoanData`, and document stale `loanAmount`/`estimatedMonthlyPayment` fields.

**Architecture:** The loan-provider (Solidity 0.8.30) added an `amountRepaidInCurrentPeriod` field to `LoanData` but the lending-pool (Solidity 0.6.12) was never synced. This causes the lending-pool to misinterpret `amountRepaidInCurrentPeriod` as `status` when decoding cross-contract `getLoanByLSA()` calls. The fix adds the missing field to the lending-pool struct and all struct constructors.

**Tech Stack:** Solidity 0.6.12 (lending-pool, Hardhat), Solidity 0.8.30 (loan-provider, Foundry)

**Design doc:** `docs/plans/2026-02-21-vuln-37-static-loan-amount-drift-design.md`

**Parallel agents:** Tasks 1 and 2 are independent and can be dispatched in parallel.

---

## Task 1: Sync lending-pool `DataTypes.LoanData` struct (CRITICAL)

**Files:**
- Modify: `lending-pool/contracts/protocol/libraries/types/DataTypes.sol:55-79`
- Modify: `lending-pool/contracts/mocks/MockLoan.sol:320-331`
- Modify: `lending-pool/contracts/test-harness/LoanLiquidationLogicHarness.sol:44-67`

### Step 1: Add `amountRepaidInCurrentPeriod` field to `DataTypes.LoanData` struct

In `lending-pool/contracts/protocol/libraries/types/DataTypes.sol`, add the field between `lastPaymentTimestamp` and `status` to match the loan-provider struct layout:

```solidity
  /**
   * @notice Complete loan information stored per LSA
   * @param borrower The address that created and owns this loan
   * @param depositAmount Initial USDC deposit amount (6 decimals)
   * @param loanAmount Total amount borrowed via flash loan (6 decimals). Historical record only — does not track accrued interest. For live debt, read the variable debt token balance.
   * @param collateralAmount cbBTC amount user wants to achieve (8 decimals)
   * @param estimatedMonthlyPayment Estimated monthly payment calculated at creation (6 decimals). Computed once using max variable borrow rate; not updated during loan lifetime.
   * @param duration Loan term length in months
   * @param createdAt Unix timestamp when loan was created
   * @param insuranceID Insurance/Order ID for tracking this loan
   * @param lastPaymentTimestamp Timestamp at which last payment was made.
   * @param amountRepaidInCurrentPeriod Accumulated partial repayments within the current billing period (6 decimals)
   * @param status Current lifecycle status of the loan
   */
  struct LoanData {
    address borrower;
    uint256 depositAmount;
    uint256 loanAmount;
    uint256 collateralAmount;
    uint256 estimatedMonthlyPayment;
    uint256 duration;
    uint256 createdAt;
    uint256 insuranceID;
    uint256 lastPaymentTimestamp;
    uint256 amountRepaidInCurrentPeriod;
    LoanStatus status;
  }
```

### Step 2: Update `MockLoan.createActiveLoan` struct literal

In `lending-pool/contracts/mocks/MockLoan.sol`, add `amountRepaidInCurrentPeriod: 0` to the struct literal at `createActiveLoan`:

```solidity
        _loanData[lsa] = DataTypes.LoanData({
            borrower: borrower,
            depositAmount: loanAmount / 3, // ~33% deposit
            loanAmount: loanAmount,
            collateralAmount: collateralAmount,
            estimatedMonthlyPayment: monthlyPayment,
            duration: duration,
            createdAt: block.timestamp,
            insuranceID: 0,
            lastPaymentTimestamp: block.timestamp,
            amountRepaidInCurrentPeriod: 0,
            status: DataTypes.LoanStatus.Active
        });
```

### Step 3: Update `LoanLiquidationLogicHarness.setLoanData` function

In `lending-pool/contracts/test-harness/LoanLiquidationLogicHarness.sol`, add the parameter and field:

```solidity
    function setLoanData(
        address borrower,
        uint256 depositAmount,
        uint256 loanAmount,
        uint256 collateralAmount,
        uint256 estimatedMonthlyPayment,
        uint256 duration,
        uint256 createdAt,
        uint256 insuranceID,
        uint256 lastPaymentTimestamp,
        uint256 amountRepaidInCurrentPeriod,
        DataTypes.LoanStatus status
    ) external {
        _loanData = DataTypes.LoanData({
            borrower: borrower,
            depositAmount: depositAmount,
            loanAmount: loanAmount,
            collateralAmount: collateralAmount,
            estimatedMonthlyPayment: estimatedMonthlyPayment,
            duration: duration,
            createdAt: createdAt,
            insuranceID: insuranceID,
            lastPaymentTimestamp: lastPaymentTimestamp,
            amountRepaidInCurrentPeriod: amountRepaidInCurrentPeriod,
            status: status
        });
    }
```

### Step 4: Find and update any test-suite calls to `setLoanData` in harness

Search `lending-pool/test-suites/` for calls to `setLoanData` that pass 10 arguments (the old signature). Add `0` as the new `amountRepaidInCurrentPeriod` argument (second-to-last, before `status`).

Run: `grep -rn "setLoanData" lending-pool/test-suites/`

For each call site, insert `0` (or `ethers.BigNumber.from(0)`) as the 10th argument.

### Step 5: Compile lending-pool to verify struct alignment

Run: `cd lending-pool && npm run compile`

Expected: Clean compilation with no errors. If any file still constructs `LoanData` with 10 fields, the compiler will error with "wrong argument count."

### Step 6: Run lending-pool Bitmor tests

Run: `cd lending-pool && npm run test-bitmor`

Expected: All tests pass. The struct change is additive — existing logic does not reference `amountRepaidInCurrentPeriod` in the lending-pool.

### Step 7: Run full lending-pool test suite

Run: `cd lending-pool && npm test`

Expected: All tests pass.

### Step 8: Commit

```bash
git add lending-pool/contracts/protocol/libraries/types/DataTypes.sol \
       lending-pool/contracts/mocks/MockLoan.sol \
       lending-pool/contracts/test-harness/LoanLiquidationLogicHarness.sol
# Also add any modified test files from Step 4
git commit -m "fix: sync lending-pool LoanData struct with loan-provider (vuln-37)

Add amountRepaidInCurrentPeriod field to lending-pool DataTypes.LoanData
to match the loan-provider struct layout. Without this, the ABI decoder
misinterprets amountRepaidInCurrentPeriod as LoanStatus when decoding
cross-contract getLoanByLSA() calls, breaking liquidation for any loan
with partial repayments.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

## Task 2: Document stale `loanAmount` and `estimatedMonthlyPayment` (LOW)

**Files:**
- Modify: `loan-provider/src/libraries/types/DataTypes.sol:489-515`

### Step 1: Add `@dev` staleness warnings to loan-provider NatSpec

In `loan-provider/src/libraries/types/DataTypes.sol`, update the NatSpec for `loanAmount` and `estimatedMonthlyPayment`:

```solidity
    /**
     * @notice Complete loan information stored per LSA
     * @param borrower The address that created and owns this loan
     * @param depositAmount Initial USDC deposit amount (6 decimals)
     * @param loanAmount Total amount borrowed via flash loan (6 decimals)
     * @dev `loanAmount` is a historical record set at creation. It does not track accrued
     *      interest or reflect partial repayments. For live outstanding debt, read the variable
     *      debt token balance via `BitmorLendingPoolLogic.getVDTTokenAmount()`.
     * @param collateralAmount cbBTC amount user wants to achieve (8 decimals)
     * @param estimatedMonthlyPayment Estimated monthly payment calculated at creation (6 decimals)
     * @dev `estimatedMonthlyPayment` is computed once using the max variable borrow rate at loan
     *      creation time. It is not recalculated during the loan lifetime. It serves as the
     *      billing-period divisor for duration tracking and micro-liquidation sizing.
     * @param duration Loan term length in months
     * @param createdAt Unix timestamp when loan was created
     * @param insuranceID Insurance/Order ID for tracking this loan
     * @param lastPaymentTimestamp Timestamp at which last payment was made.
     * @param amountRepaidInCurrentPeriod Accumulated partial repayments within the current billing period (6 decimals)
     * @param status Current lifecycle status of the loan
     */
```

### Step 2: Verify loan-provider compiles

Run: `cd loan-provider && forge build`

Expected: Clean compilation.

### Step 3: Commit

```bash
git add loan-provider/src/libraries/types/DataTypes.sol
git commit -m "docs: document loanAmount and estimatedMonthlyPayment staleness (vuln-37)

Add @dev warnings clarifying that loanAmount is a historical record and
estimatedMonthlyPayment is computed once at creation. Direct consumers
to read live variable debt token balance for actual outstanding debt.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

## Task 3: Final verification

### Step 1: Run loan-provider unit tests

Run: `cd /Users/megabyte0x/Developer/bitmor/bitmor-core && make test:unit`

Expected: All tests pass.

### Step 2: Run lending-pool Bitmor tests

Run: `cd /Users/megabyte0x/Developer/bitmor/bitmor-core && make test:lp`

Expected: All tests pass.

### Step 3: Verify struct field ordering matches

Manually confirm both structs have identical field order:

| Index | loan-provider field | lending-pool field |
|-------|--------------------|--------------------|
| 0 | `address borrower` | `address borrower` |
| 1 | `uint256 depositAmount` | `uint256 depositAmount` |
| 2 | `uint256 loanAmount` | `uint256 loanAmount` |
| 3 | `uint256 collateralAmount` | `uint256 collateralAmount` |
| 4 | `uint256 estimatedMonthlyPayment` | `uint256 estimatedMonthlyPayment` |
| 5 | `uint256 duration` | `uint256 duration` |
| 6 | `uint256 createdAt` | `uint256 createdAt` |
| 7 | `uint256 insuranceID` | `uint256 insuranceID` |
| 8 | `uint256 lastPaymentTimestamp` | `uint256 lastPaymentTimestamp` |
| 9 | `uint256 amountRepaidInCurrentPeriod` | `uint256 amountRepaidInCurrentPeriod` |
| 10 | `LoanStatus status` | `LoanStatus status` |
