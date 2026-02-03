import BigNumber from "bignumber.js";

import { DRE, increaseTime } from '../../helpers/misc-utils.js';
import { APPROVAL_AMOUNT_LENDING_POOL, oneEther } from '../../helpers/constants.js';
import { convertToCurrencyDecimals, getContractAddress } from '../../helpers/contracts-helpers.js';
import { makeSuite } from './helpers/make-suite.js';
import { ProtocolErrors, RateMode } from '../../helpers/types.js';
import { calcExpectedVariableDebtTokenBalance } from './helpers/utils/calculations.js';
import { getUserData, getReserveData } from './helpers/utils/helpers.js';

import { parseEther } from 'ethers';

import chai from 'chai';
const { expect } = chai;

/**
 * BITMOR ARCHITECTURE - Liquidation Tests (receiving underlying asset)
 *
 * These tests validate liquidation where liquidator receives underlying collateral (not aTokens).
 *
 * Key differences from standard Aave V2:
 * - Uses cbBTC as collateral, USDC as debt (Bitmor's supported assets)
 * - Deposits go through mockLoanProvider (registered as BitmorLoan)
 * - Borrows require credit delegation to mockLoanProvider
 * - Liquidations require active loan in mockLoan + loan must be overdue
 * - BitmorLoan address switches between mockLoanProvider (deposits/borrows) and mockLoan (liquidations)
 */
makeSuite('LendingPool liquidation - liquidator receiving the underlying asset', (testEnv) => {
  const {
    INVALID_HF,
    VL_NO_ACTIVE_RESERVE
  } = ProtocolErrors;

  before('Before LendingPool liquidation: set config', () => {
    BigNumber.config({ DECIMAL_PLACES: 0, ROUNDING_MODE: BigNumber.ROUND_DOWN });
  });

  after('After LendingPool liquidation: reset config', () => {
    BigNumber.config({ DECIMAL_PLACES: 20, ROUNDING_MODE: BigNumber.ROUND_HALF_UP });
  });

  it("It's not possible to liquidate on a non-active collateral or a non active principal", async () => {
    const { configurator, cbBTC, pool, users, usdc, mockLoan, addressesProvider } = testEnv;
    const user = users[1];

    // Set mockLoan as BitmorLoan for liquidation checks
    await addressesProvider.setBitmorLoan(getContractAddress(mockLoan));

    // Deactivate cbBTC (collateral)
    await configurator.deactivateReserve(getContractAddress(cbBTC));

    await expect(
      pool.liquidationCall(getContractAddress(cbBTC), getContractAddress(usdc), user.address, parseEther('1000'), false)
    ).to.be.revertedWith(VL_NO_ACTIVE_RESERVE);

    await configurator.activateReserve(getContractAddress(cbBTC));

    // Deactivate USDC (debt asset)
    await configurator.deactivateReserve(getContractAddress(usdc));

    await expect(
      pool.liquidationCall(getContractAddress(cbBTC), getContractAddress(usdc), user.address, parseEther('1000'), false)
    ).to.be.revertedWith(VL_NO_ACTIVE_RESERVE);

    await configurator.activateReserve(getContractAddress(usdc));
  });

  it('Deposits cbBTC, borrows USDC', async () => {
    const { usdc, cbBTC, users, pool, oracle, mockLoanProvider, mockLoan, addressesProvider, helpersContract } = testEnv;
    const depositor = users[0];
    const borrower = users[1];

    // Set mockLoanProvider as BitmorLoan for deposits
    await addressesProvider.setBitmorLoan(getContractAddress(mockLoanProvider));

    // User 1 deposits 100,000,000 USDC (liquidity for borrowing)
    const amountUSDCtoDeposit = await convertToCurrencyDecimals(getContractAddress(usdc), '100000000');
    await usdc.connect(depositor.signer).mint(amountUSDCtoDeposit);
    await usdc.connect(depositor.signer).approve(getContractAddress(mockLoanProvider), APPROVAL_AMOUNT_LENDING_POOL);
    await mockLoanProvider
      .connect(depositor.signer)
      .deposit(getContractAddress(usdc), amountUSDCtoDeposit, depositor.address, '0');

    // User 2 deposits 1 cbBTC as collateral
    const amountCbBTCtoDeposit = await convertToCurrencyDecimals(getContractAddress(cbBTC), '1');
    await cbBTC.connect(borrower.signer).mint(amountCbBTCtoDeposit);
    await cbBTC.connect(borrower.signer).approve(getContractAddress(mockLoanProvider), APPROVAL_AMOUNT_LENDING_POOL);
    await mockLoanProvider
      .connect(borrower.signer)
      .deposit(getContractAddress(cbBTC), amountCbBTCtoDeposit, borrower.address, '0');

    // Calculate borrow amount (95% of available)
    const userGlobalData = await pool.getUserAccountData(borrower.address);
    const usdcPrice = await oracle.getAssetPrice(getContractAddress(usdc));

    const amountUSDCToBorrow = await convertToCurrencyDecimals(
      getContractAddress(usdc),
      new BigNumber(userGlobalData.availableBorrowsETH.toString())
        .div(usdcPrice.toString())
        .multipliedBy(0.95)
        .toFixed(0)
    );

    // Create active loan in mockLoan for the borrower
    await mockLoan.createActiveLoan(
      borrower.address,
      borrower.address,
      amountCbBTCtoDeposit,
      amountUSDCToBorrow,
      12,
      5000
    );

    // Approve credit delegation to mockLoanProvider for variable debt
    const { variableDebtTokenAddress } = await helpersContract.getReserveTokensAddresses(getContractAddress(usdc));
    const Vdt = await DRE.ethers.getContractAt("VariableDebtToken", variableDebtTokenAddress);
    await Vdt.connect(borrower.signer).approveDelegation(
      mockLoanProvider.target,
      "0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"
    );

    // User 2 borrows USDC via mockLoanProvider
    await mockLoanProvider
      .connect(borrower.signer)
      .borrow(getContractAddress(usdc), amountUSDCToBorrow, RateMode.Variable, '0', borrower.address);

    const userGlobalDataAfter = await pool.getUserAccountData(borrower.address);

    expect(userGlobalDataAfter.currentLiquidationThreshold.toString()).to.be.equal(
      '8000',
      INVALID_HF
    );
  });

  it('Drop the health factor below 1', async () => {
    const { cbBTC, users, pool, oracle } = testEnv;
    const borrower = users[1];

    const cbBTCPrice = await oracle.getAssetPrice(getContractAddress(cbBTC));

    // Drop cbBTC price by 20% to push health factor below 1
    await oracle.setAssetPrice(
      getContractAddress(cbBTC),
      new BigNumber(cbBTCPrice.toString()).multipliedBy(0.80).toFixed(0)
    );

    const userGlobalData = await pool.getUserAccountData(borrower.address);

    expect(userGlobalData.healthFactor.toString()).to.be.lessThan(
      oneEther.toString(),
      INVALID_HF
    );
  });

  it('Liquidates the borrow', async () => {
    const { usdc, cbBTC, users, pool, oracle, helpersContract, mockLoan, addressesProvider } = testEnv;
    const liquidator = users[3];
    const borrower = users[1];

    // Mint USDC to the liquidator
    await usdc.connect(liquidator.signer).mint(await convertToCurrencyDecimals(getContractAddress(usdc), '1000000'));

    // Approve protocol to access the liquidator wallet
    await usdc.connect(liquidator.signer).approve(getContractAddress(pool), APPROVAL_AMOUNT_LENDING_POOL);

    const usdcReserveDataBefore = await helpersContract.getReserveData(getContractAddress(usdc));
    const cbBTCReserveDataBefore = await helpersContract.getReserveData(getContractAddress(cbBTC));

    const userReserveDataBefore = await getUserData(
      pool,
      helpersContract,
      getContractAddress(usdc),
      borrower.address
    );

    const amountToLiquidate = new BigNumber(userReserveDataBefore.currentVariableDebt.toString())
      .div(2)
      .toFixed(0);

    // Make the loan overdue so it can be liquidated
    await mockLoan.makeLoanOverdue(borrower.address, 30);

    // Set mockLoan as BitmorLoan for liquidation
    await addressesProvider.setBitmorLoan(getContractAddress(mockLoan));

    await increaseTime(100);

    const tx = await pool
      .connect(liquidator.signer)
      .liquidationCall(getContractAddress(cbBTC), getContractAddress(usdc), borrower.address, amountToLiquidate, false);

    const userReserveDataAfter = await getUserData(
      pool,
      helpersContract,
      getContractAddress(usdc),
      borrower.address
    );

    const usdcReserveDataAfter = await helpersContract.getReserveData(getContractAddress(usdc));
    const cbBTCReserveDataAfter = await helpersContract.getReserveData(getContractAddress(cbBTC));

    const collateralPrice = await oracle.getAssetPrice(getContractAddress(cbBTC));
    const principalPrice = await oracle.getAssetPrice(getContractAddress(usdc));

    const collateralDecimals = (
      await helpersContract.getReserveConfigurationData(getContractAddress(cbBTC))
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

    if (!tx.blockNumber) {
      expect(false, 'Invalid block number');
      return;
    }
    const txTimestamp = new BigNumber(
      (await DRE.ethers.provider.getBlock(tx.blockNumber)).timestamp
    );

    const variableDebtBeforeTx = calcExpectedVariableDebtTokenBalance(
      await getReserveData(helpersContract, getContractAddress(usdc)),
      userReserveDataBefore,
      txTimestamp
    );

    expect(userReserveDataAfter.currentVariableDebt.toString()).to.be.almostEqual(
      variableDebtBeforeTx.minus(amountToLiquidate).toFixed(0),
      'Invalid user debt after liquidation'
    );

    // The liquidity index of the principal reserve needs to be bigger than the index before
    expect(usdcReserveDataAfter.liquidityIndex.toString()).to.be.greaterThanOrEqual(
      usdcReserveDataBefore.liquidityIndex.toString(),
      'Invalid liquidity index'
    );

    // The principal APY after a liquidation needs to be lower than the APY before
    expect(usdcReserveDataAfter.liquidityRate.toString()).to.be.lessThan(
      usdcReserveDataBefore.liquidityRate.toString(),
      'Invalid liquidity APY'
    );

    expect(usdcReserveDataAfter.availableLiquidity.toString()).to.be.almostEqual(
      new BigNumber(usdcReserveDataBefore.availableLiquidity.toString())
        .plus(amountToLiquidate)
        .toFixed(0),
      'Invalid principal available liquidity'
    );

    expect(cbBTCReserveDataAfter.availableLiquidity.toString()).to.be.almostEqual(
      new BigNumber(cbBTCReserveDataBefore.availableLiquidity.toString())
        .minus(expectedCollateralLiquidated)
        .toFixed(0),
      'Invalid collateral available liquidity'
    );
  });

  it('User 3 deposits 1000 USDC, user 4 deposits 1 cbBTC, user 4 borrows - drops HF, liquidates the borrow', async () => {
    const { usdc, users, pool, oracle, cbBTC, helpersContract, mockLoanProvider, mockLoan, addressesProvider } = testEnv;

    const depositor = users[3];
    const borrower = users[4];
    const liquidator = users[5];

    // Set mockLoanProvider as BitmorLoan for deposits/borrows
    await addressesProvider.setBitmorLoan(getContractAddress(mockLoanProvider));

    // Depositor deposits 1000 USDC
    const amountUSDCtoDeposit = await convertToCurrencyDecimals(getContractAddress(usdc), '100000');
    await usdc.connect(depositor.signer).mint(amountUSDCtoDeposit);
    await usdc.connect(depositor.signer).approve(getContractAddress(mockLoanProvider), APPROVAL_AMOUNT_LENDING_POOL);
    await mockLoanProvider
      .connect(depositor.signer)
      .deposit(getContractAddress(usdc), amountUSDCtoDeposit, depositor.address, '0');

    // Borrower deposits 1 cbBTC
    const amountCbBTCtoDeposit = await convertToCurrencyDecimals(getContractAddress(cbBTC), '1');
    await cbBTC.connect(borrower.signer).mint(amountCbBTCtoDeposit);
    await cbBTC.connect(borrower.signer).approve(getContractAddress(mockLoanProvider), APPROVAL_AMOUNT_LENDING_POOL);
    await mockLoanProvider
      .connect(borrower.signer)
      .deposit(getContractAddress(cbBTC), amountCbBTCtoDeposit, borrower.address, '0');

    // Borrower borrows USDC
    const userGlobalData = await pool.getUserAccountData(borrower.address);
    const usdcPrice = await oracle.getAssetPrice(getContractAddress(usdc));
    const cbbtcPrice = await oracle.getAssetPrice(getContractAddress(cbBTC));

    const amountUSDCToBorrow = await convertToCurrencyDecimals(
      getContractAddress(usdc),
      new BigNumber(userGlobalData.availableBorrowsETH.toString())
        .div(usdcPrice.toString())
        .multipliedBy(0.9502)
        .toFixed(0)
    );

    // Approve credit delegation for variable debt
    const { variableDebtTokenAddress } = await helpersContract.getReserveTokensAddresses(getContractAddress(usdc));
    const Vdt = await DRE.ethers.getContractAt("VariableDebtToken", variableDebtTokenAddress);
    await Vdt.connect(borrower.signer).approveDelegation(
      mockLoanProvider.target,
      "0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"
    );

    await mockLoanProvider
      .connect(borrower.signer)
      .borrow(getContractAddress(usdc), amountUSDCToBorrow, RateMode.Variable, '0', borrower.address);

    // Raise USDC price to push HF below 1
    await oracle.setAssetPrice(
      getContractAddress(usdc),
      new BigNumber(usdcPrice.toString()).multipliedBy(1.12).toFixed(0)
    );

    // Mint USDC to the liquidator (enough to cover the debt)
    await usdc
      .connect(liquidator.signer)
      .mint(await convertToCurrencyDecimals(getContractAddress(usdc), '100000'));

    // Approve protocol to access liquidator wallet
    await usdc.connect(liquidator.signer).approve(getContractAddress(pool), APPROVAL_AMOUNT_LENDING_POOL);

    const userReserveDataBefore = await helpersContract.getUserReserveData(
      getContractAddress(usdc),
      borrower.address
    );

    const usdcReserveDataBefore = await helpersContract.getReserveData(getContractAddress(usdc));
    const cbBTCReserveDataBefore = await helpersContract.getReserveData(getContractAddress(cbBTC));

    const amountToLiquidate = new BigNumber(
      userReserveDataBefore.currentVariableDebt.toString()
    ).toFixed(0);

    // Create active loan AFTER borrow, then make it overdue
    await mockLoan.createActiveLoan(
      borrower.address,
      borrower.address,
      amountCbBTCtoDeposit,
      0,
      12,
      5000
    );

    // Update mockLoan's collateral asset to match cbBTC address
    await mockLoan.setCollateralAssetAddress(getContractAddress(cbBTC));

    // Drop cbBTC price by 20% to push HF below 1 and make loan overdue
    const cbBTCPrice = await oracle.getAssetPrice(getContractAddress(cbBTC));
    await mockLoan.makeLoanOverdue(borrower.address, 30);
    await oracle.setAssetPrice(getContractAddress(cbBTC), (cbBTCPrice * 40n) / 100n);
    await addressesProvider.setBitmorLoan(getContractAddress(mockLoan));

    await increaseTime(100);

    await pool
      .connect(liquidator.signer)
      .liquidationCall(getContractAddress(cbBTC), getContractAddress(usdc), borrower.address, amountToLiquidate, false);

    const userReserveDataAfter = await helpersContract.getUserReserveData(
      getContractAddress(usdc),
      borrower.address
    );

    const usdcReserveDataAfter = await helpersContract.getReserveData(getContractAddress(usdc));
    const cbBTCReserveDataAfter = await helpersContract.getReserveData(getContractAddress(cbBTC));

    const collateralPrice = await oracle.getAssetPrice(getContractAddress(cbBTC));
    const principalPrice = await oracle.getAssetPrice(getContractAddress(usdc));

    const collateralDecimals = (
      await helpersContract.getReserveConfigurationData(getContractAddress(cbBTC))
    ).decimals.toString();
    const principalDecimals = (
      await helpersContract.getReserveConfigurationData(getContractAddress(usdc))
    ).decimals.toString();

    const liquidationBonus = (
      await helpersContract.getReserveConfigurationData(getContractAddress(cbBTC))
    ).liquidationBonus.toString();

    // Calculate expected collateral to liquidate for the requested debt
    const expectedCollateralLiquidated = new BigNumber(principalPrice.toString())
      .times(new BigNumber(amountToLiquidate).times(liquidationBonus))
      .times(new BigNumber(10).pow(collateralDecimals))
      .div(
        new BigNumber(collateralPrice.toString()).times(new BigNumber(10).pow(principalDecimals))
      )
      .div(10000)
      .decimalPlaces(0, BigNumber.ROUND_DOWN);

    // Get user's collateral balance before liquidation (1 cbBTC = 1e8)
    const userCollateralBalance = new BigNumber(amountCbBTCtoDeposit.toString());

    // If position is underwater, only partial debt can be liquidated
    let actualDebtLiquidated: BigNumber;
    let actualCollateralLiquidated: BigNumber;

    if (expectedCollateralLiquidated.gt(userCollateralBalance)) {
      // Underwater: all collateral is taken, calculate debt covered
      actualCollateralLiquidated = userCollateralBalance;
      actualDebtLiquidated = new BigNumber(collateralPrice.toString())
        .times(userCollateralBalance)
        .times(new BigNumber(10).pow(principalDecimals))
        .div(new BigNumber(principalPrice.toString()).times(new BigNumber(10).pow(collateralDecimals)))
        .times(10000)
        .div(liquidationBonus)
        .decimalPlaces(0, BigNumber.ROUND_DOWN);
    } else {
      // Sufficient collateral: full debt is liquidated
      actualCollateralLiquidated = expectedCollateralLiquidated;
      actualDebtLiquidated = new BigNumber(amountToLiquidate);
    }

    expect(userReserveDataAfter.currentVariableDebt.toString()).to.be.almostEqual(
      new BigNumber(userReserveDataBefore.currentVariableDebt.toString())
        .minus(actualDebtLiquidated)
        .toFixed(0),
      'Invalid user borrow balance after liquidation'
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

    expect(usdcReserveDataAfter.availableLiquidity.toString()).to.be.almostEqual(
      new BigNumber(usdcReserveDataBefore.availableLiquidity.toString())
        .plus(actualDebtLiquidated)
        .toFixed(0),
      'Invalid principal available liquidity'
    );

    expect(cbBTCReserveDataAfter.availableLiquidity.toString()).to.be.almostEqual(
      new BigNumber(cbBTCReserveDataBefore.availableLiquidity.toString())
        .minus(actualCollateralLiquidated)
        .toFixed(0),
      'Invalid collateral available liquidity'
    );
  });
});
