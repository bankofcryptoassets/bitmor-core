# Naming Inconsistency Report: collateralAsset (bvBTC) vs btc (cbBTC)

**Branch:** `fix/bvbtc-naming`
**Date:** 2026-02-22
**Methodology:** Parallel agent analysis (5 agents covering protocol, libraries, tests, interfaces/vaults, scripts)

---

## Asset Definitions (Ground Truth)

The protocol has two distinct BTC-related assets:

| Identifier | Asset | Token | Role |
|-----------|-------|-------|------|
| `i_COLLATERAL_ASSET` / `collateralAsset` | **bvBTC** | BTCVault ERC-4626 shares | Deposited as collateral into Bitmor Lending Pool |
| `i_BTC` / `btc` | **cbBTC** | Coinbase Wrapped Bitcoin | Underlying asset; user swaps USDC to cbBTC |

**Flow:** USDC → swap → **cbBTC** → deposit into BTCVault → **bvBTC** shares → deposit into Lending Pool as collateral

---

## Summary

| Severity | Count | Description |
|----------|-------|-------------|
| **BUG** | 7 | Wrong oracle target in tests, wrong asset in deployment scripts |
| **NAMING** | 7 | Struct fields/variables/errors named incorrectly |
| **COMMENT** | 22 | NatSpec says "collateral" when meaning cbBTC, or reversed descriptions |
| **Total** | **36** | |

---

## BUG Findings (Wrong Behavior / Wrong Asset Target)

### B-01: `LoanFuzzTestBase._dropOraclePrice()` targets mockBTCVault instead of mockCbBTC

- **File:** `test/fuzz/base/LoanFuzzTestBase.sol:375`
- **Current:** `mockOracle.dropPrice(address(mockBTCVault), dropPercent)`
- **Should be:** `mockOracle.dropPrice(address(mockCbBTC), dropPercent)`
- **Impact:** All fuzz tests using `_dropOraclePrice()` drop the wrong asset's price. Production code queries cbBTC price. Contrast with `LoanUnitTestBase:373` which correctly targets `mockCbBTC`.

### B-02: `LoanFuzzTestBase._setBtcPrice()` targets mockBTCVault instead of mockCbBTC

- **File:** `test/fuzz/base/LoanFuzzTestBase.sol:381`
- **Current:** `mockOracle.setAssetPrice(address(mockBTCVault), price)`
- **Should be:** `mockOracle.setAssetPrice(address(mockCbBTC), price)`
- **Impact:** Same root cause as B-01.

### B-03: `CloseLoan.fuzz.t.sol` drops bvBTC price, not cbBTC price

- **File:** `test/fuzz/pure/CloseLoan.fuzz.t.sol:144`
- **Current:** `mockOracle.dropPrice(address(mockBTCVault), priceDrop)`
- **Should be:** `mockOracle.dropPrice(address(mockCbBTC), priceDrop)`
- **Impact:** Close-loan fuzz test price drops don't affect the cbBTC price that production code uses.

### B-04: `LoanContract.t.sol` `vm.mockCall` targets collateralAsset for calculateStrikePrice

- **File:** `test/unit/Loan/LoanContract.t.sol:106`
- **Current:** `abi.encodeWithSelector(IPriceOracleGetter.getAssetPrice.selector, collateralAsset)`
- **Should be:** `abi.encodeWithSelector(IPriceOracleGetter.getAssetPrice.selector, btc)`
- **Impact:** `calculateStrikePrice` at `Loan.sol:403` now queries `i_BTC`, so this mock doesn't intercept the real call. Test may pass for wrong reasons.

### B-05: `HelperConfig.getCollateralAsset()` reads cbBTC from lending pool instead of bvBTC

- **File:** `script/HelperConfig.s.sol:214`
- **Current:** `return _readAddress("bcbBTC")` — reads cbBTC from `lending-pool/deployed-contracts.json`
- **Should be:** Return the BTCVault (bvBTC) address, e.g., via `getBTCVault()` or `_readDeployment("collateralAsset")`
- **Impact:** On Base Sepolia deployments, `i_COLLATERAL_ASSET` would be set to cbBTC instead of bvBTC.

### B-06: `DeployLoan.s.sol` uses `getCollateralAsset()` which returns wrong asset on testnet

- **File:** `script/deployment/DeployLoan.s.sol:52`
- **Current:** `collateralAsset: config.getCollateralAsset()`
- **Should be:** `collateralAsset: config.getBTCVault()`
- **Impact:** Downstream of B-05. Loan contract would be constructed with wrong `i_COLLATERAL_ASSET`.

### B-07: `BaseLoan.t.sol._utilSeedUserAndApprove` mints cbBTC when token is bvBTC

- **File:** `test/unit/Loan/BaseLoan.t.sol:488-491`
- **Current:** `} else if (token == collateralAsset) { _fundCbBTC(_user, amount); }`
- **Should be:** Should mint bvBTC shares (or deposit cbBTC into vault to get shares)
- **Impact:** If called with `collateralAsset` (bvBTC address), mints the wrong token type.

---

## NAMING Findings (Misleading Variable/Field/Error Names)

### N-01: `InitializeLoanContext.minCollateralAmt` / `maxCollateralAmt` hold cbBTC bounds

- **File:** `src/libraries/types/DataTypes.sol:221-228`
- **Current:** `uint256 minCollateralAmt` / `uint256 maxCollateralAmt`
- **Should be:** `uint256 minBTCAmt` / `uint256 maxBTCAmt`
- **Note:** `CalculateLoanDetailsContext` (same file, lines 392-394) already uses the correct names `minBTCAmt` / `maxBTCAmt`. These should match.

### N-02: `Errors.GreaterThanMaxCollateralAllowed` / `LessThanMinimumCollateralAllowed`

- **File:** `src/libraries/helpers/Errors.sol:97-103`
- **Current:** Error names say "Collateral" but are triggered by cbBTC bounds checks
- **Should be:** `GreaterThanMaxBTCAllowed` / `LessThanMinBTCAllowed`

### N-03: `HelperConfig.COLLATERL_AMT` — typo + ambiguous asset denomination

- **File:** `script/HelperConfig.s.sol:40`
- **Current:** `uint256 constant COLLATERL_AMT = 1e8 * DECIMAL_CBBTC`
- **Should be:** `CBBTC_AMT` or `BTC_AMOUNT` (fix typo, clarify it's cbBTC units)

### N-04: `HelperConfig` has two getters for bvBTC that return different things

- **File:** `script/HelperConfig.s.sol:214 vs 241`
- **Current:** `getCollateralAsset()` reads `"bcbBTC"` (cbBTC); `getBTCVault()` reads `"collateralAsset"` (bvBTC)
- **Should be:** Both should return bvBTC. Unify to one getter or fix `getCollateralAsset()`.

### N-05: `CloseLoanLogic.collateralAssetPrice` — set but never used (dead variable)

- **File:** `src/libraries/logic/CloseLoanLogic.sol:63-64, 130`
- **Current:** `vars.collateralAssetPrice` is assigned but never read in any calculation
- **Should be:** Remove dead variable or document why it exists.

### N-06: Test `@param collateral` described as "Collateral amount in cbBTC"

- **Files:** `test/base/LoanUnitTestBase.sol:315,326`, `test/fuzz/base/LoanFuzzTestBase.sol:152,318,330`, `test/fuzz/pure/InitializeLoan.fuzz.t.sol:44`, `test/fuzz/pure/CloseLoan.fuzz.t.sol:42`
- **Current:** `@param collateral Collateral amount in cbBTC (8 decimals)`
- **Should be:** `@param collateral Target cbBTC amount (8 decimals)` — "collateral" implies bvBTC

### N-07: `Errors.InsufficientCollateral` reused for "deposit exceeds BTC value"

- **File:** `src/libraries/helpers/LoanMath.sol:131`
- **Current:** Reverts `InsufficientCollateral` when `depositValueUSD > btcValueUSD`
- **Should be:** A more specific error like `DepositExceedsBTCValue` or updated NatSpec

---

## COMMENT Findings (Incorrect/Misleading Documentation)

### Source Code Comments

| ID | File | Line | Current | Should Be |
|----|------|------|---------|-----------|
| C-01 | `FlashLoanLogic.sol` | 226 | "Redeem `btc` for `bvBTC` shares" | "Redeem `bvBTC` shares for `btc`" (direction reversed) |
| C-02 | `RepayLogic.sol` | 108 | "Redeem `btc` for `bvBTC` shares" | "Redeem `bvBTC` shares for `btc`" (direction reversed) |
| C-03 | `FlashLoanLogic.sol` | 63 | "Amount of collateral to swap" | "Amount of cbBTC to swap" |
| C-04 | `CloseLoanLogic.sol` | 135 | `ctx.collaterlAsset` (typo) | `ctx.collateralAsset` |
| C-05 | `CloseLoanLogic.sol` | 158 | `vars.debtAsset` (non-existent) | `ctx.debtAsset` |
| C-06 | `DataTypes.sol` | 170 | "Target collateral amount (cbBTC)" | "Target cbBTC amount (8 decimals)" |
| C-07 | `DataTypes.sol` | 469 | "Target collateral amount" | "Target cbBTC amount" |
| C-08 | `DataTypes.sol` | 221 | "Minimum collateral amount allowed" | "Minimum cbBTC amount allowed" |
| C-09 | `DataTypes.sol` | 225 | "Maximum collateral amount allowed" | "Maximum cbBTC amount allowed" |
| C-10 | `LoanStorage.sol` | 86 | "shares to btc" | "shares to cbBTC" |
| C-11 | `LoanStorage.sol` | 52 | "Wrapped Bitcoin address" | "cbBTC (Coinbase Wrapped Bitcoin) address" |
| C-12 | `LoanStorage.sol` | 92 | "Max amount of BTC...as collateral" | "Max cbBTC amount for a loan" |
| C-13 | `LoanStorage.sol` | 95 | "Min. amount of BTC...as collateral" | "Min. cbBTC amount for a loan" |

### Interface NatSpec Comments

| ID | File | Line | Current | Should Be |
|----|------|------|---------|-----------|
| C-14 | `ILoan.sol` | 20 | "Amount of cbBTC collateral" | "Target cbBTC amount" |
| C-15 | `ILoan.sol` | 138 | "maximum BTC collateral amount" | "maximum cbBTC amount" |
| C-16 | `ILoan.sol` | 144 | "minimum BTC collateral amount" | "minimum cbBTC amount" |
| C-17 | `ILoan.sol` | 300-303 | "collateral asset will be transferred" | "underlying cbBTC will be transferred" |
| C-18 | `ILoan.sol` | 373 | "Collateral asset amount in cbBTC" | "Target cbBTC amount" |
| C-19 | `ILoan.sol` | 410 | "maximum BTC collateral amount" | "maximum cbBTC amount" |
| C-20 | `ILoan.sol` | 418 | "maximum BTC collateral amount" | "maximum cbBTC amount" |
| C-21 | `ILoan.sol` | 422 | "minimum BTC collateral amount" | "minimum cbBTC amount" |
| C-22 | `ILoan.sol` | 429 | "minimum BTC collateral amount" | "minimum cbBTC amount" |

### Test Comments

| ID | File | Line | Current | Should Be |
|----|------|------|---------|-----------|
| C-23 | `LSALogicHarness.sol` | 31 | `collateralAsset...e.g., cbBTC` | `collateralAsset...e.g., bvBTC` |
| C-24 | `CloseLoan.t.sol` | 177 | "collateralAsset == btc using same mockCbBTC" | Stale — they are now distinct addresses |

---

## Files Reviewed With No Issues

These files correctly distinguish bvBTC and cbBTC throughout:

**Source:** `SwapLogic.sol`, `LSALogic.sol`, `BitmorLendingPoolLogic.sol`, `AavePoolLogic.sol`, `TokenizedStrategyLogic.sol`, `StrategyStateLogic.sol`, `VaultStateLogic.sol`, `BTCVaultLogic.sol`, `Constants.sol`, `BTCVault__Validation.sol`, `BTCVault.sol`, `BTCVault__Storage.sol`, `AaveTokenizedStrategy.sol`, `SimpleTokenizedStrategy.sol`, `USDCVault.sol`, `USDCStrategy.sol`, `RolesData.sol`, `BitmorAccessManager.sol`, `LoanVault.sol`, `LoanVaultFactory.sol`, `AutoRepayment.sol`

**Tests:** `RepayLoan.t.sol`, `ViewFunctions.t.sol`, `AdminSetters.t.sol`, `ClaimSurplusCollateral.t.sol`, `AccessControls.t.sol`, `PauseUnpause.t.sol`, `FullLiquidation.t.sol`, `MicroLiquidationCompletion.t.sol`, `LoanVault.t.sol`, `LSAExploit.t.sol`, `AutoRepayment.t.sol`, `LoanMath.fuzz.t.sol`, `Repayloan.fuzz.t.sol`, `Loan.fuzz.t.sol`, `TestConstants.sol`, `FuzzConstants.sol`

---

## Priority Recommendations

### Immediate (test correctness)
1. Fix B-01/B-02: `LoanFuzzTestBase._dropOraclePrice()`/`_setBtcPrice()` → target `mockCbBTC`
2. Fix B-03: `CloseLoan.fuzz.t.sol:144` → target `mockCbBTC`
3. Fix B-04: `LoanContract.t.sol:106` → mock `btc` not `collateralAsset`

### High Priority (deployment safety)
4. Fix B-05/B-06: `HelperConfig.getCollateralAsset()` should return bvBTC, not cbBTC
5. Rename N-01: `InitializeLoanContext.minCollateralAmt`/`maxCollateralAmt` → `minBTCAmt`/`maxBTCAmt`

### Medium Priority (naming clarity)
6. Rename N-02: Error names from `*Collateral*` to `*BTC*` for cbBTC bounds
7. Fix N-05: Remove dead `collateralAssetPrice` variable in `CloseLoanLogic`
8. Fix C-01/C-02: Reversed redemption direction comments

### Low Priority (documentation)
9. All remaining COMMENT findings (C-03 through C-24)
