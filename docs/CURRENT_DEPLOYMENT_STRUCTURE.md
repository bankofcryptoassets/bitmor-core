# Current Deployment Structure Reference

> This document captures the existing deployment infrastructure as of 2026-01-21, before the unified deployment system implementation.

## Overview

The Bitmor protocol consists of two modules with separate deployment systems:
- **lending-pool/**: Hardhat v3 + TypeScript (Solidity 0.6.12)
- **loan-provider/**: Foundry (Solidity 0.8.30)

---

## Lending Pool (Hardhat)

### Directory Structure

```
lending-pool/
├── tasks/
│   ├── actions/migrations/
│   │   ├── bitmor.action.ts        # Main deployment orchestrator
│   │   └── bitmor-dev.action.ts    # Dev deployment
│   ├── migrations/
│   │   ├── bitmor.sepolia.ts       # Base Sepolia config
│   │   └── bitmor.dev.ts           # Local dev config
│   ├── full/                       # Sequential deployment steps
│   │   ├── 1_address_provider.ts
│   │   ├── 2_lending_pool.ts
│   │   ├── 3_oracles.ts
│   │   ├── 4_data_provider.ts
│   │   ├── 5_weth_gateway.ts
│   │   ├── 6_initialize.ts
│   │   └── 7_ui_helpers.ts
│   ├── dev/
│   │   └── deploy-bitmor-mock-tokens.ts
│   └── helpers/
├── contracts/                      # Aave V2 fork + Bitmor mods
├── deployed-contracts.json         # Deployment artifacts
├── hardhat.config.ts
├── register-tasks.ts               # Task loader
└── package.json
```

### Deployment Commands

```bash
# Base Sepolia (testnet)
npm run aave:baseSepolia:full:migration

# Local development (implied but not in scripts)
npm run bitmor:dev  # If configured
```

### Deployment Sequence

1. `full:deploy-address-provider-registry`
2. `full:deploy-address-provider` (pool: Bitmor)
3. `full:deploy-lending-pool`
4. `full:deploy-oracles` (pool: Bitmor)
5. `full:data-provider` (pool: Bitmor)
6. `full:deploy-WETH-gateway`
7. `full:initialize-lending-pool` (pool: Bitmor)
8. `verify-contracts` (optional)

### Artifact: deployed-contracts.json

```json
{
  "LendingPool": {
    "sepolia": { "address": "0x816adb21898B49eC92E1FfecEAf9717D40C00fdD", "deployer": "..." },
    "hardhat": { "address": "...", "deployer": "..." },
    "localhost": { "address": "...", "deployer": "..." }
  },
  "LendingPoolConfigurator": { ... },
  "LendingPoolAddressesProvider": { ... },
  "AaveOracle": { ... },
  "abcbBTC": { ... },
  "abUSDC": { ... },
  "bcbBTC": { ... },
  "bUSDC": { ... },
  ...
}
```

### Environment Variables

```
MNEMONIC=
ALCHEMY_KEY=
ETHERSCAN_KEY=
BASE_RPC_URL=
BASE_SEPOLIA_RPC_URL=
```

---

## Loan Provider (Foundry)

### Directory Structure

```
loan-provider/
├── script/
│   ├── deployment/
│   │   ├── DeployAccessManager.s.sol
│   │   ├── DeploySwapAdapterWrapper.s.sol
│   │   ├── DeployLoanVault.s.sol
│   │   ├── DeployLoan.s.sol
│   │   ├── DeployLoanVaultFactory.s.sol
│   │   └── SaveDeployedAddresses.s.sol
│   ├── interaction/
│   │   ├── SetLoanVaultFactory.s.sol
│   │   ├── SetBitmorLoan.s.sol
│   │   ├── SetGracePeriod.s.sol
│   │   └── MintTokens.s.sol
│   └── HelperConfig.s.sol          # Central config
├── src/
│   ├── protocol/
│   ├── libraries/
│   ├── vaults/
│   └── mocks/
│       └── MintableERC20.sol
├── test/
├── broadcast/                      # Foundry deployment artifacts
├── deployments.json                # Aggregated addresses
├── foundry.toml
└── Makefile
```

### Makefile Targets

```makefile
# Core deployments
deployAccessManager
deploySwapAdapterWrapper
deployLoanVault
deployLoan
deployLoanVaultFactory
saveAddresses

# Interactions
setLoanVaultFactory
setBitmorLoan
setGracePeriod
mintTokens

# Combined
setup                    # Full deployment sequence
verifyAll
```

### Deployment Sequence (make setup)

1. `deployAccessManager`
2. `deploySwapAdapterWrapper`
3. `deployLoanVault`
4. `deployLoan`
5. `deployLoanVaultFactory`
6. `saveAddresses`
7. `setLoanVaultFactory`
8. `setGracePeriod`
9. `setBitmorLoan`

### Artifact: deployments.json

```json
{
  "deployments": {
    "84532": {
      "network": "base-sepolia",
      "deployedContracts": {
        "accessManager": "0x...",
        "swapAdapterWrapper": "0x...",
        "loanVault": "0x...",
        "loan": "0xe712f36F11D5011F4BA47BCFCDa1a40e1fa8BA2b",
        "loanVaultFactory": "0x..."
      },
      "networkConfig": {
        "bitmorLendingPool": "0x816adb21898B49eC92E1FfecEAf9717D40C00fdD",
        "aaveOracle": "0x...",
        "cbBTC": "0x...",
        "usdc": "0x..."
      },
      "constants": {
        "minDepositPercentage": 33,
        "gracePeriod": 604800,
        "slippage": 50
      },
      "timestamp": "...",
      "blockNumber": 35197687
    }
  }
}
```

### HelperConfig.s.sol

Reads addresses from:
1. `./deployments.json` (via DevOpsTools)
2. `../lending-pool/deployed-contracts.json` (cross-module)
3. Hardcoded constants (Aave V3 addresses)

```solidity
// Key addresses (Base Sepolia)
AAVE_V3_POOL = 0xcFc53C27C1b813066F22D2fa70C3D0b4CAa70b7B
AAVE_V3_ADDRESSES_PROVIDER = 0x39Eb7Ca3b8f0F29C21a008b1F281b30c4539736a

// Wallets (cast)
BITMOR_OWNER = 0x30fF6c272f2F427CcC81cb7fB14F5AFB94fF9Ad6
BITMOR_USER = 0xAe773320F12d18c93acAA4C2054340620b748E3a
```

### Environment Variables

```
BASE_SEPOLIA_RPC_URL=
ETHERSCAN_KEY=
ALCHEMY_KEY=
MNEMONIC=
BLOCK_NUMBER=35197687
```

### Foundry Configuration (foundry.toml)

```toml
[profile.default]
fs_permissions = [
  { access = "read", path = "./broadcast" },
  { access = "read", path = "../lending-pool/deployed-contracts.json" },
  { access = "read-write", path = "./deployments.json" }
]
ffi = true
cbor_metadata = true
```

---

## Cross-Module Integration

### Address Flow

```
lending-pool                    loan-provider
     │                               │
     ▼                               │
deployed-contracts.json ───────────► HelperConfig.s.sol
     │                               │
     │                               ▼
     │                          deployments.json
     │                               │
     └─── (One-way dependency) ──────┘
```

### Deployment Order

1. **Deploy lending-pool first** → generates `deployed-contracts.json`
2. **Deploy loan-provider second** → reads lending-pool addresses, generates `deployments.json`

### Current Deployed Addresses (Base Sepolia)

| Contract | Address |
|----------|---------|
| LendingPool | `0x816adb21898B49eC92E1FfecEAf9717D40C00fdD` |
| Loan | `0xe712f36F11D5011F4BA47BCFCDa1a40e1fa8BA2b` |
| LoanVaultFactory | See deployments.json |

---

## Testing Infrastructure

### Loan Provider Tests

```bash
# Fork-based tests
make test                           # Uses BASE_SEPOLIA_RPC_URL fork
forge test --fork-url base_sepolia  # Direct fork

# Specific tests
forge test --mt test_functionName --fork-url base_sepolia -vvvv
```

### Lending Pool Tests

```bash
npm test                    # Core Aave tests
npm run test-bitmor         # Bitmor-specific
npm run test-scenarios      # Protocol scenarios
```

---

## Gaps Identified

| Gap | Description |
|-----|-------------|
| No unified orchestration | Must run deployments in separate terminals |
| No local Anvil automation | DEPLOYMENT_SETUP.md mentions it but not implemented |
| Mock contracts scattered | Each module has own mocks |
| No environment validation | Can fail mid-deployment |
| No state tracking for local | Only testnet state saved |
| Documentation scattered | Info in CLAUDE.md, package.json, Makefile |

---

## Files Reference

### Critical Configuration Files

| File | Purpose |
|------|---------|
| `lending-pool/deployed-contracts.json` | Hardhat deployment artifacts |
| `loan-provider/deployments.json` | Foundry deployment artifacts |
| `loan-provider/script/HelperConfig.s.sol` | Central address resolver |
| `lending-pool/register-tasks.ts` | Task registration |
| `loan-provider/Makefile` | Deployment commands |

### Environment Files

| File | Module |
|------|--------|
| `lending-pool/.env` | Hardhat config |
| `loan-provider/.env` | Foundry config |

---

*Last updated: 2026-01-21*
