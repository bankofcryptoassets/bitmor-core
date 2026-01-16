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

# Test (requires Base Sepolia fork)
make test                                           # All tests
forge test --mt test_functionName --fork-url base_sepolia -vvvv  # Single test

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

## Testing

### Foundry Tests (loan-provider/)

Tests require Base Sepolia fork. Key test files in `test/unit/`:
- `Loan/BaseLoan.t.sol` - Shared test base with helpers and setup
- `Loan/InitializeLoan.t.sol`, `RepayLoan.t.sol`, `CloseLoan.t.sol`
- `MicroLiquidation.t.sol`, `FullLiquidation.t.sol`
- `Vault/BTC/*.t.sol` - BTCVault tests

Helpful make targets:
```bash
make testLoanInitialization
make testRepay
make testCloseLoan
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
