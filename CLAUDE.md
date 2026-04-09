# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Bitmor is a BTC-collateralized lending protocol built on Aave V2. The repository has three modules:

- **`lending-pool/`**: Aave V2-based lending pool (Hardhat + TypeScript, Solidity 0.6.12)
- **`loan-provider/`**: BTC loan system using flash loans and per-user vaults (Foundry + Solidity 0.8.30)
- **`swap-routers/`**: Uniswap V4 swap router integration (Foundry)

Users deposit USDC, flash loan additional USDC from Aave V3, swap to cbBTC as collateral, deposit into the Bitmor Lending Pool, and repay monthly.

## Skill Overrides

**IMPORTANT: When using `/brainstorming` or `/superpowers:brainstorming`, ALWAYS follow these additional rules:**

1. **Ask these questions first:**
   - "Are we gonna work with parallel agents?"
   - If yes: "Will we use git worktrees?"

2. **After brainstorming:**
   - If user asks to write a plan → use `/superpowers:writing-plans` skill
   - If parallel agents are requested → include `/superpowers:dispatching-parallel-agents` in the plan

## Rules

1. When a new session is started, always use `/superpowers:using-superpowers` skill PROACTIVELY.
2. When ask to AUDIT, always use `/trailofbits` skill PROACTIVELY.

## Commands

### Root Makefile (preferred)

```bash
# Setup
make install                 # Install all deps + configure git hooks
make build                   # Build all contracts (lending-pool + loan-provider + swap-routers)
make clean                   # Clean all build artifacts

# Formatting
make format                  # Format all code (Prettier + Forge)
make format-check            # Check formatting without changes

# Local Development
make anvil                   # Start Anvil (port 8545, chainId 31337)
make anvil-stop              # Stop Anvil
make deploy-local            # Deploy full protocol to Anvil (run in separate terminal after anvil)

# Testing (loan-provider unit)
make test                    # Unit tests (default, no RPC needed)
make test:unit               # Unit tests with mocks
make test:fork               # Fork tests (requires BASE_SEPOLIA_RPC_URL)
make test:loan:unit          # Loan contract unit tests
make test:vault:unit         # Vault unit tests
make test:strategy:unit      # Strategy unit tests
make test:liquidation:unit   # Liquidation unit tests
make test:fuzz               # All fuzz tests (FOUNDRY_PROFILE=fuzz)
make test:invariant          # Invariant tests (FOUNDRY_PROFILE=invariant)

# Testing (loan-provider integration — requires Anvil + deploy-local)
make test:integration              # All integration tests
make test:integration:setup        # Deployment validation
make test:integration:access       # Access control tests
make test:integration:liquidation  # Liquidation execution
make test:integration:lifecycle    # Init, repay, close flows
make test:integration:vault        # Vault/strategy interaction tests
make test:integration:initloan     # All InitLoan adversarial tests

# Testing (lending-pool)
make test:lp                 # Bitmor-specific tests
make test:lp:aave            # Core Aave tests
make test:lp:scenarios       # Protocol scenario tests

# Combined
make test:all                # Unit tests + lending-pool tests
```

### loan-provider/ (Foundry)

```bash
cd loan-provider

# Single test debugging
make test:single TEST=test_functionName        # Single test by name (-vvvv)
make test:contract CONTRACT=ContractName       # All tests in a contract
make test:fuzz:usdcVault                       # USDC vault fuzz tests only
forge test --match-test test_X -vvvv           # Direct forge invocation

# Integration single test
make test:integration:single TEST=test_name
make test:integration:contract CONTRACT=Name

# Coverage & gas
make coverage                # FOUNDRY_PROFILE=coverage forge coverage --ir-minimum
make coverage-lcov           # Generate lcov report
make coverage-html           # Generate HTML coverage report
make gas-report
```

### lending-pool/ (Hardhat)

```bash
cd lending-pool
npm run compile              # Build
npm test                     # Aave tests
npm run test-bitmor          # Bitmor-specific tests
npm run test-scenarios       # Protocol scenario tests
npm run aave:baseSepolia:full:migration  # Deploy to Base Sepolia
npm run prettier:write       # Format
```

### Local Deployment Flow

```
make deploy-local (FOUNDRY_PROFILE=local)
├── Phase 1: DeployPhase1Local.s.sol → bitmor-deploy save
│   └── AccessManager → MockTokens → MockOracles → BTCVault (UUPS proxy)
├── Phase 2: lending-pool → bitmor-deploy save-lp
│   └── npm run bitmor:localhost:dev:migration
├── Phase 3: DeployLibraries → bitmor-deploy save → bitmor-deploy libraries
│            DeployPhase3Local.s.sol → bitmor-deploy save
│   └── USDCVault/Loan/AutoRepayment/AddressesProvider (UUPS proxies)
│       → Beacon chain (LoanVault impl → Beacon → Controller → Factory)
│       → Strategies → Wire strategies (as ADMIN) → Oracle reconfig
│       → Role setup + UPGRADER wiring
└── Phase 4: PostDeployChecks.s.sol
    └── Validate proxy pointers, beacon ownership, role wiring
```

**Address registry:** All addresses are saved to `deployments/<chainId>/latest.json` by the `bitmor-deploy` TS CLI (`deploy/tools/`). Forge scripts no longer write JSON directly. Timestamped snapshots are created for each save.

## Architecture

### Loan Flow (loan-provider/)

1. User calls `initializeLoan(deposit, premium, collateral, duration, data)`
2. `Loan.sol` takes flash loan from Aave V3
3. Flash loan callback swaps USDC → cbBTC via Uniswap V4
4. cbBTC deposited to Bitmor Lending Pool, creating aToken position in user's `LoanVault` (LSA)
5. Flash loan repaid from user's deposit
6. User repays monthly; on completion, collateral returned

### Proxy Architecture (loan-provider/)

All core contracts are deployed behind proxies with ERC-7201 namespaced storage:

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

### Core Contracts (loan-provider/src/)

**Protocol Layer**:
- `protocol/Loan.sol` - Main entry point for loan lifecycle (UUPS upgradeable)
- `protocol/LoanVault.sol` - Per-loan smart account (LSA) holding Aave position (BeaconProxy)
- `protocol/LoanVaultFactory.sol` - Factory deploying LoanVaults as BeaconProxies
- `protocol/AutoRepayment.sol` - Scheduled repayment automation (UUPS upgradeable)
- `protocol/BeaconController.sol` - AccessManaged wrapper for beacon upgrades
- `protocol/BitmorAddressesProvider.sol` - Protocol address registry (UUPS upgradeable)
- `protocol/LoanStorage.sol` - ERC-7201 namespaced storage for Loan

**Logic Libraries** (`libraries/logic/`):
- `LoanLogic.sol` - Loan initialization, validation, state updates for liquidations
- `FlashLoanLogic.sol` - Aave V3 flash loan callback handling for init and close flows
- `RepayLogic.sol` - Monthly repayment execution
- `CloseLoanLogic.sol` - Pre-closure flow with flash loan coordination
- `SwapLogic.sol` - Token swaps with slippage protection (zQuoter or oracle-based)
- `LSALogic.sol` - Credit delegation setup and collateral withdrawal
- `BitmorLendingPoolLogic.sol` - Bitmor Pool operations (deposit, borrow, repay, withdraw)
- `AavePoolLogic.sol` - Flash loan wrapper for Aave V3
- `TokenizedStrategyLogic.sol` - Strategy deposit/withdraw interactions
- `StrategyStateLogic.sol` - Queue management for multi-strategy vaults
- `VaultStateLogic.sol` - Vault configuration and state
- `BTCVaultLogic.sol` - BTC vault specific operations

**Vault System** (`vaults/`):
- `btc-vault/BTCVault.sol` - ERC-4626 vault with multi-strategy support
- `btc-vault/TokenizedStrategy/` - Strategy implementations (Aave, Simple)
- `usdc-vault/USDCVault.sol` - USDC vault implementation

**Adapters**:
- `adapters/UniswapV4SwapAdapterWrapper.sol` - Uniswap V4 integration (testnet/mainnet)

### Lending Pool (lending-pool/contracts/)

Standard Aave V2 structure — `protocol/`, `interfaces/`, `flashloan/`, `adapters/`, `mocks/`. Integration with loan-provider is interface-only (Solidity 0.6.12 vs 0.8.30).

### Script Architecture (loan-provider/script/)

```
loan-provider/script/
├── deployment/
│   ├── DeploymentConstants.sol          # Shared constants
│   ├── DeploymentBase.s.sol             # Proxy helpers, role wiring, preflight, manifest
│   ├── PostDeployChecks.s.sol           # Post-deploy invariant validation
│   ├── local/                           # Local Anvil scripts
│   │   ├── DeployPhase1Local.s.sol
│   │   └── DeployPhase3Local.s.sol
│   └── mainnet/                         # Base mainnet scripts
│       ├── DeployPhase1Mainnet.s.sol
│       ├── DeployPhase3Mainnet.s.sol
│       └── TransferToMultisig.s.sol
├── upgrade/                             # Upgrade scripts
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

**HelperConfig.s.sol** is the single source of truth for deployment addresses:
- **All getters** read from `../deployments/<chainId>/latest.json` using dot-path keys (e.g., `.loanProvider.loan`, `.lendingPool.pool`, `.tokens.usdc`)
- **Mainnet overrides**: `getAaveV3Pool()`, `getAaveAddressesProvider()`, `getCbBTC()`, `getUSDC()` return hardcoded constants on Base mainnet

**Chain Behavior**:
| Chain | Bitmor Contracts | External Protocols |
|-------|------------------|--------------------|
| Local (31337) | `deployments/31337/latest.json` | `deployments/31337/latest.json` (mocks) |
| Testnet (84532) | `deployments/84532/latest.json` | `deployments/84532/latest.json` (mocks) |
| Mainnet (8453) | `deployments/8453/latest.json` | Constants |

## Testing

### Foundry Profiles (loan-provider/)

| Profile | Use Case |
|---------|----------|
| `unit` | Unit tests with mocks (default for `make test`) |
| `integration` | Integration tests against local Anvil |
| `fork` | Fork tests against Base Sepolia |
| `fuzz` | Fuzz tests (10,000 runs) — `test/fuzz/pure/` (math) and `test/fuzz/stateful/` (vault/loan sequences) |
| `invariant` | Invariant tests (10,000 runs, depth 50) |
| `coverage` | Coverage with optimizer disabled |
| `security` | Model checker (CHC engine, overflow/underflow targets) |
| `local` | Fast local deployment builds |

### Test Base Classes (`test/base/`)

| Class | Inherits | Provides |
|-------|----------|----------|
| `BitmorTestBase` | — | AccessManager, 16 role actors, `_scheduleAndExecute()` |
| `UnitTestBase` | BitmorTestBase | MockAaveV3Pool, MockERC20, `_fundUSDC()`, `_fundCbBTC()` |
| `LoanUnitTestBase` | UnitTestBase | Full Loan+mock infrastructure, `_createStandardLoan()` |
| `ForkTestBase` | BitmorTestBase | Real Aave V3 on fork, `_dealToken()` |
| `IntegrationTestBase` | BitmorTestBase | Loads addresses from `deployments/<chainId>/latest.json` |

**Integration tests** require Anvil running with `make deploy-local` completed first.

### Key Test Gotchas

**vm.prank with external calls:** Cache role IDs before `vm.prank()` to avoid the prank being consumed:

```solidity
// WRONG — EXECUTOR_ID() external call consumes the prank
vm.prank(admin);
manager.grantRole(EXECUTOR_ID(), borrower, NO_DELAY);

// CORRECT
uint64 executorRoleId = EXECUTOR_ID();
vm.prank(admin);
manager.grantRole(executorRoleId, borrower, NO_DELAY);
```

**Delayed operations:** Use `_scheduleAndExecute()` for functions with 1-day role delays (e.g., `unpause`, vault curator ops).

## Configuration

### Environment Variables

**lending-pool/.env**: `MNEMONIC`, `ALCHEMY_KEY`, `ETHERSCAN_KEY`

**loan-provider/.env**: `BASE_SEPOLIA_RPC_URL`, `ETHERSCAN_KEY`

### Wallets (loan-provider/)

Two `cast` wallets required: `bitmor_owner` (admin/deployer) and `bitmor_user` (test user).

### Import Aliases (loan-provider/)

```
@bitmor/=src/
@openzeppelin/contracts/=lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/
@openzeppelin-upgradeable/=lib/openzeppelin-contracts-upgradeable/contracts/
@openzeppelin-foundry-upgrades/=lib/openzeppelin-foundry-upgrades/src/
@solady/=lib/solady/src/
@btcVault/=src/vaults/btc-vault/
@usdcVault/=src/vaults/usdc-vault/
@bitmor-config/=script/config/
@lending-pool/=../lending-pool/contracts/
```

### Key Addresses

Deployed addresses: `deployments/<chainId>/latest.json` (unified registry for all modules).
Base Sepolia Aave V3 Pool: `0xcFc53C27C1b813066F22D2fa70C3D0b4CAa70b7B`

## Role Configuration (AccessManager)

Role definitions: `loan-provider/script/config/RolesData.sol`

### Operational Roles

| Role       | ID  | Target      | Delay  | Description                          |
|------------|-----|-------------|--------|--------------------------------------|
| ADMIN      | 0   | —           | 0      | Top-level admin                      |
| EXECUTOR   | 1   | Loan        | 0      | Loan initialization, insurance       |
| LPCM       | 2   | Loan        | 0      | Liquidation data updates             |
| LPM_FAST   | 3   | Loan        | 0      | Emergency pause                      |
| LPM_SLOW   | 30  | Loan        | 1 day  | State variable updates, unpause      |
| ARE        | 4   | AutoRepay   | 0      | Auto repayment execution             |
| UPGRADER   | 5   | All proxies | 48h    | UUPS + beacon upgrades               |
| BVM_FAST   | 11  | BTCVault    | 0      | Pause, emergency withdraw            |
| BVM_SLOW   | 110 | BTCVault    | 1 day  | Fee recipient, unpause               |
| BVC        | 12  | BTCVault    | 1 day  | Strategy add/remove/cap              |
| BVA_FAST   | 13  | BTCVault    | 0      | Asset reallocation                   |
| BVA_SLOW   | 130 | BTCVault    | 1 day  | Supply/withdraw queue config         |
| BVD        | 14  | BTCVault    | 0      | Deposit operations (held by Loan)    |
| UVM_FAST   | 21  | USDCVault   | 0      | Pause, fund withdrawal               |
| UVM_SLOW   | 210 | USDCVault   | 1 day  | Unpause                              |
| UVC        | 22  | USDCVault   | 1 day  | Strategy, yield source config        |
| UVA        | 23  | USDCVault   | 0      | Asset reallocation                   |

### Guardian Roles

Guardians cancel delayed operations before execution:
- `GUARDIAN_LPM_SLOW` (930), `GUARDIAN_BVM_SLOW` (9110), `GUARDIAN_BVC` (912)
- `GUARDIAN_BVA_SLOW` (9130), `GUARDIAN_UVM_SLOW` (9210), `GUARDIAN_UVC` (922)
- `GUARDIAN_UPGRADER` (95) - Can cancel pending proxy upgrades during 48h window

## Security Analysis

```bash
# Model checker build
cd loan-provider && FOUNDRY_PROFILE=security forge build

# Aderyn static analysis (aderyn.toml in repo root)
aderyn .
```

Security documentation: `vulnerability-reports/`, `Vulnerability-testing-list.md`, `Invariants.md`

## Working with Both Systems

1. **Lending pool changes**: `lending-pool/` with Hardhat; integration with loan-provider is interface-only
2. **Loan system changes**: `loan-provider/` with Foundry
3. **Full deployment**: Deploy lending pool first, then loan system
4. **Local development**: `make anvil` + `make deploy-local` for full local stack; integration tests require this
5. **Address resolution**: `HelperConfig.s.sol` reads `../lending-pool/deployed-contracts.json` for pool/oracle addresses

## Key Files Reference

| Category | File |
|----------|------|
| Network config | `loan-provider/script/HelperConfig.s.sol` |
| Deployment constants | `loan-provider/script/deployment/DeploymentConstants.sol` |
| Deployment base | `loan-provider/script/deployment/DeploymentBase.s.sol` |
| Role definitions | `loan-provider/script/config/RolesData.sol` |
| Local roles | `loan-provider/script/config/LocalRolesConfig.sol` |
| Mainnet roles | `loan-provider/script/config/MainnetRolesConfig.sol` |
| Phase 1 deploy (local) | `loan-provider/script/deployment/local/DeployPhase1Local.s.sol` |
| Phase 3 deploy (local) | `loan-provider/script/deployment/local/DeployPhase3Local.s.sol` |
| Post-deploy checks | `loan-provider/script/deployment/PostDeployChecks.s.sol` |
| UUPS upgrade | `loan-provider/script/upgrade/UpgradeUUPS.s.sol` |
| Beacon upgrade | `loan-provider/script/upgrade/UpgradeBeacon.s.sol` |
| Deploy orchestrator | `deploy/scripts/deploy-local.sh` |
| Protocol invariants | `Invariants.md` |
| Test constants | `loan-provider/test/helpers/TestConstants.sol` |
| Deployment registry | `deployments/<chainId>/latest.json` |
| Deploy CLI tool | `deploy/tools/src/cli.ts` |
