import type { HardhatRuntimeEnvironment } from 'hardhat/types/hre';
import { getParamPerNetwork, getContractAddress } from '../../helpers/contracts-helpers.js';
import { waitForTx } from '../../helpers/misc-utils.js';
import { ConfigNames, loadPoolConfig } from '../../helpers/configuration.js';
import { eNetwork } from '../../helpers/types.js';
import {
  getFirstSigner,
  getLendingPoolAddressesProvider,
  getLendingPoolAddressesProviderRegistry,
} from '../../helpers/contracts-getters.js';
import { isAddress, parseEther } from 'ethers';
import { isZeroAddress } from 'ethereumjs-util';
import type { Signer } from 'ethers';

type Args = {
  pool: string;
  addressesProvider: string;
  verify?: boolean;
  deployRegistry?: boolean;
};

export default async function addMarketToRegistryAction(
  { verify, addressesProvider, pool, deployRegistry }: Args,
  hre: HardhatRuntimeEnvironment
) {
  await hre.tasks.getTask('set-DRE').run({});

  let signer: Signer;
  const conn = await hre.network.connect();
  const network = conn.networkName as eNetwork;
  const poolConfig = loadPoolConfig(pool as ConfigNames);
  const { ProviderId } = poolConfig;

  let providerRegistryAddress = getParamPerNetwork(poolConfig.ProviderRegistry, network);
  let providerRegistryOwner = getParamPerNetwork(poolConfig.ProviderRegistryOwner, network);
  const currentSignerAddress = (
    await (await getFirstSigner()).getAddress()
  ).toLocaleLowerCase();
  let deployed = false;

  // If registry exists but owner not configured, try to get owner from registry contract
  if (
    providerRegistryAddress &&
    isAddress(providerRegistryAddress) &&
    !isZeroAddress(providerRegistryAddress) &&
    (!providerRegistryOwner || !isAddress(providerRegistryOwner) || isZeroAddress(providerRegistryOwner))
  ) {
    console.log('- Registry exists, fetching owner from registry contract...');
    try {
      const registryContract = await getLendingPoolAddressesProviderRegistry(providerRegistryAddress);
      providerRegistryOwner = await registryContract.owner();
      console.log('- Registry owner:', providerRegistryOwner);
    } catch (error) {
      console.log('- Could not fetch owner from registry, will use current signer');
      providerRegistryOwner = currentSignerAddress;
    }
  }

  if (
    deployRegistry ||
    !providerRegistryAddress ||
    !isAddress(providerRegistryAddress) ||
    isZeroAddress(providerRegistryAddress)
  ) {
    console.log('- Deploying a new Address Providers Registry:');

    await hre.tasks.getTask('full:deploy-address-provider-registry').run({ verify, pool });

    const registry = await getLendingPoolAddressesProviderRegistry();
    providerRegistryAddress = getContractAddress(registry);
    providerRegistryOwner = await (await getFirstSigner()).getAddress();
    deployed = true;
  }

  if (
    !providerRegistryOwner ||
    !isAddress(providerRegistryOwner) ||
    isZeroAddress(providerRegistryOwner)
  ) {
    throw Error('config.ProviderRegistryOwner is missing or is not an address.');
  }

  // Checks if deployer address is registry owner
  if (process.env.FORK) {
    await hre.network.provider.request({
      method: 'hardhat_impersonateAccount',
      params: [providerRegistryOwner],
    });
    signer = await conn.ethers.getSigner(providerRegistryOwner);
    const firstAccount = await getFirstSigner();
    await firstAccount.sendTransaction({ value: parseEther('10'), to: providerRegistryOwner });
  } else if (
    !deployed &&
    providerRegistryOwner.toLocaleLowerCase() !== currentSignerAddress.toLocaleLowerCase()
  ) {
    console.error('ProviderRegistryOwner config does not match current signer:');
    console.error('Expected:', providerRegistryOwner);
    console.error('Current:', currentSignerAddress);
    throw new Error('ProviderRegistryOwner mismatch');
  } else {
    signer = await conn.ethers.getSigner(providerRegistryOwner);
  }

  // 1. Address Provider Registry instance
  const addressesProviderRegistry = (
    await getLendingPoolAddressesProviderRegistry(providerRegistryAddress)
  ).connect(signer) as any;

  const addressesProviderInstance = await getLendingPoolAddressesProvider(addressesProvider);

  // 2. Set the provider at the Registry
  await waitForTx(
    await addressesProviderRegistry.registerAddressesProvider(
      getContractAddress(addressesProviderInstance),
      ProviderId
    )
  );
  console.log(
    `Added LendingPoolAddressesProvider with address "${getContractAddress(addressesProviderInstance)}" to registry located at ${getContractAddress(addressesProviderRegistry)}`
  );
}
