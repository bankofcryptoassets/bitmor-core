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
  // mainnet
  if (network === 'base') {
    return '0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf';
  }

  // For testnet (sepolia): fetch mock cbBTC from loan-provider
  if (network === 'sepolia') {
    try {
      const fs = await import('fs');
      const path = await import('path');

      const loanProviderPath = path.join(process.cwd(), '../loan-provider/deployments.json');

      if (fs.existsSync(loanProviderPath)) {
        const deploymentsContent = fs.readFileSync(loanProviderPath, 'utf8');
        const deployments = JSON.parse(deploymentsContent);

        const chainId = await getChainIdFromNetwork(network);
        const cbBTCMock = deployments.deployments?.[chainId]?.networkConfig?.cbBTC;

        if (cbBTCMock) {
          return cbBTCMock;
        }
      }

      throw new Error(
        `cbBTC mock not found in loan-provider deployments for sepolia. ` +
        `Please ensure loan-provider mocks are deployed and cbBTC field exists.`
      );
    } catch (error) {
      throw new Error(`Failed to load cbBTC mock for sepolia: ${error}`);
    }
  }

  // For hardhat (non-fork): fetch from database
  if (network === 'hardhat' && !process.env.FORK) {
    const db = getDb();
    const actualNetwork = DRE.network.networkName;
    const bcbBTC = db.get(`bcbBTC.${actualNetwork}`).value()?.address;
    if (bcbBTC) {
      return bcbBTC;
    }
    throw new Error(
      `bcbBTC address not found in database for local network ${actualNetwork}. ` +
      `Please ensure bcbBTC mock is deployed.`
    );
  }

  // For fork: return real cbBTC address (same as mainnet)
  if (process.env.FORK === 'base') {
    return '0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf';
  }

  throw new Error(`cbBTC address not configured for network ${network}.`);
};

export const getBvBTCAddress = async (
  config: PoolConfiguration,
  network: eNetwork
): Promise<tEthereumAddress> => {
  let bvBTCAddress: string | undefined;

  try {
    const fs = await import('fs');
    const path = await import('path');

    const loanProviderPath = path.join(process.cwd(), '../loan-provider/deployments.json');

    if (fs.existsSync(loanProviderPath)) {
      const deploymentsContent = fs.readFileSync(loanProviderPath, 'utf8');
      const deployments = JSON.parse(deploymentsContent);

      const chainId = await getChainIdFromNetwork(network);
      const collateralAsset =
        deployments.deployments?.[chainId]?.networkConfig?.collateralAsset;

      if (collateralAsset) bvBTCAddress = collateralAsset;
    } else {
      console.warn(`loan-provider deployments.json not found at: ${loanProviderPath}`);
    }
  } catch (error) {
    console.warn('Could not load bvBTC from loan-provider deployments:', error);
  }

  if (!bvBTCAddress || bvBTCAddress === '') {
    throw new Error(
      `bvBTC address not found for network ${network}. ` +
      `Please ensure loan-provider is deployed first and deployments.json exists at ../loan-provider/deployments.json`
    );
  }

  return bvBTCAddress;
};

export const getBUSDCAddress = async (
  config: PoolConfiguration,
  network: eNetwork
): Promise<tEthereumAddress> => {
  let bUSDCAddress: string | undefined;

  try {
    const fs = await import('fs');
    const path = await import('path');

    const loanProviderPath = path.join(process.cwd(), '../loan-provider/deployments.json');

    if (fs.existsSync(loanProviderPath)) {
      const deploymentsContent = fs.readFileSync(loanProviderPath, 'utf8');
      const deployments = JSON.parse(deploymentsContent);

      const chainId = await getChainIdFromNetwork(network);
      const debtAsset = deployments.deployments?.[chainId]?.networkConfig?.debtAsset;

      if (debtAsset) bUSDCAddress = debtAsset;
    } else {
      console.warn(`loan-provider deployments.json not found at: ${loanProviderPath}`);
    }
  } catch (error) {
    console.warn('Could not load bUSDC from loan-provider deployments:', error);
  }

  if (!bUSDCAddress || bUSDCAddress === '') {
    throw new Error(
      `bUSDC address not found for network ${network}. ` +
        `Please ensure loan-provider is deployed first and deployments.json exists at ../loan-provider/deployments.json`
    );
  }

  return bUSDCAddress;
};

const getChainIdFromNetwork = async (network: eNetwork): Promise<string> => {
  if (process.env.FORK) {
    // Anvil fork runs with --chain-id 31337; append "-fork" to distinguish from local
    return '31337-fork';
  }

  const chainIds: { [key: string]: string } = {
    'sepolia': '84532',
    'base': '8453',
    'hardhat': '31337',
    'localhost': '31337',
  };

  return chainIds[network] || '31337';
};
