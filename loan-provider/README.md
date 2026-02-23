# Loan Provider

BTC-collateralized loan system built on Aave V3 flash loans and the Bitmor Lending Pool. Users deposit USDC as a down payment, flash loan additional USDC, swap to cbBTC collateral, and repay monthly.

## Setup

### Prerequisites

- [Foundry](https://getfoundry.sh) (forge, cast, anvil)
- Two cast wallets: `bitmor_owner` (admin/deployer) and `bitmor_user` (test user)

```bash
cast wallet new bitmor_owner
cast wallet new bitmor_user
```

### Install

```bash
forge install
```

### Environment

Create `loan-provider/.env` from `.env.example`:

```
BASE_SEPOLIA_RPC_URL=""
ETHERSCAN_KEY=""
```

## Testing

```bash
# Unit tests (no RPC needed — mock infrastructure)
make test

# Domain-specific unit tests
make test:loan:unit          # Loan contract tests
make test:vault:unit         # Vault tests
make test:strategy:unit      # Strategy tests
make test:liquidation:unit   # Liquidation tests

# Fork tests (requires BASE_SEPOLIA_RPC_URL)
make test:fork

# Fuzz tests (10,000 runs)
make test:fuzz

# Invariant tests (10,000 runs, depth 50)
make test:invariant

# Integration tests (requires running Anvil + make deploy-local from repo root)
make test:integration

# Single test debugging
make test:single TEST=test_functionName
make test:contract CONTRACT=ContractName
```

## Build

```bash
forge build
make coverage        # Coverage report
make gas-report      # Gas report
```

## Deployment (Base Sepolia)

```bash
make setup           # Full deployment: all contracts + configuration
make verifyAll       # Verify contracts on Sourcify
```

See the root `CLAUDE.md` for full deployment and architecture documentation.
