import { task } from 'hardhat/config';
import { ArgumentType } from 'hardhat/types/arguments';
import { ConfigNames } from '../../helpers/configuration.js';

const CONTRACT_NAME = 'WETHGateway';

export const deployWethGateway = task(`full-deploy-weth-gateway`, `Deploys the ${CONTRACT_NAME} contract`)
  .addOption({
    name: 'pool',
    description: `Pool name to retrieve configuration, supported: ${Object.values(ConfigNames).join(', ')}`,
    type: ArgumentType.STRING,
    defaultValue: '',
  })
  .addFlag({ name: 'verify', description: `Verify ${CONTRACT_NAME} contract via Etherscan API.` })
  .setAction(() => import('../actions/deployments/core/deploy-weth-gateway.action.js'))
  .build();
