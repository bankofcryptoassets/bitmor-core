# Session Continuation - Deployment Infrastructure

> **Last Updated:** 2026-01-22 (Session 8)
> **Status:** Plan 6 (Deployment Optimization) - COMPLETE ✅
> **Branch:** `fix/deploymentSetup`

## Overview

Six major plans - five complete, one in progress:
1. **Deployment Testing Infrastructure** - Basic deployment scripts and orchestration ✅
2. **AccessManager Integration Design** - Production-like AccessManager setup with schedule/execute pattern ✅
3. **HelperConfig Consolidation** - Single source of truth for deployment configuration ✅
4. **Script Configuration Optimization** - Extended HelperConfig with centralized getters and path helpers ✅
5. **Local Testing Infrastructure** - Unit tests on Anvil with mocks, integration tests on Base Mainnet fork 🔄
6. **Deployment Optimization** - Consolidate 14 forge scripts into 2 for faster local deployments ✅

## Session 8 Progress (2026-01-22)

### ISSUE RESOLVED ✅

**Problem:** `AccessManagerUnauthorizedCall` revert during `schedule()` calls even though roles were correctly granted with 1-day execution delays.

**Root Cause:** Foundry simulates the **entire script** before broadcasting any transactions. When `grantRole()` is followed by `schedule()` in the same script:
1. Simulation runs `grantRole()` - state change is **not committed** to chain
2. Simulation runs `schedule()` - checks role on **actual chain state** (role not granted yet)
3. `schedule()` fails because the role grant isn't visible during simulation

**Secondary Issue:** After splitting scripts, `schedule()` transactions were being broadcast but **failing on-chain** with `AccessManagerUnauthorizedCall`. This was caused by **block.timestamp drift** between Foundry simulation and actual transaction broadcast:
- Simulation computes `when = block.timestamp + 86400`
- Actual tx broadcasts ~10 minutes later with higher `block.timestamp`
- AccessManager check `when >= block.timestamp + delay` fails

### Solution: Three-Script Split + SCHEDULE_BUFFER

**Commit:** `e2adf54` - fix(deploy): split Phase 3 into schedule/execute scripts

Split Phase 3 into three scripts that run sequentially:

| Script | Purpose | Runs After |
|--------|---------|------------|
| `DeployPhase3.s.sol` | Deploy contracts + setup roles (no scheduling) | Phase 2 |
| `SchedulePhase3.s.sol` | Schedule timelocked operations | DeployPhase3 (roles on-chain) |
| `ExecutePhase3.s.sol` | Execute scheduled operations | Time advance |

**Files Created/Modified:**

| File | Changes |
|------|---------|
| `loan-provider/script/deployment/SchedulePhase3.s.sol` | **Created** - New script that schedules operations after roles are on-chain |
| `loan-provider/script/deployment/ExecutePhase3.s.sol` | **Modified** - Refactored to use HelperConfig and read addresses from JSON |
| `loan-provider/script/deployment/DeployPhase3.s.sol` | **Modified** - Removed `_scheduleLocalOperations()` call |
| `loan-provider/script/deployment/DeploymentConstants.sol` | **Modified** - Added `SCHEDULE_BUFFER` (10 minutes) |
| `deploy/scripts/deploy-local.sh` | **Modified** - Added Phase 3b, updated TIME_ADVANCE to 87001 seconds |

**Key Code Changes:**

```solidity
// DeploymentConstants.sol - Added buffer for timestamp drift
uint256 public constant SCHEDULE_BUFFER = 10 minutes;
uint256 public constant TIME_ADVANCE_SECONDS = EXECUTION_DELAY + SCHEDULE_BUFFER + EXECUTION_BUFFER;

// SchedulePhase3.sol - Include buffer in when calculation
uint48 when = uint48(block.timestamp + DeploymentConstants.EXECUTION_DELAY + DeploymentConstants.SCHEDULE_BUFFER);
```

**Updated Deployment Flow:**

```
make deploy-local
    └── deploy-local.sh
        ├── Phase 1: DeployPhase1.s.sol
        ├── Phase 2: lending-pool (npm migration)
        ├── Phase 3a: DeployPhase3.s.sol (deploy + roles)
        ├── Phase 3b: SchedulePhase3.s.sol (schedule operations)
        ├── Time advance: 87001 seconds (1 day + 10 min + 1 sec)
        └── Phase 3c: ExecutePhase3.s.sol (execute scheduled ops)
```

**Why Direct JSON Reading Instead of HelperConfig:**

`SchedulePhase3.s.sol` and `ExecutePhase3.s.sol` read addresses directly from `deployments.json` instead of using `helperConfig.getAccessManager()` because:
- DevOpsTools (used by HelperConfig getters) iterates through all broadcast files
- With multiple broadcast files, this causes `MemoryOOG` errors
- Direct JSON reading is more efficient for addresses already saved in deployments.json

### Deployment Verified

Full local deployment completes successfully:
```bash
make deploy-local
# All phases complete
# Addresses saved to loan-provider/deployments.json
```

---

## Session 7 Progress (2026-01-22)

### ISSUE RESOLVED ✅

**Problem:** OpenZeppelin's AccessManager `schedule()` function requires `setback > 0` (non-zero execution delay).

**Analysis of AccessManager.sol (lines 441-456):**
```solidity
function schedule(...) public virtual returns (bytes32 operationId, uint32 nonce) {
    address caller = _msgSender();
    (, uint32 setback) = _canCallExtended(caller, target, data);

    // If setback == 0, schedule() reverts!
    if (setback == 0 || (when > 0 && when < minWhen)) {
        revert AccessManagerUnauthorizedCall(caller, target, _checkSelector(data));
    }
    // ...
}
```

**The Bug:** In `_grantLocalOperationalRoles()`, roles were granted with `executionDelay = 0`:
```solidity
manager.grantRole(lpmSlowId, admin, 0); // ← This causes setback == 0
```

When `canCall()` is called, it returns `delay = currentDelay` from the role grant. With `currentDelay = 0`, `setback = 0`, so `schedule()` reverts.

**The Fix:** Grant roles with production execution delays (`1 days`):
```solidity
manager.grantRole(lpmSlowId, admin, 1 days); // ← Now setback > 0
manager.grantRole(bvcId, admin, 1 days);
manager.grantRole(uvcId, admin, 1 days);
```

### Implementation Complete ✅

**Commit:** `d16f551` - fix(deploy): enable schedule/execute pattern with 1-day execution delays

**Files Modified:**

| File | Changes |
|------|---------|
| `loan-provider/script/deployment/DeployPhase3.s.sol` | Updated role grants from `executionDelay=0` to `1 days`; added `STRATEGY_CAP` constant; added `setMaxStrategies()` call before `addStrategy()`; removed non-existent `setYieldSourceAllocation` call |
| `loan-provider/src/accessManager/RolesData.sol` | Fixed 4 selector bugs (see below) |
| `loan-provider/src/mocks/MockUniswapV4SwapAdapter.sol` | **Created** - Mock swap adapter for local testing with configurable BTC/USDC prices |
| `loan-provider/script/deployment/DeployMockSwapAdapter.s.sol` | **Created** - Deployment script for MockUniswapV4SwapAdapter |
| `loan-provider/script/interaction/AccessManager/InitialSetup.s.sol` | Added `virtual` keyword to `run()` function for override support |
| `loan-provider/script/helpers/DeploymentHelper.s.sol` | Formatting fixes |

**RolesData.sol Selector Fixes:**

| Function | Bug | Fix |
|----------|-----|-----|
| `getLPM_SLOW_SELECTORS()` | `selectors[4]` was duplicate `setGracePeriod` | Changed to `setPreClosureFee.selector` |
| `getBVC_SELECTORS()` | `addStrategy(address)` wrong signature | Changed to `addStrategy(address,uint256)` |
| `getBVC_SELECTORS()` | Missing `setMaxStrategies` | Added `setMaxStrategies(uint256)` as `selectors[3]` |
| `getUVC_SELECTORS()` | `setNewStrategy(address)` doesn't exist | Changed to `setStrategy(address)` |

**Key Code Changes in DeployPhase3.s.sol:**

```solidity
// Before (BROKEN):
manager.grantRole(lpmSlowId, admin, 0);  // setback == 0, schedule() reverts
manager.grantRole(bvcId, admin, 0);
manager.grantRole(uvcId, admin, 0);

// After (FIXED):
manager.grantRole(lpmSlowId, admin, 1 days);  // setback > 0, schedule() works
manager.grantRole(bvcId, admin, 1 days);
manager.grantRole(uvcId, admin, 1 days);
```

```solidity
// Added before addStrategy():
manager.schedule(btcVault, abi.encodeWithSignature("setMaxStrategies(uint256)", 5), when);

// Fixed signature:
manager.schedule(btcVault, abi.encodeWithSignature("addStrategy(address,uint256)", aaveStrategy, STRATEGY_CAP), when);
```

**Deployment Verified:**
- Full local deployment completes successfully with `make deploy-local`
- All contracts deployed to `loan-provider/deployments.json`:
  - AccessManager, MockTokens (USDC, cbBTC), MockOracles (BTC/USD, USDC/USD)
  - BTCVault, USDCVault, Loan, LoanVault, LoanVaultFactory
  - SwapAdapterWrapper, AaveStrategy, USDCStrategy

**Sample deployments.json output:**
```json
{
  "deployments": {
    "31337": {
      "network": "localhost",
      "networkConfig": {
        "accessManager": "0x4CF4dd3f71B67a7622ac250f8b10d266Dc5aEbcE",
        "collateralAsset": "0xE2b5bDE7e80f89975f7229d78aD9259b2723d11F",
        "debtAsset": "0x2498e8059929e18e2a2cED4e32ef145fa2F4a744",
        "btcVault": "...",
        "usdcVault": "...",
        "loan": "...",
        "loanVaultFactory": "...",
        "swapAdapterWrapper": "...",
        "aaveStrategy": "...",
        "usdcStrategy": "..."
      }
    }
  }
}
```

### Next Steps

1. **Implement Plan 5 (Local Testing Infrastructure)** - Enable unit tests on local Anvil without Base Sepolia fork
   - See `docs/plans/2026-01-21-local-testing-infrastructure-impl.md`
   - Key task: Create MockAaveV3Pool for flash loan testing

2. **Optional: Merge fix/deploymentSetup branch** - All deployment infrastructure is now working

---

## Historical Reference (Sessions 5-6)

<details>
<summary>Click to expand previous session notes (superseded by Session 7 fix)</summary>

### Session 6 - Attempted Fix: Direct Contract Calls (REJECTED)

Attempted to bypass the schedule/execute pattern by calling restricted functions directly on the target contracts:
```solidity
// This approach was WRONG
ILoan(loan).setLoanVaultFactory(loanVaultFactory);
```

**Why This Doesn't Work:**
- Contracts use OpenZeppelin's `AccessManaged` pattern with `restricted` modifier
- Restricted functions check authorization through the AccessManager
- Direct calls still go through access control - they don't bypass it

### Session 5 Progress (2026-01-22)

### Plan 6 Implementation Status

**Completed Tasks:**
- ✅ Task 1: Added `[profile.local]` to `foundry.toml` with `via_ir=true`, `optimizer_runs=1`
- ✅ Task 2: Created `DeployPhase1.s.sol` - consolidated Phase 1 deployment
- ✅ Task 3: Created `DeployPhase3.s.sol` - consolidated Phase 3 deployment
- ✅ Task 4: Updated `deploy-local.sh` to use consolidated scripts with `FOUNDRY_PROFILE=local`
- 🚧 Task 5: Testing - BLOCKED on AccessManager `schedule()` authorization

### Issues Encountered and Fixes

#### Issue 1: Stack Too Deep with `via_ir=false`
**Error:** `Compiler error: Stack too deep. Try compiling with --via-ir`
**Investigation:**
- forge-std 1.11.0 has 1,405 assembly blocks requiring via_ir
- Solady library uses inline assembly with variables exceeding stack depth
- This is a known Foundry ecosystem issue, not project-specific
**Resolution:** Keep `via_ir=true` but use `optimizer_runs=1` for faster compilation

#### Issue 2: Override Without Virtual
**Error:** `Trying to override non-virtual function`
**Fix:** Added `virtual` keyword to `InitialSetup.run()` function

#### Issue 3: AccessManagerLockedRole(0)
**Error:** `AccessManagerLockedRole(0)` when trying to `labelRole(0, "ADMIN")`
**Cause:** ADMIN role (ID 0) is a locked role in OpenZeppelin's AccessManager
**Fix:** Added `if (role.id == 0) continue;` in `_initialSetup()` to skip the ADMIN role

#### Issue 4: NOT_CONTRACT Validation Error
**Error:** `NOT_CONTRACT` when granting roles with `isContract: true`
**Cause:** `RolesData.INITIAL_ADMIN` is hardcoded to a production address that doesn't exist on local Anvil
**Fix:** Skip contract validation on local chain:
```solidity
// In InitialSetup.s.sol
if (role.isContract && block.chainid != 31337) {
    _validateContract(role.grantee);
}
```

#### Issue 5: AccessManagerUnauthorizedCall (CURRENT BLOCKER)
**Error:** `AccessManagerUnauthorizedCall(deployer, Loan, setLoanVaultFactory.selector)`
**When:** Calling `manager.schedule(loan, abi.encodeCall(ILoan.setLoanVaultFactory, ...), when)`

**What Works:**
- All contract deployments succeed (Phase 1, 2, 3)
- `setTargetFunctionRole(loan, selectors, lpmSlowId)` succeeds
- `grantRole(lpmSlowId, deployer, 0)` succeeds (event emitted: `RoleGranted(roleId: 30, ...)`)
- Guardian roles granted and set up correctly

**What Fails:**
- `manager.schedule(loan, ...)` reverts with `AccessManagerUnauthorizedCall`

**Root Cause Analysis:**
The OpenZeppelin AccessManager `schedule()` function requires:
1. Caller has the role required to call the target function
2. The function has a non-zero delay configured for that role

Looking at `_canCallExtended()` in AccessManager:
```solidity
function schedule(...) public virtual returns (bytes32, uint32) {
    address caller = _msgSender();
    (, uint32 setback) = _canCallExtended(caller, target, data);

    // If call with delay is not authorized, or if requested timing is too soon, revert
    if (setback == 0 || (when > 0 && when < minWhen)) {
        revert AccessManagerUnauthorizedCall(caller, target, _checkSelector(data));
    }
    ...
}
```

The issue is that `_canCallExtended()` returns `setback == 0` even though:
- Role 30 (LPM_SLOW) was granted to deployer
- `setTargetFunctionRole(loan, selectors, 30)` was called

**Suspected Issue:** The `schedule()` function checks authorization against the **target contract's authority**, not just the AccessManager's role configuration. The Loan contract's `authority()` may not be correctly set or recognized.

### Files Modified in Session 5

| File | Changes |
|------|---------|
| `loan-provider/foundry.toml` | Added `[profile.local]` with `via_ir=true`, `optimizer_runs=1`, `sizes=false` |
| `loan-provider/script/deployment/DeployPhase1.s.sol` | **Created** - Consolidated Phase 1: AccessManager, MockTokens, MockOracles, BTCVault |
| `loan-provider/script/deployment/DeployPhase3.s.sol` | **Created** - Consolidated Phase 3: USDCVault, SwapAdapter, Loan, Strategies, AccessManager setup |
| `deploy/scripts/deploy-local.sh` | Updated to use `DeployPhase1.s.sol` and `DeployPhase3.s.sol` with `FOUNDRY_PROFILE=local` |
| `loan-provider/script/interaction/AccessManager/InitialSetup.s.sol` | Added `virtual` to `run()`, skip ADMIN role (ID 0), skip contract validation on local chain |

### DeployPhase3.s.sol Key Functions

```solidity
contract DeployPhase3 is InitialSetup {
    function run() public override {
        _loadPhase1Addresses();      // Read from deployments.json
        _loadLendingPoolAddresses(); // Read from lending-pool/deployed-contracts.json

        vm.startBroadcast();
        // Deploy: USDCVault, MockSwapAdapter, SwapAdapterWrapper, LoanVault, Loan, LoanVaultFactory, Strategies
        _setupAccessManagerRoles();
        vm.stopBroadcast();

        _warpAndExecute();           // Time warp + execute delayed operations
        _saveDeployments();          // Save to deployments.json
    }

    function _setupAccessManagerRoles() internal {
        manager = BitmorAccessManager(accessManager);
        _grantLocalOperationalRoles();  // Set target function roles + grant roles
        _setupLocalGuardians();         // Grant guardian roles + set relationships
        _scheduleLocalOperations();     // FAILS HERE with AccessManagerUnauthorizedCall
    }

    function _grantLocalOperationalRoles() internal {
        // Set target function roles for actual deployed contracts
        manager.setTargetFunctionRole(loan, rolesData.getLPM_SLOW_SELECTORS(), lpmSlowId);
        manager.setTargetFunctionRole(btcVault, rolesData.getBVC_SELECTORS(), bvcId);
        manager.setTargetFunctionRole(usdcVault, rolesData.getUVC_SELECTORS(), uvcId);

        // Grant roles to deployer
        manager.grantRole(lpmSlowId, admin, 0);  // LPM_SLOW (30)
        manager.grantRole(bvcId, admin, 0);      // BVC (12)
        manager.grantRole(uvcId, admin, 0);      // UVC (22)
    }
}
```

### Next Steps to Resolve Blocker

**Option 1: Direct Execute Instead of Schedule**
For local deployment, skip the schedule/execute pattern entirely and call the Loan contract directly. The deployer is the admin and can configure contracts immediately.

**Option 2: Investigate AccessManager Authority Chain**
1. Verify Loan contract's `authority()` returns the correct AccessManager address
2. Check if there's a timing issue with role grants becoming effective
3. Investigate if `_canCallExtended()` has additional requirements beyond role membership

**Option 3: Simplify Local Setup**
Create a separate `_setupLocalSimple()` that bypasses AccessManager scheduling:
```solidity
// Direct calls instead of schedule/execute
ILoan(loan).setLoanVaultFactory(loanVaultFactory);
ILoan(loan).setGracePeriod(GRACE_PERIOD);
// etc.
```

**Recommended:** Option 3 - For local development, the schedule/execute pattern adds unnecessary complexity. Save that for production deployments.

</details>

---

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

### Plan 5: Local Testing Infrastructure (Ready for Implementation)

**Problem:** Current Foundry tests require Base Sepolia fork and can't run locally. No mock for Aave V3 flash loans.

**Solution:** Enable both unit testing (local Anvil with mocks) and integration testing (Base Mainnet fork) using chain ID detection in test setUp().

**Design Decisions:**

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Mock Aave V3 location | Both deployment scripts AND tests | Local deployment for manual testing; tests deploy fresh for isolation |
| Mode switching | Makefile targets + chain ID detection | `test-unit` vs `test-integration` |
| Test organization | Same tests, conditional setup | No duplication; single test validates both modes |
| Deploy vs read addresses | Always deploy fresh | Tests are isolated and deterministic |
| Hardhat tests | No changes | Keep current `buildTestEnv()` behavior |
| Fork target | Base Mainnet (8453) | Test against production contracts |

**Files to Create/Modify:**

| File | Action |
|------|--------|
| `test/mock/MockAaveV3Pool.sol` | Enhance with `FLASHLOAN_PREMIUM_TOTAL()`, `fund()`, configurable premium |
| `script/deployment/DeployMockAaveV3Pool.s.sol` | Create with local chain guard |
| `deploy/scripts/deploy-local.sh` | Add MockAaveV3Pool to Phase 1 |
| `script/deployment/SaveLocalDeployment.s.sol` | Save aaveV3Pool address |
| `script/HelperConfig.s.sol` | Add Base Mainnet config, update `getAaveV3Pool()` |
| `test/unit/Loan/BaseLoan.t.sol` | Add chain ID detection for mock vs real Aave |
| `Makefile` | Add `test-unit`, `test-integration`, `test-all` targets |
| `foundry.toml` | Add `base_mainnet` RPC endpoint |

**Test Execution Flow:**
```
make test-unit (local Anvil)
├── block.chainid == 31337
├── BaseLoan.setUp() deploys fresh MockAaveV3Pool
├── Tests run against mocks
└── Fast, deterministic, no network needed

make test-integration (Base Mainnet fork)
├── block.chainid == 8453
├── BaseLoan.setUp() uses real Aave V3
├── Tests run against production contracts
└── Validates real integration
```

**Usage:**
```bash
# Terminal 1: Start Anvil (for unit tests)
make anvil

# Terminal 2: Run tests
make test-unit         # Fast, local
make test-integration  # Fork mode
make test-all          # Both
```

**Implementation Plan:** See `docs/plans/2026-01-21-local-testing-infrastructure-impl.md`

### Plan 6: Deployment Optimization (Ready for Implementation)

**Problem:** Current `deploy-local.sh` takes too long because:
- 13 separate `forge script` calls - each has startup overhead + potential recompilation
- `via_ir = true` in foundry.toml - IR pipeline is 5-10x slower than standard compilation
- DevOpsTools broadcast file reads - requires sequential execution

**Solution:** Consolidate Phase 1 into one script and Phase 3 into one script, plus add a fast local profile.

**Expected Speedup:**
- Compilation: ~5-10x faster (no IR pipeline)
- Script execution: ~12 fewer process spawns (2 scripts vs 14)
- Overall: From several minutes → under 30 seconds for loan-provider phases

**Files to Create:**

| File | Purpose |
|------|---------|
| `loan-provider/script/deployment/DeployPhase1.s.sol` | Consolidated Phase 1: AccessManager, MockTokens, MockOracles, BTCVault |
| `loan-provider/script/deployment/DeployPhase3.s.sol` | Consolidated Phase 3: USDCVault, Loan system, Strategies, AccessManager setup |

**Files to Modify:**

| File | Change |
|------|--------|
| `loan-provider/foundry.toml` | Add `[profile.local]` with `via_ir = false` |
| `deploy/scripts/deploy-local.sh` | Replace 14 script calls with 2 (using `FOUNDRY_PROFILE=local`) |

**Key Design Decisions:**

1. **USDCVault moved to Phase 3** - Requires LendingPool address which is deployed in Phase 2
2. **In-memory address passing** - No DevOpsTools lookups between deployments within a phase
3. **Inherits from InitialSetup** - DeployPhase3 reuses existing AccessManager setup logic
4. **Individual scripts preserved** - Kept for production deployments on Base Sepolia
5. **Local profile only** - Different bytecode than production (no IR) is acceptable for local dev

**Consolidated Deployment Flow:**
```
make deploy-local
    └── deploy-local.sh (FOUNDRY_PROFILE=local)
        ├── Phase 1: DeployPhase1.s.sol (single script)
        │   ├── AccessManager
        │   ├── MockTokens (USDC, cbBTC)
        │   ├── MockOracles (BTC/USD, USDC/USD)
        │   ├── BTCVault
        │   └── Save to deployments.json
        │
        ├── Phase 2: lending-pool (unchanged)
        │   └── npm run bitmor:localhost:dev:migration
        │
        └── Phase 3: DeployPhase3.s.sol (single script)
            ├── USDCVault
            ├── MockSwapAdapter
            ├── SwapAdapterWrapper
            ├── LoanVault (implementation)
            ├── Loan
            ├── LoanVaultFactory
            ├── Strategies (Aave, USDC)
            ├── AccessManager setup (roles, grants, guardians, schedule)
            ├── Time warp + execute delayed operations
            └── Save final addresses to deployments.json
```

**Implementation Plan:** See `docs/plans/2026-01-21-deployment-optimization-design.md`

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

**Current (slow - 14 script calls):**
```
make deploy-local
    └── deploy-local.sh (--private-key for Anvil)
        ├── Phase 1: loan-provider (6 scripts)
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
        └── Phase 3: loan-provider (8 scripts)
            ├── DeployMockSwapAdapter
            ├── DeploySwapAdapterWrapper
            ├── DeployLoanVault
            ├── DeployLoan
            ├── DeployLoanVaultFactory
            ├── DeployStrategies
            ├── LocalFullSetup --sig "run(bool)" true
            └── SaveDeployedAddresses
```

**Optimized (Plan 6 - 4 script calls with schedule/execute split):**
```
make deploy-local
    └── deploy-local.sh (FOUNDRY_PROFILE=local)
        ├── Phase 1: DeployPhase1.s.sol
        │   └── AccessManager → Tokens → Oracles → BTCVault → save JSON
        │
        ├── Phase 2: lending-pool (unchanged)
        │   └── npm run bitmor:localhost:dev:migration
        │
        ├── Phase 3a: DeployPhase3.s.sol
        │   └── USDCVault → SwapAdapter → Loan → Strategies → roles → save JSON
        │
        ├── Phase 3b: SchedulePhase3.s.sol
        │   └── Schedule all timelocked operations (reads from JSON)
        │
        ├── Time advance: 87001 seconds (1 day + 10 min + 1 sec)
        │
        └── Phase 3c: ExecutePhase3.s.sol
            └── Execute scheduled operations via AccessManager
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

## How to Test Local Deployment

```bash
# Terminal 1: Start Anvil
cd bitmor-core
make anvil

# Terminal 2: Run deployment
make deploy-local

# Verify
cat loan-provider/deployments.json | jq '.deployments["31337"].networkConfig'
```

## Recommended Next Steps

### 1. Implement Plan 5 (Local Testing Infrastructure)

Execute the implementation plan at `docs/plans/2026-01-21-local-testing-infrastructure-impl.md`:

1. **Task 1:** Enhance MockAaveV3Pool with `FLASHLOAN_PREMIUM_TOTAL()`, `fund()`, configurable premium
2. **Task 2:** Create DeployMockAaveV3Pool.s.sol with local chain guard
3. **Task 3:** Update deploy-local.sh to deploy MockAaveV3Pool in Phase 1
4. **Task 4:** Update SaveLocalDeployment.s.sol to save aaveV3Pool address
5. **Task 5:** Update HelperConfig.s.sol with Base Mainnet config
6. **Task 6:** Update BaseLoan.t.sol with chain ID detection
7. **Task 7:** Update Makefile with new test targets
8. **Task 8:** Test full flow: `make anvil` → `make test-unit` → `make test-integration`

### 2. Merge fix/deploymentSetup Branch

All deployment infrastructure is working. Consider merging to main.

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
| **Optimization (Plan 6)**      |                                                                       |
| Consolidated Phase 1           | `loan-provider/script/deployment/DeployPhase1.s.sol`                  |
| Consolidated Phase 3a (deploy) | `loan-provider/script/deployment/DeployPhase3.s.sol`                  |
| Phase 3b (schedule)            | `loan-provider/script/deployment/SchedulePhase3.s.sol`                |
| Phase 3c (execute)             | `loan-provider/script/deployment/ExecutePhase3.s.sol`                 |
| Deployment constants           | `loan-provider/script/deployment/DeploymentConstants.sol`             |
| Foundry config                 | `loan-provider/foundry.toml` (add `[profile.local]`)                  |
| **Testing (Plan 5)**           |                                                                       |
| Mock Aave V3 Pool              | `loan-provider/test/mock/MockAaveV3Pool.sol`                          |
| Mock deployment script         | `loan-provider/script/deployment/DeployMockAaveV3Pool.s.sol`          |
| Test base (chain detection)    | `loan-provider/test/unit/Loan/BaseLoan.t.sol`                         |
| loan-provider Makefile         | `loan-provider/Makefile`                                              |

## Plans Reference

All implementation plans are saved in `docs/plans/`:

| Plan                              | File                                                              | Status      |
| --------------------------------- | ----------------------------------------------------------------- | ----------- |
| Deployment Testing Infrastructure | `docs/plans/2026-01-21-deployment-testing-infrastructure.md`      | Complete ✅ |
| AccessManager Integration Design  | `docs/plans/2026-01-21-accessmanager-integration-design.md`       | Complete ✅ |
| HelperConfig Consolidation        | `docs/plans/2026-01-21-helperconfig-consolidation.md`             | Complete ✅ |
| Script Configuration Optimization | `docs/plans/2026-01-21-script-config-optimization.md`             | Complete ✅ |
| Local Testing Infrastructure      | `docs/plans/2026-01-21-local-testing-infrastructure-design.md`    | Design Done |
| Local Testing Implementation      | `docs/plans/2026-01-21-local-testing-infrastructure-impl.md`      | Ready       |
| Deployment Optimization           | `docs/plans/2026-01-21-deployment-optimization-design.md`         | Complete ✅ |
| AccessManager Schedule/Execute Fix | `docs/plans/2026-01-22-fix-accessmanager-schedule-execute.md`    | Complete ✅ |
| Foundry Simulation Timing Fix     | SESSION_CONTINUATION.md (Session 8)                               | Complete ✅ |

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

### Plan 6 Commits:
- `fa917cf` docs: add deployment documentation and build infrastructure
- `bb58724` feat(test): add MockChainlinkOracle for local testing
- `3bf61e1` feat(script): add deployment scripts and strategy configuration
- `06ddd00` feat(script): add centralized getters and path helpers to HelperConfig
- `cd190d1` refactor(script): simplify LocalFullSetup to use _initialSetup without role targets
- `d16f551` fix(deploy): enable schedule/execute pattern with 1-day execution delays
- `e2adf54` fix(deploy): split Phase 3 into schedule/execute scripts

## Quick Start for New Session

```bash
# Terminal 1: Start Anvil
cd bitmor-core
make anvil

# Terminal 2: Deploy full system
make deploy-local

# Verify deployment
cat loan-provider/deployments.json | jq '.deployments["31337"].networkConfig'
```

**Current state:** Local deployment works end-to-end. Next task is implementing Plan 5 (Local Testing Infrastructure) to enable `forge test` without Base Sepolia fork.
