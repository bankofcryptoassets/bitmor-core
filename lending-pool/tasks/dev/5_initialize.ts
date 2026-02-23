import { task } from 'hardhat/config';
import { ArgumentType } from 'hardhat/types/arguments';

export const devInitializeLendingPoolTask = task(
  'dev:initialize-lending-pool',
  'Initialize lending pool configuration for dev/localhost'
)
  .addFlag({ name: 'verify', description: 'Verify contracts at Etherscan' })
  .addOption({
    name: 'pool',
    description: 'Pool name to retrieve configuration',
    type: ArgumentType.STRING,
    defaultValue: '',
  })
  .setAction(() => import('../actions/initialization/dev-initialize-lending-pool.action.js'))
  .build();
