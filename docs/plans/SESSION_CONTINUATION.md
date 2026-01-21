# Session Continuation - Deployment Infrastructure

> **Last Updated:** 2026-01-21 (Session 2)
> **Status:** All planned tasks complete, ready for testing
> **Branch:** `fix/deploymentSetup`

## Overview

Four major plans have been implemented:
1. **Deployment Testing Infrastructure** - Basic deployment scripts and orchestration
2. **AccessManager Integration Design** - Production-like AccessManager setup with schedule/execute pattern
3. **HelperConfig Consolidation** - Single source of truth for deployment configuration
4. **Script Configuration Optimization** - Extended HelperConfig with centralized getters and path helpers

## Completed Work

### Plan 1: Deployment Testing Infrastructure

| File                             | Purpose                                 |
| -------------------------------- | --------------------------------------- |
| `deploy/scripts/deploy-local.sh` | Three-phase deployment orchestrator     |
| `deploy/scripts/.gitkeep`        | Directory placeholder                   |
| `deploy/artifacts/.gitkeep`      | Directory placeholder                   |
| `Makefile` (root)                | `make anvil`, `make deploy-local`, etc. |
| `DEPLOYMENT_SETUP.md`            | Comprehensive deployment guide          |

**loan-provider/script/deployment/**
| File                        | Purpose                                        |
| --------------------------- | ---------------------------------------------- |
| `DeploymentConstants.sol`   | Shared constants (no magic values)             |
| `SaveLocalDeployment.s.sol` | Saves Phase 1 addresses to deployments.json    |
| `DeployMockOracles.s.sol`   | Deploys BTC/USDC mock Chainlink oracles        |
| `DeployBTCVault.s.sol`      | Deploys BTCVault (produces bvBTC)              |
| `DeployUSDCVault.s.sol`     | Deploys USDCVault                              |
| `DeployStrategies.s.sol`    | Deploys AaveTokenizedStrategy and USDCStrategy |

**Mocks:**
| File                                              | Purpose                              |
| ------------------------------------------------- | ------------------------------------ |
| `loan-provider/test/mock/MockChainlinkOracle.sol` | Chainlink AggregatorV3Interface mock |

### Plan 2: AccessManager Integration Design

| File                                                                  | Purpose                                                                |
| --------------------------------------------------------------------- | ---------------------------------------------------------------------- |
| `loan-provider/script/helpers/DeploymentHelper.s.sol`                 | DevOpsTools wrappers, lending-pool JSON reader, time warp utilities    |
| `loan-provider/script/StrategyConfig.s.sol`                           | Strategy deployment config (uses HelperConfig getters)                 |
| `loan-provider/script/interaction/AccessManager/LocalFullSetup.s.sol` | Comprehensive setup: roles, grants, guardians, schedule, warp, execute |

**Modified Files:**
| File                                                                | Changes                                                                                                  |
| ------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------- |
| `loan-provider/src/accessManager/RolesData.sol`                     | Added `RoleTargets` struct and `getAllRolesWithTargets()`                                                |
| `loan-provider/script/interaction/AccessManager/InitialSetup.s.sol` | Added virtual `_buildRoleTargets()`, `_getAdmin()`, `_initialSetupWithTargets()`                         |
| `loan-provider/script/HelperConfig.s.sol`                           | Added `getAaveAllocation()`, `getMinimumDeltaRequired()` getters                                         |
| `deploy/scripts/deploy-local.sh`                                    | Updated to use `--private-key`, added DeployStrategies, replaced interaction scripts with LocalFullSetup |

### Plan 3: HelperConfig Consolidation

**Goal:** Establish `HelperConfig.s.sol` as the single source of truth for all deployment configuration, eliminating duplicate logic.

**Commits on `fix/deploymentSetup` branch:**
| Commit    | Message                                                                                 |
| --------- | --------------------------------------------------------------------------------------- |
| `1f1ad17` | feat(script): add readLendingPoolAddress() public method to HelperConfig                |
| `9631fae` | refactor(script): DeploymentHelper delegates to HelperConfig for lending-pool addresses |
| `3c4f523` | refactor(script): DeployBTCVault uses HelperConfig for AccessManager                    |
| `94704bb` | refactor(script): DeployUSDCVault uses HelperConfig for AccessManager consistently      |
| `7d19262` | refactor(script): LocalFullSetup uses HelperConfig for lending-pool addresses           |

**Changes Made:**
| File                                                                  | Changes                                                                                                     |
| --------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------- |
| `loan-provider/script/HelperConfig.s.sol`                             | Added public `readLendingPoolAddress(string contractName)` method wrapping internal `_readAddress()`        |
| `loan-provider/script/helpers/DeploymentHelper.s.sol`                 | Removed duplicate `_getLendingPoolNetwork()` logic, now delegates to HelperConfig; removed `stdJson` import |
| `loan-provider/script/deployment/DeployBTCVault.s.sol`                | Uses `helperConfig.getAccessManager()` instead of DevOpsTools lookup                                        |
| `loan-provider/script/deployment/DeployUSDCVault.s.sol`               | Uses `helperConfig.getAccessManager()` for consistency (already used HelperConfig for bitmorPool)           |
| `loan-provider/script/interaction/AccessManager/LocalFullSetup.s.sol` | Uses `config.readLendingPoolAddress()` instead of inherited `readLendingPoolAddress()`                      |

**Additional Consolidation:**
| File                                                        | Changes                                                                                                                                                    |
| ----------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `loan-provider/script/deployment/SaveLocalDeployment.s.sol` | Now extends DeploymentHelper; uses `getDeployedAddressOrZero()` instead of custom `_getAddressOptional()`; removed DevOpsTools/DeploymentConstants imports |

### Plan 4: Script Configuration Optimization

**Goal:** Extend HelperConfig with centralized getters for vault addresses, token addresses, oracle addresses, network utilities, and path helpers. Refactor StrategyConfig to avoid redundant HelperConfig instantiation.

**Commits on `fix/deploymentSetup` branch:**
| Commit    | Message                                                                             |
| --------- | ----------------------------------------------------------------------------------- |
| `d0b431c` | refactor(script): make chain ID constants public in HelperConfig                    |
| `cd190d1` | refactor(script): simplify LocalFullSetup to use _initialSetup without role targets |
| `06ddd00` | feat(script): add centralized getters and path helpers to HelperConfig              |

**New Getters Added to HelperConfig.s.sol:**

| Category              | Methods                                                                                       |
| --------------------- | --------------------------------------------------------------------------------------------- |
| **Vault Addresses**   | `getBTCVault()`, `getUSDCVault()`, `getAaveTokenizedStrategy()`, `getUSDCStrategy()`          |
| **Token Addresses**   | `getCbBTC()`, `getUSDC()`, `getMockCbBTC()`, `getMockUSDC()`                                  |
| **Oracle Addresses**  | `getBtcUsdOracle()`                                                                           |
| **Network Utilities** | `getNetworkName(chainId)`, `getCurrentNetworkName()`                                          |
| **Path Helpers**      | `getDeploymentsJsonPath()`, `getLendingPoolDeploymentsPath()`, `getBroadcastPath(scriptName)` |

**StrategyConfig.s.sol Refactoring:**
- Added overloaded `getStrategyConfig(HelperConfig)` to accept external HelperConfig instance
- Caches HelperConfig internally via `_cachedHelperConfig`
- Added `getCachedHelperConfig()` accessor
- Uses HelperConfig's public chain ID constants instead of local copies
- Internal methods changed from non-view to view (read cached config)

## Architecture

### Final Architecture After All Plans
```
HelperConfig.s.sol (SINGLE SOURCE OF TRUTH - EXTENDED)
    ├── Network config (addresses, params)
    ├── Chain ID constants (PUBLIC)
    │   ├── CHAIN_ID_LOCAL (31337)
    │   ├── CHAIN_ID_BASE_SEPOLIA (84532)
    │   └── CHAIN_ID_BASE_MAINNET (8453)
    ├── Core getters
    │   ├── getAccessManager(), getBitmorPool(), getOracle()
    │   ├── getGracePeriod(), getLiquidationBuffer(), etc.
    │   └── readLendingPoolAddress()
    ├── Vault getters
    │   ├── getBTCVault(), getUSDCVault()
    │   └── getAaveTokenizedStrategy(), getUSDCStrategy()
    ├── Token getters
    │   ├── getCbBTC(), getUSDC() (chain-aware)
    │   └── getMockCbBTC(), getMockUSDC() (local only)
    ├── Oracle getters
    │   └── getBtcUsdOracle()
    ├── Network utilities
    │   ├── getNetworkName(chainId)
    │   └── getCurrentNetworkName()
    └── Path helpers
        ├── getDeploymentsJsonPath()
        ├── getLendingPoolDeploymentsPath()
        └── getBroadcastPath(scriptName)

StrategyConfig.s.sol (OPTIMIZED)
    ├── getStrategyConfig() → creates new HelperConfig
    ├── getStrategyConfig(HelperConfig) → uses provided instance
    ├── getCachedHelperConfig() → returns cached instance
    └── Uses HelperConfig.CHAIN_ID_* constants

DeploymentHelper.s.sol (UTILITIES ONLY)
    ├── DevOpsTools wrappers (requireDeployed, getDeployedAddressOrZero)
    ├── Time manipulation (warpTime, warpTimeTo)
    ├── Chain detection (isLocalChain)
    └── readLendingPoolAddress() → delegates to HelperConfig

Deployment Scripts (extend DeploymentHelper)
    ├── SaveLocalDeployment.s.sol → uses getDeployedAddressOrZero()
    ├── DeployBTCVault.s.sol → uses HelperConfig.getAccessManager()
    ├── DeployUSDCVault.s.sol → uses HelperConfig.getAccessManager()
    └── LocalFullSetup.s.sol → uses config.readLendingPoolAddress()
```

### Deployment Flow
```
make deploy-local
    └── deploy-local.sh (--private-key for Anvil)
        ├── Phase 1: loan-provider
        │   ├── DeployAccessManager
        │   ├── DeployMockTokens
        │   ├── DeployMockOracles
        │   ├── DeployBTCVault
        │   ├── DeployUSDCVault
        │   └── SaveLocalDeployment
        │
        ├── Phase 2: lending-pool
        │   └── npm run bitmor:localhost:dev:migration
        │
        └── Phase 3: loan-provider
            ├── DeploySwapAdapterWrapper
            ├── DeployLoanVault
            ├── DeployLoan
            ├── DeployLoanVaultFactory
            ├── DeployStrategies
            ├── LocalFullSetup --sig "run(bool)" true
            │   ├── _initialSetup() (roles + grants)
            │   ├── _setupGuardians() (chain-aware)
            │   ├── _scheduleOperations() (delayed ops)
            │   ├── warpTime(1 days + 1)
            │   └── _executeOperations()
            └── SaveDeployedAddresses
```

### Key Design Decisions

1. **`--private-key` over `--account`**: Uses Anvil's default funded account (0xac0974...) for simpler local testing

2. **LocalFullSetup.s.sol**: Consolidates all AccessManager configuration:
   - Replaces separate `SetLoanVaultFactory.s.sol` and `SetBitmorLoan.s.sol`
   - Uses schedule/execute pattern for delayed operations
   - Time warps 1 day + 1 second to execute scheduled operations
   - Chain-aware guardian setup (simplified for local, full for production)

3. **HelperConfig as Single Source of Truth**: All address lookups and configuration go through HelperConfig
   - Vault, token, oracle addresses via dedicated getters
   - Path helpers for JSON files and broadcast directories
   - Network name utilities for chain identification

4. **DeploymentHelper.s.sol**: Centralized utilities including:
   - `requireDeployed()` / `getDeployedAddressOrZero()` - DevOpsTools wrappers
   - `readLendingPoolAddress()` - Delegates to HelperConfig
   - `warpTime()` / `warpTimeTo()` - Anvil time manipulation
   - `isLocalChain()` - Chain detection

## Role Configuration

### Operational Roles
| Role     | ID  | Target        | Grantee                      |
| -------- | --- | ------------- | ---------------------------- |
| ADMIN    | 0   | -             | admin EOA                    |
| EXECUTOR | 1   | Loan          | admin EOA                    |
| LPCM     | 2   | Loan          | LendingPoolCollateralManager |
| LPM_FAST | 3   | Loan          | admin EOA                    |
| LPM_SLOW | 30  | Loan          | admin EOA (1-day delay)      |
| ARE      | 4   | AutoRepayment | admin EOA                    |
| BVM_FAST | 11  | BTCVault      | admin EOA                    |
| BVM_SLOW | 110 | BTCVault      | admin EOA (1-day delay)      |
| BVC      | 12  | BTCVault      | admin EOA (1-day delay)      |
| BVA_FAST | 13  | BTCVault      | admin EOA                    |
| BVA_SLOW | 130 | BTCVault      | admin EOA (1-day delay)      |
| BVD      | 14  | BTCVault      | Loan contract                |
| UVM_FAST | 21  | USDCVault     | admin EOA                    |
| UVM_SLOW | 210 | USDCVault     | admin EOA (1-day delay)      |
| UVC      | 22  | USDCVault     | admin EOA (1-day delay)      |
| UVA      | 23  | USDCVault     | admin EOA                    |

### Guardian Roles
Guardian roles can cancel delayed operations for their protected roles:
- GUARDIAN_LPM_SLOW (930) → protects LPM_SLOW
- GUARDIAN_BVM_SLOW (9110) → protects BVM_SLOW
- GUARDIAN_BVC (912) → protects BVC
- GUARDIAN_BVA_SLOW (9130) → protects BVA_SLOW
- GUARDIAN_UVM_SLOW (9210) → protects UVM_SLOW
- GUARDIAN_UVC (922) → protects UVC

## Technical Notes

### Solidity Public Struct Getters Return Tuples
When accessing public struct variables in Solidity, they return tuples, not structs:
```solidity
// Wrong - will fail
uint64 id = rolesData.GUARDIAN_LPM_SLOW().id;

// Correct - destructure tuple
(, uint64 id,) = rolesData.GUARDIAN_LPM_SLOW();

// RoleData has 10 elements in getter (selectors excluded)
(,,,, uint64 roleId,,,,,) = rolesData.LPM_SLOW();
```

### Time Warp
Uses `vm.warp(block.timestamp + seconds_)` instead of `skip()` (which isn't available in all contexts).

### Strategy Constructor Order
USDCStrategy constructor is `(_vault, _aave, _blp)` - order matters.

### Chain-Aware Token Getters
`getCbBTC()` and `getUSDC()` are chain-aware:
- Local chain: reads from `deployments.json`
- Testnet/mainnet: returns hardcoded constants

## How to Test

```bash
# Terminal 1: Start Anvil
cd bitmor-core
make anvil

# Terminal 2: Run deployment
make deploy-local

# Verify
cat loan-provider/deployments.json | jq '.deployments["31337"]'
```

## Next Steps (if continuing work)

1. **Test full deployment flow** - Run `make deploy-local` with Anvil
2. **Verify AccessManager state** - Check roles are granted, operations executed
3. **Run loan-provider tests** - `cd loan-provider && make test`
4. **Fork testing** - Test with `--fork-url` for Base Sepolia integration
5. **Update other scripts** - Migrate remaining scripts to use new HelperConfig getters

## Key Files Reference

| Category                       | File                                                                  |
| ------------------------------ | --------------------------------------------------------------------- |
| Role definitions               | `loan-provider/src/accessManager/RolesData.sol`                       |
| AccessManager                  | `loan-provider/src/accessManager/BitmorAccessManager.sol`             |
| Setup script                   | `loan-provider/script/interaction/AccessManager/LocalFullSetup.s.sol` |
| Deployment helper              | `loan-provider/script/helpers/DeploymentHelper.s.sol`                 |
| Strategy config                | `loan-provider/script/StrategyConfig.s.sol`                           |
| Network config (SINGLE SOURCE) | `loan-provider/script/HelperConfig.s.sol`                             |
| Orchestrator                   | `deploy/scripts/deploy-local.sh`                                      |
| Root Makefile                  | `Makefile`                                                            |

## Plans Reference

All implementation plans are saved in `docs/plans/` or `loan-provider/docs/plans/`:

| Plan                              | File                                                         | Status   |
| --------------------------------- | ------------------------------------------------------------ | -------- |
| Deployment Testing Infrastructure | `docs/plans/2026-01-21-deployment-testing-infrastructure.md` | Complete |
| AccessManager Integration Design  | `docs/plans/2026-01-21-accessmanager-integration-design.md`  | Complete |
| HelperConfig Consolidation        | `docs/plans/2026-01-21-helperconfig-consolidation.md`        | Complete |
| Script Configuration Optimization | `docs/plans/2026-01-21-script-config-optimization.md`        | Complete |

## Git Commits Summary (fix/deploymentSetup branch)

### Plan 3 Commits:
- `1f1ad17` feat(script): add readLendingPoolAddress() public method to HelperConfig
- `9631fae` refactor(script): DeploymentHelper delegates to HelperConfig for lending-pool addresses
- `3c4f523` refactor(script): DeployBTCVault uses HelperConfig for AccessManager
- `94704bb` refactor(script): DeployUSDCVault uses HelperConfig for AccessManager consistently
- `7d19262` refactor(script): LocalFullSetup uses HelperConfig for lending-pool addresses

### Plan 4 Commits:
- `d0b431c` refactor(script): make chain ID constants public in HelperConfig
- `cd190d1` refactor(script): simplify LocalFullSetup to use _initialSetup without role targets
- `06ddd00` feat(script): add centralized getters and path helpers to HelperConfig
