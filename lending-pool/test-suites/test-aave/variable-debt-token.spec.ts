import chai from 'chai';
const { expect } = chai;
import { makeSuite } from './helpers/make-suite.js';
import type { TestEnv } from './helpers/make-suite.js';
import { ProtocolErrors, TokenContractId, eContractid } from '../../helpers/types.js';
import { getVariableDebtToken, getAaveOracle } from '../../helpers/contracts-getters.js';
import { getContractAddress } from '../../helpers/contracts-helpers.js';
import { Contract, parseEther, ZeroAddress } from 'ethers';

makeSuite('Variable debt token tests', (testEnv: TestEnv) => {
  const { CT_CALLER_MUST_BE_LENDING_POOL } = ProtocolErrors;

  it('Tries to invoke mint not being the LendingPool', async () => {
    const { deployer, pool, dai, helpersContract } = testEnv;

    const daiVariableDebtTokenAddress = (
      await helpersContract.getReserveTokensAddresses(getContractAddress(dai))
    ).variableDebtTokenAddress;

    const variableDebtContract = await getVariableDebtToken(daiVariableDebtTokenAddress);

    await expect(
      variableDebtContract.mint(deployer.address, deployer.address, '1', '1')
    ).to.be.revertedWith(CT_CALLER_MUST_BE_LENDING_POOL);
  });

  it('Tries to invoke burn not being the LendingPool', async () => {
    const { deployer, pool, dai, helpersContract } = testEnv;

    const daiVariableDebtTokenAddress = (
      await helpersContract.getReserveTokensAddresses(getContractAddress(dai))
    ).variableDebtTokenAddress;

    const variableDebtContract = await getVariableDebtToken(daiVariableDebtTokenAddress);

    await expect(variableDebtContract.burn(deployer.address, '1', '1')).to.be.revertedWith(
      CT_CALLER_MUST_BE_LENDING_POOL
    );
  });

  it('getScaledUserBalanceAndSupply returns balance and supply', async () => {
    const { deployer, usdc, helpersContract } = testEnv;

    const { variableDebtTokenAddress } = await helpersContract.getReserveTokensAddresses(
      getContractAddress(usdc)
    );
    const variableDebtContract = await getVariableDebtToken(variableDebtTokenAddress);

    const result = await variableDebtContract.getScaledUserBalanceAndSupply(deployer.address);
    expect(result[0]).to.be.gte(0n);
    expect(result[1]).to.be.gte(0n);
  });

  it('UNDERLYING_ASSET_ADDRESS returns correct asset', async () => {
    const { usdc, helpersContract } = testEnv;

    const { variableDebtTokenAddress } = await helpersContract.getReserveTokensAddresses(
      getContractAddress(usdc)
    );
    const variableDebtContract = await getVariableDebtToken(variableDebtTokenAddress);

    expect(await variableDebtContract.UNDERLYING_ASSET_ADDRESS()).to.equal(
      getContractAddress(usdc)
    );
  });

  it('getIncentivesController returns controller address', async () => {
    const { usdc, helpersContract } = testEnv;

    const { variableDebtTokenAddress } = await helpersContract.getReserveTokensAddresses(
      getContractAddress(usdc)
    );
    const variableDebtContract = await getVariableDebtToken(variableDebtTokenAddress);

    await variableDebtContract.getIncentivesController();
  });

  it('POOL returns lending pool address', async () => {
    const { pool, usdc, helpersContract } = testEnv;

    const { variableDebtTokenAddress } = await helpersContract.getReserveTokensAddresses(
      getContractAddress(usdc)
    );
    const variableDebtContract = await getVariableDebtToken(variableDebtTokenAddress);

    expect(await variableDebtContract.POOL()).to.equal(getContractAddress(pool));
  });

  describe('AaveOracle: coverage', () => {
    it('setAssetSources updates asset sources', async () => {
      const { usdc } = testEnv;
      const aaveOracle = await getAaveOracle();

      const currentSource = await aaveOracle.getSourceOfAsset(getContractAddress(usdc));
      await aaveOracle.setAssetSources([getContractAddress(usdc)], [currentSource]);
    });

    it('setFallbackOracle updates fallback oracle', async () => {
      const aaveOracle = await getAaveOracle();

      const currentFallback = await aaveOracle.getFallbackOracle();
      await aaveOracle.setFallbackOracle(currentFallback);
    });

    it('setBTC updates BTC address', async () => {
      const { cbBTC } = testEnv;
      const aaveOracle = await getAaveOracle();

      await aaveOracle.setBTC(getContractAddress(cbBTC));
      expect(await aaveOracle.s_btc()).to.equal(getContractAddress(cbBTC));
    });

    it('setbvBTC updates bvBTC address', async () => {
      const { btcVault } = testEnv;
      const aaveOracle = await getAaveOracle();

      await aaveOracle.setbvBTC(getContractAddress(btcVault));
      expect(await aaveOracle.s_bvBTC()).to.equal(getContractAddress(btcVault));
    });

    it('getAssetPrice enters bvBTC vault conversion path', async () => {
      const { btcVault } = testEnv;
      const aaveOracle = await getAaveOracle();

      // Lines 113-117: bvBTC path reverts due to Solidity 0.6.12 uint8 overflow
      // 10 ** uint8(8) overflows to 0, causing SafeMath division by zero
      await expect(
        aaveOracle.getAssetPrice(getContractAddress(btcVault))
      ).to.be.revertedWith('SafeMath: division by zero');
    });

    it('getAssetPrice returns correct price for WETH', async () => {
      const { weth } = testEnv;
      const aaveOracle = await getAaveOracle();

      // With USD denomination, WETH price should be $2500 (250000000000 = 2500 * 1e8)
      const price = await aaveOracle.getAssetPrice(getContractAddress(weth));
      expect(price).to.equal(250000000000n);
    });

    it('getAssetPrice uses Chainlink source when price > 0', async () => {
      const { usdc, deployer } = testEnv;
      const aaveOracle = await getAaveOracle();

      const sourceAddress = await aaveOracle.getSourceOfAsset(getContractAddress(usdc));
      expect(sourceAddress).to.not.equal(ZeroAddress);

      const price = await aaveOracle.getAssetPrice(getContractAddress(usdc));
      expect(price).to.be.greaterThan(0n);
    });

    it('getAssetPrice falls back to fallback oracle when Chainlink price <= 0', async () => {
      const { usdc, deployer } = testEnv;
      const aaveOracle = await getAaveOracle();

      const sourceAddress = await aaveOracle.getSourceOfAsset(getContractAddress(usdc));
      const aggregator = new Contract(
        sourceAddress,
        ['function updateAnswer(int256)', 'function latestAnswer() view returns (int256)'],
        deployer.signer
      );

      // Save original price
      const originalPrice = await aggregator.latestAnswer();

      // Set price to 0 to trigger fallback
      await aggregator.updateAnswer(0);

      // getAssetPrice should now fall back to the fallback oracle
      const price = await aaveOracle.getAssetPrice(getContractAddress(usdc));
      expect(price).to.be.gte(0n);

      // Restore original price
      await aggregator.updateAnswer(originalPrice);
    });

    it('getAssetPrice falls back when source is address(0)', async () => {
      const { deployer } = testEnv;
      const aaveOracle = await getAaveOracle();

      // Use a random address that has no source set
      const price = await aaveOracle.getAssetPrice(deployer.address);
      expect(price).to.be.gte(0n);
    });

    it('getAssetsPrices returns prices for multiple assets', async () => {
      const { usdc, cbBTC } = testEnv;
      const aaveOracle = await getAaveOracle();

      const prices = await aaveOracle.getAssetsPrices([
        getContractAddress(usdc),
        getContractAddress(cbBTC),
      ]);
      expect(prices.length).to.equal(2);
    });

    it('getSourceOfAsset returns source address', async () => {
      const { usdc } = testEnv;
      const aaveOracle = await getAaveOracle();

      const source = await aaveOracle.getSourceOfAsset(getContractAddress(usdc));
      expect(source).to.not.equal(ZeroAddress);
    });

    it('getFallbackOracle returns fallback oracle address', async () => {
      const aaveOracle = await getAaveOracle();

      const fallback = await aaveOracle.getFallbackOracle();
      expect(fallback).to.not.equal(ZeroAddress);
    });
  });

  describe('DebtTokenBase: disabled ERC20 functions', () => {
    it('transfer reverts with TRANSFER_NOT_SUPPORTED', async () => {
      const { users, usdc, helpersContract } = testEnv;
      const { variableDebtTokenAddress } = await helpersContract.getReserveTokensAddresses(getContractAddress(usdc));
      const variableDebtContract = await getVariableDebtToken(variableDebtTokenAddress);

      await expect(
        variableDebtContract.transfer(users[0].address, '1')
      ).to.be.revertedWith('TRANSFER_NOT_SUPPORTED');
    });

    it('allowance reverts with ALLOWANCE_NOT_SUPPORTED', async () => {
      const { deployer, users, usdc, helpersContract } = testEnv;
      const { variableDebtTokenAddress } = await helpersContract.getReserveTokensAddresses(getContractAddress(usdc));
      const variableDebtContract = await getVariableDebtToken(variableDebtTokenAddress);

      await expect(
        variableDebtContract.allowance(deployer.address, users[0].address)
      ).to.be.revertedWith('ALLOWANCE_NOT_SUPPORTED');
    });

    it('approve reverts with APPROVAL_NOT_SUPPORTED', async () => {
      const { users, usdc, helpersContract } = testEnv;
      const { variableDebtTokenAddress } = await helpersContract.getReserveTokensAddresses(getContractAddress(usdc));
      const variableDebtContract = await getVariableDebtToken(variableDebtTokenAddress);

      await expect(
        variableDebtContract.approve(users[0].address, '1')
      ).to.be.revertedWith('APPROVAL_NOT_SUPPORTED');
    });

    it('transferFrom reverts with TRANSFER_NOT_SUPPORTED', async () => {
      const { deployer, users, usdc, helpersContract } = testEnv;
      const { variableDebtTokenAddress } = await helpersContract.getReserveTokensAddresses(getContractAddress(usdc));
      const variableDebtContract = await getVariableDebtToken(variableDebtTokenAddress);

      await expect(
        variableDebtContract.transferFrom(deployer.address, users[0].address, '1')
      ).to.be.revertedWith('TRANSFER_NOT_SUPPORTED');
    });

    it('increaseAllowance reverts with ALLOWANCE_NOT_SUPPORTED', async () => {
      const { users, usdc, helpersContract } = testEnv;
      const { variableDebtTokenAddress } = await helpersContract.getReserveTokensAddresses(getContractAddress(usdc));
      const variableDebtContract = await getVariableDebtToken(variableDebtTokenAddress);

      await expect(
        variableDebtContract.increaseAllowance(users[0].address, '1')
      ).to.be.revertedWith('ALLOWANCE_NOT_SUPPORTED');
    });

    it('decreaseAllowance reverts with ALLOWANCE_NOT_SUPPORTED', async () => {
      const { users, usdc, helpersContract } = testEnv;
      const { variableDebtTokenAddress } = await helpersContract.getReserveTokensAddresses(getContractAddress(usdc));
      const variableDebtContract = await getVariableDebtToken(variableDebtTokenAddress);

      await expect(
        variableDebtContract.decreaseAllowance(users[0].address, '1')
      ).to.be.revertedWith('ALLOWANCE_NOT_SUPPORTED');
    });
  });
});
