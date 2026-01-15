import { task } from 'hardhat/config';
import { ArgumentType } from 'hardhat/types/arguments';
import { ConfigNames } from '../../helpers/configuration.js';

export const deployAddressProvider = task(
  'full:deploy-address-provider',
  'Deploy address provider, registry and fee provider for dev enviroment'
)
  .addFlag({ name: 'verify', description: 'Verify contracts at Etherscan' })
  .addOption({
    name: 'pool',
    description: `Pool name to retrieve configuration, supported: ${Object.values(ConfigNames).join(', ')}`,
    type: ArgumentType.STRING,
    defaultValue: '',
  })
  .addFlag({ name: 'skipRegistry', description: 'Skip registry operations' })
  .setAction(() => import('../actions/deployments/core/deploy-address-provider.action.js'))
  .build();
