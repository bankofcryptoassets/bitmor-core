# HelperConfig Centralization Design

**Date:** 2026-03-13
**Status:** Approved
**Branch:** feat/upgradability

## Problem

Deployment scripts (`DeployPhase1Local`, `DeployPhase1Mainnet`, `DeployPhase3Local`, `DeployPhase3Mainnet`) each define their own protocol constants (fees, slippages, collateral bounds) and address loading logic. This creates:

- 11 duplicated constants across DeployPhase3 scripts (identical values, separate definitions)
- Hardcoded JSON paths and network keys in each script's `_loadPhase1Addresses()` / `_loadLendingPoolAddresses()`
- Mainnet-specific addresses (`CBBTC_BASE_MAINNET`, `USDC_BASE_MAINNET`, `SWAP_ADAPTER_BASE_MAINNET`) scattered across deployment scripts instead of centralized
- Risk of inconsistency when updating a value in one script but not others

## Decision

**Approach A: HelperConfig as Single Source of Truth.** All protocol configuration and chain-specific addresses centralized in `HelperConfig.s.sol`. Deployers only need to edit one file for any network.

## Design

### 1. New `LoanConfig` Struct in HelperConfig

```solidity
struct LoanConfig {
    uint256 preClosureFeeBps;       // 10 (0.1%)
    uint256 gracePeriod;            // 7 days
    uint256 maxDuration;            // 60 months
    uint256 slippageSwap;           // 50 bps (0.5%)
    uint256 slippageSharesToAsset;  // 100 bps (1%)
    uint256 maxBTCAmt;              // 10e8
    uint256 minBTCAmt;              // 0.01e8
    uint256 minDepositBps;          // 3000 (30%)
    uint256 liquidationFee;         // 0
    uint256 liquidationBuffer;      // 50 bps (0.5%)
    uint256 strategyCap;            // type(uint256).max
    uint256 maxStrategies;          // 5
    uint256 entryFee;               // 10 bps (0.1%)
    uint256 exitFee;                // 10 bps (0.1%)
}
```

A `getLoanConfig()` getter returns this for any chain. Initially all chains share the same values; the getter can branch on `block.chainid` if they diverge.

### 2. Slimmed `NetworkConfig` (addresses only)

Remove `preClosureFeeBps`, `gracePeriod`, `entryFee`, `exitFee`:

```solidity
struct NetworkConfig {
    address accessManager;
    address bitmorPool;
    address aaveV3Pool;
    address aaveAddressesProvider;
    address oracle;
    address collateralAsset;
    address debtAsset;
    address btc;
    address swapper;
    address premiumCollector;
    address usdc;
    address usdc_holder;
}
```

### 3. Mainnet Addresses in HelperConfig

Move scattered mainnet address constants into HelperConfig alongside existing ones:

```solidity
// Already exists:
address constant AAVE_V3_POOL_BASE_MAINNET = 0xA238Dd80C259a72e81d7e4664a9801593F98d1c5;
address constant AAVE_ADDRESSES_PROVIDER_BASE_MAINNET = 0xe20fCBdBfFC4Dd138cE8b2E6FBb6CB49777ad64D;

// New (move from deployment scripts):
address constant CBBTC_BASE_MAINNET = address(0);       // TODO: set before deployment
address constant USDC_BASE_MAINNET = address(0);         // TODO: set before deployment
address constant SWAP_ADAPTER_BASE_MAINNET = address(0); // TODO: set before deployment
```

Getters branch on `block.chainid == CHAIN_ID_BASE_MAINNET` (same pattern as `getAaveV3Pool()`).

### 4. Shared Address Loaders in DeploymentBase

Move `_loadPhase1Addresses()` and `_loadLendingPoolAddresses()` from individual scripts into `DeploymentBase.s.sol`:

- Return structs (`Phase1Addresses`, `LendingPoolAddresses`) for clean data passing
- Use `block.chainid` + `vm.toString()` for JSON path construction (no hardcoded chain ID strings)
- Use `HelperConfig.getLendingPoolNetworkKey()` for lending-pool JSON key resolution

New HelperConfig getter:
```solidity
function getLendingPoolNetworkKey() public view returns (string memory) {
    if (block.chainid == CHAIN_ID_LOCAL) return "localhost";
    if (block.chainid == CHAIN_ID_BASE_SEPOLIA) return "sepolia";
    if (block.chainid == CHAIN_ID_BASE_MAINNET) return "base";
    revert("HelperConfig: unsupported chain for lending pool");
}
```

### 5. DeployPhase Script Simplification

**DeployPhase1 (both):**
- Delete `MAX_STRATEGIES` → `getLoanConfig().maxStrategies`
- Delete `CBBTC_BASE_MAINNET` (mainnet) → HelperConfig getter

**DeployPhase3 (both):**
- Delete all 11 constants → `getLoanConfig()`
- Delete `SWAP_ADAPTER_BASE_MAINNET`, `USDC_BASE_MAINNET` (mainnet) → HelperConfig getters
- Delete `_loadPhase1Addresses()`, `_loadLendingPoolAddresses()` → inherited from DeploymentBase
- Delete `_loadExternalProtocolAddresses()` (mainnet) → inherited loader handles it

### 6. Test Impact

**No test file changes required.** All tests use existing convenience getters (`config.getPreClosureFee()`, `config.getGracePeriod()`, `config.getMaxDuration()`) which will be wired to `LoanConfig` constants internally.

Changes to `_initLocalConfig()` / `_initBaseSepoliaConfig()` (stop setting removed fields) are internal to HelperConfig.

Vault test bases (`BaseTestForBTCVault.t.sol`, `BaseTestForUSDCVault.t.sol`) use their own `MockNetworkConfig` structs — unaffected.

## Files Affected

| File | Change Type |
|------|-------------|
| `script/HelperConfig.s.sol` | Major: add LoanConfig, slim NetworkConfig, add mainnet addresses, add getLendingPoolNetworkKey() |
| `script/deployment/DeploymentBase.s.sol` | Medium: add shared loaders, update _preflightLendingPool() |
| `script/deployment/local/DeployPhase1Local.s.sol` | Minor: remove MAX_STRATEGIES |
| `script/deployment/mainnet/DeployPhase1Mainnet.s.sol` | Minor: remove MAX_STRATEGIES, CBBTC_BASE_MAINNET |
| `script/deployment/local/DeployPhase3Local.s.sol` | Major: remove 11 constants, remove loaders, use getLoanConfig() |
| `script/deployment/mainnet/DeployPhase3Mainnet.s.sol` | Major: remove 11 constants + 2 addresses, remove loaders |

## Parallel Agent Work Breakdown

1. **Agent 1 (blocking):** HelperConfig + DeploymentBase shared loaders
2. **Agent 2:** DeployPhase1 simplification (both local + mainnet) — depends on Agent 1
3. **Agent 3:** DeployPhase3 simplification (both local + mainnet) — depends on Agent 1
4. **Agent 4:** Test updates if any surface — depends on Agent 1

All agents use git worktrees for isolation.
