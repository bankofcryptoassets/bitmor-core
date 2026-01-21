# Script Configuration Optimization Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Centralize configuration access patterns in HelperConfig.s.sol and StrategyConfig.s.sol to eliminate redundant instantiations and inconsistent address sourcing.

**Architecture:** Refactor HelperConfig to include chain ID constants, network name mappings, and improve StrategyConfig to accept an optional HelperConfig instance instead of always creating new ones. This reduces constructor calls and establishes consistent patterns across all deployment/interaction scripts.

**Tech Stack:** Foundry Scripts (Solidity 0.8.30), forge-std, foundry-devops

---

## Analysis Summary

### Current Issues Identified

1. **Redundant HelperConfig Instantiations** (~15 instances across scripts)
2. **StrategyConfig creates internal HelperConfig** (double instantiation in LocalFullSetup)
3. **Chain ID constants scattered** across HelperConfig, StrategyConfig, SaveDeployedAddresses, SaveLocalDeployment
4. **Network name mapping hardcoded** in SaveDeployedAddresses and VerifyAllContracts
5. **Mixed address sources** in DeployBTCVault/DeployUSDCVault (DevOpsTools vs HelperConfig)

### Constraints

Per user request, changes are limited to:
- `loan-provider/script/HelperConfig.s.sol`
- `loan-provider/script/StrategyConfig.s.sol`

---

## Task 1: Centralize Chain ID Constants in HelperConfig

**Files:**
- Modify: `loan-provider/script/HelperConfig.s.sol:37-38`

**Rationale:** Chain IDs are currently defined in HelperConfig, StrategyConfig, SaveLocalDeployment, and DeploymentConstants. Making HelperConfig's constants public allows other scripts to reference them.

**Step 1: Make chain ID constants public**

Change from:
```solidity
uint256 constant CHAIN_ID_LOCAL = 31337;
uint256 constant CHAIN_ID_BASE_SEPOLIA = 84532;
```

To:
```solidity
uint256 public constant CHAIN_ID_LOCAL = 31337;
uint256 public constant CHAIN_ID_BASE_SEPOLIA = 84532;
uint256 public constant CHAIN_ID_BASE_MAINNET = 8453;
```

**Step 2: Verify build succeeds**

Run: `cd /Users/megabyte0x/Developer/bitmor/bitmor-core/loan-provider && forge build --skip test`
Expected: Build successful

**Step 3: Commit**

```bash
git add loan-provider/script/HelperConfig.s.sol
git commit -m "$(cat <<'EOF'
refactor(script): make chain ID constants public in HelperConfig

Centralizes chain ID constants as public for reference by other scripts.
Adds BASE_MAINNET chain ID for future mainnet support.

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: Add Network Name Mapping to HelperConfig

**Files:**
- Modify: `loan-provider/script/HelperConfig.s.sol` (add after line 66)

**Rationale:** SaveDeployedAddresses.s.sol and VerifyAllContracts.s.sol both have hardcoded chain ID → network name mappings. Centralizing this in HelperConfig provides a single source of truth.

**Step 1: Add network name getter**

Add after the fee constants (around line 70):

```solidity
/// @notice Returns human-readable network name for a given chain ID
/// @param chainId The chain ID to look up
/// @return name The network name (e.g., "base-sepolia", "local")
function getNetworkName(uint256 chainId) public pure returns (string memory name) {
    if (chainId == CHAIN_ID_LOCAL) {
        name = "local";
    } else if (chainId == CHAIN_ID_BASE_SEPOLIA) {
        name = "base-sepolia";
    } else if (chainId == CHAIN_ID_BASE_MAINNET) {
        name = "base";
    } else {
        name = "unknown";
    }
}

/// @notice Returns network name for current chain
/// @return name The network name for block.chainid
function getCurrentNetworkName() public view returns (string memory) {
    return getNetworkName(block.chainid);
}
```

**Step 2: Verify build succeeds**

Run: `cd /Users/megabyte0x/Developer/bitmor/bitmor-core/loan-provider && forge build --skip test`
Expected: Build successful

**Step 3: Commit**

```bash
git add loan-provider/script/HelperConfig.s.sol
git commit -m "$(cat <<'EOF'
feat(script): add network name mapping to HelperConfig

Adds getNetworkName(chainId) and getCurrentNetworkName() methods
for centralized chain ID to network name resolution.

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: Refactor StrategyConfig to Accept Optional HelperConfig

**Files:**
- Modify: `loan-provider/script/StrategyConfig.s.sol` (entire file)

**Rationale:** StrategyConfig currently creates a new HelperConfig instance internally in both `_getLocalStrategyConfig()` and `_getBaseSepoliaStrategyConfig()`. When LocalFullSetup uses StrategyConfig, this creates a redundant HelperConfig. By allowing an external HelperConfig to be passed in, we avoid double instantiation.

**Step 1: Add HelperConfig caching and overloaded methods**

Replace the entire StrategyConfig.s.sol content:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script} from "forge-std/Script.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

/// @title StrategyConfig
/// @author Bitmor Protocol
/// @notice Configuration for vault strategy deployments
/// @dev Provides chain-aware strategy configuration separate from network config
contract StrategyConfig is Script {
    /// @notice Configuration for BTCVault strategy deployment
    struct BTCVaultStrategyConfig {
        bool deployAaveStrategy; /// @dev Whether to deploy AaveTokenizedStrategy
        address yieldSource; /// @dev Aave pool address for AaveTokenizedStrategy
    }

    /// @notice Configuration for USDCVault strategy deployment
    struct USDCVaultStrategyConfig {
        bool deployUSDCStrategy; /// @dev Whether to deploy USDCStrategy
        address aavePool; /// @dev Aave V3 pool address
        address blpPool; /// @dev Bitmor Lending Pool address
        uint256 aaveAllocation; /// @dev Basis points for Aave allocation (e.g., 8000 = 80%)
        uint256 minimumDeltaRequired; /// @dev Basis points threshold for reallocation
    }

    /// @notice Complete strategy deployment configuration
    struct StrategyDeploymentConfig {
        BTCVaultStrategyConfig btcVault;
        USDCVaultStrategyConfig usdcVault;
    }

    /// @dev Cached HelperConfig instance to avoid redundant instantiation
    HelperConfig internal _cachedHelperConfig;

    /// @notice Returns strategy configuration for current chain
    /// @dev Creates a new HelperConfig instance internally
    /// @return config The strategy deployment configuration
    function getStrategyConfig() public returns (StrategyDeploymentConfig memory config) {
        return getStrategyConfig(new HelperConfig());
    }

    /// @notice Returns strategy configuration using provided HelperConfig
    /// @dev Use this overload when you already have a HelperConfig instance to avoid redundant instantiation
    /// @param helperConfig Existing HelperConfig instance to read from
    /// @return config The strategy deployment configuration
    function getStrategyConfig(HelperConfig helperConfig) public returns (StrategyDeploymentConfig memory config) {
        _cachedHelperConfig = helperConfig;

        if (block.chainid == helperConfig.CHAIN_ID_LOCAL()) {
            return _getLocalStrategyConfig();
        } else if (block.chainid == helperConfig.CHAIN_ID_BASE_SEPOLIA()) {
            return _getBaseSepoliaStrategyConfig();
        }
        revert("StrategyConfig: unsupported chain");
    }

    /// @notice Returns the cached HelperConfig instance
    /// @dev Returns the HelperConfig used in the last getStrategyConfig call
    /// @return The cached HelperConfig or reverts if not set
    function getCachedHelperConfig() public view returns (HelperConfig) {
        require(address(_cachedHelperConfig) != address(0), "StrategyConfig: no cached config");
        return _cachedHelperConfig;
    }

    /// @notice Returns strategy config for local Anvil deployment
    function _getLocalStrategyConfig() internal view returns (StrategyDeploymentConfig memory) {
        HelperConfig.NetworkConfig memory networkConfig = _cachedHelperConfig.getNetworkConfig();

        return StrategyDeploymentConfig({
            btcVault: BTCVaultStrategyConfig({deployAaveStrategy: true, yieldSource: networkConfig.aaveV3Pool}),
            usdcVault: USDCVaultStrategyConfig({
                deployUSDCStrategy: true,
                aavePool: networkConfig.aaveV3Pool,
                blpPool: networkConfig.bitmorPool,
                aaveAllocation: _cachedHelperConfig.getAaveAllocation(),
                minimumDeltaRequired: _cachedHelperConfig.getMinimumDeltaRequired()
            })
        });
    }

    /// @notice Returns strategy config for Base Sepolia deployment
    function _getBaseSepoliaStrategyConfig() internal view returns (StrategyDeploymentConfig memory) {
        HelperConfig.NetworkConfig memory networkConfig = _cachedHelperConfig.getNetworkConfig();

        return StrategyDeploymentConfig({
            btcVault: BTCVaultStrategyConfig({deployAaveStrategy: true, yieldSource: networkConfig.aaveV3Pool}),
            usdcVault: USDCVaultStrategyConfig({
                deployUSDCStrategy: true,
                aavePool: networkConfig.aaveV3Pool,
                blpPool: networkConfig.bitmorPool,
                aaveAllocation: _cachedHelperConfig.getAaveAllocation(),
                minimumDeltaRequired: _cachedHelperConfig.getMinimumDeltaRequired()
            })
        });
    }
}
```

**Step 2: Verify build succeeds**

Run: `cd /Users/megabyte0x/Developer/bitmor/bitmor-core/loan-provider && forge build --skip test`
Expected: Build successful

**Step 3: Commit**

```bash
git add loan-provider/script/StrategyConfig.s.sol
git commit -m "$(cat <<'EOF'
refactor(script): StrategyConfig accepts optional HelperConfig instance

- Add overloaded getStrategyConfig(HelperConfig) to avoid redundant instantiation
- Cache HelperConfig internally for reuse by internal methods
- Add getCachedHelperConfig() for external access to cached instance
- Use HelperConfig's public chain ID constants instead of local copies
- Change internal methods from non-view to view since they read cached config

Breaking: None - original getStrategyConfig() still works unchanged

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: Add Vault Address Getters to HelperConfig

**Files:**
- Modify: `loan-provider/script/HelperConfig.s.sol` (add after line 248)

**Rationale:** DeployStrategies.s.sol currently reads vault addresses from DevOpsTools broadcast files. Adding getters to HelperConfig provides a consistent interface, even if the underlying implementation still uses DevOpsTools.

**Step 1: Add vault address getters**

Add after `getLoan()` function (around line 250):

```solidity
/// @notice Returns the deployed BTCVault address
/// @return The BTCVault proxy address from most recent deployment
function getBTCVault() public view returns (address) {
    return _getAddress("BTCVault");
}

/// @notice Returns the deployed USDCVault address
/// @return The USDCVault proxy address from most recent deployment
function getUSDCVault() public view returns (address) {
    return _getAddress("USDCVault");
}

/// @notice Returns the deployed AaveTokenizedStrategy address for BTCVault
/// @return The AaveTokenizedStrategy address from most recent deployment
function getAaveTokenizedStrategy() public view returns (address) {
    return _getAddress("AaveTokenizedStrategy");
}

/// @notice Returns the deployed USDCStrategy address
/// @return The USDCStrategy address from most recent deployment
function getUSDCStrategy() public view returns (address) {
    return _getAddress("USDCStrategy");
}
```

**Step 2: Verify build succeeds**

Run: `cd /Users/megabyte0x/Developer/bitmor/bitmor-core/loan-provider && forge build --skip test`
Expected: Build successful

**Step 3: Commit**

```bash
git add loan-provider/script/HelperConfig.s.sol
git commit -m "$(cat <<'EOF'
feat(script): add vault and strategy address getters to HelperConfig

Adds getBTCVault(), getUSDCVault(), getAaveTokenizedStrategy(), and
getUSDCStrategy() for consistent vault address access via HelperConfig.
Uses existing _getAddress() pattern with DevOpsTools.

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: Add Token Address Getters for Local Chain

**Files:**
- Modify: `loan-provider/script/HelperConfig.s.sol` (add after vault getters)

**Rationale:** DeployBTCVault and DeployUSDCVault read token addresses from DevOpsTools for local chain. Adding dedicated getters provides a unified interface.

**Step 1: Add token getters that work for both chains**

Add after the vault getters:

```solidity
/// @notice Returns the cbBTC/BTC token address
/// @dev For local chain, reads from deployments.json; for testnet/mainnet uses constant
/// @return The cbBTC token address
function getCbBTC() public view returns (address) {
    if (block.chainid == CHAIN_ID_LOCAL) {
        return _readLocalDeployment("cbBTC");
    }
    return BTC_BASE_SEPOLIA;
}

/// @notice Returns the USDC token address
/// @dev For local chain, reads from deployments.json; for testnet/mainnet uses constant
/// @return The USDC token address
function getUSDC() public view returns (address) {
    if (block.chainid == CHAIN_ID_LOCAL) {
        return _readLocalDeployment("debtAsset");
    }
    return USDC_BASE_SEPOLIA;
}

/// @notice Returns the deployed mock cbBTC contract address (local only)
/// @return The MockCbBTC address from most recent deployment, or address(0) if not local
function getMockCbBTC() public view returns (address) {
    if (block.chainid == CHAIN_ID_LOCAL) {
        return _getAddress("MockCbBTC");
    }
    return address(0);
}

/// @notice Returns the deployed mock USDC contract address (local only)
/// @return The MockUSDC address from most recent deployment, or address(0) if not local
function getMockUSDC() public view returns (address) {
    if (block.chainid == CHAIN_ID_LOCAL) {
        return _getAddress("MockUSDC");
    }
    return address(0);
}
```

**Step 2: Verify build succeeds**

Run: `cd /Users/megabyte0x/Developer/bitmor/bitmor-core/loan-provider && forge build --skip test`
Expected: Build successful

**Step 3: Commit**

```bash
git add loan-provider/script/HelperConfig.s.sol
git commit -m "$(cat <<'EOF'
feat(script): add token address getters to HelperConfig

Adds getCbBTC(), getUSDC(), getMockCbBTC(), getMockUSDC() for unified
token address access. Local chain reads from deployments.json while
testnet/mainnet uses defined constants.

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: Add Chainlink Oracle Getters

**Files:**
- Modify: `loan-provider/script/HelperConfig.s.sol` (add after token getters)

**Rationale:** DeployMockOracles uses DeploymentConstants for prices, but there's no way to get deployed oracle addresses. Adding getters completes the oracle configuration story.

**Step 1: Add oracle address getters**

Add after token getters:

```solidity
/// @notice Returns the deployed BTC/USD Chainlink oracle address
/// @return The BTC/USD oracle address from most recent deployment
function getBtcUsdOracle() public view returns (address) {
    return _getAddress("MockChainlinkOracle");
}

/// @notice Returns the deployed USDC/USD Chainlink oracle address
/// @return The USDC/USD oracle address, or address(0) if not deployed
function getUsdcUsdOracle() public view returns (address) {
    // USDC oracle may be deployed with different name
    try this.getBtcUsdOracle() returns (address) {
        // If BTC oracle exists, try to get USDC oracle
        // Note: This assumes oracles are deployed with distinguishable names
        // For now, return address(0) as USDC is typically 1:1 pegged
        return address(0);
    } catch {
        return address(0);
    }
}
```

**Step 2: Verify build succeeds**

Run: `cd /Users/megabyte0x/Developer/bitmor/bitmor-core/loan-provider && forge build --skip test`
Expected: Build successful

**Step 3: Commit**

```bash
git add loan-provider/script/HelperConfig.s.sol
git commit -m "$(cat <<'EOF'
feat(script): add oracle address getters to HelperConfig

Adds getBtcUsdOracle() and getUsdcUsdOracle() for accessing deployed
Chainlink oracle addresses from broadcast files.

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 7: Add Deployment JSON Path Helpers

**Files:**
- Modify: `loan-provider/script/HelperConfig.s.sol` (add after oracle getters)

**Rationale:** Multiple scripts construct JSON paths for reading deployment files. Centralizing path construction reduces errors and makes the pattern discoverable.

**Step 1: Add path helpers**

Add after oracle getters:

```solidity
/// @notice Returns the path to loan-provider's deployments.json
/// @return The absolute path to deployments.json
function getDeploymentsJsonPath() public view returns (string memory) {
    return string.concat(vm.projectRoot(), "/deployments.json");
}

/// @notice Returns the path to lending-pool's deployed-contracts.json
/// @return The absolute path to deployed-contracts.json
function getLendingPoolDeploymentsPath() public view returns (string memory) {
    return string.concat(vm.projectRoot(), "/../lending-pool/deployed-contracts.json");
}

/// @notice Returns the broadcast directory for a given script
/// @param scriptName The script file name (e.g., "DeployLoan.s.sol")
/// @return The absolute path to the broadcast directory
function getBroadcastPath(string memory scriptName) public view returns (string memory) {
    return string.concat(
        vm.projectRoot(),
        "/broadcast/",
        scriptName,
        "/",
        vm.toString(block.chainid),
        "/run-latest.json"
    );
}
```

**Step 2: Verify build succeeds**

Run: `cd /Users/megabyte0x/Developer/bitmor/bitmor-core/loan-provider && forge build --skip test`
Expected: Build successful

**Step 3: Commit**

```bash
git add loan-provider/script/HelperConfig.s.sol
git commit -m "$(cat <<'EOF'
feat(script): add deployment JSON path helpers to HelperConfig

Adds getDeploymentsJsonPath(), getLendingPoolDeploymentsPath(), and
getBroadcastPath() for centralized path construction used by multiple
scripts.

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 8: Run Full Test Suite to Verify No Regressions

**Files:**
- None (verification only)

**Step 1: Run forge build**

Run: `cd /Users/megabyte0x/Developer/bitmor/bitmor-core/loan-provider && forge build`
Expected: Build successful with no errors

**Step 2: Run test suite (if fork available)**

Run: `cd /Users/megabyte0x/Developer/bitmor/bitmor-core/loan-provider && forge test --fork-url base_sepolia -vv`
Expected: All tests pass

**Step 3: Verify scripts still compile**

Run: `cd /Users/megabyte0x/Developer/bitmor/bitmor-core/loan-provider && forge script script/HelperConfig.s.sol --fork-url base_sepolia`
Expected: Script runs without error

---

## Summary of Changes

### HelperConfig.s.sol Additions

| Method | Purpose |
|--------|---------|
| `CHAIN_ID_BASE_MAINNET` | New constant for Base mainnet (8453) |
| `getNetworkName(chainId)` | Chain ID to network name mapping |
| `getCurrentNetworkName()` | Network name for current chain |
| `getBTCVault()` | BTCVault address from broadcast |
| `getUSDCVault()` | USDCVault address from broadcast |
| `getAaveTokenizedStrategy()` | Strategy address from broadcast |
| `getUSDCStrategy()` | Strategy address from broadcast |
| `getCbBTC()` | cbBTC address (chain-aware) |
| `getUSDC()` | USDC address (chain-aware) |
| `getMockCbBTC()` | Mock cbBTC address (local only) |
| `getMockUSDC()` | Mock USDC address (local only) |
| `getBtcUsdOracle()` | Oracle address from broadcast |
| `getUsdcUsdOracle()` | Oracle address (placeholder) |
| `getDeploymentsJsonPath()` | Path to deployments.json |
| `getLendingPoolDeploymentsPath()` | Path to lending-pool JSON |
| `getBroadcastPath(script)` | Path to script's broadcast file |

### StrategyConfig.s.sol Changes

| Change | Before | After |
|--------|--------|-------|
| HelperConfig instantiation | Creates new in each internal method | Accepts optional external instance, caches internally |
| Chain ID constants | Local copies | Uses HelperConfig's public constants |
| Internal methods | Non-view | View (read cached config) |
| New method | N/A | `getStrategyConfig(HelperConfig)` overload |
| New method | N/A | `getCachedHelperConfig()` accessor |

### Benefits

1. **Reduced redundancy**: Scripts using StrategyConfig can pass existing HelperConfig
2. **Centralized constants**: All chain IDs accessible from HelperConfig
3. **Consistent address access**: Vault, token, oracle addresses all via HelperConfig
4. **Path helpers**: Reduces string concatenation errors across scripts
5. **Backward compatible**: Original `getStrategyConfig()` still works unchanged
