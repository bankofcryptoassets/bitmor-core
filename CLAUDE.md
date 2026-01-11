# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This is a Bitmor lending protocol based on Aave Protocol V2, featuring both traditional DeFi lending pools and a novel loan system. The repository contains smart contracts for decentralized non-custodial liquidity markets with additional Bitmor-specific loan functionality.

The project has a dual-directory structure:
- **`lending-pool/`**: Aave V2-based lending protocol (Hardhat + TypeScript)
- **`loan-provider/`**: Bitmor loan system (Foundry + Solidity)

## Development Environment

This project uses both Hardhat and Foundry in separate directories:

### Hardhat (lending-pool/ - Primary development)
- **Location**: `lending-pool/` directory
- **Compilation**: `npm run compile` (from lending-pool/)
- **Testing**:
  - All tests: `npm test`
  - Aave tests: `npm run test`
  - AMM tests: `npm run test-amm`
  - Bitmor tests: `npm run test-bitmor`
  - Scenario tests: `npm run test-scenarios`
- **Local development**: `docker-compose up` then `docker-compose exec contracts-env bash`
- **Networks**: Base Sepolia (primary testnet), Hardhat local, mainnet fork

### Foundry (loan-provider/ - Secondary development)
- **Location**: `loan-provider/` directory
- **Build**: `forge build` or `make build` (from loan-provider/)
- **Test**: `forge test --fork-url base_sepolia` or `make test`
- **Format**: `forge fmt` or `make format`
- **Quick setup**: `make setup` (deploys full Bitmor system to Base Sepolia)
- **Individual tests**: Use make targets like `make testLoanInitialization`, `make testRepay`, `make testCloseLoan`

### Environment Setup
Required `.env` file in `lending-pool/`:
```
MNEMONIC=""
ALCHEMY_KEY=""
INFURA_KEY=""
ETHERSCAN_KEY=""
TENDERLY_PROJECT=""
TENDERLY_USERNAME=""
```

Required `.env` file in `loan-provider/`:
```
BASE_SEPOLIA_RPC_URL=""
ETHERSCAN_KEY=""
```

## Architecture

This project has a dual-repository structure with two main development environments:

### lending-pool/ (Aave V2 + Bitmor Integration)
- **`contracts/`**: Smart contract source code
  - `contracts/protocol/`: Core Aave V2 lending protocol contracts
  - `contracts/mocks/`: Testing utilities and mock contracts
  - `contracts/adapters/`: Flash loan and swap adapters
  - `contracts/interfaces/`: Contract interfaces
  - `contracts/misc/`: Utility contracts
  - `contracts/flashloan/`: Flash loan implementations
- **`tasks/`**: Hardhat deployment and interaction tasks
- **`test-suites/`**: Test files organized by protocol area (test-aave, test-amm, test-bitmor)
- **`markets/`**: Market configuration files (bitmor/, aave/, amm/, etc.)
- **`helpers/`**: TypeScript utilities and contract getters
- **`scripts/`**: Node.js interaction scripts for deployed contracts

### loan-provider/ (Pure Bitmor Loan System)
- **`src/`**: Solidity source contracts
  - `src/protocol/`: Core loan protocol contracts (Loan.sol)
  - `src/vault/`: Vault contracts (LoanVault.sol, LoanVaultFactory.sol)
  - `src/dependencies/`: OpenZeppelin dependencies
  - `src/interfaces/`: Loan system interfaces
  - `src/libraries/`: Shared logic libraries
  - `src/mocks/`: Test contracts
  - `src/adapters/`: Swap and interaction adapters
- **`script/`**: Foundry deployment and interaction scripts
- **`test/`**: Foundry test contracts

### Key Components
1. **Lending Protocol**: Standard Aave V2 lending pools with aTokens, stable/variable debt tokens
2. **Bitmor Loan System**: Custom loan contracts with vault factory pattern
3. **Price Oracles**: Chainlink and custom price feed integrations
4. **Adapters**: Flash loan receivers and DEX swap adapters
5. **Dual Development**: Both Hardhat (lending-pool) and Foundry (loan-provider) environments

## Common Commands

### Hardhat Commands (lending-pool/)
All commands should be run from the `lending-pool/` directory:

**Build & Development:**
- `npm run compile` - Compile all contracts
- `npm run prettier:write` - Format TypeScript and Solidity code
- `npm run ci:clean` - Clean artifacts and cache

**Testing:**
- `npm test` or `npm run test` - Run full Aave test suite
- `npm run test-bitmor` - Run Bitmor-specific tests
- `npm run test-amm` - Run AMM tests
- `npm run test-scenarios` - Run protocol scenario tests
- `npm run test-amm-scenarios` - Run AMM scenario tests

**Network Deployments:**
- `npm run aave:docker:full:migration` - Local Docker deployment
- `npm run aave:baseSepolia:full:migration` - Deploy to Base Sepolia
- `npm run aave:fork:main` - Deploy to mainnet fork

### Foundry Commands (loan-provider/)
All commands should be run from the `loan-provider/` directory:

**Build & Development:**
- `forge build` or `make build` - Build contracts
- `forge test --fork-url base_sepolia` or `make test` - Run all tests
- `forge fmt` or `make format` - Format Solidity code
- `make coverage` - Generate coverage report
- `make gasReport` - Generate gas usage report

**Quick Deployment:**
- `make setup` - Deploy full Bitmor system to Base Sepolia
- `make deployMockTokens` - Deploy test tokens
- `make deployLoan` - Deploy loan contracts
- `make initializeLoan` - Initialize a test loan

**Individual Components:**
- `make deployLoanVault` - Deploy loan vault implementation
- `make deployLoanVaultFactory` - Deploy vault factory
- `make mintTokens` - Mint test tokens
- `make verifyAll` - Verify all deployed contracts

**Testing Individual Functions:**
- `make testLoanInitialization` - Test loan initialization
- `make testRepay` - Test loan repayment
- `make testCloseLoan` - Test loan closure
- `make testCreateAutoRepayment` - Test auto-repayment creation
- `make testExecuteRepayment` - Test auto-repayment execution

### Network Configurations
- **Base Sepolia**: Primary testnet (Chain ID: 84532)
- **Hardhat Local**: Local development network
- **Mainnet Fork**: For testing with real data

## Contract Verification
- **Hardhat**: Add `--verify` flag to deployment commands
- **Foundry**: Uses Sourcify verification with `--verifier sourcify` flag
- Both require proper `ETHERSCAN_KEY` in environment

## Market Configuration
Market configs are located in `lending-pool/markets/` directory following `IAaveConfiguration` interface:
- `markets/bitmor/` - Bitmor-specific market configuration
- `markets/aave/` - Standard Aave market configuration
- `markets/amm/` - AMM market configuration
- Each market has deployment tasks and reserve configurations

## Important Files

### Configuration Files
- `lending-pool/hardhat.config.ts` - Hardhat configuration with network settings
- `lending-pool/helper-hardhat-config.ts` - Network and deployment parameters
- `loan-provider/foundry.toml` - Foundry configuration with profiles and RPC endpoints
- `loan-provider/Makefile` - Foundry deployment shortcuts and test commands

### Development Files
- `lending-pool/package.json` - NPM scripts and dependencies
- `lending-pool/.env` - Environment variables (not committed)
- `lending-pool/docker-compose.yml` - Docker development environment
- `loan-provider/remappings.txt` - Solidity import mappings
- `loan-provider/deployments.json` - Contract deployment addresses

### Deployment and Verification
- `lending-pool/deployed-contracts.json` - Hardhat deployment addresses
- `loan-provider/VERIFICATION.md` - Contract verification instructions
- Both projects support automatic contract verification on deployment

## Working with Both Systems

When working on this codebase, you'll often need to switch between directories:

1. **For lending pool modifications**: Work in `lending-pool/` with Hardhat
2. **For loan system modifications**: Work in `loan-provider/` with Foundry
3. **Full system deployment**: Use both environments in sequence
4. **Integration testing**: Deploy lending pool first, then loan system

The systems are designed to integrate, with the lending pool providing liquidity and the loan system providing additional functionality on top.

## Testing Strategy

### Hardhat Testing (lending-pool/)
- Tests organized in `test-suites/` by feature area
- Uses Waffle framework with ethers.js
- Fork testing available with `FORK=main` environment variable
- Scenario tests in separate files for complex user flows

### Foundry Testing (loan-provider/)
- Tests in `test/` directory using Foundry's testing framework
- Fork testing configured in `foundry.toml` with automatic block number detection
- Individual test functions can be run with `--mt test_functionName`
- Coverage reporting available with `make coverage`

## Security Considerations

- Both projects use OpenZeppelin contracts for security-critical functionality
- Foundry profile includes model checker configuration for security analysis
- Use `FOUNDRY_PROFILE=security forge build` for enhanced security analysis
- Pre-commit hooks ensure code formatting consistency