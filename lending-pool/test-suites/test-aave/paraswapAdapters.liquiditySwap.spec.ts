import { makeSuite } from './helpers/make-suite.js';
import type { TestEnv } from './helpers/make-suite.js';
import {
  convertToCurrencyDecimals,
  getContract,
  buildPermitParams,
  getSignatureFromTypedData,
  buildParaSwapLiquiditySwapParams,
  getContractAddress
} from '../../helpers/contracts-helpers.js';
import {
  getMockParaSwapAugustus,
  getMockParaSwapAugustusRegistry,
} from '../../helpers/contracts-getters.js';
import { deployParaSwapLiquiditySwapAdapter } from '../../helpers/contracts-deployments.js';
import type { MockParaSwapAugustus, MockParaSwapAugustusRegistry } from '../../types/ethers-contracts/index.js';
import BigNumber from "bignumber.js";

import { DRE, evmRevert, evmSnapshot } from '../../helpers/misc-utils.js';
import { ethers, parseEther } from 'ethers';
import { eContractid } from '../../helpers/types.js';
import type { AToken } from '../../types/ethers-contracts/index.js';
import { BUIDLEREVM_CHAINID } from '../../helpers/buidler-constants.js';
import { MAX_UINT_AMOUNT } from '../../helpers/constants.js';

import chai from 'chai';
import { accounts } from '../../test-wallets.js';
const { expect } = chai;

makeSuite('ParaSwap adapters', (testEnv: TestEnv) => {
  let mockAugustus: MockParaSwapAugustus;
  let mockAugustusRegistry: MockParaSwapAugustusRegistry;
  let evmSnapshotId: string;

  before(async () => {
    mockAugustus = await getMockParaSwapAugustus();
    mockAugustusRegistry = await getMockParaSwapAugustusRegistry();
  });

  beforeEach(async () => {
    evmSnapshotId = await evmSnapshot();
  });

  afterEach(async () => {
    await evmRevert(evmSnapshotId);
  });

  describe('ParaSwapLiquiditySwapAdapter', () => {
    describe('constructor', () => {
      it('should deploy with correct parameters', async () => {
        const { addressesProvider } = testEnv;
        await deployParaSwapLiquiditySwapAdapter([
          getContractAddress(addressesProvider),
          getContractAddress(mockAugustusRegistry),
        ]);
      });

      it('should revert if not valid addresses provider', async () => {
        await expect(
          deployParaSwapLiquiditySwapAdapter([
            getContractAddress(mockAugustus), // any invalid contract can be used here
            getContractAddress(mockAugustusRegistry),
          ])
        ).to.be.revert(DRE.ethers);
      });

      it('should revert if not valid augustus registry', async () => {
        const { addressesProvider } = testEnv;
        await expect(
          deployParaSwapLiquiditySwapAdapter([
            getContractAddress(addressesProvider),
            getContractAddress(mockAugustus), // any invalid contract can be used here
          ])
        ).to.be.revert(DRE.ethers);
      });
    });

    describe('executeOperation', () => {
      beforeEach(async () => {
        const { users, weth, dai, pool, deployer } = testEnv;
        const userAddress = users[0].address;

        // Provide liquidity
        await dai.mint(parseEther('20000'));
        await dai.approve(getContractAddress(pool), parseEther('20000'));
        await pool.deposit(getContractAddress(dai), parseEther('20000'), deployer.address, 0);

        await weth.mint(parseEther('10000'));
        await weth.approve(getContractAddress(pool), parseEther('10000'));
        await pool.deposit(getContractAddress(weth), parseEther('10000'), deployer.address, 0);

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
          paraswapLiquiditySwapAdapter,
        } = testEnv;
        const user = users[0].signer;
        const userAddress = users[0].address;

        const amountWETHtoSwap = await convertToCurrencyDecimals(getContractAddress(weth), '10');

        const daiPrice = await oracle.getAssetPrice(getContractAddress(dai));
        const expectedDaiAmount = await convertToCurrencyDecimals(
          getContractAddress(dai),
          new BigNumber(amountWETHtoSwap.toString()).div(daiPrice.toString()).toFixed(0)
        );

        await mockAugustus.expectSwap(getContractAddress(weth), getContractAddress(dai), amountWETHtoSwap, amountWETHtoSwap, expectedDaiAmount);

        const flashloanPremium = amountWETHtoSwap * 9n / 10000n;
        const flashloanTotal = (amountWETHtoSwap + flashloanPremium);

        // User will swap liquidity aEth to aDai
        const userAEthBalanceBefore = await aWETH.balanceOf(userAddress);
        await aWETH.connect(user).approve(getContractAddress(paraswapLiquiditySwapAdapter), flashloanTotal);

        const mockAugustusCalldata = mockAugustus.interface.encodeFunctionData(
          'swap',
          [getContractAddress(weth), getContractAddress(dai), amountWETHtoSwap, expectedDaiAmount]
        );

        const params = buildParaSwapLiquiditySwapParams(
          getContractAddress(dai),
          expectedDaiAmount,
          0,
          mockAugustusCalldata,
          getContractAddress(mockAugustus),
          0,
          0,
          0,
          '0x0000000000000000000000000000000000000000000000000000000000000000',
          '0x0000000000000000000000000000000000000000000000000000000000000000'
        );

        await expect(
          pool
            .connect(user)
            .flashLoan(
              getContractAddress(paraswapLiquiditySwapAdapter),
              [getContractAddress(weth)],
              [amountWETHtoSwap],
              [0],
              userAddress,
              params,
              0
            )
        )
          .to.emit(paraswapLiquiditySwapAdapter, 'Swapped')
          .withArgs(getContractAddress(weth), getContractAddress(dai), amountWETHtoSwap, expectedDaiAmount);

        const adapterWethBalance = await weth.balanceOf(getContractAddress(paraswapLiquiditySwapAdapter));
        const adapterDaiBalance = await dai.balanceOf(getContractAddress(paraswapLiquiditySwapAdapter));
        const userADaiBalance = await aDai.balanceOf(userAddress);
        const userAEthBalance = await aWETH.balanceOf(userAddress);

        // N.B. will get some portion of flashloan premium back from the pool
        expect(adapterWethBalance).to.be.eq(0n);
        expect(adapterDaiBalance).to.be.eq(0n);
        expect(userADaiBalance).to.be.eq(expectedDaiAmount);
        expect(userAEthBalance).to.be.gte((userAEthBalanceBefore - flashloanTotal));
        expect(userAEthBalance).to.be.lte((userAEthBalanceBefore - amountWETHtoSwap));
      });

      it('should correctly swap tokens using permit', async () => {
        const {
          users,
          weth,
          oracle,
          dai,
          aDai,
          aWETH,
          pool,
          paraswapLiquiditySwapAdapter,
        } = testEnv;
        const user = users[0].signer;
        const userAddress = users[0].address;

        const amountWETHtoSwap = await convertToCurrencyDecimals(getContractAddress(weth), '10');

        const daiPrice = await oracle.getAssetPrice(getContractAddress(dai));
        const expectedDaiAmount = await convertToCurrencyDecimals(
          getContractAddress(dai),
          new BigNumber(amountWETHtoSwap.toString()).div(daiPrice.toString()).toFixed(0)
        );

        await mockAugustus.expectSwap(getContractAddress(weth), getContractAddress(dai), amountWETHtoSwap, amountWETHtoSwap, expectedDaiAmount);

        const flashloanPremium = amountWETHtoSwap * 9n / 10000n;
        const flashloanTotal = (amountWETHtoSwap + flashloanPremium);

        // User will swap liquidity aEth to aDai
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
          getContractAddress(paraswapLiquiditySwapAdapter),
          nonce,
          deadline,
          flashloanTotal.toString()
        );

        const ownerPrivateKey = accounts[1].secretKey;
        if (!ownerPrivateKey) {
          throw new Error('INVALID_OWNER_PK');
        }

        const { v, r, s } = getSignatureFromTypedData(ownerPrivateKey, msgParams);

        const mockAugustusCalldata = mockAugustus.interface.encodeFunctionData(
          'swap',
          [getContractAddress(weth), getContractAddress(dai), amountWETHtoSwap, expectedDaiAmount]
        );

        const params = buildParaSwapLiquiditySwapParams(
          getContractAddress(dai),
          expectedDaiAmount,
          0,
          mockAugustusCalldata,
          getContractAddress(mockAugustus),
          flashloanTotal,
          deadline,
          v,
          r,
          s
        );

        await expect(
          pool
            .connect(user)
            .flashLoan(
              getContractAddress(paraswapLiquiditySwapAdapter),
              [getContractAddress(weth)],
              [amountWETHtoSwap],
              [0],
              userAddress,
              params,
              0
            )
        )
          .to.emit(paraswapLiquiditySwapAdapter, 'Swapped')
          .withArgs(getContractAddress(weth), getContractAddress(dai), amountWETHtoSwap, expectedDaiAmount);

        const adapterWethBalance = await weth.balanceOf(getContractAddress(paraswapLiquiditySwapAdapter));
        const adapterDaiBalance = await dai.balanceOf(getContractAddress(paraswapLiquiditySwapAdapter));
        const userADaiBalance = await aDai.balanceOf(userAddress);
        const userAEthBalance = await aWETH.balanceOf(userAddress);

        // N.B. will get some portion of flashloan premium back from the pool
        expect(adapterWethBalance).to.be.eq(0n);
        expect(adapterDaiBalance).to.be.eq(0n);
        expect(userADaiBalance).to.be.eq(expectedDaiAmount);
        expect(userAEthBalance).to.be.gte((userAEthBalanceBefore - flashloanTotal));
        expect(userAEthBalance).to.be.lte((userAEthBalanceBefore - amountWETHtoSwap));
      });

      it('should revert if caller not lending pool', async () => {
        const {
          users,
          weth,
          oracle,
          dai,
          aWETH,
          paraswapLiquiditySwapAdapter,
        } = testEnv;
        const user = users[0].signer;
        const userAddress = users[0].address;

        const amountWETHtoSwap = await convertToCurrencyDecimals(getContractAddress(weth), '10');

        const daiPrice = await oracle.getAssetPrice(getContractAddress(dai));
        const expectedDaiAmount = await convertToCurrencyDecimals(
          getContractAddress(dai),
          new BigNumber(amountWETHtoSwap.toString()).div(daiPrice.toString()).toFixed(0)
        );

        await mockAugustus.expectSwap(getContractAddress(weth), getContractAddress(dai), amountWETHtoSwap, amountWETHtoSwap, expectedDaiAmount);

        const flashloanPremium = amountWETHtoSwap * 9n / 10000n;
        const flashloanTotal = (amountWETHtoSwap + flashloanPremium);

        // User will swap liquidity aEth to aDai
        await aWETH.connect(user).approve(getContractAddress(paraswapLiquiditySwapAdapter), flashloanTotal);

        const mockAugustusCalldata = mockAugustus.interface.encodeFunctionData(
          'swap',
          [getContractAddress(weth), getContractAddress(dai), amountWETHtoSwap, expectedDaiAmount]
        );

        const params = buildParaSwapLiquiditySwapParams(
          getContractAddress(dai),
          expectedDaiAmount,
          0,
          mockAugustusCalldata,
          getContractAddress(mockAugustus),
          0,
          0,
          0,
          '0x0000000000000000000000000000000000000000000000000000000000000000',
          '0x0000000000000000000000000000000000000000000000000000000000000000'
        );

        await expect(
          paraswapLiquiditySwapAdapter
            .connect(user)
            .executeOperation(
              [getContractAddress(weth)],
              [amountWETHtoSwap],
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
          paraswapLiquiditySwapAdapter,
          pool,
          deployer,
        } = testEnv;
        const user = users[0].signer;
        const userAddress = users[0].address;

        const amountUSDCtoSwap = await convertToCurrencyDecimals(getContractAddress(usdc), '10');
        const liquidity = await convertToCurrencyDecimals(getContractAddress(usdc), '20000');

        const flashloanPremium = amountUSDCtoSwap * 9n / 10000n;
        const flashloanTotal = (amountUSDCtoSwap + flashloanPremium);

        // Provider liquidity
        await usdc.mint(liquidity);
        await usdc.approve(getContractAddress(pool), liquidity);
        await pool.deposit(getContractAddress(usdc), liquidity, deployer.address, 0);

        // Make a deposit for user
        await usdc.connect(user).mint(flashloanTotal);
        await usdc.connect(user).approve(getContractAddress(pool), flashloanTotal);
        await pool.connect(user).deposit(getContractAddress(usdc), flashloanTotal, userAddress, 0);

        const usdcPrice = await oracle.getAssetPrice(getContractAddress(usdc));
        const daiPrice = await oracle.getAssetPrice(getContractAddress(dai));

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

        await mockAugustus.expectSwap(getContractAddress(usdc), getContractAddress(dai), amountUSDCtoSwap, amountUSDCtoSwap, expectedDaiAmount);

        const aUsdcData = await pool.getReserveData(getContractAddress(usdc));
        const aUsdc = await getContract<AToken>(eContractid.AToken, aUsdcData.aTokenAddress);

        // User will swap liquidity aUsdc to aDai
        const userAUsdcBalanceBefore = await aUsdc.balanceOf(userAddress);
        await aUsdc.connect(user).approve(getContractAddress(paraswapLiquiditySwapAdapter), flashloanTotal);

        const mockAugustusCalldata = mockAugustus.interface.encodeFunctionData(
          'swap',
          [getContractAddress(usdc), getContractAddress(dai), amountUSDCtoSwap, expectedDaiAmount]
        );

        const params = buildParaSwapLiquiditySwapParams(
          getContractAddress(dai),
          expectedDaiAmount,
          0,
          mockAugustusCalldata,
          getContractAddress(mockAugustus),
          0,
          0,
          0,
          '0x0000000000000000000000000000000000000000000000000000000000000000',
          '0x0000000000000000000000000000000000000000000000000000000000000000'
        );

        await expect(
          pool
            .connect(user)
            .flashLoan(
              getContractAddress(paraswapLiquiditySwapAdapter),
              [getContractAddress(usdc)],
              [amountUSDCtoSwap],
              [0],
              userAddress,
              params,
              0
            )
        )
          .to.emit(paraswapLiquiditySwapAdapter, 'Swapped')
          .withArgs(getContractAddress(usdc), getContractAddress(dai), amountUSDCtoSwap, expectedDaiAmount);

        const adapterUsdcBalance = await usdc.balanceOf(getContractAddress(paraswapLiquiditySwapAdapter));
        const adapterDaiBalance = await dai.balanceOf(getContractAddress(paraswapLiquiditySwapAdapter));
        const userADaiBalance = await aDai.balanceOf(userAddress);
        const userAUsdcBalance = await aUsdc.balanceOf(userAddress);

        // N.B. will get some portion of flashloan premium back from the pool
        expect(adapterUsdcBalance).to.be.eq(0n);
        expect(adapterDaiBalance).to.be.eq(0n);
        expect(userADaiBalance).to.be.eq(expectedDaiAmount);
        expect(userAUsdcBalance).to.be.gte((userAUsdcBalanceBefore - flashloanTotal));
        expect(userAUsdcBalance).to.be.lte((userAUsdcBalanceBefore - amountUSDCtoSwap));
      });

      it('should revert when min amount to receive exceeds the max slippage amount', async () => {
        const {
          users,
          weth,
          oracle,
          dai,
          aWETH,
          pool,
          paraswapLiquiditySwapAdapter,
        } = testEnv;
        const user = users[0].signer;
        const userAddress = users[0].address;

        const amountWETHtoSwap = await convertToCurrencyDecimals(getContractAddress(weth), '10');

        const daiPrice = await oracle.getAssetPrice(getContractAddress(dai));
        const expectedDaiAmount = await convertToCurrencyDecimals(
          getContractAddress(dai),
          new BigNumber(amountWETHtoSwap.toString()).div(daiPrice.toString()).toFixed(0)
        );

        await mockAugustus.expectSwap(getContractAddress(weth), getContractAddress(dai), amountWETHtoSwap, amountWETHtoSwap, expectedDaiAmount);

        const smallExpectedDaiAmount = expectedDaiAmount / 2n;

        const flashloanPremium = amountWETHtoSwap * 9n / 10000n;
        const flashloanTotal = (amountWETHtoSwap + flashloanPremium);

        // User will swap liquidity aEth to aDai
        await aWETH.connect(user).approve(getContractAddress(paraswapLiquiditySwapAdapter), flashloanTotal);

        const mockAugustusCalldata = mockAugustus.interface.encodeFunctionData(
          'swap',
          [getContractAddress(weth), getContractAddress(dai), amountWETHtoSwap, expectedDaiAmount]
        );

        const params = buildParaSwapLiquiditySwapParams(
          getContractAddress(dai),
          smallExpectedDaiAmount,
          0,
          mockAugustusCalldata,
          getContractAddress(mockAugustus),
          0,
          0,
          0,
          '0x0000000000000000000000000000000000000000000000000000000000000000',
          '0x0000000000000000000000000000000000000000000000000000000000000000'
        );

        await expect(
          pool
            .connect(user)
            .flashLoan(
              getContractAddress(paraswapLiquiditySwapAdapter),
              [getContractAddress(weth)],
              [amountWETHtoSwap],
              [0],
              userAddress,
              params,
              0
            )
        ).to.be.revertedWith('MIN_AMOUNT_EXCEEDS_MAX_SLIPPAGE');
      });

      it('should revert when min amount to receive exceeds the max slippage amount (with tokens of different decimals)', async () => {
        const {
          users,
          usdc,
          oracle,
          dai,
          paraswapLiquiditySwapAdapter,
          pool,
          deployer,
        } = testEnv;
        const user = users[0].signer;
        const userAddress = users[0].address;

        const amountUSDCtoSwap = await convertToCurrencyDecimals(getContractAddress(usdc), '10');
        const liquidity = await convertToCurrencyDecimals(getContractAddress(usdc), '20000');

        const flashloanPremium = amountUSDCtoSwap * 9n / 10000n;
        const flashloanTotal = (amountUSDCtoSwap + flashloanPremium);

        // Provider liquidity
        await usdc.mint(liquidity);
        await usdc.approve(getContractAddress(pool), liquidity);
        await pool.deposit(getContractAddress(usdc), liquidity, deployer.address, 0);

        // Make a deposit for user
        await usdc.connect(user).mint(flashloanTotal);
        await usdc.connect(user).approve(getContractAddress(pool), flashloanTotal);
        await pool.connect(user).deposit(getContractAddress(usdc), flashloanTotal, userAddress, 0);

        const usdcPrice = await oracle.getAssetPrice(getContractAddress(usdc));
        const daiPrice = await oracle.getAssetPrice(getContractAddress(dai));

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

        await mockAugustus.expectSwap(getContractAddress(usdc), getContractAddress(dai), amountUSDCtoSwap, amountUSDCtoSwap, expectedDaiAmount);

        const smallExpectedDaiAmount = expectedDaiAmount / 2n;

        const aUsdcData = await pool.getReserveData(getContractAddress(usdc));
        const aUsdc = await getContract<AToken>(eContractid.AToken, aUsdcData.aTokenAddress);

        // User will swap liquidity aUsdc to aDai
        await aUsdc.connect(user).approve(getContractAddress(paraswapLiquiditySwapAdapter), flashloanTotal);

        const mockAugustusCalldata = mockAugustus.interface.encodeFunctionData(
          'swap',
          [getContractAddress(usdc), getContractAddress(dai), amountUSDCtoSwap, expectedDaiAmount]
        );

        const params = buildParaSwapLiquiditySwapParams(
          getContractAddress(dai),
          smallExpectedDaiAmount,
          0,
          mockAugustusCalldata,
          getContractAddress(mockAugustus),
          0,
          0,
          0,
          '0x0000000000000000000000000000000000000000000000000000000000000000',
          '0x0000000000000000000000000000000000000000000000000000000000000000'
        );

        await expect(
          pool
            .connect(user)
            .flashLoan(
              getContractAddress(paraswapLiquiditySwapAdapter),
              [getContractAddress(usdc)],
              [amountUSDCtoSwap],
              [0],
              userAddress,
              params,
              0
            )
        ).to.be.revertedWith('MIN_AMOUNT_EXCEEDS_MAX_SLIPPAGE');
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
          paraswapLiquiditySwapAdapter,
        } = testEnv;
        const user = users[0].signer;
        const userAddress = users[0].address;

        const amountWETHtoSwap = await convertToCurrencyDecimals(getContractAddress(weth), '10');

        const daiPrice = await oracle.getAssetPrice(getContractAddress(dai));
        const expectedDaiAmount = await convertToCurrencyDecimals(
          getContractAddress(dai),
          new BigNumber(amountWETHtoSwap.toString()).div(daiPrice.toString()).toFixed(0)
        );

        await mockAugustus.expectSwap(getContractAddress(weth), getContractAddress(dai), amountWETHtoSwap, amountWETHtoSwap, expectedDaiAmount);

        const bigAmountToSwap = parseEther('11');
        const flashloanPremium = bigAmountToSwap * 9n / 10000n;
        const flashloanTotal = (bigAmountToSwap + flashloanPremium);

        // Remove other balance
        await aWETH.connect(user).transfer(users[1].address, parseEther('90') - flashloanPremium);

        // User will swap liquidity aEth to aDai
        const userAEthBalanceBefore = await aWETH.balanceOf(userAddress);
        expect(userAEthBalanceBefore).to.be.eq((amountWETHtoSwap + flashloanPremium));

        await aWETH.connect(user).approve(getContractAddress(paraswapLiquiditySwapAdapter), flashloanTotal);

        const mockAugustusCalldata = mockAugustus.interface.encodeFunctionData(
          'swap',
          [getContractAddress(weth), getContractAddress(dai), bigAmountToSwap, expectedDaiAmount]
        );

        const params = buildParaSwapLiquiditySwapParams(
          getContractAddress(dai),
          expectedDaiAmount,
          4 + 2*32,
          mockAugustusCalldata,
          getContractAddress(mockAugustus),
          0,
          0,
          0,
          '0x0000000000000000000000000000000000000000000000000000000000000000',
          '0x0000000000000000000000000000000000000000000000000000000000000000'
        );

        await expect(
          pool
            .connect(user)
            .flashLoan(
              getContractAddress(paraswapLiquiditySwapAdapter),
              [getContractAddress(weth)],
              [bigAmountToSwap],
              [0],
              userAddress,
              params,
              0
            )
        )
          .to.emit(paraswapLiquiditySwapAdapter, 'Swapped')
          .withArgs(getContractAddress(weth), getContractAddress(dai), amountWETHtoSwap, expectedDaiAmount);

        const adapterWethBalance = await weth.balanceOf(getContractAddress(paraswapLiquiditySwapAdapter));
        const adapterDaiBalance = await dai.balanceOf(getContractAddress(paraswapLiquiditySwapAdapter));
        const userADaiBalance = await aDai.balanceOf(userAddress);
        const userAEthBalance = await aWETH.balanceOf(userAddress);

        expect(adapterWethBalance).to.be.eq(0n);
        expect(adapterDaiBalance).to.be.eq(0n);
        expect(userADaiBalance).to.be.eq(expectedDaiAmount);
        expect(userAEthBalance).to.be.eq(0n);
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
          paraswapLiquiditySwapAdapter,
        } = testEnv;
        const user = users[0].signer;
        const userAddress = users[0].address;

        const amountWETHtoSwap = await convertToCurrencyDecimals(getContractAddress(weth), '10');

        const daiPrice = await oracle.getAssetPrice(getContractAddress(dai));
        const expectedDaiAmount = await convertToCurrencyDecimals(
          getContractAddress(dai),
          new BigNumber(amountWETHtoSwap.toString()).div(daiPrice.toString()).toFixed(0)
        );

        await mockAugustus.expectSwap(getContractAddress(weth), getContractAddress(dai), amountWETHtoSwap, amountWETHtoSwap, expectedDaiAmount);

        const bigAmountToSwap = parseEther('11');
        const flashloanPremium = bigAmountToSwap * 9n / 10000n;
        const flashloanTotal = (bigAmountToSwap + flashloanPremium);

        // Remove other balance
        await aWETH.connect(user).transfer(users[1].address, parseEther('90') - flashloanPremium);

        // User will swap liquidity aEth to aDai
        const userAEthBalanceBefore = await aWETH.balanceOf(userAddress);
        expect(userAEthBalanceBefore).to.be.eq((amountWETHtoSwap + flashloanPremium));

        const chainId = Number((await DRE.ethers.provider.getNetwork()).chainId);
        const deadline = MAX_UINT_AMOUNT;
        const nonce = Number(await aWETH._nonces(userAddress));
        const msgParams = buildPermitParams(
          chainId,
          getContractAddress(aWETH),
          '1',
          await aWETH.name(),
          userAddress,
          getContractAddress(paraswapLiquiditySwapAdapter),
          nonce,
          deadline,
          flashloanTotal.toString()
        );

        const ownerPrivateKey = accounts[1].secretKey;
        if (!ownerPrivateKey) {
          throw new Error('INVALID_OWNER_PK');
        }

        const { v, r, s } = getSignatureFromTypedData(ownerPrivateKey, msgParams);

        const mockAugustusCalldata = mockAugustus.interface.encodeFunctionData(
          'swap',
          [getContractAddress(weth), getContractAddress(dai), bigAmountToSwap, expectedDaiAmount]
        );

        const params = buildParaSwapLiquiditySwapParams(
          getContractAddress(dai),
          expectedDaiAmount,
          4 + 2*32,
          mockAugustusCalldata,
          getContractAddress(mockAugustus),
          flashloanTotal,
          deadline,
          v,
          r,
          s
        );

        await expect(
          pool
            .connect(user)
            .flashLoan(
              getContractAddress(paraswapLiquiditySwapAdapter),
              [getContractAddress(weth)],
              [bigAmountToSwap],
              [0],
              userAddress,
              params,
              0
            )
        )
          .to.emit(paraswapLiquiditySwapAdapter, 'Swapped')
          .withArgs(getContractAddress(weth), getContractAddress(dai), amountWETHtoSwap, expectedDaiAmount);

        const adapterWethBalance = await weth.balanceOf(getContractAddress(paraswapLiquiditySwapAdapter));
        const adapterDaiBalance = await dai.balanceOf(getContractAddress(paraswapLiquiditySwapAdapter));
        const userADaiBalance = await aDai.balanceOf(userAddress);
        const userAEthBalance = await aWETH.balanceOf(userAddress);

        expect(adapterWethBalance).to.be.eq(0n);
        expect(adapterDaiBalance).to.be.eq(0n);
        expect(userADaiBalance).to.be.eq(expectedDaiAmount);
        expect(userAEthBalance).to.be.eq(0n);
      });

      it('should revert trying to swap all the balance with insufficient amount', async () => {
        const {
          users,
          weth,
          oracle,
          dai,
          aWETH,
          pool,
          paraswapLiquiditySwapAdapter,
        } = testEnv;
        const user = users[0].signer;
        const userAddress = users[0].address;

        const amountWETHtoSwap = await convertToCurrencyDecimals(getContractAddress(weth), '10');

        const daiPrice = await oracle.getAssetPrice(getContractAddress(dai));
        const expectedDaiAmount = await convertToCurrencyDecimals(
          getContractAddress(dai),
          new BigNumber(amountWETHtoSwap.toString()).div(daiPrice.toString()).toFixed(0)
        );

        await mockAugustus.expectSwap(getContractAddress(weth), getContractAddress(dai), amountWETHtoSwap, amountWETHtoSwap, expectedDaiAmount);

        const smallAmountToSwap = parseEther('9');
        const flashloanPremium = smallAmountToSwap * 9n / 10000n;
        const flashloanTotal = (smallAmountToSwap + flashloanPremium);

        // Remove other balance
        await aWETH.connect(user).transfer(users[1].address, parseEther('90') - flashloanPremium);

        // User will swap liquidity aEth to aDai
        const userAEthBalanceBefore = await aWETH.balanceOf(userAddress);
        expect(userAEthBalanceBefore).to.be.eq((amountWETHtoSwap + flashloanPremium));

        await aWETH.connect(user).approve(getContractAddress(paraswapLiquiditySwapAdapter), flashloanTotal);

        const mockAugustusCalldata = mockAugustus.interface.encodeFunctionData(
          'swap',
          [getContractAddress(weth), getContractAddress(dai), smallAmountToSwap, expectedDaiAmount]
        );

        const params = buildParaSwapLiquiditySwapParams(
          getContractAddress(dai),
          expectedDaiAmount,
          4 + 2*32,
          mockAugustusCalldata,
          getContractAddress(mockAugustus),
          0,
          0,
          0,
          '0x0000000000000000000000000000000000000000000000000000000000000000',
          '0x0000000000000000000000000000000000000000000000000000000000000000'
        );

        await expect(
          pool
            .connect(user)
            .flashLoan(
              getContractAddress(paraswapLiquiditySwapAdapter),
              [getContractAddress(weth)],
              [smallAmountToSwap],
              [0],
              userAddress,
              params,
              0
            )
        ).to.be.revertedWith('INSUFFICIENT_AMOUNT_TO_SWAP');
      });

      it('should revert trying to swap more than balance', async () => {
        const {
          users,
          weth,
          oracle,
          dai,
          aWETH,
          pool,
          paraswapLiquiditySwapAdapter,
        } = testEnv;
        const user = users[0].signer;
        const userAddress = users[0].address;

        const amountWETHtoSwap = await convertToCurrencyDecimals(getContractAddress(weth), '101');

        const daiPrice = await oracle.getAssetPrice(getContractAddress(dai));
        const expectedDaiAmount = await convertToCurrencyDecimals(
          getContractAddress(dai),
          new BigNumber(amountWETHtoSwap.toString()).div(daiPrice.toString()).toFixed(0)
        );

        await mockAugustus.expectSwap(getContractAddress(weth), getContractAddress(dai), amountWETHtoSwap, amountWETHtoSwap, expectedDaiAmount);

        const flashloanPremium = amountWETHtoSwap * 9n / 10000n;
        const flashloanTotal = (amountWETHtoSwap + flashloanPremium);

        // User will swap liquidity aEth to aDai
        await aWETH.connect(user).approve(getContractAddress(paraswapLiquiditySwapAdapter), flashloanTotal);

        const mockAugustusCalldata = mockAugustus.interface.encodeFunctionData(
          'swap',
          [getContractAddress(weth), getContractAddress(dai), amountWETHtoSwap, expectedDaiAmount]
        );

        const params = buildParaSwapLiquiditySwapParams(
          getContractAddress(dai),
          expectedDaiAmount,
          0,
          mockAugustusCalldata,
          getContractAddress(mockAugustus),
          0,
          0,
          0,
          '0x0000000000000000000000000000000000000000000000000000000000000000',
          '0x0000000000000000000000000000000000000000000000000000000000000000'
        );

        await expect(
          pool
            .connect(user)
            .flashLoan(
              getContractAddress(paraswapLiquiditySwapAdapter),
              [getContractAddress(weth)],
              [amountWETHtoSwap],
              [0],
              userAddress,
              params,
              0
            )
        ).to.be.revertedWith('INSUFFICIENT_ATOKEN_BALANCE');
      });

      it('should not touch any token balance already in the adapter', async () => {
        const {
          users,
          weth,
          oracle,
          dai,
          aDai,
          aWETH,
          pool,
          paraswapLiquiditySwapAdapter,
        } = testEnv;
        const user = users[0].signer;
        const userAddress = users[0].address;

        // Put token balances in the adapter
        const adapterWethBalanceBefore = parseEther('123');
        await weth.mint(adapterWethBalanceBefore);
        await weth.transfer(getContractAddress(paraswapLiquiditySwapAdapter), adapterWethBalanceBefore);
        const adapterDaiBalanceBefore = parseEther('234');
        await dai.mint(adapterDaiBalanceBefore);
        await dai.transfer(getContractAddress(paraswapLiquiditySwapAdapter), adapterDaiBalanceBefore);

        const amountWETHtoSwap = await convertToCurrencyDecimals(getContractAddress(weth), '10');

        const daiPrice = await oracle.getAssetPrice(getContractAddress(dai));
        const expectedDaiAmount = await convertToCurrencyDecimals(
          getContractAddress(dai),
          new BigNumber(amountWETHtoSwap.toString()).div(daiPrice.toString()).toFixed(0)
        );

        await mockAugustus.expectSwap(getContractAddress(weth), getContractAddress(dai), amountWETHtoSwap, amountWETHtoSwap, expectedDaiAmount);

        const flashloanPremium = amountWETHtoSwap * 9n / 10000n;
        const flashloanTotal = (amountWETHtoSwap + flashloanPremium);

        // User will swap liquidity aEth to aDai
        const userAEthBalanceBefore = await aWETH.balanceOf(userAddress);
        await aWETH.connect(user).approve(getContractAddress(paraswapLiquiditySwapAdapter), flashloanTotal);

        const mockAugustusCalldata = mockAugustus.interface.encodeFunctionData(
          'swap',
          [getContractAddress(weth), getContractAddress(dai), amountWETHtoSwap, expectedDaiAmount]
        );

        const params = buildParaSwapLiquiditySwapParams(
          getContractAddress(dai),
          expectedDaiAmount,
          0,
          mockAugustusCalldata,
          getContractAddress(mockAugustus),
          0,
          0,
          0,
          '0x0000000000000000000000000000000000000000000000000000000000000000',
          '0x0000000000000000000000000000000000000000000000000000000000000000'
        );

        await expect(
          pool
            .connect(user)
            .flashLoan(
              getContractAddress(paraswapLiquiditySwapAdapter),
              [getContractAddress(weth)],
              [amountWETHtoSwap],
              [0],
              userAddress,
              params,
              0
            )
        )
          .to.emit(paraswapLiquiditySwapAdapter, 'Swapped')
          .withArgs(getContractAddress(weth), getContractAddress(dai), amountWETHtoSwap, expectedDaiAmount);

        const adapterWethBalance = await weth.balanceOf(getContractAddress(paraswapLiquiditySwapAdapter));
        const adapterDaiBalance = await dai.balanceOf(getContractAddress(paraswapLiquiditySwapAdapter));
        const userADaiBalance = await aDai.balanceOf(userAddress);
        const userAEthBalance = await aWETH.balanceOf(userAddress);

        // N.B. will get some portion of flashloan premium back from the pool
        expect(adapterWethBalance).to.be.eq(adapterWethBalanceBefore);
        expect(adapterDaiBalance).to.be.eq(adapterDaiBalanceBefore);
        expect(userADaiBalance).to.be.eq(expectedDaiAmount);
        expect(userAEthBalance).to.be.gte((userAEthBalanceBefore - flashloanTotal));
        expect(userAEthBalance).to.be.lte((userAEthBalanceBefore - amountWETHtoSwap));
      });
    });

    describe('executeOperation with borrowing', () => {
      beforeEach(async () => {
        const { users, weth, dai, pool, deployer } = testEnv;
        const userAddress = users[0].address;
        const borrower = users[1].signer;
        const borrowerAddress = users[1].address;

        // Provide liquidity
        await dai.mint(parseEther('20000'));
        await dai.approve(getContractAddress(pool), parseEther('20000'));
        await pool.deposit(getContractAddress(dai), parseEther('20000'), deployer.address, 0);

        await weth.mint(parseEther('10000'));
        await weth.approve(getContractAddress(pool), parseEther('10000'));
        await pool.deposit(getContractAddress(weth), parseEther('10000'), deployer.address, 0);

        // Make a deposit for user
        await weth.mint(parseEther('100'));
        await weth.approve(getContractAddress(pool), parseEther('100'));
        await pool.deposit(getContractAddress(weth), parseEther('100'), userAddress, 0);

        // Add borrowing
        const collateralAmount = parseEther('10000000');
        await dai.mint(collateralAmount);
        await dai.approve(getContractAddress(pool), collateralAmount);
        await pool.deposit(getContractAddress(dai), collateralAmount, borrowerAddress, 0);
        await pool.connect(borrower).borrow(getContractAddress(weth), parseEther('5000'), 2, 0, borrowerAddress);
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
          paraswapLiquiditySwapAdapter,
        } = testEnv;
        const user = users[0].signer;
        const userAddress = users[0].address;

        const amountWETHtoSwap = await convertToCurrencyDecimals(getContractAddress(weth), '10');

        const daiPrice = await oracle.getAssetPrice(getContractAddress(dai));
        const expectedDaiAmount = await convertToCurrencyDecimals(
          getContractAddress(dai),
          new BigNumber(amountWETHtoSwap.toString()).div(daiPrice.toString()).toFixed(0)
        );

        await mockAugustus.expectSwap(getContractAddress(weth), getContractAddress(dai), amountWETHtoSwap, amountWETHtoSwap, expectedDaiAmount);

        const flashloanPremium = amountWETHtoSwap * 9n / 10000n;
        const flashloanTotal = (amountWETHtoSwap + flashloanPremium);

        // User will swap liquidity aEth to aDai
        const userAEthBalanceBefore = await aWETH.balanceOf(userAddress);
        await aWETH.connect(user).approve(getContractAddress(paraswapLiquiditySwapAdapter), flashloanTotal);

        const mockAugustusCalldata = mockAugustus.interface.encodeFunctionData(
          'swap',
          [getContractAddress(weth), getContractAddress(dai), amountWETHtoSwap, expectedDaiAmount]
        );

        const params = buildParaSwapLiquiditySwapParams(
          getContractAddress(dai),
          expectedDaiAmount,
          0,
          mockAugustusCalldata,
          getContractAddress(mockAugustus),
          0,
          0,
          0,
          '0x0000000000000000000000000000000000000000000000000000000000000000',
          '0x0000000000000000000000000000000000000000000000000000000000000000'
        );

        await expect(
          pool
            .connect(user)
            .flashLoan(
              getContractAddress(paraswapLiquiditySwapAdapter),
              [getContractAddress(weth)],
              [amountWETHtoSwap],
              [0],
              userAddress,
              params,
              0
            )
        )
          .to.emit(paraswapLiquiditySwapAdapter, 'Swapped')
          .withArgs(getContractAddress(weth), getContractAddress(dai), amountWETHtoSwap, expectedDaiAmount);

        const adapterWethBalance = await weth.balanceOf(getContractAddress(paraswapLiquiditySwapAdapter));
        const adapterDaiBalance = await dai.balanceOf(getContractAddress(paraswapLiquiditySwapAdapter));
        const userADaiBalance = await aDai.balanceOf(userAddress);
        const userAEthBalance = await aWETH.balanceOf(userAddress);

        // N.B. will get some portion of flashloan premium back from the pool
        expect(adapterWethBalance).to.be.eq(0n);
        expect(adapterDaiBalance).to.be.eq(0n);
        expect(userADaiBalance).to.be.eq(expectedDaiAmount);
        expect(userAEthBalance).to.be.gt((userAEthBalanceBefore - flashloanTotal));
        expect(userAEthBalance).to.be.lt(userAEthBalanceBefore * 10001n / (10000n - amountWETHtoSwap));
      });

      it('should correctly swap tokens using permit', async () => {
        const {
          users,
          weth,
          oracle,
          dai,
          aDai,
          aWETH,
          pool,
          paraswapLiquiditySwapAdapter,
        } = testEnv;
        const user = users[0].signer;
        const userAddress = users[0].address;

        const amountWETHtoSwap = await convertToCurrencyDecimals(getContractAddress(weth), '10');

        const daiPrice = await oracle.getAssetPrice(getContractAddress(dai));
        const expectedDaiAmount = await convertToCurrencyDecimals(
          getContractAddress(dai),
          new BigNumber(amountWETHtoSwap.toString()).div(daiPrice.toString()).toFixed(0)
        );

        await mockAugustus.expectSwap(getContractAddress(weth), getContractAddress(dai), amountWETHtoSwap, amountWETHtoSwap, expectedDaiAmount);

        const flashloanPremium = amountWETHtoSwap * 9n / 10000n;
        const flashloanTotal = (amountWETHtoSwap + flashloanPremium);

        // User will swap liquidity aEth to aDai
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
          getContractAddress(paraswapLiquiditySwapAdapter),
          nonce,
          deadline,
          flashloanTotal.toString()
        );

        const ownerPrivateKey = accounts[1].secretKey;
        if (!ownerPrivateKey) {
          throw new Error('INVALID_OWNER_PK');
        }

        const { v, r, s } = getSignatureFromTypedData(ownerPrivateKey, msgParams);

        const mockAugustusCalldata = mockAugustus.interface.encodeFunctionData(
          'swap',
          [getContractAddress(weth), getContractAddress(dai), amountWETHtoSwap, expectedDaiAmount]
        );

        const params = buildParaSwapLiquiditySwapParams(
          getContractAddress(dai),
          expectedDaiAmount,
          0,
          mockAugustusCalldata,
          getContractAddress(mockAugustus),
          flashloanTotal,
          deadline,
          v,
          r,
          s
        );

        await expect(
          pool
            .connect(user)
            .flashLoan(
              getContractAddress(paraswapLiquiditySwapAdapter),
              [getContractAddress(weth)],
              [amountWETHtoSwap],
              [0],
              userAddress,
              params,
              0
            )
        )
          .to.emit(paraswapLiquiditySwapAdapter, 'Swapped')
          .withArgs(getContractAddress(weth), getContractAddress(dai), amountWETHtoSwap, expectedDaiAmount);

        const adapterWethBalance = await weth.balanceOf(getContractAddress(paraswapLiquiditySwapAdapter));
        const adapterDaiBalance = await dai.balanceOf(getContractAddress(paraswapLiquiditySwapAdapter));
        const userADaiBalance = await aDai.balanceOf(userAddress);
        const userAEthBalance = await aWETH.balanceOf(userAddress);

        // N.B. will get some portion of flashloan premium back from the pool
        expect(adapterWethBalance).to.be.eq(0n);
        expect(adapterDaiBalance).to.be.eq(0n);
        expect(userADaiBalance).to.be.eq(expectedDaiAmount);
        expect(userAEthBalance).to.be.gt((userAEthBalanceBefore - flashloanTotal));
        expect(userAEthBalance).to.be.lt(userAEthBalanceBefore * 10001n / (10000n - amountWETHtoSwap));
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
          paraswapLiquiditySwapAdapter,
        } = testEnv;
        const user = users[0].signer;
        const userAddress = users[0].address;

        const amountWETHtoSwap = await convertToCurrencyDecimals(getContractAddress(weth), '10');

        const daiPrice = await oracle.getAssetPrice(getContractAddress(dai));
        const expectedDaiAmount = await convertToCurrencyDecimals(
          getContractAddress(dai),
          new BigNumber(amountWETHtoSwap.toString()).div(daiPrice.toString()).toFixed(0)
        );

        await mockAugustus.expectSwap(getContractAddress(weth), getContractAddress(dai), (amountWETHtoSwap + 1n), amountWETHtoSwap * 10001n / 10000n, expectedDaiAmount);

        const bigAmountToSwap = parseEther('11');
        const flashloanPremium = bigAmountToSwap * 9n / 10000n;
        const flashloanTotal = (bigAmountToSwap + flashloanPremium);

        // Remove other balance
        await aWETH.connect(user).transfer(users[1].address, parseEther('90') - flashloanPremium);

        // User will swap liquidity aEth to aDai
        await aWETH.connect(user).approve(getContractAddress(paraswapLiquiditySwapAdapter), flashloanTotal);

        const mockAugustusCalldata = mockAugustus.interface.encodeFunctionData(
          'swap',
          [getContractAddress(weth), getContractAddress(dai), bigAmountToSwap, expectedDaiAmount]
        );

        const params = buildParaSwapLiquiditySwapParams(
          getContractAddress(dai),
          expectedDaiAmount,
          4 + 2*32,
          mockAugustusCalldata,
          getContractAddress(mockAugustus),
          0,
          0,
          0,
          '0x0000000000000000000000000000000000000000000000000000000000000000',
          '0x0000000000000000000000000000000000000000000000000000000000000000'
        );

        await expect(
          pool
            .connect(user)
            .flashLoan(
              getContractAddress(paraswapLiquiditySwapAdapter),
              [getContractAddress(weth)],
              [bigAmountToSwap],
              [0],
              userAddress,
              params,
              0
            )
        ).to.emit(paraswapLiquiditySwapAdapter, 'Swapped');

        const adapterWethBalance = await weth.balanceOf(getContractAddress(paraswapLiquiditySwapAdapter));
        const adapterDaiBalance = await dai.balanceOf(getContractAddress(paraswapLiquiditySwapAdapter));
        const userADaiBalance = await aDai.balanceOf(userAddress);
        const userAEthBalance = await aWETH.balanceOf(userAddress);

        expect(adapterWethBalance).to.be.eq(0n);
        expect(adapterDaiBalance).to.be.eq(0n);
        expect(userADaiBalance).to.be.eq(expectedDaiAmount);
        expect(userAEthBalance).to.be.eq(0n);
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
          paraswapLiquiditySwapAdapter,
        } = testEnv;
        const user = users[0].signer;
        const userAddress = users[0].address;

        const amountWETHtoSwap = await convertToCurrencyDecimals(getContractAddress(weth), '10');

        const daiPrice = await oracle.getAssetPrice(getContractAddress(dai));
        const expectedDaiAmount = await convertToCurrencyDecimals(
          getContractAddress(dai),
          new BigNumber(amountWETHtoSwap.toString()).div(daiPrice.toString()).toFixed(0)
        );

        await mockAugustus.expectSwap(getContractAddress(weth), getContractAddress(dai), (amountWETHtoSwap + 1n), amountWETHtoSwap * 10001n / 10000n, expectedDaiAmount);

        const bigAmountToSwap = parseEther('11');
        const flashloanPremium = bigAmountToSwap * 9n / 10000n;
        const flashloanTotal = (bigAmountToSwap + flashloanPremium);

        // Remove other balance
        await aWETH.connect(user).transfer(users[1].address, parseEther('90') - flashloanPremium);

        // User will swap liquidity aEth to aDai
        const chainId = Number((await DRE.ethers.provider.getNetwork()).chainId);
        const deadline = MAX_UINT_AMOUNT;
        const nonce = Number(await aWETH._nonces(userAddress));
        const msgParams = buildPermitParams(
          chainId,
          getContractAddress(aWETH),
          '1',
          await aWETH.name(),
          userAddress,
          getContractAddress(paraswapLiquiditySwapAdapter),
          nonce,
          deadline,
          flashloanTotal.toString()
        );

        const ownerPrivateKey = accounts[1].secretKey;
        if (!ownerPrivateKey) {
          throw new Error('INVALID_OWNER_PK');
        }

        const { v, r, s } = getSignatureFromTypedData(ownerPrivateKey, msgParams);

        const mockAugustusCalldata = mockAugustus.interface.encodeFunctionData(
          'swap',
          [getContractAddress(weth), getContractAddress(dai), bigAmountToSwap, expectedDaiAmount]
        );

        const params = buildParaSwapLiquiditySwapParams(
          getContractAddress(dai),
          expectedDaiAmount,
          4 + 2*32,
          mockAugustusCalldata,
          getContractAddress(mockAugustus),
          flashloanTotal,
          deadline,
          v,
          r,
          s
        );

        await expect(
          pool
            .connect(user)
            .flashLoan(
              getContractAddress(paraswapLiquiditySwapAdapter),
              [getContractAddress(weth)],
              [bigAmountToSwap],
              [0],
              userAddress,
              params,
              0
            )
        ).to.emit(paraswapLiquiditySwapAdapter, 'Swapped');

        const adapterWethBalance = await weth.balanceOf(getContractAddress(paraswapLiquiditySwapAdapter));
        const adapterDaiBalance = await dai.balanceOf(getContractAddress(paraswapLiquiditySwapAdapter));
        const userADaiBalance = await aDai.balanceOf(userAddress);
        const userAEthBalance = await aWETH.balanceOf(userAddress);

        expect(adapterWethBalance).to.be.eq(0n);
        expect(adapterDaiBalance).to.be.eq(0n);
        expect(userADaiBalance).to.be.eq(expectedDaiAmount);
        expect(userAEthBalance).to.be.eq(0n);
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

        await weth.mint(parseEther('10000'));
        await weth.approve(getContractAddress(pool), parseEther('10000'));
        await pool.deposit(getContractAddress(weth), parseEther('10000'), deployer.address, 0);

        // Make a deposit for user
        await weth.mint(parseEther('100'));
        await weth.approve(getContractAddress(pool), parseEther('100'));
        await pool.deposit(getContractAddress(weth), parseEther('100'), userAddress, 0);
      });

      it('should correctly swap tokens and deposit the out tokens in the pool', async () => {
        const { users, weth, oracle, dai, aDai, aWETH, paraswapLiquiditySwapAdapter } = testEnv;
        const user = users[0].signer;
        const userAddress = users[0].address;

        const amountWETHtoSwap = await convertToCurrencyDecimals(getContractAddress(weth), '10');

        const daiPrice = await oracle.getAssetPrice(getContractAddress(dai));
        const expectedDaiAmount = await convertToCurrencyDecimals(
          getContractAddress(dai),
          new BigNumber(amountWETHtoSwap.toString()).div(daiPrice.toString()).toFixed(0)
        );

        await mockAugustus.expectSwap(getContractAddress(weth), getContractAddress(dai), amountWETHtoSwap, amountWETHtoSwap, expectedDaiAmount);

        // User will swap liquidity aEth to aDai
        const userAEthBalanceBefore = await aWETH.balanceOf(userAddress);
        await aWETH.connect(user).approve(getContractAddress(paraswapLiquiditySwapAdapter), amountWETHtoSwap);

        const mockAugustusCalldata = mockAugustus.interface.encodeFunctionData(
          'swap',
          [getContractAddress(weth), getContractAddress(dai), amountWETHtoSwap, expectedDaiAmount]
        );

        await expect(
          paraswapLiquiditySwapAdapter.connect(user).swapAndDeposit(
            getContractAddress(weth),
            getContractAddress(dai),
            amountWETHtoSwap,
            expectedDaiAmount,
            0,
            mockAugustusCalldata,
            getContractAddress(mockAugustus),
            {
              amount: 0,
              deadline: 0,
              v: 0,
              r: '0x0000000000000000000000000000000000000000000000000000000000000000',
              s: '0x0000000000000000000000000000000000000000000000000000000000000000',
            }
          )
        )
          .to.emit(paraswapLiquiditySwapAdapter, 'Swapped')
          .withArgs(getContractAddress(weth), getContractAddress(dai), amountWETHtoSwap, expectedDaiAmount);

        const adapterWethBalance = await weth.balanceOf(getContractAddress(paraswapLiquiditySwapAdapter));
        const adapterDaiBalance = await dai.balanceOf(getContractAddress(paraswapLiquiditySwapAdapter));
        const userADaiBalance = await aDai.balanceOf(userAddress);
        const userAEthBalance = await aWETH.balanceOf(userAddress);

        expect(adapterWethBalance).to.be.eq(0n);
        expect(adapterDaiBalance).to.be.eq(0n);
        expect(userADaiBalance).to.be.eq(expectedDaiAmount);
        expect(userAEthBalance).to.be.eq((userAEthBalanceBefore - amountWETHtoSwap));
      });

      it('should correctly swap tokens using permit', async () => {
        const { users, weth, oracle, dai, aDai, aWETH, paraswapLiquiditySwapAdapter } = testEnv;
        const user = users[0].signer;
        const userAddress = users[0].address;

        const amountWETHtoSwap = await convertToCurrencyDecimals(getContractAddress(weth), '10');

        const daiPrice = await oracle.getAssetPrice(getContractAddress(dai));
        const expectedDaiAmount = await convertToCurrencyDecimals(
          getContractAddress(dai),
          new BigNumber(amountWETHtoSwap.toString()).div(daiPrice.toString()).toFixed(0)
        );

        await mockAugustus.expectSwap(getContractAddress(weth), getContractAddress(dai), amountWETHtoSwap, amountWETHtoSwap, expectedDaiAmount);

        // User will swap liquidity aEth to aDai
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
          getContractAddress(paraswapLiquiditySwapAdapter),
          nonce,
          deadline,
          amountWETHtoSwap.toString()
        );

        const ownerPrivateKey = accounts[1].secretKey;
        if (!ownerPrivateKey) {
          throw new Error('INVALID_OWNER_PK');
        }

        const { v, r, s } = getSignatureFromTypedData(ownerPrivateKey, msgParams);

        const mockAugustusCalldata = mockAugustus.interface.encodeFunctionData(
          'swap',
          [getContractAddress(weth), getContractAddress(dai), amountWETHtoSwap, expectedDaiAmount]
        );

        await expect(
          paraswapLiquiditySwapAdapter.connect(user).swapAndDeposit(
            getContractAddress(weth),
            getContractAddress(dai),
            amountWETHtoSwap,
            expectedDaiAmount,
            0,
            mockAugustusCalldata,
            getContractAddress(mockAugustus),
            {
              amount: amountWETHtoSwap,
              deadline,
              v,
              r,
              s,
            }
          )
        )
          .to.emit(paraswapLiquiditySwapAdapter, 'Swapped')
          .withArgs(getContractAddress(weth), getContractAddress(dai), amountWETHtoSwap, expectedDaiAmount);

        const adapterWethBalance = await weth.balanceOf(getContractAddress(paraswapLiquiditySwapAdapter));
        const adapterDaiBalance = await dai.balanceOf(getContractAddress(paraswapLiquiditySwapAdapter));
        const userADaiBalance = await aDai.balanceOf(userAddress);
        const userAEthBalance = await aWETH.balanceOf(userAddress);

        expect(adapterWethBalance).to.be.eq(0n);
        expect(adapterDaiBalance).to.be.eq(0n);
        expect(userADaiBalance).to.be.eq(expectedDaiAmount);
        expect(userAEthBalance).to.be.eq((userAEthBalanceBefore - amountWETHtoSwap));
      });

      it('should revert when trying to swap more than balance', async () => {
        const { users, weth, oracle, dai, aWETH, paraswapLiquiditySwapAdapter } = testEnv;
        const user = users[0].signer;
        const userAddress = users[0].address;

        const amountWETHtoSwap = (await convertToCurrencyDecimals(getContractAddress(weth), '100')) + 1n;

        const daiPrice = await oracle.getAssetPrice(getContractAddress(dai));
        const expectedDaiAmount = await convertToCurrencyDecimals(
          getContractAddress(dai),
          new BigNumber(amountWETHtoSwap.toString()).div(daiPrice.toString()).toFixed(0)
        );

        await mockAugustus.expectSwap(getContractAddress(weth), getContractAddress(dai), amountWETHtoSwap, amountWETHtoSwap, expectedDaiAmount);

        // User will swap liquidity aEth to aDai
        await aWETH.connect(user).approve(getContractAddress(paraswapLiquiditySwapAdapter), amountWETHtoSwap);

        const mockAugustusCalldata = mockAugustus.interface.encodeFunctionData(
          'swap',
          [getContractAddress(weth), getContractAddress(dai), amountWETHtoSwap, expectedDaiAmount]
        );

        await expect(
          paraswapLiquiditySwapAdapter.connect(user).swapAndDeposit(
            getContractAddress(weth),
            getContractAddress(dai),
            amountWETHtoSwap,
            expectedDaiAmount,
            0,
            mockAugustusCalldata,
            getContractAddress(mockAugustus),
            {
              amount: 0,
              deadline: 0,
              v: 0,
              r: '0x0000000000000000000000000000000000000000000000000000000000000000',
              s: '0x0000000000000000000000000000000000000000000000000000000000000000',
            }
          )
        ).to.be.revertedWith('SafeERC20: low-level call failed');
      });

      it('should revert when trying to swap more than allowance', async () => {
        const { users, weth, oracle, dai, aWETH, paraswapLiquiditySwapAdapter } = testEnv;
        const user = users[0].signer;
        const userAddress = users[0].address;

        const amountWETHtoSwap = await convertToCurrencyDecimals(getContractAddress(weth), '10');

        const daiPrice = await oracle.getAssetPrice(getContractAddress(dai));
        const expectedDaiAmount = await convertToCurrencyDecimals(
          getContractAddress(dai),
          new BigNumber(amountWETHtoSwap.toString()).div(daiPrice.toString()).toFixed(0)
        );

        await mockAugustus.expectSwap(getContractAddress(weth), getContractAddress(dai), amountWETHtoSwap, amountWETHtoSwap, expectedDaiAmount);

        // User will swap liquidity aEth to aDai
        await aWETH.connect(user).approve(getContractAddress(paraswapLiquiditySwapAdapter), (amountWETHtoSwap - 1n));

        const mockAugustusCalldata = mockAugustus.interface.encodeFunctionData(
          'swap',
          [getContractAddress(weth), getContractAddress(dai), amountWETHtoSwap, expectedDaiAmount]
        );

        await expect(
          paraswapLiquiditySwapAdapter.connect(user).swapAndDeposit(
            getContractAddress(weth),
            getContractAddress(dai),
            amountWETHtoSwap,
            expectedDaiAmount,
            0,
            mockAugustusCalldata,
            getContractAddress(mockAugustus),
            {
              amount: 0,
              deadline: 0,
              v: 0,
              r: '0x0000000000000000000000000000000000000000000000000000000000000000',
              s: '0x0000000000000000000000000000000000000000000000000000000000000000',
            }
          )
        ).to.be.revertedWith('SafeERC20: low-level call failed');
      });

      it('should revert when min amount to receive exceeds the max slippage amount', async () => {
        const { users, weth, oracle, dai, aWETH, paraswapLiquiditySwapAdapter } = testEnv;
        const user = users[0].signer;

        const amountWETHtoSwap = await convertToCurrencyDecimals(getContractAddress(weth), '10');

        const daiPrice = await oracle.getAssetPrice(getContractAddress(dai));
        const expectedDaiAmount = await convertToCurrencyDecimals(
          getContractAddress(dai),
          new BigNumber(amountWETHtoSwap.toString()).div(daiPrice.toString()).toFixed(0)
        );

        await mockAugustus.expectSwap(getContractAddress(weth), getContractAddress(dai), amountWETHtoSwap, amountWETHtoSwap, expectedDaiAmount);

        const smallExpectedDaiAmount = expectedDaiAmount / 2n;

        // User will swap liquidity aEth to aDai
        await aWETH.connect(user).approve(getContractAddress(paraswapLiquiditySwapAdapter), amountWETHtoSwap);

        const mockAugustusCalldata = mockAugustus.interface.encodeFunctionData(
          'swap',
          [getContractAddress(weth), getContractAddress(dai), amountWETHtoSwap, expectedDaiAmount]
        );

        await expect(
          paraswapLiquiditySwapAdapter.connect(user).swapAndDeposit(
            getContractAddress(weth),
            getContractAddress(dai),
            amountWETHtoSwap,
            smallExpectedDaiAmount,
            0,
            mockAugustusCalldata,
            getContractAddress(mockAugustus),
            {
              amount: 0,
              deadline: 0,
              v: 0,
              r: '0x0000000000000000000000000000000000000000000000000000000000000000',
              s: '0x0000000000000000000000000000000000000000000000000000000000000000',
            }
          )
        ).to.be.revertedWith('MIN_AMOUNT_EXCEEDS_MAX_SLIPPAGE');
      });

      it('should revert if wrong address used for Augustus', async () => {
        const { users, weth, oracle, dai, aWETH, paraswapLiquiditySwapAdapter } = testEnv;
        const user = users[0].signer;
        const userAddress = users[0].address;

        const amountWETHtoSwap = await convertToCurrencyDecimals(getContractAddress(weth), '10');

        const daiPrice = await oracle.getAssetPrice(getContractAddress(dai));
        const expectedDaiAmount = await convertToCurrencyDecimals(
          getContractAddress(dai),
          new BigNumber(amountWETHtoSwap.toString()).div(daiPrice.toString()).toFixed(0)
        );

        await mockAugustus.expectSwap(getContractAddress(weth), getContractAddress(dai), amountWETHtoSwap, amountWETHtoSwap, expectedDaiAmount);

        // User will swap liquidity aEth to aDai
        await aWETH.connect(user).approve(getContractAddress(paraswapLiquiditySwapAdapter), amountWETHtoSwap);

        const mockAugustusCalldata = mockAugustus.interface.encodeFunctionData(
          'swap',
          [getContractAddress(weth), getContractAddress(dai), amountWETHtoSwap, expectedDaiAmount]
        );

        await expect(
          paraswapLiquiditySwapAdapter.connect(user).swapAndDeposit(
            getContractAddress(weth),
            getContractAddress(dai),
            amountWETHtoSwap,
            expectedDaiAmount,
            0,
            mockAugustusCalldata,
            getContractAddress(oracle), // using arbitrary contract instead of mock Augustus
            {
              amount: 0,
              deadline: 0,
              v: 0,
              r: '0x0000000000000000000000000000000000000000000000000000000000000000',
              s: '0x0000000000000000000000000000000000000000000000000000000000000000',
            }
          )
        ).to.be.revertedWith('INVALID_AUGUSTUS');
      });

      it('should bubble up errors from Augustus', async () => {
        const { users, weth, oracle, dai, aWETH, paraswapLiquiditySwapAdapter } = testEnv;
        const user = users[0].signer;

        const amountWETHtoSwap = await convertToCurrencyDecimals(getContractAddress(weth), '10');

        const daiPrice = await oracle.getAssetPrice(getContractAddress(dai));
        const expectedDaiAmount = await convertToCurrencyDecimals(
          getContractAddress(dai),
          new BigNumber(amountWETHtoSwap.toString()).div(daiPrice.toString()).toFixed(0)
        );

        await mockAugustus.expectSwap(getContractAddress(weth), getContractAddress(dai), amountWETHtoSwap, amountWETHtoSwap, expectedDaiAmount);

        // User will swap liquidity aEth to aDai
        await aWETH.connect(user).approve(getContractAddress(paraswapLiquiditySwapAdapter), amountWETHtoSwap);

        // Add 1 to expected amount so it will fail
        const mockAugustusCalldata = mockAugustus.interface.encodeFunctionData(
          'swap',
          [getContractAddress(weth), getContractAddress(dai), amountWETHtoSwap, (expectedDaiAmount + 1n)]
        );

        await expect(
          paraswapLiquiditySwapAdapter.connect(user).swapAndDeposit(
            getContractAddress(weth),
            getContractAddress(dai),
            amountWETHtoSwap,
            expectedDaiAmount,
            0,
            mockAugustusCalldata,
            getContractAddress(mockAugustus),
            {
              amount: 0,
              deadline: 0,
              v: 0,
              r: '0x0000000000000000000000000000000000000000000000000000000000000000',
              s: '0x0000000000000000000000000000000000000000000000000000000000000000',
            }
          )
        ).to.be.revertedWith('Received amount of tokens are less than expected');
      });

      it('should revert if Augustus swaps for less than minimum to receive', async () => {
        const { users, weth, oracle, dai, aWETH, paraswapLiquiditySwapAdapter } = testEnv;
        const user = users[0].signer;
        const userAddress = users[0].address;

        const amountWETHtoSwap = await convertToCurrencyDecimals(getContractAddress(weth), '10');

        const daiPrice = await oracle.getAssetPrice(getContractAddress(dai));
        const expectedDaiAmount = await convertToCurrencyDecimals(
          getContractAddress(dai),
          new BigNumber(amountWETHtoSwap.toString()).div(daiPrice.toString()).toFixed(0)
        );
        const actualDaiAmount = (expectedDaiAmount - 1n);

        await mockAugustus.expectSwap(getContractAddress(weth), getContractAddress(dai), amountWETHtoSwap, amountWETHtoSwap, actualDaiAmount);

        // User will swap liquidity aEth to aDai
        await aWETH.connect(user).approve(getContractAddress(paraswapLiquiditySwapAdapter), amountWETHtoSwap);

        const mockAugustusCalldata = mockAugustus.interface.encodeFunctionData(
          'swap',
          [getContractAddress(weth), getContractAddress(dai), amountWETHtoSwap, actualDaiAmount]
        );

        await expect(
          paraswapLiquiditySwapAdapter.connect(user).swapAndDeposit(
            getContractAddress(weth),
            getContractAddress(dai),
            amountWETHtoSwap,
            expectedDaiAmount,
            0,
            mockAugustusCalldata,
            getContractAddress(mockAugustus),
            {
              amount: 0,
              deadline: 0,
              v: 0,
              r: '0x0000000000000000000000000000000000000000000000000000000000000000',
              s: '0x0000000000000000000000000000000000000000000000000000000000000000',
            }
          )
        ).to.be.revertedWith('INSUFFICIENT_AMOUNT_RECEIVED');
      });

      it("should revert if Augustus doesn't swap correct amount", async () => {
        const { users, weth, oracle, dai, aWETH, paraswapLiquiditySwapAdapter } = testEnv;
        const user = users[0].signer;
        const userAddress = users[0].address;

        const amountWETHtoSwap = await convertToCurrencyDecimals(getContractAddress(weth), '10');

        const daiPrice = await oracle.getAssetPrice(getContractAddress(dai));
        const expectedDaiAmount = await convertToCurrencyDecimals(
          getContractAddress(dai),
          new BigNumber(amountWETHtoSwap.toString()).div(daiPrice.toString()).toFixed(0)
        );

        const augustusSwapAmount = (amountWETHtoSwap - 1n);

        await mockAugustus.expectSwap(getContractAddress(weth), getContractAddress(dai), augustusSwapAmount, augustusSwapAmount, expectedDaiAmount);

        // User will swap liquidity aEth to aDai
        await aWETH.connect(user).approve(getContractAddress(paraswapLiquiditySwapAdapter), amountWETHtoSwap);

        const mockAugustusCalldata = mockAugustus.interface.encodeFunctionData(
          'swap',
          [getContractAddress(weth), getContractAddress(dai), augustusSwapAmount, expectedDaiAmount]
        );

        await expect(
          paraswapLiquiditySwapAdapter.connect(user).swapAndDeposit(
            getContractAddress(weth),
            getContractAddress(dai),
            amountWETHtoSwap,
            expectedDaiAmount,
            0,
            mockAugustusCalldata,
            getContractAddress(mockAugustus),
            {
              amount: 0,
              deadline: 0,
              v: 0,
              r: '0x0000000000000000000000000000000000000000000000000000000000000000',
              s: '0x0000000000000000000000000000000000000000000000000000000000000000',
            }
          )
        ).to.be.revertedWith('WRONG_BALANCE_AFTER_SWAP');
      });

      it('should correctly swap all the balance when using a bigger amount', async () => {
        const { users, weth, oracle, dai, aDai, aWETH, paraswapLiquiditySwapAdapter } = testEnv;
        const user = users[0].signer;
        const userAddress = users[0].address;

        const amountWETHtoSwap = await convertToCurrencyDecimals(getContractAddress(weth), '10');

        const daiPrice = await oracle.getAssetPrice(getContractAddress(dai));
        const expectedDaiAmount = await convertToCurrencyDecimals(
          getContractAddress(dai),
          new BigNumber(amountWETHtoSwap.toString()).div(daiPrice.toString()).toFixed(0)
        );

        await mockAugustus.expectSwap(getContractAddress(weth), getContractAddress(dai), amountWETHtoSwap, amountWETHtoSwap, expectedDaiAmount);

        // Remove other balance
        await aWETH.connect(user).transfer(users[1].address, parseEther('90'));

        // User will swap liquidity aEth to aDai
        const userAEthBalanceBefore = await aWETH.balanceOf(userAddress);
        expect(userAEthBalanceBefore).to.be.eq(amountWETHtoSwap);

        const bigAmountToSwap = parseEther('11');
        await aWETH.connect(user).approve(getContractAddress(paraswapLiquiditySwapAdapter), bigAmountToSwap);

        const mockAugustusCalldata = mockAugustus.interface.encodeFunctionData(
          'swap',
          [getContractAddress(weth), getContractAddress(dai), bigAmountToSwap, expectedDaiAmount]
        );

        await expect(
          paraswapLiquiditySwapAdapter.connect(user).swapAndDeposit(
            getContractAddress(weth),
            getContractAddress(dai),
            bigAmountToSwap,
            expectedDaiAmount,
            4 + 2*32,
            mockAugustusCalldata,
            getContractAddress(mockAugustus),
            {
              amount: 0,
              deadline: 0,
              v: 0,
              r: '0x0000000000000000000000000000000000000000000000000000000000000000',
              s: '0x0000000000000000000000000000000000000000000000000000000000000000',
            }
          )
        )
          .to.emit(paraswapLiquiditySwapAdapter, 'Swapped')
          .withArgs(getContractAddress(weth), getContractAddress(dai), amountWETHtoSwap, expectedDaiAmount);

        const adapterWethBalance = await weth.balanceOf(getContractAddress(paraswapLiquiditySwapAdapter));
        const adapterDaiBalance = await dai.balanceOf(getContractAddress(paraswapLiquiditySwapAdapter));
        const userADaiBalance = await aDai.balanceOf(userAddress);
        const userAEthBalance = await aWETH.balanceOf(userAddress);

        expect(adapterWethBalance).to.be.eq(0n);
        expect(adapterDaiBalance).to.be.eq(0n);
        expect(userADaiBalance).to.be.eq(expectedDaiAmount);
        expect(userAEthBalance).to.be.eq(0n);
      });

      it('should correctly swap all the balance when using permit', async () => {
        const { users, weth, oracle, dai, aDai, aWETH, paraswapLiquiditySwapAdapter } = testEnv;
        const user = users[0].signer;
        const userAddress = users[0].address;

        const amountWETHtoSwap = await convertToCurrencyDecimals(getContractAddress(weth), '10');

        const daiPrice = await oracle.getAssetPrice(getContractAddress(dai));
        const expectedDaiAmount = await convertToCurrencyDecimals(
          getContractAddress(dai),
          new BigNumber(amountWETHtoSwap.toString()).div(daiPrice.toString()).toFixed(0)
        );

        await mockAugustus.expectSwap(getContractAddress(weth), getContractAddress(dai), amountWETHtoSwap, amountWETHtoSwap, expectedDaiAmount);

        // Remove other balance
        await aWETH.connect(user).transfer(users[1].address, parseEther('90'));

        // User will swap liquidity aEth to aDai
        const userAEthBalanceBefore = await aWETH.balanceOf(userAddress);
        expect(userAEthBalanceBefore).to.be.eq(amountWETHtoSwap);

        const bigAmountToSwap = parseEther('11');

        const chainId = Number((await DRE.ethers.provider.getNetwork()).chainId);
        const deadline = MAX_UINT_AMOUNT;
        const nonce = Number(await aWETH._nonces(userAddress));
        const msgParams = buildPermitParams(
          chainId,
          getContractAddress(aWETH),
          '1',
          await aWETH.name(),
          userAddress,
          getContractAddress(paraswapLiquiditySwapAdapter),
          nonce,
          deadline,
          bigAmountToSwap.toString()
        );

        const ownerPrivateKey = accounts[1].secretKey;
        if (!ownerPrivateKey) {
          throw new Error('INVALID_OWNER_PK');
        }

        const { v, r, s } = getSignatureFromTypedData(ownerPrivateKey, msgParams);

        const mockAugustusCalldata = mockAugustus.interface.encodeFunctionData(
          'swap',
          [getContractAddress(weth), getContractAddress(dai), bigAmountToSwap, expectedDaiAmount]
        );

        await expect(
          paraswapLiquiditySwapAdapter.connect(user).swapAndDeposit(
            getContractAddress(weth),
            getContractAddress(dai),
            bigAmountToSwap,
            expectedDaiAmount,
            4 + 2*32,
            mockAugustusCalldata,
            getContractAddress(mockAugustus),
            {
              amount: bigAmountToSwap,
              deadline,
              v,
              r,
              s,
            }
          )
        )
          .to.emit(paraswapLiquiditySwapAdapter, 'Swapped')
          .withArgs(getContractAddress(weth), getContractAddress(dai), amountWETHtoSwap, expectedDaiAmount);

        const adapterWethBalance = await weth.balanceOf(getContractAddress(paraswapLiquiditySwapAdapter));
        const adapterDaiBalance = await dai.balanceOf(getContractAddress(paraswapLiquiditySwapAdapter));
        const userADaiBalance = await aDai.balanceOf(userAddress);
        const userAEthBalance = await aWETH.balanceOf(userAddress);

        expect(adapterWethBalance).to.be.eq(0n);
        expect(adapterDaiBalance).to.be.eq(0n);
        expect(userADaiBalance).to.be.eq(expectedDaiAmount);
        expect(userAEthBalance).to.be.eq(0n);
      });

      it('should revert trying to swap all the balance when using a smaller amount', async () => {
        const { users, weth, oracle, dai, aWETH, paraswapLiquiditySwapAdapter } = testEnv;
        const user = users[0].signer;
        const userAddress = users[0].address;

        const amountWETHtoSwap = await convertToCurrencyDecimals(getContractAddress(weth), '10');

        const daiPrice = await oracle.getAssetPrice(getContractAddress(dai));
        const expectedDaiAmount = await convertToCurrencyDecimals(
          getContractAddress(dai),
          new BigNumber(amountWETHtoSwap.toString()).div(daiPrice.toString()).toFixed(0)
        );

        await mockAugustus.expectSwap(getContractAddress(weth), getContractAddress(dai), amountWETHtoSwap, amountWETHtoSwap, expectedDaiAmount);

        // Remove other balance
        await aWETH.connect(user).transfer(users[1].address, parseEther('90'));

        // User will swap liquidity aEth to aDai
        const userAEthBalanceBefore = await aWETH.balanceOf(userAddress);
        expect(userAEthBalanceBefore).to.be.eq(amountWETHtoSwap);

        const smallAmountToSwap = parseEther('10') - 1n;
        await aWETH.connect(user).approve(getContractAddress(paraswapLiquiditySwapAdapter), smallAmountToSwap);

        const mockAugustusCalldata = mockAugustus.interface.encodeFunctionData(
          'swap',
          [getContractAddress(weth), getContractAddress(dai), smallAmountToSwap, expectedDaiAmount]
        );

        await expect(
          paraswapLiquiditySwapAdapter.connect(user).swapAndDeposit(
            getContractAddress(weth),
            getContractAddress(dai),
            smallAmountToSwap,
            expectedDaiAmount,
            4 + 2*32,
            mockAugustusCalldata,
            getContractAddress(mockAugustus),
            {
              amount: 0,
              deadline: 0,
              v: 0,
              r: '0x0000000000000000000000000000000000000000000000000000000000000000',
              s: '0x0000000000000000000000000000000000000000000000000000000000000000',
            }
          )
        ).to.be.revertedWith('INSUFFICIENT_AMOUNT_TO_SWAP');
      });

      it('should not touch any token balance already in the adapter', async () => {
        const { users, weth, oracle, dai, aDai, aWETH, paraswapLiquiditySwapAdapter } = testEnv;
        const user = users[0].signer;
        const userAddress = users[0].address;

        // Put token balances in the adapter
        const adapterWethBalanceBefore = parseEther('123');
        await weth.mint(adapterWethBalanceBefore);
        await weth.transfer(getContractAddress(paraswapLiquiditySwapAdapter), adapterWethBalanceBefore);
        const adapterDaiBalanceBefore = parseEther('234');
        await dai.mint(adapterDaiBalanceBefore);
        await dai.transfer(getContractAddress(paraswapLiquiditySwapAdapter), adapterDaiBalanceBefore);

        const amountWETHtoSwap = await convertToCurrencyDecimals(getContractAddress(weth), '10');

        const daiPrice = await oracle.getAssetPrice(getContractAddress(dai));
        const expectedDaiAmount = await convertToCurrencyDecimals(
          getContractAddress(dai),
          new BigNumber(amountWETHtoSwap.toString()).div(daiPrice.toString()).toFixed(0)
        );

        await mockAugustus.expectSwap(getContractAddress(weth), getContractAddress(dai), amountWETHtoSwap, amountWETHtoSwap, expectedDaiAmount);

        // User will swap liquidity aEth to aDai
        const userAEthBalanceBefore = await aWETH.balanceOf(userAddress);
        await aWETH.connect(user).approve(getContractAddress(paraswapLiquiditySwapAdapter), amountWETHtoSwap);

        const mockAugustusCalldata = mockAugustus.interface.encodeFunctionData(
          'swap',
          [getContractAddress(weth), getContractAddress(dai), amountWETHtoSwap, expectedDaiAmount]
        );

        await expect(
          paraswapLiquiditySwapAdapter.connect(user).swapAndDeposit(
            getContractAddress(weth),
            getContractAddress(dai),
            amountWETHtoSwap,
            expectedDaiAmount,
            0,
            mockAugustusCalldata,
            getContractAddress(mockAugustus),
            {
              amount: 0,
              deadline: 0,
              v: 0,
              r: '0x0000000000000000000000000000000000000000000000000000000000000000',
              s: '0x0000000000000000000000000000000000000000000000000000000000000000',
            }
          )
        )
          .to.emit(paraswapLiquiditySwapAdapter, 'Swapped')
          .withArgs(getContractAddress(weth), getContractAddress(dai), amountWETHtoSwap, expectedDaiAmount);

        const adapterWethBalance = await weth.balanceOf(getContractAddress(paraswapLiquiditySwapAdapter));
        const adapterDaiBalance = await dai.balanceOf(getContractAddress(paraswapLiquiditySwapAdapter));
        const userADaiBalance = await aDai.balanceOf(userAddress);
        const userAEthBalance = await aWETH.balanceOf(userAddress);

        expect(adapterWethBalance).to.be.eq(adapterWethBalanceBefore);
        expect(adapterDaiBalance).to.be.eq(adapterDaiBalanceBefore);
        expect(userADaiBalance).to.be.eq(expectedDaiAmount);
        expect(userAEthBalance).to.be.eq((userAEthBalanceBefore - amountWETHtoSwap));
      });
    });

    describe('swapAndDeposit with borrowing', () => {
      beforeEach(async () => {
        const { users, weth, dai, pool, deployer } = testEnv;
        const userAddress = users[0].address;
        const borrower = users[1].signer;
        const borrowerAddress = users[1].address;

        // Provide liquidity
        await dai.mint(parseEther('20000'));
        await dai.approve(getContractAddress(pool), parseEther('20000'));
        await pool.deposit(getContractAddress(dai), parseEther('20000'), deployer.address, 0);

        await weth.mint(parseEther('10000'));
        await weth.approve(getContractAddress(pool), parseEther('10000'));
        await pool.deposit(getContractAddress(weth), parseEther('10000'), deployer.address, 0);

        // Make a deposit for user
        await weth.mint(parseEther('100'));
        await weth.approve(getContractAddress(pool), parseEther('100'));
        await pool.deposit(getContractAddress(weth), parseEther('100'), userAddress, 0);

        // Add borrowing
        const collateralAmount = parseEther('10000000');
        await dai.mint(collateralAmount);
        await dai.approve(getContractAddress(pool), collateralAmount);
        await pool.deposit(getContractAddress(dai), collateralAmount, borrowerAddress, 0);
        await pool.connect(borrower).borrow(getContractAddress(weth), parseEther('5000'), 2, 0, borrowerAddress);
      });

      it('should correctly swap tokens and deposit the out tokens in the pool', async () => {
        const { users, weth, oracle, dai, aDai, aWETH, paraswapLiquiditySwapAdapter } = testEnv;
        const user = users[0].signer;
        const userAddress = users[0].address;

        const amountWETHtoSwap = await convertToCurrencyDecimals(getContractAddress(weth), '10');

        const daiPrice = await oracle.getAssetPrice(getContractAddress(dai));
        const expectedDaiAmount = await convertToCurrencyDecimals(
          getContractAddress(dai),
          new BigNumber(amountWETHtoSwap.toString()).div(daiPrice.toString()).toFixed(0)
        );

        await mockAugustus.expectSwap(getContractAddress(weth), getContractAddress(dai), amountWETHtoSwap, amountWETHtoSwap, expectedDaiAmount);

        // User will swap liquidity aEth to aDai
        const userAEthBalanceBefore = await aWETH.balanceOf(userAddress);
        await aWETH.connect(user).approve(getContractAddress(paraswapLiquiditySwapAdapter), amountWETHtoSwap);

        const mockAugustusCalldata = mockAugustus.interface.encodeFunctionData(
          'swap',
          [getContractAddress(weth), getContractAddress(dai), amountWETHtoSwap, expectedDaiAmount]
        );

        await expect(
          paraswapLiquiditySwapAdapter.connect(user).swapAndDeposit(
            getContractAddress(weth),
            getContractAddress(dai),
            amountWETHtoSwap,
            expectedDaiAmount,
            0,
            mockAugustusCalldata,
            getContractAddress(mockAugustus),
            {
              amount: 0,
              deadline: 0,
              v: 0,
              r: '0x0000000000000000000000000000000000000000000000000000000000000000',
              s: '0x0000000000000000000000000000000000000000000000000000000000000000',
            }
          )
        )
          .to.emit(paraswapLiquiditySwapAdapter, 'Swapped')
          .withArgs(getContractAddress(weth), getContractAddress(dai), amountWETHtoSwap, expectedDaiAmount);

        const adapterWethBalance = await weth.balanceOf(getContractAddress(paraswapLiquiditySwapAdapter));
        const adapterDaiBalance = await dai.balanceOf(getContractAddress(paraswapLiquiditySwapAdapter));
        const userADaiBalance = await aDai.balanceOf(userAddress);
        const userAEthBalance = await aWETH.balanceOf(userAddress);

        expect(adapterWethBalance).to.be.eq(0n);
        expect(adapterDaiBalance).to.be.eq(0n);
        expect(userADaiBalance).to.be.eq(expectedDaiAmount);
        expect(userAEthBalance).to.be.gt((userAEthBalanceBefore - amountWETHtoSwap));
        expect(userAEthBalance).to.be.lt(userAEthBalanceBefore * 10001n / (10000n - amountWETHtoSwap));
      });

      it('should correctly swap tokens using permit', async () => {
        const { users, weth, oracle, dai, aDai, aWETH, paraswapLiquiditySwapAdapter } = testEnv;
        const user = users[0].signer;
        const userAddress = users[0].address;

        const amountWETHtoSwap = await convertToCurrencyDecimals(getContractAddress(weth), '10');

        const daiPrice = await oracle.getAssetPrice(getContractAddress(dai));
        const expectedDaiAmount = await convertToCurrencyDecimals(
          getContractAddress(dai),
          new BigNumber(amountWETHtoSwap.toString()).div(daiPrice.toString()).toFixed(0)
        );

        await mockAugustus.expectSwap(getContractAddress(weth), getContractAddress(dai), amountWETHtoSwap, amountWETHtoSwap, expectedDaiAmount);

        // User will swap liquidity aEth to aDai
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
          getContractAddress(paraswapLiquiditySwapAdapter),
          nonce,
          deadline,
          amountWETHtoSwap.toString()
        );

        const ownerPrivateKey = accounts[1].secretKey;
        if (!ownerPrivateKey) {
          throw new Error('INVALID_OWNER_PK');
        }

        const { v, r, s } = getSignatureFromTypedData(ownerPrivateKey, msgParams);

        const mockAugustusCalldata = mockAugustus.interface.encodeFunctionData(
          'swap',
          [getContractAddress(weth), getContractAddress(dai), amountWETHtoSwap, expectedDaiAmount]
        );

        await expect(
          paraswapLiquiditySwapAdapter.connect(user).swapAndDeposit(
            getContractAddress(weth),
            getContractAddress(dai),
            amountWETHtoSwap,
            expectedDaiAmount,
            0,
            mockAugustusCalldata,
            getContractAddress(mockAugustus),
            {
              amount: amountWETHtoSwap,
              deadline,
              v,
              r,
              s,
            }
          )
        )
          .to.emit(paraswapLiquiditySwapAdapter, 'Swapped')
          .withArgs(getContractAddress(weth), getContractAddress(dai), amountWETHtoSwap, expectedDaiAmount);

        const adapterWethBalance = await weth.balanceOf(getContractAddress(paraswapLiquiditySwapAdapter));
        const adapterDaiBalance = await dai.balanceOf(getContractAddress(paraswapLiquiditySwapAdapter));
        const userADaiBalance = await aDai.balanceOf(userAddress);
        const userAEthBalance = await aWETH.balanceOf(userAddress);

        expect(adapterWethBalance).to.be.eq(0n);
        expect(adapterDaiBalance).to.be.eq(0n);
        expect(userADaiBalance).to.be.eq(expectedDaiAmount);
        expect(userAEthBalance).to.be.gt((userAEthBalanceBefore - amountWETHtoSwap));
        expect(userAEthBalance).to.be.lt(userAEthBalanceBefore * 10001n / (10000n - amountWETHtoSwap));
      });

      it('should correctly swap all the balance when using a bigger amount', async () => {
        const { users, weth, oracle, dai, aDai, aWETH, paraswapLiquiditySwapAdapter } = testEnv;
        const user = users[0].signer;
        const userAddress = users[0].address;

        const amountWETHtoSwap = await convertToCurrencyDecimals(getContractAddress(weth), '10');

        const daiPrice = await oracle.getAssetPrice(getContractAddress(dai));
        const expectedDaiAmount = await convertToCurrencyDecimals(
          getContractAddress(dai),
          new BigNumber(amountWETHtoSwap.toString()).div(daiPrice.toString()).toFixed(0)
        );

        await mockAugustus.expectSwap(getContractAddress(weth), getContractAddress(dai), (amountWETHtoSwap + 1n), amountWETHtoSwap * 10001n / 10000n, expectedDaiAmount);

        // Remove other balance
        await aWETH.connect(user).transfer(users[1].address, parseEther('90'));

        // User will swap liquidity aEth to aDai
        const bigAmountToSwap = parseEther('11');
        await aWETH.connect(user).approve(getContractAddress(paraswapLiquiditySwapAdapter), bigAmountToSwap);

        const mockAugustusCalldata = mockAugustus.interface.encodeFunctionData(
          'swap',
          [getContractAddress(weth), getContractAddress(dai), bigAmountToSwap, expectedDaiAmount]
        );

        await expect(
          paraswapLiquiditySwapAdapter.connect(user).swapAndDeposit(
            getContractAddress(weth),
            getContractAddress(dai),
            bigAmountToSwap,
            expectedDaiAmount,
            4 + 2*32,
            mockAugustusCalldata,
            getContractAddress(mockAugustus),
            {
              amount: 0,
              deadline: 0,
              v: 0,
              r: '0x0000000000000000000000000000000000000000000000000000000000000000',
              s: '0x0000000000000000000000000000000000000000000000000000000000000000',
            }
          )
        ).to.emit(paraswapLiquiditySwapAdapter, 'Swapped');

        const adapterWethBalance = await weth.balanceOf(getContractAddress(paraswapLiquiditySwapAdapter));
        const adapterDaiBalance = await dai.balanceOf(getContractAddress(paraswapLiquiditySwapAdapter));
        const userADaiBalance = await aDai.balanceOf(userAddress);
        const userAEthBalance = await aWETH.balanceOf(userAddress);

        expect(adapterWethBalance).to.be.eq(0n);
        expect(adapterDaiBalance).to.be.eq(0n);
        expect(userADaiBalance).to.be.eq(expectedDaiAmount);
        expect(userAEthBalance).to.be.eq(0n);
      });

      it('should correctly swap all the balance when using permit', async () => {
        const { users, weth, oracle, dai, aDai, aWETH, paraswapLiquiditySwapAdapter } = testEnv;
        const user = users[0].signer;
        const userAddress = users[0].address;

        const amountWETHtoSwap = await convertToCurrencyDecimals(getContractAddress(weth), '10');

        const daiPrice = await oracle.getAssetPrice(getContractAddress(dai));
        const expectedDaiAmount = await convertToCurrencyDecimals(
          getContractAddress(dai),
          new BigNumber(amountWETHtoSwap.toString()).div(daiPrice.toString()).toFixed(0)
        );

        await mockAugustus.expectSwap(getContractAddress(weth), getContractAddress(dai), (amountWETHtoSwap + 1n), amountWETHtoSwap * 10001n / 10000n, expectedDaiAmount);

        // Remove other balance
        await aWETH.connect(user).transfer(users[1].address, parseEther('90'));

        // User will swap liquidity aEth to aDai
        const bigAmountToSwap = parseEther('11');

        const chainId = Number((await DRE.ethers.provider.getNetwork()).chainId);
        const deadline = MAX_UINT_AMOUNT;
        const nonce = Number(await aWETH._nonces(userAddress));
        const msgParams = buildPermitParams(
          chainId,
          getContractAddress(aWETH),
          '1',
          await aWETH.name(),
          userAddress,
          getContractAddress(paraswapLiquiditySwapAdapter),
          nonce,
          deadline,
          bigAmountToSwap.toString()
        );

        const ownerPrivateKey = accounts[1].secretKey;
        if (!ownerPrivateKey) {
          throw new Error('INVALID_OWNER_PK');
        }

        const { v, r, s } = getSignatureFromTypedData(ownerPrivateKey, msgParams);

        const mockAugustusCalldata = mockAugustus.interface.encodeFunctionData(
          'swap',
          [getContractAddress(weth), getContractAddress(dai), bigAmountToSwap, expectedDaiAmount]
        );

        await expect(
          paraswapLiquiditySwapAdapter.connect(user).swapAndDeposit(
            getContractAddress(weth),
            getContractAddress(dai),
            bigAmountToSwap,
            expectedDaiAmount,
            4 + 2*32,
            mockAugustusCalldata,
            getContractAddress(mockAugustus),
            {
              amount: bigAmountToSwap,
              deadline,
              v,
              r,
              s,
            }
          )
        ).to.emit(paraswapLiquiditySwapAdapter, 'Swapped');

        const adapterWethBalance = await weth.balanceOf(getContractAddress(paraswapLiquiditySwapAdapter));
        const adapterDaiBalance = await dai.balanceOf(getContractAddress(paraswapLiquiditySwapAdapter));
        const userADaiBalance = await aDai.balanceOf(userAddress);
        const userAEthBalance = await aWETH.balanceOf(userAddress);

        expect(adapterWethBalance).to.be.eq(0n);
        expect(adapterDaiBalance).to.be.eq(0n);
        expect(userADaiBalance).to.be.eq(expectedDaiAmount);
        expect(userAEthBalance).to.be.eq(0n);
      });
    });
  });
});
