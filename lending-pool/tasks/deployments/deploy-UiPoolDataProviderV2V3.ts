import { task } from 'hardhat/config';
import { eContractid } from '../../helpers/types.js';

export const deployUiPoolDataProviderV2V3Task = task(
  `deploy-${eContractid.UiPoolDataProviderV2V3}`,
  `Deploys the UiPoolDataProviderV2V3 contract`
)
  .addFlag({ name: 'verify', description: 'Verify UiPoolDataProviderV2V3 contract via Etherscan API.' })
  .setAction(() => import('../actions/deployments/data-providers/deploy-ui-pool-data-provider-v2v3.action.js'))
  .build();
