import { makeSuite } from './helpers/make-suite.js';
import type { TestEnv } from './helpers/make-suite.js';
import {convertToCurrencyDecimals,
  getContractAddress} from '../../helpers/contracts-helpers.js';
import { getMockUniswapRouter } from '../../helpers/contracts-getters.js';
import type { MockUniswapV2Router02 } from '../../types/ethers-contracts/index.js';
import BigNumber from "bignumber.js";

import { evmRevert, evmSnapshot } from '../../helpers/misc-utils.js';
import { ethers, parseEther } from 'ethers';
import { USD_ADDRESS } from '../../helpers/constants.js';

import chai from 'chai';
const { expect } = chai;

makeSuite('Uniswap adapters', (testEnv: TestEnv) => {
  let mockUniswapRouter: MockUniswapV2Router02;
  let evmSnapshotId: string;

  before(async () => {
    mockUniswapRouter = await getMockUniswapRouter();
  });

  beforeEach(async () => {
    evmSnapshotId = await evmSnapshot();
  });

  afterEach(async () => {
    await evmRevert(evmSnapshotId);
  });

  describe('BaseUniswapAdapter', () => {
    describe('getAmountsOut', () => {
      it('should return the estimated amountOut and prices for the asset swap', async () => {
        const { weth, dai, uniswapLiquiditySwapAdapter, oracle } = testEnv;

        const amountIn = parseEther('1');
        const flashloanPremium = amountIn * 9n / 10000n;
        const amountToSwap = (amountIn - flashloanPremium);

        const wethPrice = await oracle.getAssetPrice(getContractAddress(weth));
        const daiPrice = await oracle.getAssetPrice(getContractAddress(dai));
        const usdPrice = await oracle.getAssetPrice(USD_ADDRESS);

        const expectedDaiAmount = await convertToCurrencyDecimals(
          getContractAddress(dai),
          new BigNumber(amountToSwap.toString()).div(daiPrice.toString()).toFixed(0)
        );

        const outPerInPrice = amountToSwap
          * parseEther('1')
          * parseEther('1')
          / (expectedDaiAmount * parseEther('1'));
        const ethUsdValue = amountIn
          * wethPrice
          / parseEther('1')
          * usdPrice
          / parseEther('1');
        const daiUsdValue = expectedDaiAmount
          * daiPrice
          / parseEther('1')
          * usdPrice
          / parseEther('1');

        await mockUniswapRouter.setAmountOut(
          amountToSwap,
          getContractAddress(weth),
          getContractAddress(dai),
          expectedDaiAmount
        );

        const result = await uniswapLiquiditySwapAdapter.getAmountsOut(
          amountIn,
          getContractAddress(weth),
          getContractAddress(dai)
        );

        expect(result['0']).to.be.eq(expectedDaiAmount);
        expect(result['1']).to.be.eq(outPerInPrice);
        expect(result['2']).to.be.eq(ethUsdValue);
        expect(result['3']).to.be.eq(daiUsdValue);
      });
      it('should work correctly with different decimals', async () => {
        const { aave, usdc, uniswapLiquiditySwapAdapter, oracle } = testEnv;

        const amountIn = parseEther('10');
        const flashloanPremium = amountIn * 9n / 10000n;
        const amountToSwap = (amountIn - flashloanPremium);

        const aavePrice = await oracle.getAssetPrice(getContractAddress(aave));
        const usdcPrice = await oracle.getAssetPrice(getContractAddress(usdc));
        const usdPrice = await oracle.getAssetPrice(USD_ADDRESS);

        const expectedUSDCAmount = await convertToCurrencyDecimals(
          getContractAddress(usdc),
          new BigNumber(amountToSwap.toString()).div(usdcPrice.toString()).toFixed(0)
        );

        const outPerInPrice = amountToSwap
          * parseEther('1')
          * 1000000n // usdc 6 decimals
          / (expectedUSDCAmount * parseEther('1'));

        const aaveUsdValue = amountIn
          * aavePrice
          / parseEther('1')
          * usdPrice
          / parseEther('1');

        const usdcUsdValue = expectedUSDCAmount
          * usdcPrice
          / 1000000n // usdc 6 decimals
          * usdPrice
          / parseEther('1');

        await mockUniswapRouter.setAmountOut(
          amountToSwap,
          getContractAddress(aave),
          getContractAddress(usdc),
          expectedUSDCAmount
        );

        const result = await uniswapLiquiditySwapAdapter.getAmountsOut(
          amountIn,
          getContractAddress(aave),
          getContractAddress(usdc)
        );

        expect(result['0']).to.be.eq(expectedUSDCAmount);
        expect(result['1']).to.be.eq(outPerInPrice);
        expect(result['2']).to.be.eq(aaveUsdValue);
        expect(result['3']).to.be.eq(usdcUsdValue);
      });
    });

    describe('getAmountsIn', () => {
      it('should return the estimated required amountIn for the asset swap', async () => {
        const { weth, dai, uniswapLiquiditySwapAdapter, oracle } = testEnv;

        const amountIn = parseEther('1');
        const flashloanPremium = amountIn * 9n / 10000n;
        const amountToSwap = (amountIn + flashloanPremium);

        const wethPrice = await oracle.getAssetPrice(getContractAddress(weth));
        const daiPrice = await oracle.getAssetPrice(getContractAddress(dai));
        const usdPrice = await oracle.getAssetPrice(USD_ADDRESS);

        const amountOut = await convertToCurrencyDecimals(
          getContractAddress(dai),
          new BigNumber(amountIn.toString()).div(daiPrice.toString()).toFixed(0)
        );

        const inPerOutPrice = amountOut
          * parseEther('1')
          * parseEther('1')
          / (amountToSwap * parseEther('1'));

        const ethUsdValue = amountToSwap
          * wethPrice
          / parseEther('1')
          * usdPrice
          / parseEther('1');
        const daiUsdValue = amountOut
          * daiPrice
          / parseEther('1')
          * usdPrice
          / parseEther('1');

        await mockUniswapRouter.setAmountIn(amountOut, getContractAddress(weth), getContractAddress(dai), amountIn);

        const result = await uniswapLiquiditySwapAdapter.getAmountsIn(
          amountOut,
          getContractAddress(weth),
          getContractAddress(dai)
        );

        expect(result['0']).to.be.eq(amountToSwap);
        expect(result['1']).to.be.eq(inPerOutPrice);
        expect(result['2']).to.be.eq(ethUsdValue);
        expect(result['3']).to.be.eq(daiUsdValue);
      });
      it('should work correctly with different decimals', async () => {
        const { aave, usdc, uniswapLiquiditySwapAdapter, oracle } = testEnv;

        const amountIn = parseEther('10');
        const flashloanPremium = amountIn * 9n / 10000n;
        const amountToSwap = (amountIn + flashloanPremium);

        const aavePrice = await oracle.getAssetPrice(getContractAddress(aave));
        const usdcPrice = await oracle.getAssetPrice(getContractAddress(usdc));
        const usdPrice = await oracle.getAssetPrice(USD_ADDRESS);

        const amountOut = await convertToCurrencyDecimals(
          getContractAddress(usdc),
          new BigNumber(amountToSwap.toString()).div(usdcPrice.toString()).toFixed(0)
        );

        const inPerOutPrice = amountOut
          * parseEther('1')
          * parseEther('1')
          / (amountToSwap * 1000000n); // usdc 6 decimals

        const aaveUsdValue = amountToSwap
          * aavePrice
          / parseEther('1')
          * usdPrice
          / parseEther('1');

        const usdcUsdValue = amountOut
          * usdcPrice
          / 1000000n // usdc 6 decimals
          * usdPrice
          / parseEther('1');

        await mockUniswapRouter.setAmountIn(amountOut, getContractAddress(aave), getContractAddress(usdc), amountIn);

        const result = await uniswapLiquiditySwapAdapter.getAmountsIn(
          amountOut,
          getContractAddress(aave),
          getContractAddress(usdc)
        );

        expect(result['0']).to.be.eq(amountToSwap);
        expect(result['1']).to.be.eq(inPerOutPrice);
        expect(result['2']).to.be.eq(aaveUsdValue);
        expect(result['3']).to.be.eq(usdcUsdValue);
      });
    });
  });
});
