import { makeSuite } from './helpers/make-suite.js';
import type { TestEnv } from './helpers/make-suite.js';
import {
  convertToCurrencyDecimals,
  getContract,
  buildPermitParams,
  getSignatureFromTypedData,
  buildRepayAdapterParams,
  getContractAddress
} from '../../helpers/contracts-helpers.js';
import { getMockUniswapRouter } from '../../helpers/contracts-getters.js';
import { deployUniswapRepayAdapter } from '../../helpers/contracts-deployments.js';
import type { MockUniswapV2Router02 } from '../../types/ethers-contracts/index.js';
import BigNumber from "bignumber.js";

import { DRE, evmRevert, evmSnapshot } from '../../helpers/misc-utils.js';
import { ethers, parseEther } from 'ethers';
import { eContractid } from '../../helpers/types.js';
import type { StableDebtToken } from '../../types/ethers-contracts/index.js';
import { BUIDLEREVM_CHAINID } from '../../helpers/buidler-constants.js';
import { MAX_UINT_AMOUNT } from '../../helpers/constants.js';
import type { VariableDebtToken } from '../../types/ethers-contracts/index.js';

import chai from 'chai';
import { accounts } from '../../test-wallets.js';
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

  describe('UniswapRepayAdapter', () => {
    beforeEach(async () => {
      const { users, weth, dai, usdc, aave, pool, deployer } = testEnv;
      const userAddress = users[0].address;

      // Provide liquidity
      await dai.mint(parseEther('20000'));
      await dai.approve(getContractAddress(pool), parseEther('20000'));
      await pool.deposit(getContractAddress(dai), parseEther('20000'), deployer.address, 0);

      const usdcLiquidity = await convertToCurrencyDecimals(getContractAddress(usdc), '2000000');
      await usdc.mint(usdcLiquidity);
      await usdc.approve(getContractAddress(pool), usdcLiquidity);
      await pool.deposit(getContractAddress(usdc), usdcLiquidity, deployer.address, 0);

      await weth.mint(parseEther('100'));
      await weth.approve(getContractAddress(pool), parseEther('100'));
      await pool.deposit(getContractAddress(weth), parseEther('100'), deployer.address, 0);

      await aave.mint(parseEther('1000000'));
      await aave.approve(getContractAddress(pool), parseEther('1000000'));
      await pool.deposit(getContractAddress(aave), parseEther('1000000'), deployer.address, 0);

      // Make a deposit for user
      await weth.mint(parseEther('1000'));
      await weth.approve(getContractAddress(pool), parseEther('1000'));
      await pool.deposit(getContractAddress(weth), parseEther('1000'), userAddress, 0);

      await aave.mint(parseEther('1000000'));
      await aave.approve(getContractAddress(pool), parseEther('1000000'));
      await pool.deposit(getContractAddress(aave), parseEther('1000000'), userAddress, 0);

      await usdc.mint(usdcLiquidity);
      await usdc.approve(getContractAddress(pool), usdcLiquidity);
      await pool.deposit(getContractAddress(usdc), usdcLiquidity, userAddress, 0);
    });

    describe('constructor', () => {
      it('should deploy with correct parameters', async () => {
        const { addressesProvider, weth } = testEnv;
        await deployUniswapRepayAdapter([
          getContractAddress(addressesProvider),
          getContractAddress(mockUniswapRouter),
          getContractAddress(weth),
        ]);
      });

      it('should revert if not valid addresses provider', async () => {
        const { weth } = testEnv;
        await expect(
          deployUniswapRepayAdapter([
            getContractAddress(mockUniswapRouter),
            getContractAddress(mockUniswapRouter),
            getContractAddress(weth),
          ])
        ).to.be.revert(DRE.ethers);
      });
    });

    describe('executeOperation', () => {
      it('should correctly swap tokens and repay debt', async () => {
        const {
          users,
          pool,
          weth,
          aWETH,
          oracle,
          dai,
          uniswapRepayAdapter,
          helpersContract,
        } = testEnv;
        const user = users[0].signer;
        const userAddress = users[0].address;

        const amountWETHtoSwap = await convertToCurrencyDecimals(getContractAddress(weth), '10');

        const daiPrice = await oracle.getAssetPrice(getContractAddress(dai));
        const expectedDaiAmount = await convertToCurrencyDecimals(
          getContractAddress(dai),
          new BigNumber(amountWETHtoSwap.toString()).div(daiPrice.toString()).toFixed(0)
        );

        // Open user Debt
        await pool.connect(user).borrow(getContractAddress(dai), expectedDaiAmount, 1, 0, userAddress);

        const daiStableDebtTokenAddress = (
          await helpersContract.getReserveTokensAddresses(getContractAddress(dai))
        ).stableDebtTokenAddress;

        const daiStableDebtContract = await getContract<StableDebtToken>(
          eContractid.StableDebtToken,
          daiStableDebtTokenAddress
        );

        const userDaiStableDebtAmountBefore = await daiStableDebtContract.balanceOf(userAddress);

        const liquidityToSwap = amountWETHtoSwap;
        await aWETH.connect(user).approve(getContractAddress(uniswapRepayAdapter), liquidityToSwap);
        const userAEthBalanceBefore = await aWETH.balanceOf(userAddress);

        await mockUniswapRouter.connect(user).setAmountToSwap(getContractAddress(weth), liquidityToSwap);

        const flashLoanDebt = new BigNumber(expectedDaiAmount.toString())
          .multipliedBy(1.0009)
          .toFixed(0);

        await mockUniswapRouter.setAmountIn(
          flashLoanDebt,
          getContractAddress(weth),
          getContractAddress(dai),
          liquidityToSwap
        );

        const params = buildRepayAdapterParams(
          getContractAddress(weth),
          liquidityToSwap,
          1,
          0,
          0,
          0,
          '0x0000000000000000000000000000000000000000000000000000000000000000',
          '0x0000000000000000000000000000000000000000000000000000000000000000',
          false
        );

        await expect(
          pool
            .connect(user)
            .flashLoan(
              getContractAddress(uniswapRepayAdapter),
              [getContractAddress(dai)],
              [expectedDaiAmount.toString()],
              [0],
              userAddress,
              params,
              0
            )
        )
          .to.emit(uniswapRepayAdapter, 'Swapped')
          .withArgs(getContractAddress(weth), getContractAddress(dai), liquidityToSwap.toString(), flashLoanDebt);

        const adapterWethBalance = await weth.balanceOf(getContractAddress(uniswapRepayAdapter));
        const adapterDaiBalance = await dai.balanceOf(getContractAddress(uniswapRepayAdapter));
        const userDaiStableDebtAmount = await daiStableDebtContract.balanceOf(userAddress);
        const userAEthBalance = await aWETH.balanceOf(userAddress);

        expect(adapterWethBalance).to.be.eq(0n);
        expect(adapterDaiBalance).to.be.eq(0n);
        expect(userDaiStableDebtAmountBefore).to.be.gte(expectedDaiAmount);
        expect(userDaiStableDebtAmount).to.be.lt(expectedDaiAmount);
        expect(userAEthBalance).to.be.lt(userAEthBalanceBefore);
        expect(userAEthBalance).to.be.gte((userAEthBalanceBefore - BigInt(liquidityToSwap)));
      });

      it('should correctly swap tokens and repay debt with permit', async () => {
        const {
          users,
          pool,
          weth,
          aWETH,
          oracle,
          dai,
          uniswapRepayAdapter,
          helpersContract,
        } = testEnv;
        const user = users[0].signer;
        const userAddress = users[0].address;

        const amountWETHtoSwap = await convertToCurrencyDecimals(getContractAddress(weth), '10');

        const daiPrice = await oracle.getAssetPrice(getContractAddress(dai));
        const expectedDaiAmount = await convertToCurrencyDecimals(
          getContractAddress(dai),
          new BigNumber(amountWETHtoSwap.toString()).div(daiPrice.toString()).toFixed(0)
        );

        // Open user Debt
        await pool.connect(user).borrow(getContractAddress(dai), expectedDaiAmount, 1, 0, userAddress);

        const daiStableDebtTokenAddress = (
          await helpersContract.getReserveTokensAddresses(getContractAddress(dai))
        ).stableDebtTokenAddress;

        const daiStableDebtContract = await getContract<StableDebtToken>(
          eContractid.StableDebtToken,
          daiStableDebtTokenAddress
        );

        const userDaiStableDebtAmountBefore = await daiStableDebtContract.balanceOf(userAddress);

        const liquidityToSwap = amountWETHtoSwap;
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
          getContractAddress(uniswapRepayAdapter),
          nonce,
          deadline,
          liquidityToSwap.toString()
        );

        const ownerPrivateKey = accounts[1].secretKey;
        if (!ownerPrivateKey) {
          throw new Error('INVALID_OWNER_PK');
        }

        const { v, r, s } = getSignatureFromTypedData(ownerPrivateKey, msgParams);

        await mockUniswapRouter.connect(user).setAmountToSwap(getContractAddress(weth), liquidityToSwap);

        const flashLoanDebt = new BigNumber(expectedDaiAmount.toString())
          .multipliedBy(1.0009)
          .toFixed(0);

        await mockUniswapRouter.setAmountIn(
          flashLoanDebt,
          getContractAddress(weth),
          getContractAddress(dai),
          liquidityToSwap
        );

        const params = buildRepayAdapterParams(
          getContractAddress(weth),
          liquidityToSwap,
          1,
          liquidityToSwap,
          deadline,
          v,
          r,
          s,
          false
        );

        await expect(
          pool
            .connect(user)
            .flashLoan(
              getContractAddress(uniswapRepayAdapter),
              [getContractAddress(dai)],
              [expectedDaiAmount.toString()],
              [0],
              userAddress,
              params,
              0
            )
        )
          .to.emit(uniswapRepayAdapter, 'Swapped')
          .withArgs(getContractAddress(weth), getContractAddress(dai), liquidityToSwap.toString(), flashLoanDebt);

        const adapterWethBalance = await weth.balanceOf(getContractAddress(uniswapRepayAdapter));
        const adapterDaiBalance = await dai.balanceOf(getContractAddress(uniswapRepayAdapter));
        const userDaiStableDebtAmount = await daiStableDebtContract.balanceOf(userAddress);
        const userAEthBalance = await aWETH.balanceOf(userAddress);

        expect(adapterWethBalance).to.be.eq(0n);
        expect(adapterDaiBalance).to.be.eq(0n);
        expect(userDaiStableDebtAmountBefore).to.be.gte(expectedDaiAmount);
        expect(userDaiStableDebtAmount).to.be.lt(expectedDaiAmount);
        expect(userAEthBalance).to.be.lt(userAEthBalanceBefore);
        expect(userAEthBalance).to.be.gte((userAEthBalanceBefore - BigInt(liquidityToSwap)));
      });

      it('should revert if caller not lending pool', async () => {
        const { users, pool, weth, aWETH, oracle, dai, uniswapRepayAdapter } = testEnv;
        const user = users[0].signer;
        const userAddress = users[0].address;

        const amountWETHtoSwap = await convertToCurrencyDecimals(getContractAddress(weth), '10');

        const daiPrice = await oracle.getAssetPrice(getContractAddress(dai));
        const expectedDaiAmount = await convertToCurrencyDecimals(
          getContractAddress(dai),
          new BigNumber(amountWETHtoSwap.toString()).div(daiPrice.toString()).toFixed(0)
        );

        // Open user Debt
        await pool.connect(user).borrow(getContractAddress(dai), expectedDaiAmount, 1, 0, userAddress);

        const liquidityToSwap = amountWETHtoSwap;
        await aWETH.connect(user).approve(getContractAddress(uniswapRepayAdapter), liquidityToSwap);

        await mockUniswapRouter.connect(user).setAmountToSwap(getContractAddress(weth), liquidityToSwap);

        const params = buildRepayAdapterParams(
          getContractAddress(weth),
          liquidityToSwap,
          1,
          0,
          0,
          0,
          '0x0000000000000000000000000000000000000000000000000000000000000000',
          '0x0000000000000000000000000000000000000000000000000000000000000000',
          false
        );

        await expect(
          uniswapRepayAdapter
            .connect(user)
            .executeOperation(
              [getContractAddress(dai)],
              [expectedDaiAmount.toString()],
              [0],
              userAddress,
              params
            )
        ).to.be.revertedWith('CALLER_MUST_BE_LENDING_POOL');
      });

      it('should revert if there is not debt to repay with the specified rate mode', async () => {
        const { users, pool, weth, oracle, dai, uniswapRepayAdapter, aWETH } = testEnv;
        const user = users[0].signer;
        const userAddress = users[0].address;

        const amountWETHtoSwap = await convertToCurrencyDecimals(getContractAddress(weth), '10');

        await weth.connect(user).mint(amountWETHtoSwap);
        await weth.connect(user).transfer(getContractAddress(uniswapRepayAdapter), amountWETHtoSwap);

        const daiPrice = await oracle.getAssetPrice(getContractAddress(dai));
        const expectedDaiAmount = await convertToCurrencyDecimals(
          getContractAddress(dai),
          new BigNumber(amountWETHtoSwap.toString()).div(daiPrice.toString()).toFixed(0)
        );

        // Open user Debt
        await pool.connect(user).borrow(getContractAddress(dai), expectedDaiAmount, 2, 0, userAddress);

        const liquidityToSwap = amountWETHtoSwap;
        await aWETH.connect(user).approve(getContractAddress(uniswapRepayAdapter), liquidityToSwap);

        await mockUniswapRouter.connect(user).setAmountToSwap(getContractAddress(weth), liquidityToSwap);

        const params = buildRepayAdapterParams(
          getContractAddress(weth),
          liquidityToSwap,
          1,
          0,
          0,
          0,
          '0x0000000000000000000000000000000000000000000000000000000000000000',
          '0x0000000000000000000000000000000000000000000000000000000000000000',
          false
        );

        await expect(
          pool
            .connect(user)
            .flashLoan(
              getContractAddress(uniswapRepayAdapter),
              [getContractAddress(dai)],
              [expectedDaiAmount.toString()],
              [0],
              userAddress,
              params,
              0
            )
        ).to.be.revert(DRE.ethers);
      });

      it('should revert if there is not debt to repay', async () => {
        const { users, pool, weth, oracle, dai, uniswapRepayAdapter, aWETH } = testEnv;
        const user = users[0].signer;
        const userAddress = users[0].address;

        const amountWETHtoSwap = await convertToCurrencyDecimals(getContractAddress(weth), '10');

        await weth.connect(user).mint(amountWETHtoSwap);
        await weth.connect(user).transfer(getContractAddress(uniswapRepayAdapter), amountWETHtoSwap);

        const daiPrice = await oracle.getAssetPrice(getContractAddress(dai));
        const expectedDaiAmount = await convertToCurrencyDecimals(
          getContractAddress(dai),
          new BigNumber(amountWETHtoSwap.toString()).div(daiPrice.toString()).toFixed(0)
        );

        const liquidityToSwap = amountWETHtoSwap;
        await aWETH.connect(user).approve(getContractAddress(uniswapRepayAdapter), liquidityToSwap);

        await mockUniswapRouter.connect(user).setAmountToSwap(getContractAddress(weth), liquidityToSwap);

        const params = buildRepayAdapterParams(
          getContractAddress(weth),
          liquidityToSwap,
          1,
          0,
          0,
          0,
          '0x0000000000000000000000000000000000000000000000000000000000000000',
          '0x0000000000000000000000000000000000000000000000000000000000000000',
          false
        );

        await expect(
          pool
            .connect(user)
            .flashLoan(
              getContractAddress(uniswapRepayAdapter),
              [getContractAddress(dai)],
              [expectedDaiAmount.toString()],
              [0],
              userAddress,
              params,
              0
            )
        ).to.be.revert(DRE.ethers);
      });

      it('should revert when max amount allowed to swap is bigger than max slippage', async () => {
        const { users, pool, weth, oracle, dai, aWETH, uniswapRepayAdapter } = testEnv;
        const user = users[0].signer;
        const userAddress = users[0].address;

        const amountWETHtoSwap = await convertToCurrencyDecimals(getContractAddress(weth), '10');

        const daiPrice = await oracle.getAssetPrice(getContractAddress(dai));
        const expectedDaiAmount = await convertToCurrencyDecimals(
          getContractAddress(dai),
          new BigNumber(amountWETHtoSwap.toString()).div(daiPrice.toString()).toFixed(0)
        );

        // Open user Debt
        await pool.connect(user).borrow(getContractAddress(dai), expectedDaiAmount, 1, 0, userAddress);

        const bigMaxAmountToSwap = amountWETHtoSwap * 2n;
        await aWETH.connect(user).approve(getContractAddress(uniswapRepayAdapter), bigMaxAmountToSwap);

        await mockUniswapRouter.connect(user).setAmountToSwap(getContractAddress(weth), bigMaxAmountToSwap);

        const flashLoanDebt = new BigNumber(expectedDaiAmount.toString())
          .multipliedBy(1.0009)
          .toFixed(0);

        await mockUniswapRouter.setAmountIn(
          flashLoanDebt,
          getContractAddress(weth),
          getContractAddress(dai),
          bigMaxAmountToSwap
        );

        const params = buildRepayAdapterParams(
          getContractAddress(weth),
          bigMaxAmountToSwap,
          1,
          0,
          0,
          0,
          '0x0000000000000000000000000000000000000000000000000000000000000000',
          '0x0000000000000000000000000000000000000000000000000000000000000000',
          false
        );

        await expect(
          pool
            .connect(user)
            .flashLoan(
              getContractAddress(uniswapRepayAdapter),
              [getContractAddress(dai)],
              [expectedDaiAmount.toString()],
              [0],
              userAddress,
              params,
              0
            )
        ).to.be.revertedWith('maxAmountToSwap exceed max slippage');
      });

      it('should swap, repay debt and pull the needed ATokens leaving no leftovers', async () => {
        const {
          users,
          pool,
          weth,
          aWETH,
          oracle,
          dai,
          uniswapRepayAdapter,
          helpersContract,
        } = testEnv;
        const user = users[0].signer;
        const userAddress = users[0].address;

        const amountWETHtoSwap = await convertToCurrencyDecimals(getContractAddress(weth), '10');

        const daiPrice = await oracle.getAssetPrice(getContractAddress(dai));
        const expectedDaiAmount = await convertToCurrencyDecimals(
          getContractAddress(dai),
          new BigNumber(amountWETHtoSwap.toString()).div(daiPrice.toString()).toFixed(0)
        );

        // Open user Debt
        await pool.connect(user).borrow(getContractAddress(dai), expectedDaiAmount, 1, 0, userAddress);

        const daiStableDebtTokenAddress = (
          await helpersContract.getReserveTokensAddresses(getContractAddress(dai))
        ).stableDebtTokenAddress;

        const daiStableDebtContract = await getContract<StableDebtToken>(
          eContractid.StableDebtToken,
          daiStableDebtTokenAddress
        );

        const userDaiStableDebtAmountBefore = await daiStableDebtContract.balanceOf(userAddress);

        const liquidityToSwap = amountWETHtoSwap;
        await aWETH.connect(user).approve(getContractAddress(uniswapRepayAdapter), liquidityToSwap);
        const userAEthBalanceBefore = await aWETH.balanceOf(userAddress);
        const userWethBalanceBefore = await weth.balanceOf(userAddress);

        const actualWEthSwapped = new BigNumber(liquidityToSwap.toString())
          .multipliedBy(0.995)
          .toFixed(0);

        await mockUniswapRouter.connect(user).setAmountToSwap(getContractAddress(weth), actualWEthSwapped);

        const flashLoanDebt = new BigNumber(expectedDaiAmount.toString())
          .multipliedBy(1.0009)
          .toFixed(0);

        await mockUniswapRouter.setAmountIn(
          flashLoanDebt,
          getContractAddress(weth),
          getContractAddress(dai),
          actualWEthSwapped
        );

        const params = buildRepayAdapterParams(
          getContractAddress(weth),
          liquidityToSwap,
          1,
          0,
          0,
          0,
          '0x0000000000000000000000000000000000000000000000000000000000000000',
          '0x0000000000000000000000000000000000000000000000000000000000000000',
          false
        );

        await expect(
          pool
            .connect(user)
            .flashLoan(
              getContractAddress(uniswapRepayAdapter),
              [getContractAddress(dai)],
              [expectedDaiAmount.toString()],
              [0],
              userAddress,
              params,
              0
            )
        )
          .to.emit(uniswapRepayAdapter, 'Swapped')
          .withArgs(getContractAddress(weth), getContractAddress(dai), actualWEthSwapped.toString(), flashLoanDebt);

        const adapterWethBalance = await weth.balanceOf(getContractAddress(uniswapRepayAdapter));
        const adapterDaiBalance = await dai.balanceOf(getContractAddress(uniswapRepayAdapter));
        const userDaiStableDebtAmount = await daiStableDebtContract.balanceOf(userAddress);
        const userAEthBalance = await aWETH.balanceOf(userAddress);
        const adapterAEthBalance = await aWETH.balanceOf(getContractAddress(uniswapRepayAdapter));
        const userWethBalance = await weth.balanceOf(userAddress);

        expect(adapterAEthBalance).to.be.eq(0n);
        expect(adapterWethBalance).to.be.eq(0n);
        expect(adapterDaiBalance).to.be.eq(0n);
        expect(userDaiStableDebtAmountBefore).to.be.gte(expectedDaiAmount);
        expect(userDaiStableDebtAmount).to.be.lt(expectedDaiAmount);
        expect(userAEthBalance).to.be.lt(userAEthBalanceBefore);
        expect(userAEthBalance).to.be.eq((userAEthBalanceBefore - BigInt(actualWEthSwapped)));
        expect(userWethBalance).to.be.eq(userWethBalanceBefore);
      });

      it('should correctly swap tokens and repay the whole stable debt', async () => {
        const {
          users,
          pool,
          weth,
          aWETH,
          oracle,
          dai,
          uniswapRepayAdapter,
          helpersContract,
        } = testEnv;
        const user = users[0].signer;
        const userAddress = users[0].address;

        const amountWETHtoSwap = await convertToCurrencyDecimals(getContractAddress(weth), '10');

        const daiPrice = await oracle.getAssetPrice(getContractAddress(dai));
        const expectedDaiAmount = await convertToCurrencyDecimals(
          getContractAddress(dai),
          new BigNumber(amountWETHtoSwap.toString()).div(daiPrice.toString()).toFixed(0)
        );

        // Open user Debt
        await pool.connect(user).borrow(getContractAddress(dai), expectedDaiAmount, 1, 0, userAddress);

        const daiStableDebtTokenAddress = (
          await helpersContract.getReserveTokensAddresses(getContractAddress(dai))
        ).stableDebtTokenAddress;

        const daiStableDebtContract = await getContract<StableDebtToken>(
          eContractid.StableDebtToken,
          daiStableDebtTokenAddress
        );

        const userDaiStableDebtAmountBefore = await daiStableDebtContract.balanceOf(userAddress);

        // Add a % to repay on top of the debt
        const liquidityToSwap = new BigNumber(amountWETHtoSwap.toString())
          .multipliedBy(1.1)
          .toFixed(0);

        await aWETH.connect(user).approve(getContractAddress(uniswapRepayAdapter), liquidityToSwap);
        const userAEthBalanceBefore = await aWETH.balanceOf(userAddress);

        // Add a % to repay on top of the debt
        const amountToRepay = new BigNumber(expectedDaiAmount.toString())
          .multipliedBy(1.1)
          .toFixed(0);

        await mockUniswapRouter.connect(user).setAmountToSwap(getContractAddress(weth), amountWETHtoSwap);
        await mockUniswapRouter.setDefaultMockValue(amountWETHtoSwap);

        const params = buildRepayAdapterParams(
          getContractAddress(weth),
          liquidityToSwap,
          1,
          0,
          0,
          0,
          '0x0000000000000000000000000000000000000000000000000000000000000000',
          '0x0000000000000000000000000000000000000000000000000000000000000000',
          false
        );

        await pool
          .connect(user)
          .flashLoan(
            getContractAddress(uniswapRepayAdapter),
            [getContractAddress(dai)],
            [amountToRepay.toString()],
            [0],
            userAddress,
            params,
            0
          );

        const adapterWethBalance = await weth.balanceOf(getContractAddress(uniswapRepayAdapter));
        const adapterDaiBalance = await dai.balanceOf(getContractAddress(uniswapRepayAdapter));
        const userDaiStableDebtAmount = await daiStableDebtContract.balanceOf(userAddress);
        const userAEthBalance = await aWETH.balanceOf(userAddress);
        const adapterAEthBalance = await aWETH.balanceOf(getContractAddress(uniswapRepayAdapter));

        expect(adapterAEthBalance).to.be.eq(0n);
        expect(adapterWethBalance).to.be.eq(0n);
        expect(adapterDaiBalance).to.be.eq(0n);
        expect(userDaiStableDebtAmountBefore).to.be.gte(expectedDaiAmount);
        expect(userDaiStableDebtAmount).to.be.eq(0n);
        expect(userAEthBalance).to.be.lt(userAEthBalanceBefore);
        expect(userAEthBalance).to.be.gte((userAEthBalanceBefore - BigInt(liquidityToSwap)));
      });

      it('should correctly swap tokens and repay the whole variable debt', async () => {
        const {
          users,
          pool,
          weth,
          aWETH,
          oracle,
          dai,
          uniswapRepayAdapter,
          helpersContract,
        } = testEnv;
        const user = users[0].signer;
        const userAddress = users[0].address;

        const amountWETHtoSwap = await convertToCurrencyDecimals(getContractAddress(weth), '10');

        const daiPrice = await oracle.getAssetPrice(getContractAddress(dai));
        const expectedDaiAmount = await convertToCurrencyDecimals(
          getContractAddress(dai),
          new BigNumber(amountWETHtoSwap.toString()).div(daiPrice.toString()).toFixed(0)
        );

        // Open user Debt
        await pool.connect(user).borrow(getContractAddress(dai), expectedDaiAmount, 2, 0, userAddress);

        const daiStableVariableTokenAddress = (
          await helpersContract.getReserveTokensAddresses(getContractAddress(dai))
        ).variableDebtTokenAddress;

        const daiVariableDebtContract = await getContract<StableDebtToken>(
          eContractid.VariableDebtToken,
          daiStableVariableTokenAddress
        );

        const userDaiVariableDebtAmountBefore = await daiVariableDebtContract.balanceOf(
          userAddress
        );

        // Add a % to repay on top of the debt
        const liquidityToSwap = new BigNumber(amountWETHtoSwap.toString())
          .multipliedBy(1.1)
          .toFixed(0);

        await aWETH.connect(user).approve(getContractAddress(uniswapRepayAdapter), liquidityToSwap);
        const userAEthBalanceBefore = await aWETH.balanceOf(userAddress);

        // Add a % to repay on top of the debt
        const amountToRepay = new BigNumber(expectedDaiAmount.toString())
          .multipliedBy(1.1)
          .toFixed(0);

        await mockUniswapRouter.connect(user).setAmountToSwap(getContractAddress(weth), amountWETHtoSwap);
        await mockUniswapRouter.setDefaultMockValue(amountWETHtoSwap);

        const params = buildRepayAdapterParams(
          getContractAddress(weth),
          liquidityToSwap,
          2,
          0,
          0,
          0,
          '0x0000000000000000000000000000000000000000000000000000000000000000',
          '0x0000000000000000000000000000000000000000000000000000000000000000',
          false
        );

        await pool
          .connect(user)
          .flashLoan(
            getContractAddress(uniswapRepayAdapter),
            [getContractAddress(dai)],
            [amountToRepay.toString()],
            [0],
            userAddress,
            params,
            0
          );

        const adapterWethBalance = await weth.balanceOf(getContractAddress(uniswapRepayAdapter));
        const adapterDaiBalance = await dai.balanceOf(getContractAddress(uniswapRepayAdapter));
        const userDaiVariableDebtAmount = await daiVariableDebtContract.balanceOf(userAddress);
        const userAEthBalance = await aWETH.balanceOf(userAddress);
        const adapterAEthBalance = await aWETH.balanceOf(getContractAddress(uniswapRepayAdapter));

        expect(adapterAEthBalance).to.be.eq(0n);
        expect(adapterWethBalance).to.be.eq(0n);
        expect(adapterDaiBalance).to.be.eq(0n);
        expect(userDaiVariableDebtAmountBefore).to.be.gte(expectedDaiAmount);
        expect(userDaiVariableDebtAmount).to.be.eq(0n);
        expect(userAEthBalance).to.be.lt(userAEthBalanceBefore);
        expect(userAEthBalance).to.be.gte((userAEthBalanceBefore - BigInt(liquidityToSwap)));
      });

      it('should correctly repay debt via flash loan using the same asset as collateral', async () => {
        const { users, pool, aDai, dai, uniswapRepayAdapter, helpersContract } = testEnv;
        const user = users[0].signer;
        const userAddress = users[0].address;

        // Add deposit for user
        await dai.mint(parseEther('30'));
        await dai.approve(getContractAddress(pool), parseEther('30'));
        await pool.deposit(getContractAddress(dai), parseEther('30'), userAddress, 0);

        const amountCollateralToSwap = parseEther('10');
        const debtAmount = parseEther('10');

        // Open user Debt
        await pool.connect(user).borrow(getContractAddress(dai), debtAmount, 2, 0, userAddress);

        const daiVariableDebtTokenAddress = (
          await helpersContract.getReserveTokensAddresses(getContractAddress(dai))
        ).variableDebtTokenAddress;

        const daiVariableDebtContract = await getContract<VariableDebtToken>(
          eContractid.VariableDebtToken,
          daiVariableDebtTokenAddress
        );

        const userDaiVariableDebtAmountBefore = await daiVariableDebtContract.balanceOf(
          userAddress
        );

        const flashLoanDebt = new BigNumber(amountCollateralToSwap.toString())
          .multipliedBy(1.0009)
          .toFixed(0);

        await aDai.connect(user).approve(getContractAddress(uniswapRepayAdapter), flashLoanDebt);
        const userADaiBalanceBefore = await aDai.balanceOf(userAddress);
        const userDaiBalanceBefore = await dai.balanceOf(userAddress);

        const params = buildRepayAdapterParams(
          getContractAddress(dai),
          amountCollateralToSwap,
          2,
          0,
          0,
          0,
          '0x0000000000000000000000000000000000000000000000000000000000000000',
          '0x0000000000000000000000000000000000000000000000000000000000000000',
          false
        );

        await pool
          .connect(user)
          .flashLoan(
            getContractAddress(uniswapRepayAdapter),
            [getContractAddress(dai)],
            [amountCollateralToSwap.toString()],
            [0],
            userAddress,
            params,
            0
          );

        const adapterDaiBalance = await dai.balanceOf(getContractAddress(uniswapRepayAdapter));
        const userDaiVariableDebtAmount = await daiVariableDebtContract.balanceOf(userAddress);
        const userADaiBalance = await aDai.balanceOf(userAddress);
        const adapterADaiBalance = await aDai.balanceOf(getContractAddress(uniswapRepayAdapter));
        const userDaiBalance = await dai.balanceOf(userAddress);

        expect(adapterADaiBalance).to.be.eq(0n, 'adapter aDAI balance should be zero');
        expect(adapterDaiBalance).to.be.eq(0n, 'adapter DAI balance should be zero');
        expect(userDaiVariableDebtAmountBefore).to.be.gte(
          debtAmount,
          ' user DAI variable debt before should be gte debtAmount'
        );
        expect(userDaiVariableDebtAmount).to.be.lt(
          debtAmount,
          'user dai variable debt amount should be lt debt amount'
        );
        expect(userADaiBalance).to.be.lt(
          userADaiBalanceBefore,
          'user aDAI balance should be lt aDAI prior balance'
        );
        expect(userADaiBalance).to.be.gte(
          (userADaiBalanceBefore - BigInt(flashLoanDebt)),
          'user aDAI balance should be gte aDAI prior balance sub flash loan debt'
        );
        expect(userDaiBalance).to.be.eq(userDaiBalanceBefore, 'user dai balance eq prior balance');
      });
    });

    describe('swapAndRepay', () => {
      it('should correctly swap tokens and repay debt', async () => {
        const {
          users,
          pool,
          weth,
          aWETH,
          oracle,
          dai,
          uniswapRepayAdapter,
          helpersContract,
        } = testEnv;
        const user = users[0].signer;
        const userAddress = users[0].address;

        const amountWETHtoSwap = await convertToCurrencyDecimals(getContractAddress(weth), '10');

        const daiPrice = await oracle.getAssetPrice(getContractAddress(dai));
        const expectedDaiAmount = await convertToCurrencyDecimals(
          getContractAddress(dai),
          new BigNumber(amountWETHtoSwap.toString()).div(daiPrice.toString()).toFixed(0)
        );

        // Open user Debt
        await pool.connect(user).borrow(getContractAddress(dai), expectedDaiAmount, 1, 0, userAddress);

        const daiStableDebtTokenAddress = (
          await helpersContract.getReserveTokensAddresses(getContractAddress(dai))
        ).stableDebtTokenAddress;

        const daiStableDebtContract = await getContract<StableDebtToken>(
          eContractid.StableDebtToken,
          daiStableDebtTokenAddress
        );

        const userDaiStableDebtAmountBefore = await daiStableDebtContract.balanceOf(userAddress);

        const liquidityToSwap = amountWETHtoSwap;
        await aWETH.connect(user).approve(getContractAddress(uniswapRepayAdapter), liquidityToSwap);
        const userAEthBalanceBefore = await aWETH.balanceOf(userAddress);

        await mockUniswapRouter.setAmountToSwap(getContractAddress(weth), liquidityToSwap);

        await mockUniswapRouter.setDefaultMockValue(liquidityToSwap);

        await uniswapRepayAdapter.connect(user).swapAndRepay(
          getContractAddress(weth),
          getContractAddress(dai),
          liquidityToSwap,
          expectedDaiAmount,
          1,
          {
            amount: 0,
            deadline: 0,
            v: 0,
            r: '0x0000000000000000000000000000000000000000000000000000000000000000',
            s: '0x0000000000000000000000000000000000000000000000000000000000000000',
          },
          false
        );

        const adapterWethBalance = await weth.balanceOf(getContractAddress(uniswapRepayAdapter));
        const adapterDaiBalance = await dai.balanceOf(getContractAddress(uniswapRepayAdapter));
        const userDaiStableDebtAmount = await daiStableDebtContract.balanceOf(userAddress);
        const userAEthBalance = await aWETH.balanceOf(userAddress);

        expect(adapterWethBalance).to.be.eq(0n);
        expect(adapterDaiBalance).to.be.eq(0n);
        expect(userDaiStableDebtAmountBefore).to.be.gte(expectedDaiAmount);
        expect(userDaiStableDebtAmount).to.be.lt(expectedDaiAmount);
        expect(userAEthBalance).to.be.lt(userAEthBalanceBefore);
        expect(userAEthBalance).to.be.gte((userAEthBalanceBefore - BigInt(liquidityToSwap)));
      });

      it('should correctly swap tokens and repay debt with permit', async () => {
        const {
          users,
          pool,
          weth,
          aWETH,
          oracle,
          dai,
          uniswapRepayAdapter,
          helpersContract,
        } = testEnv;
        const user = users[0].signer;
        const userAddress = users[0].address;

        const amountWETHtoSwap = await convertToCurrencyDecimals(getContractAddress(weth), '10');

        const daiPrice = await oracle.getAssetPrice(getContractAddress(dai));
        const expectedDaiAmount = await convertToCurrencyDecimals(
          getContractAddress(dai),
          new BigNumber(amountWETHtoSwap.toString()).div(daiPrice.toString()).toFixed(0)
        );

        // Open user Debt
        await pool.connect(user).borrow(getContractAddress(dai), expectedDaiAmount, 1, 0, userAddress);

        const daiStableDebtTokenAddress = (
          await helpersContract.getReserveTokensAddresses(getContractAddress(dai))
        ).stableDebtTokenAddress;

        const daiStableDebtContract = await getContract<StableDebtToken>(
          eContractid.StableDebtToken,
          daiStableDebtTokenAddress
        );

        const userDaiStableDebtAmountBefore = await daiStableDebtContract.balanceOf(userAddress);

        const liquidityToSwap = amountWETHtoSwap;
        const userAEthBalanceBefore = await aWETH.balanceOf(userAddress);

        await mockUniswapRouter.setAmountToSwap(getContractAddress(weth), liquidityToSwap);

        await mockUniswapRouter.setDefaultMockValue(liquidityToSwap);

        const chainId = Number((await DRE.ethers.provider.getNetwork()).chainId);
        const deadline = MAX_UINT_AMOUNT;
        const nonce = Number(await aWETH._nonces(userAddress));
        const msgParams = buildPermitParams(
          chainId,
          getContractAddress(aWETH),
          '1',
          await aWETH.name(),
          userAddress,
          getContractAddress(uniswapRepayAdapter),
          nonce,
          deadline,
          liquidityToSwap.toString()
        );

        const ownerPrivateKey = accounts[1].secretKey;
        if (!ownerPrivateKey) {
          throw new Error('INVALID_OWNER_PK');
        }

        const { v, r, s } = getSignatureFromTypedData(ownerPrivateKey, msgParams);

        await uniswapRepayAdapter.connect(user).swapAndRepay(
          getContractAddress(weth),
          getContractAddress(dai),
          liquidityToSwap,
          expectedDaiAmount,
          1,
          {
            amount: liquidityToSwap,
            deadline,
            v,
            r,
            s,
          },
          false
        );

        const adapterWethBalance = await weth.balanceOf(getContractAddress(uniswapRepayAdapter));
        const adapterDaiBalance = await dai.balanceOf(getContractAddress(uniswapRepayAdapter));
        const userDaiStableDebtAmount = await daiStableDebtContract.balanceOf(userAddress);
        const userAEthBalance = await aWETH.balanceOf(userAddress);

        expect(adapterWethBalance).to.be.eq(0n);
        expect(adapterDaiBalance).to.be.eq(0n);
        expect(userDaiStableDebtAmountBefore).to.be.gte(expectedDaiAmount);
        expect(userDaiStableDebtAmount).to.be.lt(expectedDaiAmount);
        expect(userAEthBalance).to.be.lt(userAEthBalanceBefore);
        expect(userAEthBalance).to.be.gte((userAEthBalanceBefore - BigInt(liquidityToSwap)));
      });

      it('should revert if there is not debt to repay', async () => {
        const { users, weth, aWETH, oracle, dai, uniswapRepayAdapter } = testEnv;
        const user = users[0].signer;

        const amountWETHtoSwap = await convertToCurrencyDecimals(getContractAddress(weth), '10');

        const daiPrice = await oracle.getAssetPrice(getContractAddress(dai));
        const expectedDaiAmount = await convertToCurrencyDecimals(
          getContractAddress(dai),
          new BigNumber(amountWETHtoSwap.toString()).div(daiPrice.toString()).toFixed(0)
        );

        const liquidityToSwap = amountWETHtoSwap;
        await aWETH.connect(user).approve(getContractAddress(uniswapRepayAdapter), liquidityToSwap);

        await mockUniswapRouter.setAmountToSwap(getContractAddress(weth), liquidityToSwap);

        await mockUniswapRouter.setDefaultMockValue(liquidityToSwap);

        await expect(
          uniswapRepayAdapter.connect(user).swapAndRepay(
            getContractAddress(weth),
            getContractAddress(dai),
            liquidityToSwap,
            expectedDaiAmount,
            1,
            {
              amount: 0,
              deadline: 0,
              v: 0,
              r: '0x0000000000000000000000000000000000000000000000000000000000000000',
              s: '0x0000000000000000000000000000000000000000000000000000000000000000',
            },
            false
          )
        ).to.be.revert(DRE.ethers);
      });

      it('should revert when max amount allowed to swap is bigger than max slippage', async () => {
        const { users, pool, weth, aWETH, oracle, dai, uniswapRepayAdapter } = testEnv;
        const user = users[0].signer;
        const userAddress = users[0].address;

        const amountWETHtoSwap = await convertToCurrencyDecimals(getContractAddress(weth), '10');

        const daiPrice = await oracle.getAssetPrice(getContractAddress(dai));
        const expectedDaiAmount = await convertToCurrencyDecimals(
          getContractAddress(dai),
          new BigNumber(amountWETHtoSwap.toString()).div(daiPrice.toString()).toFixed(0)
        );

        // Open user Debt
        await pool.connect(user).borrow(getContractAddress(dai), expectedDaiAmount, 1, 0, userAddress);

        const bigMaxAmountToSwap = amountWETHtoSwap * 2n;
        await aWETH.connect(user).approve(getContractAddress(uniswapRepayAdapter), bigMaxAmountToSwap);

        await mockUniswapRouter.connect(user).setAmountToSwap(getContractAddress(weth), bigMaxAmountToSwap);

        await mockUniswapRouter.setDefaultMockValue(bigMaxAmountToSwap);

        await expect(
          uniswapRepayAdapter.connect(user).swapAndRepay(
            getContractAddress(weth),
            getContractAddress(dai),
            bigMaxAmountToSwap,
            expectedDaiAmount,
            1,
            {
              amount: 0,
              deadline: 0,
              v: 0,
              r: '0x0000000000000000000000000000000000000000000000000000000000000000',
              s: '0x0000000000000000000000000000000000000000000000000000000000000000',
            },
            false
          )
        ).to.be.revertedWith('maxAmountToSwap exceed max slippage');
      });

      it('should swap, repay debt and pull the needed ATokens leaving no leftovers', async () => {
        const {
          users,
          pool,
          weth,
          aWETH,
          oracle,
          dai,
          uniswapRepayAdapter,
          helpersContract,
        } = testEnv;
        const user = users[0].signer;
        const userAddress = users[0].address;

        const amountWETHtoSwap = await convertToCurrencyDecimals(getContractAddress(weth), '10');

        const daiPrice = await oracle.getAssetPrice(getContractAddress(dai));
        const expectedDaiAmount = await convertToCurrencyDecimals(
          getContractAddress(dai),
          new BigNumber(amountWETHtoSwap.toString()).div(daiPrice.toString()).toFixed(0)
        );

        // Open user Debt
        await pool.connect(user).borrow(getContractAddress(dai), expectedDaiAmount, 1, 0, userAddress);

        const daiStableDebtTokenAddress = (
          await helpersContract.getReserveTokensAddresses(getContractAddress(dai))
        ).stableDebtTokenAddress;

        const daiStableDebtContract = await getContract<StableDebtToken>(
          eContractid.StableDebtToken,
          daiStableDebtTokenAddress
        );

        const userDaiStableDebtAmountBefore = await daiStableDebtContract.balanceOf(userAddress);

        const liquidityToSwap = amountWETHtoSwap;
        await aWETH.connect(user).approve(getContractAddress(uniswapRepayAdapter), liquidityToSwap);
        const userAEthBalanceBefore = await aWETH.balanceOf(userAddress);
        const userWethBalanceBefore = await weth.balanceOf(userAddress);

        const actualWEthSwapped = new BigNumber(liquidityToSwap.toString())
          .multipliedBy(0.995)
          .toFixed(0);

        await mockUniswapRouter.connect(user).setAmountToSwap(getContractAddress(weth), actualWEthSwapped);

        await mockUniswapRouter.setDefaultMockValue(actualWEthSwapped);

        await uniswapRepayAdapter.connect(user).swapAndRepay(
          getContractAddress(weth),
          getContractAddress(dai),
          liquidityToSwap,
          expectedDaiAmount,
          1,
          {
            amount: 0,
            deadline: 0,
            v: 0,
            r: '0x0000000000000000000000000000000000000000000000000000000000000000',
            s: '0x0000000000000000000000000000000000000000000000000000000000000000',
          },
          false
        );

        const adapterWethBalance = await weth.balanceOf(getContractAddress(uniswapRepayAdapter));
        const adapterDaiBalance = await dai.balanceOf(getContractAddress(uniswapRepayAdapter));
        const userDaiStableDebtAmount = await daiStableDebtContract.balanceOf(userAddress);
        const userAEthBalance = await aWETH.balanceOf(userAddress);
        const adapterAEthBalance = await aWETH.balanceOf(getContractAddress(uniswapRepayAdapter));
        const userWethBalance = await weth.balanceOf(userAddress);

        expect(adapterAEthBalance).to.be.eq(0n);
        expect(adapterWethBalance).to.be.eq(0n);
        expect(adapterDaiBalance).to.be.eq(0n);
        expect(userDaiStableDebtAmountBefore).to.be.gte(expectedDaiAmount);
        expect(userDaiStableDebtAmount).to.be.lt(expectedDaiAmount);
        expect(userAEthBalance).to.be.lt(userAEthBalanceBefore);
        expect(userAEthBalance).to.be.eq((userAEthBalanceBefore - BigInt(actualWEthSwapped)));
        expect(userWethBalance).to.be.eq(userWethBalanceBefore);
      });

      it('should correctly swap tokens and repay the whole stable debt', async () => {
        const {
          users,
          pool,
          weth,
          aWETH,
          oracle,
          dai,
          uniswapRepayAdapter,
          helpersContract,
        } = testEnv;
        const user = users[0].signer;
        const userAddress = users[0].address;

        const amountWETHtoSwap = await convertToCurrencyDecimals(getContractAddress(weth), '10');

        const daiPrice = await oracle.getAssetPrice(getContractAddress(dai));
        const expectedDaiAmount = await convertToCurrencyDecimals(
          getContractAddress(dai),
          new BigNumber(amountWETHtoSwap.toString()).div(daiPrice.toString()).toFixed(0)
        );

        // Open user Debt
        await pool.connect(user).borrow(getContractAddress(dai), expectedDaiAmount, 1, 0, userAddress);

        const daiStableDebtTokenAddress = (
          await helpersContract.getReserveTokensAddresses(getContractAddress(dai))
        ).stableDebtTokenAddress;

        const daiStableDebtContract = await getContract<StableDebtToken>(
          eContractid.StableDebtToken,
          daiStableDebtTokenAddress
        );

        const userDaiStableDebtAmountBefore = await daiStableDebtContract.balanceOf(userAddress);

        // Add a % to repay on top of the debt
        const liquidityToSwap = new BigNumber(amountWETHtoSwap.toString())
          .multipliedBy(1.1)
          .toFixed(0);

        await aWETH.connect(user).approve(getContractAddress(uniswapRepayAdapter), liquidityToSwap);
        const userAEthBalanceBefore = await aWETH.balanceOf(userAddress);

        // Add a % to repay on top of the debt
        const amountToRepay = new BigNumber(expectedDaiAmount.toString())
          .multipliedBy(1.1)
          .toFixed(0);

        await mockUniswapRouter.connect(user).setAmountToSwap(getContractAddress(weth), amountWETHtoSwap);
        await mockUniswapRouter.setDefaultMockValue(amountWETHtoSwap);

        await uniswapRepayAdapter.connect(user).swapAndRepay(
          getContractAddress(weth),
          getContractAddress(dai),
          liquidityToSwap,
          amountToRepay,
          1,
          {
            amount: 0,
            deadline: 0,
            v: 0,
            r: '0x0000000000000000000000000000000000000000000000000000000000000000',
            s: '0x0000000000000000000000000000000000000000000000000000000000000000',
          },
          false
        );

        const adapterWethBalance = await weth.balanceOf(getContractAddress(uniswapRepayAdapter));
        const adapterDaiBalance = await dai.balanceOf(getContractAddress(uniswapRepayAdapter));
        const userDaiStableDebtAmount = await daiStableDebtContract.balanceOf(userAddress);
        const userAEthBalance = await aWETH.balanceOf(userAddress);
        const adapterAEthBalance = await aWETH.balanceOf(getContractAddress(uniswapRepayAdapter));

        expect(adapterAEthBalance).to.be.eq(0n);
        expect(adapterWethBalance).to.be.eq(0n);
        expect(adapterDaiBalance).to.be.eq(0n);
        expect(userDaiStableDebtAmountBefore).to.be.gte(expectedDaiAmount);
        expect(userDaiStableDebtAmount).to.be.eq(0n);
        expect(userAEthBalance).to.be.lt(userAEthBalanceBefore);
        expect(userAEthBalance).to.be.gte((userAEthBalanceBefore - BigInt(liquidityToSwap)));
      });

      it('should correctly swap tokens and repay the whole variable debt', async () => {
        const {
          users,
          pool,
          weth,
          aWETH,
          oracle,
          dai,
          uniswapRepayAdapter,
          helpersContract,
        } = testEnv;
        const user = users[0].signer;
        const userAddress = users[0].address;

        const amountWETHtoSwap = await convertToCurrencyDecimals(getContractAddress(weth), '10');

        const daiPrice = await oracle.getAssetPrice(getContractAddress(dai));
        const expectedDaiAmount = await convertToCurrencyDecimals(
          getContractAddress(dai),
          new BigNumber(amountWETHtoSwap.toString()).div(daiPrice.toString()).toFixed(0)
        );

        // Open user Debt
        await pool.connect(user).borrow(getContractAddress(dai), expectedDaiAmount, 2, 0, userAddress);

        const daiStableVariableTokenAddress = (
          await helpersContract.getReserveTokensAddresses(getContractAddress(dai))
        ).variableDebtTokenAddress;

        const daiVariableDebtContract = await getContract<StableDebtToken>(
          eContractid.VariableDebtToken,
          daiStableVariableTokenAddress
        );

        const userDaiVariableDebtAmountBefore = await daiVariableDebtContract.balanceOf(
          userAddress
        );

        // Add a % to repay on top of the debt
        const liquidityToSwap = new BigNumber(amountWETHtoSwap.toString())
          .multipliedBy(1.1)
          .toFixed(0);

        await aWETH.connect(user).approve(getContractAddress(uniswapRepayAdapter), liquidityToSwap);
        const userAEthBalanceBefore = await aWETH.balanceOf(userAddress);

        // Add a % to repay on top of the debt
        const amountToRepay = new BigNumber(expectedDaiAmount.toString())
          .multipliedBy(1.1)
          .toFixed(0);

        await mockUniswapRouter.connect(user).setAmountToSwap(getContractAddress(weth), amountWETHtoSwap);
        await mockUniswapRouter.setDefaultMockValue(amountWETHtoSwap);

        await uniswapRepayAdapter.connect(user).swapAndRepay(
          getContractAddress(weth),
          getContractAddress(dai),
          liquidityToSwap,
          amountToRepay,
          2,
          {
            amount: 0,
            deadline: 0,
            v: 0,
            r: '0x0000000000000000000000000000000000000000000000000000000000000000',
            s: '0x0000000000000000000000000000000000000000000000000000000000000000',
          },
          false
        );

        const adapterWethBalance = await weth.balanceOf(getContractAddress(uniswapRepayAdapter));
        const adapterDaiBalance = await dai.balanceOf(getContractAddress(uniswapRepayAdapter));
        const userDaiVariableDebtAmount = await daiVariableDebtContract.balanceOf(userAddress);
        const userAEthBalance = await aWETH.balanceOf(userAddress);
        const adapterAEthBalance = await aWETH.balanceOf(getContractAddress(uniswapRepayAdapter));

        expect(adapterAEthBalance).to.be.eq(0n);
        expect(adapterWethBalance).to.be.eq(0n);
        expect(adapterDaiBalance).to.be.eq(0n);
        expect(userDaiVariableDebtAmountBefore).to.be.gte(expectedDaiAmount);
        expect(userDaiVariableDebtAmount).to.be.eq(0n);
        expect(userAEthBalance).to.be.lt(userAEthBalanceBefore);
        expect(userAEthBalance).to.be.gte((userAEthBalanceBefore - BigInt(liquidityToSwap)));
      });

      it('should correctly repay debt using the same asset as collateral', async () => {
        const { users, pool, dai, uniswapRepayAdapter, helpersContract, aDai } = testEnv;
        const user = users[0].signer;
        const userAddress = users[0].address;

        // Add deposit for user
        await dai.mint(parseEther('30'));
        await dai.approve(getContractAddress(pool), parseEther('30'));
        await pool.deposit(getContractAddress(dai), parseEther('30'), userAddress, 0);

        const amountCollateralToSwap = parseEther('4');

        const debtAmount = parseEther('3');

        // Open user Debt
        await pool.connect(user).borrow(getContractAddress(dai), debtAmount, 2, 0, userAddress);

        const daiVariableDebtTokenAddress = (
          await helpersContract.getReserveTokensAddresses(getContractAddress(dai))
        ).variableDebtTokenAddress;

        const daiVariableDebtContract = await getContract<StableDebtToken>(
          eContractid.StableDebtToken,
          daiVariableDebtTokenAddress
        );

        const userDaiVariableDebtAmountBefore = await daiVariableDebtContract.balanceOf(
          userAddress
        );

        await aDai.connect(user).approve(getContractAddress(uniswapRepayAdapter), amountCollateralToSwap);
        const userADaiBalanceBefore = await aDai.balanceOf(userAddress);
        const userDaiBalanceBefore = await dai.balanceOf(userAddress);

        await uniswapRepayAdapter.connect(user).swapAndRepay(
          getContractAddress(dai),
          getContractAddress(dai),
          amountCollateralToSwap,
          amountCollateralToSwap,
          2,
          {
            amount: 0,
            deadline: 0,
            v: 0,
            r: '0x0000000000000000000000000000000000000000000000000000000000000000',
            s: '0x0000000000000000000000000000000000000000000000000000000000000000',
          },
          false
        );

        const adapterDaiBalance = await dai.balanceOf(getContractAddress(uniswapRepayAdapter));
        const userDaiVariableDebtAmount = await daiVariableDebtContract.balanceOf(userAddress);
        const userADaiBalance = await aDai.balanceOf(userAddress);
        const adapterADaiBalance = await aDai.balanceOf(getContractAddress(uniswapRepayAdapter));
        const userDaiBalance = await dai.balanceOf(userAddress);

        expect(adapterADaiBalance).to.be.eq(0n, 'adapter aADAI should be zero');
        expect(adapterDaiBalance).to.be.eq(0n, 'adapter DAI should be zero');
        expect(userDaiVariableDebtAmountBefore).to.be.gte(
          debtAmount,
          'user dai variable debt before should be gte debtAmount'
        );
        expect(userDaiVariableDebtAmount).to.be.lt(
          debtAmount,
          'current user dai variable debt amount should be less than debtAmount'
        );
        expect(userADaiBalance).to.be.lt(
          userADaiBalanceBefore,
          'current user aDAI balance should be less than prior balance'
        );
        expect(userADaiBalance).to.be.gte(
          (userADaiBalanceBefore - amountCollateralToSwap),
          'current user aDAI balance should be gte user balance sub swapped collateral'
        );
        expect(userDaiBalance).to.be.eq(
          userDaiBalanceBefore,
          'user DAI balance should remain equal'
        );
      });
    });
  });
});
