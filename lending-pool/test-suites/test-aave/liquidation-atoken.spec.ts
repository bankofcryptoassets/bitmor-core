import BigNumber from "bignumber.js";

import { DRE } from '../../helpers/misc-utils.js';
import { APPROVAL_AMOUNT_LENDING_POOL, oneEther, ZERO_ADDRESS } from '../../helpers/constants.js';
import { convertToCurrencyDecimals, getContractAddress } from '../../helpers/contracts-helpers.js';
import { makeSuite } from './helpers/make-suite.js';
import { ProtocolErrors, RateMode } from '../../helpers/types.js';
import { calcExpectedVariableDebtTokenBalance } from './helpers/utils/calculations.js';
import { getUserData, getReserveData } from './helpers/utils/helpers.js';
import { depositViaVault } from './helpers/vault-helpers.js';

import chai from 'chai';
const { expect } = chai;

makeSuite('LendingPool liquidation - liquidator receiving aToken', (testEnv) => {
  const {
    LPCM_HEALTH_FACTOR_NOT_BELOW_THRESHOLD,
    INVALID_HF,
    LPCM_SPECIFIED_CURRENCY_NOT_BORROWED_BY_USER,
    LPCM_COLLATERAL_CANNOT_BE_LIQUIDATED,
    LP_IS_PAUSED,
    LPCM_CANNOT_FULL_LIQUIDATE
  } = ProtocolErrors;

  it.only('Deposits cbBTC, borrows USDC/Check liquidation fails because health factor is above 1', async () => {
    const { users, pool, oracle, usdc, mockLoanProvider, cbBTC, mockLoan, addressesProvider } = testEnv;
    const depositor = users[0];
    const borrower = users[1];

    //user 1 deposits 1000 usdc
    const amountDAItoDeposit = await convertToCurrencyDecimals(getContractAddress(usdc), '100000000');
    await usdc.connect(depositor.signer).mint(amountDAItoDeposit);
    await usdc.connect(depositor.signer).approve(getContractAddress(mockLoanProvider), APPROVAL_AMOUNT_LENDING_POOL);
    await mockLoanProvider
      .connect(depositor.signer)
      .deposit(getContractAddress(usdc), amountDAItoDeposit, depositor.address, '0');

    //user 2 deposits 1 cbBTC
    const amountETHtoDeposit = await convertToCurrencyDecimals(getContractAddress(cbBTC), '1');
    await cbBTC.connect(borrower.signer).mint(amountETHtoDeposit);
    await cbBTC.connect(borrower.signer).approve(getContractAddress(mockLoanProvider), APPROVAL_AMOUNT_LENDING_POOL);
    await mockLoanProvider
      .connect(borrower.signer)
      .deposit(getContractAddress(cbBTC), amountETHtoDeposit, borrower.address, '0');
    //user 2 borrows
    const userGlobalData = await pool.getUserAccountData(borrower.address);
    const usdcPrice = await oracle.getAssetPrice(getContractAddress(usdc));

    console.log("Dai Price", usdcPrice.toString());

    const amountUsdcToBorrow = await convertToCurrencyDecimals(
      getContractAddress(usdc),
      new BigNumber(userGlobalData.availableBorrowsETH.toString())
        .div(usdcPrice.toString())
        .multipliedBy(0.95)
        .toFixed(0)
    );

    await mockLoan.createActiveLoan(
      borrower.address,
      borrower.address,
      amountETHtoDeposit,
      amountUsdcToBorrow,
      12,
      5000
    )

    await addressesProvider.setUSDCVault(ZERO_ADDRESS)

    const Vdt = await DRE.ethers.getContractAt("VariableDebtToken", "0x7f19f1cc91f205633e9937e6782adc445ac40e86");
    await Vdt.connect(borrower.signer).approveDelegation(
      mockLoanProvider.target,
      "0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"
    );


    await mockLoanProvider
      .connect(borrower.signer)
      .borrow(getContractAddress(usdc), amountUsdcToBorrow, RateMode.Variable, '0', borrower.address);
    
    console.log("borrow complete");

    const userGlobalDataAfter = await pool.getUserAccountData(borrower.address);

    expect(userGlobalDataAfter.currentLiquidationThreshold.toString()).to.be.equal(
      '8000',
      'Invalid liquidation threshold'
    );

    await addressesProvider.setBitmorLoan(mockLoan);

    // await pool.liquidationCall(getContractAddress(cbBTC), getContractAddress(usdc), borrower.address, 1, true);

    //someone tries to liquidate user 2
    await expect(
      pool.liquidationCall(getContractAddress(cbBTC), getContractAddress(usdc), borrower.address, 1, true)
    ).to.be.revertedWith(LPCM_CANNOT_FULL_LIQUIDATE);
  });

  it('Drop the health factor below 1', async () => {
    const { usdc, users, pool, oracle } = testEnv;
    const borrower = users[1];

    const usdcPrice = await oracle.getAssetPrice(getContractAddress(usdc));

    await oracle.setAssetPrice(
      getContractAddress(usdc),
      new BigNumber(usdcPrice.toString()).multipliedBy(1.15).toFixed(0)
    );

    const userGlobalData = await pool.getUserAccountData(borrower.address);

    expect(userGlobalData.healthFactor.toString()).to.be.lessThan(
      oneEther.toString(),
      INVALID_HF
    );
  });

  it('Tries to liquidate a different currency than the loan principal', async () => {
    const { pool, users, cbBTC } = testEnv;
    const borrower = users[1];
    //user 2 tries to borrow
    await expect(
      pool.liquidationCall(getContractAddress(cbBTC), getContractAddress(cbBTC), borrower.address, oneEther.toString(), true)
    ).revertedWith(LPCM_SPECIFIED_CURRENCY_NOT_BORROWED_BY_USER);
  });

  it('Tries to liquidate a different collateral than the borrower collateral', async () => {
    const { pool, usdc, users } = testEnv;
    const borrower = users[1];

    await expect(
      pool.liquidationCall(getContractAddress(usdc), getContractAddress(usdc), borrower.address, oneEther.toString(), true)
    ).revertedWith(LPCM_COLLATERAL_CANNOT_BE_LIQUIDATED);
  });

  it.only('Liquidates the borrow', async () => {
    const {
      pool,
      dai,
      weth,
      users,
      oracle,
      helpersContract,
      deployer,
      usdc,
      cbBTC,
      addressesProvider,
      mockLoan,
      mockLoanProvider
    } = testEnv;
    const borrower = users[1];

    //mints dai to the caller
    await usdc.mint(await convertToCurrencyDecimals(getContractAddress(usdc), '1000'));

    //approve protocol to access depositor wallet
    await usdc.approve(getContractAddress(pool), APPROVAL_AMOUNT_LENDING_POOL);

    const daiReserveDataBefore = await getReserveData(helpersContract, getContractAddress(usdc));
    const ethReserveDataBefore = await helpersContract.getReserveData(getContractAddress(cbBTC));

    const userReserveDataBefore = await getUserData(
      pool,
      helpersContract,
      getContractAddress(usdc),
      borrower.address
    );

    console.log("userReserveDataBefore:: ", userReserveDataBefore);

    const amountToLiquidate = new BigNumber(userReserveDataBefore.currentVariableDebt.toString())
      .div(2)
      .toFixed(0);
    
    console.log("amountToLiquidate: ", amountToLiquidate);
    console.log(users[0].address);
    console.log("pool:: ", pool.target);

    await addressesProvider.setBitmorLoan(mockLoan);
    await mockLoan.createActiveLoan(
      borrower.address,
      borrower.address,
      await convertToCurrencyDecimals(getContractAddress(cbBTC), '1'),
      0,
      12,
      5000
    )
    await mockLoan.makeLoanOverdue(borrower.address, 30);
    const cbbtcPrice = await oracle.getAssetPrice(cbBTC.target);
    await oracle.setAssetPrice(cbBTC.target, (cbbtcPrice * 80n)/100n);
    const tx = await pool.liquidationCall(
      getContractAddress(cbBTC),
      getContractAddress(usdc),
      borrower.address,
      amountToLiquidate,
      true
    );

    const userReserveDataAfter = await helpersContract.getUserReserveData(
      getContractAddress(usdc),
      borrower.address
    );

    const userGlobalDataAfter = await pool.getUserAccountData(borrower.address);

    const daiReserveDataAfter = await helpersContract.getReserveData(getContractAddress(usdc));
    const ethReserveDataAfter = await helpersContract.getReserveData(getContractAddress(cbBTC));

    const collateralPrice = (await oracle.getAssetPrice(getContractAddress(cbBTC))).toString();
    const principalPrice = (await oracle.getAssetPrice(getContractAddress(usdc))).toString();

    const collateralDecimals = (
      await helpersContract.getReserveConfigurationData(getContractAddress(cbBTC))
    ).decimals.toString();
    const principalDecimals = (
      await helpersContract.getReserveConfigurationData(getContractAddress(usdc))
    ).decimals.toString();

    const expectedCollateralLiquidated = new BigNumber(principalPrice)
      .times(new BigNumber(amountToLiquidate).times(105))
      .times(new BigNumber(10).pow(collateralDecimals))
      .div(new BigNumber(collateralPrice).times(new BigNumber(10).pow(principalDecimals)))
      .decimalPlaces(0, BigNumber.ROUND_DOWN);

    if (!tx.blockNumber) {
      expect(false, 'Invalid block number');
      return;
    }

    const txTimestamp = new BigNumber(
      (await DRE.ethers.provider.getBlock(tx.blockNumber)).timestamp
    );

    const variableDebtBeforeTx = calcExpectedVariableDebtTokenBalance(
      daiReserveDataBefore,
      userReserveDataBefore,
      txTimestamp
    );

    expect(userGlobalDataAfter.healthFactor.toString()).to.be.greaterThan(
      oneEther.toFixed(0),
      'Invalid health factor'
    );

    expect(userReserveDataAfter.currentVariableDebt.toString()).to.be.almostEqual(
      new BigNumber(variableDebtBeforeTx).minus(amountToLiquidate).toFixed(0),
      'Invalid user borrow balance after liquidation'
    );

    expect(daiReserveDataAfter.availableLiquidity.toString()).to.be.almostEqual(
      new BigNumber(daiReserveDataBefore.availableLiquidity.toString())
        .plus(amountToLiquidate)
        .toFixed(0),
      'Invalid principal available liquidity'
    );

    //the liquidity index of the principal reserve needs to be bigger than the index before
    expect(daiReserveDataAfter.liquidityIndex.toString()).to.be.greaterThanOrEqual(
      daiReserveDataBefore.liquidityIndex.toString(),
      'Invalid liquidity index'
    );

    //the principal APY after a liquidation needs to be lower than the APY before
    expect(daiReserveDataAfter.liquidityRate.toString()).to.be.lessThan(
      daiReserveDataBefore.liquidityRate.toString(),
      'Invalid liquidity APY'
    );

    expect(ethReserveDataAfter.availableLiquidity.toString()).to.be.almostEqual(
      new BigNumber(ethReserveDataBefore.availableLiquidity.toString()).toFixed(0),
      'Invalid collateral available liquidity'
    );

    expect(
      (await helpersContract.getUserReserveData(getContractAddress(weth), deployer.address))
        .usageAsCollateralEnabled
    ).to.be.true;
  });

  it('User 3 deposits 1000 USDC, user 4 1 WETH, user 4 borrows - drops HF, liquidates the borrow', async () => {
    const { users, pool, usdc, oracle, weth, helpersContract } = testEnv;
    const depositor = users[3];
    const borrower = users[4];

    //user 3 deposits 1000 USDC via vault
    const amountUSDCtoDeposit = await convertToCurrencyDecimals(getContractAddress(usdc), '1000');
    await depositViaVault(usdc, amountUSDCtoDeposit, depositor, testEnv);

    //user 4 deposits 1 WETH via vault
    const amountETHtoDeposit = await convertToCurrencyDecimals(getContractAddress(weth), '1');
    await depositViaVault(weth, amountETHtoDeposit, borrower, testEnv);

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

    await pool
      .connect(borrower.signer)
      .borrow(getContractAddress(usdc), amountUSDCToBorrow, RateMode.Stable, '0', borrower.address);

    //drops HF below 1

    await oracle.setAssetPrice(
      getContractAddress(usdc),
      new BigNumber(usdcPrice.toString()).multipliedBy(1.12).toFixed(0)
    );

    //mints dai to the liquidator

    await usdc.mint(await convertToCurrencyDecimals(getContractAddress(usdc), '1000'));

    //approve protocol to access depositor wallet
    await usdc.approve(getContractAddress(pool), APPROVAL_AMOUNT_LENDING_POOL);

    const userReserveDataBefore = await helpersContract.getUserReserveData(
      getContractAddress(usdc),
      borrower.address
    );

    const usdcReserveDataBefore = await helpersContract.getReserveData(getContractAddress(usdc));
    const ethReserveDataBefore = await helpersContract.getReserveData(getContractAddress(weth));

    const amountToLiquidate = new BigNumber(userReserveDataBefore.currentStableDebt.toString())
      .multipliedBy(0.5)
      .toFixed(0);

    await pool.liquidationCall(
      getContractAddress(weth),
      getContractAddress(usdc),
      borrower.address,
      amountToLiquidate,
      true
    );

    const userReserveDataAfter = await helpersContract.getUserReserveData(
      getContractAddress(usdc),
      borrower.address
    );

    const userGlobalDataAfter = await pool.getUserAccountData(borrower.address);

    const usdcReserveDataAfter = await helpersContract.getReserveData(getContractAddress(usdc));
    const ethReserveDataAfter = await helpersContract.getReserveData(getContractAddress(weth));

    const collateralPrice = (await oracle.getAssetPrice(getContractAddress(weth))).toString();
    const principalPrice = (await oracle.getAssetPrice(getContractAddress(usdc))).toString();

    const collateralDecimals = (
      await helpersContract.getReserveConfigurationData(getContractAddress(weth))
    ).decimals.toString();
    const principalDecimals = (
      await helpersContract.getReserveConfigurationData(getContractAddress(usdc))
    ).decimals.toString();

    const expectedCollateralLiquidated = new BigNumber(principalPrice)
      .times(new BigNumber(amountToLiquidate).times(105))
      .times(new BigNumber(10).pow(collateralDecimals))
      .div(new BigNumber(collateralPrice).times(new BigNumber(10).pow(principalDecimals)))
      .decimalPlaces(0, BigNumber.ROUND_DOWN);

    expect(userGlobalDataAfter.healthFactor.toString()).to.be.greaterThan(
      oneEther.toFixed(0),
      'Invalid health factor'
    );

    expect(userReserveDataAfter.currentStableDebt.toString()).to.be.almostEqual(
      new BigNumber(userReserveDataBefore.currentStableDebt.toString())
        .minus(amountToLiquidate)
        .toFixed(0),
      'Invalid user borrow balance after liquidation'
    );

    expect(usdcReserveDataAfter.availableLiquidity.toString()).to.be.almostEqual(
      new BigNumber(usdcReserveDataBefore.availableLiquidity.toString())
        .plus(amountToLiquidate)
        .toFixed(0),
      'Invalid principal available liquidity'
    );

    //the liquidity index of the principal reserve needs to be bigger than the index before
    expect(usdcReserveDataAfter.liquidityIndex.toString()).to.be.greaterThanOrEqual(
      usdcReserveDataBefore.liquidityIndex.toString(),
      'Invalid liquidity index'
    );

    //the principal APY after a liquidation needs to be lower than the APY before
    expect(usdcReserveDataAfter.liquidityRate.toString()).to.be.lessThan(
      usdcReserveDataBefore.liquidityRate.toString(),
      'Invalid liquidity APY'
    );

    expect(ethReserveDataAfter.availableLiquidity.toString()).to.be.almostEqual(
      new BigNumber(ethReserveDataBefore.availableLiquidity.toString()).toFixed(0),
      'Invalid collateral available liquidity'
    );
  });
});
