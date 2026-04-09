import { AavePools } from './types.js';
import type {
  iMultiPoolsAssets,
  IReserveParams,
  PoolConfiguration,
  eNetwork,
  IBaseConfiguration,
  tEthereumAddress,
} from './types.js';
import { getEthersSignersAddresses, getParamPerPool } from './contracts-helpers.js';
import AaveConfig from '../markets/aave/index.js';
import MaticConfig from '../markets/matic/index.js';
import AvalancheConfig from '../markets/avalanche/index.js';
import AmmConfig from '../markets/amm/index.js';
import BitmorConfig from '../markets/bitmor/index.js';

import { CommonsConfig } from '../markets/aave/commons.js';
import { DRE, filterMapBy, getDb } from './misc-utils.js';
import { getParamPerNetwork } from './contracts-helpers.js';
// import { deployWETHMocked } from './contracts-deployments'; // Removed to break circular dependency

import fs from 'fs';
import path from 'path';

/**
 * Read a value from the unified deployment registry at `../deployments/<chainKey>/latest.json`.
 * Returns `null` if the file doesn't exist or the path is unresolvable.
 */
function readFromRegistry(chainKey: string, dotPath: string): string | null {
  const registryPath = path.join(process.cwd(), '../deployments', chainKey, 'latest.json');
  if (!fs.existsSync(registryPath)) return null;
  const json = JSON.parse(fs.readFileSync(registryPath, 'utf-8'));
  const parts = dotPath.split('.');
  let current: any = json;
  for (const part of parts) {
    current = current?.[part];
  }
  return current ?? null;
}

/**
 * Map a Hardhat network name to the chain key used in the deployment registry.
 * When `FORK` env is set, appends `-fork` to distinguish fork deployments.
 */
function getChainKeyFromNetwork(network: string): string {
  const map: Record<string, string> = {
    'sepolia': '84532',
    'base': '8453',
    'hardhat': '31337',
    'localhost': '31337',
  };
  const fork = process.env.FORK;
  const chainId = map[network] ?? '31337';
  return fork ? `${chainId}-fork` : chainId;
}

export enum ConfigNames {
  Commons = 'Commons',
  Aave = 'Aave',
  Matic = 'Matic',
  Amm = 'Amm',
  Avalanche = 'Avalanche',
  Bitmor = 'Bitmor',
}

export const loadPoolConfig = (configName: ConfigNames): PoolConfiguration => {
  switch (configName) {
    case ConfigNames.Aave:
      return AaveConfig;
    case ConfigNames.Matic:
      return MaticConfig;
    case ConfigNames.Amm:
      return AmmConfig;
    case ConfigNames.Avalanche:
      return AvalancheConfig;
    case ConfigNames.Bitmor:
      return BitmorConfig;
    case ConfigNames.Commons:
      return CommonsConfig;
    default:
      throw new Error(
        `Unsupported pool configuration: ${configName} is not one of the supported configs ${Object.values(
          ConfigNames
        )}`
      );
  }
};

// ----------------
// PROTOCOL PARAMS PER POOL
// ----------------

export const getReservesConfigByPool = (pool: AavePools): iMultiPoolsAssets<IReserveParams> =>
  getParamPerPool<iMultiPoolsAssets<IReserveParams>>(
    {
      [AavePools.proto]: {
        ...AaveConfig.ReservesConfig,
      },
      [AavePools.amm]: {
        ...AmmConfig.ReservesConfig,
      },
      [AavePools.matic]: {
        ...MaticConfig.ReservesConfig,
      },
      [AavePools.avalanche]: {
        ...AvalancheConfig.ReservesConfig,
      },
    },
    pool
  );

export const getGenesisPoolAdmin = async (
  config: IBaseConfiguration
): Promise<tEthereumAddress> => {
  const currentNetwork = process.env.FORK ? process.env.FORK : DRE.network.networkName;
  const targetAddress = getParamPerNetwork(config.PoolAdmin, <eNetwork>currentNetwork);
  if (targetAddress) {
    return targetAddress;
  }
  const addressList = await getEthersSignersAddresses();
  const addressIndex = config.PoolAdminIndex;
  return addressList[addressIndex];
};

export const getEmergencyAdmin = async (config: IBaseConfiguration): Promise<tEthereumAddress> => {
  const currentNetwork = process.env.FORK ? process.env.FORK : DRE.network.networkName;
  const targetAddress = getParamPerNetwork(config.EmergencyAdmin, <eNetwork>currentNetwork);
  if (targetAddress) {
    return targetAddress;
  }
  const addressList = await getEthersSignersAddresses();
  const addressIndex = config.EmergencyAdminIndex;
  return addressList[addressIndex];
};

export const getTreasuryAddress = async (config: IBaseConfiguration): Promise<tEthereumAddress> => {
  const currentNetwork = process.env.FORK ? process.env.FORK : DRE.network.networkName;
  return getParamPerNetwork(config.ReserveFactorTreasuryAddress, <eNetwork>currentNetwork);
};

export const getATokenDomainSeparatorPerNetwork = (
  network: eNetwork,
  config: IBaseConfiguration
): tEthereumAddress => getParamPerNetwork<tEthereumAddress>(config.ATokenDomainSeparator, network);

export const getWethAddress = async (config: IBaseConfiguration) => {
  const currentNetwork = process.env.FORK ? process.env.FORK : DRE.network.networkName;
  const wethAddress = getParamPerNetwork(config.WETH, <eNetwork>currentNetwork);
  if (wethAddress) {
    return wethAddress;
  }
  if (currentNetwork.includes('main')) {
    throw new Error('WETH not set at mainnet configuration.');
  }
  // const weth = await deployWETHMocked(); // Commented to break circular dependency
  // return weth.address;
  throw new Error('WETH address must be configured - auto-deployment removed to break circular dependency');
};

export const getWrappedNativeTokenAddress = async (config: IBaseConfiguration) => {
  const currentNetwork = process.env.MAINNET_FORK === 'true' ? 'main' : DRE.network.networkName;
  const wethAddress = getParamPerNetwork(config.WrappedNativeToken, <eNetwork>currentNetwork);

  // If wethAddress is set and not empty string, return it
  if (wethAddress && wethAddress !== '') {
    return wethAddress;
  }

  if (currentNetwork.includes('main')) {
    throw new Error('WETH not set at mainnet configuration.');
  }

  // For local networks, try to get WETH from deployed contracts database
  const db = getDb();
  const deployedWeth = db.get(`WETH.${currentNetwork}`).value();
  if (deployedWeth?.address) {
    return deployedWeth.address;
  }

  throw new Error('WETH address must be configured - auto-deployment removed to break circular dependency');
};

export const getLendingRateOracles = (poolConfig: IBaseConfiguration) => {
  const {
    ProtocolGlobalParams: { UsdAddress },
    LendingRateOracleRatesCommon,
    ReserveAssets,
  } = poolConfig;

  const network = process.env.FORK ? process.env.FORK : DRE.network.networkName;
  const reserveAssets = ReserveAssets[network];

  // If network doesn't have ReserveAssets configured, return empty
  if (!reserveAssets) {
    return {};
  }

  return filterMapBy(LendingRateOracleRatesCommon, (key) =>
    Object.keys(reserveAssets).includes(key)
  );
};

export const getQuoteCurrency = async (config: IBaseConfiguration) => {
  switch (config.OracleQuoteCurrency) {
    case 'ETH':
    case 'WETH':
      return getWethAddress(config);
    case 'USD':
      return config.ProtocolGlobalParams.UsdAddress;
    default:
      throw `Quote ${config.OracleQuoteCurrency} currency not set. Add a new case to getQuoteCurrency switch`;
  }
};

export const getBcbBTCAddress = async (
  config: PoolConfiguration,
  network: eNetwork
): Promise<tEthereumAddress> => {
  // mainnet — hardcoded
  if (network === 'base') {
    return '0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf';
  }

  // For fork of base mainnet: return real cbBTC address
  if (process.env.FORK === 'base') {
    return '0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf';
  }

  // Try unified deployment registry first
  const chainKey = getChainKeyFromNetwork(network);
  const registryAddress = readFromRegistry(chainKey, 'tokens.cbBTC');
  if (registryAddress) {
    return registryAddress;
  }

  // Fallback: hardhat database (non-fork local)
  if (network === 'hardhat' && !process.env.FORK) {
    const db = getDb();
    const actualNetwork = DRE.network.networkName;
    const bcbBTC = db.get(`bcbBTC.${actualNetwork}`).value()?.address;
    if (bcbBTC) {
      return bcbBTC;
    }
  }

  throw new Error(
    `cbBTC address not found for network ${network}. ` +
    `Ensure deployments exist at ../deployments/${chainKey}/latest.json or bcbBTC is in the local database.`
  );
};

export const getBvBTCAddress = async (
  config: PoolConfiguration,
  network: eNetwork
): Promise<tEthereumAddress> => {
  // Try unified deployment registry first
  const chainKey = getChainKeyFromNetwork(network);
  const registryAddress = readFromRegistry(chainKey, 'loanProvider.btcVault');
  if (registryAddress) {
    return registryAddress;
  }

  throw new Error(
    `bvBTC address not found for network ${network}. ` +
    `Ensure deployments exist at ../deployments/${chainKey}/latest.json with loanProvider.btcVault.`
  );
};

export const getUSDCAddress = async (
  config: PoolConfiguration,
  network: eNetwork
): Promise<tEthereumAddress> => {
  // Try unified deployment registry first
  const chainKey = getChainKeyFromNetwork(network);
  const registryAddress = readFromRegistry(chainKey, 'tokens.usdc');
  if (registryAddress) {
    return registryAddress;
  }

  throw new Error(
    `USDC address not found for network ${network}. ` +
    `Ensure deployments exist at ../deployments/${chainKey}/latest.json with tokens.usdc.`
  );
};

/**
 * Returns oracle aggregator addresses from the unified deployment registry.
 * On testnet, these are ChainlinkOracleWrapper addresses deployed by loan-provider Phase 1.
 * Falls back to ChainlinkAggregator from pool config if registry has no entries.
 */
export const getOracleAggregatorsFromRegistry = (
  network: eNetwork
): { [symbol: string]: string } | null => {
  const chainKey = getChainKeyFromNetwork(network);
  const btcOracle = readFromRegistry(chainKey, 'external.btcOracle');
  const usdcOracle = readFromRegistry(chainKey, 'external.usdcOracle');

  if (!btcOracle || !usdcOracle) return null;

  return {
    USDC: usdcOracle,
    bvBTC: btcOracle,
  };
};
