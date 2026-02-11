# Bitmor Protocol

Get your first whole 1 BTC with an undercollateralised loan.


## Repo Setup

This repo have two projects initialized:
1. Lending Pool: A fork of Aave v2 with Hardhat v3 (previously was Hardhat v2).
2. Loan Provider: A foundry setup for other protocol components: Loan Provider, Vaults and Access Manager.


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
├── lending-pool/          # Aave V2 fork (Hardhat + TypeScript)
│   ├── contracts/         # Solidity contracts
│   ├── test-suites/       # Test suites
│   └── helpers/           # Deployment helpers
│
└── loan-provider/         # BTC loan system (Foundry + Solidity)
    ├── src/               # Source contracts
    ├── test/              # Foundry tests
    └── script/            # Deployment scripts
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
make test        # Run unit tests (no RPC needed)
make test:all    # Run all tests
```

See [TEST.md](./TEST.md) for complete testing documentation.

---

## Local Development

### Running Local Anvil Node

```bash
# From repository root
cd loan-provider
make anvil
```

This starts a local Ethereum node on `http://localhost:8545`.

### Full Local Deployment

In a separate terminal:
```bash
make deploy-local
```

This runs a multi-phase deployment:
1. **Phase 1**: AccessManager, MockTokens, MockOracles, BTCVault
2. **Phase 2**: lending-pool migration
3. **Phase 3a**: USDCVault, SwapAdapter, Loan, Strategies
4. **Phase 3b**: Schedule timelocked operations
5. **Phase 3c**: Execute scheduled operations

### Verify Local Deployment

```bash
cat loan-provider/deployments.json | jq '.deployments["31337"].networkConfig'
```

---

## Markets configuration

The configurations related with the Aave Markets are located at `markets` directory. You can follow the `IAaveConfiguration` interface to create new Markets configuration or extend the current Aave configuration.

Each market should have his own Market configuration file, and their own set of deployment tasks, using the Aave market config and tasks as a reference.

## Deployments

For deploying the Bitmor protocol, use the scripts in `package.json` for lending-pool and `Makefile` for loan-provider.

### lending-pool Deployments

| Command                                   | Description                  |
| ----------------------------------------- | ---------------------------- |
| `npm run aave:baseSepolia:full:migration` | Deploy to Base Sepolia       |
| `npm run bitmor:localhost:dev:migration`  | Deploy to local Hardhat node |
| `npm run aave:fork:main`                  | Deploy to mainnet fork       |

#### Base Sepolia Deployment

```bash
# With Docker
docker-compose up
docker-compose exec contracts-env bash
npm run aave:baseSepolia:full:migration

# Without Docker
npm run aave:baseSepolia:full:migration
```

#### Local Development Deployment

```bash
npm run bitmor:localhost:dev:migration
```

### loan-provider Deployments

| Command                         | Description                                     |
| ------------------------------- | ----------------------------------------------- |
| `make setup`                    | Full deployment (all contracts + configuration) |
| `make deployLoan`               | Deploy Loan contract                            |
| `make deployLoanVault`          | Deploy LoanVault implementation                 |
| `make deployLoanVaultFactory`   | Deploy vault factory                            |
| `make deploySwapAdapterWrapper` | Deploy Uniswap V4 swap adapter                  |

#### Full Setup (Base Sepolia)

```bash
cd loan-provider
make setup
```

#### Individual Deployments

```bash
# Deploy core contracts
make deployLoan
make deployLoanVault
make deployLoanVaultFactory

# Post-deployment configuration
make setLoanVaultFactory    # Link factory to Loan
make setBitmorLoan          # Register Loan in AddressesProvider
make saveAddresses          # Persist deployment addresses

# Verification
make verifyAll              # Verify on Sourcify
```

### Deployment Addresses

Deployed addresses are stored in:
- `lending-pool/deployed-contracts.json` - lending-pool addresses
- `loan-provider/deployments.json` - loan-provider addresses

---

## Console Interaction

### Mainnet Fork Console

Deploy and interact with the protocol in a forked mainnet:

```bash
docker-compose run contracts-env npm run console:fork
```

```javascript
// Deploy the Aave protocol in fork mode
await run('aave:mainnet')

// Initialize HRE
run('set-DRE');

// Import contract getters
const contractGetters = require('./helpers/contracts-getters');

// Get LendingPool instance
const lendingPool = await contractGetters.getLendingPool("LendingPool address");

// Impersonate an address
await network.provider.request({
  method: "hardhat_impersonateAccount",
  params: ["0xb1adceddb2941033a090dd166a462fe1c2029484"]
});

const signer = await ethers.provider.getSigner("0xb1adceddb2941033a090dd166a462fe1c2029484")

// Interact with tokens
const DAI = await contractGetters.getIErc20Detailed("0x6B175474E89094C44Da98b954EedeAC495271d0F");
await DAI.connect(signer).approve(lendingPool.address, ethers.utils.parseUnits('100'));
await lendingPool.connect(signer).deposit(DAI.address, ethers.utils.parseUnits('100'), await signer.getAddress(), '0');
```

### Mainnet Console

Interact with deployed Aave contracts on mainnet:

```bash
docker-compose run contracts-env npx hardhat --network main console
```

```javascript
run("set-DRE")

const contractGetters = require('./helpers/contracts-getters');
const signer = await contractGetters.getFirstSigner();

// Use deployed LendingPool address
const lendingPool = await contractGetters.getLendingPool("0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9");

const DAI = await contractGetters.getIErc20Detailed("0x6B175474E89094C44Da98b954EedeAC495271d0F");
await DAI.connect(signer).approve(lendingPool.address, ethers.utils.parseUnits('100'));
await lendingPool.connect(signer).deposit(DAI.address, ethers.utils.parseUnits('100'), await signer.getAddress(), '0');
```

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
