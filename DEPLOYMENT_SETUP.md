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
cbBTC → BTCVault → bvBTC (vault shares) → Lending Pool (collateral) → Borrow USDC
```

**Key:** The lending pool uses **bvBTC** (BTCVault shares) as collateral, not raw cbBTC.

## Deployment Phases

The deployment is split into three phases to handle cross-module dependencies:

### Phase 1: loan-provider (Foundry → Anvil)

Deploys foundational contracts and saves addresses to `loan-provider/deployments.json`:

| Contract | Description |
|----------|-------------|
| AccessManager | Role-based access control |
| MockUSDC | Mock USDC token (6 decimals) |
| MockCbBTC | Mock cbBTC token (8 decimals) |
| MockChainlinkOracle | BTC ($100k) and USDC ($1) price feeds |
| BTCVault | ERC-4626 vault producing **bvBTC** shares |

The `collateralAsset` field in `deployments.json` contains the bvBTC (BTCVault) address.

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

| Contract | Description |
|----------|-------------|
| USDCVault | USDC vault (needs LendingPool address) |
| SwapAdapterWrapper | Uniswap V4 swap integration |
| LoanVault | Per-loan smart account implementation |
| Loan | Main entry point for loans |
| LoanVaultFactory | CREATE2 factory for LoanVaults |

## Commands

| Command | Description |
|---------|-------------|
| `make anvil` | Start local Anvil (chainId 31337) |
| `make anvil-stop` | Stop Anvil |
| `make deploy-local` | Deploy complete protocol to Anvil |
| `make build` | Build all contracts |
| `make install` | Install all dependencies |
| `make test` | Run all tests |
| `make test-unit` | Run loan-provider tests only |
| `make test-lending-pool` | Run lending-pool tests only |
| `make clean` | Clean build artifacts |

## Prerequisites

### Required Wallets

The deployment scripts use cast wallets (keystore-based) instead of raw private keys:

```bash
# Create dev wallet for local deployment (uses Anvil's default account)
cast wallet import dev --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

# For testnet deployment (interactive password prompt)
cast wallet import bitmor_owner --interactive
cast wallet import bitmor_user --interactive
```

### Environment Variables

**loan-provider/.env:**
```
BASE_SEPOLIA_RPC_URL=https://...
ETHERSCAN_KEY=...
```

**lending-pool/.env:**
```
MNEMONIC="..."
ALCHEMY_KEY=...
ETHERSCAN_KEY=...
```

## Testnet Deployment (Base Sepolia)

```bash
# Use bitmor_owner account
DEPLOY_ACCOUNT=bitmor_owner ./deploy/scripts/deploy-local.sh

# Or use existing module-specific targets
cd lending-pool && npm run aave:baseSepolia:full:migration
cd loan-provider && make setup
```

## Configuration Files

| File | Purpose |
|------|---------|
| `loan-provider/deployments.json` | Phase 1 addresses (bvBTC, mocks) |
| `lending-pool/deployed-contracts.json` | Phase 2 addresses (LendingPool, Oracle) |
| `loan-provider/script/deployment/DeploymentConstants.sol` | Shared Solidity constants |
| `loan-provider/script/HelperConfig.s.sol` | Network-aware config reader |

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
# Restart Anvil with correct chainId
make anvil-stop
make anvil
```

### "bvBTC address not found"

Ensure Phase 1 completed successfully. Check:
```bash
cat loan-provider/deployments.json | jq '.deployments["31337"].networkConfig.collateralAsset'
```

### "LendingPool not deployed yet"

Ensure Phase 2 completed successfully. Check:
```bash
cat lending-pool/deployed-contracts.json | jq '.LendingPool.hardhat.address'
```

## Tech Stack

| Module | Framework | Solidity Version |
|--------|-----------|-----------------|
| lending-pool | Hardhat v3 | 0.6.12 |
| loan-provider | Foundry | 0.8.30 |
| Orchestration | Bash + Make | - |
