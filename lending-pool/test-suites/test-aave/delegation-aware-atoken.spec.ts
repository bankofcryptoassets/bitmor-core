import { MAX_UINT_AMOUNT, ZERO_ADDRESS } from '../../helpers/constants.js';
import { BUIDLEREVM_CHAINID } from '../../helpers/buidler-constants.js';
import {buildPermitParams, getSignatureFromTypedData,
  getContractAddress} from '../../helpers/contracts-helpers.js';
import chai from 'chai';
const { expect } = chai;
import { parseEther } from 'ethers';
import { ProtocolErrors } from '../../helpers/types.js';
import { makeSuite } from './helpers/make-suite.js';
import type { TestEnv } from './helpers/make-suite.js';
import { DRE } from '../../helpers/misc-utils.js';
import {
  ConfigNames,
  getATokenDomainSeparatorPerNetwork,
  getTreasuryAddress,
  loadPoolConfig,
} from '../../helpers/configuration.js';
import { waitForTx } from '../../helpers/misc-utils.js';
import {
  deployDelegationAwareAToken,
  deployMintableDelegationERC20,
} from '../../helpers/contracts-deployments.js';
import type { DelegationAwareAToken } from '../../types/ethers-contracts/index.js';
import type { MintableDelegationERC20 } from '../../types/ethers-contracts/index.js';
import AaveConfig from '../../markets/aave/index.js';

makeSuite('AToken: underlying delegation', (testEnv: TestEnv) => {
  const poolConfig = loadPoolConfig(ConfigNames.Commons);
  let delegationAToken = <DelegationAwareAToken>{};
  let delegationERC20 = <MintableDelegationERC20>{};

  it('Deploys a new MintableDelegationERC20 and a DelegationAwareAToken', async () => {
    const { pool } = testEnv;

    delegationERC20 = await deployMintableDelegationERC20(['DEL', 'DEL', '18']);

    delegationAToken = await deployDelegationAwareAToken(
      [
        getContractAddress(pool),
        getContractAddress(delegationERC20),
        await getTreasuryAddress(AaveConfig),
        ZERO_ADDRESS,
        'aDEL',
        'aDEL',
      ],
      false
    );

    //await delegationAToken.initialize(getContractAddress(pool), ZERO_ADDRESS, delegationERC20.address, ZERO_ADDRESS, '18', 'aDEL', 'aDEL');

    console.log((await delegationAToken.decimals()).toString());
  });

  it('Tries to delegate with the caller not being the Aave admin', async () => {
    const { users } = testEnv;

    await expect(
      delegationAToken.connect(users[1].signer).delegateUnderlyingTo(users[2].address)
    ).to.be.revertedWith(ProtocolErrors.CALLER_NOT_POOL_ADMIN);
  });

  it('Tries to delegate to user 2', async () => {
    const { users } = testEnv;

    await delegationAToken.delegateUnderlyingTo(users[2].address);

    const delegateeAddress = await delegationERC20.delegatee();

    expect(delegateeAddress).to.be.equal(users[2].address);
  });
});
