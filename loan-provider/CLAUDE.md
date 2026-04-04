# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This is the **loan-provider** module of the Bitmor Protocol - a Foundry-based Solidity project implementing a BTC-collateralized lending system. Users deposit USDC as a down payment, flash loan additional USDC, swap to cbBTC (collateral), and repay over time. The system integrates with Aave V3 for flash loans and the Bitmor Lending Pool (deployed separately in `../lending-pool/`).

## Build & Test Commands

```bash
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
make test:contract CONTRACT=ContractName # Tests for a contract

# Format code
forge fmt

# Coverage report
make coverage

# Gas report
make gas-report
```

### Deployment

All core contracts are deployed behind UUPS or Beacon proxies. See `../DEPLOYMENT_SETUP.md` for full details.

```bash
# Local deployment (from repo root)
make deploy-local               # All phases: proxies + beacon + roles + validation

# Individual phases
make deploy:phase1:local        # AccessManager + BTCVault proxy + mocks
make deploy:phase3:local        # All remaining proxies + roles
make deploy:check               # Post-deploy invariant checks

# Upgrades
make upgrade:uups:schedule PROXY=0x... CONTRACT="src/..." INIT_DATA=0x RPC_URL=...
make upgrade:beacon:schedule NEW_IMPL=0x... RPC_URL=...
```

### Wallet Setup

Tests and deployments require two cast wallets:

- `bitmor_owner`: Admin/deployer account
- `bitmor_user`: Test user account

## Architecture

### Proxy Architecture

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

All upgradeable contracts use ERC-7201 namespaced storage (`@bitmor.storage.*`).

### Core Contracts (`src/protocol/`)

| Contract               | Description                                                                                                                                               |
| ---------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `Loan.sol`             | UUPS upgradeable. Main entry point for loan lifecycle (initialize, repay, close). Uses flash loans from Aave V3, swaps via Uniswap V4 |
| `LoanVault.sol`        | BeaconProxy. Per-loan smart account (LSA) holding the Aave position (aTokens/debt tokens)                            |
| `LoanVaultFactory.sol` | Non-upgradeable. Factory deploying LoanVaults as BeaconProxies                                                                                                                |
| `LoanStorage.sol`      | ERC-7201 namespaced storage for Loan contract                                                                                                                          |
| `AutoRepayment.sol`    | UUPS upgradeable. Scheduled repayment automation                                                                                                                            |
| `BeaconController.sol` | Non-upgradeable. AccessManaged wrapper for beacon upgrades                                                                                                                            |
| `BitmorAddressesProvider.sol` | UUPS upgradeable. Protocol address registry                                                                                                                            |

### Logic Libraries (`src/libraries/logic/`)

| Library                      | Lines | Description                                                     |
| ---------------------------- | ----- | --------------------------------------------------------------- |
| `LoanLogic.sol`              | ~277  | Public linked library. Loan initialization, validation, state updates for liquidations |
| `FlashLoanLogic.sol`         | ~242  | Aave V3 flash loan callback handling for init and close flows   |
| `RepayLogic.sol`             | ~107  | Monthly repayment execution logic                               |
| `CloseLoanLogic.sol`         | ~185  | Pre-closure flow with flash loan coordination                   |
| `SwapLogic.sol`              | ~132  | Token swaps with slippage protection (zQuoter or oracle-based)  |
| `LSALogic.sol`               | ~91   | Credit delegation setup and collateral withdrawal               |
| `BitmorLendingPoolLogic.sol` | ~132  | Bitmor Pool operations (deposit, borrow, repay, withdraw)       |
| `AavePoolLogic.sol`          | ~42   | Flash loan wrapper for Aave V3                                  |
| `TokenizedStrategyLogic.sol` | -     | Strategy deposit/withdraw interactions                          |
| `StrategyStateLogic.sol`     | -     | Queue management for multi-strategy vaults                      |
| `VaultStateLogic.sol`        | -     | Vault configuration and state                                   |
| `BTCVaultLogic.sol`          | -     | BTC vault specific operations                                   |

### Helper Libraries (`src/libraries/helpers/`)

| Library                    | Lines | Description                                                                                 |
| -------------------------- | ----- | ------------------------------------------------------------------------------------------- |
| `LoanMath.sol`             | ~288  | EMI calculation, rayPow, strike price, MIN_DEPOSIT_PERCENTAGE (33%)                         |
| `Errors.sol`               | ~226  | 25+ custom errors organized by category (validation, loan, flash loan, swap, access, vault) |
| `BTCVault__Validation.sol` | -     | Strategy validation for BTC vault                                                           |

### Data Types (`src/libraries/types/`)

`DataTypes.sol` contains shared structs:

- `LoanData` - Loan state (borrower, amounts, duration, status)
- `LoanStatus` - Enum: Active, Completed, Liquidated
- `ReserveData` - Aave reserve configuration
- `ExecuteInitializeLoanParams`, `ExecuteFLOperationParams`, etc.

### Vault System (`src/vaults/`)

**BTC Vault** (`btc-vault/`):

- `BTCVault.sol` - ERC-4626 vault with multi-strategy support
- `TokenizedStrategy/` - Strategy implementations:
    - `AaveTokenizedStrategy.sol` - Aave V2 integration
    - `SimpleTokenizedStrategy.sol` - Basic strategy base

**USDC Vault** (`usdc-vault/`):

- `USDCVault.sol` - USDC vault implementation
- `USDCStrategy.sol` - USDC strategy

### Adapters (`src/adapters/`)

- `UniswapV4SwapAdapterWrapper.sol` - Uniswap V4 swap integration (Base Sepolia)
- `SwapAdaptor.sol` - Generic swap adapter interface (Aerodrome for mainnet)

## Detailed Loan Flow

### Initialization (`initializeLoan`)

```
User
  │
  ▼
Loan.initializeLoan(deposit, premium, collateral, duration, data)
  │
  ├─► LoanLogic.executeInitializeLoan()
  │     │
  │     ├─► Validate: collateral bounds, deposit >= 33%
  │     ├─► Calculate: loanAmount, monthlyPayment (via LoanMath)
  │     ├─► Deploy: LSA via LoanVaultFactory.createLoanVault()
  │     ├─► Store: loan data in s_loansByLSA mapping
  │     ├─► Transfer: deposit from user, premium to collector
  │     └─► Initiate: flash loan via AavePoolLogic
  │
  └─► FlashLoanLogic.executeFLOperationInitiailizingLoan() [callback]
        │
        ├─► Validate: caller == Aave pool, initiator == this
        ├─► SwapLogic.calculateMinBTCAmt() → slippage protection
        ├─► SwapLogic.executeSwap() → USDC to cbBTC
        ├─► LSALogic.approveCreditDelegation() → enable borrowing
        ├─► BitmorLendingPoolLogic.depositCollateral() → LSA receives aTokens
        ├─► BitmorLendingPoolLogic.borrowDebt() → repay flash loan
        └─► Approve Aave pool for flash loan repayment
```

### Repayment (`repay`)

```
User
  │
  ▼
Loan.repay(lsa, repaymentAmount)
  │
  └─► RepayLogic.executeRepay()
        │
        ├─► Validate: loan exists, active, within grace period
        ├─► Transfer: repayment from user
        ├─► BitmorLendingPoolLogic.executeLoanRepayment()
        ├─► Update: lastPaymentTimestamp, remaining duration
        └─► Emit: Loan__LoanRepaid event
```

### Closure (`closeLoan`)

```
User
  │
  ▼
Loan.closeLoan(lsa, withdrawInBTC)
  │
  └─► CloseLoanLogic.executeCloseLoan()
        │
        ├─► Calculate: total debt, pre-closure fee
        ├─► Initiate: flash loan via AavePoolLogic
        └─► FlashLoanLogic.executeFLOperationCloseLoan() [callback]
              │
              ├─► Validate: caller == Aave pool, initiator == this
              ├─► BitmorLendingPoolLogic.executeLoanRepayment()
              ├─► LSALogic.withdrawCollateral() (if debt == 0)
              ├─► Transfer: pre-closure fee to collector
              ├─► SwapLogic.executeSwap() → cbBTC to USDC
              └─► Approve Aave pool for flash loan repayment
```

## Access Control System

Uses OpenZeppelin `AccessManagedUpgradeable` pattern with role-based restrictions defined in `script/config/RolesData.sol`.

### Operational Roles (16 total)

| Role       | ID  | Contract      | Description                            | Delay |
| ---------- | --- | ------------- | -------------------------------------- | ----- |
| `ADMIN`    | 0   | AccessManager | Top-level admin, can grant all roles   | 0     |
| `EXECUTOR` | 1   | Loan          | Loan initialization, insurance updates | 0     |
| `LPCM`     | 2   | Loan          | Liquidation data updates               | 0     |
| `LPM_FAST` | 3   | Loan          | Emergency pause                        | 0     |
| `LPM_SLOW` | 30  | Loan          | State variable updates, unpause        | 1 day |
| `ARE`      | 4   | AutoRepayment | Auto repayment execution               | 0     |
| `UPGRADER` | 5   | All proxies   | UUPS + beacon upgrades                 | 48h   |
| `BVM_FAST` | 11  | BTCVault      | Pause, emergency withdraw              | 0     |
| `BVM_SLOW` | 110 | BTCVault      | Fee recipient, unpause                 | 1 day |
| `BVC`      | 12  | BTCVault      | Strategy add/remove/cap changes        | 1 day |
| `BVA_FAST` | 13  | BTCVault      | Asset reallocation                     | 0     |
| `BVA_SLOW` | 130 | BTCVault      | Supply/withdraw queue config           | 1 day |
| `BVD`      | 14  | BTCVault      | Deposit operations                     | 0     |
| `UVM_FAST` | 21  | USDCVault     | Pause, fund withdrawal                 | 0     |
| `UVM_SLOW` | 210 | USDCVault     | Unpause operations                     | 1 day |
| `UVC`      | 22  | USDCVault     | Strategy, yield source config          | 1 day |
| `UVA`      | 23  | USDCVault     | Asset reallocation                     | 0     |

### Guardian Roles (6 total)

Guardians can cancel delayed operations before execution:

- `GUARDIAN_LPM_SLOW` (930) - Guards LPM_SLOW operations
- `GUARDIAN_BVM_SLOW` (9110) - Guards BVM_SLOW operations
- `GUARDIAN_BVC` (912) - Guards BVC operations
- `GUARDIAN_BVA_SLOW` (9130) - Guards BVA_SLOW operations
- `GUARDIAN_UVM_SLOW` (9210) - Guards UVM_SLOW operations
- `GUARDIAN_UVC` (922) - Guards UVC operations
- `GUARDIAN_UPGRADER` (95) - Guards UPGRADER operations (can cancel pending upgrades)

## Security Patterns

### Flash Loan Callback Validation

```solidity
// FlashLoanLogic.sol - Both executeFLOperationInitiailizingLoan and executeFLOperationCloseLoan
if (msg.sender != ctx.aavePool) revert Errors.CallerIsNotAAVEPool();
if (params.initiator != address(this)) revert Errors.WrongFLInitiator();
```

### Reentrancy Protection

Critical functions use OpenZeppelin's `ReentrancyGuardTransient` (transient storage for gas efficiency):

- `Loan.initializeLoan()` - `nonReentrant`
- `Loan.repay()` - `nonReentrant`
- `Loan.closeLoan()` - `nonReentrant`

### Access Control

- `restricted` modifier on admin functions (via AccessManaged)
- `Pausable` for emergency stops
- Time delays on sensitive operations (1 day for state changes)

### LoanVault Security

- `execute()` function protected by `onlyOwner` (Loan contract)
- Credit delegation scoped to Protocol only
- Strategy removal requires cap=0 and balance=0

## Constants

From `LoanStorage.sol` and `LoanMath.sol`:

| Constant                  | Value   | Description                     |
| ------------------------- | ------- | ------------------------------- |
| `s_slippage_swap`         | 50      | 0.5% maximum slippage tolerance |
| `MIN_DEPOSIT_PERCENTAGE`  | 33_00   | 33% minimum deposit requirement |
| `s_maxBTCAmt`             | 1e8     | 1 BTC maximum collateral        |
| `s_minBTCAmt`             | 0.01e8  | 0.01 BTC minimum collateral     |
| `LOAN_REPAYMENT_INTERVAL` | 30 days | Monthly repayment interval      |
| `RAY`                     | 1e27    | Interest rate precision         |
| `BASIS_POINTS`            | 10000   | 100% in basis points            |

## External Dependencies

- **Aave V3** (`i_AAVE_V3_POOL`): Flash loans for loan initialization/closure
- **Bitmor Lending Pool** (`i_BITMOR_POOL`): Stores collateral, issues aTokens/debt tokens
- **Uniswap V4**: Token swaps via `UniswapV4SwapAdapterWrapper` (testnet)
- **Aerodrome**: Token swaps via `SwapAdaptor` + `zQuoter` (mainnet)
- **Chainlink Oracles**: Price feeds via `IPriceOracleGetter`

## Test Structure

Tests are in `test/unit/` and use mock-based infrastructure (no fork required):

**Loan Tests:**

- `Loan/BaseLoan.t.sol` - Shared test base with helpers, snapshots, and setup
- `Loan/InitializeLoan.t.sol` - Loan creation tests (12 tests)
- `Loan/RepayLoan.t.sol` - Repayment tests (17 tests)
- `Loan/CloseLoan.t.sol` - Loan closure tests (16 tests)
- `Loan/LoanContract.t.sol` - Core loan functionality (10 tests)

**Liquidation Tests:**

- `MicroLiquidation.t.sol` - Micro liquidation scenarios (12 tests)
- `FullLiquidation.t.sol` - Full liquidation scenarios (13 tests)

**Other Tests:**

- `LendingPool.t.sol` - Lending pool security and payment calculations (7 tests)
- `Insurance.t.sol` - Insurance integration tests
- `Vault/BTC/*.t.sol` - BTCVault tests

### Mock Infrastructure (`test/mock/`)

| Mock Contract                  | Purpose                                                       |
| ------------------------------ | ------------------------------------------------------------- |
| `MockBitmorLendingPool.sol`    | Simulates Bitmor lending pool with deposit/borrow/liquidation |
| `MockPriceOracle.sol`          | Controllable price oracle for liquidation testing             |
| `MockAddressesProvider.sol`    | Provides addresses for protocol contracts                     |
| `MockAToken.sol`               | Simulates aToken balance tracking                             |
| `MockVariableDebtToken.sol`    | Simulates debt token balance tracking                         |
| `MockSwapAdapter.sol`          | Simulates token swaps with oracle-based pricing               |
| `MockInterestRateStrategy.sol` | Configurable interest rate strategy                           |
| `MockAaveV3Pool.sol`           | Simulates Aave V3 flash loans                                 |

### Test Helpers

`MockBitmorLendingPool` provides test state control:

- `setHealthFactor(lsa, value)` - Set health factor for full liquidation tests
- `setUserOverdue(lsa, bool)` - Set overdue state for micro liquidation tests
- `setLiquidationType(lsa, type)` - Direct liquidation type control (0=none, 1=full, 2=micro)
- `setVariableBorrowRate(asset, rate)` - Set interest rate (in RAY)
- `setInsuranceId(lsa, id)` - Set insurance ID for tests

`BaseLoan.t.sol` provides:

- `_createStandardLoan()` - Creates 1 BTC / 12 month loan
- `_createLoanForBorrower(borrower, ...)` - Creates loan for specific borrower (handles role grants)
- `_captureTestSnapshot(lsa)` - Snapshot loan state before/after
- `_setupForMicroLiquidation(lsa)` - Setup overdue loan scenario
- `_setupForFullLiquidation(lsa)` - Setup price-drop liquidation

### Test Gotchas

**vm.prank with external calls:** When using `vm.prank(admin)` before `manager.grantRole()`, cache external call results (like `EXECUTOR_ID()`) BEFORE the prank to avoid consuming it:

```solidity
// WRONG - prank consumed by EXECUTOR_ID()
vm.prank(admin);
manager.grantRole(EXECUTOR_ID(), borrower, NO_DELAY);

// CORRECT - cache before prank
uint64 executorRoleId = EXECUTOR_ID();
vm.prank(admin);
manager.grantRole(executorRoleId, borrower, NO_DELAY);
```

**Borrow access control:** `MockBitmorLendingPool.borrow()` only allows calls from the registered Loan contract. Tests creating separate Loan instances must register them:

```solidity
mockAddressesProvider.setBitmorLoan(address(newLoanInstance));
```

## Configuration

**Network**: Base Sepolia (Chain ID: 84532)

**Key addresses** (from `script/HelperConfig.s.sol`):

- Aave V3 Pool: `0xcFc53C27C1b813066F22D2fa70C3D0b4CAa70b7B`
- Aave Addresses Provider: `0x39Eb7Ca3b8f0F29C21a008b1F281b30c4539736a`

**Deployment state**: `../deployments/<chainId>/latest.json` - Unified registry containing all deployed contract addresses (loan-provider, lending-pool, tokens, external)

**Integration**: All addresses (including lending pool) are read from the unified registry via HelperConfig

## Import Aliases

From `remappings.txt`:

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
forge-std/=lib/forge-std/src/
```

## Known TODOs

Tracked TODO items in the codebase:

| Location                         | Description                                           |
| -------------------------------- | ----------------------------------------------------- |
| `LoanMath.sol:75`                | Consider replacing rayPow with cleaner implementation |
| `LoanMath.sol:115,196`           | Verify EMI calculation logic for edge cases           |
| `SwapLogic.sol:102`              | Shift all swaps to Uniswap V4 router                  |
| `RolesData.sol:39`               | Verify admin address for production deployment        |
| `BTCVault__Validation.sol:37`    | Implement validation logic for fund reallocation      |
| `SimpleTokenizedStrategy.sol:71` | Implement balance calculation in derived contracts    |
| `USDCStrategy.sol:237`           | aToken balance vs underlying assets calculation       |
| `USDCStrategy.sol:321`           | Implement slippage check for AAVE withdrawals         |
| `SwapAdaptor.sol:28`             | Confirm zRouter address on Base mainnet               |

## Security Considerations

### Known Risks (from security review)

**MEDIUM-HIGH Risk:**
| Finding | Location | Description |
| ------------------ | ------------------------------------------------ | ------------------------------------------------------------------------------------------- |
| Oracle staleness | `SwapLogic.sol:119-120`, `LoanLogic.sol:207-208` | No freshness check on `getAssetPrice()` calls - stale prices could affect loan calculations |
| EMI precision loss | `LoanMath.sol:163,165,171` | RAY division truncation in EMI calculations could accumulate errors |
| Hardcoded slippage | `LoanStorage.sol:70` | 0.5% `s_slippage_swap` may fail in high volatility periods |

**LOW Risk:**
| Finding | Location | Description |
| ---------------------- | --------------- | --------------------------------------------------------------------------- |
| Unbounded loans array | `Loan.sol:287` | `getUserAllLoans()` iterates all user loans - DoS potential for heavy users |
| No max duration | `LoanLogic.sol` | Missing upper bound validation on loan duration |
| No pre-closure fee cap | `Loan.sol` | `s_preClosureFeeBps` admin-controlled but unbounded |

### Secure Patterns Implemented

- **Flash loan callback validation** - Verifies caller is Aave pool and initiator is contract (`FlashLoanLogic.sol`)
- **ReentrancyGuard** - Applied to `initializeLoan()`, `repay()`, `closeLoan()` (`Loan.sol`)
- **Strategy removal safety** - Requires cap=0 and balance=0 before removal (`BTCVault.sol`)
- **Credit delegation scoping** - Delegation limited to Protocol only (`LoanVault.sol`)
- **LoanVault execute protection** - `execute()` restricted to owner (`LoanVault.sol`)

## Documentation

| Document             | Location                                                | Description                                                                   |
| -------------------- | ------------------------------------------------------- | ----------------------------------------------------------------------------- |
| Session Continuation | `docs/plans/SESSION_CONTINUATION.md`                    | Tracks implementation progress and provides context for session continuations |
| Test Migration Plan  | `docs/plans/2026-01-22-comprehensive-test-migration.md` | Original plan for migrating tests to mock infrastructure                      |
