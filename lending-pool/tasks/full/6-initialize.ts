import { task } from 'hardhat/config';
import { ArgumentType } from 'hardhat/types/arguments';
import { ConfigNames } from '../../helpers/configuration.js';

export const initializeLendingPool = task('full:initialize-lending-pool', 'Initialize lending pool configuration.')
  .addFlag({ name: 'verify', description: 'Verify contracts at Etherscan' })
  .addOption({
    name: 'pool',
    description: `Pool name to retrieve configuration, supported: ${Object.values(ConfigNames).join(', ')}`,
    type: ArgumentType.STRING,
    defaultValue: '',
  })
  .setAction(() => import('../actions/initialize-lending-pool.action.js'))
  .build();
