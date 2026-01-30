# Session Continuation - Test Setup Fixes

> **For Claude:** This document tracks implementation progress and provides context for session continuations.

**Branch:** `fix/testSetup`
**Last Updated:** 2026-01-23

---

## Completed Work

### Task 10: Fix Insurance.t.sol (Completed)
- Added `_createInsuredLoanWithMockId` helper
- Fixed insurance ID setup in tests
- Status: **4/7 tests passing** (3 tests have separate issues with premium validation logic)

### Task 11: Fix FullLiquidation.t.sol (Completed)
- Added `mockBitmorPool.setHealthFactor(lsa, value)` to tests requiring unhealthy loan state
- Added `_setLiquidationType(lsa, LIQUIDATION_TYPE_FULL)` for liquidation eligibility
- Commit: `fb827fa test: migrate BaseTestForBTCVault to mock tokens`
- Status: **13/13 tests passing**

### Task 12: Fix MicroLiquidation.t.sol (Completed)
- Added `mockBitmorPool.setUserOverdue(lsa, true)` for overdue state
- Added `_setLiquidationType(lsa, LIQUIDATION_TYPE_MICRO)` for micro-liquidation eligibility
- Fixed mock's monthly payment calculation to use actual loan data (`loanData.estimatedMonthlyPayment`)
- Fixed collateral calculation with proper oracle price conversion
- Status: **12/12 tests passing**

### Task 13: Fix LendingPool.t.sol (Completed - 2026-01-23)
**Issues Fixed:**

1. **AccessManager permission errors** (`test_highUtilization_100pct_12PaymentsFullyRepayLoan`, `test_lowUtilization_90pct_finalPaymentOvercoversDebt`):
   - Root cause: `vm.prank(admin)` was consumed by `EXECUTOR_ID()` external call to `rolesData.EXECUTOR()` before reaching `manager.grantRole()`
   - Fix: Cache role ID before prank in `_createLoanForBorrower()` (BaseLoan.t.sol:195-197)

2. **Borrow revert tests** (`test_lendingPool_borrowBTC_revertsForUser`, `test_lendingPool_borrowUSDC_revertsForUser`):
   - Root cause: Mock had no access control on `borrow()`
   - Fix: Added check in MockBitmorLendingPool.sol to only allow Loan contract to borrow (lines 148-152)

3. **LoanIsNotActive error** (`test_lowUtilization_90pct_finalPaymentOvercoversDebt`):
   - Root cause: At 90% utilization with lower interest, loan paid off in 11 months, triggering auto-close before 12th payment
   - Fix: Reduced loop from 11 to 10 iterations (LendingPool.t.sol:180)

4. **Monthly payment calculation** (`test_monthlyPaymentCalculation_amortizesAtMaxRate`):
   - Root cause: Mock's default rate was 5%, but test expected 20% (MAX_APR_BPS)
   - Fix: Added `setVariableBorrowRate()` helper to mock and set rate in test (MockBitmorLendingPool.sol:457-462)

5. **Side effect fix - InitializeLoan.t.sol**:
   - The borrow access control broke `test_initializeLoan_flashLoanIntegration_success`
   - Fix: Register loan2 in addresses provider (InitializeLoan.t.sol:222-223)

**Commit:** `2f4dcd4 test: fix LendingPool.t.sol tests`

**Status:** **7/7 tests passing**

---

## Test Status Summary

| Test File | Status | Notes |
|-----------|--------|-------|
| `Loan/InitializeLoan.t.sol` | 12/12 passing | |
| `Loan/RepayLoan.t.sol` | 17/17 passing | |
| `Loan/CloseLoan.t.sol` | 16/16 passing | |
| `Loan/LoanContract.t.sol` | 10/10 passing | |
| `MicroLiquidation.t.sol` | 12/12 passing | |
| `FullLiquidation.t.sol` | 13/13 passing | |
| `LendingPool.t.sol` | 7/7 passing | |
| `Insurance.t.sol` | 4/7 passing | Premium validation tests failing (separate issue) |

**Total: 87/90 tests passing**

---

## Key Code Changes

### MockBitmorLendingPool.sol
New test helpers added:
```solidity
/// @notice Set the variable borrow rate for a reserve (test helper)
function setVariableBorrowRate(address asset, uint256 rate) external {
    _reserves[asset].currentVariableBorrowRate = uint128(rate);
}
```

Added borrow access control:
```solidity
function borrow(...) external override {
    address bitmorLoan = _addressesProvider.getBitmorLoan();
    if (msg.sender != bitmorLoan) {
        revert Errors.UnauthorizedCaller();
    }
    // ... rest of function
}
```

### BaseLoan.t.sol
Fixed role grant to cache ID before prank:
```solidity
function _createLoanForBorrower(...) internal returns (address lsa) {
    // Cache role ID before prank to avoid consuming the prank
    uint64 executorRoleId = EXECUTOR_ID();

    vm.prank(admin);
    manager.grantRole(executorRoleId, borrower, NO_DELAY);
    // ...
}
```

---

## Known Issues (Not in Scope)

### Insurance.t.sol - 3 Failing Tests
These failures are unrelated to the test infrastructure fixes:
1. `test_insurance_initializeLoan_premiumBelowEstimate_reverts` - Premium validation logic
2. `test_insurance_initializeLoan_premiumAboveEstimate_refundsExcess` - Premium collector balance
3. `test_insurance_fullLiquidation_overdue_claimAfter1Day_paysLiquidatorPlus3pct` - Max debt coverage

These require investigation into the premium validation logic in the Loan contract, not test fixes.

---

## Next Steps

1. **Insurance Premium Logic**: Investigate why premium validation tests fail
2. **AutoRepayment.t.sol**: Check if tests need similar fixes
3. **Vault Tests**: Verify BTCVault and USDCVault tests pass with mock infrastructure

---

## Important Context for Session Continuation

When continuing work on this branch:

1. **Run tests first**: `forge test --match-path 'test/unit/Loan/*.t.sol'` to verify current state
2. **Mock helpers available**:
   - `mockBitmorPool.setHealthFactor(lsa, value)` - For full liquidation tests
   - `mockBitmorPool.setUserOverdue(lsa, bool)` - For micro liquidation tests
   - `mockBitmorPool.setLiquidationType(lsa, type)` - Direct liquidation type control
   - `mockBitmorPool.setVariableBorrowRate(asset, rate)` - For interest rate tests
   - `mockBitmorPool.setInsuranceId(lsa, id)` - For insurance tests

3. **vm.prank gotcha**: When using `vm.prank(admin)` before `manager.grantRole()`, cache external call results (like `EXECUTOR_ID()`) BEFORE the prank to avoid consuming it.

4. **Borrow access control**: MockBitmorLendingPool now requires caller to be registered Loan contract. Tests creating separate Loan instances must register them via `mockAddressesProvider.setBitmorLoan(address)`.
