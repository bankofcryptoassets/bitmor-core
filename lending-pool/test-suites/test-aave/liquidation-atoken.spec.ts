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

  it('Deposits cbBTC, borrows USDC/Check liquidation fails because type of liquidation is not 1', async () => {
    const { users, pool, oracle, usdc, mockLoanProvider, cbBTC, mockLoan, addressesProvider, helpersContract } = testEnv;
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
    );

    const {variableDebtTokenAddress} = await helpersContract.getReserveTokensAddresses(getContractAddress(usdc));
    const Vdt = await DRE.ethers.getContractAt("VariableDebtToken", variableDebtTokenAddress);
    await Vdt.connect(borrower.signer).approveDelegation(
      mockLoanProvider.target,
      "0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"
    );


    await mockLoanProvider
      .connect(borrower.signer)
      .borrow(getContractAddress(usdc), amountUsdcToBorrow, RateMode.Variable, '0', borrower.address);

    const userGlobalDataAfter = await pool.getUserAccountData(borrower.address);

    expect(userGlobalDataAfter.currentLiquidationThreshold.toString()).to.be.equal(
      '8000',
      'Invalid liquidation threshold'
    );

    await addressesProvider.setBitmorLoan(getContractAddress(mockLoan));

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

  it('Liquidates the borrow', async () => {
    const {
      pool,
      users,
      oracle,
      helpersContract,
      deployer,
      usdc,
      cbBTC,
      mockLoan
    } = testEnv;
    const borrower = users[1];

    //mints dai to the caller
    await usdc.mint(await convertToCurrencyDecimals(getContractAddress(usdc), '100000'));

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

    const amountToLiquidate = new BigNumber(userReserveDataBefore.currentVariableDebt.toString())
      .div(2)
      .toFixed(0);

    await mockLoan.createActiveLoan(
      borrower.address,
      borrower.address,
      await convertToCurrencyDecimals(getContractAddress(cbBTC), '1'),
      0,
      12,
      5000
    );
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
      oneEther.div(10).toFixed(0),
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
      (await helpersContract.getUserReserveData(getContractAddress(cbBTC), deployer.address))
        .usageAsCollateralEnabled
    ).to.be.true;
  });

  it('User 3 deposits 1000 USDC, user 4 deposits 1 cbBTC, user 4 borrows - drops HF, liquidates the borrow', async () => {
    const { users, pool, usdc, oracle, cbBTC, helpersContract, mockLoanProvider, addressesProvider, mockLoan } = testEnv;
    const depositor = users[3];
    const borrower = users[4];

    //user 3 deposits 1000 USDC
    const amountUsdctoDeposit = await convertToCurrencyDecimals(getContractAddress(usdc), '1000');
    await addressesProvider.setBitmorLoan(getContractAddress(mockLoanProvider));
    await usdc.connect(depositor.signer).mint(amountUsdctoDeposit);
    await usdc.connect(depositor.signer).approve(getContractAddress(mockLoanProvider), APPROVAL_AMOUNT_LENDING_POOL);
    await mockLoanProvider
      .connect(depositor.signer)
      .deposit(getContractAddress(usdc), amountUsdctoDeposit, depositor.address, '0');

    //user 4 deposits 1 WETH via vault
    const amountCbBtctoDeposit = await convertToCurrencyDecimals(getContractAddress(cbBTC), '1');
    await cbBTC.connect(borrower.signer).mint(amountCbBtctoDeposit);
    await cbBTC.connect(borrower.signer).approve(getContractAddress(mockLoanProvider), APPROVAL_AMOUNT_LENDING_POOL);
    await mockLoanProvider
      .connect(borrower.signer)
      .deposit(getContractAddress(cbBTC), amountCbBtctoDeposit, borrower.address, '0');


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

    const {stableDebtTokenAddress} = await helpersContract.getReserveTokensAddresses(getContractAddress(usdc));
    const Vdt = await DRE.ethers.getContractAt("VariableDebtToken", stableDebtTokenAddress);
    await Vdt.connect(borrower.signer).approveDelegation(
      mockLoanProvider.target,
      "0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"
    ); 

    await mockLoanProvider
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
    const ethReserveDataBefore = await helpersContract.getReserveData(getContractAddress(cbBTC));

    const amountToLiquidate = new BigNumber(userReserveDataBefore.currentStableDebt.toString())
      .toFixed(0);

    await mockLoan.createActiveLoan(
      borrower.address,
      borrower.address,
      await convertToCurrencyDecimals(getContractAddress(cbBTC), '1'),
      0,
      12,
      5000
    );
    const cbbtcPrice = await oracle.getAssetPrice(getContractAddress(cbBTC));
    await mockLoan.makeLoanOverdue(borrower.address, 30);
    await oracle.setAssetPrice(cbBTC.target, (cbbtcPrice * 95n)/100n);
    await addressesProvider.setBitmorLoan(getContractAddress(mockLoan));


    await pool.liquidationCall(
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

    const usdcReserveDataAfter = await helpersContract.getReserveData(getContractAddress(usdc));
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

    expect(userGlobalDataAfter.healthFactor.toString()).to.be.greaterThan(
      oneEther.div(10).toFixed(0),
      'Invalid health factor'
    );

    expect(userReserveDataAfter.currentVariableDebt.toString()).to.be.almostEqual(
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

  it('User 5 deposits 10000 USDC, liquidation fails because the health factor is below threshold', async () => {
    const {users, usdc, mockLoanProvider, mockLoan, helpersContract, pool, addressesProvider, cbBTC, oracle} = testEnv;
    const user = users[5];
    await addressesProvider.setBitmorLoan(mockLoanProvider);
    const amountBtcToDeposit = await convertToCurrencyDecimals(getContractAddress(cbBTC), '0.1');
    await cbBTC.connect(user.signer).mint(amountBtcToDeposit);
    await cbBTC.connect(user.signer).approve(getContractAddress(mockLoanProvider), APPROVAL_AMOUNT_LENDING_POOL);
    await mockLoanProvider
      .connect(user.signer)
      .deposit(getContractAddress(cbBTC), amountBtcToDeposit, user.address, '0');
    
    
    const amountUsdcToBorrow = await convertToCurrencyDecimals(getContractAddress(usdc), '5000');
    
    await mockLoan.createActiveLoan(
      user.address,
      user.address,
      amountBtcToDeposit,
      amountUsdcToBorrow,
      12,
      5000
    );
  
    const {variableDebtTokenAddress} = await helpersContract.getReserveTokensAddresses(getContractAddress(usdc));
    const Vdt = await DRE.ethers.getContractAt("VariableDebtToken", variableDebtTokenAddress);
    await Vdt.connect(user.signer).approveDelegation(
      mockLoanProvider.target,
      "0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"
    );
  
    await mockLoanProvider
      .connect(user.signer)
      .borrow(getContractAddress(usdc), amountUsdcToBorrow, RateMode.Variable, '0', user.address);
    
    const poolAccountData = await pool.getUserAccountData(mockLoanProvider.target);
    const userAccountData = await pool.getUserAccountData(user.address);

    console.log("poolAccountData:: ", poolAccountData);
    console.log("userAccountData:: ", userAccountData);

    await addressesProvider.setBitmorLoan(mockLoan.target);
    // let type = await pool.checkTypeOfLiquidation(user.address);
    // console.log("type:: ", type);
    // const price = await oracle.getAssetPrice(getContractAddress(cbBTC));
    // console.log("price:: ", price);
    // const newPrice = (new BigNumber(price) * new BigNumber(50)) / new BigNumber(100);
    // const newPrice = (price * 8980n) / 10000n;
    // console.log("newPrice:: ", newPrice);
    // await oracle.setAssetPrice(getContractAddress(cbBTC), newPrice);
    await mockLoan.setLoanStatus(user.address, 2n);
    const type = await pool.checkTypeOfLiquidation(user.address);
    expect(type.toString()).to.be.equals("0");
    // console.log("type:: ", type);
    // const userAccountData2 = await pool.getUserAccountData(user.address);
    // console.log("userAccountData2:: ", userAccountData2);
  })

  it('Check type of liquidation should return 0 for inactive loans', async() => {})
});
