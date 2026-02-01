import { APPROVAL_AMOUNT_LENDING_POOL, MAX_UINT_AMOUNT, ZERO_ADDRESS } from '../../helpers/constants.js';
import { convertToCurrencyDecimals, getContractAddress } from '../../helpers/contracts-helpers.js';
import chai from 'chai';
const { expect } = chai;
import { RateMode } from '../../helpers/types.js';
import { makeSuite } from './helpers/make-suite.js';
import type { TestEnv } from './helpers/make-suite.js';
import BigNumber from 'bignumber.js';
import { DRE } from '../../helpers/misc-utils.js';

makeSuite('AToken: Transfer', (testEnv: TestEnv) => {

  it('USDC Vault deposits to pool and receives aTokens', async () => {
    const { users, usdc, aUsdc, mockBitmorUSDCVault } = testEnv;

    const depositor = users[0];
    const amountUSDCtoDeposit = await convertToCurrencyDecimals(getContractAddress(usdc), '1000');

    await usdc.connect(depositor.signer).mint(amountUSDCtoDeposit);

    const vaultAddress = await mockBitmorUSDCVault.getAddress();

    // Depositor approves vault to spend USDC
    await usdc.connect(depositor.signer).approve(vaultAddress, APPROVAL_AMOUNT_LENDING_POOL);

    // Vault deposits to lending pool (vault receives aTokens, user receives vault shares)
    await mockBitmorUSDCVault
      .connect(depositor.signer)
      .deposit(amountUSDCtoDeposit, depositor.address);

    // Check that VAULT received the aTokens
    const vaultATokenBalance = await aUsdc.balanceOf(vaultAddress);
    const userATokenBalance = await aUsdc.balanceOf(depositor.address);

    expect(vaultATokenBalance.toString()).to.be.equal(
      amountUSDCtoDeposit.toString(),
      'Vault should receive aTokens'
    );
    expect(userATokenBalance.toString()).to.be.equal('0', 'User should NOT receive aTokens directly');
  });

  it('User 0 deposits USDC via vault, User 1 borrows USDC with cbBTC collateral', async () => {
    const { users, pool, oracle, usdc, mockBitmorUSDCVault, mockLoanProvider, cbBTC, mockLoan, addressesProvider } = testEnv;

    const depositor = users[0];
    const borrower = users[1];

    // User 0 deposits 30000 USDC via VAULT to provide liquidity
    const amountUSDCtoDeposit = await convertToCurrencyDecimals(getContractAddress(usdc), '30000');
    await usdc.connect(depositor.signer).mint(amountUSDCtoDeposit);

    const vaultAddress = await mockBitmorUSDCVault.getAddress();
    await usdc.connect(depositor.signer).approve(vaultAddress, APPROVAL_AMOUNT_LENDING_POOL);

    // BITMOR: Deposit via vault (correct architecture)
    await mockBitmorUSDCVault
      .connect(depositor.signer)
      .deposit(amountUSDCtoDeposit, depositor.address);

    // User 1 deposits 1 cbBTC as collateral via mockLoanProvider (as loan contract)
    const amountBTCtoDeposit = await convertToCurrencyDecimals(getContractAddress(cbBTC), '1');
    await cbBTC.connect(borrower.signer).mint(amountBTCtoDeposit);
    await cbBTC.connect(borrower.signer).approve(getContractAddress(mockLoanProvider), APPROVAL_AMOUNT_LENDING_POOL);
    await mockLoanProvider
      .connect(borrower.signer)
      .deposit(getContractAddress(cbBTC), amountBTCtoDeposit, borrower.address, '0');

    // Calculate borrow amount (95% of available borrows)
    const userGlobalData = await pool.getUserAccountData(borrower.address);
    const usdcPrice = await oracle.getAssetPrice(getContractAddress(usdc));

    const amountUsdcToBorrow = await convertToCurrencyDecimals(
      getContractAddress(usdc),
      new BigNumber(userGlobalData.availableBorrowsETH.toString())
        .div(usdcPrice.toString())
        .multipliedBy(0.95)
        .toFixed(0)
    );

    // Create active loan in MockLoan
    await mockLoan.createActiveLoan(
      borrower.address,
      borrower.address,
      amountBTCtoDeposit,
      amountUsdcToBorrow,
      12,
      5000
    );

    // Temporarily set USDCVault to ZERO_ADDRESS (to allow borrow)
    await addressesProvider.setUSDCVault(ZERO_ADDRESS);

    // Approve credit delegation
    const Vdt = await DRE.ethers.getContractAt('VariableDebtToken', '0x7f19f1cc91f205633e9937e6782adc445ac40e86');
    await Vdt.connect(borrower.signer).approveDelegation(
      mockLoanProvider.target,
      '0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff'
    );

    // User 1 borrows USDC via mockLoanProvider (as loan contract)
    await mockLoanProvider
      .connect(borrower.signer)
      .borrow(getContractAddress(usdc), amountUsdcToBorrow, RateMode.Variable, '0', borrower.address);

    // Verify borrow succeeded
    const userGlobalDataAfter = await pool.getUserAccountData(borrower.address);
    expect(userGlobalDataAfter.totalDebtETH.toString()).to.not.equal('0', 'User should have debt');

    // Restore BitmorLoan
    await addressesProvider.setBitmorLoan(mockLoan);
  });

});
