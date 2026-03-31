# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This is the **lending-pool** module of the Bitmor protocol — a fork of Aave V2 with custom liquidation mechanics. It uses Hardhat v3 and TypeScript.

Key Bitmor modifications to Aave V2:
- **Micro-liquidation**: Sells just enough collateral to restore healthy position rather than liquidating the full position
- **Full liquidation**: Standard liquidation with modified checks that include `isInsured` parameter
- **`checkTypeOfLiquidation`**: Returns liquidation type (0=none, 1=full, 2=micro) based on loan status, health factor, and payment history
- **Vault-only deposits**: All deposits must go through vault contracts (Error 85: LP_CALLER_NOT_VAULT)
- **Flash loans disabled**: Flash loans are completely disabled (Error 86: LP_FLASHLOAN_DISABLED)
- **Vault shares vs aTokens**: Users hold vault shares (ERC20), vaults hold aTokens (collateral in pool)

## Commands

```bash
# Build
npm run compile

# Test
npm test                    # Aave core tests
npm run test-bitmor         # Bitmor-specific tests
npm run test-amm            # AMM tests
npm run test-scenarios      # Protocol scenario tests

# Deploy to Base Sepolia
npm run aave:baseSepolia:full:migration

# Local development
npm run bitmor:localhost:dev:migration

# Format
npm run prettier:write
```

### Running a Single Test

```bash
# Run specific test file
npm run compile && TS_NODE_TRANSPILE_ONLY=1 npx hardhat test ./test-suites/test-bitmor/__setup.spec.ts

# Run with fork
FORK=main npm run compile && TS_NODE_TRANSPILE_ONLY=1 npx hardhat test ./test-suites/test-aave/scenario.spec.ts
```

## Architecture

### Core Protocol Contracts (`contracts/protocol/`)

**Lending Pool**:
- `lendingpool/LendingPool.sol` - Main entry point for deposits, borrows, repays, flash loans
- `lendingpool/LendingPoolCollateralManager.sol` - Handles `liquidationCall` and `microLiquidationCall`
- `lendingpool/LendingPoolConfigurator.sol` - Admin functions for reserve configuration
- `lendingpool/LendingPoolStorage.sol` - Storage layout (inherited by LendingPool)

**Libraries** (`protocol/libraries/`):
- `logic/LoanLiquidationLogic.sol` - **Bitmor-specific**: Determines liquidation type based on loan data, health factor, insurance status
- `logic/ValidationLogic.sol` - Validates liquidation calls (modified for micro-liquidation)
- `logic/GenericLogic.sol` - User account data calculations, health factor
- `logic/ReserveLogic.sol` - Reserve state updates
- `types/DataTypes.sol` - **Extended** with `LoanData` struct and `LoanStatus` enum for Bitmor loan tracking

### Bitmor-Specific Interfaces

- `interfaces/ILoan.sol` - Interface to the external Loan contract (from `loan-provider/`)
- `interfaces/ILendingPool.sol` - Extended with `microLiquidationCall` and `checkTypeOfLiquidation`
- `interfaces/ILendingPoolCollateralManager.sol` - Extended for micro-liquidation

### Key Data Structures

```solidity
// DataTypes.sol - Bitmor loan tracking
struct LoanData {
    address borrower;
    uint256 depositAmount;        // Initial USDC deposit (6 decimals)
    uint256 loanAmount;           // Flash loan amount (6 decimals)
    uint256 btcAmount;     // cbBTC collateral (8 decimals)
    uint256 estimatedMonthlyPayment;
    uint256 duration;             // Loan term in months
    uint256 createdAt;
    uint256 insuranceID;          // 0 = uninsured
    uint256 lastPaymentTimestamp;
    LoanStatus status;            // Active, Completed, Liquidated
}
```

### Market Configuration (`markets/`)

- `bitmor/index.ts` - Bitmor market config (MarketId, ProviderId, ReserveAssets)
- `bitmor/reservesConfigs.ts` - Reserve strategies for USDC and bcbBTC
- `bitmor/commons.ts` - Common Bitmor parameters

### Deployment Tasks (`tasks/`)

- `migrations/bitmor.sepolia.ts` - Base Sepolia deployment
- `migrations/bitmor.dev.ts` - Local development deployment
- `actions/migrations/bitmor.action.ts` - Core migration action

## Configuration

### Environment Variables (`.env`)

```
MNEMONIC=""           # Deployment wallet mnemonic
ALCHEMY_KEY=""        # RPC provider
ETHERSCAN_KEY=""      # Contract verification
```

### Networks

- `sepolia` (Base Sepolia, chainId 84532) - Primary testnet
- `hardhat` / `default` - Local testing
- `localhost` - Local node

### Deployed Addresses

Stored in `deployed-contracts.json`, keyed by network. Key contracts:
- `LendingPool` - Main protocol entry point
- `LendingPoolCollateralManager` - Liquidation logic
- `AaveOracle` - Price oracle
- `USDC`, `bcbBTC` - Reserve asset addresses

## Testing

Tests are in `test-suites/`:
- `test-aave/` - Core Aave V2 tests
- `test-bitmor/` - Bitmor-specific tests (liquidation mechanics)
- `test-amm/` - AMM-related tests

Test helpers:
- `helpers/make-suite.ts` - Test setup and fixtures
- `helpers/scenario-engine.ts` - Scenario-based testing

## Integration with loan-provider

This module integrates with `../loan-provider/` via:
1. The `ILoan` interface - lending-pool calls into `Loan.sol` to get loan data
2. `LendingPoolAddressesProvider.getBitmorLoan()` - Returns the external Loan contract address
3. Deployed addresses exported to `deployed-contracts.json` for loan-provider to consume

## Liquidation Flow

```
checkTypeOfLiquidation(user)
    │
    ├─→ 0: No liquidation (loan inactive OR payment not overdue)
    │
    ├─→ 1: Full liquidation
    │      - Uninsured AND health factor < 1
    │      - OR collateral cannot cover micro-liquidation
    │      - OR remaining collateral < guard amount after micro-liq
    │
    └─→ 2: Micro-liquidation
           - Payment overdue (lastPayment + grace + interval < now)
           - Collateral sufficient to cover one EMI + bonus
           - Remaining collateral covers remaining debt + bonus
```

## Solidity Version

All contracts use Solidity 0.6.12 with optimizer enabled (200 runs).
