import type { Contract } from 'ethers';
import type { HardhatRuntimeEnvironment } from 'hardhat/types/hre';
import { DRE } from './dre.js';

export const usingTenderly = () =>
  DRE &&
  ((DRE as HardhatRuntimeEnvironment).network.networkName?.includes('tenderly') ||
    process.env.TENDERLY === 'true');

export const verifyAtTenderly = async (id: string, instance: Contract) => {
  console.log('\n- Doing Tenderly contract verification of', id);
  await (DRE as any).tenderlyNetwork.verify({
    name: id,
    address: instance.address,
  });
  console.log(`  - Verified ${id} at Tenderly!`);
};
