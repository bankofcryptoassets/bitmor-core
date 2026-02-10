# Test Documentation

Testing commands for the Bitmor Protocol. The project has two modules:
- **loan-provider/** - Foundry-based loan system
- **lending-pool/** - Hardhat-based Aave V2 fork

---

## Quick Start

New to the project? Run these from the repository root:

```bash
# Run unit tests (no RPC needed)
make test

# Run all tests (unit + lending-pool)
make test:all
```

---

## Development Workflow

### Unit Tests (loan-provider)

Unit tests use mock contracts and require no external RPC connection.

```bash
# All unit tests
make test:unit

# Domain-specific tests
make test:loan:unit           # Loan contract tests
make test:vault:unit          # BTCVault and USDCVault tests
make test:liquidation:unit    # Micro and full liquidation tests
```

### Integration Tests (loan-provider)

Integration tests run against real deployed contracts on a local Anvil node. They require a running Anvil instance with the full system deployed.

**Prerequisites:**

```bash
# Terminal 1: Start Anvil
make anvil

# Terminal 2: Deploy the full system
make deploy-local
```

**Run all integration tests:**

```bash
make test:integration
```

**Run a single test file:**

```bash
cd loan-provider

# SetUpState tests
FOUNDRY_PROFILE=integration forge test --match-path "test/integration/SetUpState.t.sol" --fork-url http://127.0.0.1:8545 -vvv

# Liquidation tests
FOUNDRY_PROFILE=integration forge test --match-path "test/integration/Liquidation.t.sol" --fork-url http://127.0.0.1:8545 -vvv

# AccessControl tests
FOUNDRY_PROFILE=integration forge test --match-path "test/integration/AccessControl.t.sol" --fork-url http://127.0.0.1:8545 -vvv

# VaultStrategy tests
FOUNDRY_PROFILE=integration forge test --match-path "test/integration/VaultStrategy.t.sol" --fork-url http://127.0.0.1:8545 -vvv

# LoanLifecycle tests
FOUNDRY_PROFILE=integration forge test --match-path "test/integration/LoanLifecycle.t.sol" --fork-url http://127.0.0.1:8545 -vvv
```

**Run a single test function:**

```bash
cd loan-provider
FOUNDRY_PROFILE=integration forge test --match-test test_FullLiquidation_ExecuteViaLendingPool --fork-url http://127.0.0.1:8545 -vvvv
```

### Fork Tests (loan-provider)

Fork tests run against Base Sepolia and require `BASE_SEPOLIA_RPC_URL` in your environment.

```bash
# Run fork tests
make test:fork
```

### Lending Pool Tests (Hardhat)

```bash
# Bitmor-specific tests (liquidation mechanics)
make test:lp

# Core Aave V2 tests
make test:lp:aave

# Protocol scenario tests
make test:lp:scenarios
```

### Single Test Debugging

From the repository root:
```bash
# Run single test by function name
make test:single TEST=test_initializeLoan_success

# Run all tests for a specific contract
make test:contract CONTRACT=InitializeLoan
```

Or directly from `loan-provider/`:
```bash
cd loan-provider

# Run with verbose output
forge test --match-test test_initializeLoan_success -vvvv

# Run tests for specific file
FOUNDRY_PROFILE=unit forge test --match-path "test/unit/Loan/InitializeLoan.t.sol" -vvv
```

---

## CI / Full Verification

```bash
# Run all tests
make test:all

# Generate coverage report (requires fork)
cd loan-provider && make coverage

# Generate gas report (requires fork)
cd loan-provider && make gas-report
```

---

## Test Structure Overview

### loan-provider/test/

```
test/
├── base/                        # Test base contracts
│   ├── BitmorTestBase.sol       # Core: AccessManager, roles, actors
│   ├── UnitTestBase.sol         # Unit tests with mocks
│   ├── ForkTestBase.sol         # Fork tests with real protocols
│   ├── LoanUnitTestBase.sol     # Loan-specific unit test base
│   └── IntegrationTestBase.sol  # Integration tests with pre-deployed contracts
│
├── mock/                        # Mock contracts
│   ├── MockBitmorLendingPool.sol
│   ├── MockAaveV3Pool.sol
│   ├── MockPriceOracle.sol
│   ├── MockSwapAdapter.sol
│   ├── MockAToken.sol
│   ├── MockVariableDebtToken.sol
│   └── MockERC20.sol
│
├── helpers/
│   └── TestConstants.sol        # Shared test constants
│
├── integration/                 # Integration tests (require Anvil + deploy-local)
│   ├── SetUpState.t.sol         # Deployment validation (15 tests)
│   ├── AccessControl.t.sol      # Role-path coverage (25 tests)
│   ├── Liquidation.t.sol        # Real liquidation execution (10 tests)
│   ├── LoanLifecycle.t.sol      # Init, repay, close flows (10 tests)
│   └── VaultStrategy.t.sol      # Vault deposit and strategy tests (7 tests)
│
└── unit/                        # Unit test files
    ├── Loan/
    │   ├── BaseLoan.t.sol       # Shared loan test helpers
    │   ├── InitializeLoan.t.sol
    │   ├── RepayLoan.t.sol
    │   ├── CloseLoan.t.sol
    │   └── LoanContract.t.sol
    ├── MicroLiquidation.t.sol
    ├── FullLiquidation.t.sol
    ├── Vault/
    │   ├── BTC/                 # BTCVault tests
    │   └── USDC/                # USDCVault tests
    └── ...
```

### lending-pool/test-suites/

```
test-suites/
├── test-aave/                   # Core Aave V2 tests
│   ├── __setup.spec.ts          # Test setup
│   ├── flashloan.spec.ts
│   ├── liquidation-*.spec.ts
│   ├── scenario.spec.ts
│   └── helpers/
│       ├── make-suite.ts
│       └── scenario-engine.ts
│
├── test-bitmor/                 # Bitmor-specific tests
│   ├── __setup.spec.ts
│   └── helpers/
│       └── make-suite.ts
│
└── test-amm/                    # AMM tests
```

---

## Troubleshooting

### "Contract not compiled" errors (lending-pool)

Always compile before running tests:
```bash
cd lending-pool
npm run compile
npm run test-bitmor
```

### Fork tests failing with RPC errors

Ensure `BASE_SEPOLIA_RPC_URL` is set:
```bash
export BASE_SEPOLIA_RPC_URL="https://base-sepolia.g.alchemy.com/v2/YOUR_KEY"
make test:fork
```

### Test hanging or timing out

For fork tests, the deployment block is read from `deployments.json`. If the file is missing or outdated:
```bash
cd loan-provider
BLOCK_NUMBER=latest make test:fork
```

### Stack too deep errors

Use the security profile for analysis builds:
```bash
cd loan-provider
FOUNDRY_PROFILE=security forge build
```

### "Caller not authorized" in tests

Ensure roles are granted before calling restricted functions. See `test/base/BitmorTestBase.sol` for the `_scheduleAndExecute()` helper.

---

## Foundry Profiles

The loan-provider uses different profiles for different test types:

| Profile | Use Case |
|---------|----------|
| `unit` | Unit tests with mocks (default for `make test`) |
| `integration` | Integration tests against local Anvil (`make test:integration`) |
| `fork` | Fork tests against Base Sepolia |
| `security` | Analysis builds with extra checks |
| `local` | Local Anvil deployments |

Example:
```bash
FOUNDRY_PROFILE=unit forge test --match-path "test/unit/**/*.sol"
```

---

## Additional Resources

- **CLAUDE.md** - Codebase overview and architecture
- **DEPLOYMENT_SETUP.md** - Deployment instructions
- **docs/plans/** - Implementation plans and session notes
