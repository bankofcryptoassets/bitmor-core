import { task } from 'hardhat/config';
import { ArgumentType } from 'hardhat/types/arguments';
import { ConfigNames } from '../../helpers/configuration.js';

export const deployLendingPool = task(
  'full:deploy-lending-pool',
  'Deploy lending pool for dev enviroment'
)
  .addFlag({ name: 'verify', description: 'Verify contracts at Etherscan' })
  .addOption({
    name: 'pool',
    description: `Pool name to retrieve configuration, supported: ${Object.values(ConfigNames).join(', ')}`,
    type: ArgumentType.STRING,
    defaultValue: '',
  })
  .setAction(() => import('../actions/deployments/core/deploy-lending-pool.action.js'))
  .build();
