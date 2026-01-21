# AccessManager Integration Design

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Create production-like AccessManager setup with schedule/execute pattern for local and fork deployments.

**Key Decision:** Use `--private-key` for local Anvil (pre-funded accounts), time warp via `skip()` for delayed operations.

---

## Architecture Overview

```
make deploy-local
    └── deploy-local.sh (--private-key for Anvil)
        ├── Phase 1: loan-provider (vaults, mocks)
        ├── Phase 2: lending-pool (LendingPool)
        └── Phase 3: loan-provider
            ├── DeployLoan, DeployLoanVault, DeployLoanVaultFactory
            ├── DeployStrategies.s.sol
            ├── LocalFullSetup.s.sol --sig "run(bool)" true
            │   ├── _setupTargetFunctionRoles()
            │   ├── _grantRoles()
            │   ├── _setupGuardians() (chain-aware)
            │   ├── _scheduleOperations()
            │   ├── warpTime(1 days + 1)
            │   └── _executeOperations()
            └── SaveDeployedAddresses
```

---

## Task 1: Create DeploymentHelper.s.sol

**File:** `loan-provider/script/helpers/DeploymentHelper.s.sol`

**Purpose:** Centralized helper library for common deployment operations.

```solidity
// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {DevOpsTools} from "lib/foundry-devops/src/DevOpsTools.sol";

/// @title DeploymentHelper
/// @notice Common utilities for deployment scripts
contract DeploymentHelper is Script {
    using stdJson for string;

    // ===== DevOpsTools Wrappers =====

    function getDeployedAddress(string memory contractName) internal view returns (address) {
        return DevOpsTools.get_most_recent_deployment(contractName, block.chainid);
    }

    function getDeployedAddressOrZero(string memory contractName) internal view returns (address) {
        try this._getDeployedAddressExternal(contractName) returns (address addr) {
            return addr;
        } catch {
            return address(0);
        }
    }

    function _getDeployedAddressExternal(string memory contractName) external view returns (address) {
        return DevOpsTools.get_most_recent_deployment(contractName, block.chainid);
    }

    function requireDeployed(string memory contractName) internal view returns (address addr) {
        addr = getDeployedAddress(contractName);
        require(addr != address(0), string.concat(contractName, " not deployed"));
    }

    // ===== Lending Pool JSON Reader =====

    function readLendingPoolAddress(string memory contractName) internal view returns (address) {
        string memory network = _getLendingPoolNetwork();
        string memory path = string.concat(vm.projectRoot(), "/../lending-pool/deployed-contracts.json");
        string memory json = vm.readFile(path);
        string memory key = string.concat(".", contractName, ".", network, ".address");
        return json.readAddress(key);
    }

    function _getLendingPoolNetwork() internal view returns (string memory) {
        if (block.chainid == 31337 || block.chainid == 1337) return "hardhat";
        if (block.chainid == 84532) return "sepolia";
        if (block.chainid == 8453) return "base";
        revert("Unsupported chain for lending-pool");
    }

    // ===== Anvil Time Manipulation =====

    /// @notice Advances block.timestamp by specified seconds
    /// @param seconds_ Time to skip forward
    function warpTime(uint256 seconds_) internal {
        skip(seconds_);
    }

    /// @notice Sets block.timestamp to specific value
    /// @param newTimestamp The new timestamp to set
    function warpTimeTo(uint256 newTimestamp) internal {
        vm.warp(newTimestamp);
    }

    // ===== Common Validation =====

    function requireNonZero(address addr, string memory name) internal pure {
        require(addr != address(0), string.concat(name, " is zero address"));
    }

    function isLocalChain() internal view returns (bool) {
        return block.chainid == 31337;
    }
}
```

**Verification:**
```bash
cd loan-provider && forge build --match-contract DeploymentHelper
```

---

## Task 2: Create StrategyConfig.s.sol

**File:** `loan-provider/script/StrategyConfig.s.sol`

**Purpose:** Strategy deployment configuration, separate from network config.

```solidity
// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script} from "forge-std/Script.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

/// @title StrategyConfig
/// @notice Configuration for vault strategy deployments
contract StrategyConfig is Script {

    struct BTCVaultStrategyConfig {
        bool deployAaveStrategy;
        address yieldSource;        // Aave pool for AaveTokenizedStrategy
    }

    struct USDCVaultStrategyConfig {
        bool deployUSDCStrategy;
        address aavePool;           // Aave V3 pool
        address blpPool;            // Bitmor Lending Pool
        uint256 aaveAllocation;     // Basis points (e.g., 8000 = 80%)
        uint256 minimumDeltaRequired; // Basis points for reallocation threshold
    }

    struct StrategyDeploymentConfig {
        BTCVaultStrategyConfig btcVault;
        USDCVaultStrategyConfig usdcVault;
    }

    uint256 constant CHAIN_ID_LOCAL = 31337;
    uint256 constant CHAIN_ID_BASE_SEPOLIA = 84532;

    function getStrategyConfig() public view returns (StrategyDeploymentConfig memory) {
        if (block.chainid == CHAIN_ID_LOCAL) {
            return _getLocalStrategyConfig();
        } else if (block.chainid == CHAIN_ID_BASE_SEPOLIA) {
            return _getBaseSepoliaStrategyConfig();
        }
        revert("StrategyConfig: unsupported chain");
    }

    function _getLocalStrategyConfig() internal view returns (StrategyDeploymentConfig memory) {
        HelperConfig helperConfig = new HelperConfig();
        HelperConfig.NetworkConfig memory networkConfig = helperConfig.getNetworkConfig();

        return StrategyDeploymentConfig({
            btcVault: BTCVaultStrategyConfig({
                deployAaveStrategy: true,
                yieldSource: networkConfig.aaveV3Pool
            }),
            usdcVault: USDCVaultStrategyConfig({
                deployUSDCStrategy: true,
                aavePool: networkConfig.aaveV3Pool,
                blpPool: networkConfig.bitmorPool,
                aaveAllocation: 8000,        // 80% to Aave
                minimumDeltaRequired: 100    // 1% minimum delta
            })
        });
    }

    function _getBaseSepoliaStrategyConfig() internal view returns (StrategyDeploymentConfig memory) {
        HelperConfig helperConfig = new HelperConfig();
        HelperConfig.NetworkConfig memory networkConfig = helperConfig.getNetworkConfig();

        return StrategyDeploymentConfig({
            btcVault: BTCVaultStrategyConfig({
                deployAaveStrategy: true,
                yieldSource: networkConfig.aaveV3Pool
            }),
            usdcVault: USDCVaultStrategyConfig({
                deployUSDCStrategy: true,
                aavePool: networkConfig.aaveV3Pool,
                blpPool: networkConfig.bitmorPool,
                aaveAllocation: 8000,
                minimumDeltaRequired: 100
            })
        });
    }
}
```

**Verification:**
```bash
cd loan-provider && forge build --match-contract StrategyConfig
```

---

## Task 3: Create DeployStrategies.s.sol

**File:** `loan-provider/script/deployment/DeployStrategies.s.sol`

**Purpose:** Deploys vault strategies based on StrategyConfig.

```solidity
// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script, console} from "forge-std/Script.sol";
import {DeploymentHelper} from "../helpers/DeploymentHelper.s.sol";
import {StrategyConfig} from "../StrategyConfig.s.sol";
import {AaveTokenizedStrategy} from "@btcVault/TokenizedStrategy/AaveTokenizedStrategy.sol";
import {USDCStrategy} from "@usdcVault/USDCStrategy.sol";

/// @title DeployStrategies
/// @notice Deploys vault strategies based on StrategyConfig
contract DeployStrategies is Script, DeploymentHelper {

    function run() external returns (address aaveStrategy, address usdcStrategy) {
        StrategyConfig strategyConfig = new StrategyConfig();
        StrategyConfig.StrategyDeploymentConfig memory config = strategyConfig.getStrategyConfig();

        // Get deployed vault addresses
        address btcVault = requireDeployed("BTCVault");
        address usdcVault = requireDeployed("USDCVault");

        vm.startBroadcast();

        // Deploy BTC Vault Strategy (AaveTokenizedStrategy)
        if (config.btcVault.deployAaveStrategy) {
            AaveTokenizedStrategy strategy = new AaveTokenizedStrategy(
                config.btcVault.yieldSource,
                btcVault
            );
            aaveStrategy = address(strategy);
            console.log("AaveTokenizedStrategy:", aaveStrategy);
        }

        // Deploy USDC Vault Strategy
        if (config.usdcVault.deployUSDCStrategy) {
            USDCStrategy strategy = new USDCStrategy(
                usdcVault,
                config.usdcVault.aavePool,
                config.usdcVault.blpPool
            );
            usdcStrategy = address(strategy);
            console.log("USDCStrategy:", usdcStrategy);
        }

        vm.stopBroadcast();

        console.log("=== Strategies Deployed ===");
    }
}
```

**Verification:**
```bash
cd loan-provider && forge build --match-contract DeployStrategies
```

---

## Task 4: Modify RolesData.sol

**File:** `loan-provider/src/accessManager/RolesData.sol`

**Changes:** Add `RoleTargets` struct and `getAllRolesWithTargets()` function.

**Add after existing structs:**

```solidity
/// @notice Addresses for role targets and contract grantees
struct RoleTargets {
    address loan;
    address btcVault;
    address usdcVault;
    address autoRepayment;
    address lpcm;  // LendingPoolCollateralManager
}

/// @notice Returns all roles configured with actual deployed addresses
/// @param targets Contract addresses for role targets
/// @param admin Address for EOA roles (deployer/multisig)
function getAllRolesWithTargets(
    RoleTargets memory targets,
    address admin
) external view returns (RoleData[] memory roles) {
    roles = new RoleData[](16);

    // Admin role
    roles[0] = _buildRole(ADMIN, address(0), admin);

    // Loan roles - target: loan contract
    roles[1] = _buildRole(EXECUTOR, targets.loan, admin);           // EOA grantee
    roles[2] = _buildRole(LPCM, targets.loan, targets.lpcm);        // Contract grantee
    roles[3] = _buildRole(LPM_FAST, targets.loan, admin);
    roles[4] = _buildRole(LPM_SLOW, targets.loan, admin);

    // AutoRepayment role
    roles[5] = _buildRole(ARE, targets.autoRepayment, admin);

    // BTCVault roles - target: btcVault contract
    roles[6] = _buildRole(BVM_FAST, targets.btcVault, admin);
    roles[7] = _buildRole(BVM_SLOW, targets.btcVault, admin);
    roles[8] = _buildRole(BVC, targets.btcVault, admin);
    roles[9] = _buildRole(BVA_FAST, targets.btcVault, admin);
    roles[10] = _buildRole(BVA_SLOW, targets.btcVault, admin);
    roles[11] = _buildRole(BVD, targets.btcVault, targets.loan);    // Loan as grantee

    // USDCVault roles - target: usdcVault contract
    roles[12] = _buildRole(UVM_FAST, targets.usdcVault, admin);
    roles[13] = _buildRole(UVM_SLOW, targets.usdcVault, admin);
    roles[14] = _buildRole(UVC, targets.usdcVault, admin);
    roles[15] = _buildRole(UVA, targets.usdcVault, admin);
}

/// @notice Builds a RoleData with overridden target and grantee
function _buildRole(
    RoleData storage baseRole,
    address target,
    address grantee
) internal view returns (RoleData memory) {
    return RoleData({
        target: target,
        grantee: grantee,
        isContract: baseRole.isContract,
        executionDelay: baseRole.executionDelay,
        grantDelay: baseRole.grantDelay,
        id: baseRole.id,
        label: baseRole.label,
        selectors: baseRole.selectors,
        isGuarded: baseRole.isGuarded,
        guardian: baseRole.guardian,
        adminRoleId: baseRole.adminRoleId
    });
}
```

**Verification:**
```bash
cd loan-provider && forge build --match-contract RolesData
```

---

## Task 5: Modify InitialSetup.s.sol

**File:** `loan-provider/script/interaction/AccessManager/InitialSetup.s.sol`

**Changes:** Add virtual `_buildRoleTargets()` and use dynamic targets.

**Add virtual function:**

```solidity
/// @notice Builds role targets from deployed addresses
/// @dev Override in child contracts to provide actual deployed addresses
function _buildRoleTargets() internal view virtual returns (RolesData.RoleTargets memory) {
    // Default: return empty targets (for backward compatibility)
    return RolesData.RoleTargets({
        loan: address(0),
        btcVault: address(0),
        usdcVault: address(0),
        autoRepayment: address(0),
        lpcm: address(0)
    });
}

/// @notice Returns the admin address for EOA roles
/// @dev Override to customize admin address
function _getAdmin() internal view virtual returns (address) {
    return config.getInitialAdmin();
}
```

**Modify `_initialSetup()` to support dynamic targets (add alternative function):**

```solidity
/// @notice Setup with dynamic targets (for LocalFullSetup)
function _initialSetupWithTargets() internal {
    config = new HelperConfig();
    manager = BitmorAccessManager(config.getAccessManager());

    RolesData rolesData = new RolesData();
    RolesData.RoleTargets memory targets = _buildRoleTargets();
    address admin = _getAdmin();

    RolesData.RoleData[] memory roles = rolesData.getAllRolesWithTargets(targets, admin);

    uint256 rolesLength = roles.length;
    if (rolesLength == 0) return;

    for (uint256 i = 0; i < rolesLength; i++) {
        RolesData.RoleData memory role = roles[i];

        // Skip if target is zero (contract not deployed)
        if (role.target == address(0) && role.selectors.length > 0) continue;

        _setRoleLabel(role.id, role.label);

        if (role.adminRoleId > 0) {
            _setAdmin(role.id, role.adminRoleId);
        }

        if (role.grantDelay > 0) {
            _setGrantDelay(role.id, role.grantDelay);
        }

        if (role.selectors.length > 0 && role.target != address(0)) {
            _setTargetSelectors(role.target, role.selectors, role.id);
        }

        if (role.isContract && role.grantee != address(0)) {
            _validateContract(role.grantee);
        }

        if (role.grantee != address(0)) {
            _grantRole(role.id, role.grantee, role.executionDelay);
        }
    }
}
```

**Verification:**
```bash
cd loan-provider && forge build --match-contract InitialSetup
```

---

## Task 6: Create LocalFullSetup.s.sol

**File:** `loan-provider/script/interaction/AccessManager/LocalFullSetup.s.sol`

**Purpose:** Comprehensive AccessManager setup with schedule/execute pattern.

```solidity
// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {console} from "forge-std/console.sol";
import {InitialSetup} from "./InitialSetup.s.sol";
import {DeploymentHelper} from "../../helpers/DeploymentHelper.s.sol";
import {StrategyConfig} from "../../StrategyConfig.s.sol";
import {RolesData} from "@bitmor/accessManager/RolesData.sol";
import {ILoan} from "@bitmor/interfaces/ILoan.sol";

/// @title LocalFullSetup
/// @notice Comprehensive AccessManager setup: roles, grants, schedule, warp, execute
contract LocalFullSetup is InitialSetup, DeploymentHelper {

    // Deployed contract addresses
    address internal loan;
    address internal btcVault;
    address internal usdcVault;
    address internal autoRepayment;

    // Config
    StrategyConfig internal strategyConfig;
    RolesData internal rolesData;

    /// @notice Main entry point
    /// @param enableTimeWarp Set true for Anvil (local or fork), false for live networks
    function run(bool enableTimeWarp) external {
        _loadDeployedAddresses();
        _loadConfigs();

        vm.startBroadcast();

        // Step 1-2: Setup target function roles and grant roles
        _initialSetupWithTargets();

        // Step 3: Setup guardians (chain-aware)
        _setupGuardians();

        // Step 4: Schedule all delayed operations
        _scheduleOperations();

        vm.stopBroadcast();

        // Step 5: Time warp (if enabled)
        if (enableTimeWarp) {
            console.log("Warping time by 1 day + 1 second...");
            warpTime(1 days + 1);

            vm.startBroadcast();

            // Step 6: Execute scheduled operations
            _executeOperations();

            vm.stopBroadcast();
        } else {
            console.log("Time warp disabled. Operations scheduled but not executed.");
            console.log("Execute manually after delay or warp time externally.");
        }

        _logSummary(enableTimeWarp);
    }

    function _loadDeployedAddresses() internal {
        loan = requireDeployed("Loan");
        btcVault = requireDeployed("BTCVault");
        usdcVault = requireDeployed("USDCVault");
        autoRepayment = getDeployedAddressOrZero("AutoRepayment");
    }

    function _loadConfigs() internal {
        strategyConfig = new StrategyConfig();
        rolesData = new RolesData();
    }

    /// @notice Override to provide actual deployed addresses
    function _buildRoleTargets() internal view override returns (RolesData.RoleTargets memory) {
        return RolesData.RoleTargets({
            loan: loan,
            btcVault: btcVault,
            usdcVault: usdcVault,
            autoRepayment: autoRepayment,
            lpcm: readLendingPoolAddress("LendingPoolCollateralManager")
        });
    }

    // ===== Guardian Setup =====

    function _setupGuardians() internal {
        address admin = config.getInitialAdmin();

        if (isLocalChain()) {
            _setupSimplifiedGuardians(admin);
        } else {
            _setupProductionGuardians();
        }
    }

    function _setupSimplifiedGuardians(address admin) internal {
        // Grant all guardian roles to admin with 0 delay
        _grantRole(rolesData.GUARDIAN_LPM_SLOW().id, admin, 0);
        _grantRole(rolesData.GUARDIAN_BVM_SLOW().id, admin, 0);
        _grantRole(rolesData.GUARDIAN_BVC().id, admin, 0);
        _grantRole(rolesData.GUARDIAN_BVA_SLOW().id, admin, 0);
        _grantRole(rolesData.GUARDIAN_UVM_SLOW().id, admin, 0);
        _grantRole(rolesData.GUARDIAN_UVC().id, admin, 0);

        // Set guardian relationships
        vm.broadcast();
        manager.setRoleGuardian(rolesData.LPM_SLOW().id, rolesData.GUARDIAN_LPM_SLOW().id);
        vm.broadcast();
        manager.setRoleGuardian(rolesData.BVM_SLOW().id, rolesData.GUARDIAN_BVM_SLOW().id);
        vm.broadcast();
        manager.setRoleGuardian(rolesData.BVC().id, rolesData.GUARDIAN_BVC().id);
        vm.broadcast();
        manager.setRoleGuardian(rolesData.BVA_SLOW().id, rolesData.GUARDIAN_BVA_SLOW().id);
        vm.broadcast();
        manager.setRoleGuardian(rolesData.UVM_SLOW().id, rolesData.GUARDIAN_UVM_SLOW().id);
        vm.broadcast();
        manager.setRoleGuardian(rolesData.UVC().id, rolesData.GUARDIAN_UVC().id);
    }

    function _setupProductionGuardians() internal {
        _setGuardian(rolesData.LPM_SLOW().id, rolesData.GUARDIAN_LPM_SLOW());
        _setGuardian(rolesData.BVM_SLOW().id, rolesData.GUARDIAN_BVM_SLOW());
        _setGuardian(rolesData.BVC().id, rolesData.GUARDIAN_BVC());
        _setGuardian(rolesData.BVA_SLOW().id, rolesData.GUARDIAN_BVA_SLOW());
        _setGuardian(rolesData.UVM_SLOW().id, rolesData.GUARDIAN_UVM_SLOW());
        _setGuardian(rolesData.UVC().id, rolesData.GUARDIAN_UVC());
    }

    // ===== Schedule Operations =====

    function _scheduleOperations() internal {
        uint48 when = uint48(block.timestamp + 1 days);

        // LPM_SLOW Operations (Loan config)
        address loanVaultFactory = requireDeployed("LoanVaultFactory");

        _scheduleOperation(loan, abi.encodeCall(ILoan.setLoanVaultFactory, (loanVaultFactory)), when);
        _scheduleOperation(loan, abi.encodeCall(ILoan.setGracePeriod, (config.getGracePeriod())), when);
        _scheduleOperation(loan, abi.encodeCall(ILoan.setLiquidationBuffer, (config.getLiquidationBuffer())), when);
        _scheduleOperation(loan, abi.encodeCall(ILoan.setPremiumCollector, (config.getPremiumCollector())), when);
        _scheduleOperation(loan, abi.encodeCall(ILoan.setPreClosureFee, (config.getPreClosureFee())), when);

        // BVC Operations (BTCVault strategy) - if strategy deployed
        address aaveStrategy = getDeployedAddressOrZero("AaveTokenizedStrategy");
        if (aaveStrategy != address(0)) {
            // Note: addStrategy selector needs to match BTCVault interface
            _scheduleOperation(btcVault, abi.encodeWithSignature("addStrategy(address)", aaveStrategy), when);
        }

        // UVC Operations (USDCVault strategy) - if strategy deployed
        address usdcStrategy = getDeployedAddressOrZero("USDCStrategy");
        if (usdcStrategy != address(0)) {
            StrategyConfig.StrategyDeploymentConfig memory stratConfig = strategyConfig.getStrategyConfig();
            _scheduleOperation(usdcVault, abi.encodeWithSignature("setNewStrategy(address)", usdcStrategy), when);
            _scheduleOperation(
                usdcVault,
                abi.encodeWithSignature("setYieldSourceAllocation(uint256)", stratConfig.usdcVault.aaveAllocation),
                when
            );
        }

        console.log("Operations scheduled for:", when);
    }

    function _scheduleOperation(address target, bytes memory data, uint48 when) internal {
        vm.broadcast();
        manager.schedule(target, data, when);
    }

    // ===== Execute Operations =====

    function _executeOperations() internal {
        // LPM_SLOW Operations
        address loanVaultFactory = requireDeployed("LoanVaultFactory");

        _executeOperation(loan, abi.encodeCall(ILoan.setLoanVaultFactory, (loanVaultFactory)));
        _executeOperation(loan, abi.encodeCall(ILoan.setGracePeriod, (config.getGracePeriod())));
        _executeOperation(loan, abi.encodeCall(ILoan.setLiquidationBuffer, (config.getLiquidationBuffer())));
        _executeOperation(loan, abi.encodeCall(ILoan.setPremiumCollector, (config.getPremiumCollector())));
        _executeOperation(loan, abi.encodeCall(ILoan.setPreClosureFee, (config.getPreClosureFee())));

        // BVC Operations
        address aaveStrategy = getDeployedAddressOrZero("AaveTokenizedStrategy");
        if (aaveStrategy != address(0)) {
            _executeOperation(btcVault, abi.encodeWithSignature("addStrategy(address)", aaveStrategy));
        }

        // UVC Operations
        address usdcStrategy = getDeployedAddressOrZero("USDCStrategy");
        if (usdcStrategy != address(0)) {
            StrategyConfig.StrategyDeploymentConfig memory stratConfig = strategyConfig.getStrategyConfig();
            _executeOperation(usdcVault, abi.encodeWithSignature("setNewStrategy(address)", usdcStrategy));
            _executeOperation(
                usdcVault,
                abi.encodeWithSignature("setYieldSourceAllocation(uint256)", stratConfig.usdcVault.aaveAllocation)
            );
        }

        console.log("All operations executed.");
    }

    function _executeOperation(address target, bytes memory data) internal {
        vm.broadcast();
        manager.execute(target, data);
    }

    // ===== Logging =====

    function _logSummary(bool timeWarpEnabled) internal view {
        console.log("");
        console.log("=== LocalFullSetup Complete ===");
        console.log("Loan:", loan);
        console.log("BTCVault:", btcVault);
        console.log("USDCVault:", usdcVault);
        console.log("AutoRepayment:", autoRepayment);
        console.log("Time warp enabled:", timeWarpEnabled);
    }
}
```

**Verification:**
```bash
cd loan-provider && forge build --match-contract LocalFullSetup
```

---

## Task 7: Update deploy-local.sh

**File:** `deploy/scripts/deploy-local.sh`

**Changes:** Use `--private-key`, add DeployStrategies, replace interaction scripts with LocalFullSetup.

```bash
#!/bin/bash
set -e

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RPC="http://127.0.0.1:8545"

# Anvil's default funded account (Account 0)
PRIVATE_KEY="${PRIVATE_KEY:-0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80}"

log() { echo "[DEPLOY] $1"; }
error() { echo "[ERROR] $1"; exit 1; }

# ============ Preflight Checks ============
log "=== Preflight Checks ==="

cast chain-id --rpc-url "$RPC" > /dev/null 2>&1 || error "Anvil not running. Start with: make anvil"
CHAIN_ID=$(cast chain-id --rpc-url "$RPC")
log "Anvil running (chainId: $CHAIN_ID)"

[ "$CHAIN_ID" = "31337" ] || error "Expected chainId 31337, got $CHAIN_ID"

# ============ Phase 1: loan-provider (vaults) ============
log ""
log "=========================================="
log "Phase 1: loan-provider (AccessManager, Vaults)"
log "=========================================="
cd "$ROOT/loan-provider"

log "Deploying AccessManager..."
forge script script/deployment/DeployAccessManager.s.sol:DeployAccessManager \
    --rpc-url "$RPC" --private-key "$PRIVATE_KEY" --broadcast -vvv

log "Deploying Mock Tokens (USDC, cbBTC)..."
forge script script/deployment/DeployMockTokens.s.sol:DeployMockTokens \
    --rpc-url "$RPC" --private-key "$PRIVATE_KEY" --broadcast -vvv

log "Deploying Mock Oracles..."
forge script script/deployment/DeployMockOracles.s.sol:DeployMockOracles \
    --rpc-url "$RPC" --private-key "$PRIVATE_KEY" --broadcast -vvv

log "Deploying BTCVault (produces bvBTC)..."
forge script script/deployment/DeployBTCVault.s.sol:DeployBTCVault \
    --rpc-url "$RPC" --private-key "$PRIVATE_KEY" --broadcast -vvv

log "Deploying USDCVault..."
forge script script/deployment/DeployUSDCVault.s.sol:DeployUSDCVault \
    --rpc-url "$RPC" --private-key "$PRIVATE_KEY" --broadcast -vvv

log "Saving Phase 1 addresses to deployments.json..."
forge script script/deployment/SaveLocalDeployment.s.sol:SaveLocalDeployment \
    --rpc-url "$RPC" --private-key "$PRIVATE_KEY" --broadcast -vvv

log "Phase 1 complete."

# ============ Phase 2: lending-pool ============
log ""
log "=========================================="
log "Phase 2: lending-pool (LendingPool with bvBTC reserve)"
log "=========================================="
cd "$ROOT/lending-pool"

log "Deploying Bitmor Lending Pool..."
npm run bitmor:localhost:dev:migration

log "Phase 2 complete."

# ============ Phase 3: loan-provider (Loan contracts) ============
log ""
log "=========================================="
log "Phase 3: loan-provider (Loan contracts + AccessManager setup)"
log "=========================================="
cd "$ROOT/loan-provider"

log "Deploying SwapAdapterWrapper..."
forge script script/deployment/DeploySwapAdapterWrapper.s.sol:DeploySwapAdapterWrapper \
    --rpc-url "$RPC" --private-key "$PRIVATE_KEY" --broadcast -vvv

log "Deploying LoanVault..."
forge script script/deployment/DeployLoanVault.s.sol:DeployLoanVault \
    --rpc-url "$RPC" --private-key "$PRIVATE_KEY" --broadcast -vvv

log "Deploying Loan..."
forge script script/deployment/DeployLoan.s.sol:DeployLoan \
    --rpc-url "$RPC" --private-key "$PRIVATE_KEY" --broadcast -vvv

log "Deploying LoanVaultFactory..."
forge script script/deployment/DeployLoanVaultFactory.s.sol:DeployLoanVaultFactory \
    --rpc-url "$RPC" --private-key "$PRIVATE_KEY" --broadcast -vvv

log "Deploying Strategies..."
forge script script/deployment/DeployStrategies.s.sol:DeployStrategies \
    --rpc-url "$RPC" --private-key "$PRIVATE_KEY" --broadcast -vvv

log "Running LocalFullSetup (roles, grants, schedule, warp, execute)..."
forge script script/interaction/AccessManager/LocalFullSetup.s.sol:LocalFullSetup \
    --sig "run(bool)" true \
    --rpc-url "$RPC" --private-key "$PRIVATE_KEY" --broadcast -vvv

log "Saving final addresses..."
forge script script/deployment/SaveDeployedAddresses.s.sol:SaveDeployedAddresses \
    --rpc-url "$RPC" --private-key "$PRIVATE_KEY" --broadcast -vvv

# ============ Summary ============
log ""
log "=========================================="
log "Deployment Complete!"
log "=========================================="
log ""
log "Addresses saved to:"
log "  - loan-provider/deployments.json"
log "  - lending-pool/deployed-contracts.json"
log ""
log "Verify with:"
log "  cat loan-provider/deployments.json | jq '.deployments[\"31337\"]'"
```

**Verification:**
```bash
chmod +x deploy/scripts/deploy-local.sh
./deploy/scripts/deploy-local.sh  # With Anvil running
```

---

## Files Summary

| Action | File |
|--------|------|
| Create | `loan-provider/script/helpers/DeploymentHelper.s.sol` |
| Create | `loan-provider/script/StrategyConfig.s.sol` |
| Create | `loan-provider/script/deployment/DeployStrategies.s.sol` |
| Create | `loan-provider/script/interaction/AccessManager/LocalFullSetup.s.sol` |
| Modify | `loan-provider/src/accessManager/RolesData.sol` |
| Modify | `loan-provider/script/interaction/AccessManager/InitialSetup.s.sol` |
| Modify | `deploy/scripts/deploy-local.sh` |

---

## Verification Checklist

1. [ ] All new Solidity files compile: `cd loan-provider && forge build`
2. [ ] deploy-local.sh is executable: `chmod +x deploy/scripts/deploy-local.sh`
3. [ ] Start Anvil: `make anvil`
4. [ ] Run deployment: `make deploy-local`
5. [ ] Verify addresses: `cat loan-provider/deployments.json | jq '.deployments["31337"]'`
6. [ ] Check AccessManager state: roles granted, operations executed
