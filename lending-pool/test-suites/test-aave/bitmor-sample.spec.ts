import { makeSuite } from './helpers/make-suite.js';
import type { TestEnv } from './helpers/make-suite.js';
import chai from 'chai';
const { expect } = chai;

/**
 * Bitmor Sample Tests
 *
 * NOTE: Updated to use ethers v6 patterns (.getAddress() instead of .address)
 * as part of Hardhat 3 migration. The TestEnv interface was updated to include
 * mockLoanProvider and mockBitmorUSDCVault for testing Bitmor-specific callers.
 */
makeSuite('Bitmor Sample Tests', (testEnv: TestEnv) => {
  describe('Mock Bitmor Callers', () => {
    it('MockLoanProvider should be deployed', async () => {
      const { mockLoanProvider } = testEnv;
      // ethers v6: use getAddress() instead of .address
      const addr = await mockLoanProvider.getAddress();
      expect(addr).to.not.equal('0x0000000000000000000000000000000000000000');
    });

    it('MockUSDCVault should be deployed', async () => {
      const { mockBitmorUSDCVault } = testEnv;
      // ethers v6: use getAddress() instead of .address
      const addr = await mockBitmorUSDCVault.getAddress();
      expect(addr).to.not.equal('0x0000000000000000000000000000000000000000');
    });

    it('MockLoanProvider should reference the correct pool', async () => {
      const { mockLoanProvider, pool } = testEnv;
      const poolAddress = await mockLoanProvider.pool();
      // ethers v6: use getAddress() instead of .address
      const expectedPoolAddress = await pool.getAddress();
      expect(poolAddress).to.equal(expectedPoolAddress);
    });

    it('MockUSDCVault should reference the correct pool', async () => {
      const { mockBitmorUSDCVault, pool } = testEnv;
      const poolAddress = await mockBitmorUSDCVault.getLendingPool();
      // ethers v6: use getAddress() instead of .address
      const expectedPoolAddress = await pool.getAddress();
      expect(poolAddress).to.equal(expectedPoolAddress);
    });
  });
});
