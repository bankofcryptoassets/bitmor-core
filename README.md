# Bitmor Protocol

Get your first whole 1 BTC with an undercollateralised loan.


## Repo Setup

This repo have two projects initialized:
1. Lending Pool: A fork of Aave v2 with Hardhat v3 (previously was Hardhat v2).
2. Loan Provider: A foundry setup for other protocol components: Loan Provider, Vaults and Access Manager.


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



## New Deployment Flow 

Only for testnet which should work with test.

> Lending pool local testing will require local deployment of the vaults. 
> Mock USDC vault and you will require bvBTC mock 

1. Deploy Access Manager
2. Deploy USDC and BTC mock token.
4. Deploy USDC and BTC vaults. 
   1. bvBTC shares means. Need to initialize them as a reserve.
5. Deploy Lending Pool 
6. Deploy loan provider
7. Set addresses in AddressesProvider (USDC, BTC vault)
8. 