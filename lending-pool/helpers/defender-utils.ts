import { formatEther } from 'ethers';
import type { Signer } from 'ethers';
import type { HardhatRuntimeEnvironment } from 'hardhat/types/hre';
import { DRE, impersonateAccountsHardhat } from './misc-utils.js';
import { usingTenderly } from './tenderly-utils.js';

export const usingDefender = () => process.env.DEFENDER === 'true';

export const getDefenderRelaySigner = async () => {
  const { DEFENDER_API_KEY, DEFENDER_SECRET_KEY } = process.env;
  let defenderSigner: Signer;

  if (!DEFENDER_API_KEY || !DEFENDER_SECRET_KEY) {
    throw new Error('Defender secrets required');
  }

  // Lazy load defender packages only when needed
  const { DefenderRelaySigner, DefenderRelayProvider } = await import('defender-relay-client/lib/ethers');

  const credentials = { apiKey: DEFENDER_API_KEY, apiSecret: DEFENDER_SECRET_KEY };

  defenderSigner = new DefenderRelaySigner(credentials, new DefenderRelayProvider(credentials), {
    speed: 'fast',
  });

  const defenderAddress = await defenderSigner.getAddress();
  console.log('  - Using Defender Relay: ', defenderAddress);

  // Replace signer if FORK=main is active
  if (process.env.FORK === 'main') {
    console.log('  - Impersonating Defender Relay');
    await impersonateAccountsHardhat([defenderAddress]);
    defenderSigner = await (DRE as HardhatRuntimeEnvironment).ethers.getSigner(defenderAddress);
  }
  // Replace signer if Tenderly network is active
  if (usingTenderly()) {
    console.log('  - Impersonating Defender Relay via Tenderly');
    defenderSigner = await (DRE as HardhatRuntimeEnvironment).ethers.getSigner(defenderAddress);
  }
  console.log('  - Balance: ', formatEther(await defenderSigner.getBalance()));

  return defenderSigner;
};
