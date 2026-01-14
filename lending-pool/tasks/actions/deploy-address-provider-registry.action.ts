import { formatEther } from 'ethers';
import type { HardhatRuntimeEnvironment } from 'hardhat/types/hre';
import { ConfigNames, loadPoolConfig } from '../../helpers/configuration.js';
import { deployLendingPoolAddressesProviderRegistry } from '../../helpers/contracts-deployments.js';
import { getFirstSigner } from '../../helpers/contracts-getters.js';
import { getParamPerNetwork, getContractAddress } from '../../helpers/contracts-helpers.js';
import { notFalsyOrZeroAddress } from '../../helpers/misc-utils.js';
import { eNetwork } from '../../helpers/types.js';

type Args = {
  verify: boolean;
  pool: string;
};

export default async function deployAddressProviderRegistryAction(
  { verify, pool }: Args,
  hre: HardhatRuntimeEnvironment
) {
  console.log('prior dre');
  await hre.tasks.getTask('set-DRE').run({});

  // Validate pool name
  if (!pool || !Object.values(ConfigNames).includes(pool as ConfigNames)) {
    throw new Error(
      `Invalid --pool "${pool}". Supported: ${Object.values(ConfigNames).join(', ')}`
    );
  }

  const poolConfig = loadPoolConfig(pool as ConfigNames);
  const conn = await hre.network.connect();
  const network = conn.networkName as eNetwork;

  const signer = await getFirstSigner();
  const addr = await signer.getAddress();

  // ethers v6: balance comes from provider, not signer
  // HH3: get provider from conn.ethers or conn.provider
  const provider = (conn as any).ethers?.provider || conn.provider;
  const balance = await provider.getBalance(addr);

  const latestNonce = await provider.getTransactionCount(addr, "latest");
  const pendingNonce = await provider.getTransactionCount(addr, "pending");

  console.log("Nonce latest:", latestNonce, "pending:", pendingNonce);

  console.log('Deployer:', addr, formatEther(balance));

  const providerRegistryAddress = getParamPerNetwork(poolConfig.ProviderRegistry, network);

  console.log('Signer', addr);
  console.log('Balance', formatEther(balance));

  

  if (notFalsyOrZeroAddress(providerRegistryAddress)) {
    console.log('Already deployed Provider Registry Address at', providerRegistryAddress);
  } else {
    const contract = await deployLendingPoolAddressesProviderRegistry(verify);
    console.log('Deployed Registry Address:', getContractAddress(contract));
  }
}
