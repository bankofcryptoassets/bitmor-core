# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This is the **loan-provider** module of the Bitmor Protocol - a Foundry-based Solidity project implementing a BTC-collateralized lending system. Users deposit USDC as a down payment, flash loan additional USDC, swap to cbBTC (collateral), and repay over time. The system integrates with Aave V3 for flash loans and the Bitmor Lending Pool (deployed separately in `../lending-pool/`).

## Build & Test Commands

```bash
# Build
forge build

# Run all tests (requires Base Sepolia fork)
make test
# or directly:
forge test --fork-url base_sepolia --fork-block-number <block>

# Run specific test by name pattern
forge test --mt test_functionName --fork-url base_sepolia -vvvv

# Format code
forge fmt

# Coverage report
make coverage

# Gas report
make gasReport
```

### Deployment (Base Sepolia)

```bash
# Full setup: deploys all contracts and configures the system
make setup

# Individual deployments
make deployLoan                 # Deploy Loan contract
make deployLoanVault            # Deploy LoanVault implementation
make deployLoanVaultFactory     # Deploy vault factory
make deploySwapAdapterWrapper   # Deploy Uniswap V4 swap adapter

# Post-deployment configuration
make setLoanVaultFactory        # Link factory to Loan contract
make setBitmorLoan              # Register Loan in AddressesProvider
make saveAddresses              # Persist deployment addresses
make verifyAll                  # Verify contracts on Sourcify
```

### Wallet Setup

Tests and deployments require two cast wallets:
- `bitmor_owner`: Admin/deployer account
- `bitmor_user`: Test user account

## Architecture

### Core Contracts

**Loan System (`src/protocol/`)**:
- `Loan.sol` - Main entry point for loan lifecycle (initialize, repay, close). Uses flash loans from Aave V3, swaps via Uniswap V4, and stores collateral in per-user vaults
- `LoanVault.sol` - Per-loan smart account (LSA) holding the Aave position (aTokens/debt tokens). Deployed via CREATE2 for deterministic addresses
- `LoanVaultFactory.sol` - Minimal proxy factory deploying LoanVaults
- `LoanStorage.sol` - Storage layout for Loan contract
- `AutoRepayment.sol` - Scheduled repayment automation

**Libraries (`src/libraries/`)**:
- `logic/LoanLogic.sol` - Core loan calculations and initialization logic
- `logic/RepayLogic.sol` - Repayment execution
- `logic/CloseLoanLogic.sol` - Loan closure/settlement
- `logic/FlashLoanLogic.sol` - Flash loan callback handling
- `logic/SwapLogic.sol` - Token swap execution
- `helpers/LoanMath.sol` - Interest rate and payment calculations
- `helpers/Errors.sol` - Custom error definitions
- `types/DataTypes.sol` - Shared structs (`LoanData`, `LoanStatus`, etc.)

**Vault System (`src/vault/`)**:
- `btc-vault/BTCVault.sol` - ERC-4626 vault with multi-strategy support for BTC assets
- `btc-vault/TokenizedStrategy/` - Strategy implementations (Aave, Simple)
- `usdc-vault/USDCVault.sol` - USDC vault implementation

**Adapters (`src/adapters/`)**:
- `UniswapV4SwapAdapterWrapper.sol` - Uniswap V4 swap integration
- `SwapAdaptor.sol` - Generic swap adapter interface

### Loan Flow

1. User calls `initializeLoan(deposit, premium, collateral, duration, data)`
2. Loan contract takes flash loan from Aave V3 for remaining amount
3. Flash loan callback swaps USDC → cbBTC via Uniswap V4
4. cbBTC deposited to Bitmor Lending Pool, creating aToken position in user's LoanVault (LSA)
5. Flash loan repaid from user's deposit + borrowed amount
6. User repays monthly; on completion, collateral returned to user

### External Dependencies

- **Aave V3** (`i_AAVE_V3_POOL`): Flash loans for loan initialization
- **Bitmor Lending Pool** (`i_BITMOR_POOL`): Stores collateral, issues aTokens/debt tokens
- **Uniswap V4**: Token swaps via `UniswapV4SwapAdapterWrapper`
- **Chainlink Oracles**: Price feeds via `IPriceOracleGetter`

### Access Control

Uses OpenZeppelin `AccessManaged` pattern with role-based restrictions:
- `restricted` modifier on admin functions
- `Pausable` for emergency stops

## Test Structure

Tests are in `test/unit/` and require a Base Sepolia fork:

- `Loan/BaseLoan.t.sol` - Shared test base with helpers, snapshots, and setup
- `Loan/InitializeLoan.t.sol` - Loan creation tests
- `Loan/RepayLoan.t.sol` - Repayment tests
- `Loan/CloseLoan.t.sol` - Loan closure tests
- `MicroLiquidation.t.sol`, `FullLiquidation.t.sol` - Liquidation scenarios
- `Vault/BTC/*.t.sol` - BTCVault tests
- `Utilities.t.sol` - Shared test utilities

### Test Helpers

`BaseLoan.t.sol` provides:
- `_createStandardLoan()` - Creates 1 BTC / 12 month loan
- `_captureTestSnapshot(lsa)` - Snapshot loan state before/after
- `_setupForMicroLiquidation(lsa)` - Setup overdue loan scenario
- `_setupForFullLiquidation(lsa)` - Setup price-drop liquidation

## Configuration

**Network**: Base Sepolia (Chain ID: 84532)

**Key addresses** (from `script/HelperConfig.s.sol`):
- Aave V3 Pool: `0xcFc53C27C1b813066F22D2fa70C3D0b4CAa70b7B`
- Aave Addresses Provider: `0x39Eb7Ca3b8f0F29C21a008b1F281b30c4539736a`

**Deployment state**: `deployments.json` - Contains deployed contract addresses and block numbers

**Integration**: Reads Bitmor Lending Pool addresses from `../lending-pool/deployed-contracts.json`

## Import Aliases

From `remappings.txt`:
```
@bitmor/=src/
@openzeppelin/=lib/openzeppelin-contracts/contracts/
@solady/=lib/solady/src/
forge-std/=lib/forge-std/src/
```
