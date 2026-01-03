import type { Contract } from 'ethers';
import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { DRE } from './dre';

export const usingTenderly = () =>
  DRE &&
  ((DRE as HardhatRuntimeEnvironment).network.name.includes('tenderly') ||
    process.env.TENDERLY === 'true');

export const verifyAtTenderly = async (id: string, instance: Contract) => {
  console.log('\n- Doing Tenderly contract verification of', id);
  await (DRE as any).tenderlyNetwork.verify({
    name: id,
    address: instance.address,
  });
  console.log(`  - Verified ${id} at Tenderly!`);
};
