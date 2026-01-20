import { APPROVAL_AMOUNT_LENDING_POOL, MAX_UINT_AMOUNT, ZERO_ADDRESS } from '../../helpers/constants.js';
import { convertToCurrencyDecimals, getContractAddress } from '../../helpers/contracts-helpers.js';
import chai from 'chai';
const { expect } = chai;
import { parseEther } from 'ethers';
import { RateMode, ProtocolErrors } from '../../helpers/types.js';
import { makeSuite } from './helpers/make-suite.js';
import type { TestEnv } from './helpers/make-suite.js';
import { CommonsConfig } from '../../markets/aave/commons.js';

const AAVE_REFERRAL = CommonsConfig.ProtocolGlobalParams.AaveReferral;

makeSuite('AToken: Transfer', (testEnv: TestEnv) => {
  const {
    INVALID_FROM_BALANCE_AFTER_TRANSFER,
    INVALID_TO_BALANCE_AFTER_TRANSFER,
    VL_TRANSFER_NOT_ALLOWED,
  } = ProtocolErrors;

  it('User 0 deposits 1000 DAI, transfers to user 1', async () => {
    const { users, pool, dai, aDai, usdcVault } = testEnv;

    await dai.connect(users[0].signer).mint(await convertToCurrencyDecimals(getContractAddress(dai), '1000'));

    // BITMOR: Deposit via vault instead of direct pool deposit
    const amountDAItoDeposit = await convertToCurrencyDecimals(getContractAddress(dai), '1000');
    const vaultAddress = await usdcVault.getAddress();

    await dai.connect(users[0].signer).approve(vaultAddress, APPROVAL_AMOUNT_LENDING_POOL);

    // BITMOR: User deposits to vault, receives vault shares
    await usdcVault
      .connect(users[0].signer)
      .deposit(amountDAItoDeposit, users[0].address);

    // BITMOR: Transfer vault shares (not aTokens)
    // In Bitmor, users hold vault shares and can transfer them
    await usdcVault.connect(users[0].signer).transfer(users[1].address, amountDAItoDeposit);

    const name = await usdcVault.name();

    expect(name).to.be.equal('Mock Vault Shares');

    // BITMOR: Check vault share balances (not aToken balances)
    const fromBalance = await usdcVault.balanceOf(users[0].address);
    const toBalance = await usdcVault.balanceOf(users[1].address);

    expect(fromBalance.toString()).to.be.equal('0', INVALID_FROM_BALANCE_AFTER_TRANSFER);
    expect(toBalance.toString()).to.be.equal(
      amountDAItoDeposit.toString(),
      INVALID_TO_BALANCE_AFTER_TRANSFER
    );
  });

  it('User 0 deposits 1 WETH and user 1 tries to borrow the WETH with the received DAI as collateral', async () => {
    const { users, pool, weth, helpersContract, wethVault, addressesProvider, deployer } = testEnv;

    // Switch to WETH vault
    const wethVaultAddress = await wethVault.getAddress();
    await addressesProvider.connect(deployer.signer).setUSDCVault(wethVaultAddress);

    await weth.connect(users[0].signer).mint(await convertToCurrencyDecimals(getContractAddress(weth), '1'));

    // Deposit WETH via WETH vault
    await weth.connect(users[0].signer).approve(wethVaultAddress, APPROVAL_AMOUNT_LENDING_POOL);
    await wethVault.connect(users[0].signer).deposit(parseEther('1.0'), users[0].address);

    // User 1 tries to borrow WETH using DAI vault shares as collateral
    // In Bitmor, vault shares are not recognized as collateral
    // Expected: Borrow should fail with error '9' (VL_COLLATERAL_BALANCE_IS_0)
    await expect(
      pool
        .connect(users[1].signer)
        .borrow(
          getContractAddress(weth),
          parseEther('0.1'),
          RateMode.Stable,
          AAVE_REFERRAL,
          users[1].address
        )
    ).to.be.revertedWith('9');
  });

});
