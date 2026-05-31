# Bitmor Protocol

Get your first whole 1 BTC with an undercollateralised loan.


## Repo Setup

This repo has three projects:
1. Lending Pool: A fork of Aave V2 with Hardhat (Solidity 0.6.12) — custom liquidation mechanics.
2. Loan Provider: Foundry-based BTC loan system using flash loans and per-user vaults (Solidity 0.8.30).
3. Swap Routers: Uniswap V4 swap adapter integration (Foundry, Solidity 0.8.30).


## Setup

## Prerequisites

Before setting up the project, ensure you have the following installed:

| Tool           | Version | Purpose                          |
| -------------- | ------- | -------------------------------- |
| Node.js        | v18+    | lending-pool (Hardhat)           |
| npm            | v9+     | Package management               |
| Docker         | Latest  | Container environment            |
| docker-compose | Latest  | Multi-container orchestration    |
| Foundry        | Latest  | loan-provider (Forge/Cast/Anvil) |
| Git            | Latest  | Version control                  |

### Install Foundry

```bash
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

Verify installation:
```bash
forge --version
cast --version
anvil --version
```

---

## Repository Structure

```
bitmor-core/
├── lending-pool/          # Aave V2 fork (Hardhat + TypeScript, Solidity 0.6.12)
│   ├── contracts/         # Solidity contracts
│   ├── test-suites/       # Test suites
│   └── helpers/           # Deployment helpers
│
├── loan-provider/         # BTC loan system (Foundry + Solidity 0.8.30)
│   ├── src/               # Source contracts (UUPS + Beacon upgradeable)
│   ├── test/              # Foundry tests
│   └── script/            # Deployment & upgrade scripts
│       ├── deployment/    # Phase-based deployment (local/ + mainnet/)
│       ├── upgrade/       # UUPS and Beacon upgrade scripts
│       └── config/        # RolesData, per-network role configs
│
├── swap-routers/          # Uniswap V4 swap adapter (Foundry + Solidity 0.8.30)
│   ├── src/               # UniswapV4SwapAdapterWrapper
│   └── script/            # Deployment scripts
│
└── deploy/scripts/        # Cross-module deployment orchestration
    └── deploy-local.sh    # Full local protocol deployment
```

---

## Setup

### Quick Start (Recommended)

From the repository root:

```bash
make install     # Installs all dependencies + enables git hooks
make build       # Build all contracts
make test        # Run unit tests
```

> **Note for existing team members:** After pulling this branch, run `make install` once to enable the new pre-commit formatting hooks.

### Quick Start (lending-pool only)

```bash
cd lending-pool
npm install
npm run compile
npm test
```

### Quick Start (loan-provider only)

```bash
cd loan-provider
forge install
forge build
make test        # Run unit tests (no RPC needed)
```

---

## Code Formatting

This repository uses automatic code formatting via git pre-commit hooks.

### Automatic Formatting (on commit)

After running `make install`, code is automatically formatted every time you commit:
- **lending-pool**: Prettier formats `.sol`, `.ts` files
- **loan-provider**: `forge fmt` formats Solidity files

### Manual Formatting

```bash
make format        # Format all code
make format-check  # Check formatting without changes (useful for CI)
```

### Setup for New/Existing Team Members

```bash
make install       # Run once after cloning or pulling this update
```

This configures git to use the `.githooks/` folder for pre-commit hooks.

---

## Detailed Setup

### lending-pool Setup (Docker)

The repository uses Docker Compose to manage sensitive keys and load the configuration. Prior any action like test or deploy, you must run `docker-compose up` to start the `contracts-env` container, and then connect to the container console via `docker-compose exec contracts-env bash`.

Follow the next steps to setup the repository:

1. Install `docker` and `docker-compose`
2. Create an environment file named `.env`:

```bash
# lending-pool/.env

# Mnemonic, only first address will be used
MNEMONIC=""

# Add Alchemy or Infura provider keys, alchemy takes preference at the config level
ALCHEMY_KEY=""
INFURA_KEY=""

# Optional Etherscan key, for automatize the verification of the contracts at Etherscan
ETHERSCAN_KEY=""

# Optional, if you plan to use Tenderly scripts
TENDERLY_PROJECT=""
TENDERLY_USERNAME=""
```

3. Start Docker environment:
```bash
docker-compose up
```

4. In a separate terminal, connect to the container:
```bash
docker-compose exec contracts-env bash
```

### lending-pool Setup (Without Docker)

If you prefer running without Docker:

```bash
cd lending-pool
npm install
npm run compile
```

### loan-provider Setup

1. Navigate to the loan-provider directory:
```bash
cd loan-provider
```

2. Install dependencies:
```bash
forge install
```

3. Create environment file:
```bash
# loan-provider/.env

# RPC URLs
BASE_SEPOLIA_RPC_URL="https://sepolia.base.org"
BASE_MAINNET_RPC_URL="https://mainnet.base.org"

# Etherscan API key for verification
ETHERSCAN_KEY=""

# Private keys (for deployment only)
PRIVATE_KEY=""
```

4. Setup Cast Wallets (for deployments):
```bash
# Create deployer wallet
cast wallet new bitmor_owner

# Create test user wallet
cast wallet new bitmor_user
```

Learn more about cast wallets: https://getfoundry.sh/cast/reference/wallet

5. Build contracts:
```bash
forge build
```

---

## Testing

For quick testing:
```bash
# Unit tests (no RPC needed)
make test

# Run all tests (unit + lending-pool)
make test:all

# Specific test targets
make test:loan:unit          # Loan contract tests
make test:vault:unit         # Vault tests
make test:strategy:unit      # Strategy tests
make test:fork               # Fork tests (requires BASE_SEPOLIA_RPC_URL)
make test:fuzz               # Fuzz tests
make test:integration        # Integration tests (requires make deploy-local first)
```

See [TEST.md](./TEST.md) for complete testing documentation.

---

## Local Development

### Running Local Anvil Node

```bash
# From repository root
make anvil
```

This starts a local Ethereum node on `http://localhost:8545` (port 8545, chainId 31337).

### Full Local Deployment

In a separate terminal:
```bash
make deploy-local
```

This runs a multi-phase proxy-based deployment:
1. **Phase 1**: AccessManager, MockTokens, MockOracles, BTCVault (UUPS proxy)
2. **Phase 2**: lending-pool migration (Hardhat)
3. **Phase 3a**: LoanLogic linked library + all remaining UUPS proxies + Beacon chain + Strategies + Roles
4. **Phase 3b**: Schedule timelocked operations (1-day delay)
5. **Phase 3c**: Execute scheduled operations
6. **Phase 4**: PostDeployChecks validation (proxy pointers, beacon ownership, role wiring)

### Verify Local Deployment

```bash
cat deployments/31337/latest.json | jq .
```

---

## Proxy Architecture

All core contracts are deployed behind proxies with ERC-7201 namespaced storage:

| Contract | Proxy Pattern | Upgrade Control |
|----------|--------------|-----------------|
| Loan | UUPS | UPGRADER role (48h delay) |
| BTCVault | UUPS | UPGRADER role (48h delay) |
| USDCVault | UUPS | UPGRADER role (48h delay) |
| AutoRepayment | UUPS | UPGRADER role (48h delay) |
| BitmorAddressesProvider | UUPS | UPGRADER role (48h delay) |
| LoanVault | BeaconProxy | BeaconController (48h delay) |

See [DEPLOYMENT_SETUP.md](./DEPLOYMENT_SETUP.md) for upgrade procedures and guardian cancellation.

## Deployments

All core loan-provider contracts are deployed behind UUPS or Beacon proxies. See [DEPLOYMENT_SETUP.md](./DEPLOYMENT_SETUP.md) for the full deployment guide.

### Quick Reference

| Command | Description |
|---------|-------------|
| `make deploy-local` | Deploy full protocol to local Anvil (all phases) |
| `make deploy:phase1:local` | Phase 1 only: AccessManager + BTCVault proxy + mocks |
| `make deploy:phase3:local` | Phase 3 only: All proxies + beacon chain + roles |
| `make deploy:check` | Post-deploy invariant checks |

### Mainnet Deployment

| Command | Description |
|---------|-------------|
| `make deploy:phase1:mainnet` | Phase 1: AccessManager + BTCVault proxy (real cbBTC) |
| `make deploy:phase3:mainnet` | Phase 3: All proxies + roles (real addresses) |
| `make deploy:schedule:mainnet` | Schedule timelocked operations |
| `make deploy:transfer:mainnet` | Transfer ADMIN to governance Safe |

### Upgrade Commands

| Command | Description |
|---------|-------------|
| `make upgrade:uups:schedule PROXY=0x... CONTRACT="src/..." INIT_DATA=0x RPC_URL=...` | Schedule UUPS upgrade (48h delay) |
| `make upgrade:beacon:schedule NEW_IMPL=0x... RPC_URL=...` | Schedule beacon upgrade (48h delay) |

### lending-pool Deployments

| Command                                   | Description                  |
| ----------------------------------------- | ---------------------------- |
| `npm run aave:baseSepolia:full:migration` | Deploy to Base Sepolia       |
| `npm run bitmor:localhost:dev:migration`  | Deploy to local Hardhat node |

### Deployment Addresses

Deployed addresses are stored in the unified registry:
- `deployments/<chainId>/latest.json` - all addresses (loan-provider, lending-pool, tokens, external)
- Timestamped snapshots in `deployments/<chainId>/` for deployment history

---

## Troubleshooting

### Common Issues

#### lending-pool

| Issue                                        | Solution                                                                |
| -------------------------------------------- | ----------------------------------------------------------------------- |
| `HardhatError: HHE1000` - Artifact not found | Run `npm run compile` before tests                                      |
| Tests hang on Docker                         | Ensure Docker has sufficient memory (4GB+)                              |
| TypeScript errors                            | Run `npm run compile` to regenerate types                               |
| `Error 85: LP_CALLER_NOT_VAULT`              | Bitmor requires vault-mediated deposits; use `depositViaVault()` helper |

#### loan-provider

| Issue                           | Solution                                                         |
| ------------------------------- | ---------------------------------------------------------------- |
| `forge test` fails without fork | Use `make test` for unit tests or `make test:fork` for fork tests |
| Missing submodules              | Run `forge install` or `git submodule update --init --recursive` |
| `Stack too deep` errors         | Use `--via-ir` flag or refactor code                             |
| Cast wallet not found           | Run `cast wallet new <wallet_name>`                              |
| OZ upgrade validation error     | Run `forge clean && forge build` in loan-provider/               |
| PostDeployChecks FAILED         | Check console output for `[FAIL]` — likely proxy/role mismatch   |

### Bitmor-Specific Test Notes

The lending-pool has modified Aave V2 behavior:

1. **Vault-only deposits**: Direct `pool.deposit()` calls fail with Error 85. Use vault contracts or `depositViaVault()` helper.

2. **Flash loans disabled**: Flash loan functions revert with Error 86.

3. **Liquidation types**: Use `checkTypeOfLiquidation()` to determine if micro (2), full (1), or no (0) liquidation applies.

---

## Key Addresses (Base Sepolia)

| Contract                | Address                                      |
| ----------------------- | -------------------------------------------- |
| Aave V3 Pool            | `0xcFc53C27C1b813066F22D2fa70C3D0b4CAa70b7B` |
| Aave Addresses Provider | `0x39Eb7Ca3b8f0F29C21a008b1F281b30c4539736a` |

See `deployed-contracts.json` for full address list.
