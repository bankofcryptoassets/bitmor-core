import { makeSuite, TestEnv } from './helpers/make-suite.js';
import { expect } from 'chai';

makeSuite('Bitmor Sample Tests', (testEnv: TestEnv) => {
  describe('Mock Bitmor Callers', () => {
    it('MockLoanProvider should be deployed', async () => {
      const { mockLoanProvider } = testEnv;
      expect(mockLoanProvider.address).to.not.equal(
        '0x0000000000000000000000000000000000000000'
      );
    });

    it('MockUSDCVault should be deployed', async () => {
      const { mockBitmorUSDCVault } = testEnv;
      expect(mockBitmorUSDCVault.address).to.not.equal(
        '0x0000000000000000000000000000000000000000'
      );
    });

    it('MockLoanProvider should reference the correct pool', async () => {
      const { mockLoanProvider, pool } = testEnv;
      const poolAddress = await mockLoanProvider.pool();
      expect(poolAddress).to.equal(pool.address);
    });

    it('MockUSDCVault should reference the correct pool', async () => {
      const { mockBitmorUSDCVault, pool } = testEnv;
      const poolAddress = await mockBitmorUSDCVault.pool();
      expect(poolAddress).to.equal(pool.address);
    });
  });
});
