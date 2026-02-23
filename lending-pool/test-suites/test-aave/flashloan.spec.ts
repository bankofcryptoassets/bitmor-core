import { makeSuite } from './helpers/make-suite.js';
import type { TestEnv } from './helpers/make-suite.js';
import { getContractAddress } from '../../helpers/contracts-helpers.js';
import { parseEther } from 'ethers';
import type { MockFlashLoanReceiver } from '../../types/ethers-contracts/index.js';
import { getMockFlashLoanReceiver } from '../../helpers/contracts-getters.js';
import { depositViaVault } from "./helpers/vault-helpers.js";

import chai from 'chai';
const { expect } = chai;

makeSuite('LendingPool FlashLoan function', (testEnv: TestEnv) => {
  let _mockFlashLoanReceiver = {} as MockFlashLoanReceiver;

  before(async () => {
    _mockFlashLoanReceiver = await getMockFlashLoanReceiver();
  });

  it('Deposits WETH into the reserve for testing', async () => {
    const { weth, deployer } = testEnv;
    const amountToDeposit = parseEther('10');
    await depositViaVault(weth, amountToDeposit, deployer, testEnv);
  });

  it('Flash loans are disabled - mode 0 should revert with error 86', async () => {
    const { pool, weth } = testEnv;

    // Attempt flash loan with mode 0 (classic flash loan)
    // Expected: Revert with error code '86' (LP_FLASHLOAN_DISABLED)
    await expect(
      pool.flashLoan(
        getContractAddress(_mockFlashLoanReceiver),
        [getContractAddress(weth)],
        [parseEther('1')],
        [0],
        getContractAddress(_mockFlashLoanReceiver),
        '0x10',
        '0'
      )
    ).to.be.revertedWith('86');
  });

  it('Flash loans are disabled - mode 1 should revert with error 86', async () => {
    const { pool, weth, deployer } = testEnv;

    // Attempt flash loan with mode 1 (stable debt)
    // Expected: Revert with error code '86' (LP_FLASHLOAN_DISABLED)
    await expect(
      pool.flashLoan(
        getContractAddress(_mockFlashLoanReceiver),
        [getContractAddress(weth)],
        [parseEther('1')],
        [1],
        deployer.address,
        '0x10',
        '0'
      )
    ).to.be.revertedWith('86');
  });

  it('Flash loans are disabled - mode 2 should revert with error 86', async () => {
    const { pool, weth, deployer } = testEnv;

    // Attempt flash loan with mode 2 (variable debt)
    // Expected: Revert with error code '86' (LP_FLASHLOAN_DISABLED)
    await expect(
      pool.flashLoan(
        getContractAddress(_mockFlashLoanReceiver),
        [getContractAddress(weth)],
        [parseEther('1')],
        [2],
        deployer.address,
        '0x10',
        '0'
      )
    ).to.be.revertedWith('86');
  });
});
