import {
  oneRay,
  ZERO_ADDRESS,
  MOCK_CHAINLINK_AGGREGATORS_PRICES,
  oneEther,
} from '../../helpers/constants';
import { ICommonConfiguration, eBaseNetwork } from '../../helpers/types';

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
  },
  PoolAdminIndex: 0,
  EmergencyAdmin: {
    [eBaseNetwork.base]: undefined,
    [eBaseNetwork.sepolia]: undefined,
  },
  EmergencyAdminIndex: 1,
  ProviderRegistry: {
    [eBaseNetwork.base]: '',
    [eBaseNetwork.sepolia]: '',
  },
  ProviderRegistryOwner: {
    [eBaseNetwork.base]: '',
    [eBaseNetwork.sepolia]: '',
  },
  LendingRateOracle: {
    [eBaseNetwork.base]: '',
    [eBaseNetwork.sepolia]: '',
  },
  LendingPoolCollateralManager: {
    [eBaseNetwork.base]: '',
    [eBaseNetwork.sepolia]: '',
  },
  LendingPoolConfigurator: {
    [eBaseNetwork.base]: '',
    [eBaseNetwork.sepolia]: '',
  },
  LendingPool: {
    [eBaseNetwork.base]: '',
    [eBaseNetwork.sepolia]: '',
  },
  WethGateway: {
    [eBaseNetwork.base]: '',
    [eBaseNetwork.sepolia]: '',
  },
  TokenDistributor: {
    [eBaseNetwork.base]: '',
    [eBaseNetwork.sepolia]: '',
  },
  AaveOracle: {
    [eBaseNetwork.base]: '',
    [eBaseNetwork.sepolia]: '',
  },
  FallbackOracle: {
    [eBaseNetwork.base]: ZERO_ADDRESS,
    [eBaseNetwork.sepolia]: ZERO_ADDRESS,
  },
  ChainlinkAggregator: {
    [eBaseNetwork.base]: {},
    [eBaseNetwork.sepolia]: {
      USDC: '0x45EA2E641164835014F46B70F011504FD22ec19A',
      cbBTC: '0xC6F89E85Ce021cf8Ab900EbD51579710EE91bb2F',
    },
  },
  ReserveAssets: {
    [eBaseNetwork.base]: {},
    [eBaseNetwork.sepolia]: {},
  },
  ReservesConfig: {},
  ATokenDomainSeparator: {
    [eBaseNetwork.base]: '',
    [eBaseNetwork.sepolia]: '',
  },
  WETH: {
    [eBaseNetwork.base]: '',
    [eBaseNetwork.sepolia]: '',
  },
  WrappedNativeToken: {
    [eBaseNetwork.base]: '',
    [eBaseNetwork.sepolia]: '',
  },
  ReserveFactorTreasuryAddress: {
    [eBaseNetwork.base]: '0x464c71f6c2f760dda6093dcb91c24c39e5d6e18c',
    [eBaseNetwork.sepolia]: '0x464c71f6c2f760dda6093dcb91c24c39e5d6e18c',
  },
  IncentivesController: {
    [eBaseNetwork.base]: ZERO_ADDRESS,
    [eBaseNetwork.sepolia]: ZERO_ADDRESS,
  },
};
