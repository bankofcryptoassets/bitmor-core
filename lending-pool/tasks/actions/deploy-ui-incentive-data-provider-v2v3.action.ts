import type { HardhatRuntimeEnvironment } from 'hardhat/types/hre';
import { deployUiIncentiveDataProviderV2V3 } from '../../helpers/contracts-deployments.js';
import { getContractAddress } from '../../helpers/contracts-helpers.js';

type Args = {
  verify: boolean;
};

export default async function deployUiIncentiveDataProviderV2V3Action(
  { verify }: Args,
  hre: HardhatRuntimeEnvironment
) {
  await hre.tasks.getTask('set-DRE').run({});

  const conn = await hre.network.connect();

  // HH3: chainId is not typed on NetworkConnection, access via config
  const networkConfig = (hre.config.networks as any)[conn.networkName];
  const chainId = networkConfig?.chainId;
  if (!chainId) {
    throw new Error('INVALID_CHAIN_ID');
  }

  console.log(`\n- UiIncentiveDataProviderV2V3 deployment`);

  const uiIncentiveDataProviderV2V3 = await deployUiIncentiveDataProviderV2V3(verify);

  console.log('UiIncentiveDataProviderV2V3 deployed at:', getContractAddress(uiIncentiveDataProviderV2V3));
}
