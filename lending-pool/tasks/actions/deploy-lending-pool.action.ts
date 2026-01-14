import type { HardhatRuntimeEnvironment } from 'hardhat/types/hre';
import { getParamPerNetwork, insertContractAddressInDb, getContractAddress } from '../../helpers/contracts-helpers.js';
import {
  deployATokenImplementations,
  deployATokensAndRatesHelper,
  deployLendingPool,
  deployLendingPoolConfigurator,
  deployStableAndVariableTokensHelper,
} from '../../helpers/contracts-deployments.js';
import { eContractid, eNetwork } from '../../helpers/types.js';
import { notFalsyOrZeroAddress, waitForTx } from '../../helpers/misc-utils.js';
import {
  getLendingPoolAddressesProvider,
  getLendingPool,
  getLendingPoolConfiguratorProxy,
} from '../../helpers/contracts-getters.js';
import {
  loadPoolConfig,
  ConfigNames,
  getEmergencyAdmin,
} from '../../helpers/configuration.js';

type Args = {
  verify: boolean;
  pool: string;
};

export default async function deployLendingPoolAction(
  { verify, pool }: Args,
  hre: HardhatRuntimeEnvironment
) {
  try {
    await hre.tasks.getTask('set-DRE').run({});

    // Validate pool name
    if (!pool || !Object.values(ConfigNames).includes(pool as ConfigNames)) {
      throw new Error(
        `Invalid --pool "${pool}". Supported: ${Object.values(ConfigNames).join(', ')}`
      );
    }

    const conn = await hre.network.connect();
    const network = conn.networkName as eNetwork;
    const poolConfig = loadPoolConfig(pool as ConfigNames);
    const addressesProvider = await getLendingPoolAddressesProvider();

    const { LendingPool, LendingPoolConfigurator } = poolConfig;

    // Reuse/deploy lending pool implementation
    let lendingPoolImplAddress = getParamPerNetwork(LendingPool, network);
    if (!notFalsyOrZeroAddress(lendingPoolImplAddress)) {
      console.log('\tDeploying new lending pool implementation & libraries...');
      const lendingPoolImpl = await deployLendingPool(verify);
      lendingPoolImplAddress = getContractAddress(lendingPoolImpl);
      await lendingPoolImpl.initialize(getContractAddress(addressesProvider));
    }
    console.log('\tSetting lending pool implementation with address:', lendingPoolImplAddress);
    // Set lending pool impl to Address provider
    await waitForTx(await addressesProvider.setLendingPoolImpl(lendingPoolImplAddress));

    const address = await addressesProvider.getLendingPool();
    const lendingPoolProxy = await getLendingPool(address);

    await insertContractAddressInDb(eContractid.LendingPool, getContractAddress(lendingPoolProxy));

    // Reuse/deploy lending pool configurator
    let lendingPoolConfiguratorImplAddress = getParamPerNetwork(LendingPoolConfigurator, network);
    if (!notFalsyOrZeroAddress(lendingPoolConfiguratorImplAddress)) {
      console.log('\tDeploying new configurator implementation...');
      const lendingPoolConfiguratorImpl = await deployLendingPoolConfigurator(verify);
      lendingPoolConfiguratorImplAddress = getContractAddress(lendingPoolConfiguratorImpl);
    }
    console.log(
      '\tSetting lending pool configurator implementation with address:',
      lendingPoolConfiguratorImplAddress
    );
    // Set lending pool conf impl to Address Provider
    await waitForTx(
      await addressesProvider.setLendingPoolConfiguratorImpl(lendingPoolConfiguratorImplAddress)
    );

    const lendingPoolConfiguratorProxy = await getLendingPoolConfiguratorProxy(
      await addressesProvider.getLendingPoolConfigurator()
    );

    await insertContractAddressInDb(
      eContractid.LendingPoolConfigurator,
      getContractAddress(lendingPoolConfiguratorProxy)
    );

    // ethers v6: getSigner from connection ethers
    const adminAddress = await getEmergencyAdmin(poolConfig);
    const admin = await (conn as any).ethers.getSigner(adminAddress);

    // Pause market during deployment
    await waitForTx(await lendingPoolConfiguratorProxy.connect(admin).setPoolPause(true));

    // Deploy deployment helpers
    await deployStableAndVariableTokensHelper(
      [getContractAddress(lendingPoolProxy), getContractAddress(addressesProvider)],
      verify
    );
    await deployATokensAndRatesHelper(
      [
        getContractAddress(lendingPoolProxy),
        getContractAddress(addressesProvider),
        getContractAddress(lendingPoolConfiguratorProxy),
      ],
      verify
    );
    await deployATokenImplementations(pool as ConfigNames, poolConfig.ReservesConfig, verify);
  } catch (error) {
    const conn = await hre.network.connect();
    if (conn.networkName.includes('tenderly')) {
      const tenderlyAny = (hre as any).tenderly;
      const configAny = (hre.config as any).tenderly;
      if (tenderlyAny?.network && configAny?.username && configAny?.project) {
        try {
          const transactionLink = `https://dashboard.tenderly.co/${configAny.username}/${
            configAny.project
          }/fork/${tenderlyAny.network().getFork()}/simulation/${tenderlyAny.network().getHead()}`;
          console.error('Check tx error:', transactionLink);
        } catch (e) {
          // Ignore if tenderly network methods fail
        }
      }
    }
    throw error;
  }
}
