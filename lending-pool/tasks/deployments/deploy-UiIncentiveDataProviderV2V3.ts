import { task } from 'hardhat/config';
import { eContractid } from '../../helpers/types.js';

export const deployUiIncentiveDataProviderV2V3Task = task(
  `deploy-${eContractid.UiIncentiveDataProviderV2V3}`,
  `Deploys the UiIncentiveDataProviderV2V3 contract`
)
  .addFlag({ name: 'verify', description: 'Verify UiIncentiveDataProviderV2V3 contract via Etherscan API.' })
  .setAction(() => import('../actions/deployments/data-providers/deploy-ui-incentive-data-provider-v2v3.action.js'))
  .build();
