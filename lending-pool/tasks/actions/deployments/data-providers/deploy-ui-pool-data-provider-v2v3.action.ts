import type { HardhatRuntimeEnvironment } from 'hardhat/types/hre';
import { deployUiPoolDataProviderV2V3 } from '../../../../helpers/contracts-deployments.js';
import { chainlinkAggregatorProxy, chainlinkEthUsdAggregatorProxy } from '../../../../helpers/constants.js';
import { getContractAddress } from '../../../../helpers/contracts-helpers.js';

type Args = {
  verify: boolean;
};

export default async function deployUiPoolDataProviderV2V3Action(
  { verify }: Args,
  hre: HardhatRuntimeEnvironment
) {
  await hre.tasks.getTask('set-DRE').run({});

  const conn = await hre.network.connect();
  const network = process.env.FORK ? process.env.FORK : conn.networkName;

  // HH3: chainId is not typed on NetworkConnection, access via config
  const networkConfig = (hre.config.networks as any)[conn.networkName];
  const chainId = networkConfig?.chainId;
  if (!chainId) {
    throw new Error('INVALID_CHAIN_ID');
  }

  console.log(
    `\n- UiPoolDataProviderV2V3 price aggregator: ${chainlinkAggregatorProxy[network]}`
  );
  console.log(
    `\n- UiPoolDataProviderV2V3 eth/usd price aggregator: ${chainlinkEthUsdAggregatorProxy[network]}`
  );
  console.log(`\n- UiPoolDataProviderV2V3 deployment`);

  const UiPoolDataProviderV2V3 = await deployUiPoolDataProviderV2V3(
    chainlinkAggregatorProxy[network],
    chainlinkEthUsdAggregatorProxy[network],
    verify
  );

  console.log('UiPoolDataProviderV2V3 deployed at:', getContractAddress(UiPoolDataProviderV2V3));
}
