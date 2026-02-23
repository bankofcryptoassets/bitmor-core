/**
 * Tests for LendingPool public getter functions.
 * These tests ensure coverage for simple view functions that return protocol parameters.
 */

import { makeSuite } from './helpers/make-suite.js';
import type { TestEnv } from './helpers/make-suite.js';
import chai from 'chai';

const { expect } = chai;

makeSuite('LendingPool: Getter Functions', (testEnv: TestEnv) => {
  it('paused() returns false when pool is not paused', async () => {
    const { pool } = testEnv;
    const isPaused = await pool.paused();
    expect(isPaused).to.be.equal(false);
  });

  it('paused() returns true when pool is paused', async () => {
    const { pool, configurator, users } = testEnv;

    // Pause the pool
    await configurator.connect(users[1].signer).setPoolPause(true);

    const isPaused = await pool.paused();
    expect(isPaused).to.be.equal(true);

    // Unpause the pool for other tests
    await configurator.connect(users[1].signer).setPoolPause(false);
  });

  it('MAX_STABLE_RATE_BORROW_SIZE_PERCENT() returns expected value', async () => {
    const { pool } = testEnv;
    const maxStableRateBorrowSizePercent = await pool.MAX_STABLE_RATE_BORROW_SIZE_PERCENT();
    // Default value is 2500 (25%)
    expect(maxStableRateBorrowSizePercent).to.be.equal(2500n);
  });

  it('FLASHLOAN_PREMIUM_TOTAL() returns expected value', async () => {
    const { pool } = testEnv;
    const flashLoanPremium = await pool.FLASHLOAN_PREMIUM_TOTAL();
    // Default value is 9 (0.09%)
    expect(flashLoanPremium).to.be.equal(9n);
  });

  it('MAX_NUMBER_RESERVES() returns expected value', async () => {
    const { pool } = testEnv;
    const maxNumberReserves = await pool.MAX_NUMBER_RESERVES();
    // Default value is 128
    expect(maxNumberReserves).to.be.equal(128n);
  });
});
