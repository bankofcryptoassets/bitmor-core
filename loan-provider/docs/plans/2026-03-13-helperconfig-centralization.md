# HelperConfig Centralization Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Centralize all deployment configuration into `HelperConfig.s.sol` so deployers only edit one file for any network.

**Architecture:** Add `ProtocolConfig` struct to HelperConfig for all protocol parameters (fees, slippages, bounds). Slim `NetworkConfig` to addresses-only. Move mainnet address constants into HelperConfig. Extract shared address loaders into DeploymentBase. Simplify DeployPhase scripts to delegate to these shared abstractions.

**Tech Stack:** Foundry / Solidity 0.8.30 / OpenZeppelin Upgrades

**Design doc:** `docs/plans/2026-03-13-helperconfig-centralization-design.md`

---

## Task 1: HelperConfig — Add `ProtocolConfig` struct and `getProtocolConfig()` getter

> **BLOCKING:** Tasks 2-4 depend on this task.

**Files:**
- Modify: `script/HelperConfig.s.sol`

**Step 1: Add the `ProtocolConfig` struct after `NetworkConfig` (after line 29)**

```solidity
/// @notice Protocol-wide configuration parameters for deployment scripts
/// @dev All protocol constants centralized here — deployers only edit this struct's values
struct ProtocolConfig {
    /// @notice Loan pre-closure fee in basis points (0.1%)
    uint256 preClosureFeeBps;
    /// @notice Grace period for monthly payments
    uint256 gracePeriod;
    /// @notice Maximum loan duration in months
    uint256 maxDuration;
    /// @notice Swap slippage tolerance in basis points
    uint256 slippageSwap;
    /// @notice Shares-to-asset conversion slippage tolerance in basis points
    uint256 slippageSharesToAsset;
    /// @notice Maximum cbBTC collateral amount (8 decimals)
    uint256 maxBTCAmt;
    /// @notice Minimum cbBTC collateral amount (8 decimals)
    uint256 minBTCAmt;
    /// @notice Minimum deposit percentage in basis points
    uint256 minDepositBps;
    /// @notice Liquidation fee in basis points
    uint256 liquidationFee;
    /// @notice Liquidation buffer in basis points
    uint256 liquidationBuffer;
    /// @notice Maximum strategy cap
    uint256 strategyCap;
    /// @notice Maximum number of strategies per vault
    uint256 maxStrategies;
    /// @notice Vault entry fee in basis points
    uint256 entryFee;
    /// @notice Vault exit fee in basis points
    uint256 exitFee;
}
```

**Step 2: Add protocol config constants (after line 63, near other constants)**

```solidity
// Protocol configuration constants
uint256 public constant SLIPPAGE_SWAP = 50; // 0.5%
uint256 public constant SLIPPAGE_SHARES_TO_ASSET = 100; // 1%
uint256 public constant MAX_BTC_AMOUNT = 10e8; // 10 BTC
uint256 public constant MIN_BTC_AMOUNT = 0.01e8; // 0.01 BTC
uint256 public constant MIN_DEPOSIT_BPS = 30_00; // 30%
uint256 public constant LIQUIDATION_BUFFER = 50; // 0.5%
uint256 public constant STRATEGY_CAP = type(uint256).max;
uint256 public constant MAX_STRATEGIES = 5;
```

**Step 3: Add the `getProtocolConfig()` getter (after existing getters, around line 175)**

```solidity
/// @notice Returns the full protocol configuration for deployment scripts
/// @dev All chains currently share the same values. Branch on `block.chainid` if they diverge.
/// @return config The populated ProtocolConfig struct
function getProtocolConfig() public pure returns (ProtocolConfig memory config) {
    config = ProtocolConfig({
        preClosureFeeBps: PRE_CLOSURE_FEE,
        gracePeriod: GRACE_PERIOD,
        maxDuration: MAX_DURATION,
        slippageSwap: SLIPPAGE_SWAP,
        slippageSharesToAsset: SLIPPAGE_SHARES_TO_ASSET,
        maxBTCAmt: MAX_BTC_AMOUNT,
        minBTCAmt: MIN_BTC_AMOUNT,
        minDepositBps: MIN_DEPOSIT_BPS,
        liquidationFee: LIQUIDATION_FEE,
        liquidationBuffer: LIQUIDATION_BUFFER,
        strategyCap: STRATEGY_CAP,
        maxStrategies: MAX_STRATEGIES,
        entryFee: DEFAULT_ENTRY_FEE,
        exitFee: DEFAULT_EXIT_FEE
    });
}
```

**Step 4: Remove 4 fields from `NetworkConfig` struct (lines 22-28)**

Change from:
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
    uint256 preClosureFeeBps;
    uint256 gracePeriod;
    // Vault test config
    address usdc;
    address usdc_holder;
    uint256 entryFee;
    uint256 exitFee;
}
```

To:
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

**Step 5: Update `_initLocalConfig()` — remove 4 deleted field assignments (lines 135-140)**

Remove these lines:
```solidity
s_networkConfig.preClosureFeeBps = getPreClosureFee();
s_networkConfig.gracePeriod = getGracePeriod();
...
s_networkConfig.entryFee = DEFAULT_ENTRY_FEE;
s_networkConfig.exitFee = DEFAULT_EXIT_FEE;
```

**Step 6: Update `_initBaseSepoliaConfig()` — remove 4 deleted field assignments (lines 112-117)**

Remove these lines:
```solidity
s_networkConfig.preClosureFeeBps = getPreClosureFee();
s_networkConfig.gracePeriod = getGracePeriod();
...
s_networkConfig.entryFee = DEFAULT_ENTRY_FEE;
s_networkConfig.exitFee = DEFAULT_EXIT_FEE;
```

**Step 7: Add mainnet address constants (after `AAVE_ADDRESSES_PROVIDER_BASE_MAINNET`, line 50)**

```solidity
// TODO: Replace with actual Base mainnet addresses before deployment
address constant CBBTC_BASE_MAINNET = address(0);
address constant USDC_BASE_MAINNET = address(0);
address constant SWAP_ADAPTER_BASE_MAINNET = address(0);
```

**Step 8: Add/update getters for mainnet addresses**

Update `getCbBTC()` (line 331) to branch on mainnet:
```solidity
function getCbBTC() public view returns (address) {
    if (block.chainid == CHAIN_ID_BASE_MAINNET) {
        return CBBTC_BASE_MAINNET;
    }
    return _readDeployment("cbBTC");
}
```

Update `getUSDC()` (line 338) to branch on mainnet:
```solidity
function getUSDC() public view returns (address) {
    if (block.chainid == CHAIN_ID_BASE_MAINNET) {
        return USDC_BASE_MAINNET;
    }
    return _readDeployment("debtAsset");
}
```

Add new getter for swap adapter on mainnet:
```solidity
/// @notice Returns the swap adapter address
/// @dev Mainnet uses a hardcoded constant; local/testnet reads from deployments.json
function getSwapAdapterAddress() public view returns (address) {
    if (block.chainid == CHAIN_ID_BASE_MAINNET) {
        return SWAP_ADAPTER_BASE_MAINNET;
    }
    return _readDeployment("swapper");
}
```

**Step 9: Add `getLendingPoolNetworkKey()` getter**

```solidity
/// @notice Returns the network key used in lending-pool/deployed-contracts.json
/// @dev Maps chain ID to the key the lending-pool Hardhat deployment uses
/// @return key The network key (e.g., "localhost", "sepolia", "base")
function getLendingPoolNetworkKey() public view returns (string memory key) {
    if (block.chainid == CHAIN_ID_LOCAL || block.chainid == 1337) {
        key = "localhost";
    } else if (block.chainid == CHAIN_ID_BASE_SEPOLIA) {
        key = "sepolia";
    } else if (block.chainid == CHAIN_ID_BASE_MAINNET) {
        key = "base";
    } else {
        revert("HelperConfig: unsupported chain for lending pool network key");
    }
}
```

**Step 10: Build and verify compilation**

Run: `cd loan-provider && forge build`
Expected: Compilation succeeds (tests may have warnings about unused fields but should not error since no test accesses the removed struct fields directly)

**Step 11: Commit**

```
feat: add ProtocolConfig struct and centralize config in HelperConfig

- Add ProtocolConfig struct with all 14 protocol parameters
- Add getProtocolConfig() getter for deployment scripts
- Slim NetworkConfig: remove preClosureFeeBps, gracePeriod, entryFee, exitFee
- Add mainnet address constants (CBBTC, USDC, SWAP_ADAPTER)
- Add getLendingPoolNetworkKey() for shared JSON key resolution
- Update getCbBTC()/getUSDC() to branch on mainnet chain ID
```

---

## Task 2: DeploymentBase — Add shared address loaders

> **Depends on:** Task 1
> **BLOCKING:** Tasks 3-4 depend on this task.

**Files:**
- Modify: `script/deployment/DeploymentBase.s.sol`

**Step 1: Add import for HelperConfig (after line 17)**

```solidity
import {HelperConfig} from "../HelperConfig.s.sol";
```

**Step 2: Add return structs for loaders (after the `RoleGrantees` struct, around line 76)**

```solidity
/// @notice Addresses loaded from deployments.json (Phase 1 outputs)
struct Phase1Addresses {
    address accessManager;
    address debtAsset;     // USDC (mock or real)
    address cbBTC;         // cbBTC (mock or real)
    address btcVault;      // BTCVault proxy (collateralAsset)
    address btcVaultImpl;  // BTCVault implementation
    address btcOracle;     // BTC/USD oracle (local only, address(0) on mainnet)
    address usdcOracle;    // USDC/USD oracle (local only, address(0) on mainnet)
    address aaveV3Pool;    // Aave V3 Pool (mock or real)
    address aaveAddressesProvider; // Aave V3 Addresses Provider (mock or real)
    address loanLogicLib;  // LoanLogic linked library (address(0) if not deployed)
}

/// @notice Addresses loaded from lending-pool/deployed-contracts.json
struct LendingPoolAddresses {
    address bitmorPool;
    address aaveOracle;
    address lendingPoolAddressesProvider;
}
```

**Step 3: Add `_loadPhase1Addresses()` shared loader (after `_preflightLendingPool()`, around line 516)**

```solidity
/// @notice Loads Phase 1 addresses from deployments.json for the current chain
/// @dev Uses `block.chainid` to construct the JSON path dynamically — no hardcoded chain ID strings.
/// Fields that don't exist for certain chains (e.g., oracles on mainnet) return address(0).
/// @return addrs The populated Phase1Addresses struct
function _loadPhase1Addresses() internal view returns (Phase1Addresses memory addrs) {
    string memory json = vm.readFile("./deployments.json");
    string memory base = string.concat(".deployments.", vm.toString(block.chainid), ".networkConfig.");

    addrs.accessManager = vm.parseJsonAddress(json, string.concat(base, "accessManager"));
    addrs.cbBTC = vm.parseJsonAddress(json, string.concat(base, "cbBTC"));
    addrs.btcVault = vm.parseJsonAddress(json, string.concat(base, "collateralAsset"));
    addrs.btcVaultImpl = vm.parseJsonAddress(json, string.concat(base, "btcVaultImpl"));

    // debtAsset may not exist in Phase 1 on mainnet (USDC is a known constant)
    try vm.parseJsonAddress(json, string.concat(base, "debtAsset")) returns (address parsed) {
        addrs.debtAsset = parsed;
    } catch {}

    // These only exist on local/testnet (mock deployments)
    try vm.parseJsonAddress(json, string.concat(base, "btcOracle")) returns (address parsed) {
        addrs.btcOracle = parsed;
    } catch {}
    try vm.parseJsonAddress(json, string.concat(base, "usdcOracle")) returns (address parsed) {
        addrs.usdcOracle = parsed;
    } catch {}
    try vm.parseJsonAddress(json, string.concat(base, "aaveV3Pool")) returns (address parsed) {
        addrs.aaveV3Pool = parsed;
    } catch {}
    try vm.parseJsonAddress(json, string.concat(base, "aaveAddressesProvider")) returns (address parsed) {
        addrs.aaveAddressesProvider = parsed;
    } catch {}
    try vm.parseJsonAddress(json, string.concat(base, "loanLogicLib")) returns (address parsed) {
        addrs.loanLogicLib = parsed;
    } catch {}

    // On mainnet, Aave addresses come from HelperConfig constants, not deployments.json
    if (block.chainid == DeploymentConstants.BASE_MAINNET_CHAIN_ID) {
        HelperConfig helperConfig = new HelperConfig();
        addrs.aaveV3Pool = helperConfig.getAaveV3Pool();
        addrs.aaveAddressesProvider = helperConfig.getAaveAddressesProvider();
        addrs.debtAsset = helperConfig.getUSDC();
    }

    console2.log("Loaded Phase 1: AccessManager:", addrs.accessManager);
    console2.log("Loaded Phase 1: BTCVault:", addrs.btcVault);
}
```

**Step 4: Add `_loadLendingPoolAddresses()` shared loader**

```solidity
/// @notice Loads lending pool addresses from deployed-contracts.json for the current chain
/// @dev Uses `HelperConfig.getLendingPoolNetworkKey()` for the JSON network key.
/// @return addrs The populated LendingPoolAddresses struct
function _loadLendingPoolAddresses() internal view returns (LendingPoolAddresses memory addrs) {
    HelperConfig helperConfig = new HelperConfig();
    string memory networkKey = helperConfig.getLendingPoolNetworkKey();
    string memory json = vm.readFile("../lending-pool/deployed-contracts.json");

    addrs.bitmorPool = vm.parseJsonAddress(json, string.concat(".LendingPool.", networkKey, ".address"));
    addrs.aaveOracle = vm.parseJsonAddress(json, string.concat(".AaveOracle.", networkKey, ".address"));
    addrs.lendingPoolAddressesProvider =
        vm.parseJsonAddress(json, string.concat(".LendingPoolAddressesProvider.", networkKey, ".address"));

    console2.log("Loaded LendingPool:", addrs.bitmorPool);
    console2.log("Loaded AaveOracle:", addrs.aaveOracle);
    console2.log("Loaded LendingPoolAddressesProvider:", addrs.lendingPoolAddressesProvider);
}
```

**Step 5: Update `_preflightLendingPool()` to use HelperConfig (lines 501-516)**

Replace the hardcoded network key mapping:

```solidity
function _preflightLendingPool() internal view {
    string memory json = vm.readFile("../lending-pool/deployed-contracts.json");

    HelperConfig helperConfig = new HelperConfig();
    string memory networkKey = helperConfig.getLendingPoolNetworkKey();

    address lendingPool = vm.parseJsonAddress(json, string.concat(".LendingPool.", networkKey, ".address"));
    require(lendingPool != address(0), "DeploymentBase: LendingPool is zero");
    require(lendingPool.code.length > 0, "DeploymentBase: LendingPool has no bytecode");
}
```

**Step 6: Build and verify**

Run: `cd loan-provider && forge build`
Expected: Compilation succeeds

**Step 7: Commit**

```
feat: add shared address loaders to DeploymentBase

- Add Phase1Addresses and LendingPoolAddresses return structs
- Add _loadPhase1Addresses() with dynamic chain ID path resolution
- Add _loadLendingPoolAddresses() using HelperConfig.getLendingPoolNetworkKey()
- Update _preflightLendingPool() to use HelperConfig for network key
```

---

## Task 3: Simplify DeployPhase1 scripts

> **Depends on:** Tasks 1 and 2

**Files:**
- Modify: `script/deployment/local/DeployPhase1Local.s.sol`
- Modify: `script/deployment/mainnet/DeployPhase1Mainnet.s.sol`

**Step 1: Simplify DeployPhase1Local**

Remove `MAX_STRATEGIES` constant (line 26). Add import and use `getProtocolConfig()`:

Add import after existing imports:
```solidity
import {HelperConfig} from "../../HelperConfig.s.sol";
```

Replace line 99 (the `BTCVault.initialize` call) — change `MAX_STRATEGIES` to:
```solidity
HelperConfig helperConfig = new HelperConfig();
HelperConfig.ProtocolConfig memory pc = helperConfig.getProtocolConfig();
```

Then in the `_deployUUPSProxy` call:
```solidity
btcVault = _deployUUPSProxy(
    "BTCVault.sol", abi.encodeCall(BTCVault.initialize, (mockCbBTC, accessManager, pc.maxStrategies))
);
```

**Step 2: Simplify DeployPhase1Mainnet**

Remove `MAX_STRATEGIES` constant (line 29). Remove `CBBTC_BASE_MAINNET` constant (line 34).

Add import:
```solidity
import {HelperConfig} from "../../HelperConfig.s.sol";
```

In `run()`, replace the constant references:
```solidity
HelperConfig helperConfig = new HelperConfig();
HelperConfig.ProtocolConfig memory pc = helperConfig.getProtocolConfig();
address cbBTC = helperConfig.getCbBTC();

require(cbBTC != address(0), "DeployPhase1Mainnet: set CBBTC_BASE_MAINNET in HelperConfig");
require(cbBTC.code.length > 0, "DeployPhase1Mainnet: cbBTC has no bytecode");
```

Replace `CBBTC_BASE_MAINNET` → `cbBTC` and `MAX_STRATEGIES` → `pc.maxStrategies` throughout.

Update `_savePhase1()` to use `cbBTC` state variable instead of `CBBTC_BASE_MAINNET`. Add `address public cbBTC;` as a state variable set in `run()`.

**Step 3: Build and verify**

Run: `cd loan-provider && forge build`
Expected: Compilation succeeds

**Step 4: Commit**

```
refactor: simplify DeployPhase1 scripts to use HelperConfig

- Remove MAX_STRATEGIES constant from both Phase1 scripts
- Remove CBBTC_BASE_MAINNET from DeployPhase1Mainnet
- Use HelperConfig.getProtocolConfig().maxStrategies
- Use HelperConfig.getCbBTC() for mainnet cbBTC address
```

---

## Task 4: Simplify DeployPhase3 scripts

> **Depends on:** Tasks 1 and 2

**Files:**
- Modify: `script/deployment/local/DeployPhase3Local.s.sol`
- Modify: `script/deployment/mainnet/DeployPhase3Mainnet.s.sol`

### Sub-task 4a: Simplify DeployPhase3Local

**Step 1: Delete all 11 constants (lines 42-72)**

Remove:
```
PRE_CLOSURE_FEE, GRACE_PERIOD, MAX_DURATION, SLIPPAGE_SWAP,
SLIPPAGE_SHARES_TO_ASSET, MAX_BTC_AMOUNT, MIN_BTC_AMOUNT,
MIN_DEPOSIT_BPS, LIQUIDATION_FEE, LIQUIDATION_BUFFER, STRATEGY_CAP
```

**Step 2: Add HelperConfig import (if not already present)**

```solidity
import {HelperConfig} from "../../HelperConfig.s.sol";
```

**Step 3: Delete `_loadPhase1Addresses()` (lines 367-385) and `_loadLendingPoolAddresses()` (lines 389-399)**

These are replaced by the inherited versions in DeploymentBase.

**Step 4: Refactor `run()` to use shared loaders and ProtocolConfig**

Replace the state variable declarations and loading calls at the top of `run()`. After `_preflightPhase3()` and `_preflightLendingPool()`:

```solidity
HelperConfig helperConfig = new HelperConfig();
HelperConfig.ProtocolConfig memory pc = helperConfig.getProtocolConfig();

Phase1Addresses memory p1 = _loadPhase1Addresses();
LendingPoolAddresses memory lp = _loadLendingPoolAddresses();

// Assign to state variables for _saveDeployments() and _setupAccessManagerRoles()
accessManager = p1.accessManager;
mockUsdc = p1.debtAsset;
mockCbBTC = p1.cbBTC;
btcVault = p1.btcVault;
btcVaultImpl = p1.btcVaultImpl;
btcOracle = p1.btcOracle;
usdcOracle = p1.usdcOracle;
aaveV3Pool = p1.aaveV3Pool;
aaveAddressesProvider = p1.aaveAddressesProvider;
loanLogicLib = p1.loanLogicLib;
bitmorPool = lp.bitmorPool;
aaveOracle = lp.aaveOracle;
lendingPoolAddressesProvider = lp.lendingPoolAddressesProvider;
```

**Step 5: Update `ILoan.InitParams` construction to use `pc` (around line 270)**

```solidity
ILoan.InitParams memory loanInitParams = ILoan.InitParams({
    manager: accessManager,
    aaveV3Pool: aaveV3Pool,
    aaveAddressesProvider: aaveAddressesProvider,
    bitmorPool: bitmorPool,
    oracle: aaveOracle,
    collateralAsset: btcVault,
    debtAsset: mockUsdc,
    btc: mockCbBTC,
    bitmorAddressesProvider: bitmorAddressesProvider,
    preClosureFeeBps: pc.preClosureFeeBps,
    gracePeriod: pc.gracePeriod,
    slippageSwap: pc.slippageSwap,
    slippageSharesToAsset: pc.slippageSharesToAsset,
    maxBTCAmt: pc.maxBTCAmt,
    minBTCAmt: pc.minBTCAmt,
    minDeposit: pc.minDepositBps,
    maxDuration: pc.maxDuration,
    liquidationFee: pc.liquidationFee
});
```

### Sub-task 4b: Simplify DeployPhase3Mainnet

**Step 6: Delete all 11 constants + 2 mainnet address constants**

Remove constants (lines 38-70):
```
PRE_CLOSURE_FEE, GRACE_PERIOD, MAX_DURATION, SLIPPAGE_SWAP,
SLIPPAGE_SHARES_TO_ASSET, MAX_BTC_AMOUNT, MIN_BTC_AMOUNT,
MIN_DEPOSIT_BPS, LIQUIDATION_FEE, LIQUIDATION_BUFFER, STRATEGY_CAP
```

Remove mainnet address constants (lines 74-78):
```
SWAP_ADAPTER_BASE_MAINNET, USDC_BASE_MAINNET
```

**Step 7: Add HelperConfig import**

```solidity
import {HelperConfig} from "../../HelperConfig.s.sol";
```

**Step 8: Delete `_loadPhase1Addresses()`, `_loadLendingPoolAddresses()`, `_loadExternalProtocolAddresses()`**

All replaced by inherited DeploymentBase loaders.

**Step 9: Refactor `run()` — same pattern as Local**

```solidity
HelperConfig helperConfig = new HelperConfig();
HelperConfig.ProtocolConfig memory pc = helperConfig.getProtocolConfig();

// Mainnet address validation
address swapAdapterAddr = helperConfig.getSwapAdapterAddress();
address usdcAddr = helperConfig.getUSDC();
require(swapAdapterAddr != address(0), "DeployPhase3Mainnet: set SWAP_ADAPTER_BASE_MAINNET in HelperConfig");
require(usdcAddr != address(0), "DeployPhase3Mainnet: set USDC_BASE_MAINNET in HelperConfig");
require(swapAdapterAddr.code.length > 0, "DeployPhase3Mainnet: swap adapter has no bytecode");
require(usdcAddr.code.length > 0, "DeployPhase3Mainnet: USDC has no bytecode");

Phase1Addresses memory p1 = _loadPhase1Addresses();
LendingPoolAddresses memory lp = _loadLendingPoolAddresses();

// Assign to state variables
accessManager = p1.accessManager;
cbBTC = p1.cbBTC;
btcVault = p1.btcVault;
btcVaultImpl = p1.btcVaultImpl;
aaveV3Pool = p1.aaveV3Pool;
aaveAddressesProvider = p1.aaveAddressesProvider;
bitmorPool = lp.bitmorPool;
aaveOracle = lp.aaveOracle;
lendingPoolAddressesProvider = lp.lendingPoolAddressesProvider;
swapAdapter = swapAdapterAddr;
usdc = usdcAddr;
```

**Step 10: Update `ILoan.InitParams` construction to use `pc` (same as Local)**

**Step 11: Build and verify**

Run: `cd loan-provider && forge build`
Expected: Compilation succeeds

**Step 12: Commit**

```
refactor: simplify DeployPhase3 scripts to use HelperConfig and shared loaders

- Remove 11 duplicated constants from both DeployPhase3 scripts
- Remove mainnet address constants (SWAP_ADAPTER, USDC) from DeployPhase3Mainnet
- Delete per-script _loadPhase1Addresses() and _loadLendingPoolAddresses()
- Use inherited DeploymentBase shared loaders
- Build ILoan.InitParams from HelperConfig.getProtocolConfig()
```

---

## Task 5: Run full test suite and fix any breakage

> **Depends on:** Tasks 1-4

**Files:**
- Potentially modify: any test file that accesses removed `NetworkConfig` fields

**Step 1: Run unit tests**

Run: `cd loan-provider && make test`
Expected: All unit tests pass. The removed `NetworkConfig` fields (`preClosureFeeBps`, `gracePeriod`, `entryFee`, `exitFee`) are NOT accessed directly in tests — they all go through getters like `config.getPreClosureFee()` which still work.

**Step 2: Run build to check for compilation errors**

Run: `cd loan-provider && forge build`
Expected: Clean build. If any test file imports `NetworkConfig` and destructures it expecting 16 fields, it will fail here — fix by updating the destructure to 12 fields.

**Step 3: If any tests fail, fix them**

The most likely breakage pattern:
- Test code that does `NetworkConfig memory nc = config.s_networkConfig()` and accesses `.preClosureFeeBps` → replace with `config.getPreClosureFee()`
- Test code that constructs a `NetworkConfig` literal with all fields → remove the 4 deleted fields

**Step 4: Commit fixes if any**

```
fix: update tests for slimmed NetworkConfig struct
```

---

## Parallel Agent Assignment (Git Worktrees)

| Agent | Task(s) | Worktree Branch | Depends On |
|-------|---------|-----------------|------------|
| Agent 1 | Tasks 1 + 2 | `feat/helperconfig-central-core` | None (blocking) |
| Agent 2 | Task 3 | `feat/helperconfig-central-phase1` | Agent 1 merged |
| Agent 3 | Task 4 | `feat/helperconfig-central-phase3` | Agent 1 merged |
| Agent 4 | Task 5 | `feat/helperconfig-central-tests` | Agents 2+3 merged |

**Merge order:** Agent 1 → merge to `feat/upgradability` → Agents 2 & 3 (parallel) → merge both → Agent 4

**Note:** Agents 2 and 3 can run in parallel since they touch different files (Phase1 vs Phase3 scripts). Agent 4 runs last to catch any integration issues.
