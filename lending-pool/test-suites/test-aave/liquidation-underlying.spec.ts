import BigNumber from "bignumber.js";


import { DRE, increaseTime } from '../../helpers/misc-utils.js';
import { APPROVAL_AMOUNT_LENDING_POOL, oneEther } from '../../helpers/constants.js';
import { convertToCurrencyDecimals, getContractAddress } from '../../helpers/contracts-helpers.js';
import { makeSuite } from './helpers/make-suite.js';
import { ProtocolErrors, RateMode } from '../../helpers/types.js';
import { calcExpectedStableDebtTokenBalance } from './helpers/utils/calculations.js';
import { getUserData } from './helpers/utils/helpers.js';

import { parseEther } from 'ethers';

import chai from 'chai';
const { expect } = chai;

makeSuite('LendingPool liquidation - liquidator receiving the underlying asset', (testEnv) => {
  const { INVALID_HF } = ProtocolErrors;

  before('Before LendingPool liquidation: set config', () => {
    BigNumber.config({ DECIMAL_PLACES: 0, ROUNDING_MODE: BigNumber.ROUND_DOWN });
  });

  after('After LendingPool liquidation: reset config', () => {
    BigNumber.config({ DECIMAL_PLACES: 20, ROUNDING_MODE: BigNumber.ROUND_HALF_UP });
  });

  it("It's not possible to liquidate on a non-active collateral or a non active principal", async () => {
    const { configurator, weth, pool, users, dai } = testEnv;
    const user = users[1];
    await configurator.deactivateReserve(getContractAddress(weth));

    await expect(
      pool.liquidationCall(getContractAddress(weth), getContractAddress(dai), user.address, parseEther('1000'), false)
    ).to.be.revertedWith('2');

    await configurator.activateReserve(getContractAddress(weth));

    await configurator.deactivateReserve(getContractAddress(dai));

    await expect(
      pool.liquidationCall(getContractAddress(weth), getContractAddress(dai), user.address, parseEther('1000'), false)
    ).to.be.revertedWith('2');

    await configurator.activateReserve(getContractAddress(dai));
  });

  it('Deposits WETH, borrows DAI', async () => {
    const { dai, weth, users, pool, oracle } = testEnv;
    const depositor = users[0];
    const borrower = users[1];

    //mints DAI to depositor
    await dai.connect(depositor.signer).mint(await convertToCurrencyDecimals(getContractAddress(dai), '1000'));

    //approve protocol to access depositor wallet
    await dai.connect(depositor.signer).approve(getContractAddress(pool), APPROVAL_AMOUNT_LENDING_POOL);

    //user 1 deposits 1000 DAI
    const amountDAItoDeposit = await convertToCurrencyDecimals(getContractAddress(dai), '1000');

    await pool
      .connect(depositor.signer)
      .deposit(getContractAddress(dai), amountDAItoDeposit, depositor.address, '0');
    //user 2 deposits 1 ETH
    const amountETHtoDeposit = await convertToCurrencyDecimals(getContractAddress(weth), '1');

    //mints WETH to borrower
    await weth.connect(borrower.signer).mint(await convertToCurrencyDecimals(getContractAddress(weth), '1000'));

    //approve protocol to access the borrower wallet
    await weth.connect(borrower.signer).approve(getContractAddress(pool), APPROVAL_AMOUNT_LENDING_POOL);

    await pool
      .connect(borrower.signer)
      .deposit(getContractAddress(weth), amountETHtoDeposit, borrower.address, '0');

    //user 2 borrows

    const userGlobalData = await pool.getUserAccountData(borrower.address);
    const daiPrice = await oracle.getAssetPrice(getContractAddress(dai));

    const amountDAIToBorrow = await convertToCurrencyDecimals(
      getContractAddress(dai),
      new BigNumber(userGlobalData.availableBorrowsETH.toString())
        .div(daiPrice.toString())
        .multipliedBy(0.95)
        .toFixed(0)
    );

    await pool
      .connect(borrower.signer)
      .borrow(getContractAddress(dai), amountDAIToBorrow, RateMode.Stable, '0', borrower.address);

    const userGlobalDataAfter = await pool.getUserAccountData(borrower.address);

    expect(userGlobalDataAfter.currentLiquidationThreshold.toString()).to.be.equal(
      '8250',
      INVALID_HF
    );
  });

  it('Drop the health factor below 1', async () => {
    const { dai, weth, users, pool, oracle } = testEnv;
    const borrower = users[1];

    const daiPrice = await oracle.getAssetPrice(getContractAddress(dai));

    await oracle.setAssetPrice(
      getContractAddress(dai),
      new BigNumber(daiPrice.toString()).multipliedBy(1.18).toFixed(0)
    );

    const userGlobalData = await pool.getUserAccountData(borrower.address);

    expect(userGlobalData.healthFactor.toString()).to.be.lt(
      oneEther.toFixed(0),
      INVALID_HF
    );
  });

  it('Liquidates the borrow', async () => {
    const { dai, weth, users, pool, oracle, helpersContract } = testEnv;
    const liquidator = users[3];
    const borrower = users[1];

    //mints dai to the liquidator
    await dai.connect(liquidator.signer).mint(await convertToCurrencyDecimals(getContractAddress(dai), '1000'));

    //approve protocol to access the liquidator wallet
    await dai.connect(liquidator.signer).approve(getContractAddress(pool), APPROVAL_AMOUNT_LENDING_POOL);

    const daiReserveDataBefore = await helpersContract.getReserveData(getContractAddress(dai));
    const ethReserveDataBefore = await helpersContract.getReserveData(getContractAddress(weth));

    const userReserveDataBefore = await getUserData(
      pool,
      helpersContract,
      getContractAddress(dai),
      borrower.address
    );

    const amountToLiquidate = new BigNumber(userReserveDataBefore.currentStableDebt.toString())
      .div(2)
      .toFixed(0);

    await increaseTime(100);

    const tx = await pool
      .connect(liquidator.signer)
      .liquidationCall(getContractAddress(weth), getContractAddress(dai), borrower.address, amountToLiquidate, false);

    const userReserveDataAfter = await getUserData(
      pool,
      helpersContract,
      getContractAddress(dai),
      borrower.address
    );

    const daiReserveDataAfter = await helpersContract.getReserveData(getContractAddress(dai));
    const ethReserveDataAfter = await helpersContract.getReserveData(getContractAddress(weth));

    const collateralPrice = await oracle.getAssetPrice(getContractAddress(weth));
    const principalPrice = await oracle.getAssetPrice(getContractAddress(dai));

    const collateralDecimals = (
      await helpersContract.getReserveConfigurationData(getContractAddress(weth))
    ).decimals.toString();
    const principalDecimals = (
      await helpersContract.getReserveConfigurationData(getContractAddress(dai))
    ).decimals.toString();

    const expectedCollateralLiquidated = new BigNumber(principalPrice.toString())
      .times(new BigNumber(amountToLiquidate).times(105))
      .times(new BigNumber(10).pow(collateralDecimals))
      .div(
        new BigNumber(collateralPrice.toString()).times(new BigNumber(10).pow(principalDecimals))
      )
      .div(100)
      .decimalPlaces(0, BigNumber.ROUND_DOWN);

    if (!tx.blockNumber) {
      expect(false, 'Invalid block number');
      return;
    }
    const txTimestamp = new BigNumber(
      (await DRE.ethers.provider.getBlock(tx.blockNumber)).timestamp
    );

    const stableDebtBeforeTx = calcExpectedStableDebtTokenBalance(
      userReserveDataBefore.principalStableDebt,
      userReserveDataBefore.stableBorrowRate,
      userReserveDataBefore.stableRateLastUpdated,
      txTimestamp
    );

    expect(userReserveDataAfter.currentStableDebt.toString()).to.be.almostEqual(
      stableDebtBeforeTx.minus(amountToLiquidate).toFixed(0),
      'Invalid user debt after liquidation'
    );

    //the liquidity index of the principal reserve needs to be bigger than the index before
    expect(daiReserveDataAfter.liquidityIndex.toString()).to.be.gte(
      daiReserveDataBefore.liquidityIndex.toString(),
      'Invalid liquidity index'
    );

    //the principal APY after a liquidation needs to be lower than the APY before
    expect(daiReserveDataAfter.liquidityRate.toString()).to.be.lt(
      daiReserveDataBefore.liquidityRate.toString(),
      'Invalid liquidity APY'
    );

    expect(daiReserveDataAfter.availableLiquidity.toString()).to.be.almostEqual(
      new BigNumber(daiReserveDataBefore.availableLiquidity.toString())
        .plus(amountToLiquidate)
        .toFixed(0),
      'Invalid principal available liquidity'
    );

    expect(ethReserveDataAfter.availableLiquidity.toString()).to.be.almostEqual(
      new BigNumber(ethReserveDataBefore.availableLiquidity.toString())
        .minus(expectedCollateralLiquidated)
        .toFixed(0),
      'Invalid collateral available liquidity'
    );
  });

  it('User 3 deposits 1000 USDC, user 4 1 WETH, user 4 borrows - drops HF, liquidates the borrow', async () => {
    const { usdc, users, pool, oracle, weth, helpersContract } = testEnv;

    const depositor = users[3];
    const borrower = users[4];
    const liquidator = users[5];

    //mints USDC to depositor
    await usdc
      .connect(depositor.signer)
      .mint(await convertToCurrencyDecimals(getContractAddress(usdc), '1000'));

    //approve protocol to access depositor wallet
    await usdc.connect(depositor.signer).approve(getContractAddress(pool), APPROVAL_AMOUNT_LENDING_POOL);

    //depositor deposits 1000 USDC
    const amountUSDCtoDeposit = await convertToCurrencyDecimals(getContractAddress(usdc), '1000');

    await pool
      .connect(depositor.signer)
      .deposit(getContractAddress(usdc), amountUSDCtoDeposit, depositor.address, '0');

    //borrower deposits 1 ETH
    const amountETHtoDeposit = await convertToCurrencyDecimals(getContractAddress(weth), '1');

    //mints WETH to borrower
    await weth.connect(borrower.signer).mint(await convertToCurrencyDecimals(getContractAddress(weth), '1000'));

    //approve protocol to access the borrower wallet
    await weth.connect(borrower.signer).approve(getContractAddress(pool), APPROVAL_AMOUNT_LENDING_POOL);

    await pool
      .connect(borrower.signer)
      .deposit(getContractAddress(weth), amountETHtoDeposit, borrower.address, '0');

    //borrower borrows
    const userGlobalData = await pool.getUserAccountData(borrower.address);

    const usdcPrice = await oracle.getAssetPrice(getContractAddress(usdc));

    const amountUSDCToBorrow = await convertToCurrencyDecimals(
      getContractAddress(usdc),
      new BigNumber(userGlobalData.availableBorrowsETH.toString())
        .div(usdcPrice.toString())
        .multipliedBy(0.9502)
        .toFixed(0)
    );

    await pool
      .connect(borrower.signer)
      .borrow(getContractAddress(usdc), amountUSDCToBorrow, RateMode.Stable, '0', borrower.address);

    //drops HF below 1
    await oracle.setAssetPrice(
      getContractAddress(usdc),
      new BigNumber(usdcPrice.toString()).multipliedBy(1.12).toFixed(0)
    );

    //mints dai to the liquidator

    await usdc
      .connect(liquidator.signer)
      .mint(await convertToCurrencyDecimals(getContractAddress(usdc), '1000'));

    //approve protocol to access depositor wallet
    await usdc.connect(liquidator.signer).approve(getContractAddress(pool), APPROVAL_AMOUNT_LENDING_POOL);

    const userReserveDataBefore = await helpersContract.getUserReserveData(
      getContractAddress(usdc),
      borrower.address
    );

    const usdcReserveDataBefore = await helpersContract.getReserveData(getContractAddress(usdc));
    const ethReserveDataBefore = await helpersContract.getReserveData(getContractAddress(weth));

    const amountToLiquidate = new BigNumber(
      userReserveDataBefore.currentStableDebt.toString()
    )
      .div(2)
      .toFixed(0);

    await pool
      .connect(liquidator.signer)
      .liquidationCall(getContractAddress(weth), getContractAddress(usdc), borrower.address, amountToLiquidate, false);

    const userReserveDataAfter = await helpersContract.getUserReserveData(
      getContractAddress(usdc),
      borrower.address
    );

    const userGlobalDataAfter = await pool.getUserAccountData(borrower.address);

    const usdcReserveDataAfter = await helpersContract.getReserveData(getContractAddress(usdc));
    const ethReserveDataAfter = await helpersContract.getReserveData(getContractAddress(weth));

    const collateralPrice = await oracle.getAssetPrice(getContractAddress(weth));
    const principalPrice = await oracle.getAssetPrice(getContractAddress(usdc));

    const collateralDecimals = (
      await helpersContract.getReserveConfigurationData(getContractAddress(weth))
    ).decimals.toString();
    const principalDecimals = (
      await helpersContract.getReserveConfigurationData(getContractAddress(usdc))
    ).decimals.toString();

    const expectedCollateralLiquidated = new BigNumber(principalPrice.toString())
      .times(new BigNumber(amountToLiquidate).times(105))
      .times(new BigNumber(10).pow(collateralDecimals))
      .div(
        new BigNumber(collateralPrice.toString()).times(new BigNumber(10).pow(principalDecimals))
      )
      .div(100)
      .decimalPlaces(0, BigNumber.ROUND_DOWN);

    expect(userGlobalDataAfter.healthFactor.toString()).to.be.gt(
      oneEther.toFixed(0),
      'Invalid health factor'
    );

    expect(userReserveDataAfter.currentStableDebt.toString()).to.be.almostEqual(
      new BigNumber(userReserveDataBefore.currentStableDebt.toString())
        .minus(amountToLiquidate)
        .toFixed(0),
      'Invalid user borrow balance after liquidation'
    );

    //the liquidity index of the principal reserve needs to be bigger than the index before
    expect(usdcReserveDataAfter.liquidityIndex.toString()).to.be.gte(
      usdcReserveDataBefore.liquidityIndex.toString(),
      'Invalid liquidity index'
    );

    //the principal APY after a liquidation needs to be lower than the APY before
    expect(usdcReserveDataAfter.liquidityRate.toString()).to.be.lt(
      usdcReserveDataBefore.liquidityRate.toString(),
      'Invalid liquidity APY'
    );

    expect(usdcReserveDataAfter.availableLiquidity.toString()).to.be.almostEqual(
      new BigNumber(usdcReserveDataBefore.availableLiquidity.toString())
        .plus(amountToLiquidate)
        .toFixed(0),
      'Invalid principal available liquidity'
    );

    expect(ethReserveDataAfter.availableLiquidity.toString()).to.be.almostEqual(
      new BigNumber(ethReserveDataBefore.availableLiquidity.toString())
        .minus(expectedCollateralLiquidated)
        .toFixed(0),
      'Invalid collateral available liquidity'
    );
  });

  it('User 4 deposits 10 AAVE - drops HF, liquidates the AAVE, which results on a lower amount being liquidated', async () => {
    const { aave, usdc, users, pool, oracle, helpersContract } = testEnv;

    const depositor = users[3];
    const borrower = users[4];
    const liquidator = users[5];

    //mints AAVE to borrower
    await aave.connect(borrower.signer).mint(await convertToCurrencyDecimals(getContractAddress(aave), '10'));

    //approve protocol to access the borrower wallet
    await aave.connect(borrower.signer).approve(getContractAddress(pool), APPROVAL_AMOUNT_LENDING_POOL);

    //borrower deposits 10 AAVE
    const amountToDeposit = await convertToCurrencyDecimals(getContractAddress(aave), '10');

    await pool
      .connect(borrower.signer)
      .deposit(getContractAddress(aave), amountToDeposit, borrower.address, '0');
    const usdcPrice = await oracle.getAssetPrice(getContractAddress(usdc));

    //drops HF below 1
    await oracle.setAssetPrice(
      getContractAddress(usdc),
      new BigNumber(usdcPrice.toString()).multipliedBy(1.14).toFixed(0)
    );

    //mints usdc to the liquidator
    await usdc
      .connect(liquidator.signer)
      .mint(await convertToCurrencyDecimals(getContractAddress(usdc), '1000'));

    //approve protocol to access depositor wallet
    await usdc.connect(liquidator.signer).approve(getContractAddress(pool), APPROVAL_AMOUNT_LENDING_POOL);

    const userReserveDataBefore = await helpersContract.getUserReserveData(
      getContractAddress(usdc),
      borrower.address
    );

    const usdcReserveDataBefore = await helpersContract.getReserveData(getContractAddress(usdc));
    const aaveReserveDataBefore = await helpersContract.getReserveData(getContractAddress(aave));

    const amountToLiquidate = new BigNumber(userReserveDataBefore.currentStableDebt.toString())
      .div(2)
      .decimalPlaces(0, BigNumber.ROUND_DOWN)
      .toFixed(0);

    const collateralPrice = await oracle.getAssetPrice(getContractAddress(aave));
    const principalPrice = await oracle.getAssetPrice(getContractAddress(usdc));

    await pool
      .connect(liquidator.signer)
      .liquidationCall(getContractAddress(aave), getContractAddress(usdc), borrower.address, amountToLiquidate, false);

    const userReserveDataAfter = await helpersContract.getUserReserveData(
      getContractAddress(usdc),
      borrower.address
    );

    const userGlobalDataAfter = await pool.getUserAccountData(borrower.address);

    const usdcReserveDataAfter = await helpersContract.getReserveData(getContractAddress(usdc));
    const aaveReserveDataAfter = await helpersContract.getReserveData(getContractAddress(aave));

    const aaveConfiguration = await helpersContract.getReserveConfigurationData(getContractAddress(aave));
    const collateralDecimals = aaveConfiguration.decimals.toString();
    const liquidationBonus = aaveConfiguration.liquidationBonus.toString();

    const principalDecimals = (
      await helpersContract.getReserveConfigurationData(getContractAddress(usdc))
    ).decimals.toString();

    const expectedCollateralLiquidated = oneEther.multipliedBy('10');

    const expectedPrincipal = new BigNumber(collateralPrice.toString())
      .times(expectedCollateralLiquidated)
      .times(new BigNumber(10).pow(principalDecimals))
      .div(
        new BigNumber(principalPrice.toString()).times(new BigNumber(10).pow(collateralDecimals))
      )
      .times(10000)
      .div(liquidationBonus.toString())
      .decimalPlaces(0, BigNumber.ROUND_DOWN);

    expect(userGlobalDataAfter.healthFactor.toString()).to.be.gt(
      oneEther.toFixed(0),
      'Invalid health factor'
    );

    expect(userReserveDataAfter.currentStableDebt.toString()).to.be.almostEqual(
      new BigNumber(userReserveDataBefore.currentStableDebt.toString())
        .minus(expectedPrincipal)
        .toFixed(0),
      'Invalid user borrow balance after liquidation'
    );

    expect(usdcReserveDataAfter.availableLiquidity.toString()).to.be.almostEqual(
      new BigNumber(usdcReserveDataBefore.availableLiquidity.toString())
        .plus(expectedPrincipal)
        .toFixed(0),
      'Invalid principal available liquidity'
    );

    expect(aaveReserveDataAfter.availableLiquidity.toString()).to.be.almostEqual(
      new BigNumber(aaveReserveDataBefore.availableLiquidity.toString())
        .minus(expectedCollateralLiquidated)
        .toFixed(0),
      'Invalid collateral available liquidity'
    );
  });
});
