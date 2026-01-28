import { makeSuite } from './helpers/make-suite.js';
import type { TestEnv } from './helpers/make-suite.js';
import { ProtocolErrors, RateMode } from '../../helpers/types.js';
import { APPROVAL_AMOUNT_LENDING_POOL, oneEther } from '../../helpers/constants.js';
import {convertToCurrencyDecimals,
  getContractAddress} from '../../helpers/contracts-helpers.js';
import { parseEther, parseUnits } from 'ethers';
import BigNumber from "bignumber.js";

import type { MockFlashLoanReceiver } from '../../types/ethers-contracts/index.js';
import { getMockFlashLoanReceiver } from '../../helpers/contracts-getters.js';

import chai from 'chai';
const { expect } = chai;

makeSuite('Pausable Pool', (testEnv: TestEnv) => {
  let _mockFlashLoanReceiver = {} as MockFlashLoanReceiver;

  const {
    LP_IS_PAUSED,
    INVALID_FROM_BALANCE_AFTER_TRANSFER,
    INVALID_TO_BALANCE_AFTER_TRANSFER,
  } = ProtocolErrors;

  before(async () => {
    _mockFlashLoanReceiver = await getMockFlashLoanReceiver();
  });

  it('User 0 deposits 1000 USDC. Configurator pauses pool. Transfers to user 1 reverts. Configurator unpauses the network and next transfer succees', async () => {
    const { users, pool, usdc, aUSDC, configurator, addressesProvider } = testEnv;
    const amountDAItoDeposit = await convertToCurrencyDecimals(getContractAddress(usdc), '1000');

    await usdc.connect(users[0].signer).mint(amountDAItoDeposit);

    // user 0 deposits 1000 DAI
    await usdc.connect(users[0].signer).approve(getContractAddress(pool), APPROVAL_AMOUNT_LENDING_POOL);

    // override the USDC vault address to by pass check on LendingPool(Error: LP_CALLER_NOT_VAULT_OR_LOAN_PROVIDER)
    await addressesProvider.setUSDCVault(users[0].address);
    await pool
      .connect(users[0].signer)
      .deposit(getContractAddress(usdc), amountDAItoDeposit, users[0].address, '0');

    const user0Balance = await aUSDC.balanceOf(users[0].address);
    const user1Balance = await aUSDC.balanceOf(users[1].address);

    // Configurator pauses the pool
    await configurator.connect(users[1].signer).setPoolPause(true);

    // User 0 tries the transfer to User 1
    await expect(
      aUSDC.connect(users[0].signer).transfer(users[1].address, amountDAItoDeposit)
    ).to.revertedWith(LP_IS_PAUSED);

    const pausedFromBalance = await aUSDC.balanceOf(users[0].address);
    const pausedToBalance = await aUSDC.balanceOf(users[1].address);

    expect(pausedFromBalance).to.be.equal(
      user0Balance.toString(),
      INVALID_TO_BALANCE_AFTER_TRANSFER
    );
    expect(pausedToBalance.toString()).to.be.equal(
      user1Balance.toString(),
      INVALID_FROM_BALANCE_AFTER_TRANSFER
    );

    // Configurator unpauses the pool
    await configurator.connect(users[1].signer).setPoolPause(false);

    // User 0 succeeds transfer to User 1
    await aUSDC.connect(users[0].signer).transfer(users[1].address, amountDAItoDeposit);

    const fromBalance = await aUSDC.balanceOf(users[0].address);
    const toBalance = await aUSDC.balanceOf(users[1].address);

    expect(fromBalance.toString()).to.be.equal(
      (user0Balance - amountDAItoDeposit),
      INVALID_FROM_BALANCE_AFTER_TRANSFER
    );
    expect(toBalance.toString()).to.be.equal(
      (user1Balance + amountDAItoDeposit),
      INVALID_TO_BALANCE_AFTER_TRANSFER
    );
  });

  it('Deposit', async () => {
    const { users, pool, usdc, configurator } = testEnv;

    const amountUsdcToDeposit = await convertToCurrencyDecimals(getContractAddress(usdc), '1000');

    await usdc.connect(users[0].signer).mint(amountUsdcToDeposit);

    // user 0 deposits 1000 DAI
    await usdc.connect(users[0].signer).approve(getContractAddress(pool), APPROVAL_AMOUNT_LENDING_POOL);

    // Configurator pauses the pool
    await configurator.connect(users[1].signer).setPoolPause(true);
    await expect(
      pool.connect(users[0].signer).deposit(getContractAddress(usdc), amountUsdcToDeposit, users[0].address, '0')
    ).to.revertedWith(LP_IS_PAUSED);

    // Configurator unpauses the pool
    await configurator.connect(users[1].signer).setPoolPause(false);
  });

  it('Withdraw', async () => {
    const { users, pool, usdc, aUSDC, configurator } = testEnv;

    const amountDAItoDeposit = await convertToCurrencyDecimals(getContractAddress(usdc), '1000');

    await usdc.connect(users[0].signer).mint(amountDAItoDeposit);

    // user 0 deposits 1000 DAI
    await usdc.connect(users[0].signer).approve(getContractAddress(pool), APPROVAL_AMOUNT_LENDING_POOL);
    await pool
      .connect(users[0].signer)
      .deposit(getContractAddress(usdc), amountDAItoDeposit, users[0].address, '0');

    // Configurator pauses the pool
    await configurator.connect(users[1].signer).setPoolPause(true);

    // user tries to burn
    await expect(
      pool.connect(users[0].signer).withdraw(getContractAddress(usdc), amountDAItoDeposit, users[0].address)
    ).to.revertedWith(LP_IS_PAUSED);

    // Configurator unpauses the pool
    await configurator.connect(users[1].signer).setPoolPause(false);
  });

  it('Borrow', async () => {
    const { pool, usdc, users, configurator } = testEnv;

    const user = users[1];
    // Pause the pool
    await configurator.connect(users[1].signer).setPoolPause(true);

    // Try to execute liquidation
    await expect(
      pool.connect(user.signer).borrow(getContractAddress(usdc), '1', '1', '0', user.address)
    ).revertedWith(LP_IS_PAUSED);

    // Unpause the pool
    await configurator.connect(users[1].signer).setPoolPause(false);
  });

  it('Repay', async () => {
    const { pool, usdc, users, configurator } = testEnv;

    const user = users[1];
    // Pause the pool
    await configurator.connect(users[1].signer).setPoolPause(true);

    // Try to execute liquidation
    await expect(pool.connect(user.signer).repay(getContractAddress(usdc), '1', '1', user.address)).revertedWith(
      LP_IS_PAUSED
    );

    // Unpause the pool
    await configurator.connect(users[1].signer).setPoolPause(false);
  });

  it('Flash loan', async () => {
    const { dai, pool, cbBTC, users, configurator } = testEnv;

    const caller = users[3];

    const flashAmount = parseEther('0.8');

    await _mockFlashLoanReceiver.setFailExecutionTransfer(true);

    // Pause pool
    await configurator.connect(users[1].signer).setPoolPause(true);

    await expect(
      pool
        .connect(caller.signer)
        .flashLoan(
          getContractAddress(_mockFlashLoanReceiver),
          [getContractAddress(cbBTC)],
          [flashAmount],
          [1],
          caller.address,
          '0x10',
          '0'
        )
    ).revertedWith(LP_IS_PAUSED);

    // Unpause pool
    await configurator.connect(users[1].signer).setPoolPause(false);
  });

  it('Liquidation call', async () => {
    const { users, pool, usdc, oracle, cbBTC, configurator, helpersContract, addressesProvider, mockBitmorUSDCVault } = testEnv;
    const depositor = users[3];
    const borrower = users[4];

    //mints USDC to depositor
    await usdc
      .connect(depositor.signer)
      .mint(await convertToCurrencyDecimals(getContractAddress(usdc), '1000'));

    //approve protocol to access depositor wallet
    await usdc.connect(depositor.signer).approve(getContractAddress(pool), APPROVAL_AMOUNT_LENDING_POOL);

    //user 3 deposits 1000 USDC
    const amountUSDCtoDeposit = await convertToCurrencyDecimals(getContractAddress(usdc), '1000');

    // override the USDC vault address to by pass check on LendingPool(Error: LP_CALLER_NOT_VAULT_OR_LOAN_PROVIDER)
    await addressesProvider.setUSDCVault(depositor.address);
    await pool
      .connect(depositor.signer)
      .deposit(getContractAddress(usdc), amountUSDCtoDeposit, depositor.address, '0');

    //user 4 deposits 1 cbBTC
    const amountETHtoDeposit = await convertToCurrencyDecimals(getContractAddress(cbBTC), '1');

    //mints cbBTC to borrower
    await cbBTC.connect(borrower.signer).mint(amountETHtoDeposit);

    //approve protocol to access borrower wallet
    await cbBTC.connect(borrower.signer).approve(getContractAddress(pool), APPROVAL_AMOUNT_LENDING_POOL);

    // override the USDC vault address to by pass check on LendingPool(Error: LP_CALLER_NOT_VAULT_OR_LOAN_PROVIDER)
    await addressesProvider.setUSDCVault(borrower.address);
    await pool
      .connect(borrower.signer)
      .deposit(getContractAddress(cbBTC), amountETHtoDeposit, borrower.address, '0');
    
    //user 4 borrows
    const userGlobalData = await pool.getUserAccountData(borrower.address);

    const usdcPrice = await oracle.getAssetPrice(getContractAddress(usdc));

    const amountUSDCToBorrow = await convertToCurrencyDecimals(
      getContractAddress(usdc),
      new BigNumber(userGlobalData.availableBorrowsETH.toString())
        .div(usdcPrice.toString())
        .multipliedBy(0.9502)
        .toFixed(0)
    );

    // override the bitmor loan to by pass check on LendingPool(Error: LP_CALLER_NOT_VAULT_OR_LOAN_PROVIDER)
    await addressesProvider.setBitmorLoan(borrower.address);
    await addressesProvider.setUSDCVault(mockBitmorUSDCVault.target);
    const asset = await mockBitmorUSDCVault.asset();
    console.log("asset in test:: ", asset);
    await pool
      .connect(borrower.signer)
      .borrow(getContractAddress(usdc), amountUSDCToBorrow, 2, 0, borrower.address);
    console.log("deposit complete");

    // Drops HF below 1
    await oracle.setAssetPrice(
      getContractAddress(usdc),
      new BigNumber(usdcPrice.toString()).multipliedBy(1.2).toFixed(0)
    );

    //mints dai to the liquidator
    await usdc.mint(await convertToCurrencyDecimals(getContractAddress(usdc), '1000'));
    await usdc.approve(getContractAddress(pool), APPROVAL_AMOUNT_LENDING_POOL);

    const userReserveDataBefore = await helpersContract.getUserReserveData(
      getContractAddress(usdc),
      borrower.address
    );

    const amountToLiquidate = new BigNumber(userReserveDataBefore.currentStableDebt.toString())
      .multipliedBy(0.5)
      .toFixed(0);

    // Pause pool
    await configurator.connect(users[1].signer).setPoolPause(true);

    console.log("deposit complete");

    // Do liquidation
    await expect(
      pool.liquidationCall(getContractAddress(cbBTC), getContractAddress(usdc), borrower.address, amountToLiquidate, true)
    ).revertedWith(LP_IS_PAUSED);

    // Unpause pool
    await configurator.connect(users[1].signer).setPoolPause(false);
  });

  it('SwapBorrowRateMode', async () => {
    const { pool, cbBTC, usdc, users, configurator, addressesProvider, mockBitmorUSDCVault, mockLoanProvider } = testEnv;
    const user = users[1];
    const amountCbBtcToDeposit = parseEther('10');
    const amountToBorrow = parseUnits('65', 6);

    await addressesProvider.setUSDCVault(user.address);
    await cbBTC.connect(user.signer).mint(amountCbBtcToDeposit);
    await cbBTC.connect(user.signer).approve(getContractAddress(pool), APPROVAL_AMOUNT_LENDING_POOL);
    await pool.connect(user.signer).deposit(getContractAddress(cbBTC), amountCbBtcToDeposit, user.address, '0');
    await addressesProvider.setBitmorLoan(user.address);
    await addressesProvider.setUSDCVault(mockBitmorUSDCVault.target);
    await pool.connect(user.signer).borrow(getContractAddress(usdc), amountToBorrow, 2, 0, user.address);

    // Pause pool
    await configurator.connect(users[1].signer).setPoolPause(true);

    // Try to repay
    await expect(
      pool.connect(user.signer).swapBorrowRateMode(getContractAddress(usdc), RateMode.Stable)
    ).revertedWith(LP_IS_PAUSED);

    // Unpause pool
    await configurator.connect(users[1].signer).setPoolPause(false);
  });

  it('RebalanceStableBorrowRate', async () => {
    const { pool, usdc, users, configurator } = testEnv;
    const user = users[1];
    // Pause pool
    await configurator.connect(users[1].signer).setPoolPause(true);

    await expect(
      pool.connect(user.signer).rebalanceStableBorrowRate(getContractAddress(usdc), user.address)
    ).revertedWith(LP_IS_PAUSED);

    // Unpause pool
    await configurator.connect(users[1].signer).setPoolPause(false);
  });

  it('setUserUseReserveAsCollateral', async () => {
    const { pool, cbBTC, users, configurator, addressesProvider } = testEnv;
    const user = users[1];

    await addressesProvider.setUSDCVault(user.address);
    const amountWETHToDeposit = parseEther('1');
    await cbBTC.connect(user.signer).mint(amountWETHToDeposit);
    await cbBTC.connect(user.signer).approve(getContractAddress(pool), APPROVAL_AMOUNT_LENDING_POOL);
    await pool.connect(user.signer).deposit(getContractAddress(cbBTC), amountWETHToDeposit, user.address, '0');

    // Pause pool
    await configurator.connect(users[1].signer).setPoolPause(true);

    await expect(
      pool.connect(user.signer).setUserUseReserveAsCollateral(getContractAddress(cbBTC), false)
    ).revertedWith(LP_IS_PAUSED);

    // Unpause pool
    await configurator.connect(users[1].signer).setPoolPause(false);
  });
});
