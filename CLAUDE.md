# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Bitmor is a BTC-collateralized lending protocol built on Aave V2. The repository has two main modules:

- **`lending-pool/`**: Aave V2-based lending pool (Hardhat + TypeScript)
- **`loan-provider/`**: BTC loan system using flash loans and per-user vaults (Foundry + Solidity)

Users deposit USDC, flash loan additional USDC from Aave V3, swap to cbBTC as collateral, deposit into the Bitmor Lending Pool, and repay monthly.

## Commands

### lending-pool/ (Hardhat)

```bash
cd lending-pool

# Build
npm run compile

# Test
npm test                    # Aave tests
npm run test-bitmor         # Bitmor-specific tests
npm run test-scenarios      # Protocol scenario tests

# Deploy to Base Sepolia
npm run aave:baseSepolia:full:migration

# Format
npm run prettier:write
```

### loan-provider/ (Foundry)

```bash
cd loan-provider

# Build
forge build

# Test
make test                    # Unit tests (default, no RPC needed)
make test:unit               # Unit tests with mocks
make test:fork               # Fork tests (requires BASE_SEPOLIA_RPC_URL)
make test:loan:unit          # Loan contract unit tests
make test:vault:unit         # Vault unit tests
make test:liquidation:unit   # Liquidation unit tests
make test:single TEST=test_functionName  # Single test by name

# Deploy full system to Base Sepolia
make setup

# Individual deployments
make deployLoan
make deployLoanVault
make deployLoanVaultFactory
make deploySwapAdapterWrapper

# Post-deployment
make setLoanVaultFactory
make setBitmorLoan
make verifyAll

# Coverage & gas
make coverage
make gasReport
```

### Local Development (Root)

```bash
# Start local Anvil node
make anvil

# Deploy full system to local Anvil (run in separate terminal)
make deploy-local

# Verify deployment
cat loan-provider/deployments.json | jq '.deployments["31337"].networkConfig'
```

The local deployment runs an optimized multi-phase orchestration:

```
make deploy-local (FOUNDRY_PROFILE=local)
├── Phase 1: DeployPhase1.s.sol
│   └── AccessManager → MockTokens → MockOracles → BTCVault → save JSON
├── Phase 2: lending-pool
│   └── npm run bitmor:localhost:dev:migration
├── Phase 3a: DeployPhase3.s.sol
│   └── USDCVault → SwapAdapter → Loan → Strategies → roles → save JSON
├── Phase 3b: SchedulePhase3.s.sol
│   └── Schedule timelocked operations (1-day delay + 10min buffer)
├── Time advance: 87001 seconds (1 day + 10 min + 1 sec)
└── Phase 3c: ExecutePhase3.s.sol
    └── Execute scheduled operations via AccessManager
```

**Note**: The schedule/execute pattern uses OpenZeppelin's AccessManager with 1-day execution delays for role-protected functions. The `SCHEDULE_BUFFER` (10 minutes) compensates for timestamp drift between Foundry simulation and broadcast.

## Architecture

### Loan Flow (loan-provider/)

1. User calls `initializeLoan(deposit, premium, collateral, duration, data)`
2. `Loan.sol` takes flash loan from Aave V3
3. Flash loan callback swaps USDC → cbBTC via Uniswap V4
4. cbBTC deposited to Bitmor Lending Pool, creating aToken position in user's `LoanVault` (LSA)
5. Flash loan repaid from user's deposit
6. User repays monthly; on completion, collateral returned

### Core Contracts (loan-provider/src/)

**Protocol Layer**:
- `protocol/Loan.sol` - Main entry point for loan lifecycle
- `protocol/LoanVault.sol` - Per-loan smart account (LSA) holding Aave position
- `protocol/LoanVaultFactory.sol` - Minimal proxy factory for deterministic LSA deployment
- `protocol/AutoRepayment.sol` - Scheduled repayment automation

**Logic Libraries** (`libraries/logic/`):
- `LoanLogic.sol` - Loan initialization and calculations
- `RepayLogic.sol` - Repayment execution
- `CloseLoanLogic.sol` - Loan closure/settlement
- `FlashLoanLogic.sol` - Flash loan callback handling
- `SwapLogic.sol` - Token swap execution

**Vault System** (`vaults/`):
- `btc-vault/BTCVault.sol` - ERC-4626 vault with multi-strategy support
- `btc-vault/TokenizedStrategy/` - Strategy implementations (Aave, Simple)
- `usdc-vault/USDCVault.sol` - USDC vault implementation

**Adapters**:
- `adapters/UniswapV4SwapAdapterWrapper.sol` - Uniswap V4 integration

### Lending Pool (lending-pool/contracts/)

Standard Aave V2 structure:
- `protocol/` - Core lending protocol (LendingPool, LendingPoolCore)
- `interfaces/` - Contract interfaces
- `flashloan/` - Flash loan implementations
- `adapters/` - Swap and flash loan adapters
- `mocks/` - Test utilities

### External Dependencies

- **Aave V3**: Flash loans for loan initialization
- **Bitmor Lending Pool**: Stores collateral, issues aTokens/debt tokens
- **Uniswap V4**: Token swaps
- **Chainlink**: Price feeds via `IPriceOracleGetter`

### Script Architecture (loan-provider/script/)

**HelperConfig.s.sol** is the single source of truth for deployment configuration:
- Network config and chain ID constants (`CHAIN_ID_LOCAL`, `CHAIN_ID_BASE_SEPOLIA`, `CHAIN_ID_BASE_MAINNET`)
- `_readDeployment(key)` - Chain-aware JSON reading from `deployments.json` (replaced DevOpsTools)
- **Type A getters** (read from JSON): `getAccessManager()`, `getLoan()`, `getBTCVault()`, `getUSDCVault()`, `getLoanVaultFactory()`, `getAaveTokenizedStrategy()`, `getUSDCStrategy()`, `getSwapAdapterWrapper()`
- **Type B getters** (mainnet constants): `getAaveV3Pool()`, `getAaveAddressesProvider()` - return constants only for mainnet
- **Type C getters** (lending pool): `getBitmorPool()`, `getOracle()` - read from `deployed-contracts.json`
- Token getters: `getCbBTC()`, `getUSDC()` (chain-aware)
- Path helpers: `getDeploymentsJsonPath()`, `getLendingPoolDeploymentsPath()`

**DeploymentHelper.s.sol** provides utilities:
- `readLendingPoolAddress()` - Delegates to HelperConfig
- `warpTime()` / `warpTimeTo()` - Anvil time manipulation
- `isLocalChain()` - Chain detection

**Consolidated Deployment Scripts** (`deployment/`):
- `DeployPhase1.s.sol` - Phase 1: AccessManager, MockTokens, MockOracles, BTCVault
- `DeployPhase3.s.sol` - Phase 3a: USDCVault, SwapAdapter, Loan, Strategies, roles
- `SchedulePhase3.s.sol` - Phase 3b: Schedule timelocked operations
- `ExecutePhase3.s.sol` - Phase 3c: Execute scheduled operations
- `DeploymentConstants.sol` - Shared constants (EXECUTION_DELAY, SCHEDULE_BUFFER)

**AccessManager Setup**:
- `interaction/AccessManager/LocalFullSetup.s.sol` - Full setup with schedule/execute pattern
- `StrategyConfig.s.sol` - Strategy deployment configuration

**Chain Behavior**:
| Chain | Bitmor Contracts | External Protocols | Lending Pool |
|-------|------------------|-------------------|--------------|
| Local (31337) | `deployments.json` | `deployments.json` (mocks) | `deployed-contracts.json` |
| Testnet (84532) | `deployments.json` | `deployments.json` (mocks) | `deployed-contracts.json` |
| Mainnet (8453) | `deployments.json` | Constants | `deployed-contracts.json` |

**JSON Key Mapping** (HelperConfig getter → deployments.json key):
- `getAccessManager()` → `accessManager`
- `getLoan()` → `loan`
- `getBTCVault()` → `collateralAsset`
- `getUSDCVault()` → `usdcVault`
- `getLoanVaultFactory()` → `loanVaultFactory`
- `getSwapAdapterWrapper()` → `swapAdapterWrapper`
- `getCbBTC()` → `cbBTC`
- `getUSDC()` → `debtAsset`

## Testing

### Foundry Tests (loan-provider/)

**Test Modes:**
- **Unit tests**: Run locally with mock infrastructure (no fork required)
- **Fork tests**: Run against Base Sepolia fork for integration testing

Key test files in `test/unit/`:
- `Loan/BaseLoan.t.sol` - Shared test base with helpers and setup
- `Loan/InitializeLoan.t.sol`, `RepayLoan.t.sol`, `CloseLoan.t.sol`
- `MicroLiquidation.t.sol`, `FullLiquidation.t.sol`
- `Vault/BTC/*.t.sol` - BTCVault tests (45 tests, mock-based)
- `Vault/USDC/*.t.sol` - USDCVault tests (21 tests, mock-based)

**Test Base Classes** (`test/base/`):
- `BitmorTestBase.sol` - Core: AccessManager, roles, actors, `_scheduleAndExecute()`
- `UnitTestBase.sol` - Unit tests with mocks, `_fundUSDC()`, `_fundCbBTC()`
- `ForkTestBase.sol` - Fork tests with real Aave V3, `_dealToken()`
- `LoanUnitTestBase.sol` - Loan-specific unit test base with mock infrastructure

**Mock Contracts** (`test/mock/`):
| Mock | Description |
|------|-------------|
| `MockERC20.sol` | Configurable ERC20 with unrestricted mint/burn |
| `MockAToken.sol` | Pool-restricted aToken with underlying asset approval |
| `MockVariableDebtToken.sol` | Pool-restricted variable debt token |
| `MockAaveV3Pool.sol` | Flash loans + lending functions (supply, withdraw, getReserveAToken) |
| `MockBitmorLendingPool.sol` | Full lending pool mock with liquidation logic |
| `MockAddressesProvider.sol` | Addresses provider for oracle and pool |
| `MockPriceOracle.sol` | Configurable price oracle |
| `MockSwapAdapter.sol` | Mock swap adapter with configurable rates |
| `MockInterestRateStrategy.sol` | Fixed interest rate strategy |
| `MockChainlinkOracle.sol` | Chainlink AggregatorV3Interface mock |

Helpful make targets:
```bash
make test                    # Unit tests (default, no RPC needed)
make test:unit               # All unit tests with mock infrastructure
make test:fork               # Fork tests with real protocols
make test:loan:unit          # Loan contract unit tests
make test:vault:unit         # Vault unit tests
make test:liquidation:unit   # Liquidation unit tests
make test:single TEST=test_initializeLoan  # Single test by name
```

### Hardhat Tests (lending-pool/)

Tests in `test-suites/` organized by protocol area:
- `test-aave/` - Core Aave tests
- `test-amm/` - AMM tests
- `test-bitmor/` - Bitmor-specific tests

Fork testing: Set `FORK=main` environment variable.

## Configuration

### Environment Variables

**lending-pool/.env**:
```
MNEMONIC=""
ALCHEMY_KEY=""
ETHERSCAN_KEY=""
```

**loan-provider/.env**:
```
BASE_SEPOLIA_RPC_URL=""
ETHERSCAN_KEY=""
```

### Wallet Setup (loan-provider/)

Tests and deployments require two cast wallets:
- `bitmor_owner`: Admin/deployer account
- `bitmor_user`: Test user account

### Import Aliases (loan-provider/)

```
@bitmor/=src/
@openzeppelin/=lib/openzeppelin-contracts/contracts/
@solady/=lib/solady/src/
@btcVault/=src/vaults/btc-vault/
@usdcVault/=src/vaults/usdc-vault/
```

### Key Addresses (Base Sepolia)

Deployed addresses are in:
- `loan-provider/deployments.json`
- `lending-pool/deployed-contracts.json`

Aave V3 Pool: `0xcFc53C27C1b813066F22D2fa70C3D0b4CAa70b7B`

## Security Analysis

```bash
cd loan-provider
FOUNDRY_PROFILE=security forge build
```

## Working with Both Systems

1. **Lending pool changes**: Work in `lending-pool/` with Hardhat
2. **Loan system changes**: Work in `loan-provider/` with Foundry
3. **Full deployment**: Deploy lending pool first, then loan system
4. **Integration**: Loan system reads Bitmor addresses from `../lending-pool/deployed-contracts.json`
5. **Local development**: Use `make anvil` + `make deploy-local` for full local testing

## Role Configuration (AccessManager)

### Operational Roles
| Role     | ID  | Target        | Grantee                      |
|----------|-----|---------------|------------------------------|
| ADMIN    | 0   | -             | admin EOA                    |
| EXECUTOR | 1   | Loan          | admin EOA                    |
| LPCM     | 2   | Loan          | LendingPoolCollateralManager |
| LPM_FAST | 3   | Loan          | admin EOA                    |
| LPM_SLOW | 30  | Loan          | admin EOA (1-day delay)      |
| BVC      | 12  | BTCVault      | admin EOA (1-day delay)      |
| BVD      | 14  | BTCVault      | Loan contract                |
| UVC      | 22  | USDCVault     | admin EOA (1-day delay)      |

### Guardian Roles
Guardian roles can cancel delayed operations for their protected roles:
- `GUARDIAN_LPM_SLOW` (930) → protects LPM_SLOW
- `GUARDIAN_BVC` (912) → protects BVC
- `GUARDIAN_UVC` (922) → protects UVC

**Role definitions**: `loan-provider/src/accessManager/RolesData.sol`

## Key Files Reference

| Category                  | File                                                                  |
|---------------------------|-----------------------------------------------------------------------|
| **Configuration**         |                                                                       |
| Network config            | `loan-provider/script/HelperConfig.s.sol`                             |
| Deployment helper         | `loan-provider/script/helpers/DeploymentHelper.s.sol`                 |
| Strategy config           | `loan-provider/script/StrategyConfig.s.sol`                           |
| Deployment constants      | `loan-provider/script/deployment/DeploymentConstants.sol`             |
| **Deployment Scripts**    |                                                                       |
| Phase 1 (consolidated)    | `loan-provider/script/deployment/DeployPhase1.s.sol`                  |
| Phase 3a (deploy)         | `loan-provider/script/deployment/DeployPhase3.s.sol`                  |
| Phase 3b (schedule)       | `loan-provider/script/deployment/SchedulePhase3.s.sol`                |
| Phase 3c (execute)        | `loan-provider/script/deployment/ExecutePhase3.s.sol`                 |
| Orchestrator              | `deploy/scripts/deploy-local.sh`                                      |
| **AccessManager**         |                                                                       |
| Role definitions          | `loan-provider/src/accessManager/RolesData.sol`                       |
| AccessManager contract    | `loan-provider/src/accessManager/BitmorAccessManager.sol`             |
| Local setup               | `loan-provider/script/interaction/AccessManager/LocalFullSetup.s.sol` |
| **Addresses**             |                                                                       |
| loan-provider addresses   | `loan-provider/deployments.json`                                      |
| lending-pool addresses    | `lending-pool/deployed-contracts.json`                                |

## Documentation

- **Deployment guide**: `DEPLOYMENT_SETUP.md` - Comprehensive deployment instructions
- **Session plans**: `docs/plans/SESSION_CONTINUATION.md` - Tracks implementation progress and completed work
- **Implementation plans**: `docs/plans/` - Detailed architecture and design decisions
- **Test setup plan**: `docs/plans/2026-01-23-test-setup-fixes.md` - Current test infrastructure migration

## Recent Production Fixes

### USDCStrategy.withdraw() Bug (2026-01-23)

**Location:** `loan-provider/src/vaults/usdc-vault/USDCStrategy.sol:178-182`

**Issue:** The `withdraw()` function called `_withdrawFunds(amount)` which withdrew assets to the strategy contract, but never transferred them to the vault. This caused vault's `maxWithdraw()` to return 0.

**Fix:** Added `i_asset.safeTransfer(msg.sender, amount)` after `_withdrawFunds()` to transfer assets to the vault.

```solidity
function withdraw(uint256 amount) external onlyVault {
    _withdrawFunds(amount);
    // Transfer withdrawn assets to vault (msg.sender)
    i_asset.safeTransfer(msg.sender, amount);
}
```
