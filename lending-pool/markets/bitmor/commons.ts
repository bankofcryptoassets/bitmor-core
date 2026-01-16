import {
  oneRay,
  ZERO_ADDRESS,
  MOCK_CHAINLINK_AGGREGATORS_PRICES,
  oneEther,
} from '../../helpers/constants.js';
import { ICommonConfiguration, eBaseNetwork, eEthereumNetwork } from '../../helpers/types.js';

export const BitmorCommonsConfig: ICommonConfiguration = {
  MarketId: 'Bitmor Lending Market',
  ATokenNamePrefix: 'Bitmor interest bearing',
  StableDebtTokenNamePrefix: 'Bitmor stable debt bearing',
  VariableDebtTokenNamePrefix: 'Bitmor variable debt bearing',
  SymbolPrefix: '',
  ProviderId: 100,
  OracleQuoteCurrency: 'USD',
  OracleQuoteUnit: oneEther.toString(),
  ProtocolGlobalParams: {
    TokenDistributorPercentageBase: '10000',
    MockUsdPriceInWei: '5848466240000000',
    UsdAddress: '0x10F7Fc1F91Ba351f9C629c5947AD69bD03C05b96',
    NilAddress: ZERO_ADDRESS,
    OneAddress: '0x0000000000000000000000000000000000000001',
    AaveReferral: '0',
  },

  Mocks: {
    AllAssetsInitialPrices: {
      ...MOCK_CHAINLINK_AGGREGATORS_PRICES,
    },
  },

  LendingRateOracleRatesCommon: {
    USDC: {
      borrowRate: oneRay.multipliedBy(0.039).toFixed(),
    },
    cbBTC: {
      borrowRate: oneRay.multipliedBy(0.03).toFixed(),
    },
  },

  PoolAdmin: {
    [eBaseNetwork.base]: undefined,
    [eBaseNetwork.sepolia]: undefined,
    [eEthereumNetwork.hardhat]: undefined,
  },
  PoolAdminIndex: 0,
  EmergencyAdmin: {
    [eBaseNetwork.base]: undefined,
    [eBaseNetwork.sepolia]: undefined,
    [eEthereumNetwork.hardhat]: undefined,
  },
  EmergencyAdminIndex: 1,
  ProviderRegistry: {
    [eBaseNetwork.base]: '',
    [eBaseNetwork.sepolia]: '0xFF8086Ff0210344535C12De39696dfd0BE641e01',
    [eEthereumNetwork.hardhat]: '',
  },
  ProviderRegistryOwner: {
    [eBaseNetwork.base]: '',
    [eBaseNetwork.sepolia]: '',
    [eEthereumNetwork.hardhat]: '',
  },
  LendingRateOracle: {
    [eBaseNetwork.base]: '',
    [eBaseNetwork.sepolia]: '',
    [eEthereumNetwork.hardhat]: '',
  },
  LendingPoolCollateralManager: {
    [eBaseNetwork.base]: '',
    [eBaseNetwork.sepolia]: '',
    [eEthereumNetwork.hardhat]: '',
  },
  LendingPoolConfigurator: {
    [eBaseNetwork.base]: '',
    [eBaseNetwork.sepolia]: '',
    [eEthereumNetwork.hardhat]: '',
  },
  LendingPool: {
    [eBaseNetwork.base]: '',
    [eBaseNetwork.sepolia]: '',
    [eEthereumNetwork.hardhat]: '',
  },
  WethGateway: {
    [eBaseNetwork.base]: '',
    [eBaseNetwork.sepolia]: '',
    [eEthereumNetwork.hardhat]: '',
  },
  TokenDistributor: {
    [eBaseNetwork.base]: '',
    [eBaseNetwork.sepolia]: '',
    [eEthereumNetwork.hardhat]: '',
  },
  AaveOracle: {
    [eBaseNetwork.base]: '',
    [eBaseNetwork.sepolia]: '',
    [eEthereumNetwork.hardhat]: '',
  },
  FallbackOracle: {
    [eBaseNetwork.base]: ZERO_ADDRESS,
    [eBaseNetwork.sepolia]: ZERO_ADDRESS,
    [eEthereumNetwork.hardhat]: ZERO_ADDRESS,
  },
  ChainlinkAggregator: {
    [eBaseNetwork.base]: {},
    [eBaseNetwork.sepolia]: {
      USDC: '0xd30e2101a97dcbAeBCBC04F14C3f624E67A35165',
      cbBTC: '0x0FB99723Aee6f420beAD13e6bBB79b7E6F034298',
    },
    [eEthereumNetwork.hardhat]: {},
  },
  ReserveAssets: {
    [eBaseNetwork.base]: {},
    [eBaseNetwork.sepolia]: {},
    [eEthereumNetwork.hardhat]: {},
  },
  ReservesConfig: {},
  ATokenDomainSeparator: {
    [eBaseNetwork.base]: '',
    [eBaseNetwork.sepolia]: '',
    [eEthereumNetwork.hardhat]: '',
  },
  WETH: {
    [eBaseNetwork.base]: '0x4200000000000000000000000000000000000006',
    [eBaseNetwork.sepolia]: '0x4200000000000000000000000000000000000006',
    [eEthereumNetwork.hardhat]: '', // deployed in local evm as mock
  },
  WrappedNativeToken: {
    [eBaseNetwork.base]: '0x4200000000000000000000000000000000000006',
    [eBaseNetwork.sepolia]: '0x4200000000000000000000000000000000000006',
    [eEthereumNetwork.hardhat]: '', // deployed in local evm as mock
  },
  ReserveFactorTreasuryAddress: {
    [eBaseNetwork.base]: '0x464c71f6c2f760dda6093dcb91c24c39e5d6e18c',
    [eBaseNetwork.sepolia]: '0x464c71f6c2f760dda6093dcb91c24c39e5d6e18c',
    [eEthereumNetwork.hardhat]: ZERO_ADDRESS,
  },
  IncentivesController: {
    [eBaseNetwork.base]: ZERO_ADDRESS,
    [eBaseNetwork.sepolia]: ZERO_ADDRESS,
    [eEthereumNetwork.hardhat]: ZERO_ADDRESS,
  },
};
