import type { HardhatRuntimeEnvironment } from 'hardhat/types/hre';
import { deployBitmorMockTokens } from '../../../../helpers/contracts-deployments.js';

type Args = {
  verify: boolean;
};

export default async function devDeployBitmorMockTokensAction(
  { verify }: Args,
  hre: HardhatRuntimeEnvironment
) {
  await hre.tasks.getTask('set-DRE').run({});

  console.log('Deploying Bitmor mock tokens for development...');
  const tokens = await deployBitmorMockTokens(verify);

  console.log('Mock tokens deployed:');
  console.log('  - bUSDC:', tokens['bUSDC'].target || tokens['bUSDC'].target);
  console.log('  - bcbBTC:', tokens['bcbBTC'].target || tokens['bcbBTC'].target);

  return tokens;
}
