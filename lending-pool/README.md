# Bitmor Lending Pool

This repository contains the smart contracts for Bitmor Lending Pool. This repo is a fork of Aave V2, with a custom liquidation mechanism introducing `microLiquidationCall` and custom health-factor management depending on the type of **Loan** user took, i.e., insured or uninsured loan.

The repository uses Docker Compose and Hardhat as development enviroment for compilation, testing and deployment tasks.

## New Features with respect to AAVE V2

### Micro Liquidation Call

When a liquidator initializes a `microLiquidationCall`, if the checks passes, then its sell user's collateral just enough to get them again in the good health factor and to pay the liquidation bonus. The doesn't liquidates user's complete position and maintain healthy protocol economics.

### Full Liquidation Call

When a liquidator intializes a `liquidationCall`, if the check passess, then its does the liquidation same as how it works in AAVE v2. The primary change is in the checks which contains `isInsured` params, if `true`, then full liquidation will be disabled to prevent user from being liquidated due to price drop.

### Check Type of Liquidation

Both liquidation calls, needs to call `checkTypeOfLiquidation` which returns a `unit256`.
If return value:
  - 0: No Liquidation
  - 1: Full Liquidation
  - 2: Micro Liquidaion

This function checks the following conditions of a particular user and based on that returns. The following is the flow diagram for finalizing type of liquidation:
![](./diagrams/checkTypeOfLiquidation.png)

---

## Prerequisites

Before setting up the project, ensure you have the following installed:

| Tool | Version | Purpose |
|------|---------|---------|
| Node.js | v18+ | lending-pool (Hardhat) |
| npm | v9+ | Package management |
| Docker | Latest | Container environment |
| docker-compose | Latest | Multi-container orchestration |
| Foundry | Latest | loan-provider (Forge/Cast/Anvil) |
| Git | Latest | Version control |

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

### Quick Start (lending-pool)

```bash
cd lending-pool
npm install
npm run compile
npm test
```

### Quick Start (loan-provider)

```bash
cd loan-provider
forge install
forge build
forge test --fork-url $BASE_SEPOLIA_RPC_URL
```

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

## Test Commands

### lending-pool Tests

| Command | Description |
|---------|-------------|
| `npm test` | Run core Aave tests |
| `npm run test-bitmor` | Run Bitmor-specific tests (liquidation, vault integration) |
| `npm run test-scenarios` | Run protocol scenario tests |
| `npm run test-amm` | Run AMM tests |

#### Running All Tests

```bash
# With Docker
docker-compose up
docker-compose exec contracts-env bash
npm test

# Without Docker
cd lending-pool
npm run compile
npm test
```

#### Running Specific Test Files

```bash
# Compile first (required)
npm run compile

# Run specific test file
TS_NODE_TRANSPILE_ONLY=1 npx hardhat test ./test-suites/test-bitmor/__setup.spec.ts

# Run Bitmor sample tests
TS_NODE_TRANSPILE_ONLY=1 npx hardhat test ./test-suites/test-aave/bitmor-sample.spec.ts
```

#### Fork Testing

```bash
# Run tests against mainnet fork
FORK=main npm test

# Run scenario tests with fork
FORK=main npm run test-scenarios
```

### loan-provider Tests

| Command | Description |
|---------|-------------|
| `forge test` | Run all tests (requires fork) |
| `make test` | Run all tests via Makefile |
| `make test-unit-profile` | Run unit tests with mock infrastructure |
| `make test-fork-profile` | Run fork tests with real protocols |

#### Running All Tests

```bash
cd loan-provider

# Using make (recommended)
make test

# Using forge directly
forge test --fork-url $BASE_SEPOLIA_RPC_URL
```

#### Running Specific Tests

```bash
# Run by test name pattern
forge test --mt test_initializeLoan --fork-url $BASE_SEPOLIA_RPC_URL -vvvv

# Run by contract name
forge test --mc InitializeLoan --fork-url $BASE_SEPOLIA_RPC_URL -vv

# Run specific test file
forge test --match-path test/unit/Loan/InitializeLoan.t.sol --fork-url $BASE_SEPOLIA_RPC_URL
```

#### Test Verbosity Levels

```bash
-v     # Show test names
-vv    # Show logs
-vvv   # Show traces for failing tests
-vvvv  # Show traces for all tests
-vvvvv # Show full traces with setup
```

#### Coverage and Gas Reports

```bash
# Generate coverage report
make coverage

# Generate gas report
make gasReport
```

---

## Test Suites Overview

### lending-pool Test Structure

```
test-suites/
├── test-aave/              # Core Aave V2 tests
│   ├── __setup.spec.ts     # Test environment setup
│   ├── scenario.spec.ts    # Protocol scenarios
│   ├── bitmor-sample.spec.ts # Bitmor integration tests
│   └── helpers/
│       ├── make-suite.ts   # Test fixtures and setup
│       ├── deploy-bitmor-mocks.ts # Mock deployments
│       └── vault-helpers.ts # Vault deposit helpers
│
├── test-bitmor/            # Bitmor-specific tests
│   ├── __setup.spec.ts     # Bitmor setup
│   └── liquidation.spec.ts # Liquidation tests
│
└── test-amm/               # AMM tests
```

### loan-provider Test Structure

```
test/
├── unit/
│   ├── Loan/
│   │   ├── BaseLoan.t.sol        # Shared test base
│   │   ├── InitializeLoan.t.sol  # Loan creation (12 tests)
│   │   ├── RepayLoan.t.sol       # Repayment (17 tests)
│   │   ├── CloseLoan.t.sol       # Loan closure (16 tests)
│   │   └── LoanContract.t.sol    # Core functionality (10 tests)
│   │
│   ├── MicroLiquidation.t.sol    # Micro liquidation (12 tests)
│   ├── FullLiquidation.t.sol     # Full liquidation (13 tests)
│   │
│   └── Vault/
│       ├── BTC/                   # BTCVault tests (45 tests)
│       └── USDC/                  # USDCVault tests (21 tests)
│
├── mock/                          # Mock contracts
│   ├── MockBitmorLendingPool.sol
│   ├── MockPriceOracle.sol
│   ├── MockAaveV3Pool.sol
│   └── ...
│
└── base/                          # Test base classes
    ├── BitmorTestBase.sol
    ├── UnitTestBase.sol
    └── ForkTestBase.sol
```

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

| Command | Description |
|---------|-------------|
| `npm run aave:baseSepolia:full:migration` | Deploy to Base Sepolia |
| `npm run bitmor:localhost:dev:migration` | Deploy to local Hardhat node |
| `npm run aave:fork:main` | Deploy to mainnet fork |

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

| Command | Description |
|---------|-------------|
| `make setup` | Full deployment (all contracts + configuration) |
| `make deployLoan` | Deploy Loan contract |
| `make deployLoanVault` | Deploy LoanVault implementation |
| `make deployLoanVaultFactory` | Deploy vault factory |
| `make deploySwapAdapterWrapper` | Deploy Uniswap V4 swap adapter |

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

| Issue | Solution |
|-------|----------|
| `HardhatError: HHE1000` - Artifact not found | Run `npm run compile` before tests |
| Tests hang on Docker | Ensure Docker has sufficient memory (4GB+) |
| TypeScript errors | Run `npm run compile` to regenerate types |
| `Error 85: LP_CALLER_NOT_VAULT` | Bitmor requires vault-mediated deposits; use `depositViaVault()` helper |

#### loan-provider

| Issue | Solution |
|-------|----------|
| `forge test` fails without fork | Add `--fork-url $BASE_SEPOLIA_RPC_URL` |
| Missing submodules | Run `forge install` or `git submodule update --init --recursive` |
| `Stack too deep` errors | Use `--via-ir` flag or refactor code |
| Cast wallet not found | Run `cast wallet new <wallet_name>` |

### Bitmor-Specific Test Notes

The lending-pool has modified Aave V2 behavior:

1. **Vault-only deposits**: Direct `pool.deposit()` calls fail with Error 85. Use vault contracts or `depositViaVault()` helper.

2. **Flash loans disabled**: Flash loan functions revert with Error 86.

3. **Liquidation types**: Use `checkTypeOfLiquidation()` to determine if micro (2), full (1), or no (0) liquidation applies.

---

## Key Addresses (Base Sepolia)

| Contract | Address |
|----------|---------|
| Aave V3 Pool | `0xcFc53C27C1b813066F22D2fa70C3D0b4CAa70b7B` |
| Aave Addresses Provider | `0x39Eb7Ca3b8f0F29C21a008b1F281b30c4539736a` |

See `deployed-contracts.json` for full address list.
