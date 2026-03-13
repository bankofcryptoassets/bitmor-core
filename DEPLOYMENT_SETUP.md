# Bitmor Protocol Deployment Guide

## Quick Start (Local)

```bash
# 1. Create dev wallet (one-time setup)
cast wallet import dev --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

# 2. Start Anvil (terminal 1)
make anvil

# 3. Deploy protocol (terminal 2)
make deploy-local

# 4. Run tests
make test
```

## Architecture

```
cbBTC → BTCVault (UUPS proxy) → bvBTC (vault shares) → Lending Pool (collateral) → Borrow USDC
```

**Key:** The lending pool uses **bvBTC** (BTCVault shares) as collateral, not raw cbBTC.

### Proxy Architecture

All core contracts are deployed behind UUPS proxies with ERC-7201 namespaced storage:

| Contract | Proxy Pattern | Upgrade Control |
|----------|--------------|-----------------|
| Loan | UUPS | UPGRADER role (48h delay) |
| BTCVault | UUPS | UPGRADER role (48h delay) |
| USDCVault | UUPS | UPGRADER role (48h delay) |
| AutoRepayment | UUPS | UPGRADER role (48h delay) |
| BitmorAddressesProvider | UUPS | UPGRADER role (48h delay) |
| LoanVault | BeaconProxy | BeaconController (48h delay) |
| LoanVaultFactory | Non-upgradeable | Uses beacon address |
| BeaconController | Non-upgradeable | AccessManaged wrapper |
| Strategies | Non-upgradeable | Swappable via vault curator |

## Deployment Phases

The deployment is split into phases to handle cross-module dependencies:

### Phase 1: loan-provider (Foundry → Anvil)

Deploys foundational contracts and saves addresses to `loan-provider/deployments.json`:

| Contract | Type | Description |
|----------|------|-------------|
| AccessManager | Direct deploy | Role-based access control (root of trust) |
| MockUSDC | Direct deploy | Mock USDC token (6 decimals) |
| MockCbBTC | Direct deploy | Mock cbBTC token (8 decimals) |
| MockChainlinkOracle | Direct deploy | BTC ($100k) and USDC ($1) price feeds |
| BTCVault | **UUPS proxy** | ERC-4626 vault producing **bvBTC** shares |
| MockAaveV3Pool | Direct deploy | Mock Aave V3 for flash loans |

The `collateralAsset` field contains the BTCVault **proxy** address. `btcVaultImpl` contains the implementation.

### Phase 2: lending-pool (Hardhat → same Anvil)

Reads bvBTC address from `../loan-provider/deployments.json` and deploys:

| Contract | Description |
|----------|-------------|
| LendingPoolAddressesProvider | Core registry |
| LendingPool | Main pool with bvBTC + USDC reserves |
| AaveOracle | Price oracle with bvBTC pricing via `convertToAssets()` |
| Various libraries | GenericLogic, ValidationLogic, ReserveLogic |

### Phase 3: loan-provider (Foundry → same Anvil)

Reads LendingPool from `../lending-pool/deployed-contracts.json` and deploys:

| Contract | Type | Description |
|----------|------|-------------|
| LoanLogic | **Linked library** | Public library deployed separately (Loan.sol exceeds 24KB without it) |
| USDCVault | **UUPS proxy** | USDC vault (needs LendingPool address) |
| Loan | **UUPS proxy** | Main entry point for loans (linked to LoanLogic) |
| AutoRepayment | **UUPS proxy** | Scheduled repayment automation |
| BitmorAddressesProvider | **UUPS proxy** | Protocol address registry |
| LoanVault | **Beacon impl** | Per-loan smart account implementation |
| UpgradeableBeacon | Direct deploy | Beacon for LoanVault proxies |
| BeaconController | Direct deploy | AccessManaged wrapper for beacon upgrades |
| LoanVaultFactory | Direct deploy | CREATE2 factory using BeaconProxy |
| AaveTokenizedStrategy | Direct deploy | BTC vault strategy |
| USDCStrategy | Direct deploy | USDC vault strategy |

### Phase 4: Post-Deploy Validation

Runs `PostDeployChecks.s.sol` to verify:
- All proxy → implementation pointers are correct
- Beacon ownership transferred to BeaconController
- LoanVaultFactory points to correct beacon
- UPGRADER role wired on all proxies + BeaconController
- Guardian roles configured

## Commands

### Core Commands

| Command | Description |
|---------|-------------|
| `make anvil` | Start local Anvil (chainId 31337) |
| `make anvil-stop` | Stop Anvil |
| `make deploy-local` | Deploy full protocol to Anvil (all phases) |
| `make build` | Build all contracts |
| `make install` | Install all dependencies |
| `make test` | Run all tests |
| `make clean` | Clean build artifacts |

### Individual Phase Deployment (Local)

| Command | Description |
|---------|-------------|
| `make deploy:phase1:local` | Phase 1: AccessManager + BTCVault proxy + mocks |
| `make deploy:phase3:local` | Phase 3: All proxies + beacon chain + roles |
| `make deploy:check` | Post-deploy invariant checks |

### Mainnet Deployment (Base)

| Command | Description |
|---------|-------------|
| `make deploy:phase1:mainnet` | Phase 1: AccessManager + BTCVault proxy (real cbBTC) |
| `make deploy:phase3:mainnet` | Phase 3: All proxies + roles (real addresses) |
| `make deploy:schedule:mainnet` | Schedule timelocked operations |
| `make deploy:transfer:mainnet` | Transfer ADMIN to governance Safe |

### Upgrade Commands

| Command | Description |
|---------|-------------|
| `make upgrade:uups:schedule PROXY=0x... CONTRACT="src/..." INIT_DATA=0x RPC_URL=...` | Schedule UUPS upgrade |
| `make upgrade:uups:execute PROXY=0x... NEW_IMPL=0x... INIT_DATA=0x RPC_URL=...` | Execute after 48h delay |
| `make upgrade:beacon:schedule NEW_IMPL=0x... RPC_URL=...` | Schedule beacon upgrade |
| `make upgrade:beacon:execute NEW_IMPL=0x... RPC_URL=...` | Execute beacon upgrade |

## Local Deployment Flow

```
make deploy-local (FOUNDRY_PROFILE=local)
├── Phase 1: DeployPhase1Local.s.sol
│   └── AccessManager → MockTokens → MockOracles → BTCVault (UUPS proxy) → save JSON
├── Phase 2: lending-pool
│   └── npm run bitmor:localhost:dev:migration
├── Phase 3a: LoanLogic linked library + DeployPhase3Local.s.sol
│   └── Deploy LoanLogic as standalone library (Loan.sol exceeds 24KB without it)
│       → USDCVault/Loan/AutoRepayment/AddressesProvider (UUPS proxies)
│       → Beacon chain (LoanVault impl → Beacon → Controller → Factory)
│       → Strategies → Role setup + UPGRADER wiring → save JSON
├── Phase 3b: SchedulePhase3Local.s.sol
│   └── Schedule timelocked operations (1-day delay + 10min buffer)
├── Time advance: 87001 seconds (1 day + 10 min + 1 sec)
├── Phase 3c: ExecutePhase3Local.s.sol
│   └── Execute scheduled operations via AccessManager
└── Phase 4: PostDeployChecks.s.sol
    └── Validate proxy pointers, beacon ownership, role wiring
```

## Mainnet Deployment Flow

```
1. Deploy Phase 1 (deployer EOA)
   └── AccessManager + BTCVault proxy (real cbBTC)

2. Deploy lending-pool (Hardhat migration)

3. Deploy Phase 3 (deployer EOA)
   └── All proxies + beacon chain + strategies
       Roles granted to multisigs via MainnetRolesConfig

4. Schedule operations (deployer EOA)
   └── Timelocked ops with real 1-day delays

5. Wait real time (1 day for ops, 2 days for upgrades)

6. Execute operations (deployer EOA or Safe)

7. PostDeployChecks — verify all invariants

8. TransferToMultisig — ADMIN → governance Safe (irreversible)
```

## Script Architecture

```
loan-provider/script/
├── deployment/
│   ├── DeploymentConstants.sol          # Shared constants
│   ├── DeploymentBase.s.sol             # Proxy helpers, role wiring, preflight, manifest
│   ├── PostDeployChecks.s.sol           # Post-deploy invariant validation
│   ├── local/                           # Local Anvil scripts
│   │   ├── DeployPhase1Local.s.sol
│   │   ├── DeployPhase3Local.s.sol
│   │   ├── SchedulePhase3Local.s.sol
│   │   └── ExecutePhase3Local.s.sol
│   └── mainnet/                         # Base mainnet scripts
│       ├── DeployPhase1Mainnet.s.sol
│       ├── DeployPhase3Mainnet.s.sol
│       ├── SchedulePhase3Mainnet.s.sol
│       └── TransferToMultisig.s.sol
├── upgrade/                             # Future upgrade scripts
│   ├── UpgradeUUPS.s.sol
│   └── UpgradeBeacon.s.sol
├── config/                              # Per-network configs
│   ├── RolesData.sol                    # Role definitions (selectors, IDs, delays)
│   ├── LocalRolesConfig.sol             # All roles → deployer
│   └── MainnetRolesConfig.sol           # Roles → multisig addresses
├── HelperConfig.s.sol                   # Network-aware address reader
└── helpers/
    └── DeploymentHelper.s.sol           # Common deployment utilities
```

## Prerequisites

### Required Wallets

```bash
# Local deployment (uses Anvil's default account)
cast wallet import dev --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

# Mainnet deployment (interactive password prompt)
cast wallet import bitmor_owner --interactive
cast wallet import bitmor_user --interactive
```

### Environment Variables

**loan-provider/.env:**
```
BASE_SEPOLIA_RPC_URL=https://...
BASE_MAINNET_RPC_URL=https://...
ETHERSCAN_KEY=...
```

**lending-pool/.env:**
```
MNEMONIC="..."
ALCHEMY_KEY=...
ETHERSCAN_KEY=...
```

### Node.js Requirement

OZ foundry-upgrades requires Node.js for upgrade validation (storage layout checks, initializer analysis). Ensure `node` is available in PATH.

## Configuration Files

| File | Purpose |
|------|---------|
| `loan-provider/deployments.json` | All deployed addresses (proxy + impl) |
| `lending-pool/deployed-contracts.json` | Lending pool addresses |
| `loan-provider/script/deployment/DeploymentConstants.sol` | Shared Solidity constants |
| `loan-provider/script/HelperConfig.s.sol` | Network-aware config reader |
| `loan-provider/script/config/RolesData.sol` | Role definitions |
| `loan-provider/script/config/LocalRolesConfig.sol` | Local role grantees |
| `loan-provider/script/config/MainnetRolesConfig.sol` | Mainnet role grantees |

## deployments.json Schema

```json
{
  "deployments": {
    "31337": {
      "network": "localhost",
      "networkConfig": {
        "accessManager": "0x...",
        "loan": "0x...(proxy)",
        "loanImpl": "0x...(implementation)",
        "collateralAsset": "0x...(BTCVault proxy)",
        "btcVaultImpl": "0x...(implementation)",
        "usdcVault": "0x...(proxy)",
        "usdcVaultImpl": "0x...(implementation)",
        "autoRepayment": "0x...(proxy)",
        "autoRepaymentImpl": "0x...(implementation)",
        "bitmorAddressesProvider": "0x...(proxy)",
        "bitmorAddressesProviderImpl": "0x...(implementation)",
        "loanLogicLib": "0x...(linked library)",
        "beacon": "0x...(UpgradeableBeacon)",
        "beaconController": "0x...(BeaconController)",
        "loanVaultImpl": "0x...(LoanVault implementation)",
        "loanVaultFactory": "0x...",
        "aaveStrategy": "0x...",
        "usdcStrategy": "0x..."
      }
    }
  }
}
```

## Upgrade Process

### UUPS Proxy Upgrade (e.g., Loan V1 → V2)

```bash
# 1. Deploy new implementation + schedule upgrade (48h delay)
make upgrade:uups:schedule \
  PROXY=0x<loan_proxy> \
  CONTRACT="src/protocol/Loan.sol:Loan" \
  INIT_DATA=0x \
  RPC_URL=https://...

# 2. Wait 48 hours

# 3. Execute upgrade
make upgrade:uups:execute \
  PROXY=0x<loan_proxy> \
  NEW_IMPL=0x<new_impl> \
  INIT_DATA=0x \
  RPC_URL=https://...
```

### Beacon Upgrade (all LoanVault instances)

```bash
# 1. Schedule beacon upgrade (48h delay)
make upgrade:beacon:schedule \
  NEW_IMPL=0x<new_loanvault_impl> \
  RPC_URL=https://...

# 2. Wait 48 hours

# 3. Execute — atomically upgrades ALL LoanVault proxies
make upgrade:beacon:execute \
  NEW_IMPL=0x<new_loanvault_impl> \
  RPC_URL=https://...
```

### Guardian Cancellation

If an upgrade needs to be cancelled during the 48h window:
```bash
# Guardian multisig calls AccessManager.cancel() directly
cast send <accessManager> "cancel(address,address,bytes)" <caller> <target> <data> --account guardian
```

## Troubleshooting

### "Wallet 'dev' not found"

```bash
cast wallet import dev --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
```

### "Anvil not running"

```bash
make anvil
```

### "Expected chainId 31337"

```bash
make anvil-stop
make anvil
```

### "Preflight: accessManager not deployed"

Phase 1 didn't complete. Check:
```bash
cat loan-provider/deployments.json | jq '.deployments["31337"].networkConfig.accessManager'
```

### "Preflight: LendingPool not deployed"

Phase 2 didn't complete. Check:
```bash
cat lending-pool/deployed-contracts.json | jq '.LendingPool.localhost.address'
```

### "PostDeployChecks: FAILED"

One or more invariants failed. Check the console output for `[FAIL]` lines. Common causes:
- Beacon ownership not transferred to BeaconController
- UPGRADER role not wired on a proxy
- Implementation address mismatch

### OZ Upgrade Validation Error

If `Upgrades.deployUUPSProxy()` fails with storage layout errors:
```bash
cd loan-provider && forge clean && forge build
```
Ensure `ast = true`, `build_info = true`, `extra_output = ["storageLayout"]` are in foundry.toml for the active profile.

### LoanLogic Linking Error

If tests fail with unlinked library errors, ensure `dynamic_test_linking = true` is in foundry.toml. For deployment scripts, the `--libraries` flag must be passed (handled automatically by `deploy-local.sh`).

## Tech Stack

| Module | Framework | Solidity Version |
|--------|-----------|-----------------|
| lending-pool | Hardhat v3 | 0.6.12 |
| loan-provider | Foundry | 0.8.30 |
| Proxy toolkit | OpenZeppelin Foundry Upgrades | v5 |
| LoanLogic | Public linked library | 0.8.30 |
| Orchestration | Bash + Make | - |
