# HelperConfig Consolidation Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Establish HelperConfig.s.sol as the single source of truth for all deployment configuration, eliminating duplicate logic in DeploymentHelper and ensuring consistent address/param retrieval across all scripts.

**Architecture:** Add a public `readLendingPoolAddress()` method to HelperConfig that exposes existing `_readAddress()` functionality. Update DeploymentHelper to delegate to HelperConfig. Update deployment scripts to use HelperConfig consistently instead of custom address lookup logic.

**Tech Stack:** Foundry, Solidity 0.8.30, DevOpsTools

---

## Task 1: Add `readLendingPoolAddress()` to HelperConfig.s.sol

**Files:**
- Modify: `loan-provider/script/HelperConfig.s.sol:291` (after `_readLocalDeployment()`)

**Step 1: Add public method after `_readLocalDeployment()`**

Add at line 312 (end of file, before closing brace):

```solidity
    /// @notice Public wrapper to read address from lending-pool/deployed-contracts.json
    /// @param contractName The contract name key (e.g., "LendingPoolCollateralManager")
    /// @return addr The address from the JSON file
    function readLendingPoolAddress(string memory contractName) public view returns (address addr) {
        return _readAddress(contractName);
    }
```

**Step 2: Verify compilation**

Run: `cd loan-provider && forge build --match-contract HelperConfig`
Expected: Compilation successful

**Step 3: Commit**

```bash
git add loan-provider/script/HelperConfig.s.sol
git commit -m "feat(script): add readLendingPoolAddress() public method to HelperConfig"
```

---

## Task 2: Update DeploymentHelper.s.sol to Delegate to HelperConfig

**Files:**
- Modify: `loan-provider/script/helpers/DeploymentHelper.s.sol`

**Step 1: Add HelperConfig import**

Add after line 6 (after DevOpsTools import):

```solidity
import {HelperConfig} from "../HelperConfig.s.sol";
```

**Step 2: Replace `readLendingPoolAddress()` implementation**

Replace lines 53-62:

```solidity
    // ===== Lending Pool JSON Reader =====

    /// @notice Reads an address from lending-pool/deployed-contracts.json
    /// @param contractName The contract name key in the JSON
    /// @return The address from the JSON file
    function readLendingPoolAddress(string memory contractName) internal view returns (address) {
        string memory network = _getLendingPoolNetwork();
        string memory path = string.concat(vm.projectRoot(), "/../lending-pool/deployed-contracts.json");
        string memory json = vm.readFile(path);
        string memory key = string.concat(".", contractName, ".", network, ".address");
        return json.readAddress(key);
    }
```

With:

```solidity
    // ===== Lending Pool JSON Reader =====

    /// @notice Reads an address from lending-pool/deployed-contracts.json
    /// @dev Delegates to HelperConfig for single source of truth
    /// @param contractName The contract name key in the JSON
    /// @return The address from the JSON file
    function readLendingPoolAddress(string memory contractName) internal returns (address) {
        HelperConfig helperConfig = new HelperConfig();
        return helperConfig.readLendingPoolAddress(contractName);
    }
```

**Step 3: Remove `_getLendingPoolNetwork()` function**

Delete lines 64-71:

```solidity
    /// @notice Maps current chainId to lending-pool network key
    /// @return The network key used in deployed-contracts.json
    function _getLendingPoolNetwork() internal view returns (string memory) {
        if (block.chainid == 31337 || block.chainid == 1337) return "hardhat";
        if (block.chainid == 84532) return "sepolia";
        if (block.chainid == 8453) return "base";
        revert("Unsupported chain for lending-pool");
    }
```

**Step 4: Remove unused `stdJson` import**

Remove line 5:

```solidity
import {stdJson} from "forge-std/StdJson.sol";
```

And remove line 13:

```solidity
    using stdJson for string;
```

**Step 5: Verify compilation**

Run: `cd loan-provider && forge build --match-contract DeploymentHelper`
Expected: Compilation successful

**Step 6: Commit**

```bash
git add loan-provider/script/helpers/DeploymentHelper.s.sol
git commit -m "refactor(script): DeploymentHelper delegates to HelperConfig for lending-pool addresses"
```

---

## Task 3: Update DeployBTCVault.s.sol to Use HelperConfig

**Files:**
- Modify: `loan-provider/script/deployment/DeployBTCVault.s.sol`

**Step 1: Add HelperConfig import**

Add after line 6 (after DevOpsTools import):

```solidity
import {HelperConfig} from "../HelperConfig.s.sol";
```

**Step 2: Update `run()` to use HelperConfig for AccessManager**

Replace lines 12-15:

```solidity
    function run() external returns (address btcVault) {
        // Read cbBTC and AccessManager from previous deployments
        address cbBTC = _getRequiredAddress("MockCbBTC", "DeployMockTokens.s.sol");
        address accessManager = _getRequiredAddress("BitmorAccessManager", "DeployAccessManager.s.sol");
```

With:

```solidity
    function run() external returns (address btcVault) {
        // Read cbBTC from previous deployment (mock for local)
        address cbBTC = _getRequiredAddress("MockCbBTC", "DeployMockTokens.s.sol");

        // Read AccessManager from HelperConfig (consistent source)
        HelperConfig helperConfig = new HelperConfig();
        address accessManager = helperConfig.getAccessManager();
        require(accessManager != address(0), "DeployBTCVault: AccessManager not deployed");
```

**Step 3: Verify compilation**

Run: `cd loan-provider && forge build --match-contract DeployBTCVault`
Expected: Compilation successful

**Step 4: Commit**

```bash
git add loan-provider/script/deployment/DeployBTCVault.s.sol
git commit -m "refactor(script): DeployBTCVault uses HelperConfig for AccessManager"
```

---

## Task 4: Update DeployUSDCVault.s.sol for Consistency

**Files:**
- Modify: `loan-provider/script/deployment/DeployUSDCVault.s.sol`

**Step 1: Update `run()` to use HelperConfig for AccessManager**

Replace lines 13-20:

```solidity
    function run() external returns (address usdcVault) {
        // Read AccessManager and USDC from previous deployments
        address accessManager = _getRequiredAddress("BitmorAccessManager", "DeployAccessManager.s.sol");
        address usdc = _getRequiredAddress("MockUSDC", "DeployMockTokens.s.sol");

        // Read LendingPool from HelperConfig (reads from lending-pool/deployed-contracts.json)
        HelperConfig helperConfig = new HelperConfig();
        address bitmorPool = helperConfig.getBitmorPool();
```

With:

```solidity
    function run() external returns (address usdcVault) {
        // Read USDC from previous deployment (mock for local)
        address usdc = _getRequiredAddress("MockUSDC", "DeployMockTokens.s.sol");

        // Read AccessManager and LendingPool from HelperConfig (consistent source)
        HelperConfig helperConfig = new HelperConfig();
        address accessManager = helperConfig.getAccessManager();
        require(accessManager != address(0), "DeployUSDCVault: AccessManager not deployed");

        address bitmorPool = helperConfig.getBitmorPool();
```

**Step 2: Verify compilation**

Run: `cd loan-provider && forge build --match-contract DeployUSDCVault`
Expected: Compilation successful

**Step 3: Commit**

```bash
git add loan-provider/script/deployment/DeployUSDCVault.s.sol
git commit -m "refactor(script): DeployUSDCVault uses HelperConfig for AccessManager consistently"
```

---

## Task 5: Update LocalFullSetup.s.sol to Use HelperConfig

**Files:**
- Modify: `loan-provider/script/interaction/AccessManager/LocalFullSetup.s.sol`

**Step 1: Update `_buildRoleTargets()` to use HelperConfig**

Replace the `lpcm` line in `_buildRoleTargets()` (around line 90):

```solidity
            lpcm: readLendingPoolAddress("LendingPoolCollateralManager")
```

With:

```solidity
            lpcm: config.readLendingPoolAddress("LendingPoolCollateralManager")
```

Note: `config` is already a HelperConfig instance from the parent InitialSetup class.

**Step 2: Verify compilation**

Run: `cd loan-provider && forge build --match-contract LocalFullSetup`
Expected: Compilation successful

**Step 3: Commit**

```bash
git add loan-provider/script/interaction/AccessManager/LocalFullSetup.s.sol
git commit -m "refactor(script): LocalFullSetup uses HelperConfig for lending-pool addresses"
```

---

## Task 6: Final Build Verification

**Step 1: Build all contracts**

Run: `cd loan-provider && forge build`
Expected: Compilation successful with only pre-existing warnings

**Step 2: Commit final state**

```bash
git add -A
git commit -m "chore: consolidate deployment scripts to use HelperConfig as single source of truth"
```

---

## Verification Checklist

After all tasks complete:

1. [ ] `forge build` passes in loan-provider
2. [ ] No duplicate `_getLendingPoolNetwork()` logic exists
3. [ ] All deployment scripts use HelperConfig for:
   - AccessManager address
   - Lending pool addresses
   - Config params (gracePeriod, liquidationBuffer, etc.)
4. [ ] DeploymentHelper only provides utilities not in HelperConfig:
   - DevOpsTools wrappers with try/catch
   - Time manipulation (warpTime)
   - Chain detection (isLocalChain)

---

## Files Summary

| File | Action |
|------|--------|
| `loan-provider/script/HelperConfig.s.sol` | Add `readLendingPoolAddress()` public method |
| `loan-provider/script/helpers/DeploymentHelper.s.sol` | Delegate to HelperConfig, remove duplicate logic |
| `loan-provider/script/deployment/DeployBTCVault.s.sol` | Use HelperConfig for AccessManager |
| `loan-provider/script/deployment/DeployUSDCVault.s.sol` | Use HelperConfig for AccessManager (consistency) |
| `loan-provider/script/interaction/AccessManager/LocalFullSetup.s.sol` | Use config.readLendingPoolAddress() |

---

## Architecture After Changes

```
HelperConfig.s.sol (SINGLE SOURCE OF TRUTH)
    ├── Network config (addresses, params)
    ├── getAccessManager(), getBitmorPool(), getOracle()
    ├── getGracePeriod(), getLiquidationBuffer(), etc.
    ├── readLendingPoolAddress() [PUBLIC - NEW]
    ├── _readAddress() [INTERNAL - existing]
    └── _readLocalDeployment() [INTERNAL - existing]

DeploymentHelper.s.sol (UTILITIES ONLY)
    ├── DevOpsTools wrappers (requireDeployed, getDeployedAddressOrZero)
    ├── Time manipulation (warpTime, warpTimeTo)
    ├── Chain detection (isLocalChain)
    └── readLendingPoolAddress() → delegates to HelperConfig

Deployment Scripts
    └── All use HelperConfig for config/addresses
```
