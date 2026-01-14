import type { HardhatRuntimeEnvironment } from 'hardhat/types/hre';
import {
  loadPoolConfig,
  ConfigNames,
  getWrappedNativeTokenAddress,
} from '../../helpers/configuration.js';
import { deployWETHGateway } from '../../helpers/contracts-deployments.js';
import { getContractAddress } from '../../helpers/contracts-helpers.js';

const CONTRACT_NAME = 'WETHGateway';

type Args = {
  verify: boolean;
  pool: string;
};

export default async function deployWethGatewayAction(
  { verify, pool }: Args,
  hre: HardhatRuntimeEnvironment
) {
  await hre.tasks.getTask('set-DRE').run({});

  // Validate pool name
  if (!pool || !Object.values(ConfigNames).includes(pool as ConfigNames)) {
    throw new Error(
      `Invalid --pool "${pool}". Supported: ${Object.values(ConfigNames).join(', ')}`
    );
  }

  const poolConfig = loadPoolConfig(pool as ConfigNames);
  const Weth = await getWrappedNativeTokenAddress(poolConfig);

  const conn = await hre.network.connect();
  const networkConfig = (hre.config.networks as any)[conn.networkName];
  const chainId = networkConfig?.chainId;
  if (!chainId) {
    throw new Error('INVALID_CHAIN_ID');
  }
  const wethGateWay = await deployWETHGateway([Weth], verify);
  console.log(`${CONTRACT_NAME}.address`, getContractAddress(wethGateWay));
  console.log(`\tFinished ${CONTRACT_NAME} deployment`);
}
