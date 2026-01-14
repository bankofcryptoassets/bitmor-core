import { task } from 'hardhat/config';
import { ArgumentType } from 'hardhat/types/arguments';
import { ConfigNames } from '../../helpers/configuration.js';

export const deployAddressProviderRegistry = task(
  'full:deploy-address-provider-registry',
  'Deploy address provider registry'
)
  .addFlag({ name: 'verify', description: 'Verify contracts at Etherscan' })
  .addOption({
    name: 'pool',
    description: `Pool name to retrieve configuration, supported: ${Object.values(ConfigNames).join(', ')}`,
    type: ArgumentType.STRING,
    defaultValue: '',
  })
  .setAction(() => import('../actions/deploy-address-provider-registry.action.js'))
  .build();
