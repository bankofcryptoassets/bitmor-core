import { task } from 'hardhat/config';

export const bitmorDev = task('bitmor:dev', 'Deploy Bitmor development environment')
  .addFlag({ name: 'verify', description: 'Verify contracts at Etherscan' })
  .addFlag({ name: 'skipRegistry', description: 'Skip addresses provider registration at Addresses Provider Registry' })
  .setAction(() => import('../actions/bitmor-dev.action.js'))
  .build();
