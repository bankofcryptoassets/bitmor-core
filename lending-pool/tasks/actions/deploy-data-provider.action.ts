import type { HardhatRuntimeEnvironment } from 'hardhat/types/hre';
import { deployAaveProtocolDataProvider } from '../../helpers/contracts-deployments.js';
import { getLendingPoolAddressesProvider } from '../../helpers/contracts-getters.js';
import { getContractAddress } from '../../helpers/contracts-helpers.js';

type Args = {
  verify: boolean;
};

export default async function deployDataProviderAction(
  { verify }: Args,
  hre: HardhatRuntimeEnvironment
) {
  try {
    await hre.tasks.getTask('set-DRE').run({});

    const addressesProvider = await getLendingPoolAddressesProvider();

    await deployAaveProtocolDataProvider(getContractAddress(addressesProvider), verify);
  } catch (err) {
    console.error(err);
    throw err;
  }
}
