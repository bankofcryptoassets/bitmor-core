import { makeSuite } from './helpers/make-suite.js';
import type { TestEnv } from './helpers/make-suite.js';
import { deployUSDCReserveInterestRateStrategy } from '../../helpers/contracts-deployments.js';
import { getContractAddress } from '../../helpers/contracts-helpers.js';

import { PERCENTAGE_FACTOR, RAY } from '../../helpers/constants.js';

import { rateStrategyStableThree } from '../../markets/aave/rateStrategies.js';

import { strategyUSDC } from '../../markets/aave/reservesConfigs.js';
import type { USDCReserveInterestRateStrategy } from '../../types/ethers-contracts/index.js';
import BigNumber from 'bignumber.js';

import './helpers/utils/math';

import { expect } from 'chai';

makeSuite('USDCReserveInterestRateStrategy tests', (testEnv: TestEnv) => {
  let strategyInstance: USDCReserveInterestRateStrategy;

  before(async () => {
    const { addressesProvider, usdc, mockBitmorUSDCVault } = testEnv;

    // Set the USDC vault in addresses provider so strategy can find it
    await addressesProvider.setUSDCVault(getContractAddress(mockBitmorUSDCVault));

    // Deploy the USDC rate strategy
    strategyInstance = await deployUSDCReserveInterestRateStrategy(
      [
        getContractAddress(addressesProvider),
        rateStrategyStableThree.optimalUtilizationRate,
        rateStrategyStableThree.baseVariableBorrowRate,
        rateStrategyStableThree.variableRateSlope1,
        rateStrategyStableThree.variableRateSlope2,
        rateStrategyStableThree.stableRateSlope1,
        rateStrategyStableThree.stableRateSlope2,
      ],
      false
    );
  });

  // ============ GETTER FUNCTION TESTS ============

  it('variableRateSlope1() returns correct value', async () => {
    const slope1 = await strategyInstance.variableRateSlope1();
    expect(slope1.toString()).to.be.equal(
      rateStrategyStableThree.variableRateSlope1,
      'Invalid variableRateSlope1'
    );
  });

  it('variableRateSlope2() returns correct value', async () => {
    const slope2 = await strategyInstance.variableRateSlope2();
    expect(slope2.toString()).to.be.equal(
      rateStrategyStableThree.variableRateSlope2,
      'Invalid variableRateSlope2'
    );
  });

  it('stableRateSlope1() returns correct value', async () => {
    const slope1 = await strategyInstance.stableRateSlope1();
    expect(slope1.toString()).to.be.equal(
      rateStrategyStableThree.stableRateSlope1,
      'Invalid stableRateSlope1'
    );
  });

  it('stableRateSlope2() returns correct value', async () => {
    const slope2 = await strategyInstance.stableRateSlope2();
    expect(slope2.toString()).to.be.equal(
      rateStrategyStableThree.stableRateSlope2,
      'Invalid stableRateSlope2'
    );
  });

  it('baseVariableBorrowRate() returns correct value', async () => {
    const baseRate = await strategyInstance.baseVariableBorrowRate();
    expect(baseRate.toString()).to.be.equal(
      rateStrategyStableThree.baseVariableBorrowRate,
      'Invalid baseVariableBorrowRate'
    );
  });

  it('getMaxVariableBorrowRate() returns sum of base + slope1 + slope2', async () => {
    const maxRate = await strategyInstance.getMaxVariableBorrowRate();
    const expectedMaxRate = new BigNumber(rateStrategyStableThree.baseVariableBorrowRate)
      .plus(rateStrategyStableThree.variableRateSlope1)
      .plus(rateStrategyStableThree.variableRateSlope2);

    expect(maxRate.toString()).to.be.equal(expectedMaxRate.toFixed(0), 'Invalid maxVariableBorrowRate');
  });

  it('OPTIMAL_UTILIZATION_RATE returns correct value', async () => {
    const optimalRate = await strategyInstance.OPTIMAL_UTILIZATION_RATE();
    expect(optimalRate.toString()).to.be.equal(
      rateStrategyStableThree.optimalUtilizationRate,
      'Invalid OPTIMAL_UTILIZATION_RATE'
    );
  });

  it('EXCESS_UTILIZATION_RATE returns 1 - optimal', async () => {
    const excessRate = await strategyInstance.EXCESS_UTILIZATION_RATE();
    const expectedExcess = new BigNumber(RAY).minus(rateStrategyStableThree.optimalUtilizationRate);

    expect(excessRate.toString()).to.be.equal(expectedExcess.toFixed(0), 'Invalid EXCESS_UTILIZATION_RATE');
  });

  // ============ CALCULATE INTEREST RATES TESTS (6-param version) ============

  it('Checks rates at 0% utilization rate, empty reserve', async () => {
    const { dai } = testEnv;

    const {
      0: currentLiquidityRate,
      1: currentStableBorrowRate,
      2: currentVariableBorrowRate,
    } = await strategyInstance['calculateInterestRates(address,uint256,uint256,uint256,uint256,uint256)'](
      getContractAddress(dai), // reserve address (not USDC to avoid "WA" check)
      '1000000000000000000', // totalAssets (1 token in wei)
      0, // totalStableDebt
      0, // totalVariableDebt
      0, // averageStableBorrowRate
      strategyUSDC.reserveFactor
    );

    expect(currentLiquidityRate.toString()).to.be.equal('0', 'Invalid liquidity rate');
    expect(currentVariableBorrowRate.toString()).to.be.equal(
      rateStrategyStableThree.baseVariableBorrowRate,
      'Invalid variable rate'
    );
  });

  it('Checks rates at 90% utilization rate (optimal)', async () => {
    const { dai } = testEnv;

    // 90% utilization: totalAssets includes totalDebt (vault semantics)
    // U = totalDebt / totalAssets = 0.9 / 1.0 = 0.9
    const totalAssets = '1000000000000000000'; // 1.0 token (idle + borrowed)
    const totalVariableDebt = '900000000000000000'; // 0.9 token

    const {
      0: currentLiquidityRate,
      1: currentStableBorrowRate,
      2: currentVariableBorrowRate,
    } = await strategyInstance['calculateInterestRates(address,uint256,uint256,uint256,uint256,uint256)'](
      getContractAddress(dai),
      totalAssets,
      '0', // totalStableDebt
      totalVariableDebt,
      '0', // averageStableBorrowRate
      strategyUSDC.reserveFactor
    );

    // At optimal utilization (90%), variable rate = base + slope1
    const expectedVariableRate = new BigNumber(rateStrategyStableThree.baseVariableBorrowRate).plus(
      rateStrategyStableThree.variableRateSlope1
    );

    expect(currentVariableBorrowRate.toString()).to.be.equal(
      expectedVariableRate.toFixed(0),
      'Invalid variable rate at optimal utilization'
    );

    // Liquidity rate = variable rate * utilization * (1 - reserveFactor)
    const expectedLiquidityRate = expectedVariableRate
      .times(0.9)
      .percentMul(new BigNumber(PERCENTAGE_FACTOR).minus(strategyUSDC.reserveFactor));

    expect(currentLiquidityRate.toString()).to.be.equal(
      expectedLiquidityRate.toFixed(0),
      'Invalid liquidity rate'
    );
  });

  it('Checks rates at 100% utilization rate (above optimal)', async () => {
    const { dai } = testEnv;

    // 100% utilization: totalAssets = 0 with outstanding debt
    // When totalAssets == 0 and totalDebt > 0, utilization is capped at 100%
    const totalAssets = '0';
    const totalVariableDebt = '1000000000000000000'; // 1 token

    const {
      0: currentLiquidityRate,
      1: currentStableBorrowRate,
      2: currentVariableBorrowRate,
    } = await strategyInstance['calculateInterestRates(address,uint256,uint256,uint256,uint256,uint256)'](
      getContractAddress(dai),
      totalAssets,
      '0', // totalStableDebt
      totalVariableDebt,
      '0', // averageStableBorrowRate
      strategyUSDC.reserveFactor
    );

    // At 100% utilization, variable rate = base + slope1 + slope2
    const expectedVariableRate = new BigNumber(rateStrategyStableThree.baseVariableBorrowRate)
      .plus(rateStrategyStableThree.variableRateSlope1)
      .plus(rateStrategyStableThree.variableRateSlope2);

    expect(currentVariableBorrowRate.toString()).to.be.equal(
      expectedVariableRate.toFixed(0),
      'Invalid variable rate at 100% utilization'
    );

    // Liquidity rate at 100% utilization
    const expectedLiquidityRate = expectedVariableRate.percentMul(
      new BigNumber(PERCENTAGE_FACTOR).minus(strategyUSDC.reserveFactor)
    );

    expect(currentLiquidityRate.toString()).to.be.equal(
      expectedLiquidityRate.toFixed(0),
      'Invalid liquidity rate at 100% utilization'
    );
  });

  it('Checks rates at 45% utilization rate (below optimal)', async () => {
    const { dai } = testEnv;

    // 45% utilization: totalAssets includes totalDebt (vault semantics)
    // U = totalDebt / totalAssets = 0.45 / 1.0 = 0.45
    const totalAssets = '1000000000000000000'; // 1.0 token (idle + borrowed)
    const totalVariableDebt = '450000000000000000'; // 0.45 token

    const {
      0: currentLiquidityRate,
      1: currentStableBorrowRate,
      2: currentVariableBorrowRate,
    } = await strategyInstance['calculateInterestRates(address,uint256,uint256,uint256,uint256,uint256)'](
      getContractAddress(dai),
      totalAssets,
      '0', // totalStableDebt
      totalVariableDebt,
      '0', // averageStableBorrowRate
      strategyUSDC.reserveFactor
    );

    // Below optimal: variable rate = base + (utilization / optimal) * slope1
    // utilization = 0.45, optimal = 0.9
    // ratio = 0.45 / 0.9 = 0.5
    // variable rate = 0 + 0.5 * 0.04 RAY = 0.02 RAY
    const utilizationRatio = new BigNumber(0.45).div(0.9);
    const expectedVariableRate = new BigNumber(rateStrategyStableThree.baseVariableBorrowRate).plus(
      new BigNumber(rateStrategyStableThree.variableRateSlope1).times(utilizationRatio)
    );

    expect(currentVariableBorrowRate.toString()).to.be.almostEqual(
      expectedVariableRate.toFixed(0),
      'Invalid variable rate below optimal'
    );
  });

  it('Checks rates with mixed stable and variable debt at 100% utilization', async () => {
    const { dai } = testEnv;

    // 50% stable, 50% variable at 100% utilization
    // totalAssets = 0 with outstanding debt triggers 100% utilization cap
    const totalAssets = '0';
    const totalStableDebt = '500000000000000000'; // 0.5 token
    const totalVariableDebt = '500000000000000000'; // 0.5 token
    const averageStableBorrowRate = new BigNumber(0.1).times(RAY).toFixed(0); // 10% avg stable rate

    const {
      0: currentLiquidityRate,
      1: currentStableBorrowRate,
      2: currentVariableBorrowRate,
    } = await strategyInstance['calculateInterestRates(address,uint256,uint256,uint256,uint256,uint256)'](
      getContractAddress(dai),
      totalAssets,
      totalStableDebt,
      totalVariableDebt,
      averageStableBorrowRate,
      strategyUSDC.reserveFactor
    );

    // Variable rate should still be base + slope1 + slope2 at 100% utilization
    const expectedVariableRate = new BigNumber(rateStrategyStableThree.baseVariableBorrowRate)
      .plus(rateStrategyStableThree.variableRateSlope1)
      .plus(rateStrategyStableThree.variableRateSlope2);

    expect(currentVariableBorrowRate.toString()).to.be.equal(
      expectedVariableRate.toFixed(0),
      'Invalid variable rate with mixed debt'
    );

    // Overall borrow rate = weighted average of variable and stable
    // = (0.5 * variableRate + 0.5 * 0.1) / 1.0
    const avgBorrowRate = new BigNumber(currentVariableBorrowRate.toString())
      .plus(averageStableBorrowRate)
      .div(2);

    const expectedLiquidityRate = avgBorrowRate.percentMul(
      new BigNumber(PERCENTAGE_FACTOR).minus(strategyUSDC.reserveFactor)
    );

    expect(currentLiquidityRate.toString()).to.be.almostEqual(
      expectedLiquidityRate.toFixed(0),
      'Invalid liquidity rate with mixed debt'
    );
  });

  // ============ CALCULATE INTEREST RATES TESTS (8-param version with vault) ============

  it('Checks 8-param calculateInterestRates uses vault totalAssets for liquidity', async () => {
    const { usdc, aUSDC, mockBitmorUSDCVault, deployer } = testEnv;

    // First deposit some USDC into the vault to give it totalAssets
    const depositAmount = '1000000000'; // 1000 USDC (6 decimals)
    await usdc.mint(depositAmount);
    await usdc.approve(getContractAddress(mockBitmorUSDCVault), depositAmount);
    await mockBitmorUSDCVault.deposit(depositAmount, deployer.address);

    // Now the vault has totalAssets = 1000 USDC
    const vaultTotalAssets = await mockBitmorUSDCVault.totalAssets();
    expect(vaultTotalAssets.toString()).to.be.equal(depositAmount, 'Vault should have deposited assets');

    // Call the 8-param version - it should use vault's totalAssets as available liquidity
    const {
      0: currentLiquidityRate,
      1: currentStableBorrowRate,
      2: currentVariableBorrowRate,
    } = await strategyInstance['calculateInterestRates(address,address,uint256,uint256,uint256,uint256,uint256,uint256)'](
      getContractAddress(usdc), // reserve
      getContractAddress(aUSDC), // aToken
      0, // liquidityAdded
      0, // liquidityTaken
      0, // totalStableDebt
      0, // totalVariableDebt
      0, // averageStableBorrowRate
      strategyUSDC.reserveFactor
    );

    // With zero debt and positive liquidity, rates should be at base level
    expect(currentLiquidityRate.toString()).to.be.equal('0', 'Invalid liquidity rate');
    expect(currentVariableBorrowRate.toString()).to.be.equal(
      rateStrategyStableThree.baseVariableBorrowRate,
      'Invalid variable rate'
    );
  });

  it('Checks 8-param version reverts when reserve does not match vault asset', async () => {
    const { dai, aDai, mockBitmorUSDCVault } = testEnv;

    // This should revert with "WA" because reserve != vault.asset()
    await expect(
      strategyInstance['calculateInterestRates(address,address,uint256,uint256,uint256,uint256,uint256,uint256)'](
        getContractAddress(dai), // reserve = DAI (differs from vault asset USDC)
        getContractAddress(aDai), // aToken
        0,
        0,
        0,
        0,
        0,
        strategyUSDC.reserveFactor
      )
    ).to.be.revertedWith('WA');
  });

  it('Checks 8-param version with liquidityAdded increases available liquidity', async () => {
    const { usdc, aUSDC, mockBitmorUSDCVault } = testEnv;

    const liquidityAdded = '500000000'; // 500 USDC worth

    const {
      0: currentLiquidityRate,
      1: currentStableBorrowRate,
      2: currentVariableBorrowRate,
    } = await strategyInstance['calculateInterestRates(address,address,uint256,uint256,uint256,uint256,uint256,uint256)'](
      getContractAddress(usdc),
      getContractAddress(aUSDC),
      liquidityAdded, // liquidityAdded
      0, // liquidityTaken
      0, // totalStableDebt
      '500000000000000000', // totalVariableDebt (0.5 token in wei)
      0, // averageStableBorrowRate
      strategyUSDC.reserveFactor
    );

    // With debt and liquidity, should calculate proper rates
    // The variable rate should be non-zero since there's utilization
    expect(BigInt(currentVariableBorrowRate.toString())).to.be.greaterThan(
      BigInt(rateStrategyStableThree.baseVariableBorrowRate),
      'Variable rate should be above base with utilization'
    );
  });

  it('Checks 8-param version with liquidityTaken decreases available liquidity', async () => {
    const { usdc, aUSDC, mockBitmorUSDCVault } = testEnv;

    // Take 500 USDC from vault (simulating a borrow)
    const liquidityTaken = '500000000'; // 500 USDC

    const {
      0: currentLiquidityRate,
      1: currentStableBorrowRate,
      2: currentVariableBorrowRate,
    } = await strategyInstance['calculateInterestRates(address,address,uint256,uint256,uint256,uint256,uint256,uint256)'](
      getContractAddress(usdc),
      getContractAddress(aUSDC),
      0, // liquidityAdded
      liquidityTaken, // liquidityTaken
      0, // totalStableDebt
      '900000000000000000', // totalVariableDebt
      0, // averageStableBorrowRate
      strategyUSDC.reserveFactor
    );

    // Higher utilization due to reduced liquidity = higher rates
    expect(BigInt(currentVariableBorrowRate.toString())).to.be.greaterThan(
      BigInt(rateStrategyStableThree.baseVariableBorrowRate),
      'Variable rate should increase with reduced liquidity'
    );
  });
});
