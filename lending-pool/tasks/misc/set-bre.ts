import { task } from 'hardhat/config';

export const setDRETask = task(`set-DRE`, `Inits the DRE, to have access to all the plugins' objects`)
  .setAction(() => import('../actions/set-dre.action.js'))
  .build();
