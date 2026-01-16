import chai from 'chai';
const { expect } = chai;
import { makeSuite } from './helpers/make-suite.js';
import type { TestEnv } from './helpers/make-suite.js';
import { ProtocolErrors, TokenContractId, eContractid } from '../../helpers/types.js';
import { getVariableDebtToken } from '../../helpers/contracts-getters.js';
import { getContractAddress } from '../../helpers/contracts-helpers.js';

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
});
