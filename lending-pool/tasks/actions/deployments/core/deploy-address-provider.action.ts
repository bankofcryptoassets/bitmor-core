import type { HardhatRuntimeEnvironment } from 'hardhat/types/hre';
import { deployLendingPoolAddressesProvider } from '../../../../helpers/contracts-deployments.js';
import { notFalsyOrZeroAddress, waitForTx } from '../../../../helpers/misc-utils.js';
import {
  ConfigNames,
  loadPoolConfig,
  getGenesisPoolAdmin,
  getEmergencyAdmin,
} from '../../../../helpers/configuration.js';
import { getParamPerNetwork, getContractAddress } from '../../../../helpers/contracts-helpers.js';
import { eNetwork } from '../../../../helpers/types.js';

type Args = {
  verify: boolean;
  pool: string;
  skipRegistry: boolean;
};

export default async function deployAddressProviderAction(
  { verify, pool, skipRegistry }: Args,
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
  const { MarketId } = poolConfig;

  // 1. Deploy address provider and set genesis manager
  const addressesProvider = await deployLendingPoolAddressesProvider(MarketId, verify);

  // 2. Add to registry or setup a new one
  if (!skipRegistry) {
    const conn = await hre.network.connect();
    const network = conn.networkName as eNetwork;
    const providerRegistryAddress = getParamPerNetwork(poolConfig.ProviderRegistry, network);

    await hre.tasks.getTask('add-market-to-registry').run({
      pool,
      addressesProvider: getContractAddress(addressesProvider),
      deployRegistry: !notFalsyOrZeroAddress(providerRegistryAddress),
    });
  }

  // 3. Set pool admins
  await waitForTx(await addressesProvider.setPoolAdmin(await getGenesisPoolAdmin(poolConfig)));
  await waitForTx(await addressesProvider.setEmergencyAdmin(await getEmergencyAdmin(poolConfig)));

  console.log('Pool Admin', await addressesProvider.getPoolAdmin());
  console.log('Emergency Admin', await addressesProvider.getEmergencyAdmin());
}
