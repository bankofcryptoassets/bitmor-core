import { makeSuite } from './helpers/make-suite.js';
import type { TestEnv } from './helpers/make-suite.js';
import { APPROVAL_AMOUNT_LENDING_POOL, RAY } from '../../helpers/constants.js';
import {convertToCurrencyDecimals,
  getContractAddress} from '../../helpers/contracts-helpers.js';
import { ProtocolErrors } from '../../helpers/types.js';
import { strategyWETH } from '../../markets/aave/reservesConfigs.js';
import { depositViaVault } from './helpers/vault-helpers.js';
import { deployDefaultReserveInterestRateStrategy } from '../../helpers/contracts-deployments.js';
import { rateStrategyStableTwo } from '../../markets/aave/rateStrategies.js';

import { expect } from 'chai';

makeSuite('LendingPoolConfigurator', (testEnv: TestEnv) => {
  const {
    CALLER_NOT_POOL_ADMIN,
    LPC_RESERVE_LIQUIDITY_NOT_0,
    RC_INVALID_LTV,
    RC_INVALID_LIQ_THRESHOLD,
    RC_INVALID_LIQ_BONUS,
    RC_INVALID_DECIMALS,
    RC_INVALID_RESERVE_FACTOR,
  } = ProtocolErrors;

  it('Reverts trying to set an invalid reserve factor', async () => {
    const { configurator, weth } = testEnv;

    const invalidReserveFactor = 65536;

    await expect(
      configurator.setReserveFactor(getContractAddress(weth), invalidReserveFactor)
    ).to.be.revertedWith(RC_INVALID_RESERVE_FACTOR);
  });

  it('Deactivates the ETH reserve', async () => {
    const { configurator, weth, helpersContract } = testEnv;
    await configurator.deactivateReserve(getContractAddress(weth));
    const { isActive } = await helpersContract.getReserveConfigurationData(getContractAddress(weth));
    expect(isActive).to.be.equal(false);
  });

  it('Rectivates the ETH reserve', async () => {
    const { configurator, weth, helpersContract } = testEnv;
    await configurator.activateReserve(getContractAddress(weth));

    const { isActive } = await helpersContract.getReserveConfigurationData(getContractAddress(weth));
    expect(isActive).to.be.equal(true);
  });

  it('Check the onlyAaveAdmin on deactivateReserve ', async () => {
    const { configurator, users, weth } = testEnv;
    await expect(
      configurator.connect(users[2].signer).deactivateReserve(getContractAddress(weth)),
      CALLER_NOT_POOL_ADMIN
    ).to.be.revertedWith(CALLER_NOT_POOL_ADMIN);
  });

  it('Check the onlyAaveAdmin on activateReserve ', async () => {
    const { configurator, users, weth } = testEnv;
    await expect(
      configurator.connect(users[2].signer).activateReserve(getContractAddress(weth)),
      CALLER_NOT_POOL_ADMIN
    ).to.be.revertedWith(CALLER_NOT_POOL_ADMIN);
  });

  it('Freezes the ETH reserve', async () => {
    const { configurator, weth, helpersContract } = testEnv;

    await configurator.freezeReserve(getContractAddress(weth));
    const {
      decimals,
      ltv,
      liquidationBonus,
      liquidationThreshold,
      reserveFactor,
      stableBorrowRateEnabled,
      borrowingEnabled,
      isActive,
      isFrozen,
    } = await helpersContract.getReserveConfigurationData(getContractAddress(weth));

    expect(borrowingEnabled).to.be.equal(true);
    expect(isActive).to.be.equal(true);
    expect(isFrozen).to.be.equal(true);
    expect(decimals).to.be.equal(strategyWETH.reserveDecimals);
    expect(ltv).to.be.equal(strategyWETH.baseLTVAsCollateral);
    expect(liquidationThreshold).to.be.equal(strategyWETH.liquidationThreshold);
    expect(liquidationBonus).to.be.equal(strategyWETH.liquidationBonus);
    expect(stableBorrowRateEnabled).to.be.equal(strategyWETH.stableBorrowRateEnabled);
    expect(reserveFactor).to.be.equal(strategyWETH.reserveFactor);
  });

  it('Unfreezes the ETH reserve', async () => {
    const { configurator, helpersContract, weth } = testEnv;
    await configurator.unfreezeReserve(getContractAddress(weth));

    const {
      decimals,
      ltv,
      liquidationBonus,
      liquidationThreshold,
      reserveFactor,
      stableBorrowRateEnabled,
      borrowingEnabled,
      isActive,
      isFrozen,
    } = await helpersContract.getReserveConfigurationData(getContractAddress(weth));

    expect(borrowingEnabled).to.be.equal(true);
    expect(isActive).to.be.equal(true);
    expect(isFrozen).to.be.equal(false);
    expect(decimals).to.be.equal(strategyWETH.reserveDecimals);
    expect(ltv).to.be.equal(strategyWETH.baseLTVAsCollateral);
    expect(liquidationThreshold).to.be.equal(strategyWETH.liquidationThreshold);
    expect(liquidationBonus).to.be.equal(strategyWETH.liquidationBonus);
    expect(stableBorrowRateEnabled).to.be.equal(strategyWETH.stableBorrowRateEnabled);
    expect(reserveFactor).to.be.equal(strategyWETH.reserveFactor);
  });

  it('Check the onlyAaveAdmin on freezeReserve ', async () => {
    const { configurator, users, weth } = testEnv;
    await expect(
      configurator.connect(users[2].signer).freezeReserve(getContractAddress(weth)),
      CALLER_NOT_POOL_ADMIN
    ).to.be.revertedWith(CALLER_NOT_POOL_ADMIN);
  });

  it('Check the onlyAaveAdmin on unfreezeReserve ', async () => {
    const { configurator, users, weth } = testEnv;
    await expect(
      configurator.connect(users[2].signer).unfreezeReserve(getContractAddress(weth)),
      CALLER_NOT_POOL_ADMIN
    ).to.be.revertedWith(CALLER_NOT_POOL_ADMIN);
  });

  it('Deactivates the ETH reserve for borrowing', async () => {
    const { configurator, helpersContract, weth } = testEnv;
    await configurator.disableBorrowingOnReserve(getContractAddress(weth));
    const {
      decimals,
      ltv,
      liquidationBonus,
      liquidationThreshold,
      reserveFactor,
      stableBorrowRateEnabled,
      borrowingEnabled,
      isActive,
      isFrozen,
    } = await helpersContract.getReserveConfigurationData(getContractAddress(weth));

    expect(borrowingEnabled).to.be.equal(false);
    expect(isActive).to.be.equal(true);
    expect(isFrozen).to.be.equal(false);
    expect(decimals).to.be.equal(strategyWETH.reserveDecimals);
    expect(ltv).to.be.equal(strategyWETH.baseLTVAsCollateral);
    expect(liquidationThreshold).to.be.equal(strategyWETH.liquidationThreshold);
    expect(liquidationBonus).to.be.equal(strategyWETH.liquidationBonus);
    expect(stableBorrowRateEnabled).to.be.equal(strategyWETH.stableBorrowRateEnabled);
    expect(reserveFactor).to.be.equal(strategyWETH.reserveFactor);
  });

  it('Activates the ETH reserve for borrowing', async () => {
    const { configurator, weth, helpersContract } = testEnv;
    await configurator.enableBorrowingOnReserve(getContractAddress(weth), true);
    const { variableBorrowIndex } = await helpersContract.getReserveData(getContractAddress(weth));

    const {
      decimals,
      ltv,
      liquidationBonus,
      liquidationThreshold,
      reserveFactor,
      stableBorrowRateEnabled,
      borrowingEnabled,
      isActive,
      isFrozen,
    } = await helpersContract.getReserveConfigurationData(getContractAddress(weth));

    expect(borrowingEnabled).to.be.equal(true);
    expect(isActive).to.be.equal(true);
    expect(isFrozen).to.be.equal(false);
    expect(decimals).to.be.equal(strategyWETH.reserveDecimals);
    expect(ltv).to.be.equal(strategyWETH.baseLTVAsCollateral);
    expect(liquidationThreshold).to.be.equal(strategyWETH.liquidationThreshold);
    expect(liquidationBonus).to.be.equal(strategyWETH.liquidationBonus);
    expect(stableBorrowRateEnabled).to.be.equal(strategyWETH.stableBorrowRateEnabled);
    expect(reserveFactor).to.be.equal(strategyWETH.reserveFactor);

    expect(variableBorrowIndex.toString()).to.be.equal(RAY);
  });

  it('Check the onlyAaveAdmin on disableBorrowingOnReserve ', async () => {
    const { configurator, users, weth } = testEnv;
    await expect(
      configurator.connect(users[2].signer).disableBorrowingOnReserve(getContractAddress(weth)),
      CALLER_NOT_POOL_ADMIN
    ).to.be.revertedWith(CALLER_NOT_POOL_ADMIN);
  });

  it('Check the onlyAaveAdmin on enableBorrowingOnReserve ', async () => {
    const { configurator, users, weth } = testEnv;
    await expect(
      configurator.connect(users[2].signer).enableBorrowingOnReserve(getContractAddress(weth), true),
      CALLER_NOT_POOL_ADMIN
    ).to.be.revertedWith(CALLER_NOT_POOL_ADMIN);
  });

  it('Deactivates the ETH reserve as collateral', async () => {
    const { configurator, helpersContract, weth } = testEnv;
    await configurator.configureReserveAsCollateral(getContractAddress(weth), 0, 0, 0);

    const {
      decimals,
      ltv,
      liquidationBonus,
      liquidationThreshold,
      reserveFactor,
      stableBorrowRateEnabled,
      borrowingEnabled,
      isActive,
      isFrozen,
    } = await helpersContract.getReserveConfigurationData(getContractAddress(weth));

    expect(borrowingEnabled).to.be.equal(true);
    expect(isActive).to.be.equal(true);
    expect(isFrozen).to.be.equal(false);
    expect(decimals).to.be.equal(18);
    expect(ltv).to.be.equal(0);
    expect(liquidationThreshold).to.be.equal(0);
    expect(liquidationBonus).to.be.equal(0);
    expect(stableBorrowRateEnabled).to.be.equal(true);
    expect(reserveFactor).to.be.equal(strategyWETH.reserveFactor);
  });

  it('Activates the ETH reserve as collateral', async () => {
    const { configurator, helpersContract, weth } = testEnv;
    await configurator.configureReserveAsCollateral(getContractAddress(weth), '8000', '8250', '10500');

    const {
      decimals,
      ltv,
      liquidationBonus,
      liquidationThreshold,
      reserveFactor,
      stableBorrowRateEnabled,
      borrowingEnabled,
      isActive,
      isFrozen,
    } = await helpersContract.getReserveConfigurationData(getContractAddress(weth));

    expect(borrowingEnabled).to.be.equal(true);
    expect(isActive).to.be.equal(true);
    expect(isFrozen).to.be.equal(false);
    expect(decimals).to.be.equal(strategyWETH.reserveDecimals);
    expect(ltv).to.be.equal(strategyWETH.baseLTVAsCollateral);
    expect(liquidationThreshold).to.be.equal(strategyWETH.liquidationThreshold);
    expect(liquidationBonus).to.be.equal(strategyWETH.liquidationBonus);
    expect(stableBorrowRateEnabled).to.be.equal(strategyWETH.stableBorrowRateEnabled);
    expect(reserveFactor).to.be.equal(strategyWETH.reserveFactor);
  });

  it('Check the onlyAaveAdmin on configureReserveAsCollateral ', async () => {
    const { configurator, users, weth } = testEnv;
    await expect(
      configurator
        .connect(users[2].signer)
        .configureReserveAsCollateral(getContractAddress(weth), '7500', '8000', '10500'),
      CALLER_NOT_POOL_ADMIN
    ).to.be.revertedWith(CALLER_NOT_POOL_ADMIN);
  });

  it('Disable stable borrow rate on the ETH reserve', async () => {
    const { configurator, helpersContract, weth } = testEnv;
    await configurator.disableReserveStableRate(getContractAddress(weth));
    const {
      decimals,
      ltv,
      liquidationBonus,
      liquidationThreshold,
      reserveFactor,
      stableBorrowRateEnabled,
      borrowingEnabled,
      isActive,
      isFrozen,
    } = await helpersContract.getReserveConfigurationData(getContractAddress(weth));

    expect(borrowingEnabled).to.be.equal(true);
    expect(isActive).to.be.equal(true);
    expect(isFrozen).to.be.equal(false);
    expect(decimals).to.be.equal(strategyWETH.reserveDecimals);
    expect(ltv).to.be.equal(strategyWETH.baseLTVAsCollateral);
    expect(liquidationThreshold).to.be.equal(strategyWETH.liquidationThreshold);
    expect(liquidationBonus).to.be.equal(strategyWETH.liquidationBonus);
    expect(stableBorrowRateEnabled).to.be.equal(false);
    expect(reserveFactor).to.be.equal(strategyWETH.reserveFactor);
  });

  it('Enables stable borrow rate on the ETH reserve', async () => {
    const { configurator, helpersContract, weth } = testEnv;
    await configurator.enableReserveStableRate(getContractAddress(weth));
    const {
      decimals,
      ltv,
      liquidationBonus,
      liquidationThreshold,
      reserveFactor,
      stableBorrowRateEnabled,
      borrowingEnabled,
      isActive,
      isFrozen,
    } = await helpersContract.getReserveConfigurationData(getContractAddress(weth));

    expect(borrowingEnabled).to.be.equal(true);
    expect(isActive).to.be.equal(true);
    expect(isFrozen).to.be.equal(false);
    expect(decimals).to.be.equal(strategyWETH.reserveDecimals);
    expect(ltv).to.be.equal(strategyWETH.baseLTVAsCollateral);
    expect(liquidationThreshold).to.be.equal(strategyWETH.liquidationThreshold);
    expect(liquidationBonus).to.be.equal(strategyWETH.liquidationBonus);
    expect(stableBorrowRateEnabled).to.be.equal(true);
    expect(reserveFactor).to.be.equal(strategyWETH.reserveFactor);
  });

  it('Check the onlyAaveAdmin on disableReserveStableRate', async () => {
    const { configurator, users, weth } = testEnv;
    await expect(
      configurator.connect(users[2].signer).disableReserveStableRate(getContractAddress(weth)),
      CALLER_NOT_POOL_ADMIN
    ).to.be.revertedWith(CALLER_NOT_POOL_ADMIN);
  });

  it('Check the onlyAaveAdmin on enableReserveStableRate', async () => {
    const { configurator, users, weth } = testEnv;
    await expect(
      configurator.connect(users[2].signer).enableReserveStableRate(getContractAddress(weth)),
      CALLER_NOT_POOL_ADMIN
    ).to.be.revertedWith(CALLER_NOT_POOL_ADMIN);
  });

  it('Changes the reserve factor of WETH', async () => {
    const { configurator, helpersContract, weth } = testEnv;
    await configurator.setReserveFactor(getContractAddress(weth), '1000');
    const {
      decimals,
      ltv,
      liquidationBonus,
      liquidationThreshold,
      reserveFactor,
      stableBorrowRateEnabled,
      borrowingEnabled,
      isActive,
      isFrozen,
    } = await helpersContract.getReserveConfigurationData(getContractAddress(weth));

    expect(borrowingEnabled).to.be.equal(true);
    expect(isActive).to.be.equal(true);
    expect(isFrozen).to.be.equal(false);
    expect(decimals).to.be.equal(strategyWETH.reserveDecimals);
    expect(ltv).to.be.equal(strategyWETH.baseLTVAsCollateral);
    expect(liquidationThreshold).to.be.equal(strategyWETH.liquidationThreshold);
    expect(liquidationBonus).to.be.equal(strategyWETH.liquidationBonus);
    expect(stableBorrowRateEnabled).to.be.equal(strategyWETH.stableBorrowRateEnabled);
    expect(reserveFactor).to.be.equal(1000);
  });

  it('Check the onlyLendingPoolManager on setReserveFactor', async () => {
    const { configurator, users, weth } = testEnv;
    await expect(
      configurator.connect(users[2].signer).setReserveFactor(getContractAddress(weth), '2000'),
      CALLER_NOT_POOL_ADMIN
    ).to.be.revertedWith(CALLER_NOT_POOL_ADMIN);
  });

  it('Reverts when trying to disable the DAI reserve with liquidity on it', async () => {
    // [BITMOR AUDIT NOTE - Test Adaptation for Vault-Only Deposits]
    // CHANGE: This test was modified to comply with Bitmor's architectural requirement
    // that ALL deposits must go through the USDC Vault (enforced at LendingPool.sol:117).
    //
    // BEFORE: Direct user deposits were used: pool.deposit(asset, amount, userAddress, '0')
    // ERROR: This would fail with error code 85 (LP_CALLER_NOT_VAULT) because direct
    //        deposits to the pool are prohibited in Bitmor.
    //
    // AFTER: Using depositViaVault() helper which:
    // 1. Accepts the actual ERC20 token contract (not address string)
    // 2. Accepts a SignerWithAddress user object (not plain address string)
    // 3. Routes deposit through the vault as required by Bitmor
    //
    // IMPACT: This is NOT a bug fix - it's a design adaptation. The test still validates
    //         the same business logic (cannot disable reserve with liquidity), just with
    //         Bitmor's required deposit mechanism.
    
    const { dai, pool, configurator, users } = testEnv;
    const user = users[0]; // Use actual user signer, not pool address
    await dai.mint(await convertToCurrencyDecimals(getContractAddress(dai), '1000'));

    //approve protocol to access depositor wallet
    await dai.approve(getContractAddress(pool), APPROVAL_AMOUNT_LENDING_POOL);
    const amountDAItoDeposit = await convertToCurrencyDecimals(getContractAddress(dai), '1000');

    //user 1 deposits 1000 DAI via vault
    await depositViaVault(dai, amountDAItoDeposit, user, testEnv);
    

    await expect(
      configurator.deactivateReserve(getContractAddress(dai)),
      LPC_RESERVE_LIQUIDITY_NOT_0
    ).to.be.revertedWith(LPC_RESERVE_LIQUIDITY_NOT_0);
  });

  it('Changes the interest rate strategy of bvBTC', async () => {
    const { configurator, pool, btcVault, addressesProvider } = testEnv;

    // Deploy a new interest rate strategy
    const newStrategy = await deployDefaultReserveInterestRateStrategy(
      [
        getContractAddress(addressesProvider),
        rateStrategyStableTwo.optimalUtilizationRate,
        rateStrategyStableTwo.baseVariableBorrowRate,
        rateStrategyStableTwo.variableRateSlope1,
        rateStrategyStableTwo.variableRateSlope2,
        rateStrategyStableTwo.stableRateSlope1,
        rateStrategyStableTwo.stableRateSlope2,
      ],
      false
    );

    // Get the old strategy address
    const reserveDataBefore = await pool.getReserveData(getContractAddress(btcVault));
    const oldStrategyAddress = reserveDataBefore.interestRateStrategyAddress;

    // Set the new strategy
    await configurator.setReserveInterestRateStrategyAddress(
      getContractAddress(btcVault),
      getContractAddress(newStrategy)
    );

    // Verify the strategy was changed
    const reserveDataAfter = await pool.getReserveData(getContractAddress(btcVault));
    expect(reserveDataAfter.interestRateStrategyAddress).to.be.equal(
      getContractAddress(newStrategy),
      'Interest rate strategy was not updated'
    );
    expect(reserveDataAfter.interestRateStrategyAddress).to.not.equal(
      oldStrategyAddress,
      'Interest rate strategy should have changed'
    );
  });

  it('Check the onlyPoolAdmin on setReserveInterestRateStrategyAddress', async () => {
    const { configurator, users, btcVault, addressesProvider } = testEnv;

    // Deploy a new strategy for the test
    const newStrategy = await deployDefaultReserveInterestRateStrategy(
      [
        getContractAddress(addressesProvider),
        rateStrategyStableTwo.optimalUtilizationRate,
        rateStrategyStableTwo.baseVariableBorrowRate,
        rateStrategyStableTwo.variableRateSlope1,
        rateStrategyStableTwo.variableRateSlope2,
        rateStrategyStableTwo.stableRateSlope1,
        rateStrategyStableTwo.stableRateSlope2,
      ],
      false
    );

    await expect(
      configurator
        .connect(users[2].signer)
        .setReserveInterestRateStrategyAddress(getContractAddress(btcVault), getContractAddress(newStrategy)),
      CALLER_NOT_POOL_ADMIN
    ).to.be.revertedWith(CALLER_NOT_POOL_ADMIN);
  });
});
