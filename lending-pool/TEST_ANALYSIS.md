# Bitmor Lending Pool - Test Analysis Report

**Generated:** 2026-01-16
**Test Run:** Node v22.20.0, Hardhat v3
**Total Tests:** 228 (100 passing, 128 failing)

---

## Executive Summary

This report analyzes the 128 failing tests in the Bitmor lending-pool module (Aave V2 fork) and categorizes them based on applicability to Bitmor's custom architecture.

**Key Findings:**
- **74% of failures (95 tests)** are NOT APPLICABLE due to intentional architectural changes
- **26% of failures (33 tests)** NEED FIXING - legitimate issues
- **Major gap:** Missing Bitmor-specific liquidation tests (micro/full liquidation)
- **Root cause:** Error '85' (`LP_CALLER_NOT_VAULT`) - deposits restricted to vault-only

---

## Test Results Overview

| Metric | Count | Percentage |
|--------|-------|------------|
| ✅ Passing Tests | 100 | 44% |
| ❌ Failing Tests | 128 | 56% |
| **Total Tests** | **228** | **100%** |

### Failure Breakdown

| Category | Count | % of Failures |
|----------|-------|---------------|
| ❌ Not Applicable | 95 | 74% |
| 🔧 Needs Fixing | 33 | 26% |

---

## Root Cause Analysis: Error '85'

### Error Definition
**Error Code '85'**: `LP_CALLER_NOT_VAULT` (from `protocol/libraries/helpers/Errors.sol`)

### Source Location
`contracts/protocol/lendingpool/LendingPool.sol:117`
```solidity
require(msg.sender == usdcVaultAddress, Errors.LP_CALLER_NOT_VAULT);
```

### Why This Breaks Tests
**Bitmor's Architectural Change:** Unlike Aave V2, Bitmor restricts deposits to come only through the USDC vault. Direct user deposits are prohibited.

**Impact:** ~95 Aave V2 tests attempt direct `pool.deposit()` calls from user accounts, which now fail by design.

---

## Category 1: NOT APPLICABLE Tests (95)

These tests are incompatible with Bitmor's architecture and should be **disabled or removed**.

### 1.1 Direct Deposit Tests (70 tests)

**Reason:** Bitmor requires deposits through USDC vault, not direct user deposits.

**Examples:**
- `atoken-transfer.spec.ts` - All transfer tests (8 tests)
  - "User 0 deposits 1000 DAI, transfers to user 1"
  - "User 1 tries to transfer DAI used as collateral"

- `scenario.spec.ts` - Deposit scenarios (15+ tests)
  - "Deposits WETH, borrows DAI"
  - "User deposits ETH and borrows"

- `weth-gateway.spec.ts` - All deposit tests (20+ tests)
  - "Deposit ETH via WETHGateway"
  - "Borrow variable WETH and repay with ETH"

- `pausable-functions.spec.ts` - Deposit pause tests (5 tests)

- `atoken-modifiers.spec.ts` - Deposit modifier tests (8 tests)

- `delegation-aware-atoken.spec.ts` - Delegation tests (6 tests)

- `variable-debt-token.spec.ts` - Debt token tests (8 tests)

**Affected Files:**
- `test-suites/test-aave/atoken-transfer.spec.ts`
- `test-suites/test-aave/scenario.spec.ts`
- `test-suites/test-aave/weth-gateway.spec.ts`
- `test-suites/test-aave/pausable-functions.spec.ts`
- `test-suites/test-aave/atoken-modifiers.spec.ts`
- `test-suites/test-aave/delegation-aware-atoken.spec.ts`
- `test-suites/test-aave/variable-debt-token.spec.ts`

### 1.2 Standard Aave Liquidation Tests (12 tests)

**Reason:** Bitmor uses custom micro/full liquidation logic, not standard Aave liquidation.

**Examples:**
- `liquidation-underlying.spec.ts` (6 tests)
  - "Liquidates the borrow"
  - "Tries to liquidate different currency"
  - Standard partial liquidation tests

- `liquidation-atoken.spec.ts` (6 tests)
  - "Liquidates half of the borrow"
  - "Liquidator receives aTokens"

**Key Difference:**
- **Aave V2:** Standard liquidation with configurable close factor
- **Bitmor:** `checkTypeOfLiquidation()` returns:
  - `0`: No liquidation
  - `1`: Full liquidation (uninsured, HF < 1)
  - `2`: Micro-liquidation (overdue payment)

**Affected Files:**
- `test-suites/test-aave/liquidation-underlying.spec.ts`
- `test-suites/test-aave/liquidation-atoken.spec.ts`

### 1.3 Collateral Management Tests (8 tests)

**Reason:** Different collateral handling through loan-provider module.

**Examples:**
- "Enable/disable reserves as collateral"
- "Set user use reserve as collateral"

**Affected Files:**
- Various scenario and configuration tests

### 1.4 Swap Adapter Tests (5 tests)

**Reason:** Bitmor uses Uniswap V4 via loan-provider module, not these adapters.

**Examples:**
- `paraswapAdapters.liquiditySwap.spec.ts`
- `uniswapAdapters.*.spec.ts` (Uniswap V2/V3 adapters)

**Affected Files:**
- `test-suites/test-aave/paraswapAdapters.liquiditySwap.spec.ts`
- `test-suites/test-aave/uniswapAdapters.*.spec.ts`

---

## Category 2: NEEDS FIXING Tests (33)

These tests should work but are failing due to configuration or implementation issues.

### 2.1 Configuration/Setup Issues (15 tests)

**Problem:** Test setup doesn't include vault mock, causing legitimate tests to fail.

**Solution:** Add USDC vault mock to test environment.

**Examples:**
- `configurator.spec.ts` - Configuration tests
  - "Deactivates the ETH reserve"
  - "Initialize reserves via LendingPoolConfigurator"

- `rate-strategy.spec.ts` - Interest rate tests
  - "Borrows a variable amount"
  - "User 0 deposits 100 DAI"

- `stable-rate-economy.spec.ts` - Stable rate tests

**Fix Required:**
```typescript
// In test setup (make-suite.ts)
const usdcVault = await deployMockUSDCVault();
await addressesProvider.setUSDCVault(usdcVault.address);

// Mock vault to forward deposits to pool
await usdcVault.setAllowDeposit(true);
```

**Affected Files:**
- `test-suites/test-aave/configurator.spec.ts` (~5 tests)
- `test-suites/test-aave/rate-strategy.spec.ts` (~5 tests)
- `test-suites/test-aave/stable-rate-economy.spec.ts` (~5 tests)

### 2.2 Flash Loan Mode 2 Tests (8 tests)

**Problem:** Flash loan mode 2 (borrow mode) attempts deposit, hitting vault restriction.

**Examples:**
- `flashloan.spec.ts`
  - "Takes WETH flashloan with mode = 2, does not return funds"
  - "Takes USDC flashloan with mode = 2, creates loan for caller"

**Investigation Needed:**
- Verify if flash loan mode 2 should work with vault
- May need to route through vault or disable mode 2

**Affected Files:**
- `test-suites/test-aave/flashloan.spec.ts` (~8 tests)

### 2.3 Interest Rate & Rebalance Tests (5 tests)

**Problem:** Core functionality tests failing due to setup issues.

**Examples:**
- "Borrows DAI, check interest rates"
- "Rebalances stable borrow rate"

**Solution:** Ensure vault is configured in test setup for these scenarios.

**Affected Files:**
- Various spec files with interest rate scenarios

### 2.4 Edge Cases (5 tests)

**Problem:** Various edge case scenarios need investigation.

**Examples:**
- "Deposit with referral code"
- "Borrow on behalf of user"
- Permission and delegation tests

**Affected Files:**
- Various spec files

---

## Category 3: NEEDS NEW TESTS

Critical gaps identified by comparing with loan-provider test suite.

### 3.1 Micro-Liquidation Tests (Inspired by loan-provider)

**Source Pattern:** `loan-provider/test/unit/MicroLiquidation.t.sol`

**Test Coverage Needed:**
```typescript
describe('Micro-Liquidation', () => {
  it('Should trigger micro-liquidation when payment overdue', async () => {
    // Setup: Create loan, warp past grace period
    // Assert: checkTypeOfLiquidation returns 2
  });

  it('Should liquidate exactly one EMI worth of collateral', async () => {
    // Setup: Overdue loan
    // Execute: microLiquidationCall
    // Assert: Collateral sold = EMI + bonus
  });

  it('Should update lastPaymentTimestamp after micro-liquidation', async () => {
    // Assert: Loan data updated correctly
  });

  it('Should not trigger micro-liquidation if payment current', async () => {
    // Assert: checkTypeOfLiquidation returns 0
  });

  it('Should revert micro-liquidation if insufficient collateral', async () => {
    // Setup: Low collateral scenario
    // Assert: Reverts with appropriate error
  });
});
```

**Key Functions to Test:**
- `LendingPoolCollateralManager.microLiquidationCall()`
- `LoanLiquidationLogic.checkTypeOfLiquidation()`
- `ValidationLogic.validateMicroLiquidation()`

**New File:** `test-suites/test-bitmor/micro-liquidation.spec.ts`

### 3.2 Full Liquidation Tests (Inspired by loan-provider)

**Source Pattern:** `loan-provider/test/unit/FullLiquidation.t.sol`

**Test Coverage Needed:**
```typescript
describe('Full Liquidation', () => {
  it('Should trigger full liquidation when HF < 1 and uninsured', async () => {
    // Setup: Drop price, no insurance
    // Assert: checkTypeOfLiquidation returns 1
  });

  it('Should liquidate entire position on full liquidation', async () => {
    // Execute: liquidationCall with max debt
    // Assert: Loan status = Liquidated, duration = 0
  });

  it('Should pay liquidation bonus to liquidator', async () => {
    // Assert: Liquidator receives collateral > debt paid
  });

  it('Should not allow full liquidation if only overdue (micro eligible)', async () => {
    // Setup: Overdue but healthy HF
    // Assert: Full liquidation reverts
  });

  it('Should respect insurance status in liquidation type', async () => {
    // Setup: HF < 1 but insured
    // Assert: Different liquidation behavior
  });
});
```

**Key Functions to Test:**
- `LendingPoolCollateralManager.liquidationCall()` (modified version)
- `LoanLiquidationLogic.checkTypeOfLiquidation()`
- `ValidationLogic.validateLiquidate()` (with `isInsured` parameter)

**New File:** `test-suites/test-bitmor/full-liquidation.spec.ts`

### 3.3 Integration Tests with loan-provider

**Test Coverage Needed:**
```typescript
describe('Lending Pool ↔ Loan Provider Integration', () => {
  it('Should accept deposits from loan-provider during loan initialization', async () => {
    // Simulate loan-provider calling deposit
  });

  it('Should track loan data from external Loan contract', async () => {
    // Test ILoan interface integration
  });

  it('Should correctly calculate liquidation type using loan data', async () => {
    // Test checkTypeOfLiquidation with real loan data
  });
});
```

**New File:** `test-suites/test-bitmor/loan-integration.spec.ts`

### 3.4 Test Helpers Needed

**Pattern from loan-provider:** `test/unit/Loan/BaseLoan.t.sol`

**Create Shared Test Helpers:**
```typescript
// test-suites/test-bitmor/helpers/bitmor-helpers.ts

export async function setupLoanScenario(
  pool: LendingPool,
  borrower: SignerWithAddress,
  collateralAmount: BigNumber,
  loanAmount: BigNumber,
  duration: number
) {
  // Create loan via loan-provider mock
  // Return loan LSA address
}

export async function setupForMicroLiquidation(
  lsa: string,
  timeWarp: number
) {
  // Warp time past grace period
  // Verify checkTypeOfLiquidation returns 2
}

export async function setupForFullLiquidation(
  lsa: string,
  priceDropPercent: number
) {
  // Drop oracle price
  // Verify checkTypeOfLiquidation returns 1
}
```

---

## Comparison: Aave vs Bitmor Liquidation

| Feature | Aave V2 | Bitmor |
|---------|---------|--------|
| **Liquidation Types** | Single type, partial allowed | Micro (type 2) + Full (type 1) |
| **Trigger** | Health factor < 1 | Type-dependent (overdue OR HF < 1) |
| **Close Factor** | Configurable (0-100%) | Micro: 1 EMI, Full: 100% |
| **Insurance** | Not applicable | Affects liquidation type |
| **Loan Tracking** | N/A | External Loan contract via ILoan |
| **Function** | `liquidationCall()` | `microLiquidationCall()` + `liquidationCall()` |

**Key Bitmor Addition:**
```solidity
// Returns: 0=none, 1=full, 2=micro
function checkTypeOfLiquidation(address user) external view returns (uint256);
```

---

## Priority Action Plan

### 🔴 Priority 1: CRITICAL (Week 1)

#### 1. Document Test Status
**Action:** Mark non-applicable tests as skipped with comments.

**Implementation:**
```typescript
// In liquidation-underlying.spec.ts
it.skip('Liquidates the borrow', async () => {
  // BITMOR: Skipped - Uses custom micro/full liquidation instead of Aave liquidation
  // See: test-bitmor/micro-liquidation.spec.ts and test-bitmor/full-liquidation.spec.ts
});
```

**Files to Update:**
- All Category 1 test files (95 tests)

#### 2. Create Vault Mock for Tests
**Action:** Implement mock USDC vault that forwards deposits to pool.

**New File:** `helpers/contracts-deployments/mock-usdc-vault.ts`
```typescript
export async function deployMockUSDCVault() {
  const MockVault = await ethers.getContractFactory('MockUSDCVault');
  return await MockVault.deploy();
}
```

**Update:** `test-suites/test-aave/helpers/make-suite.ts`
```typescript
before(async () => {
  // ... existing setup ...

  // Deploy and configure vault for Bitmor
  const usdcVault = await deployMockUSDCVault();
  await addressesProvider.setUSDCVault(usdcVault.address);
  await usdcVault.setLendingPool(pool.address);
});
```

#### 3. Implement Bitmor Liquidation Test Suite
**Action:** Create comprehensive tests based on loan-provider patterns.

**New Files:**
- `test-suites/test-bitmor/micro-liquidation.spec.ts` (~15 tests)
- `test-suites/test-bitmor/full-liquidation.spec.ts` (~15 tests)
- `test-suites/test-bitmor/helpers/bitmor-helpers.ts`

**Timeline:** 3-4 days

### 🟡 Priority 2: HIGH (Week 2)

#### 4. Fix Configuration Tests
**Action:** Update 15 configuration tests to use vault mock.

**Files:**
- `test-suites/test-aave/configurator.spec.ts`
- `test-suites/test-aave/rate-strategy.spec.ts`
- `test-suites/test-aave/stable-rate-economy.spec.ts`

**Pattern:**
```typescript
// Instead of direct deposit
await pool.connect(user).deposit(dai, amount, user.address, 0);

// Use vault helper
await depositViaVault(pool, user, dai, amount);
```

#### 5. Investigate Flash Loan Mode 2
**Action:** Determine if mode 2 should work with vault architecture.

**Options:**
- Route mode 2 deposits through vault
- Disable mode 2 entirely for Bitmor
- Document architectural decision

**Files:** `test-suites/test-aave/flashloan.spec.ts`

#### 6. Add Edge Case Coverage
**Action:** Fix or document 5 edge case tests.

**Examples:**
- Referral code functionality
- Delegation with vault
- On-behalf-of operations

### 🟢 Priority 3: MEDIUM (Week 3+)

#### 7. Integration Tests
**Action:** Create loan-provider ↔ lending-pool integration test suite.

**New File:** `test-suites/test-bitmor/loan-integration.spec.ts`

**Coverage:**
- Cross-module deposit flow
- Liquidation triggered by loan status
- Oracle price integration
- Vault collateral management

#### 8. Update Documentation
**Action:** Document all architectural changes and test status.

**Files:**
- Update `CLAUDE.md` with test categorization
- Create test migration guide for developers
- Document skipped tests and reasons

---

## File-by-File Test Status

### ✅ Fully Passing (8 files)
- `addresses-provider-registry.spec.ts` - Address provider tests
- `lending-pool-addresses-provider.spec.ts` - Core address provider
- `atoken-permit.spec.ts` - Permit functionality (no deposits)
- `stable-token.spec.ts` - Token mechanics (partial)
- `pausable-functions.spec.ts` - Pause/unpause (partial)
- `mainnet/check-list.spec.ts` - Mainnet checks
- `__setup.spec.ts` - Test environment setup
- `upgradeability.spec.ts` - Upgrade proxy tests

### ⚠️ Partially Passing (5 files)
- `configurator.spec.ts` - 60% passing, 40% failing (vault setup needed)
- `rate-strategy.spec.ts` - 50% passing, 50% failing (vault setup needed)
- `flashloan.spec.ts` - 70% passing, 30% failing (mode 2 issues)
- `scenario.spec.ts` - 30% passing, 70% failing (deposit scenarios)
- `stable-rate-economy.spec.ts` - 40% passing, 60% failing

### ❌ Fully Failing (13 files)
- `liquidation-underlying.spec.ts` - ❌ Not applicable (Aave liquidation)
- `liquidation-atoken.spec.ts` - ❌ Not applicable (Aave liquidation)
- `atoken-transfer.spec.ts` - ❌ Not applicable (direct deposits)
- `weth-gateway.spec.ts` - ❌ Not applicable (direct ETH deposits)
- `atoken-modifiers.spec.ts` - ❌ Not applicable (deposit modifiers)
- `delegation-aware-atoken.spec.ts` - ❌ Not applicable (delegation with deposits)
- `variable-debt-token.spec.ts` - ❌ Not applicable (direct borrow/deposit)
- `paraswapAdapters.liquiditySwap.spec.ts` - ❌ Not applicable (swap adapter)
- `uniswapAdapters.repay.spec.ts` - ❌ Not applicable (swap adapter)
- `uniswapAdapters.liquiditySwap.spec.ts` - ❌ Not applicable (swap adapter)
- `uniswapAdapters.flashLiquidation.spec.ts` - ❌ Not applicable (swap adapter)
- `uniswapAdapters.base.spec.ts` - ❌ Not applicable (swap adapter)
- `subgraph-scenarios.spec.ts` - ❌ Not applicable (deposit scenarios)

---

## Recommended Test Commands

```bash
# Run only passing tests (exclude known failures)
npm run test -- --grep "@skip-bitmor" --invert

# Run Bitmor-specific tests only (once created)
npm run test-bitmor

# Run with coverage
npm run test -- --coverage

# Run configuration tests (Priority 2)
npm run test -- test-suites/test-aave/configurator.spec.ts

# Run liquidation tests (once created)
npm run test -- test-suites/test-bitmor/micro-liquidation.spec.ts
npm run test -- test-suites/test-bitmor/full-liquidation.spec.ts
```

---

## Key Contract Locations

### Bitmor Custom Logic
- `contracts/protocol/lendingpool/LendingPool.sol:117` - Vault-only deposit check
- `contracts/protocol/lendingpool/LendingPoolCollateralManager.sol` - Micro/full liquidation
- `contracts/protocol/libraries/logic/LoanLiquidationLogic.sol` - Liquidation type logic
- `contracts/protocol/libraries/logic/ValidationLogic.sol` - Extended with `isInsured` checks
- `contracts/protocol/libraries/types/DataTypes.sol` - `LoanData` struct, `LoanStatus` enum

### Integration Points
- `contracts/interfaces/ILoan.sol` - External loan contract interface
- `contracts/interfaces/ILendingPool.sol` - Extended with `microLiquidationCall`, `checkTypeOfLiquidation`
- `contracts/interfaces/ILendingPoolCollateralManager.sol` - Micro-liquidation support

### Error Definitions
- `contracts/protocol/libraries/helpers/Errors.sol:85` - `LP_CALLER_NOT_VAULT`

---

## Loan-Provider Test Patterns to Replicate

### From `MicroLiquidation.t.sol` (Excellent Patterns)

```solidity
// 1. Comprehensive state snapshots
TestSnapshot memory snapshot = _captureTestSnapshot(lsa);
// Captures: loan data, balances, health factor

// 2. Liquidation setup helpers
uint256 liquidationType = _setupForMicroLiquidation(lsa);
// Warps time, checks type, funds liquidator

// 3. Execution helpers
_executeMicroLiquidation(lsa);
// Handles approvals, calls, assertions

// 4. State comparison
_updateLiquidationStateAfter(state, lsa);
// Calculates deltas, validates changes
```

**Recommended:** Replicate these patterns in `test-suites/test-bitmor/helpers/bitmor-helpers.ts`

---

## Success Metrics

**Week 1 Completion:**
- [ ] All 95 non-applicable tests marked as skipped with comments
- [ ] Vault mock created and integrated into test setup
- [ ] Bitmor liquidation test suite created with 30+ tests
- [ ] Test categorization documented in CLAUDE.md

**Week 2 Completion:**
- [ ] 15 configuration tests fixed and passing
- [ ] Flash loan mode 2 investigation completed with decision documented
- [ ] Edge case tests resolved

**Week 3 Completion:**
- [ ] Integration test suite created
- [ ] Documentation updated
- [ ] Test pass rate improved to 80%+

---

## Conclusion

The 128 failing tests are primarily (74%) due to intentional architectural changes in Bitmor, not bugs. The main action items are:

1. **Document non-applicable tests** - Quick win, clarifies intent
2. **Create vault mock** - Unblocks 33 legitimate tests
3. **Implement Bitmor liquidation tests** - Fills critical gap in test coverage

The loan-provider test suite provides excellent patterns to follow for comprehensive liquidation testing.

---

**Report Generated By:** Claude Code
**Analysis Date:** 2026-01-16
**Test Environment:** Node v22.20.0, Hardhat v3, lending-pool module
**Source Files Analyzed:** 26 test spec files, test-results.log (304KB)
