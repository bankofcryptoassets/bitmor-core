import { makeSuite } from './helpers/make-suite.js';
import type { TestEnv } from './helpers/make-suite.js';
import { deployUSDCReserveInterestRateStrategy } from '../../helpers/contracts-deployments.js';
import { getContractAddress } from '../../helpers/contracts-helpers.js';

import { oneRay } from '../../helpers/constants.js';

import { rateStrategyUSDC } from '../../markets/bitmor/rateStrategies.js';

import type { USDCReserveInterestRateStrategy } from '../../types/ethers-contracts/index.js';
import BigNumber from 'bignumber.js';

import { expect } from 'chai';

/**
 * Validates the Bitmor USDC rate strategy configuration against intended values.
 * Max rate = base(5%) + slope1(4%) + slope2(3%) = 12%
 */
makeSuite('Bitmor USDC Rate Configuration Tests', (testEnv: TestEnv) => {
  let strategyInstance: USDCReserveInterestRateStrategy;

  // Expected rate parameters (hardcoded, not derived from config)
  const EXPECTED_BASE_RATE = new BigNumber(0.05).multipliedBy(oneRay).toFixed();      // 5%
  const EXPECTED_SLOPE1 = new BigNumber(0.04).multipliedBy(oneRay).toFixed();          // 4%
  const EXPECTED_SLOPE2 = new BigNumber(0.03).multipliedBy(oneRay).toFixed();          // 3%
  const EXPECTED_MAX_RATE = new BigNumber(0.12).multipliedBy(oneRay).toFixed();        // 12%
  const EXPECTED_OPTIMAL_UTILIZATION = new BigNumber(0.9).multipliedBy(oneRay).toFixed(); // 90%

  before(async () => {
    const { addressesProvider, mockBitmorUSDCVault } = testEnv;

    await addressesProvider.setUSDCVault(getContractAddress(mockBitmorUSDCVault));

    strategyInstance = await deployUSDCReserveInterestRateStrategy(
      [
        getContractAddress(addressesProvider),
        rateStrategyUSDC.optimalUtilizationRate,
        rateStrategyUSDC.baseVariableBorrowRate,
        rateStrategyUSDC.variableRateSlope1,
        rateStrategyUSDC.variableRateSlope2,
        rateStrategyUSDC.stableRateSlope1,
        rateStrategyUSDC.stableRateSlope2,
      ],
      false
    );
  });

  it('baseVariableBorrowRate should be 5%', async () => {
    const baseRate = await strategyInstance.baseVariableBorrowRate();
    expect(baseRate.toString()).to.be.equal(EXPECTED_BASE_RATE, 'Base variable borrow rate should be 5%');
  });

  it('variableRateSlope1 should be 4%', async () => {
    const slope1 = await strategyInstance.variableRateSlope1();
    expect(slope1.toString()).to.be.equal(EXPECTED_SLOPE1, 'variableRateSlope1 should be 4%');
  });

  it('variableRateSlope2 should be 3% for a 12% max rate', async () => {
    const slope2 = await strategyInstance.variableRateSlope2();
    expect(slope2.toString()).to.be.equal(EXPECTED_SLOPE2, 'variableRateSlope2 should be 3%');
  });

  it('getMaxVariableBorrowRate should be 12% (base 5% + slope1 4% + slope2 3%)', async () => {
    const maxRate = await strategyInstance.getMaxVariableBorrowRate();
    expect(maxRate.toString()).to.be.equal(EXPECTED_MAX_RATE, 'Max variable borrow rate should be 12%');
  });

  it('optimalUtilizationRate should be 90%', async () => {
    const optimalRate = await strategyInstance.OPTIMAL_UTILIZATION_RATE();
    expect(optimalRate.toString()).to.be.equal(
      EXPECTED_OPTIMAL_UTILIZATION,
      'Optimal utilization rate should be 90%'
    );
  });
});
