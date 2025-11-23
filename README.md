# Bitmor Protocol

Get your first whole 1 BTC with an undercollateralised loan.


## Setup

### Testnet (Base Sepolia)

#### Deploy Mock Tokens 
We need to deploy mock **USDC** and **cbBTC** for the testnet environment.

In `lending-pool`:
```bash
npx hardhat run scripts/deploy-tokens.js --network sepolia
```

### Deploy Bitmor Lending Pool 
We need to deploy Lending Pool with mock tokens as reserve assets.

In `lending-pool`:
```bash
npm run aave:baseSepolia:full:migration
```

To verify all the contracts on explorer:
```bash
npx hardhat run scripts/verify-all-contracts.js 
```

### Deploy Bitmor Loan Provider
Deploy the Bitmor Loan Provider System.

In `loan-provider`:
```bash
make setup
```

This will you mock tokens, add them to the Lending Pool, deploy all the contracts and save it in the `./loan-provider/deployments.json`