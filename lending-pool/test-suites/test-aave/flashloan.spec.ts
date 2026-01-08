import BigNumber from "bignumber.js";


import { makeSuite } from './helpers/make-suite.js';
import type { TestEnv } from './helpers/make-suite.js';
import { APPROVAL_AMOUNT_LENDING_POOL, oneRay } from '../../helpers/constants.js';
import {convertToCurrencyDecimals, getContract,
  getContractAddress} from '../../helpers/contracts-helpers.js';
import { parseEther, parseUnits } from 'ethers';
import type { MockFlashLoanReceiver } from '../../types/ethers-contracts/index.js';
import { ProtocolErrors, eContractid } from '../../helpers/types.js';
import {
  getMockFlashLoanReceiver,
  getStableDebtToken,
  getVariableDebtToken,
} from '../../helpers/contracts-getters.js';
import { DRE } from '../../helpers/misc-utils.js';

import chai from 'chai';
const { expect } = chai;

makeSuite('LendingPool FlashLoan function', (testEnv: TestEnv) => {
  let _mockFlashLoanReceiver = {} as MockFlashLoanReceiver;
  const {
    VL_COLLATERAL_BALANCE_IS_0,
    TRANSFER_AMOUNT_EXCEEDS_BALANCE,
    LP_INVALID_FLASHLOAN_MODE,
    SAFEERC20_LOWLEVEL_CALL,
    LP_INVALID_FLASH_LOAN_EXECUTOR_RETURN,
    LP_BORROW_ALLOWANCE_NOT_ENOUGH,
  } = ProtocolErrors;

  before(async () => {
    _mockFlashLoanReceiver = await getMockFlashLoanReceiver();
  });

  it('Deposits WETH into the reserve', async () => {
    const { pool, weth } = testEnv;
    const userAddress = await pool.getAddress();
    const amountToDeposit = parseEther('1');

    await weth.mint(amountToDeposit);

    await weth.approve(getContractAddress(pool), APPROVAL_AMOUNT_LENDING_POOL);

    await pool.deposit(getContractAddress(weth), amountToDeposit, userAddress, '0');
  });

  it('Takes WETH flashloan with mode = 0, returns the funds correctly', async () => {
    const { pool, helpersContract, weth } = testEnv;

    await pool.flashLoan(
      getContractAddress(_mockFlashLoanReceiver),
      [getContractAddress(weth)],
      [parseEther('0.8')],
      [0],
      getContractAddress(_mockFlashLoanReceiver),
      '0x10',
      '0'
    );

    parseUnits('10000');

    const reserveData = await helpersContract.getReserveData(getContractAddress(weth));

    const currentLiquidityRate = reserveData.liquidityRate;
    const currentLiquidityIndex = reserveData.liquidityIndex;

    const totalLiquidity = new BigNumber(reserveData.availableLiquidity.toString())
      .plus(reserveData.totalStableDebt.toString())
      .plus(reserveData.totalVariableDebt.toString());

    expect(totalLiquidity.toString()).to.be.equal('1000720000000000000');
    expect(currentLiquidityRate.toString()).to.be.equal('0');
    expect(currentLiquidityIndex.toString()).to.be.equal('1000720000000000000000000000');
  });

  it('Takes an ETH flashloan with mode = 0 as big as the available liquidity', async () => {
    const { pool, helpersContract, weth } = testEnv;

    const reserveDataBefore = await helpersContract.getReserveData(getContractAddress(weth));
    const txResult = await pool.flashLoan(
      getContractAddress(_mockFlashLoanReceiver),
      [getContractAddress(weth)],
      ['1000720000000000000'],
      [0],
      getContractAddress(_mockFlashLoanReceiver),
      '0x10',
      '0'
    );

    const reserveData = await helpersContract.getReserveData(getContractAddress(weth));

    const currentLiqudityRate = reserveData.liquidityRate;
    const currentLiquidityIndex = reserveData.liquidityIndex;

    const totalLiquidity = new BigNumber(reserveData.availableLiquidity.toString())
      .plus(reserveData.totalStableDebt.toString())
      .plus(reserveData.totalVariableDebt.toString());

    expect(totalLiquidity.toString()).to.be.equal('1001620648000000000');
    expect(currentLiqudityRate.toString()).to.be.equal('0');
    expect(currentLiquidityIndex.toString()).to.be.equal('1001620648000000000000000000');
  });

  it('Takes WETH flashloan, does not return the funds with mode = 0. (revert expected)', async () => {
    const { pool, weth, users } = testEnv;
    const caller = users[1];
    await _mockFlashLoanReceiver.setFailExecutionTransfer(true);

    await expect(
      pool
        .connect(caller.signer)
        .flashLoan(
          getContractAddress(_mockFlashLoanReceiver),
          [getContractAddress(weth)],
          [parseEther('0.8')],
          [0],
          caller.address,
          '0x10',
          '0'
        )
    ).to.be.revertedWith(SAFEERC20_LOWLEVEL_CALL);
  });

  it('Takes WETH flashloan, simulating a receiver as EOA (revert expected)', async () => {
    const { pool, weth, users } = testEnv;
    const caller = users[1];
    await _mockFlashLoanReceiver.setFailExecutionTransfer(true);
    await _mockFlashLoanReceiver.setSimulateEOA(true);

    await expect(
      pool
        .connect(caller.signer)
        .flashLoan(
          getContractAddress(_mockFlashLoanReceiver),
          [getContractAddress(weth)],
          [parseEther('0.8')],
          [0],
          caller.address,
          '0x10',
          '0'
        )
    ).to.be.revertedWith(LP_INVALID_FLASH_LOAN_EXECUTOR_RETURN);
  });

  it('Takes a WETH flashloan with an invalid mode. (revert expected)', async () => {
    const { pool, weth, users } = testEnv;
    const caller = users[1];
    await _mockFlashLoanReceiver.setSimulateEOA(false);
    await _mockFlashLoanReceiver.setFailExecutionTransfer(true);

    await expect(
      pool
        .connect(caller.signer)
        .flashLoan(
          getContractAddress(_mockFlashLoanReceiver),
          [getContractAddress(weth)],
          [parseEther('0.8')],
          [4],
          caller.address,
          '0x10',
          '0'
        )
    ).to.be.revert(DRE.ethers);
  });

  it('Caller deposits 1000 DAI as collateral, Takes WETH flashloan with mode = 2, does not return the funds. A variable loan for caller is created', async () => {
    const { dai, pool, weth, users, helpersContract } = testEnv;

    const caller = users[1];

    await dai.connect(caller.signer).mint(await convertToCurrencyDecimals(getContractAddress(dai), '1000'));

    await dai.connect(caller.signer).approve(getContractAddress(pool), APPROVAL_AMOUNT_LENDING_POOL);

    const amountToDeposit = await convertToCurrencyDecimals(getContractAddress(dai), '1000');

    await pool.connect(caller.signer).deposit(getContractAddress(dai), amountToDeposit, caller.address, '0');

    await _mockFlashLoanReceiver.setFailExecutionTransfer(true);

    await pool
      .connect(caller.signer)
      .flashLoan(
        getContractAddress(_mockFlashLoanReceiver),
        [getContractAddress(weth)],
        [parseEther('0.8')],
        [2],
        caller.address,
        '0x10',
        '0'
      );
    const { variableDebtTokenAddress } = await helpersContract.getReserveTokensAddresses(
      getContractAddress(weth)
    );

    const wethDebtToken = await getVariableDebtToken(variableDebtTokenAddress);

    const callerDebt = await wethDebtToken.balanceOf(caller.address);

    expect(callerDebt.toString()).to.be.equal('800000000000000000', 'Invalid user debt');
  });

  it('tries to take a flashloan that is bigger than the available liquidity (revert expected)', async () => {
    const { pool, weth, users } = testEnv;
    const caller = users[1];

    await expect(
      pool.connect(caller.signer).flashLoan(
        getContractAddress(_mockFlashLoanReceiver),
        [getContractAddress(weth)],
        ['1004415000000000000'], //slightly higher than the available liquidity
        [2],
        caller.address,
        '0x10',
        '0'
      ),
      TRANSFER_AMOUNT_EXCEEDS_BALANCE
    ).to.be.revertedWith(SAFEERC20_LOWLEVEL_CALL);
  });

  it('tries to take a flashloan using a non contract address as receiver (revert expected)', async () => {
    const { pool, deployer, weth, users } = testEnv;
    const caller = users[1];

    await expect(
      pool.flashLoan(
        deployer.address,
        [getContractAddress(weth)],
        ['1000000000000000000'],
        [2],
        caller.address,
        '0x10',
        '0'
      )
    ).to.be.revert(DRE.ethers);
  });

  it('Deposits USDC into the reserve', async () => {
    const { usdc, pool } = testEnv;
    const userAddress = await pool.getAddress();

    await usdc.mint(await convertToCurrencyDecimals(getContractAddress(usdc), '1000'));

    await usdc.approve(getContractAddress(pool), APPROVAL_AMOUNT_LENDING_POOL);

    const amountToDeposit = await convertToCurrencyDecimals(getContractAddress(usdc), '1000');

    await pool.deposit(getContractAddress(usdc), amountToDeposit, userAddress, '0');
  });

  it('Takes out a 500 USDC flashloan, returns the funds correctly', async () => {
    const { usdc, pool, helpersContract, deployer: depositor } = testEnv;

    await _mockFlashLoanReceiver.setFailExecutionTransfer(false);

    const reserveDataBefore = await helpersContract.getReserveData(getContractAddress(usdc));

    const flashloanAmount = await convertToCurrencyDecimals(getContractAddress(usdc), '500');

    await pool.flashLoan(
      getContractAddress(_mockFlashLoanReceiver),
      [getContractAddress(usdc)],
      [flashloanAmount],
      [0],
      getContractAddress(_mockFlashLoanReceiver),
      '0x10',
      '0'
    );

    const reserveDataAfter = helpersContract.getReserveData(getContractAddress(usdc));

    const reserveData = await helpersContract.getReserveData(getContractAddress(usdc));
    const userData = await helpersContract.getUserReserveData(getContractAddress(usdc), depositor.address);

    const totalLiquidity = (
      reserveData.availableLiquidity +
      reserveData.totalStableDebt +
      reserveData.totalVariableDebt
    ).toString();
    const currentLiqudityRate = reserveData.liquidityRate.toString();
    const currentLiquidityIndex = reserveData.liquidityIndex.toString();
    const currentUserBalance = userData.currentATokenBalance.toString();

    const expectedLiquidity = await convertToCurrencyDecimals(getContractAddress(usdc), '1000.450');

    expect(totalLiquidity).to.be.equal(expectedLiquidity, 'Invalid total liquidity');
    expect(currentLiqudityRate).to.be.equal('0', 'Invalid liquidity rate');
    expect(currentLiquidityIndex).to.be.equal(
      new BigNumber('1.00045').multipliedBy(oneRay).toFixed(),
      'Invalid liquidity index'
    );
    expect(currentUserBalance.toString()).to.be.equal(expectedLiquidity, 'Invalid user balance');
  });

  it('Takes out a 500 USDC flashloan with mode = 0, does not return the funds. (revert expected)', async () => {
    const { usdc, pool, users } = testEnv;
    const caller = users[2];

    const flashloanAmount = await convertToCurrencyDecimals(getContractAddress(usdc), '500');

    await _mockFlashLoanReceiver.setFailExecutionTransfer(true);

    await expect(
      pool
        .connect(caller.signer)
        .flashLoan(
          getContractAddress(_mockFlashLoanReceiver),
          [getContractAddress(usdc)],
          [flashloanAmount],
          [2],
          caller.address,
          '0x10',
          '0'
        )
    ).to.be.revertedWith(VL_COLLATERAL_BALANCE_IS_0);
  });

  it('Caller deposits 5 WETH as collateral, Takes a USDC flashloan with mode = 2, does not return the funds. A loan for caller is created', async () => {
    const { usdc, pool, weth, users, helpersContract } = testEnv;

    const caller = users[2];

    await weth.connect(caller.signer).mint(await convertToCurrencyDecimals(getContractAddress(weth), '5'));

    await weth.connect(caller.signer).approve(getContractAddress(pool), APPROVAL_AMOUNT_LENDING_POOL);

    const amountToDeposit = await convertToCurrencyDecimals(getContractAddress(weth), '5');

    await pool.connect(caller.signer).deposit(getContractAddress(weth), amountToDeposit, caller.address, '0');

    await _mockFlashLoanReceiver.setFailExecutionTransfer(true);

    const flashloanAmount = await convertToCurrencyDecimals(getContractAddress(usdc), '500');

    await pool
      .connect(caller.signer)
      .flashLoan(
        getContractAddress(_mockFlashLoanReceiver),
        [getContractAddress(usdc)],
        [flashloanAmount],
        [2],
        caller.address,
        '0x10',
        '0'
      );
    const { variableDebtTokenAddress } = await helpersContract.getReserveTokensAddresses(
      getContractAddress(usdc)
    );

    const usdcDebtToken = await getVariableDebtToken(variableDebtTokenAddress);

    const callerDebt = await usdcDebtToken.balanceOf(caller.address);

    expect(callerDebt.toString()).to.be.equal('500000000', 'Invalid user debt');
  });

  it('Caller deposits 1000 DAI as collateral, Takes a WETH flashloan with mode = 0, does not approve the transfer of the funds', async () => {
    const { dai, pool, weth, users } = testEnv;
    const caller = users[3];

    await dai.connect(caller.signer).mint(await convertToCurrencyDecimals(getContractAddress(dai), '1000'));

    await dai.connect(caller.signer).approve(getContractAddress(pool), APPROVAL_AMOUNT_LENDING_POOL);

    const amountToDeposit = await convertToCurrencyDecimals(getContractAddress(dai), '1000');

    await pool.connect(caller.signer).deposit(getContractAddress(dai), amountToDeposit, caller.address, '0');

    const flashAmount = parseEther('0.8');

    await _mockFlashLoanReceiver.setFailExecutionTransfer(false);
    await _mockFlashLoanReceiver.setAmountToApprove(flashAmount / 2n);

    await expect(
      pool
        .connect(caller.signer)
        .flashLoan(
          getContractAddress(_mockFlashLoanReceiver),
          [getContractAddress(weth)],
          [flashAmount],
          [0],
          caller.address,
          '0x10',
          '0'
        )
    ).to.be.revertedWith(SAFEERC20_LOWLEVEL_CALL);
  });

  it('Caller takes a WETH flashloan with mode = 1', async () => {
    const { dai, pool, weth, users, helpersContract } = testEnv;

    const caller = users[3];

    const flashAmount = parseEther('0.8');

    await _mockFlashLoanReceiver.setFailExecutionTransfer(true);

    await pool
      .connect(caller.signer)
      .flashLoan(
        getContractAddress(_mockFlashLoanReceiver),
        [getContractAddress(weth)],
        [flashAmount],
        [1],
        caller.address,
        '0x10',
        '0'
      );

    const { stableDebtTokenAddress } = await helpersContract.getReserveTokensAddresses(
      getContractAddress(weth)
    );

    const wethDebtToken = await getStableDebtToken(stableDebtTokenAddress);

    const callerDebt = await wethDebtToken.balanceOf(caller.address);

    expect(callerDebt.toString()).to.be.equal('800000000000000000', 'Invalid user debt');
  });

  it('Caller takes a WETH flashloan with mode = 1 onBehalfOf user without allowance', async () => {
    const { dai, pool, weth, users, helpersContract } = testEnv;

    const caller = users[5];
    const onBehalfOf = users[4];

    // Deposit 1000 dai for onBehalfOf user
    await dai.connect(onBehalfOf.signer).mint(await convertToCurrencyDecimals(getContractAddress(dai), '1000'));

    await dai.connect(onBehalfOf.signer).approve(getContractAddress(pool), APPROVAL_AMOUNT_LENDING_POOL);

    const amountToDeposit = await convertToCurrencyDecimals(getContractAddress(dai), '1000');

    await pool
      .connect(onBehalfOf.signer)
      .deposit(getContractAddress(dai), amountToDeposit, onBehalfOf.address, '0');

    const flashAmount = parseEther('0.8');

    await _mockFlashLoanReceiver.setFailExecutionTransfer(true);

    await expect(
      pool
        .connect(caller.signer)
        .flashLoan(
          getContractAddress(_mockFlashLoanReceiver),
          [getContractAddress(weth)],
          [flashAmount],
          [1],
          onBehalfOf.address,
          '0x10',
          '0'
        )
    ).to.be.revertedWith(LP_BORROW_ALLOWANCE_NOT_ENOUGH);
  });

  it('Caller takes a WETH flashloan with mode = 1 onBehalfOf user with allowance. A loan for onBehalfOf is creatd.', async () => {
    const { dai, pool, weth, users, helpersContract } = testEnv;

    const caller = users[5];
    const onBehalfOf = users[4];

    const flashAmount = parseEther('0.8');

    const reserveData = await pool.getReserveData(getContractAddress(weth));

    const stableDebtToken = await getStableDebtToken(reserveData.stableDebtTokenAddress);

    // Deposited for onBehalfOf user already, delegate borrow allowance
    await stableDebtToken.connect(onBehalfOf.signer).approveDelegation(caller.address, flashAmount);

    await _mockFlashLoanReceiver.setFailExecutionTransfer(true);

    await pool
      .connect(caller.signer)
      .flashLoan(
        getContractAddress(_mockFlashLoanReceiver),
        [getContractAddress(weth)],
        [flashAmount],
        [1],
        onBehalfOf.address,
        '0x10',
        '0'
      );

    const { stableDebtTokenAddress } = await helpersContract.getReserveTokensAddresses(
      getContractAddress(weth)
    );

    const wethDebtToken = await getStableDebtToken(stableDebtTokenAddress);

    const onBehalfOfDebt = await wethDebtToken.balanceOf(onBehalfOf.address);

    expect(onBehalfOfDebt.toString()).to.be.equal(
      '800000000000000000',
      'Invalid onBehalfOf user debt'
    );
  });
});
