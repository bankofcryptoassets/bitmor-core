import { task } from 'hardhat/config';
import { ArgumentType } from 'hardhat/types/arguments';
import { ConfigNames } from '../../helpers/configuration.js';

export const deployDataProvider = task('full:data-provider', 'Initialize lending pool configuration.')
  .addFlag({ name: 'verify', description: 'Verify contracts at Etherscan' })
  .addOption({
    name: 'pool',
    description: `Pool name to retrieve configuration, supported: ${Object.values(ConfigNames).join(', ')}`,
    type: ArgumentType.STRING,
    defaultValue: '',
  })
  .setAction(() => import('../actions/deployments/data-providers/deploy-data-provider.action.js'))
  .build();
