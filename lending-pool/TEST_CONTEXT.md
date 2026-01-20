# Test Context for Claude Code

**Purpose:** This file provides complete context about the lending-pool test analysis work. Use this when resuming work on test fixes.

---

## Current Situation

### What We Did (2026-01-16)

We ran the full Aave test suite in the lending-pool module and discovered **256 failing tests** out of 228 total tests (100 passing, 128 failing).

### The Problem

**Root Cause:** Bitmor made an architectural change to Aave V2 - all deposits MUST go through the USDC Vault. Direct user deposits are blocked.

**Error Code 85:** `LP_CALLER_NOT_VAULT`
**Location:** `contracts/protocol/lendingpool/LendingPool.sol:117`
```solidity
require(msg.sender == usdcVaultAddress, Errors.LP_CALLER_NOT_VAULT);
```

**Impact:** 93.75% of failing tests (240 tests) are NOT APPLICABLE because they attempt direct user deposits, which Bitmor prohibits by design.

---

## Key Documents Created

### 1. TEST_ANALYSIS.md (High-Level Summary)
**Size:** 19KB
**Purpose:** Executive summary for CTO review
**Contents:**
- Overview of 256 failing tests
- Categories: NOT APPLICABLE (95 tests) vs NEEDS FIXING (33 tests)
- 3-week action plan
- Priority recommendations
- New test cases needed (45+ tests)

### 2. COMPREHENSIVE-TEST-ANALYSIS.md (Detailed Breakdown)
**Size:** 72KB, 2,161 lines
**Purpose:** Developer-ready actionable guide
**Contents:**

**Section 1: Quick Reference Table (Lines 1-200)**
- All 256 failing tests in table format
- Test # | Name | File | Category | Action

**Section 2: Detailed Test-by-Test Analysis (Lines 200-1250)**
- Each test analyzed with:
  - What it tests
  - Why it fails
  - Specific action (skip or fix)
  - Code examples

**Section 3: NEW TEST CASES REQUIRED (Lines 1251-1898)**
- 45+ new test specifications
- 7 new test files to create
- Full setup/execute/assertions for each
- Complete TypeScript code examples

**Section 4: Implementation Guidelines (Lines 1899-2161)**
- 5-week implementation roadmap
- Helper functions with code
- File mappings
- Error reference

### 3. test-results.log
**Size:** 304KB
**Purpose:** Raw test output from `npm run test`
**Command used:** `source ~/.nvm/nvm.sh && nvm use 22 && npm run test 2>&1 | tee test-results.log`

---

## Test Categorization Summary

### Category 1: NOT APPLICABLE (~240 tests, 93.75%)

**These tests conflict with Bitmor's architecture and should be SKIPPED:**

1. **Direct User Deposits** - Users can't deposit directly, only vault can
2. **Standard Aave Liquidation** - Bitmor uses custom micro/full liquidation
3. **AToken Transfers Without Loans** - No direct deposits = no aTokens to transfer
4. **Collateral Management Without LSA** - Collateral managed via LoanVault (LSA)
5. **Swap Rate Mode** - Bitmor has fixed loan terms
6. **Rebalance Stable Rate** - Not applicable to Bitmor
7. **AMM Adapter Tests** - Different swap mechanism (Uniswap V4)
8. **WETH Gateway** - Bitmor uses USDC/cbBTC, not ETH

**Action:** Skip all with comments explaining Bitmor architecture

### Category 2: NEEDS FIXING (~16 tests, 6.25%)

**These tests validate core functionality still relevant to Bitmor:**

1. **Flash Loan Tests (26 tests)** - Critical for Loan.initializeLoan() flow
   - File: `flashloan.spec.ts`
   - Action: Fix with vault helper function

2. **Liquidation Tests (24 tests)** - Validates Bitmor's micro/full liquidation
   - Files: `liquidation-atoken.spec.ts`, `liquidation-underlying.spec.ts`
   - Action: Adapt for LSA and custom liquidation types

3. **Flash Liquidation Tests (14 tests)** - For liquidator flows
   - File: `uniswapAdapters.flashLiquidation.spec.ts`
   - Action: Integrate with Bitmor liquidation types

**Action:** Fix by adding vault helpers and LSA support

---

## New Tests Required (45+ tests)

### Category A: Core Liquidation Tests (17 tests)

**File 1: `test-suites/test-bitmor/micro-liquidation.spec.ts` (10 tests)**
Inspired by: `loan-provider/test/unit/MicroLiquidation.t.sol`

Tests:
1. Payment overdue execution
2. Exact debt paid calculation
3. Liquidation bonus application
4. Debt destination verification
5. Multiple liquidations over time
6. Revert if not overdue
7. Revert if insufficient collateral
8. Receive aToken = true
9. Receive aToken = false
10. Last payment behavior

**File 2: `test-suites/test-bitmor/full-liquidation.spec.ts` (7 tests)**
Inspired by: `loan-provider/test/unit/FullLiquidation.t.sol`

Tests:
1. Low health factor trigger (HF < 1, uninsured)
2. Insurance status impact on liquidation
3. Price drop before payment due
4. Liquidation bonus calculation
5. All collateral seized validation
6. Loan status update to Liquidated
7. Cannot partial liquidate in full mode

### Category B: Vault Integration Tests (5 tests)

**File 3: `test-suites/test-bitmor/usdc-vault-deposits.spec.ts`**

Tests:
1. Vault can deposit to pool successfully
2. Direct user deposit reverts with error 85
3. Vault-mediated borrow flow
4. Vault withdrawal flow
5. Multiple vaults handling

### Category C: Loan Data Tracking Tests (5 tests)

**File 4: `test-suites/test-bitmor/loan-data-tracking.spec.ts`**

Tests:
1. LoanData struct populated after initialization
2. LSA address storage and retrieval
3. Multiple loans per user tracking
4. Loan status transitions (Active -> Completed/Liquidated)
5. Duration countdown on micro-liquidation

### Category D: Insurance Parameter Tests (5 tests)

**File 5: `test-suites/test-bitmor/insurance-parameters.spec.ts`**

Tests:
1. Uninsured loan liquidates at HF < 1
2. Insured loan has different threshold
3. Insurance ID storage and retrieval
4. Update insurance ID functionality
5. Multiple insurance levels behavior

### Category E: LSA Isolation Tests (5 tests)

**File 6: `test-suites/test-bitmor/loan-vault-isolation.spec.ts`**

Tests:
1. Each LSA has separate collateral
2. Each LSA has separate debt
3. Each LSA has independent health factor
4. Only Loan contract can interact with LSA
5. LSA addresses are deterministic (CREATE2)

### Category F: Edge Cases (8 tests)

**File 7: `test-suites/test-bitmor/edge-cases.spec.ts`**

Tests:
1. Zero deposit revert
2. Zero collateral revert
3. Zero duration revert
4. Excessive leverage handling
5. Micro-liquidation on final payment
6. Dust amounts handling
7. Extreme price movements
8. Multiple simultaneous liquidations

---

## Implementation Roadmap

### Week 1: Setup Test Helpers

**Create helper files:**

1. **`test-suites/test-aave/helpers/vault-helpers.ts`**
   ```typescript
   export async function depositViaVault(
     asset: string,
     amount: BigNumber,
     poolAddress: string,
     testEnv: TestEnv
   ): Promise<void> {
     const { usdcVault, users } = testEnv;
     const depositor = users[0];

     // Mint asset to depositor
     await asset.connect(depositor.signer).mint(amount);

     // Approve vault
     await asset.connect(depositor.signer).approve(usdcVault.address, amount);

     // Deposit via vault (vault will call pool.deposit)
     await usdcVault.connect(depositor.signer).deposit(asset, amount, depositor.address);
   }

   export async function setupFlashLoanLiquidity(
     testEnv: TestEnv,
     wethAmount?: BigNumber,
     daiAmount?: BigNumber,
     usdcAmount?: BigNumber
   ): Promise<void> {
     // Implementation to setup liquidity via vault for flash loan tests
   }
   ```

2. **`test-suites/test-aave/helpers/bitmor-loan-helpers.ts`**
   ```typescript
   export async function createBitmorLoan(
     params: BitmorLoanParams
   ): Promise<string> {
     // Create loan via Loan contract
     // Returns LSA address
   }

   export async function dropHealthFactor(
     lsa: string,
     targetHF: BigNumber,
     testEnv: TestEnv
   ): Promise<void> {
     // Manipulate oracle to drop health factor
   }

   export async function warpPastGracePeriod(
     lsa: string,
     testEnv: TestEnv
   ): Promise<void> {
     // Warp time past grace period for micro-liquidation
   }
   ```

3. **Update `test-suites/test-aave/helpers/make-suite.ts`**
   - Add USDC Vault to test environment
   - Add Loan contract to test environment
   - Add cbBTC mock if needed

### Week 2: Fix Critical Tests & Skip Non-Applicable

**Priority 1: Flash Loan Tests (26 tests)**
- Update `flashloan.spec.ts` to use `depositViaVault()` helper
- Update all deposit calls to go through vault

**Priority 2: Liquidation Tests (24 tests)**
- Update `liquidation-atoken.spec.ts` and `liquidation-underlying.spec.ts`
- Change from user addresses to LSA addresses
- Add `createBitmorLoan()` calls for setup
- Add `checkTypeOfLiquidation()` validation

**Priority 3: Skip Non-Applicable Tests**
- Add `.skip()` to all 240 NOT APPLICABLE tests
- Add comments explaining Bitmor architecture differences

### Week 3-4: Create New Bitmor Tests

**Priority Order:**
1. Micro-liquidation suite (CRITICAL)
2. Full liquidation suite (CRITICAL)
3. Vault integration tests (HIGH)
4. Loan data tracking (MEDIUM)
5. Insurance parameters (MEDIUM)
6. LSA isolation (MEDIUM)
7. Edge cases (LOW)

### Week 5: Integration Testing & Documentation

- End-to-end loan lifecycle tests
- Multi-user scenarios
- Update test README
- Create test coverage report

---

## Key Bitmor Concepts

### Liquidation Types

Bitmor has a custom liquidation system determined by `checkTypeOfLiquidation(address user)`:

**Type 0: No Liquidation**
- Loan is inactive OR
- Payment not overdue

**Type 1: Full Liquidation**
- Uninsured AND health factor < 1
- OR collateral cannot cover micro-liquidation
- OR remaining collateral < guard amount after micro-liquidation
- Liquidates entire position

**Type 2: Micro-Liquidation**
- Payment overdue (lastPayment + grace + interval < now)
- Collateral sufficient to cover one EMI + bonus
- Remaining collateral covers remaining debt + bonus
- Liquidates exactly one monthly payment worth

### LoanVault (LSA) Architecture

Each loan has its own **Loan Smart Account (LSA)** deployed via CREATE2:
- Holds aTokens (collateral)
- Holds debt tokens
- Isolated from other loans
- Only Loan contract can interact
- Deterministic address

### Loan Data Structure

```solidity
struct LoanData {
    address borrower;
    uint256 depositAmount;        // USDC 6 decimals
    uint256 loanAmount;           // USDC 6 decimals
    uint256 collateralAmount;     // cbBTC 8 decimals
    uint256 estimatedMonthlyPayment;
    uint256 duration;             // Months remaining
    uint256 createdAt;
    uint256 insuranceID;          // 0 = uninsured
    uint256 lastPaymentTimestamp;
    LoanStatus status;            // Active, Completed, Liquidated
}
```

### Integration Points

**Lending Pool ↔ Loan Provider:**
1. Loan contract calls `pool.deposit()` via vault during initialization
2. Pool reads loan data via `ILoan` interface
3. `checkTypeOfLiquidation()` queries external Loan contract
4. Liquidations interact with LSA addresses, not user addresses

---

## Important Files & Locations

### Bitmor Core Contracts
- `contracts/protocol/lendingpool/LendingPool.sol:117` - Vault-only deposit check
- `contracts/protocol/lendingpool/LendingPoolCollateralManager.sol` - Micro/full liquidation
- `contracts/protocol/libraries/logic/LoanLiquidationLogic.sol` - Liquidation type logic
- `contracts/protocol/libraries/logic/ValidationLogic.sol` - Extended validation with insurance
- `contracts/protocol/libraries/types/DataTypes.sol` - LoanData struct
- `contracts/protocol/libraries/helpers/Errors.sol` - Error code 85 definition
- `contracts/interfaces/ILoan.sol` - External loan contract interface

### Loan Provider Contracts (Reference)
- `../loan-provider/src/protocol/Loan.sol` - Loan initialization
- `../loan-provider/src/protocol/LoanVault.sol` - LSA implementation
- `../loan-provider/src/vaults/usdc-vault/USDCVault.sol` - Real USDC Vault

### Test Files
- `test-suites/test-aave/` - Original Aave V2 tests (need fixing/skipping)
- `test-suites/test-bitmor/` - New Bitmor-specific tests (TO BE CREATED)
- `test-suites/test-aave/helpers/make-suite.ts` - Test environment setup
- `test-suites/test-aave/helpers/vault-helpers.ts` - TO BE CREATED
- `test-suites/test-aave/helpers/bitmor-loan-helpers.ts` - TO BE CREATED

### Test Patterns to Replicate
- `../loan-provider/test/unit/MicroLiquidation.t.sol` - Excellent micro-liquidation patterns
- `../loan-provider/test/unit/FullLiquidation.t.sol` - Excellent full liquidation patterns
- `../loan-provider/test/unit/Loan/BaseLoan.t.sol` - Excellent helper pattern

---

## Commands

### Run Tests
```bash
# Switch to Node 22 (required for Hardhat v3)
source ~/.nvm/nvm.sh && nvm use 22

# Compile
npm run compile

# Run all Aave tests (currently 100 passing, 128 failing)
npm test

# Run Bitmor-specific tests (once created)
npm run test-bitmor

# Run specific test file
npm run compile && TS_NODE_TRANSPILE_ONLY=1 npx hardhat test ./test-suites/test-aave/flashloan.spec.ts

# Run with fork
FORK=main npm run compile && TS_NODE_TRANSPILE_ONLY=1 npx hardhat test ./test-suites/test-aave/scenario.spec.ts
```

### Deploy
```bash
# Deploy to Base Sepolia
npm run aave:baseSepolia:full:migration

# Local development
npm run bitmor:localhost:dev:migration

# Format
npm run prettier:write
```

---

## Common Issues & Solutions

### Issue 1: Error 85 (LP_CALLER_NOT_VAULT)

**Symptom:** Tests fail with "reverted with reason string '85'"

**Cause:** Test attempts direct user deposit to pool

**Solution:** Use `depositViaVault()` helper instead of `pool.deposit()`

**Example:**
```typescript
// ❌ WRONG (causes error 85)
await pool.connect(user.signer).deposit(asset, amount, user.address, 0);

// ✅ CORRECT
await depositViaVault(asset, amount, pool.address, testEnv);
```

### Issue 2: Liquidation Tests Fail

**Symptom:** Liquidation calls revert or liquidationType is wrong

**Cause:** Tests use user addresses instead of LSA addresses

**Solution:**
1. Create loan via `createBitmorLoan()` to get LSA address
2. Use LSA address in liquidation call
3. Check `pool.checkTypeOfLiquidation(lsa)` before liquidating

**Example:**
```typescript
// ✅ CORRECT
const lsa = await createBitmorLoan({ user: borrower, ... });
await dropHealthFactor(lsa, parseEther('0.8'), testEnv);
const liquidationType = await pool.checkTypeOfLiquidation(lsa);
expect(liquidationType).to.equal(1); // Full liquidation

await pool.liquidationCall(collateral, debt, lsa, maxUint256, false);
```

### Issue 3: Node Version

**Symptom:** `TypeError: plugins.toReversed is not a function`

**Cause:** Using Node 18, but Hardhat v3 requires Node 22+

**Solution:** Use `nvm use 22` before running tests

---

## Test Status Summary

| Category | Count | % | Action |
|----------|-------|---|--------|
| ✅ Passing | 100 | 44% | Keep as-is |
| ❌ Not Applicable | 240 | 93.75% of failures | Skip with comments |
| 🔧 Needs Fixing | 16 | 6.25% of failures | Fix with vault helpers |
| ➕ New Tests Needed | 45+ | N/A | Create from scratch |

**Target:** 80%+ pass rate after fixes and new tests

---

## Next Steps for Claude

When resuming work on this project:

1. **Read this file first** to understand context
2. **Review COMPREHENSIVE-TEST-ANALYSIS.md** for detailed breakdown
3. **Start with Week 1 tasks** (create helpers)
4. **Ask user which priority** they want to tackle:
   - Fix flash loan tests (26 tests)
   - Fix liquidation tests (24 tests)
   - Create new micro-liquidation tests (10 tests)
   - Create new full liquidation tests (7 tests)
   - Skip non-applicable tests (240 tests)

---

## Questions to Ask User

If you need clarification:

1. **Mock vs Real Vault:** Should tests use mock USDC Vault or the real one from loan-provider?
   - Mock: Faster, simpler, Solidity 0.6.12 compatible
   - Real: True integration testing, Solidity 0.8.30

2. **Priority:** Which week should we start with?
   - Week 1: Create helpers
   - Week 2: Fix critical tests
   - Week 3-4: Create new tests

3. **Scope:** Should we fix all 256 tests or focus on new Bitmor tests?

---

**Last Updated:** 2026-01-16
**Session:** Test analysis and categorization
**Status:** Analysis complete, ready for implementation
