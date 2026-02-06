import { makeSuite } from '../helpers/make-suite.js';
import type { TestEnv } from '../helpers/make-suite.js';
import {
  convertToCurrencyDecimals,
  getContract,
  buildPermitParams,
  getSignatureFromTypedData,
  buildLiquiditySwapParams,
  getContractAddress
} from '../../../helpers/contracts-helpers.js';
import { getMockUniswapRouter } from '../../../helpers/contracts-getters.js';
import { deployUniswapLiquiditySwapAdapter } from '../../../helpers/contracts-deployments.js';
import type { MockUniswapV2Router02 } from '../../../types/ethers-contracts/index.js';
import BigNumber from "bignumber.js";

import { DRE, evmRevert, evmSnapshot } from '../../../helpers/misc-utils.js';
import { ethers, parseEther } from 'ethers';
import { eContractid } from '../../../helpers/types.js';
import type { AToken } from '../../../types/ethers-contracts/index.js';
import { BUIDLEREVM_CHAINID } from '../../../helpers/buidler-constants.js';
import { MAX_UINT_AMOUNT } from '../../../helpers/constants.js';

import chai from 'chai';
import { accounts } from '../../../test-wallets.js';
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

  describe('UniswapLiquiditySwapAdapter', () => {
    describe('constructor', () => {
      it('should deploy with correct parameters', async () => {
        const { addressesProvider, weth } = testEnv;
        await deployUniswapLiquiditySwapAdapter([
          getContractAddress(addressesProvider),
          getContractAddress(mockUniswapRouter),
          getContractAddress(weth),
        ]);
      });

      it('should revert if not valid addresses provider', async () => {
        const { weth } = testEnv;
        await expect(
          deployUniswapLiquiditySwapAdapter([
            getContractAddress(mockUniswapRouter),
            getContractAddress(mockUniswapRouter),
            getContractAddress(weth),
          ])
        ).to.be.revert(DRE.ethers);
      });
    });

    describe('executeOperation', () => {
      beforeEach(async () => {
        const { users, weth, dai, usdc, pool, deployer } = testEnv;
        const userAddress = users[0].address;

        // Provide liquidity
        await dai.mint(parseEther('20000'));
        await dai.approve(getContractAddress(pool), parseEther('20000'));
        await pool.deposit(getContractAddress(dai), parseEther('20000'), deployer.address, 0);

        const usdcAmount = await convertToCurrencyDecimals(getContractAddress(usdc), '10');
        await usdc.mint(usdcAmount);
        await usdc.approve(getContractAddress(pool), usdcAmount);
        await pool.deposit(getContractAddress(usdc), usdcAmount, deployer.address, 0);

        // Make a deposit for user
        await weth.mint(parseEther('100'));
        await weth.approve(getContractAddress(pool), parseEther('100'));
        await pool.deposit(getContractAddress(weth), parseEther('100'), userAddress, 0);
      });

      it('should correctly swap tokens and deposit the out tokens in the pool', async () => {
        const {
          users,
          weth,
          oracle,
          dai,
          aDai,
          aWETH,
          pool,
          uniswapLiquiditySwapAdapter,
        } = testEnv;
        const user = users[0].signer;
        const userAddress = users[0].address;

        const amountWETHtoSwap = await convertToCurrencyDecimals(getContractAddress(weth), '10');

        const daiPrice = await oracle.getAssetPrice(getContractAddress(dai));
        const expectedDaiAmount = await convertToCurrencyDecimals(
          getContractAddress(dai),
          new BigNumber(amountWETHtoSwap.toString()).div(daiPrice.toString()).toFixed(0)
        );

        await mockUniswapRouter.setAmountToReturn(getContractAddress(weth), expectedDaiAmount);

        // User will swap liquidity 10 aEth to aDai
        const liquidityToSwap = parseEther('10');
        await aWETH.connect(user).approve(getContractAddress(uniswapLiquiditySwapAdapter), liquidityToSwap);
        const userAEthBalanceBefore = await aWETH.balanceOf(userAddress);

        // Subtract the FL fee from the amount to be swapped 0,09%
        const flashloanAmount = new BigNumber(liquidityToSwap.toString()).div(1.0009).toFixed(0);

        const params = buildLiquiditySwapParams(
          [getContractAddress(dai)],
          [expectedDaiAmount],
          [0],
          [0],
          [0],
          [0],
          ['0x0000000000000000000000000000000000000000000000000000000000000000'],
          ['0x0000000000000000000000000000000000000000000000000000000000000000'],
          [false]
        );

        await expect(
          pool
            .connect(user)
            .flashLoan(
              getContractAddress(uniswapLiquiditySwapAdapter),
              [getContractAddress(weth)],
              [flashloanAmount.toString()],
              [0],
              userAddress,
              params,
              0
            )
        )
          .to.emit(uniswapLiquiditySwapAdapter, 'Swapped')
          .withArgs(getContractAddress(weth), getContractAddress(dai), flashloanAmount.toString(), expectedDaiAmount);

        const adapterWethBalance = await weth.balanceOf(getContractAddress(uniswapLiquiditySwapAdapter));
        const adapterDaiBalance = await dai.balanceOf(getContractAddress(uniswapLiquiditySwapAdapter));
        const adapterDaiAllowance = await dai.allowance(
          getContractAddress(uniswapLiquiditySwapAdapter),
          userAddress
        );
        const userADaiBalance = await aDai.balanceOf(userAddress);
        const userAEthBalance = await aWETH.balanceOf(userAddress);

        expect(adapterWethBalance).to.be.eq(0n);
        expect(adapterDaiBalance).to.be.eq(0n);
        expect(adapterDaiAllowance).to.be.eq(0n);
        expect(userADaiBalance).to.be.eq(expectedDaiAmount);
        expect(userAEthBalance).to.be.lt(userAEthBalanceBefore);
        expect(userAEthBalance).to.be.gte((userAEthBalanceBefore - liquidityToSwap));
      });

      it('should correctly swap and deposit multiple tokens', async () => {
        const {
          users,
          weth,
          oracle,
          dai,
          aDai,
          aWETH,
          usdc,
          pool,
          uniswapLiquiditySwapAdapter,
        } = testEnv;
        const user = users[0].signer;
        const userAddress = users[0].address;

        const amountWETHtoSwap = await convertToCurrencyDecimals(getContractAddress(weth), '10');

        const daiPrice = await oracle.getAssetPrice(getContractAddress(dai));
        const expectedDaiAmountForEth = await convertToCurrencyDecimals(
          getContractAddress(dai),
          new BigNumber(amountWETHtoSwap.toString()).div(daiPrice.toString()).toFixed(0)
        );

        const amountUSDCtoSwap = await convertToCurrencyDecimals(getContractAddress(usdc), '10');
        const usdcPrice = await oracle.getAssetPrice(getContractAddress(usdc));

        const collateralDecimals = (await usdc.decimals()).toString();
        const principalDecimals = (await dai.decimals()).toString();

        const expectedDaiAmountForUsdc = await convertToCurrencyDecimals(
          getContractAddress(dai),
          new BigNumber(amountUSDCtoSwap.toString())
            .times(
              new BigNumber(usdcPrice.toString()).times(new BigNumber(10).pow(principalDecimals))
            )
            .div(
              new BigNumber(daiPrice.toString()).times(new BigNumber(10).pow(collateralDecimals))
            )
            .div(new BigNumber(10).pow(principalDecimals))
            .toFixed(0)
        );

        // Make a deposit for user
        await usdc.connect(user).mint(amountUSDCtoSwap);
        await usdc.connect(user).approve(getContractAddress(pool), amountUSDCtoSwap);
        await pool.connect(user).deposit(getContractAddress(usdc), amountUSDCtoSwap, userAddress, 0);

        const aUsdcData = await pool.getReserveData(getContractAddress(usdc));
        const aUsdc = await getContract<AToken>(eContractid.AToken, aUsdcData.aTokenAddress);

        await mockUniswapRouter.setAmountToReturn(getContractAddress(weth), expectedDaiAmountForEth);
        await mockUniswapRouter.setAmountToReturn(getContractAddress(usdc), expectedDaiAmountForUsdc);

        await aWETH.connect(user).approve(getContractAddress(uniswapLiquiditySwapAdapter), amountWETHtoSwap);
        const userAEthBalanceBefore = await aWETH.balanceOf(userAddress);
        await aUsdc.connect(user).approve(getContractAddress(uniswapLiquiditySwapAdapter), amountUSDCtoSwap);
        const userAUsdcBalanceBefore = await aUsdc.balanceOf(userAddress);

        // Subtract the FL fee from the amount to be swapped 0,09%
        const wethFlashloanAmount = new BigNumber(amountWETHtoSwap.toString())
          .div(1.0009)
          .toFixed(0);
        const usdcFlashloanAmount = new BigNumber(amountUSDCtoSwap.toString())
          .div(1.0009)
          .toFixed(0);

        const params = buildLiquiditySwapParams(
          [getContractAddress(dai), getContractAddress(dai)],
          [expectedDaiAmountForEth, expectedDaiAmountForUsdc],
          [0, 0],
          [0, 0],
          [0, 0],
          [0, 0],
          [
            '0x0000000000000000000000000000000000000000000000000000000000000000',
            '0x0000000000000000000000000000000000000000000000000000000000000000',
          ],
          [
            '0x0000000000000000000000000000000000000000000000000000000000000000',
            '0x0000000000000000000000000000000000000000000000000000000000000000',
          ],
          [false, false]
        );

        await pool
          .connect(user)
          .flashLoan(
            getContractAddress(uniswapLiquiditySwapAdapter),
            [getContractAddress(weth), getContractAddress(usdc)],
            [wethFlashloanAmount.toString(), usdcFlashloanAmount.toString()],
            [0, 0],
            userAddress,
            params,
            0
          );

        const adapterWethBalance = await weth.balanceOf(getContractAddress(uniswapLiquiditySwapAdapter));
        const adapterDaiBalance = await dai.balanceOf(getContractAddress(uniswapLiquiditySwapAdapter));
        const adapterDaiAllowance = await dai.allowance(
          getContractAddress(uniswapLiquiditySwapAdapter),
          userAddress
        );
        const userADaiBalance = await aDai.balanceOf(userAddress);
        const userAEthBalance = await aWETH.balanceOf(userAddress);
        const userAUsdcBalance = await aUsdc.balanceOf(userAddress);

        expect(adapterWethBalance).to.be.eq(0n);
        expect(adapterDaiBalance).to.be.eq(0n);
        expect(adapterDaiAllowance).to.be.eq(0n);
        expect(userADaiBalance).to.be.eq((expectedDaiAmountForEth + expectedDaiAmountForUsdc));
        expect(userAEthBalance).to.be.lt(userAEthBalanceBefore);
        expect(userAEthBalance).to.be.gte((userAEthBalanceBefore - amountWETHtoSwap));
        expect(userAUsdcBalance).to.be.lt(userAUsdcBalanceBefore);
        expect(userAUsdcBalance).to.be.gte((userAUsdcBalanceBefore - amountUSDCtoSwap));
      });

      it('should correctly swap and deposit multiple tokens using permit', async () => {
        const {
          users,
          weth,
          oracle,
          dai,
          aDai,
          aWETH,
          usdc,
          pool,
          uniswapLiquiditySwapAdapter,
        } = testEnv;
        const user = users[0].signer;
        const userAddress = users[0].address;
        const chainId = Number((await DRE.ethers.provider.getNetwork()).chainId);
        const deadline = MAX_UINT_AMOUNT;

        const ownerPrivateKey = accounts[1].secretKey;
        if (!ownerPrivateKey) {
          throw new Error('INVALID_OWNER_PK');
        }

        const amountWETHtoSwap = await convertToCurrencyDecimals(getContractAddress(weth), '10');

        const daiPrice = await oracle.getAssetPrice(getContractAddress(dai));
        const expectedDaiAmountForEth = await convertToCurrencyDecimals(
          getContractAddress(dai),
          new BigNumber(amountWETHtoSwap.toString()).div(daiPrice.toString()).toFixed(0)
        );

        const amountUSDCtoSwap = await convertToCurrencyDecimals(getContractAddress(usdc), '10');
        const usdcPrice = await oracle.getAssetPrice(getContractAddress(usdc));

        const collateralDecimals = (await usdc.decimals()).toString();
        const principalDecimals = (await dai.decimals()).toString();

        const expectedDaiAmountForUsdc = await convertToCurrencyDecimals(
          getContractAddress(dai),
          new BigNumber(amountUSDCtoSwap.toString())
            .times(
              new BigNumber(usdcPrice.toString()).times(new BigNumber(10).pow(principalDecimals))
            )
            .div(
              new BigNumber(daiPrice.toString()).times(new BigNumber(10).pow(collateralDecimals))
            )
            .div(new BigNumber(10).pow(principalDecimals))
            .toFixed(0)
        );

        // Make a deposit for user
        await usdc.connect(user).mint(amountUSDCtoSwap);
        await usdc.connect(user).approve(getContractAddress(pool), amountUSDCtoSwap);
        await pool.connect(user).deposit(getContractAddress(usdc), amountUSDCtoSwap, userAddress, 0);

        const aUsdcData = await pool.getReserveData(getContractAddress(usdc));
        const aUsdc = await getContract<AToken>(eContractid.AToken, aUsdcData.aTokenAddress);

        await mockUniswapRouter.setAmountToReturn(getContractAddress(weth), expectedDaiAmountForEth);
        await mockUniswapRouter.setAmountToReturn(getContractAddress(usdc), expectedDaiAmountForUsdc);

        const userAEthBalanceBefore = await aWETH.balanceOf(userAddress);
        const userAUsdcBalanceBefore = await aUsdc.balanceOf(userAddress);

        const wethFlashloanAmount = new BigNumber(amountWETHtoSwap.toString())
          .div(1.0009)
          .toFixed(0);

        const usdcFlashloanAmount = new BigNumber(amountUSDCtoSwap.toString())
          .div(1.0009)
          .toFixed(0);

        const aWethNonce = Number(await aWETH._nonces(userAddress));
        const aWethMsgParams = buildPermitParams(
          chainId,
          getContractAddress(aWETH),
          '1',
          await aWETH.name(),
          userAddress,
          getContractAddress(uniswapLiquiditySwapAdapter),
          aWethNonce,
          deadline,
          amountWETHtoSwap.toString()
        );
        const { v: aWETHv, r: aWETHr, s: aWETHs } = getSignatureFromTypedData(
          ownerPrivateKey,
          aWethMsgParams
        );

        const aUsdcNonce = Number(await aUsdc._nonces(userAddress));
        const aUsdcMsgParams = buildPermitParams(
          chainId,
          getContractAddress(aUsdc),
          '1',
          await aUsdc.name(),
          userAddress,
          getContractAddress(uniswapLiquiditySwapAdapter),
          aUsdcNonce,
          deadline,
          amountUSDCtoSwap.toString()
        );
        const { v: aUsdcv, r: aUsdcr, s: aUsdcs } = getSignatureFromTypedData(
          ownerPrivateKey,
          aUsdcMsgParams
        );
        const params = buildLiquiditySwapParams(
          [getContractAddress(dai), getContractAddress(dai)],
          [expectedDaiAmountForEth, expectedDaiAmountForUsdc],
          [0, 0],
          [amountWETHtoSwap, amountUSDCtoSwap],
          [deadline, deadline],
          [aWETHv, aUsdcv],
          [aWETHr, aUsdcr],
          [aWETHs, aUsdcs],
          [false, false]
        );

        await pool
          .connect(user)
          .flashLoan(
            getContractAddress(uniswapLiquiditySwapAdapter),
            [getContractAddress(weth), getContractAddress(usdc)],
            [wethFlashloanAmount.toString(), usdcFlashloanAmount.toString()],
            [0, 0],
            userAddress,
            params,
            0
          );

        const adapterWethBalance = await weth.balanceOf(getContractAddress(uniswapLiquiditySwapAdapter));
        const adapterDaiBalance = await dai.balanceOf(getContractAddress(uniswapLiquiditySwapAdapter));
        const adapterDaiAllowance = await dai.allowance(
          getContractAddress(uniswapLiquiditySwapAdapter),
          userAddress
        );
        const userADaiBalance = await aDai.balanceOf(userAddress);
        const userAEthBalance = await aWETH.balanceOf(userAddress);
        const userAUsdcBalance = await aUsdc.balanceOf(userAddress);

        expect(adapterWethBalance).to.be.eq(0n);
        expect(adapterDaiBalance).to.be.eq(0n);
        expect(adapterDaiAllowance).to.be.eq(0n);
        expect(userADaiBalance).to.be.eq((expectedDaiAmountForEth + expectedDaiAmountForUsdc));
        expect(userAEthBalance).to.be.lt(userAEthBalanceBefore);
        expect(userAEthBalance).to.be.gte((userAEthBalanceBefore - amountWETHtoSwap));
        expect(userAUsdcBalance).to.be.lt(userAUsdcBalanceBefore);
        expect(userAUsdcBalance).to.be.gte((userAUsdcBalanceBefore - amountUSDCtoSwap));
      });

      it('should correctly swap tokens with permit', async () => {
        const {
          users,
          weth,
          oracle,
          dai,
          aDai,
          aWETH,
          pool,
          uniswapLiquiditySwapAdapter,
        } = testEnv;
        const user = users[0].signer;
        const userAddress = users[0].address;

        const amountWETHtoSwap = await convertToCurrencyDecimals(getContractAddress(weth), '10');

        const daiPrice = await oracle.getAssetPrice(getContractAddress(dai));
        const expectedDaiAmount = await convertToCurrencyDecimals(
          getContractAddress(dai),
          new BigNumber(amountWETHtoSwap.toString()).div(daiPrice.toString()).toFixed(0)
        );

        await mockUniswapRouter.setAmountToReturn(getContractAddress(weth), expectedDaiAmount);

        // User will swap liquidity 10 aEth to aDai
        const liquidityToSwap = parseEther('10');
        const userAEthBalanceBefore = await aWETH.balanceOf(userAddress);

        // Subtract the FL fee from the amount to be swapped 0,09%
        const flashloanAmount = new BigNumber(liquidityToSwap.toString()).div(1.0009).toFixed(0);

        const chainId = Number((await DRE.ethers.provider.getNetwork()).chainId);
        const deadline = MAX_UINT_AMOUNT;
        const nonce = Number(await aWETH._nonces(userAddress));
        const msgParams = buildPermitParams(
          chainId,
          getContractAddress(aWETH),
          '1',
          await aWETH.name(),
          userAddress,
          getContractAddress(uniswapLiquiditySwapAdapter),
          nonce,
          deadline,
          liquidityToSwap.toString()
        );

        const ownerPrivateKey = accounts[1].secretKey;
        if (!ownerPrivateKey) {
          throw new Error('INVALID_OWNER_PK');
        }

        const { v, r, s } = getSignatureFromTypedData(ownerPrivateKey, msgParams);

        const params = buildLiquiditySwapParams(
          [getContractAddress(dai)],
          [expectedDaiAmount],
          [0],
          [liquidityToSwap],
          [deadline],
          [v],
          [r],
          [s],
          [false]
        );

        await expect(
          pool
            .connect(user)
            .flashLoan(
              getContractAddress(uniswapLiquiditySwapAdapter),
              [getContractAddress(weth)],
              [flashloanAmount.toString()],
              [0],
              userAddress,
              params,
              0
            )
        )
          .to.emit(uniswapLiquiditySwapAdapter, 'Swapped')
          .withArgs(getContractAddress(weth), getContractAddress(dai), flashloanAmount.toString(), expectedDaiAmount);

        const adapterWethBalance = await weth.balanceOf(getContractAddress(uniswapLiquiditySwapAdapter));
        const adapterDaiBalance = await dai.balanceOf(getContractAddress(uniswapLiquiditySwapAdapter));
        const adapterDaiAllowance = await dai.allowance(
          getContractAddress(uniswapLiquiditySwapAdapter),
          userAddress
        );
        const userADaiBalance = await aDai.balanceOf(userAddress);
        const userAEthBalance = await aWETH.balanceOf(userAddress);

        expect(adapterWethBalance).to.be.eq(0n);
        expect(adapterDaiBalance).to.be.eq(0n);
        expect(adapterDaiAllowance).to.be.eq(0n);
        expect(userADaiBalance).to.be.eq(expectedDaiAmount);
        expect(userAEthBalance).to.be.lt(userAEthBalanceBefore);
        expect(userAEthBalance).to.be.gte((userAEthBalanceBefore - liquidityToSwap));
      });

      it('should revert if inconsistent params', async () => {
        const { users, weth, oracle, dai, aWETH, pool, uniswapLiquiditySwapAdapter } = testEnv;
        const user = users[0].signer;
        const userAddress = users[0].address;

        const amountWETHtoSwap = await convertToCurrencyDecimals(getContractAddress(weth), '10');

        const daiPrice = await oracle.getAssetPrice(getContractAddress(dai));
        const expectedDaiAmount = await convertToCurrencyDecimals(
          getContractAddress(dai),
          new BigNumber(amountWETHtoSwap.toString()).div(daiPrice.toString()).toFixed(0)
        );

        await mockUniswapRouter.setAmountToReturn(getContractAddress(weth), expectedDaiAmount);

        // User will swap liquidity 10 aEth to aDai
        const liquidityToSwap = parseEther('10');
        await aWETH.connect(user).approve(getContractAddress(uniswapLiquiditySwapAdapter), liquidityToSwap);

        // Subtract the FL fee from the amount to be swapped 0,09%
        const flashloanAmount = new BigNumber(liquidityToSwap.toString()).div(1.0009).toFixed(0);

        const params = buildLiquiditySwapParams(
          [getContractAddress(dai), getContractAddress(weth)],
          [expectedDaiAmount],
          [0],
          [0],
          [0],
          [0],
          ['0x0000000000000000000000000000000000000000000000000000000000000000'],
          ['0x0000000000000000000000000000000000000000000000000000000000000000'],
          [false]
        );

        await expect(
          pool
            .connect(user)
            .flashLoan(
              getContractAddress(uniswapLiquiditySwapAdapter),
              [getContractAddress(weth)],
              [flashloanAmount.toString()],
              [0],
              userAddress,
              params,
              0
            )
        ).to.be.revertedWith('INCONSISTENT_PARAMS');

        const params2 = buildLiquiditySwapParams(
          [getContractAddress(dai), getContractAddress(weth)],
          [expectedDaiAmount],
          [0, 0],
          [0, 0],
          [0, 0],
          [0],
          ['0x0000000000000000000000000000000000000000000000000000000000000000'],
          ['0x0000000000000000000000000000000000000000000000000000000000000000'],
          [false]
        );

        await expect(
          pool
            .connect(user)
            .flashLoan(
              getContractAddress(uniswapLiquiditySwapAdapter),
              [getContractAddress(weth)],
              [flashloanAmount.toString()],
              [0],
              userAddress,
              params2,
              0
            )
        ).to.be.revertedWith('INCONSISTENT_PARAMS');

        const params3 = buildLiquiditySwapParams(
          [getContractAddress(dai), getContractAddress(weth)],
          [expectedDaiAmount],
          [0, 0],
          [0],
          [0, 0],
          [0, 0],
          ['0x0000000000000000000000000000000000000000000000000000000000000000'],
          ['0x0000000000000000000000000000000000000000000000000000000000000000'],
          [false]
        );

        await expect(
          pool
            .connect(user)
            .flashLoan(
              getContractAddress(uniswapLiquiditySwapAdapter),
              [getContractAddress(weth)],
              [flashloanAmount.toString()],
              [0],
              userAddress,
              params3,
              0
            )
        ).to.be.revertedWith('INCONSISTENT_PARAMS');

        const params4 = buildLiquiditySwapParams(
          [getContractAddress(dai), getContractAddress(weth)],
          [expectedDaiAmount],
          [0],
          [0],
          [0],
          [0],
          [
            '0x0000000000000000000000000000000000000000000000000000000000000000',
            '0x0000000000000000000000000000000000000000000000000000000000000000',
          ],
          ['0x0000000000000000000000000000000000000000000000000000000000000000'],
          [false]
        );

        await expect(
          pool
            .connect(user)
            .flashLoan(
              getContractAddress(uniswapLiquiditySwapAdapter),
              [getContractAddress(weth)],
              [flashloanAmount.toString()],
              [0],
              userAddress,
              params4,
              0
            )
        ).to.be.revertedWith('INCONSISTENT_PARAMS');

        const params5 = buildLiquiditySwapParams(
          [getContractAddress(dai), getContractAddress(weth)],
          [expectedDaiAmount],
          [0],
          [0],
          [0],
          [0],
          ['0x0000000000000000000000000000000000000000000000000000000000000000'],
          [
            '0x0000000000000000000000000000000000000000000000000000000000000000',
            '0x0000000000000000000000000000000000000000000000000000000000000000',
          ],
          [false]
        );

        await expect(
          pool
            .connect(user)
            .flashLoan(
              getContractAddress(uniswapLiquiditySwapAdapter),
              [getContractAddress(weth)],
              [flashloanAmount.toString()],
              [0],
              userAddress,
              params5,
              0
            )
        ).to.be.revertedWith('INCONSISTENT_PARAMS');

        const params6 = buildLiquiditySwapParams(
          [getContractAddress(dai), getContractAddress(weth)],
          [expectedDaiAmount, expectedDaiAmount],
          [0],
          [0],
          [0],
          [0],
          ['0x0000000000000000000000000000000000000000000000000000000000000000'],
          ['0x0000000000000000000000000000000000000000000000000000000000000000'],
          [false]
        );

        await expect(
          pool
            .connect(user)
            .flashLoan(
              getContractAddress(uniswapLiquiditySwapAdapter),
              [getContractAddress(weth)],
              [flashloanAmount.toString()],
              [0],
              userAddress,
              params6,
              0
            )
        ).to.be.revertedWith('INCONSISTENT_PARAMS');

        const params7 = buildLiquiditySwapParams(
          [getContractAddress(dai)],
          [expectedDaiAmount],
          [0, 0],
          [0],
          [0],
          [0],
          ['0x0000000000000000000000000000000000000000000000000000000000000000'],
          ['0x0000000000000000000000000000000000000000000000000000000000000000'],
          [false]
        );

        await expect(
          pool
            .connect(user)
            .flashLoan(
              getContractAddress(uniswapLiquiditySwapAdapter),
              [getContractAddress(weth)],
              [flashloanAmount.toString()],
              [0],
              userAddress,
              params7,
              0
            )
        ).to.be.revertedWith('INCONSISTENT_PARAMS');

        const params8 = buildLiquiditySwapParams(
          [getContractAddress(dai)],
          [expectedDaiAmount],
          [0],
          [0, 0],
          [0],
          [0],
          ['0x0000000000000000000000000000000000000000000000000000000000000000'],
          ['0x0000000000000000000000000000000000000000000000000000000000000000'],
          [false]
        );

        await expect(
          pool
            .connect(user)
            .flashLoan(
              getContractAddress(uniswapLiquiditySwapAdapter),
              [getContractAddress(weth)],
              [flashloanAmount.toString()],
              [0],
              userAddress,
              params8,
              0
            )
        ).to.be.revertedWith('INCONSISTENT_PARAMS');

        const params9 = buildLiquiditySwapParams(
          [getContractAddress(dai)],
          [expectedDaiAmount],
          [0],
          [0],
          [0],
          [0],
          ['0x0000000000000000000000000000000000000000000000000000000000000000'],
          ['0x0000000000000000000000000000000000000000000000000000000000000000'],
          [false, false]
        );

        await expect(
          pool
            .connect(user)
            .flashLoan(
              getContractAddress(uniswapLiquiditySwapAdapter),
              [getContractAddress(weth)],
              [flashloanAmount.toString()],
              [0],
              userAddress,
              params9,
              0
            )
        ).to.be.revertedWith('INCONSISTENT_PARAMS');
      });

      it('should revert if caller not lending pool', async () => {
        const { users, weth, oracle, dai, aWETH, uniswapLiquiditySwapAdapter } = testEnv;
        const user = users[0].signer;
        const userAddress = users[0].address;

        const amountWETHtoSwap = await convertToCurrencyDecimals(getContractAddress(weth), '10');

        const daiPrice = await oracle.getAssetPrice(getContractAddress(dai));
        const expectedDaiAmount = await convertToCurrencyDecimals(
          getContractAddress(dai),
          new BigNumber(amountWETHtoSwap.toString()).div(daiPrice.toString()).toFixed(0)
        );

        await mockUniswapRouter.setAmountToReturn(getContractAddress(weth), expectedDaiAmount);

        // User will swap liquidity 10 aEth to aDai
        const liquidityToSwap = parseEther('10');
        await aWETH.connect(user).approve(getContractAddress(uniswapLiquiditySwapAdapter), liquidityToSwap);

        // Subtract the FL fee from the amount to be swapped 0,09%
        const flashloanAmount = new BigNumber(liquidityToSwap.toString()).div(1.0009).toFixed(0);

        const params = buildLiquiditySwapParams(
          [getContractAddress(dai)],
          [expectedDaiAmount],
          [0],
          [0],
          [0],
          [0],
          ['0x0000000000000000000000000000000000000000000000000000000000000000'],
          ['0x0000000000000000000000000000000000000000000000000000000000000000'],
          [false]
        );

        await expect(
          uniswapLiquiditySwapAdapter
            .connect(user)
            .executeOperation(
              [getContractAddress(weth)],
              [flashloanAmount.toString()],
              [0],
              userAddress,
              params
            )
        ).to.be.revertedWith('CALLER_MUST_BE_LENDING_POOL');
      });

      it('should work correctly with tokens of different decimals', async () => {
        const {
          users,
          usdc,
          oracle,
          dai,
          aDai,
          uniswapLiquiditySwapAdapter,
          pool,
          deployer,
        } = testEnv;
        const user = users[0].signer;
        const userAddress = users[0].address;

        const amountUSDCtoSwap = await convertToCurrencyDecimals(getContractAddress(usdc), '10');
        const liquidity = await convertToCurrencyDecimals(getContractAddress(usdc), '20000');

        // Provide liquidity
        await usdc.mint(liquidity);
        await usdc.approve(getContractAddress(pool), liquidity);
        await pool.deposit(getContractAddress(usdc), liquidity, deployer.address, 0);

        // Make a deposit for user
        await usdc.connect(user).mint(amountUSDCtoSwap);
        await usdc.connect(user).approve(getContractAddress(pool), amountUSDCtoSwap);
        await pool.connect(user).deposit(getContractAddress(usdc), amountUSDCtoSwap, userAddress, 0);

        const usdcPrice = await oracle.getAssetPrice(getContractAddress(usdc));
        const daiPrice = await oracle.getAssetPrice(getContractAddress(dai));

        // usdc 6
        const collateralDecimals = (await usdc.decimals()).toString();
        const principalDecimals = (await dai.decimals()).toString();

        const expectedDaiAmount = await convertToCurrencyDecimals(
          getContractAddress(dai),
          new BigNumber(amountUSDCtoSwap.toString())
            .times(
              new BigNumber(usdcPrice.toString()).times(new BigNumber(10).pow(principalDecimals))
            )
            .div(
              new BigNumber(daiPrice.toString()).times(new BigNumber(10).pow(collateralDecimals))
            )
            .div(new BigNumber(10).pow(principalDecimals))
            .toFixed(0)
        );

        await mockUniswapRouter.connect(user).setAmountToReturn(getContractAddress(usdc), expectedDaiAmount);

        const aUsdcData = await pool.getReserveData(getContractAddress(usdc));
        const aUsdc = await getContract<AToken>(eContractid.AToken, aUsdcData.aTokenAddress);
        const aUsdcBalance = await aUsdc.balanceOf(userAddress);
        await aUsdc.connect(user).approve(getContractAddress(uniswapLiquiditySwapAdapter), aUsdcBalance);
        // Subtract the FL fee from the amount to be swapped 0,09%
        const flashloanAmount = new BigNumber(amountUSDCtoSwap.toString()).div(1.0009).toFixed(0);

        const params = buildLiquiditySwapParams(
          [getContractAddress(dai)],
          [expectedDaiAmount],
          [0],
          [0],
          [0],
          [0],
          ['0x0000000000000000000000000000000000000000000000000000000000000000'],
          ['0x0000000000000000000000000000000000000000000000000000000000000000'],
          [false]
        );

        await expect(
          pool
            .connect(user)
            .flashLoan(
              getContractAddress(uniswapLiquiditySwapAdapter),
              [getContractAddress(usdc)],
              [flashloanAmount.toString()],
              [0],
              userAddress,
              params,
              0
            )
        )
          .to.emit(uniswapLiquiditySwapAdapter, 'Swapped')
          .withArgs(getContractAddress(usdc), getContractAddress(dai), flashloanAmount.toString(), expectedDaiAmount);

        const adapterUsdcBalance = await usdc.balanceOf(getContractAddress(uniswapLiquiditySwapAdapter));
        const adapterDaiBalance = await dai.balanceOf(getContractAddress(uniswapLiquiditySwapAdapter));
        const adapterDaiAllowance = await dai.allowance(
          getContractAddress(uniswapLiquiditySwapAdapter),
          userAddress
        );
        const aDaiBalance = await aDai.balanceOf(userAddress);

        expect(adapterUsdcBalance).to.be.eq(0n);
        expect(adapterDaiBalance).to.be.eq(0n);
        expect(adapterDaiAllowance).to.be.eq(0n);
        expect(aDaiBalance).to.be.eq(expectedDaiAmount);
      });

      it('should revert when min amount to receive exceeds the max slippage amount', async () => {
        const { users, weth, oracle, dai, aWETH, pool, uniswapLiquiditySwapAdapter } = testEnv;
        const user = users[0].signer;
        const userAddress = users[0].address;

        const amountWETHtoSwap = await convertToCurrencyDecimals(getContractAddress(weth), '10');

        const daiPrice = await oracle.getAssetPrice(getContractAddress(dai));
        const expectedDaiAmount = await convertToCurrencyDecimals(
          getContractAddress(dai),
          new BigNumber(amountWETHtoSwap.toString()).div(daiPrice.toString()).toFixed(0)
        );

        await mockUniswapRouter.setAmountToReturn(getContractAddress(weth), expectedDaiAmount);
        const smallExpectedDaiAmount = expectedDaiAmount / 2n;

        // User will swap liquidity 10 aEth to aDai
        const liquidityToSwap = parseEther('10');
        await aWETH.connect(user).approve(getContractAddress(uniswapLiquiditySwapAdapter), liquidityToSwap);

        // Subtract the FL fee from the amount to be swapped 0,09%
        const flashloanAmount = new BigNumber(liquidityToSwap.toString()).div(1.0009).toFixed(0);

        const params = buildLiquiditySwapParams(
          [getContractAddress(dai)],
          [smallExpectedDaiAmount],
          [0],
          [0],
          [0],
          [0],
          ['0x0000000000000000000000000000000000000000000000000000000000000000'],
          ['0x0000000000000000000000000000000000000000000000000000000000000000'],
          [false]
        );

        await expect(
          pool
            .connect(user)
            .flashLoan(
              getContractAddress(uniswapLiquiditySwapAdapter),
              [getContractAddress(weth)],
              [flashloanAmount.toString()],
              [0],
              userAddress,
              params,
              0
            )
        ).to.be.revertedWith('minAmountOut exceed max slippage');
      });

      it('should correctly swap tokens all the balance', async () => {
        const {
          users,
          weth,
          oracle,
          dai,
          aDai,
          aWETH,
          pool,
          uniswapLiquiditySwapAdapter,
        } = testEnv;
        const user = users[0].signer;
        const userAddress = users[0].address;

        const amountWETHtoSwap = await convertToCurrencyDecimals(getContractAddress(weth), '10');

        const daiPrice = await oracle.getAssetPrice(getContractAddress(dai));
        const expectedDaiAmount = await convertToCurrencyDecimals(
          getContractAddress(dai),
          new BigNumber(amountWETHtoSwap.toString()).div(daiPrice.toString()).toFixed(0)
        );

        await mockUniswapRouter.setAmountToReturn(getContractAddress(weth), expectedDaiAmount);

        // Remove other balance
        await aWETH.connect(user).transfer(users[1].address, parseEther('90'));
        const userAEthBalanceBefore = await aWETH.balanceOf(userAddress);

        // User will swap liquidity 10 aEth to aDai
        const liquidityToSwap = parseEther('10');
        expect(userAEthBalanceBefore).to.be.eq(liquidityToSwap);
        await aWETH.connect(user).approve(getContractAddress(uniswapLiquiditySwapAdapter), liquidityToSwap);

        const params = buildLiquiditySwapParams(
          [getContractAddress(dai)],
          [expectedDaiAmount],
          [1],
          [0],
          [0],
          [0],
          ['0x0000000000000000000000000000000000000000000000000000000000000000'],
          ['0x0000000000000000000000000000000000000000000000000000000000000000'],
          [false]
        );

        // Flashloan + premium > aToken balance. Then it will only swap the balance - premium
        const flashloanFee = liquidityToSwap * 9n / 10000n;
        const swappedAmount = (liquidityToSwap - flashloanFee);

        await expect(
          pool
            .connect(user)
            .flashLoan(
              getContractAddress(uniswapLiquiditySwapAdapter),
              [getContractAddress(weth)],
              [liquidityToSwap.toString()],
              [0],
              userAddress,
              params,
              0
            )
        )
          .to.emit(uniswapLiquiditySwapAdapter, 'Swapped')
          .withArgs(getContractAddress(weth), getContractAddress(dai), swappedAmount.toString(), expectedDaiAmount);

        const adapterWethBalance = await weth.balanceOf(getContractAddress(uniswapLiquiditySwapAdapter));
        const adapterDaiBalance = await dai.balanceOf(getContractAddress(uniswapLiquiditySwapAdapter));
        const adapterDaiAllowance = await dai.allowance(
          getContractAddress(uniswapLiquiditySwapAdapter),
          userAddress
        );
        const userADaiBalance = await aDai.balanceOf(userAddress);
        const userAEthBalance = await aWETH.balanceOf(userAddress);
        const adapterAEthBalance = await aWETH.balanceOf(getContractAddress(uniswapLiquiditySwapAdapter));

        expect(adapterWethBalance).to.be.eq(0n);
        expect(adapterDaiBalance).to.be.eq(0n);
        expect(adapterDaiAllowance).to.be.eq(0n);
        expect(userADaiBalance).to.be.eq(expectedDaiAmount);
        expect(userAEthBalance).to.be.eq(0n);
        expect(adapterAEthBalance).to.be.eq(0n);
      });

      it('should correctly swap tokens all the balance using permit', async () => {
        const {
          users,
          weth,
          oracle,
          dai,
          aDai,
          aWETH,
          pool,
          uniswapLiquiditySwapAdapter,
        } = testEnv;
        const user = users[0].signer;
        const userAddress = users[0].address;

        const amountWETHtoSwap = await convertToCurrencyDecimals(getContractAddress(weth), '10');

        const daiPrice = await oracle.getAssetPrice(getContractAddress(dai));
        const expectedDaiAmount = await convertToCurrencyDecimals(
          getContractAddress(dai),
          new BigNumber(amountWETHtoSwap.toString()).div(daiPrice.toString()).toFixed(0)
        );

        await mockUniswapRouter.setAmountToReturn(getContractAddress(weth), expectedDaiAmount);

        // Remove other balance
        await aWETH.connect(user).transfer(users[1].address, parseEther('90'));
        const userAEthBalanceBefore = await aWETH.balanceOf(userAddress);

        const liquidityToSwap = parseEther('10');
        expect(userAEthBalanceBefore).to.be.eq(liquidityToSwap);

        const chainId = Number((await DRE.ethers.provider.getNetwork()).chainId);
        const deadline = MAX_UINT_AMOUNT;
        const nonce = Number(await aWETH._nonces(userAddress));
        const msgParams = buildPermitParams(
          chainId,
          getContractAddress(aWETH),
          '1',
          await aWETH.name(),
          userAddress,
          getContractAddress(uniswapLiquiditySwapAdapter),
          nonce,
          deadline,
          liquidityToSwap.toString()
        );

        const ownerPrivateKey = accounts[1].secretKey;
        if (!ownerPrivateKey) {
          throw new Error('INVALID_OWNER_PK');
        }

        const { v, r, s } = getSignatureFromTypedData(ownerPrivateKey, msgParams);

        const params = buildLiquiditySwapParams(
          [getContractAddress(dai)],
          [expectedDaiAmount],
          [1],
          [liquidityToSwap],
          [deadline],
          [v],
          [r],
          [s],
          [false]
        );

        // Flashloan + premium > aToken balance. Then it will only swap the balance - premium
        const flashloanFee = liquidityToSwap * 9n / 10000n;
        const swappedAmount = (liquidityToSwap - flashloanFee);

        await expect(
          pool
            .connect(user)
            .flashLoan(
              getContractAddress(uniswapLiquiditySwapAdapter),
              [getContractAddress(weth)],
              [liquidityToSwap.toString()],
              [0],
              userAddress,
              params,
              0
            )
        )
          .to.emit(uniswapLiquiditySwapAdapter, 'Swapped')
          .withArgs(getContractAddress(weth), getContractAddress(dai), swappedAmount.toString(), expectedDaiAmount);

        const adapterWethBalance = await weth.balanceOf(getContractAddress(uniswapLiquiditySwapAdapter));
        const adapterDaiBalance = await dai.balanceOf(getContractAddress(uniswapLiquiditySwapAdapter));
        const adapterDaiAllowance = await dai.allowance(
          getContractAddress(uniswapLiquiditySwapAdapter),
          userAddress
        );
        const userADaiBalance = await aDai.balanceOf(userAddress);
        const userAEthBalance = await aWETH.balanceOf(userAddress);
        const adapterAEthBalance = await aWETH.balanceOf(getContractAddress(uniswapLiquiditySwapAdapter));

        expect(adapterWethBalance).to.be.eq(0n);
        expect(adapterDaiBalance).to.be.eq(0n);
        expect(adapterDaiAllowance).to.be.eq(0n);
        expect(userADaiBalance).to.be.eq(expectedDaiAmount);
        expect(userAEthBalance).to.be.eq(0n);
        expect(adapterAEthBalance).to.be.eq(0n);
      });
    });

    describe('swapAndDeposit', () => {
      beforeEach(async () => {
        const { users, weth, dai, pool, deployer } = testEnv;
        const userAddress = users[0].address;

        // Provide liquidity
        await dai.mint(parseEther('20000'));
        await dai.approve(getContractAddress(pool), parseEther('20000'));
        await pool.deposit(getContractAddress(dai), parseEther('20000'), deployer.address, 0);

        // Make a deposit for user
        await weth.mint(parseEther('100'));
        await weth.approve(getContractAddress(pool), parseEther('100'));
        await pool.deposit(getContractAddress(weth), parseEther('100'), userAddress, 0);
      });

      it('should correctly swap tokens and deposit the out tokens in the pool', async () => {
        const { users, weth, oracle, dai, aDai, aWETH, uniswapLiquiditySwapAdapter } = testEnv;
        const user = users[0].signer;
        const userAddress = users[0].address;

        const amountWETHtoSwap = await convertToCurrencyDecimals(getContractAddress(weth), '10');

        const daiPrice = await oracle.getAssetPrice(getContractAddress(dai));
        const expectedDaiAmount = await convertToCurrencyDecimals(
          getContractAddress(dai),
          new BigNumber(amountWETHtoSwap.toString()).div(daiPrice.toString()).toFixed(0)
        );

        await mockUniswapRouter.setAmountToReturn(getContractAddress(weth), expectedDaiAmount);

        // User will swap liquidity 10 aEth to aDai
        const liquidityToSwap = parseEther('10');
        await aWETH.connect(user).approve(getContractAddress(uniswapLiquiditySwapAdapter), liquidityToSwap);
        const userAEthBalanceBefore = await aWETH.balanceOf(userAddress);

        await expect(
          uniswapLiquiditySwapAdapter.connect(user).swapAndDeposit(
            [getContractAddress(weth)],
            [getContractAddress(dai)],
            [amountWETHtoSwap],
            [expectedDaiAmount],
            [
              {
                amount: 0,
                deadline: 0,
                v: 0,
                r: '0x0000000000000000000000000000000000000000000000000000000000000000',
                s: '0x0000000000000000000000000000000000000000000000000000000000000000',
              },
            ],
            [false]
          )
        )
          .to.emit(uniswapLiquiditySwapAdapter, 'Swapped')
          .withArgs(getContractAddress(weth), getContractAddress(dai), amountWETHtoSwap.toString(), expectedDaiAmount);

        const adapterWethBalance = await weth.balanceOf(getContractAddress(uniswapLiquiditySwapAdapter));
        const adapterDaiBalance = await dai.balanceOf(getContractAddress(uniswapLiquiditySwapAdapter));
        const adapterDaiAllowance = await dai.allowance(
          getContractAddress(uniswapLiquiditySwapAdapter),
          userAddress
        );
        const userADaiBalance = await aDai.balanceOf(userAddress);
        const userAEthBalance = await aWETH.balanceOf(userAddress);

        expect(adapterWethBalance).to.be.eq(0n);
        expect(adapterDaiBalance).to.be.eq(0n);
        expect(adapterDaiAllowance).to.be.eq(0n);
        expect(userADaiBalance).to.be.eq(expectedDaiAmount);
        expect(userAEthBalance).to.be.lt(userAEthBalanceBefore);
        expect(userAEthBalance).to.be.gte((userAEthBalanceBefore - liquidityToSwap));
      });

      it('should correctly swap tokens using permit', async () => {
        const { users, weth, oracle, dai, aDai, aWETH, uniswapLiquiditySwapAdapter } = testEnv;
        const user = users[0].signer;
        const userAddress = users[0].address;

        const amountWETHtoSwap = await convertToCurrencyDecimals(getContractAddress(weth), '10');

        const daiPrice = await oracle.getAssetPrice(getContractAddress(dai));
        const expectedDaiAmount = await convertToCurrencyDecimals(
          getContractAddress(dai),
          new BigNumber(amountWETHtoSwap.toString()).div(daiPrice.toString()).toFixed(0)
        );

        await mockUniswapRouter.setAmountToReturn(getContractAddress(weth), expectedDaiAmount);

        // User will swap liquidity 10 aEth to aDai
        const liquidityToSwap = parseEther('10');
        const userAEthBalanceBefore = await aWETH.balanceOf(userAddress);

        const chainId = Number((await DRE.ethers.provider.getNetwork()).chainId);
        const deadline = MAX_UINT_AMOUNT;
        const nonce = Number(await aWETH._nonces(userAddress));
        const msgParams = buildPermitParams(
          chainId,
          getContractAddress(aWETH),
          '1',
          await aWETH.name(),
          userAddress,
          getContractAddress(uniswapLiquiditySwapAdapter),
          nonce,
          deadline,
          liquidityToSwap.toString()
        );

        const ownerPrivateKey = accounts[1].secretKey;
        if (!ownerPrivateKey) {
          throw new Error('INVALID_OWNER_PK');
        }

        const { v, r, s } = getSignatureFromTypedData(ownerPrivateKey, msgParams);

        await expect(
          uniswapLiquiditySwapAdapter.connect(user).swapAndDeposit(
            [getContractAddress(weth)],
            [getContractAddress(dai)],
            [amountWETHtoSwap],
            [expectedDaiAmount],
            [
              {
                amount: liquidityToSwap,
                deadline,
                v,
                r,
                s,
              },
            ],
            [false]
          )
        )
          .to.emit(uniswapLiquiditySwapAdapter, 'Swapped')
          .withArgs(getContractAddress(weth), getContractAddress(dai), amountWETHtoSwap.toString(), expectedDaiAmount);

        const adapterWethBalance = await weth.balanceOf(getContractAddress(uniswapLiquiditySwapAdapter));
        const adapterDaiBalance = await dai.balanceOf(getContractAddress(uniswapLiquiditySwapAdapter));
        const adapterDaiAllowance = await dai.allowance(
          getContractAddress(uniswapLiquiditySwapAdapter),
          userAddress
        );
        const userADaiBalance = await aDai.balanceOf(userAddress);
        const userAEthBalance = await aWETH.balanceOf(userAddress);

        expect(adapterWethBalance).to.be.eq(0n);
        expect(adapterDaiBalance).to.be.eq(0n);
        expect(adapterDaiAllowance).to.be.eq(0n);
        expect(userADaiBalance).to.be.eq(expectedDaiAmount);
        expect(userAEthBalance).to.be.lt(userAEthBalanceBefore);
        expect(userAEthBalance).to.be.gte((userAEthBalanceBefore - liquidityToSwap));
      });

      it('should revert if inconsistent params', async () => {
        const { users, weth, dai, uniswapLiquiditySwapAdapter, oracle } = testEnv;
        const user = users[0].signer;

        const amountWETHtoSwap = await convertToCurrencyDecimals(getContractAddress(weth), '10');
        const daiPrice = await oracle.getAssetPrice(getContractAddress(dai));
        const expectedDaiAmount = await convertToCurrencyDecimals(
          getContractAddress(dai),
          new BigNumber(amountWETHtoSwap.toString()).div(daiPrice.toString()).toFixed(0)
        );

        await expect(
          uniswapLiquiditySwapAdapter.connect(user).swapAndDeposit(
            [getContractAddress(weth), getContractAddress(dai)],
            [getContractAddress(dai)],
            [amountWETHtoSwap],
            [expectedDaiAmount],
            [
              {
                amount: 0,
                deadline: 0,
                v: 0,
                r: '0x0000000000000000000000000000000000000000000000000000000000000000',
                s: '0x0000000000000000000000000000000000000000000000000000000000000000',
              },
            ],
            [false]
          )
        ).to.be.revertedWith('INCONSISTENT_PARAMS');

        await expect(
          uniswapLiquiditySwapAdapter.connect(user).swapAndDeposit(
            [getContractAddress(weth)],
            [getContractAddress(dai), getContractAddress(weth)],
            [amountWETHtoSwap],
            [expectedDaiAmount],
            [
              {
                amount: 0,
                deadline: 0,
                v: 0,
                r: '0x0000000000000000000000000000000000000000000000000000000000000000',
                s: '0x0000000000000000000000000000000000000000000000000000000000000000',
              },
            ],
            [false]
          )
        ).to.be.revertedWith('INCONSISTENT_PARAMS');

        await expect(
          uniswapLiquiditySwapAdapter.connect(user).swapAndDeposit(
            [getContractAddress(weth)],
            [getContractAddress(dai)],
            [amountWETHtoSwap, amountWETHtoSwap],
            [expectedDaiAmount],
            [
              {
                amount: 0,
                deadline: 0,
                v: 0,
                r: '0x0000000000000000000000000000000000000000000000000000000000000000',
                s: '0x0000000000000000000000000000000000000000000000000000000000000000',
              },
            ],
            [false]
          )
        ).to.be.revertedWith('INCONSISTENT_PARAMS');

        await expect(
          uniswapLiquiditySwapAdapter
            .connect(user)
            .swapAndDeposit(
              [getContractAddress(weth)],
              [getContractAddress(dai)],
              [amountWETHtoSwap],
              [expectedDaiAmount],
              [],
              [false]
            )
        ).to.be.revertedWith('INCONSISTENT_PARAMS');

        await expect(
          uniswapLiquiditySwapAdapter.connect(user).swapAndDeposit(
            [getContractAddress(weth)],
            [getContractAddress(dai)],
            [amountWETHtoSwap],
            [expectedDaiAmount, expectedDaiAmount],
            [
              {
                amount: 0,
                deadline: 0,
                v: 0,
                r: '0x0000000000000000000000000000000000000000000000000000000000000000',
                s: '0x0000000000000000000000000000000000000000000000000000000000000000',
              },
            ],
            [false]
          )
        ).to.be.revertedWith('INCONSISTENT_PARAMS');
      });

      it('should revert when min amount to receive exceeds the max slippage amount', async () => {
        const { users, weth, oracle, dai, aWETH, uniswapLiquiditySwapAdapter } = testEnv;
        const user = users[0].signer;

        const amountWETHtoSwap = await convertToCurrencyDecimals(getContractAddress(weth), '10');

        const daiPrice = await oracle.getAssetPrice(getContractAddress(dai));
        const expectedDaiAmount = await convertToCurrencyDecimals(
          getContractAddress(dai),
          new BigNumber(amountWETHtoSwap.toString()).div(daiPrice.toString()).toFixed(0)
        );

        await mockUniswapRouter.setAmountToReturn(getContractAddress(weth), expectedDaiAmount);
        const smallExpectedDaiAmount = expectedDaiAmount / 2n;

        // User will swap liquidity 10 aEth to aDai
        const liquidityToSwap = parseEther('10');
        await aWETH.connect(user).approve(getContractAddress(uniswapLiquiditySwapAdapter), liquidityToSwap);

        await expect(
          uniswapLiquiditySwapAdapter.connect(user).swapAndDeposit(
            [getContractAddress(weth)],
            [getContractAddress(dai)],
            [amountWETHtoSwap],
            [smallExpectedDaiAmount],
            [
              {
                amount: 0,
                deadline: 0,
                v: 0,
                r: '0x0000000000000000000000000000000000000000000000000000000000000000',
                s: '0x0000000000000000000000000000000000000000000000000000000000000000',
              },
            ],
            [false]
          )
        ).to.be.revertedWith('minAmountOut exceed max slippage');
      });

      it('should correctly swap tokens and deposit multiple tokens', async () => {
        const {
          users,
          weth,
          usdc,
          oracle,
          dai,
          aDai,
          aWETH,
          uniswapLiquiditySwapAdapter,
          pool,
        } = testEnv;
        const user = users[0].signer;
        const userAddress = users[0].address;

        const amountWETHtoSwap = await convertToCurrencyDecimals(getContractAddress(weth), '10');

        const daiPrice = await oracle.getAssetPrice(getContractAddress(dai));
        const expectedDaiAmountForEth = await convertToCurrencyDecimals(
          getContractAddress(dai),
          new BigNumber(amountWETHtoSwap.toString()).div(daiPrice.toString()).toFixed(0)
        );

        const amountUSDCtoSwap = await convertToCurrencyDecimals(getContractAddress(usdc), '10');
        const usdcPrice = await oracle.getAssetPrice(getContractAddress(usdc));

        const collateralDecimals = (await usdc.decimals()).toString();
        const principalDecimals = (await dai.decimals()).toString();

        const expectedDaiAmountForUsdc = await convertToCurrencyDecimals(
          getContractAddress(dai),
          new BigNumber(amountUSDCtoSwap.toString())
            .times(
              new BigNumber(usdcPrice.toString()).times(new BigNumber(10).pow(principalDecimals))
            )
            .div(
              new BigNumber(daiPrice.toString()).times(new BigNumber(10).pow(collateralDecimals))
            )
            .div(new BigNumber(10).pow(principalDecimals))
            .toFixed(0)
        );

        // Make a deposit for user
        await usdc.connect(user).mint(amountUSDCtoSwap);
        await usdc.connect(user).approve(getContractAddress(pool), amountUSDCtoSwap);
        await pool.connect(user).deposit(getContractAddress(usdc), amountUSDCtoSwap, userAddress, 0);

        const aUsdcData = await pool.getReserveData(getContractAddress(usdc));
        const aUsdc = await getContract<AToken>(eContractid.AToken, aUsdcData.aTokenAddress);

        await mockUniswapRouter.setAmountToReturn(getContractAddress(weth), expectedDaiAmountForEth);
        await mockUniswapRouter.setAmountToReturn(getContractAddress(usdc), expectedDaiAmountForUsdc);

        await aWETH.connect(user).approve(getContractAddress(uniswapLiquiditySwapAdapter), amountWETHtoSwap);
        const userAEthBalanceBefore = await aWETH.balanceOf(userAddress);
        await aUsdc.connect(user).approve(getContractAddress(uniswapLiquiditySwapAdapter), amountUSDCtoSwap);
        const userAUsdcBalanceBefore = await aUsdc.balanceOf(userAddress);

        await uniswapLiquiditySwapAdapter.connect(user).swapAndDeposit(
          [getContractAddress(weth), getContractAddress(usdc)],
          [getContractAddress(dai), getContractAddress(dai)],
          [amountWETHtoSwap, amountUSDCtoSwap],
          [expectedDaiAmountForEth, expectedDaiAmountForUsdc],
          [
            {
              amount: 0,
              deadline: 0,
              v: 0,
              r: '0x0000000000000000000000000000000000000000000000000000000000000000',
              s: '0x0000000000000000000000000000000000000000000000000000000000000000',
            },
            {
              amount: 0,
              deadline: 0,
              v: 0,
              r: '0x0000000000000000000000000000000000000000000000000000000000000000',
              s: '0x0000000000000000000000000000000000000000000000000000000000000000',
            },
          ],
          [false, false]
        );

        const adapterWethBalance = await weth.balanceOf(getContractAddress(uniswapLiquiditySwapAdapter));
        const adapterDaiBalance = await dai.balanceOf(getContractAddress(uniswapLiquiditySwapAdapter));
        const adapterDaiAllowance = await dai.allowance(
          getContractAddress(uniswapLiquiditySwapAdapter),
          userAddress
        );
        const userADaiBalance = await aDai.balanceOf(userAddress);
        const userAEthBalance = await aWETH.balanceOf(userAddress);
        const userAUsdcBalance = await aUsdc.balanceOf(userAddress);

        expect(adapterWethBalance).to.be.eq(0n);
        expect(adapterDaiBalance).to.be.eq(0n);
        expect(adapterDaiAllowance).to.be.eq(0n);
        expect(userADaiBalance).to.be.eq((expectedDaiAmountForEth + expectedDaiAmountForUsdc));
        expect(userAEthBalance).to.be.lt(userAEthBalanceBefore);
        expect(userAEthBalance).to.be.gte((userAEthBalanceBefore - amountWETHtoSwap));
        expect(userAUsdcBalance).to.be.lt(userAUsdcBalanceBefore);
        expect(userAUsdcBalance).to.be.gte((userAUsdcBalanceBefore - amountUSDCtoSwap));
      });

      it('should correctly swap tokens and deposit multiple tokens using permit', async () => {
        const {
          users,
          weth,
          usdc,
          oracle,
          dai,
          aDai,
          aWETH,
          uniswapLiquiditySwapAdapter,
          pool,
        } = testEnv;
        const user = users[0].signer;
        const userAddress = users[0].address;
        const chainId = Number((await DRE.ethers.provider.getNetwork()).chainId);
        const deadline = MAX_UINT_AMOUNT;

        const ownerPrivateKey = accounts[1].secretKey;
        if (!ownerPrivateKey) {
          throw new Error('INVALID_OWNER_PK');
        }

        const amountWETHtoSwap = await convertToCurrencyDecimals(getContractAddress(weth), '10');

        const daiPrice = await oracle.getAssetPrice(getContractAddress(dai));
        const expectedDaiAmountForEth = await convertToCurrencyDecimals(
          getContractAddress(dai),
          new BigNumber(amountWETHtoSwap.toString()).div(daiPrice.toString()).toFixed(0)
        );

        const amountUSDCtoSwap = await convertToCurrencyDecimals(getContractAddress(usdc), '10');
        const usdcPrice = await oracle.getAssetPrice(getContractAddress(usdc));

        const collateralDecimals = (await usdc.decimals()).toString();
        const principalDecimals = (await dai.decimals()).toString();

        const expectedDaiAmountForUsdc = await convertToCurrencyDecimals(
          getContractAddress(dai),
          new BigNumber(amountUSDCtoSwap.toString())
            .times(
              new BigNumber(usdcPrice.toString()).times(new BigNumber(10).pow(principalDecimals))
            )
            .div(
              new BigNumber(daiPrice.toString()).times(new BigNumber(10).pow(collateralDecimals))
            )
            .div(new BigNumber(10).pow(principalDecimals))
            .toFixed(0)
        );

        // Make a deposit for user
        await usdc.connect(user).mint(amountUSDCtoSwap);
        await usdc.connect(user).approve(getContractAddress(pool), amountUSDCtoSwap);
        await pool.connect(user).deposit(getContractAddress(usdc), amountUSDCtoSwap, userAddress, 0);

        const aUsdcData = await pool.getReserveData(getContractAddress(usdc));
        const aUsdc = await getContract<AToken>(eContractid.AToken, aUsdcData.aTokenAddress);

        await mockUniswapRouter.setAmountToReturn(getContractAddress(weth), expectedDaiAmountForEth);
        await mockUniswapRouter.setAmountToReturn(getContractAddress(usdc), expectedDaiAmountForUsdc);

        const userAEthBalanceBefore = await aWETH.balanceOf(userAddress);
        const userAUsdcBalanceBefore = await aUsdc.balanceOf(userAddress);

        const aWethNonce = Number(await aWETH._nonces(userAddress));
        const aWethMsgParams = buildPermitParams(
          chainId,
          getContractAddress(aWETH),
          '1',
          await aWETH.name(),
          userAddress,
          getContractAddress(uniswapLiquiditySwapAdapter),
          aWethNonce,
          deadline,
          amountWETHtoSwap.toString()
        );
        const { v: aWETHv, r: aWETHr, s: aWETHs } = getSignatureFromTypedData(
          ownerPrivateKey,
          aWethMsgParams
        );

        const aUsdcNonce = Number(await aUsdc._nonces(userAddress));
        const aUsdcMsgParams = buildPermitParams(
          chainId,
          getContractAddress(aUsdc),
          '1',
          await aUsdc.name(),
          userAddress,
          getContractAddress(uniswapLiquiditySwapAdapter),
          aUsdcNonce,
          deadline,
          amountUSDCtoSwap.toString()
        );
        const { v: aUsdcv, r: aUsdcr, s: aUsdcs } = getSignatureFromTypedData(
          ownerPrivateKey,
          aUsdcMsgParams
        );

        await uniswapLiquiditySwapAdapter.connect(user).swapAndDeposit(
          [getContractAddress(weth), getContractAddress(usdc)],
          [getContractAddress(dai), getContractAddress(dai)],
          [amountWETHtoSwap, amountUSDCtoSwap],
          [expectedDaiAmountForEth, expectedDaiAmountForUsdc],
          [
            {
              amount: amountWETHtoSwap,
              deadline,
              v: aWETHv,
              r: aWETHr,
              s: aWETHs,
            },
            {
              amount: amountUSDCtoSwap,
              deadline,
              v: aUsdcv,
              r: aUsdcr,
              s: aUsdcs,
            },
          ],
          [false, false]
        );

        const adapterWethBalance = await weth.balanceOf(getContractAddress(uniswapLiquiditySwapAdapter));
        const adapterDaiBalance = await dai.balanceOf(getContractAddress(uniswapLiquiditySwapAdapter));
        const adapterDaiAllowance = await dai.allowance(
          getContractAddress(uniswapLiquiditySwapAdapter),
          userAddress
        );
        const userADaiBalance = await aDai.balanceOf(userAddress);
        const userAEthBalance = await aWETH.balanceOf(userAddress);
        const userAUsdcBalance = await aUsdc.balanceOf(userAddress);

        expect(adapterWethBalance).to.be.eq(0n);
        expect(adapterDaiBalance).to.be.eq(0n);
        expect(adapterDaiAllowance).to.be.eq(0n);
        expect(userADaiBalance).to.be.eq((expectedDaiAmountForEth + expectedDaiAmountForUsdc));
        expect(userAEthBalance).to.be.lt(userAEthBalanceBefore);
        expect(userAEthBalance).to.be.gte((userAEthBalanceBefore - amountWETHtoSwap));
        expect(userAUsdcBalance).to.be.lt(userAUsdcBalanceBefore);
        expect(userAUsdcBalance).to.be.gte((userAUsdcBalanceBefore - amountUSDCtoSwap));
      });

      it('should correctly swap all the balance when using a bigger amount', async () => {
        const { users, weth, oracle, dai, aDai, aWETH, uniswapLiquiditySwapAdapter } = testEnv;
        const user = users[0].signer;
        const userAddress = users[0].address;

        const amountWETHtoSwap = await convertToCurrencyDecimals(getContractAddress(weth), '10');

        const daiPrice = await oracle.getAssetPrice(getContractAddress(dai));
        const expectedDaiAmount = await convertToCurrencyDecimals(
          getContractAddress(dai),
          new BigNumber(amountWETHtoSwap.toString()).div(daiPrice.toString()).toFixed(0)
        );

        await mockUniswapRouter.setAmountToReturn(getContractAddress(weth), expectedDaiAmount);

        // Remove other balance
        await aWETH.connect(user).transfer(users[1].address, parseEther('90'));
        const userAEthBalanceBefore = await aWETH.balanceOf(userAddress);

        // User will swap liquidity 10 aEth to aDai
        const liquidityToSwap = parseEther('10');
        expect(userAEthBalanceBefore).to.be.eq(liquidityToSwap);

        // User will swap liquidity 10 aEth to aDai
        await aWETH.connect(user).approve(getContractAddress(uniswapLiquiditySwapAdapter), liquidityToSwap);

        // Only has 10 atokens, so all the balance will be swapped
        const bigAmountToSwap = parseEther('100');

        await expect(
          uniswapLiquiditySwapAdapter.connect(user).swapAndDeposit(
            [getContractAddress(weth)],
            [getContractAddress(dai)],
            [bigAmountToSwap],
            [expectedDaiAmount],
            [
              {
                amount: 0,
                deadline: 0,
                v: 0,
                r: '0x0000000000000000000000000000000000000000000000000000000000000000',
                s: '0x0000000000000000000000000000000000000000000000000000000000000000',
              },
            ],
            [false]
          )
        )
          .to.emit(uniswapLiquiditySwapAdapter, 'Swapped')
          .withArgs(getContractAddress(weth), getContractAddress(dai), amountWETHtoSwap.toString(), expectedDaiAmount);

        const adapterWethBalance = await weth.balanceOf(getContractAddress(uniswapLiquiditySwapAdapter));
        const adapterDaiBalance = await dai.balanceOf(getContractAddress(uniswapLiquiditySwapAdapter));
        const adapterDaiAllowance = await dai.allowance(
          getContractAddress(uniswapLiquiditySwapAdapter),
          userAddress
        );
        const userADaiBalance = await aDai.balanceOf(userAddress);
        const userAEthBalance = await aWETH.balanceOf(userAddress);
        const adapterAEthBalance = await aWETH.balanceOf(getContractAddress(uniswapLiquiditySwapAdapter));

        expect(adapterWethBalance).to.be.eq(0n);
        expect(adapterDaiBalance).to.be.eq(0n);
        expect(adapterDaiAllowance).to.be.eq(0n);
        expect(userADaiBalance).to.be.eq(expectedDaiAmount);
        expect(userAEthBalance).to.be.eq(0n);
        expect(adapterAEthBalance).to.be.eq(0n);
      });

      it('should correctly swap all the balance when using permit', async () => {
        const { users, weth, oracle, dai, aDai, aWETH, uniswapLiquiditySwapAdapter } = testEnv;
        const user = users[0].signer;
        const userAddress = users[0].address;

        const amountWETHtoSwap = await convertToCurrencyDecimals(getContractAddress(weth), '10');

        const daiPrice = await oracle.getAssetPrice(getContractAddress(dai));
        const expectedDaiAmount = await convertToCurrencyDecimals(
          getContractAddress(dai),
          new BigNumber(amountWETHtoSwap.toString()).div(daiPrice.toString()).toFixed(0)
        );

        await mockUniswapRouter.setAmountToReturn(getContractAddress(weth), expectedDaiAmount);

        // Remove other balance
        await aWETH.connect(user).transfer(users[1].address, parseEther('90'));
        const userAEthBalanceBefore = await aWETH.balanceOf(userAddress);

        // User will swap liquidity 10 aEth to aDai
        const liquidityToSwap = parseEther('10');
        expect(userAEthBalanceBefore).to.be.eq(liquidityToSwap);

        // Only has 10 atokens, so all the balance will be swapped
        const bigAmountToSwap = parseEther('100');

        const chainId = Number((await DRE.ethers.provider.getNetwork()).chainId);
        const deadline = MAX_UINT_AMOUNT;

        const ownerPrivateKey = accounts[1].secretKey;
        if (!ownerPrivateKey) {
          throw new Error('INVALID_OWNER_PK');
        }
        const aWethNonce = Number(await aWETH._nonces(userAddress));
        const aWethMsgParams = buildPermitParams(
          chainId,
          getContractAddress(aWETH),
          '1',
          await aWETH.name(),
          userAddress,
          getContractAddress(uniswapLiquiditySwapAdapter),
          aWethNonce,
          deadline,
          bigAmountToSwap.toString()
        );
        const { v, r, s } = getSignatureFromTypedData(ownerPrivateKey, aWethMsgParams);

        await expect(
          uniswapLiquiditySwapAdapter.connect(user).swapAndDeposit(
            [getContractAddress(weth)],
            [getContractAddress(dai)],
            [bigAmountToSwap],
            [expectedDaiAmount],
            [
              {
                amount: bigAmountToSwap,
                deadline,
                v,
                r,
                s,
              },
            ],
            [false]
          )
        )
          .to.emit(uniswapLiquiditySwapAdapter, 'Swapped')
          .withArgs(getContractAddress(weth), getContractAddress(dai), amountWETHtoSwap.toString(), expectedDaiAmount);

        const adapterWethBalance = await weth.balanceOf(getContractAddress(uniswapLiquiditySwapAdapter));
        const adapterDaiBalance = await dai.balanceOf(getContractAddress(uniswapLiquiditySwapAdapter));
        const adapterDaiAllowance = await dai.allowance(
          getContractAddress(uniswapLiquiditySwapAdapter),
          userAddress
        );
        const userADaiBalance = await aDai.balanceOf(userAddress);
        const userAEthBalance = await aWETH.balanceOf(userAddress);
        const adapterAEthBalance = await aWETH.balanceOf(getContractAddress(uniswapLiquiditySwapAdapter));

        expect(adapterWethBalance).to.be.eq(0n);
        expect(adapterDaiBalance).to.be.eq(0n);
        expect(adapterDaiAllowance).to.be.eq(0n);
        expect(userADaiBalance).to.be.eq(expectedDaiAmount);
        expect(userAEthBalance).to.be.eq(0n);
        expect(adapterAEthBalance).to.be.eq(0n);
      });
    });
  });
});
