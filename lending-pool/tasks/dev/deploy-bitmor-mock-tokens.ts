import { task } from 'hardhat/config';

export const deployBitmorMockTokensTask = task(
  'dev:deploy-bitmor-mock-tokens',
  'Deploy Bitmor mock tokens for dev environment'
)
  .addFlag({ name: 'verify', description: 'Verify contracts at Etherscan' })
  .setAction(() => import('../actions/dev-deploy-bitmor-mock-tokens.action.js'))
  .build();
