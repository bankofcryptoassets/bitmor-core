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

In `lending-pool`
```bash
npm run aave:baseSepolia:full:migration
```

### Deploy Mock Swap Adapter
This will act as our custom dex. Since we are using **zRouter** which is not available for the *baseSepolia* we need a custom dec which will serve the minimal functionality, i.e., swapping the tokens.

In `loan-proivder`:
```bash
make deploySwapAdapterWrapper
```

### Mint Mock Tokens 
Mint mock tokens to the `owner` and `user` addresses.

In `loan-provider`:
```bash
make mintTokens
```

### Deposit Mock Tokens in the Bitmor Lending Pool
It deposits mock USDC, *bUSDC*, in the Lending Pool.

In `loan-provider`:
```bash
make depositDebtTokenToBitmorLendingPool`
```


### Deploy Bitmor Loan Provider

In `loan-provider`:
```bash
make 