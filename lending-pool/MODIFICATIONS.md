# Bitmor Lending Pool Modifications

This document tracks all modifications made to the Aave V2 codebase for Bitmor protocol's vault architecture.

## Overview

Bitmor uses a vault architecture where users own ERC20 vault shares, while vaults own aTokens (the actual collateral in the lending pool). This creates fundamental differences from standard Aave V2 where users own aTokens directly.

## Critical Architecture Constraints

### Vault Share vs aToken Ownership

**Standard Aave V2**: Users own aTokens directly → Pool recognizes user collateral

**Bitmor**: Users own vault shares → Vaults own aTokens → Pool recognizes only vault's collateral

**Impact**: Users cannot borrow or use standard flash loan modes (1 & 2) because the lending pool does not recognize vault shares as collateral.

---

## Code Modifications

### 1. Flash Loans Disabled (Error 86)

**File**: `contracts/protocol/lendingpool/LendingPool.sol`

**Reason**: Flash loan modes 1 and 2 require users to have collateral (aTokens) in the pool. In Bitmor's vault architecture, users own vault shares while vaults own the aTokens. The lending pool only recognizes aTokens as collateral, not vault shares. Mode 0 (standard flash loan) would technically work, but for consistency and security, all flash loan functionality is disabled.

**Changes**:
- Added immediate revert in `flashLoan()` function with error code 86
- Original flash loan code preserved below the revert for reference (unreachable)
- Added detailed comment block explaining the architectural reason

**Error Code**: `LP_FLASHLOAN_DISABLED = '86'`

**Test Changes**: `test-suites/test-aave/flashloan.spec.ts` - All tests now verify flash loans revert with error 86 for all modes (0, 1, 2)

---

### 2. Borrowing Requires aToken Collateral (Error 9)

**Existing Behavior**: When users try to borrow using vault shares as collateral, the pool sees zero collateral balance and reverts with error 9 (`VL_COLLATERAL_BALANCE_IS_0`)

**No Code Changes Required**: The existing validation logic correctly prevents borrowing when the pool does not recognize collateral.

**Test Changes**: Tests updated to expect error 9 when users attempt to borrow with vault shares as collateral.

**Example**: `test-suites/test-aave/atoken-transfer.spec.ts` - Tests verify that borrowing with vault shares fails with error '9'

---

### 3. Deposit Restriction - Vault-Only (Error 85)

**Existing Behavior**: `LendingPool.deposit()` includes check that only the registered vault contract can deposit assets.

**Error Code**: `LP_CALLER_NOT_VAULT = '85'`

**Impact**: All deposits must go through vault contracts. Direct user deposits to the pool are not allowed.

---

### 4. Multi-Vault System

**Problem**: Different assets (DAI, USDC, WETH) require separate vault instances, but only one vault can be registered in AddressesProvider at a time.

**Solution**: Implemented multiple vault deployments with automatic vault switching.

#### Vault Deployments

**File**: `test-suites/test-aave/__setup.spec.ts`

Three vaults deployed:
1. `MockUSDCVault` (handles DAI) - Legacy vault for DAI deposits
2. `MockActualUSDCVault` (handles USDC) - Real USDC deposits
3. `MockWETHVault` (handles WETH) - WETH deposits

#### Deployment Functions

**File**: `helpers/contracts-deployments.ts`

Added:
- `deployMockActualUSDCVault()` - Deploys USDC vault
- `deployMockWETHVault()` - Deploys WETH vault

#### Getter Functions

**File**: `helpers/contracts-getters.ts`

Added:
- `getMockActualUSDCVault()` - Retrieves deployed USDC vault
- `getMockWETHVault()` - Retrieves deployed WETH vault

#### Test Environment

**File**: `test-suites/test-aave/helpers/make-suite.ts`

Added to `TestEnv` interface:
- `actualUSDCVault: MockUSDCVault` - USDC vault reference
- `wethVault: MockUSDCVault` - WETH vault reference

---

### 5. Deposit Helper with Auto-Vault Selection

**File**: `test-suites/test-aave/helpers/vault-helpers.ts`

**Function**: `depositViaVault()`

**Purpose**: Automatically selects the correct vault based on the asset being deposited and switches the active vault in AddressesProvider.

**Logic**:
```
If asset == WETH → use wethVault
Else if asset == USDC → use actualUSDCVault
Else → use usdcVault (DAI and others)
```

**Vault Switching**:
- Checks current registered vault via `addressesProvider.getUSDCVault()`
- If different from required vault, calls `addressesProvider.setUSDCVault(newVault)`
- This ensures only the correct vault can pass the Error 85 check

**Process**:
1. Select correct vault based on asset type
2. Switch to correct vault in AddressesProvider if needed
3. Mint tokens to user
4. User approves vault
5. Vault executes deposit (vault owns resulting aTokens)
6. Returns vault shares to user (1:1 for mock vaults)

---

## Error Code Summary

| Code | Constant | Meaning | Source |
|------|----------|---------|--------|
| 9 | `VL_COLLATERAL_BALANCE_IS_0` | User has no collateral (vault shares not recognized) | Existing Aave validation |
| 85 | `LP_CALLER_NOT_VAULT` | Only vault can deposit assets | Existing Bitmor restriction |
| 86 | `LP_FLASHLOAN_DISABLED` | Flash loans disabled in Bitmor | New - added for vault architecture |

---

## Test Suite Changes

### flashloan.spec.ts
- **Before**: 20+ tests for flash loan modes, fees, debt positions
- **After**: 4 simple tests verifying error 86 for modes 0, 1, and 2
- **Removed**: All complex flash loan execution tests (no longer applicable)

### atoken-transfer.spec.ts
- **Changed**: Tests expecting borrowing now expect error 9
- **Added**: Vault switching logic before deposits
- **Updated**: All deposits use `depositViaVault()` helper

### Other Test Files (105 remaining failures)
- **Issue**: Still use direct `pool.deposit()` calls
- **Fix Required**: Replace with `depositViaVault()` calls
- **Affected Files**:
  - Liquidation tests
  - Borrow/repay tests
  - Deposit/withdraw tests
  - Collateral management tests
  - Interest rate tests
  - Credit delegation tests

---

## Configuration Files

### helpers/types.ts
Added error code:
```typescript
LP_FLASHLOAN_DISABLED = '86'
```

### contracts/protocol/libraries/helpers/Errors.sol
Added error constant:
```solidity
string public constant LP_FLASHLOAN_DISABLED = '86';
```

### helpers/contracts-helpers.ts
Added contract ID enums:
```typescript
MockActualUSDCVault = 'MockActualUSDCVault'
MockWETHVault = 'MockWETHVault'
```

---

## Audit Notes

### Security Considerations

1. **Flash Loan Disable**: Complete disable prevents any flash loan attacks. Original code preserved for reference but unreachable.

2. **Vault-Only Deposits**: Error 85 check ensures only authorized vault contracts can deposit. This prevents users from bypassing the vault share system.

3. **Collateral Isolation**: Users cannot use vault shares as collateral for borrowing. This is correct behavior - only aTokens (held by vaults) represent actual pool collateral.

4. **Vault Switching**: Single active vault design requires careful vault selection before deposits. The `depositViaVault()` helper automates this to prevent Error 85 failures.

### Known Limitations

1. **No User Borrowing**: Users cannot borrow against their vault shares. This is intentional due to the vault architecture.

2. **No Flash Loans**: Flash loan functionality completely disabled for architectural consistency.

3. **Single Active Vault**: Only one vault can be registered at a time, requiring vault switching for different asset deposits.

4. **Test Coverage**: 105 tests still need updates to use vault deposit helpers instead of direct pool deposits.

---

## Files Modified

### Solidity Contracts
- `contracts/protocol/lendingpool/LendingPool.sol` - Flash loan disable
- `contracts/protocol/libraries/helpers/Errors.sol` - Error code 86

### TypeScript Helpers
- `helpers/types.ts` - Error code enum
- `helpers/contracts-deployments.ts` - Vault deployment functions
- `helpers/contracts-getters.ts` - Vault getter functions
- `helpers/contracts-helpers.ts` - Contract ID enums

### Test Infrastructure
- `test-suites/test-aave/__setup.spec.ts` - Deploy all vaults
- `test-suites/test-aave/helpers/make-suite.ts` - TestEnv with vault references
- `test-suites/test-aave/helpers/vault-helpers.ts` - Auto-vault selection deposit helper

### Test Files
- `test-suites/test-aave/flashloan.spec.ts` - Complete rewrite for disabled flash loans
- `test-suites/test-aave/atoken-transfer.spec.ts` - Updated for vault deposits and error 9

---

## Migration Guide for Other Test Files

To fix remaining test failures, replace direct pool deposits with vault deposits:

**Before**:
```typescript
await dai.connect(user.signer).mint(amount);
await dai.connect(user.signer).approve(pool.address, amount);
await pool.connect(user.signer).deposit(dai.address, amount, user.address, '0');
```

**After**:
```typescript
await depositViaVault(dai, amount, user, testEnv);
```

The helper automatically:
1. Selects correct vault (DAI → usdcVault, USDC → actualUSDCVault, WETH → wethVault)
2. Switches active vault in AddressesProvider
3. Mints tokens to user
4. Approves vault
5. Executes deposit via vault
6. Returns vault shares to user

---

## Future Considerations

1. **Vault Share as Collateral**: Consider implementing collateral recognition for vault shares if borrowing against Bitmor deposits becomes required.

2. **Flash Loan Re-enable**: If flash loans become necessary, implement vault-aware flash loan logic that recognizes vault shares or requires vaults to be flash loan receivers.

3. **Multi-Vault Registration**: Consider allowing multiple concurrent vault registrations to eliminate vault switching overhead.

4. **Test Suite Completion**: All 105 remaining tests need conversion to use `depositViaVault()` helper.

---

## Next Steps to Fix Remaining 105 Failing Tests

### Problem Analysis

**Current Status**: 105 tests failing with Error 85 (LP_CALLER_NOT_VAULT) not all but most of were failing due to 85 we resolved few of them in the lendingPool and now they are failing with different error string and it was expected, so to fix this we have to change the expectedOutcome as per new flow which is correct actually just fix the expectedResult.

**Root Cause**: The WETHGateway contract calls `pool.deposit()` at line 49 of `contracts/misc/WETHGateway.sol`. The deposit function in LendingPool.sol (line 117) requires `msg.sender == usdcVaultAddress`, which blocks WETHGateway from depositing.

**Why WETHGateway is needed**: WETHGateway allows users to deposit/withdraw native ETH by wrapping/unwrapping WETH. It's a critical component for user experience. Tests in `test-suites/test-aave/weth-gateway.spec.ts` cover this functionality.

### Solution: Allow WETHGateway as Authorized Depositor

The vault architecture requires only vaults to call `deposit()` to maintain the vault share system. However, WETHGateway is a special case - it wraps native ETH to WETH and deposits on behalf of users. We need to whitelist WETHGateway as an authorized caller.

### Implementation Steps

#### Step 1: Add WETHGateway to AddressesProvider

**File**: `contracts/protocol/configuration/LendingPoolAddressesProvider.sol`

**Changes**:
1. Add constant at line 35 (after `USDC_VAULT`):
```solidity
bytes32 private constant WETH_GATEWAY = "WETH_GATEWAY";
```

2. Add getter function (after line 202):
```solidity
function getWETHGateway() external view override returns (address) {
    return getAddress(WETH_GATEWAY);
}
```

3. Add setter function (after line 211):
```solidity
function setWETHGateway(address wethGateway) external override onlyOwner {
    _addresses[WETH_GATEWAY] = wethGateway;
    emit WETHGatewayUpdated(wethGateway);
}
```

4. Add event declaration (with other events):
```solidity
event WETHGatewayUpdated(address indexed newAddress);
```

**Audit Comment**:
```solidity
/**
 * BITMOR: WETHGateway address storage for authorized deposit access
 *
 * WETHGateway wraps native ETH to WETH and deposits on behalf of users.
 * This is whitelisted alongside vaults for deposit() access control.
 */
```

#### Step 2: Update ILendingPoolAddressesProvider Interface

**File**: `contracts/interfaces/ILendingPoolAddressesProvider.sol`

**Changes**:
1. Add function signatures:
```solidity
function getWETHGateway() external view returns (address);
function setWETHGateway(address wethGateway) external;
```

2. Add event:
```solidity
event WETHGatewayUpdated(address indexed newAddress);
```

#### Step 3: Modify LendingPool Deposit Access Control

**File**: `contracts/protocol/lendingpool/LendingPool.sol`

**Current code (lines 115-117)**:
```solidity
// Access Control (Only vault can deposit in BLP)
address usdcVaultAddress = _addressesProvider.getUSDCVault();
require(msg.sender == usdcVaultAddress, Errors.LP_CALLER_NOT_VAULT);
```

**New code**:
```solidity
/**
 * BITMOR: Access Control - Only vault or WETHGateway can deposit
 *
 * Vault: Primary deposit mechanism where users own vault shares
 * WETHGateway: Special case for wrapping native ETH to WETH deposits
 *
 * Both are authorized to maintain vault architecture while allowing
 * native ETH deposits through the gateway.
 */
address usdcVaultAddress = _addressesProvider.getUSDCVault();
address wethGatewayAddress = _addressesProvider.getWETHGateway();
require(
    msg.sender == usdcVaultAddress || msg.sender == wethGatewayAddress,
    Errors.LP_CALLER_NOT_VAULT
);
```

#### Step 4: Register WETHGateway in Test Setup

**File**: `test-suites/test-aave/__setup.spec.ts`

**Current code (lines 334-335)**:
```typescript
const gateWay = await deployWETHGateway([getContractAddress(mockTokens.WETH)]);
await authorizeWETHGateway(getContractAddress(gateWay), lendingPoolAddress);
```

**Add after line 335**:
```typescript
// Register WETHGateway in AddressesProvider for deposit access control
await waitForTx(await addressesProvider.setWETHGateway(getContractAddress(gateWay)));
console.log('WETHGateway registered in AddressesProvider');
```

#### Step 5: Update TestEnv Interface

**File**: `test-suites/test-aave/helpers/make-suite.ts`

**Check if WETHGateway is already in TestEnv**. If not present, this step may not be needed since `wethGateway` is likely already available.

#### Step 6: Verify and Test

Run tests:
```bash
source ~/.nvm/nvm.sh && nvm use 22 && npm test
```

**Expected Results**:
- All WETHGateway tests should pass (8 tests in weth-gateway.spec.ts)
- Tests using direct `pool.deposit()` from non-vault/non-gateway addresses should still fail with Error 85
- Flash loan tests should pass (4 tests expecting error 86)
- aToken transfer tests should pass (with vault deposits and borrow expecting error 9)

### Remaining Test Failures After WETHGateway Fix

After implementing WETHGateway support, some tests may still fail if they:
1. Call `pool.deposit()` directly from user accounts (not through vault or gateway)
2. Expect users to have aToken balances directly (they have vault shares instead)
3. Test borrowing functionality (users can't borrow with vault shares)

**These tests should be reviewed individually** to determine if they need:
- Conversion to use `depositViaVault()` helper
- Modification to expect error 9 for borrowing attempts
- Skipping if they test functionality incompatible with vault architecture

### Error Code Usage Summary After WETHGateway Fix

| Code | Constant | Usage |
|------|----------|-------|
| 9 | `VL_COLLATERAL_BALANCE_IS_0` | User attempts to borrow with vault shares (pool sees no collateral) |
| 85 | `LP_CALLER_NOT_VAULT` | Non-vault, non-gateway address attempts to call `pool.deposit()` |
| 86 | `LP_FLASHLOAN_DISABLED` | Any flash loan attempt (all modes disabled) |

---

**Last Updated**: 2026-01-19
**Bitmor Protocol Version**: Aave V2 Fork with Vault Architecture
**Status**: Documentation complete. Ready for implementation in next session.
