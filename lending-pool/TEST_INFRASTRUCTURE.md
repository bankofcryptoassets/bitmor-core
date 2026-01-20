# Test Infrastructure Deep Dive

**Purpose:** This document explains exactly how the Aave/Bitmor test infrastructure works, from test setup to price oracles to token minting.

---

## Overview

The test suite uses **Hardhat** with **mock contracts** to create a completely isolated, controllable test environment. Every test runs against fresh blockchain state with predetermined token prices and unlimited mintable tokens.

---

## 1. Test Setup Flow

When you run `npm test`, the **very first thing** that happens is the `before()` hook in `test-suites/test-aave/__setup.spec.ts` executes **once** before all tests:

```typescript
before(async () => {
  // 1. Connect to Hardhat network
  const connectedNetwork = await network.connect();
  const { ethers } = connectedNetwork;

  // 2. Deploy ENTIRE test environment
  await buildTestEnv(deployer, secondaryWallet);

  // 3. Initialize testEnv object with deployed contracts
  await initializeMakeSuite();
});
```

This runs **once per test session** and deploys the entire protocol.

---

## 2. Building the Test Environment

The `buildTestEnv()` function (lines 98-312 in `__setup.spec.ts`) deploys a **complete mock Aave protocol**:

### A. Mock ERC20 Tokens (Lines 68-96)

```typescript
const deployAllMockTokens = async (deployer: Signer) => {
  const tokens: { [symbol: string]: MintableERC20 | WETH9Mocked } = {};

  for (const tokenSymbol of Object.keys(TokenContractId)) {
    if (tokenSymbol === 'WETH') {
      tokens[tokenSymbol] = await deployWETHMocked();
    } else {
      tokens[tokenSymbol] = await deployMintableERC20([
        tokenSymbol,  // "DAI"
        tokenSymbol,  // "DAI"
        18           // decimals (or from config)
      ]);
    }
  }

  return tokens;
};
```

**Key Point:** These are **MintableERC20** contracts - test tokens that anyone can mint for free:

```typescript
await dai.mint(parseEther('20000')); // Create 20,000 DAI out of thin air!
```

**No real money, no faucets, no limits.** This makes tests fast and deterministic.

### B. Price Oracle (Lines 151-204)

This is where **token prices come from**!

```typescript
// Deploy mock oracle
const fallbackOracle = await deployPriceOracle();

// Set ETH/USD price
await fallbackOracle.setEthUsdPrice(MOCK_USD_PRICE_IN_WEI); // ETH = $5848

// Set prices for all tokens
await setInitialAssetPricesInOracle(
  ALL_ASSETS_INITIAL_PRICES,  // From helpers/constants.ts
  {
    DAI: daiAddress,
    USDC: usdcAddress,
    WETH: wethAddress,
    WBTC: wbtcAddress,
    // ... all tokens
  },
  fallbackOracle
);
```

#### The PriceOracle Contract

Location: `contracts/mocks/oracle/PriceOracle.sol`

```solidity
contract PriceOracle is IPriceOracle {
  mapping(address => uint256) prices;  // token address => price in ETH
  uint256 ethPriceUsd;

  function getAssetPrice(address _asset) external view returns (uint256) {
    return prices[_asset];  // Returns the stored price
  }

  function setAssetPrice(address _asset, uint256 _price) external {
    prices[_asset] = _price;  // Anyone can set any price!
    emit AssetPriceUpdated(_asset, _price, block.timestamp);
  }

  function setEthUsdPrice(uint256 _price) external {
    ethPriceUsd = _price;
    emit EthPriceUpdated(_price, block.timestamp);
  }
}
```

**Key Features:**
- Simple mapping: `token address → price`
- **No external dependencies** (no Chainlink, no API calls)
- **Publicly writable** - any test can change any price instantly
- Prices are in **ETH** (not USD)

#### Initial Prices

Defined in `helpers/constants.ts`:

```typescript
export const MOCK_CHAINLINK_AGGREGATORS_PRICES = {
  // All prices are in ETH terms (18 decimals)
  DAI: oneEther.multipliedBy('0.00369068412860').toFixed(),  // ~0.00369 ETH
  USDC: oneEther.multipliedBy('0.00367714136416').toFixed(), // ~0.00367 ETH
  WBTC: oneEther.multipliedBy('47.332685').toFixed(),        // ~47.33 ETH
  WETH: oneEther.toFixed(),                                  // 1 ETH (base)
  cbBTC: oneEther.multipliedBy('47.332685').toFixed(),       // ~47.33 ETH
  AAVE: oneEther.multipliedBy('0.003620948469').toFixed(),   // ~0.00362 ETH
  // ... more tokens
  USD: '5848466240000000',  // ETH/USD price (8 decimals)
};
```

**Example Calculation:**
```
ETH/USD = $5,848 (from commons.ts)
DAI/ETH = 0.00369 ETH
Therefore: DAI/USD = 0.00369 * 5848 ≈ $21.58
```

**Why prices in ETH?** Aave V2 uses ETH as the base unit for all oracle prices internally.

### C. Lending Pool & Reserves (Lines 266-280)

```typescript
await initReservesByHelper(
  reservesParams,          // Config for each token (LTV, liquidation threshold, etc.)
  allReservesAddresses,    // { DAI: 0x..., USDC: 0x..., WETH: 0x... }
  ATokenNamePrefix,        // "Aave interest bearing"
  StableDebtTokenNamePrefix,
  VariableDebtTokenNamePrefix,
  SymbolPrefix,
  admin,
  treasuryAddress,
  ZERO_ADDRESS,
  ConfigNames.Aave,
  false
);
```

**This creates for EACH token:**

1. **aToken** (e.g., aDAI) - Represents deposits, earns interest
2. **Variable Debt Token** (e.g., variableDebtDAI) - Represents variable rate borrows
3. **Stable Debt Token** (e.g., stableDebtDAI) - Represents stable rate borrows

**Reserve Configuration** (from `markets/aave/reservesConfigs.ts`):
```typescript
export const strategyDAI: IReserveParams = {
  strategy: rateStrategyStable,
  baseLTVAsCollateral: '7500',    // 75% LTV
  liquidationThreshold: '8000',    // 80% liquidation threshold
  liquidationBonus: '10500',       // 5% liquidation bonus
  borrowingEnabled: true,
  stableBorrowRateEnabled: true,
  reserveDecimals: '18',
  aTokenImpl: eContractid.AToken,
  reserveFactor: '1000',           // 10% reserve factor
};
```

---

## 3. The TestEnv Object

After deployment, `initializeMakeSuite()` populates the global `testEnv` object:

**Location:** `test-suites/test-aave/helpers/make-suite.ts`

```typescript
export interface TestEnv {
  deployer: SignerWithAddress;        // First account (admin)
  users: SignerWithAddress[];         // Test accounts (users[0], users[1], etc.)
  pool: LendingPool;                  // Main lending pool contract
  configurator: LendingPoolConfigurator;  // Admin config contract
  oracle: PriceOracle;                // Price oracle
  helpersContract: AaveProtocolDataProvider;  // View functions

  // Mock tokens
  dai: MintableERC20;
  usdc: MintableERC20;
  aave: MintableERC20;
  weth: WETH9Mocked;

  // aTokens
  aDai: AToken;
  aWETH: AToken;

  // Utilities
  addressesProvider: LendingPoolAddressesProvider;
  wethGateway: WETHGateway;
  uniswapLiquiditySwapAdapter: UniswapLiquiditySwapAdapter;
  // ... more contracts
}
```

**Initialization** (lines 95-159):

```typescript
export async function initializeMakeSuite() {
  const [_deployer, ...restSigners] = await getEthersSigners();

  testEnv.deployer = {
    address: await _deployer.getAddress(),
    signer: _deployer,
  };

  for (const signer of restSigners) {
    testEnv.users.push({
      signer,
      address: await signer.getAddress(),
    });
  }

  testEnv.pool = await getLendingPool();
  testEnv.oracle = await getPriceOracle();

  // Get aToken addresses from protocol data provider
  const allTokens = await testEnv.helpersContract.getAllATokens();
  const aDaiAddress = allTokens.find((aToken) => aToken.symbol === 'aDAI')?.tokenAddress;

  testEnv.aDai = await getAToken(aDaiAddress);

  // Get underlying token addresses
  const reservesTokens = await testEnv.helpersContract.getAllReservesTokens();
  const daiAddress = reservesTokens.find((token) => token.symbol === 'DAI')?.tokenAddress;

  testEnv.dai = await getMintableERC20(daiAddress);

  // ... repeat for all tokens
}
```

This single `testEnv` object is **shared across all test suites** within a test run.

---

## 4. The makeSuite Wrapper

Every test file wraps its tests in `makeSuite()`:

```typescript
export function makeSuite(name: string, tests: (testEnv: TestEnv) => void) {
  describe(name, () => {
    before(async () => {
      await setSnapshot();  // Save blockchain state
    });

    tests(testEnv);  // Run your tests with injected testEnv

    after(async () => {
      await revertHead();   // Restore blockchain state
    });
  });
}
```

**Snapshot Mechanism:**
- `setSnapshot()` - Saves current blockchain state (balances, contract storage, etc.)
- `revertHead()` - Restores to the snapshot

**Why?** Each test suite runs with a **clean slate**. Changes in one suite don't affect others.

**Example Usage:**

```typescript
import { makeSuite } from './helpers/make-suite.js';

makeSuite('AToken: Permit', (testEnv: TestEnv) => {
  // testEnv is automatically injected

  it('Get aDAI for tests', async () => {
    const { dai, pool, deployer } = testEnv;

    await dai.mint(parseEther('20000'));
    await dai.approve(pool.address, parseEther('20000'));
    await pool.deposit(dai.address, parseEther('20000'), deployer.address, 0);
  });

  it('Submit a permit', async () => {
    // State from previous test is preserved within this suite
    const { aDai } = testEnv;
    expect(await aDai.balanceOf(deployer.address)).to.equal(parseEther('20000'));
  });
});

// After this suite completes, blockchain reverts to pre-suite state
```

---

## 5. How the aToken Permit Test Works

**File:** `test-suites/test-aave/atoken-permit.spec.ts`

```typescript
makeSuite('AToken: Permit', (testEnv: TestEnv) => {
  it('Get aDAI for tests', async () => {
    const { dai, pool, deployer } = testEnv;

    // STEP 1: Mint 20,000 DAI (free test tokens)
    await dai.mint(parseEther('20000'));
    // deployer.balance(DAI) = 20,000

    // STEP 2: Approve the pool to spend DAI
    await dai.approve(getContractAddress(pool), parseEther('20000'));
    // pool.allowance(deployer, DAI) = 20,000

    // STEP 3: Deposit DAI → receive aDAI
    await pool.deposit(
      getContractAddress(dai),    // asset
      parseEther('20000'),         // amount
      deployer.address,            // onBehalfOf
      0                            // referralCode
    );

    // NOW:
    // - deployer.balance(DAI) = 0
    // - deployer.balance(aDAI) = 20,000
    // - pool holds 20,000 DAI
  });

  it('Reverts submitting a permit with 0 expiration', async () => {
    const { aDai, deployer, users } = testEnv;
    const spender = users[1];

    // Build EIP-2612 permit signature
    const permitAmount = parseEther('2').toString();
    const msgParams = buildPermitParams(
      chainId,
      getContractAddress(aDai),
      '1',  // version
      await aDai.name(),
      deployer.address,
      spender.address,
      nonce,
      permitAmount,
      0  // expiration = 0 (invalid!)
    );

    const { v, r, s } = getSignatureFromTypedData(ownerPrivateKey, msgParams);

    // Attempt permit with 0 expiration - should revert
    await expect(
      aDai.connect(spender.signer).permit(
        deployer.address,
        spender.address,
        permitAmount,
        0,  // expiration
        v, r, s
      )
    ).to.be.revertedWith('INVALID_EXPIRATION');
  });
});
```

### What Happens During Deposit

**LendingPool.deposit() flow:**

1. **Transfer tokens in:**
   ```solidity
   IERC20(asset).transferFrom(msg.sender, aToken, amount);
   ```
   - DAI moves from deployer → aDAI contract

2. **Mint aTokens:**
   ```solidity
   IAToken(aToken).mint(onBehalfOf, amount, reserve.liquidityIndex);
   ```
   - aDAI minted to deployer (1:1 ratio initially)

3. **Update reserve state:**
   ```solidity
   reserve.updateState();
   reserve.updateInterestRates(asset, aToken, amount, 0);
   ```
   - Interest accrual begins

**Result:**
- deployer now has 20,000 aDAI
- aDAI balance grows over time as interest accrues
- Can be redeemed 1:1 for underlying DAI (plus interest)

---

## 6. How Prices Work in Tests

### Reading Prices

The lending pool reads prices from the oracle:

```solidity
uint256 assetPrice = IPriceOracle(oracle).getAssetPrice(asset);
```

### Changing Prices (For Liquidation Tests)

Tests manipulate the oracle to trigger liquidations:

```typescript
// Example from liquidation tests
const { dai, weth, pool, oracle, users } = testEnv;
const borrower = users[1];

// 1. User deposits ETH as collateral
await weth.connect(borrower.signer).mint(parseEther('10'));
await weth.connect(borrower.signer).approve(pool.address, parseEther('10'));
await pool.connect(borrower.signer).deposit(
  weth.address,
  parseEther('10'),
  borrower.address,
  0
);
// borrower has 10 aWETH

// 2. User borrows DAI
await pool.connect(borrower.signer).borrow(
  dai.address,
  parseEther('5000'),
  2,  // variable rate
  0,
  borrower.address
);
// borrower has 5000 DAI debt

// 3. DROP THE PRICE to make user under-collateralized
await oracle.setAssetPrice(weth.address, parseEther('0.5'));
// ETH was 1 ETH, now 0.5 ETH → user's collateral value dropped 50%!

// Before: 10 WETH * 1 ETH = 10 ETH collateral
// After:  10 WETH * 0.5 ETH = 5 ETH collateral
// Debt:   5000 DAI * 0.00369 ETH = 18.45 ETH
// Health Factor < 1 → LIQUIDATABLE!

// 4. Now liquidate
const liquidator = users[2];
await dai.connect(liquidator.signer).mint(parseEther('2500'));
await dai.connect(liquidator.signer).approve(pool.address, parseEther('2500'));

await pool.connect(liquidator.signer).liquidationCall(
  weth.address,         // collateral to seize
  dai.address,          // debt to repay
  borrower.address,     // user to liquidate
  parseEther('2500'),   // debt amount to cover
  false                 // receiveAToken
);

// Liquidator pays 2500 DAI, receives WETH collateral + 5% bonus
```

### Calculating Health Factor

```typescript
const userAccountData = await pool.getUserAccountData(user.address);

// Returns:
// - totalCollateralETH: Sum of (collateral * price * liquidationThreshold)
// - totalDebtETH: Sum of (debt * price)
// - availableBorrowsETH: How much more can be borrowed
// - currentLiquidationThreshold: Weighted average threshold
// - ltv: Weighted average LTV
// - healthFactor: (totalCollateralETH / totalDebtETH)

if (userAccountData.healthFactor < parseEther('1')) {
  // User can be liquidated!
}
```

---

## 7. Key Differences in Bitmor

### Standard Aave Tests

Users can deposit directly:

```typescript
await pool.deposit(dai.address, amount, user.address, 0);  // ✅ Works in Aave
```

### Bitmor Tests

This fails with **Error 85: LP_CALLER_NOT_VAULT**

**Why?** `contracts/protocol/lendingpool/LendingPool.sol:117`

```solidity
function deposit(
  address asset,
  uint256 amount,
  address onBehalfOf,
  uint16 referralCode
) external override whenNotPaused {
  // BITMOR CHANGE: Only vault can deposit
  require(msg.sender == usdcVaultAddress, Errors.LP_CALLER_NOT_VAULT);

  // ... rest of deposit logic
}
```

### Solution: Vault Helper Pattern

**Future implementation** (from TEST_CONTEXT.md):

```typescript
// test-suites/test-aave/helpers/vault-helpers.ts
export async function depositViaVault(
  asset: string,
  amount: BigNumber,
  poolAddress: string,
  testEnv: TestEnv
): Promise<void> {
  const { usdcVault, users } = testEnv;
  const depositor = users[0];

  // Mint asset to depositor
  await asset.connect(depositor.signer).mint(amount);

  // Approve vault
  await asset.connect(depositor.signer).approve(usdcVault.address, amount);

  // Deposit via vault (vault will call pool.deposit)
  await usdcVault.connect(depositor.signer).deposit(asset, amount, depositor.address);
}

// Usage in tests:
await depositViaVault(dai.address, parseEther('20000'), pool.address, testEnv);
```

### Bitmor Liquidation Differences

Standard Aave liquidates **user addresses**:

```typescript
await pool.liquidationCall(collateral, debt, borrower.address, amount, false);
```

Bitmor liquidates **LSA (Loan Smart Account) addresses**:

```typescript
// 1. Create loan to get LSA address
const lsa = await createBitmorLoan({
  user: borrower,
  depositAmount: parseUnits('10000', 6),  // USDC
  collateralAmount: parseUnits('0.5', 8),  // cbBTC
  duration: 12,  // months
});

// 2. Drop health factor
await dropHealthFactor(lsa, parseEther('0.8'), testEnv);

// 3. Check liquidation type
const liquidationType = await pool.checkTypeOfLiquidation(lsa);
// 0 = No liquidation
// 1 = Full liquidation
// 2 = Micro liquidation

// 4. Liquidate the LSA (not the user!)
await pool.liquidationCall(
  cbBTC.address,
  usdc.address,
  lsa,  // ← LSA address, NOT borrower.address!
  maxUint256,
  false
);
```

---

## 8. Complete Flow Diagram

```
npm test
  │
  ├─► test-suites/test-aave/__setup.spec.ts
  │     │
  │     └─► before() hook (runs ONCE)
  │           │
  │           ├─► buildTestEnv()
  │           │     │
  │           │     ├─► Deploy mock tokens
  │           │     │     ├─► DAI (MintableERC20, 18 decimals)
  │           │     │     ├─► USDC (MintableERC20, 6 decimals)
  │           │     │     ├─► WETH (WETH9Mocked, 18 decimals)
  │           │     │     ├─► WBTC (MintableERC20, 8 decimals)
  │           │     │     └─► ... more tokens
  │           │     │
  │           │     ├─► Deploy PriceOracle
  │           │     │     ├─► setEthUsdPrice($5848)
  │           │     │     └─► Set initial prices for all tokens
  │           │     │
  │           │     ├─► Deploy LendingPool
  │           │     │     ├─► LendingPoolAddressesProvider
  │           │     │     ├─► LendingPool implementation
  │           │     │     ├─► LendingPoolConfigurator
  │           │     │     └─► LendingPoolCollateralManager
  │           │     │
  │           │     ├─► Deploy aTokens
  │           │     │     ├─► aDai (AToken for DAI)
  │           │     │     ├─► aUSDC (AToken for USDC)
  │           │     │     ├─► aWETH (AToken for WETH)
  │           │     │     └─► ... more aTokens
  │           │     │
  │           │     ├─► Initialize reserves
  │           │     │     └─► Set LTV, liquidation threshold, interest rates
  │           │     │
  │           │     └─► Deploy adapters & utilities
  │           │           ├─► UniswapLiquiditySwapAdapter
  │           │           ├─► FlashLiquidationAdapter
  │           │           └─► WETHGateway
  │           │
  │           └─► initializeMakeSuite()
  │                 └─► Populate testEnv with deployed contracts
  │
  ├─► test-suites/test-aave/atoken-permit.spec.ts
  │     │
  │     └─► makeSuite('AToken: Permit', (testEnv) => {
  │           │
  │           ├─► before(): setSnapshot()
  │           │     └─► Save blockchain state
  │           │
  │           ├─► it('Get aDAI for tests')
  │           │     ├─► dai.mint(20000)
  │           │     ├─► dai.approve(pool)
  │           │     └─► pool.deposit(dai)
  │           │
  │           ├─► it('Reverts with 0 expiration')
  │           │     └─► Test permit edge case
  │           │
  │           ├─► it('Submits with max expiration')
  │           │     └─► Test valid permit
  │           │
  │           └─► after(): revertHead()
  │                 └─► Restore blockchain state
  │
  ├─► test-suites/test-aave/liquidation-atoken.spec.ts
  │     │
  │     └─► makeSuite('LendingPool: Liquidation', (testEnv) => {
  │           │
  │           ├─► before(): setSnapshot()
  │           │
  │           ├─► it('Liquidates with aToken')
  │           │     ├─► User deposits WETH
  │           │     ├─► User borrows DAI
  │           │     ├─► oracle.setAssetPrice(WETH, lower)
  │           │     └─► Liquidator liquidates user
  │           │
  │           └─► after(): revertHead()
  │
  └─► ... more test files
```

---

## 9. Common Test Patterns

### Pattern 1: Mint → Approve → Deposit

```typescript
it('User deposits DAI', async () => {
  const { dai, pool, users } = testEnv;
  const user = users[0];
  const amount = parseEther('10000');

  // 1. Mint tokens
  await dai.connect(user.signer).mint(amount);

  // 2. Approve pool
  await dai.connect(user.signer).approve(pool.address, amount);

  // 3. Deposit
  await pool.connect(user.signer).deposit(
    dai.address,
    amount,
    user.address,
    0
  );

  // Verify
  const aDaiBalance = await testEnv.aDai.balanceOf(user.address);
  expect(aDaiBalance).to.equal(amount);
});
```

### Pattern 2: Deposit → Borrow

```typescript
it('User borrows DAI against WETH', async () => {
  const { dai, weth, pool, users } = testEnv;
  const user = users[0];

  // 1. Deposit collateral
  await weth.connect(user.signer).mint(parseEther('10'));
  await weth.connect(user.signer).approve(pool.address, parseEther('10'));
  await pool.connect(user.signer).deposit(
    weth.address,
    parseEther('10'),
    user.address,
    0
  );

  // 2. Borrow
  const borrowAmount = parseEther('5000');
  await pool.connect(user.signer).borrow(
    dai.address,
    borrowAmount,
    2,  // variable rate
    0,
    user.address
  );

  // Verify
  const daiBalance = await dai.balanceOf(user.address);
  expect(daiBalance).to.equal(borrowAmount);
});
```

### Pattern 3: Drop Price → Liquidate

```typescript
it('Liquidates user after price drop', async () => {
  const { dai, weth, pool, oracle, users } = testEnv;
  const borrower = users[0];
  const liquidator = users[1];

  // 1. Setup: borrower deposits & borrows
  await weth.connect(borrower.signer).mint(parseEther('10'));
  await weth.connect(borrower.signer).approve(pool.address, parseEther('10'));
  await pool.connect(borrower.signer).deposit(weth.address, parseEther('10'), borrower.address, 0);

  await pool.connect(borrower.signer).borrow(dai.address, parseEther('5000'), 2, 0, borrower.address);

  // 2. Drop WETH price
  await oracle.setAssetPrice(weth.address, parseEther('0.5'));

  // 3. Check health factor
  const userAccountData = await pool.getUserAccountData(borrower.address);
  expect(userAccountData.healthFactor).to.be.lt(parseEther('1'));

  // 4. Liquidator repays debt
  await dai.connect(liquidator.signer).mint(parseEther('2500'));
  await dai.connect(liquidator.signer).approve(pool.address, parseEther('2500'));

  await pool.connect(liquidator.signer).liquidationCall(
    weth.address,
    dai.address,
    borrower.address,
    parseEther('2500'),
    false
  );

  // Verify liquidator received collateral
  const liquidatorWethBalance = await weth.balanceOf(liquidator.address);
  expect(liquidatorWethBalance).to.be.gt(0);
});
```

### Pattern 4: Time Travel

```typescript
it('Accrues interest over time', async () => {
  const { dai, pool, users } = testEnv;
  const user = users[0];

  // 1. Deposit DAI
  await dai.connect(user.signer).mint(parseEther('10000'));
  await dai.connect(user.signer).approve(pool.address, parseEther('10000'));
  await pool.connect(user.signer).deposit(dai.address, parseEther('10000'), user.address, 0);

  const initialBalance = await testEnv.aDai.balanceOf(user.address);

  // 2. Time travel 1 year
  await network.provider.send("evm_increaseTime", [365 * 24 * 60 * 60]);
  await network.provider.send("evm_mine");

  // 3. Check accrued interest
  const finalBalance = await testEnv.aDai.balanceOf(user.address);
  expect(finalBalance).to.be.gt(initialBalance);
});
```

---

## 10. Debugging Tips

### View Current Prices

```typescript
const daiPrice = await oracle.getAssetPrice(dai.address);
console.log('DAI price:', formatEther(daiPrice), 'ETH');
```

### View User Account Data

```typescript
const data = await pool.getUserAccountData(user.address);
console.log('Total collateral (ETH):', formatEther(data.totalCollateralETH));
console.log('Total debt (ETH):', formatEther(data.totalDebtETH));
console.log('Health factor:', formatEther(data.healthFactor));
console.log('LTV:', data.ltv.toString());
console.log('Liquidation threshold:', data.currentLiquidationThreshold.toString());
```

### View Reserve Data

```typescript
const reserveData = await pool.getReserveData(dai.address);
console.log('aToken address:', reserveData.aTokenAddress);
console.log('Liquidity rate:', reserveData.currentLiquidityRate.toString());
console.log('Borrow rate (variable):', reserveData.currentVariableBorrowRate.toString());
console.log('Borrow rate (stable):', reserveData.currentStableBorrowRate.toString());
```

### Check Token Balances

```typescript
console.log('DAI balance:', formatEther(await dai.balanceOf(user.address)));
console.log('aDAI balance:', formatEther(await testEnv.aDai.balanceOf(user.address)));
```

---

## 11. Summary

| Component | Purpose | Key Details |
|-----------|---------|-------------|
| **Mock Tokens** | ERC20s for testing | Unlimited minting, no real value |
| **PriceOracle** | Provides token prices | Simple mapping, publicly writable |
| **TestEnv** | Shared test state | All deployed contracts, users, tokens |
| **makeSuite** | Test isolation | Snapshot/revert for clean state |
| **Snapshots** | State management | Each suite starts fresh |
| **aTokens** | Deposit receipts | Minted 1:1 on deposit, earn interest |
| **Liquidations** | Under-collateral handling | Triggered by price drops |

### Key Concepts

1. **Everything is mock** - No real money, no external dependencies
2. **Prices are controllable** - Set via `oracle.setAssetPrice()`
3. **State is isolated** - Each test suite reverts after running
4. **Tokens are infinite** - Mint whatever you need with `.mint()`
5. **Time is controllable** - Use `evm_increaseTime` to fast-forward

### Bitmor-Specific

- **Vault-only deposits** - Must use vault helper, not direct `pool.deposit()`
- **LSA liquidations** - Liquidate LSA addresses, not user addresses
- **Liquidation types** - 0=none, 1=full, 2=micro
- **Insurance status** - Affects liquidation thresholds

---

## 12. Next Steps

To work with these tests:

1. **Read** `__setup.spec.ts` to see full deployment
2. **Explore** existing test files for patterns
3. **Create** vault helpers (Week 1 from TEST_CONTEXT.md)
4. **Fix** failing tests with vault deposits
5. **Write** new Bitmor-specific tests

For detailed implementation plan, see `TEST_CONTEXT.md`.

---

**Last Updated:** 2026-01-17
**Related Files:**
- `TEST_CONTEXT.md` - Implementation roadmap
- `COMPREHENSIVE-TEST-ANALYSIS.md` - Detailed test breakdown
- `test-suites/test-aave/__setup.spec.ts` - Test environment setup
- `helpers/constants.ts` - Initial prices and constants
- `contracts/mocks/oracle/PriceOracle.sol` - Mock oracle implementation
