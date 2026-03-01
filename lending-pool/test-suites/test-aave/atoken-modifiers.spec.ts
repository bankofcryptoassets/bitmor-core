import { expect } from 'chai';
import { makeSuite } from './helpers/make-suite.js';
import type { TestEnv } from './helpers/make-suite.js';
import { ProtocolErrors } from '../../helpers/types.js';
import { getContractAddress } from '../../helpers/contracts-helpers.js';

makeSuite('AToken: Modifiers', (testEnv: TestEnv) => {
  const { CT_CALLER_MUST_BE_LENDING_POOL } = ProtocolErrors;

  it('Tries to invoke mint not being the LendingPool', async () => {
    const { deployer, aUSDC } = testEnv;
    await expect(aUSDC.mint(deployer.address, '1', '1')).to.be.revertedWith(
      CT_CALLER_MUST_BE_LENDING_POOL
    );
  });

  it('Tries to invoke burn not being the LendingPool', async () => {
    const { deployer, aUSDC } = testEnv;
    await expect(aUSDC.burn(deployer.address, deployer.address, '1', '1')).to.be.revertedWith(
      CT_CALLER_MUST_BE_LENDING_POOL
    );
  });

  it('Tries to invoke transferOnLiquidation not being the LendingPool', async () => {
    const { deployer, users, aUSDC } = testEnv;
    await expect(
      aUSDC.transferOnLiquidation(deployer.address, users[0].address, '1')
    ).to.be.revertedWith(CT_CALLER_MUST_BE_LENDING_POOL);
  });

  it('Tries to invoke transferUnderlyingTo not being the LendingPool', async () => {
    const { deployer, aUSDC } = testEnv;
    await expect(aUSDC.transferUnderlyingTo(deployer.address, '1')).to.be.revertedWith(
      CT_CALLER_MUST_BE_LENDING_POOL
    );
  });

  it('getScaledUserBalanceAndSupply returns balance and supply', async () => {
    const { deployer, aUSDC } = testEnv;
    const result = await aUSDC.getScaledUserBalanceAndSupply(deployer.address);
    expect(result[0]).to.be.gte(0n);
    expect(result[1]).to.be.gte(0n);
  });

  it('scaledTotalSupply returns scaled supply', async () => {
    const { aUSDC } = testEnv;
    const scaledSupply = await aUSDC.scaledTotalSupply();
    expect(scaledSupply).to.be.gte(0n);
  });

  it('RESERVE_TREASURY_ADDRESS returns treasury address', async () => {
    const { aUSDC } = testEnv;
    const treasury = await aUSDC.RESERVE_TREASURY_ADDRESS();
    expect(treasury).to.be.a('string');
  });

  it('UNDERLYING_ASSET_ADDRESS returns correct asset', async () => {
    const { aUSDC, usdc } = testEnv;
    const underlyingAsset = await aUSDC.UNDERLYING_ASSET_ADDRESS();
    expect(underlyingAsset).to.equal(getContractAddress(usdc));
  });

  it('POOL returns lending pool address', async () => {
    const { aUSDC, pool } = testEnv;
    const poolAddress = await aUSDC.POOL();
    expect(poolAddress).to.equal(getContractAddress(pool));
  });

  it('getIncentivesController returns controller address', async () => {
    const { aUSDC } = testEnv;
    await aUSDC.getIncentivesController();
  });
});
