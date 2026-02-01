import { makeSuite } from '../helpers/make-suite.js';
import type { TestEnv } from '../helpers/make-suite.js';
import {
  convertToCurrencyDecimals,
  buildFlashLiquidationAdapterParams,
  getContractAddress
} from '../../../helpers/contracts-helpers.js';
import { getMockUniswapRouter } from '../../../helpers/contracts-getters.js';
import { deployFlashLiquidationAdapter } from '../../../helpers/contracts-deployments.js';
import type { MockUniswapV2Router02 } from '../../../types/ethers-contracts/index.js';
import BigNumber from "bignumber.js";

import { DRE, evmRevert, evmSnapshot, increaseTime, waitForTx } from '../../../helpers/misc-utils.js';
import { parseEther } from 'ethers';
import { ProtocolErrors, RateMode } from '../../../helpers/types.js';
import { APPROVAL_AMOUNT_LENDING_POOL, MAX_UINT_AMOUNT, oneEther } from '../../../helpers/constants.js';
import { getUserData } from '../helpers/utils/helpers.js';
import { calcExpectedStableDebtTokenBalance } from '../helpers/utils/calculations.js';
import chai from 'chai';
const { expect } = chai;

makeSuite('Uniswap adapters', (testEnv: TestEnv) => {
  let mockUniswapRouter: MockUniswapV2Router02;
  let evmSnapshotId: string;
  const { INVALID_HF, LP_LIQUIDATION_CALL_FAILED } = ProtocolErrors;

  before(async () => {
    mockUniswapRouter = await getMockUniswapRouter();
  });

  const depositAndHFBelowOne = async () => {
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

    const userGlobalDataBefore = await pool.getUserAccountData(borrower.address);
    const daiPrice = await oracle.getAssetPrice(getContractAddress(dai));

    const amountDAIToBorrow = await convertToCurrencyDecimals(
      getContractAddress(dai),
      new BigNumber(userGlobalDataBefore.availableBorrowsETH.toString())
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

    await oracle.setAssetPrice(
      getContractAddress(dai),
      new BigNumber(daiPrice.toString()).multipliedBy(1.18).toFixed(0)
    );

    const userGlobalData = await pool.getUserAccountData(borrower.address);

    expect(userGlobalData.healthFactor.toString()).to.be.lt(
      oneEther.toFixed(0),
      INVALID_HF
    );
  };

  const depositSameAssetAndHFBelowOne = async () => {
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

    const userGlobalDataBefore = await pool.getUserAccountData(borrower.address);
    const daiPrice = await oracle.getAssetPrice(getContractAddress(dai));

    const amountDAIToBorrow = await convertToCurrencyDecimals(
      getContractAddress(dai),
      new BigNumber(userGlobalDataBefore.availableBorrowsETH.toString())
        .div(daiPrice.toString())
        .multipliedBy(0.8)
        .toFixed(0)
    );
    await waitForTx(
      await pool
        .connect(borrower.signer)
        .borrow(getContractAddress(dai), amountDAIToBorrow, RateMode.Stable, '0', borrower.address)
    );

    const userGlobalDataBefore2 = await pool.getUserAccountData(borrower.address);

    const amountWETHToBorrow = new BigNumber(userGlobalDataBefore2.availableBorrowsETH.toString())
      .multipliedBy(0.8)
      .toFixed(0);

    await pool
      .connect(borrower.signer)
      .borrow(getContractAddress(weth), amountWETHToBorrow, RateMode.Variable, '0', borrower.address);

    const userGlobalDataAfter = await pool.getUserAccountData(borrower.address);

    expect(userGlobalDataAfter.currentLiquidationThreshold.toString()).to.be.equal(
      '8250',
      INVALID_HF
    );

    await oracle.setAssetPrice(
      getContractAddress(dai),
      new BigNumber(daiPrice.toString()).multipliedBy(1.18).toFixed(0)
    );

    const userGlobalData = await pool.getUserAccountData(borrower.address);

    expect(userGlobalData.healthFactor.toString()).to.be.lt(
      oneEther.toFixed(0),
      INVALID_HF
    );
  };

  beforeEach(async () => {
    evmSnapshotId = await evmSnapshot();
  });

  afterEach(async () => {
    await evmRevert(evmSnapshotId);
  });

  describe('Flash Liquidation Adapter', () => {
    before('Before LendingPool liquidation: set config', () => {
      BigNumber.config({ DECIMAL_PLACES: 0, ROUNDING_MODE: BigNumber.ROUND_DOWN });
    });

    after('After LendingPool liquidation: reset config', () => {
      BigNumber.config({ DECIMAL_PLACES: 20, ROUNDING_MODE: BigNumber.ROUND_HALF_UP });
    });

    describe('constructor', () => {
      it('should deploy with correct parameters', async () => {
        const { addressesProvider, weth } = testEnv;
        await deployFlashLiquidationAdapter([
          getContractAddress(addressesProvider),
          getContractAddress(mockUniswapRouter),
          getContractAddress(weth),
        ]);
      });

      it('should revert if not valid addresses provider', async () => {
        const { weth } = testEnv;
        await expect(
          deployFlashLiquidationAdapter([
            getContractAddress(mockUniswapRouter),
            getContractAddress(mockUniswapRouter),
            getContractAddress(weth),
          ])
        ).to.be.revert(DRE.ethers);
      });
    });

    describe('executeOperation: succesfully liquidateCall and swap via Flash Loan with profits', () => {
      it('Liquidates the borrow with profit', async () => {
        await depositAndHFBelowOne();
        await increaseTime(100);

        const {
          dai,
          weth,
          users,
          pool,
          oracle,
          helpersContract,
          flashLiquidationAdapter,
        } = testEnv;

        const liquidator = users[3];
        const borrower = users[1];
        const expectedSwap = parseEther('0.4');

        const liquidatorWethBalanceBefore = await weth.balanceOf(liquidator.address);

        // Set how much ETH will be sold and swapped for DAI at Uniswap mock
        await (await mockUniswapRouter.setAmountToSwap(getContractAddress(weth), expectedSwap)).wait();

        const collateralPrice = await oracle.getAssetPrice(getContractAddress(weth));
        const principalPrice = await oracle.getAssetPrice(getContractAddress(dai));
        const daiReserveDataBefore = await helpersContract.getReserveData(getContractAddress(dai));
        const ethReserveDataBefore = await helpersContract.getReserveData(getContractAddress(weth));
        const userReserveDataBefore = await getUserData(
          pool,
          helpersContract,
          getContractAddress(dai),
          borrower.address
        );

        const collateralDecimals = (
          await helpersContract.getReserveConfigurationData(getContractAddress(weth))
        ).decimals.toString();
        const principalDecimals = (
          await helpersContract.getReserveConfigurationData(getContractAddress(dai))
        ).decimals.toString();
        const amountToLiquidate = new BigNumber(userReserveDataBefore.currentStableDebt.toString())
          .div(2)
          .toFixed(0);

        const expectedCollateralLiquidated = new BigNumber(principalPrice.toString())
          .times(new BigNumber(amountToLiquidate).times(105))
          .times(new BigNumber(10).pow(collateralDecimals))
          .div(
            new BigNumber(collateralPrice.toString()).times(
              new BigNumber(10).pow(principalDecimals)
            )
          )
          .div(100)
          .decimalPlaces(0, BigNumber.ROUND_DOWN);

        const flashLoanDebt = new BigNumber(amountToLiquidate.toString())
          .multipliedBy(1.0009)
          .toFixed(0);

        const expectedProfit = BigInt(expectedCollateralLiquidated.toString()) - expectedSwap;

        const params = buildFlashLiquidationAdapterParams(
          getContractAddress(weth),
          getContractAddress(dai),
          borrower.address,
          amountToLiquidate,
          false
        );
        const tx = await pool
          .connect(liquidator.signer)
          .flashLoan(
            getContractAddress(flashLiquidationAdapter),
            [getContractAddress(dai)],
            [amountToLiquidate],
            [0],
            borrower.address,
            params,
            0
          );

        // Expect Swapped event
        await expect(Promise.resolve(tx)).to.emit(flashLiquidationAdapter, 'Swapped');

        // Expect LiquidationCall event
        await expect(Promise.resolve(tx)).to.emit(pool, 'LiquidationCall');

        const userReserveDataAfter = await getUserData(
          pool,
          helpersContract,
          getContractAddress(dai),
          borrower.address
        );
        const liquidatorWethBalanceAfter = await weth.balanceOf(liquidator.address);

        const daiReserveDataAfter = await helpersContract.getReserveData(getContractAddress(dai));
        const ethReserveDataAfter = await helpersContract.getReserveData(getContractAddress(weth));

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

        const collateralAssetContractBalance = await weth.balanceOf(
          getContractAddress(flashLiquidationAdapter)
        );
        const borrowAssetContractBalance = await dai.balanceOf(getContractAddress(flashLiquidationAdapter));

        expect(collateralAssetContractBalance).to.be.equal(
          '0',
          'Contract address should not keep any balance.'
        );
        expect(borrowAssetContractBalance).to.be.equal(
          '0',
          'Contract address should not keep any balance.'
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
            .plus(flashLoanDebt)
            .toFixed(0),
          'Invalid principal available liquidity'
        );

        expect(ethReserveDataAfter.availableLiquidity.toString()).to.be.almostEqual(
          new BigNumber(ethReserveDataBefore.availableLiquidity.toString())
            .minus(expectedCollateralLiquidated)
            .toFixed(0),
          'Invalid collateral available liquidity'
        );

        // Profit after flash loan liquidation
        expect(liquidatorWethBalanceAfter).to.be.equal(
          (liquidatorWethBalanceBefore + expectedProfit),
          'Invalid expected WETH profit'
        );
      });
    });

    describe('executeOperation: succesfully liquidateCall with same asset via Flash Loan, but no swap needed', () => {
      it('Liquidates the borrow with profit', async () => {
        await depositSameAssetAndHFBelowOne();
        await increaseTime(100);

        const { weth, users, pool, oracle, helpersContract, flashLiquidationAdapter } = testEnv;

        const liquidator = users[3];
        const borrower = users[1];

        const liquidatorWethBalanceBefore = await weth.balanceOf(liquidator.address);

        const assetPrice = await oracle.getAssetPrice(getContractAddress(weth));
        const ethReserveDataBefore = await helpersContract.getReserveData(getContractAddress(weth));
        const userReserveDataBefore = await getUserData(
          pool,
          helpersContract,
          getContractAddress(weth),
          borrower.address
        );

        const assetDecimals = (
          await helpersContract.getReserveConfigurationData(getContractAddress(weth))
        ).decimals.toString();
        const amountToLiquidate = new BigNumber(userReserveDataBefore.currentVariableDebt.toString())
          .div(2)
          .toFixed(0);

        const expectedCollateralLiquidated = new BigNumber(assetPrice.toString())
          .times(new BigNumber(amountToLiquidate).times(105))
          .times(new BigNumber(10).pow(assetDecimals))
          .div(new BigNumber(assetPrice.toString()).times(new BigNumber(10).pow(assetDecimals)))
          .div(100)
          .decimalPlaces(0, BigNumber.ROUND_DOWN);

        const flashLoanDebt = new BigNumber(amountToLiquidate.toString())
          .multipliedBy(1.0009)
          .toFixed(0);

        const params = buildFlashLiquidationAdapterParams(
          getContractAddress(weth),
          getContractAddress(weth),
          borrower.address,
          amountToLiquidate,
          false
        );
        const tx = await pool
          .connect(liquidator.signer)
          .flashLoan(
            getContractAddress(flashLiquidationAdapter),
            [getContractAddress(weth)],
            [amountToLiquidate],
            [0],
            borrower.address,
            params,
            0
          );

        // Dont expect Swapped event due is same asset
        await expect(Promise.resolve(tx)).to.not.emit(flashLiquidationAdapter, 'Swapped');

        // Expect LiquidationCall event
        await expect(Promise.resolve(tx))
          .to.emit(pool, 'LiquidationCall')
          .withArgs(
            getContractAddress(weth),
            getContractAddress(weth),
            borrower.address,
            amountToLiquidate.toString(),
            expectedCollateralLiquidated.toString(),
            getContractAddress(flashLiquidationAdapter),
            false
          );

        const borrowAssetContractBalance = await weth.balanceOf(getContractAddress(flashLiquidationAdapter));

        expect(borrowAssetContractBalance).to.be.equal(
          '0',
          'Contract address should not keep any balance.'
        );
      });
    });

    describe('executeOperation: succesfully liquidateCall and swap via Flash Loan without profits', () => {
      it('Liquidates the borrow', async () => {
        await depositAndHFBelowOne();
        await increaseTime(100);

        const {
          dai,
          weth,
          users,
          pool,
          oracle,
          helpersContract,
          flashLiquidationAdapter,
        } = testEnv;

        const liquidator = users[3];
        const borrower = users[1];
        const liquidatorWethBalanceBefore = await weth.balanceOf(liquidator.address);

        const collateralPrice = await oracle.getAssetPrice(getContractAddress(weth));
        const principalPrice = await oracle.getAssetPrice(getContractAddress(dai));
        const daiReserveDataBefore = await helpersContract.getReserveData(getContractAddress(dai));
        const ethReserveDataBefore = await helpersContract.getReserveData(getContractAddress(weth));
        const userReserveDataBefore = await getUserData(
          pool,
          helpersContract,
          getContractAddress(dai),
          borrower.address
        );

        const collateralDecimals = (
          await helpersContract.getReserveConfigurationData(getContractAddress(weth))
        ).decimals.toString();
        const principalDecimals = (
          await helpersContract.getReserveConfigurationData(getContractAddress(dai))
        ).decimals.toString();
        const amountToLiquidate = new BigNumber(userReserveDataBefore.currentStableDebt.toString())
          .div(2)
          .toFixed(0);

        const expectedCollateralLiquidated = new BigNumber(principalPrice.toString())
          .times(new BigNumber(amountToLiquidate).times(105))
          .times(new BigNumber(10).pow(collateralDecimals))
          .div(
            new BigNumber(collateralPrice.toString()).times(
              new BigNumber(10).pow(principalDecimals)
            )
          )
          .div(100)
          .decimalPlaces(0, BigNumber.ROUND_DOWN);

        const flashLoanDebt = new BigNumber(amountToLiquidate.toString())
          .multipliedBy(1.0009)
          .toFixed(0);

        // Set how much ETH will be sold and swapped for DAI at Uniswap mock
        await (
          await mockUniswapRouter.setAmountToSwap(
            getContractAddress(weth),
            expectedCollateralLiquidated.toString()
          )
        ).wait();

        const params = buildFlashLiquidationAdapterParams(
          getContractAddress(weth),
          getContractAddress(dai),
          borrower.address,
          amountToLiquidate,
          false
        );
        const tx = await pool
          .connect(liquidator.signer)
          .flashLoan(
            getContractAddress(flashLiquidationAdapter),
            [getContractAddress(dai)],
            [flashLoanDebt],
            [0],
            borrower.address,
            params,
            0
          );

        // Expect Swapped event
        await expect(Promise.resolve(tx)).to.emit(flashLiquidationAdapter, 'Swapped');

        // Expect LiquidationCall event
        await expect(Promise.resolve(tx)).to.emit(pool, 'LiquidationCall');

        const userReserveDataAfter = await getUserData(
          pool,
          helpersContract,
          getContractAddress(dai),
          borrower.address
        );
        const liquidatorWethBalanceAfter = await weth.balanceOf(liquidator.address);

        const daiReserveDataAfter = await helpersContract.getReserveData(getContractAddress(dai));
        const ethReserveDataAfter = await helpersContract.getReserveData(getContractAddress(weth));

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

        const collateralAssetContractBalance = await dai.balanceOf(getContractAddress(flashLiquidationAdapter));
        const borrowAssetContractBalance = await weth.balanceOf(getContractAddress(flashLiquidationAdapter));

        expect(collateralAssetContractBalance).to.be.equal(
          '0',
          'Contract address should not keep any balance.'
        );
        expect(borrowAssetContractBalance).to.be.equal(
          '0',
          'Contract address should not keep any balance.'
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

        expect(ethReserveDataAfter.availableLiquidity.toString()).to.be.almostEqual(
          new BigNumber(ethReserveDataBefore.availableLiquidity.toString())
            .minus(expectedCollateralLiquidated)
            .toFixed(0),
          'Invalid collateral available liquidity'
        );

        // Net Profit == 0 after flash loan liquidation
        expect(liquidatorWethBalanceAfter).to.be.equal(
          liquidatorWethBalanceBefore,
          'Invalid expected WETH profit'
        );
      });
    });

    describe('executeOperation: succesfully liquidateCall all available debt and swap via Flash Loan ', () => {
      it('Liquidates the borrow', async () => {
        await depositAndHFBelowOne();
        await increaseTime(100);

        const {
          dai,
          weth,
          users,
          pool,
          oracle,
          helpersContract,
          flashLiquidationAdapter,
        } = testEnv;

        const liquidator = users[3];
        const borrower = users[1];
        const liquidatorWethBalanceBefore = await weth.balanceOf(liquidator.address);

        const collateralPrice = await oracle.getAssetPrice(getContractAddress(weth));
        const principalPrice = await oracle.getAssetPrice(getContractAddress(dai));
        const daiReserveDataBefore = await helpersContract.getReserveData(getContractAddress(dai));
        const ethReserveDataBefore = await helpersContract.getReserveData(getContractAddress(weth));
        const userReserveDataBefore = await getUserData(
          pool,
          helpersContract,
          getContractAddress(dai),
          borrower.address
        );

        const collateralDecimals = (
          await helpersContract.getReserveConfigurationData(getContractAddress(weth))
        ).decimals.toString();
        const principalDecimals = (
          await helpersContract.getReserveConfigurationData(getContractAddress(dai))
        ).decimals.toString();
        const amountToLiquidate = new BigNumber(userReserveDataBefore.currentStableDebt.toString())
          .div(2)
          .toFixed(0);
        const extraAmount = new BigNumber(amountToLiquidate).times('1.15').toFixed(0);

        const expectedCollateralLiquidated = new BigNumber(principalPrice.toString())
          .times(new BigNumber(amountToLiquidate).times(105))
          .times(new BigNumber(10).pow(collateralDecimals))
          .div(
            new BigNumber(collateralPrice.toString()).times(
              new BigNumber(10).pow(principalDecimals)
            )
          )
          .div(100)
          .decimalPlaces(0, BigNumber.ROUND_DOWN);

        const flashLoanDebt = new BigNumber(amountToLiquidate.toString())
          .multipliedBy(1.0009)
          .toFixed(0);

        // Set how much ETH will be sold and swapped for DAI at Uniswap mock
        await (
          await mockUniswapRouter.setAmountToSwap(
            getContractAddress(weth),
            expectedCollateralLiquidated.toString()
          )
        ).wait();

        const params = buildFlashLiquidationAdapterParams(
          getContractAddress(weth),
          getContractAddress(dai),
          borrower.address,
          MAX_UINT_AMOUNT,
          false
        );
        const tx = await pool
          .connect(liquidator.signer)
          .flashLoan(
            getContractAddress(flashLiquidationAdapter),
            [getContractAddress(dai)],
            [extraAmount],
            [0],
            borrower.address,
            params,
            0
          );

        // Expect Swapped event
        await expect(Promise.resolve(tx)).to.emit(flashLiquidationAdapter, 'Swapped');

        // Expect LiquidationCall event
        await expect(Promise.resolve(tx)).to.emit(pool, 'LiquidationCall');

        const collateralAssetContractBalance = await dai.balanceOf(getContractAddress(flashLiquidationAdapter));
        const borrowAssetContractBalance = await dai.balanceOf(getContractAddress(flashLiquidationAdapter));

        expect(collateralAssetContractBalance).to.be.equal(
          '0',
          'Contract address should not keep any balance.'
        );
        expect(borrowAssetContractBalance).to.be.equal(
          '0',
          'Contract address should not keep any balance.'
        );
      });
    });

    describe('executeOperation: invalid params', async () => {
      it('Revert if debt asset is different than requested flash loan token', async () => {
        await depositAndHFBelowOne();

        const { dai, weth, users, pool, helpersContract, flashLiquidationAdapter } = testEnv;

        const liquidator = users[3];
        const borrower = users[1];
        const expectedSwap = parseEther('0.4');

        // Set how much ETH will be sold and swapped for DAI at Uniswap mock
        await (await mockUniswapRouter.setAmountToSwap(getContractAddress(weth), expectedSwap)).wait();

        const userReserveDataBefore = await getUserData(
          pool,
          helpersContract,
          getContractAddress(dai),
          borrower.address
        );

        const amountToLiquidate = new BigNumber(userReserveDataBefore.currentStableDebt.toString())
          .div(2)
          .toFixed(0);

        // Wrong debt asset
        const params = buildFlashLiquidationAdapterParams(
          getContractAddress(weth),
          getContractAddress(weth), // intentionally bad
          borrower.address,
          amountToLiquidate,
          false
        );
        await expect(
          pool
            .connect(liquidator.signer)
            .flashLoan(
              getContractAddress(flashLiquidationAdapter),
              [getContractAddress(dai)],
              [amountToLiquidate],
              [0],
              borrower.address,
              params,
              0
            )
        ).to.be.revertedWith('INCONSISTENT_PARAMS');
      });

      it('Revert if debt asset amount to liquidate is greater than requested flash loan', async () => {
        await depositAndHFBelowOne();

        const { dai, weth, users, pool, helpersContract, flashLiquidationAdapter } = testEnv;

        const liquidator = users[3];
        const borrower = users[1];
        const expectedSwap = parseEther('0.4');

        // Set how much ETH will be sold and swapped for DAI at Uniswap mock
        await (await mockUniswapRouter.setAmountToSwap(getContractAddress(weth), expectedSwap)).wait();

        const userReserveDataBefore = await getUserData(
          pool,
          helpersContract,
          getContractAddress(dai),
          borrower.address
        );

        const amountToLiquidate = BigInt(userReserveDataBefore.currentStableDebt) / 2n;

        // Correct params
        const params = buildFlashLiquidationAdapterParams(
          getContractAddress(weth),
          getContractAddress(dai),
          borrower.address,
          amountToLiquidate.toString(),
          false
        );
        // Bad flash loan params: requested DAI amount below amountToLiquidate
        await expect(
          pool
            .connect(liquidator.signer)
            .flashLoan(
              getContractAddress(flashLiquidationAdapter),
              [getContractAddress(dai)],
              [(amountToLiquidate / 2n).toString()],
              [0],
              borrower.address,
              params,
              0
            )
        ).to.be.revertedWith(LP_LIQUIDATION_CALL_FAILED);
      });

      it('Revert if requested multiple assets', async () => {
        await depositAndHFBelowOne();

        const { dai, weth, users, pool, helpersContract, flashLiquidationAdapter } = testEnv;

        const liquidator = users[3];
        const borrower = users[1];
        const expectedSwap = parseEther('0.4');

        // Set how much ETH will be sold and swapped for DAI at Uniswap mock
        await (await mockUniswapRouter.setAmountToSwap(getContractAddress(weth), expectedSwap)).wait();

        const userReserveDataBefore = await getUserData(
          pool,
          helpersContract,
          getContractAddress(dai),
          borrower.address
        );

        const amountToLiquidate = BigInt(userReserveDataBefore.currentStableDebt) / 2n;

        // Correct params
        const params = buildFlashLiquidationAdapterParams(
          getContractAddress(weth),
          getContractAddress(dai),
          borrower.address,
          amountToLiquidate.toString(),
          false
        );
        // Bad flash loan params: requested multiple assets
        await expect(
          pool
            .connect(liquidator.signer)
            .flashLoan(
              getContractAddress(flashLiquidationAdapter),
              [getContractAddress(dai), getContractAddress(weth)],
              [10, 10],
              [0],
              borrower.address,
              params,
              0
            )
        ).to.be.revertedWith('INCONSISTENT_PARAMS');
      });
    });
  });
});
