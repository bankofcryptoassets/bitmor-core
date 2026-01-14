import { task } from 'hardhat/config';
import { ArgumentType } from 'hardhat/types/arguments';
import { ConfigNames } from '../../helpers/configuration.js';

export const addMarketToRegistryTask = task(
  'add-market-to-registry',
  'Adds address provider to registry'
)
  .addOption({
    name: 'pool',
    description: `Pool name to retrieve configuration, supported: ${Object.values(ConfigNames).join(', ')}`,
    type: ArgumentType.STRING,
    defaultValue: '',
  })
  .addOption({
    name: 'addressesProvider',
    description: 'Address of LendingPoolAddressProvider',
    type: ArgumentType.STRING,
    defaultValue: '',
  })
  .addFlag({ name: 'verify', description: 'Verify contracts at Etherscan' })
  .addFlag({ name: 'deployRegistry', description: 'Deploy a new address provider registry' })
  .setAction(() => import('../actions/add-market-to-registry.action.js'))
  .build();
