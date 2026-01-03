import {
  AaveProtocolDataProvider__factory,
  AToken__factory,
  ATokensAndRatesHelper__factory,
  AaveOracle__factory,
  DefaultReserveInterestRateStrategy__factory,
  GenericLogic__factory,
  InitializableAdminUpgradeabilityProxy__factory,
  LendingPoolAddressesProvider__factory,
  LendingPoolAddressesProviderRegistry__factory,
  LendingPoolCollateralManager__factory,
  LendingPoolConfigurator__factory,
  LendingPool__factory,
  LendingRateOracle__factory,
  MintableERC20__factory,
  MockAToken__factory,
  MockFlashLoanReceiver__factory,
  MockStableDebtToken__factory,
  MockVariableDebtToken__factory,
  MockUniswapV2Router02__factory,
  MockParaSwapAugustus__factory,
  MockParaSwapAugustusRegistry__factory,
  ParaSwapLiquiditySwapAdapter__factory,
  PriceOracle__factory,
  ReserveLogic__factory,
  SelfdestructTransfer__factory,
  StableAndVariableTokensHelper__factory,
  StableDebtToken__factory,
  UniswapLiquiditySwapAdapter__factory,
  UniswapRepayAdapter__factory,
  VariableDebtToken__factory,
  WalletBalanceProvider__factory,
  WETH9Mocked__factory,
  WETHGateway__factory,
  FlashLiquidationAdapter__factory,
  IERC20Detailed__factory,
} from '../types/ethers-contracts/index.js';
import { getEthersSigners, MockTokenMap, getFirstSigner } from './contracts-helpers';
import { DRE, getDb, notFalsyOrZeroAddress, omit } from './misc-utils';
import { eContractid, TokenContractId } from './types.js';
import type { PoolConfiguration, tEthereumAddress } from './types.js';

// Re-export for backward compatibility
export { getFirstSigner };

export const getLendingPoolAddressesProvider = async (address?: tEthereumAddress) => {
  return await LendingPoolAddressesProvider__factory.connect(
    address ||
      (
        await getDb().get(`${eContractid.LendingPoolAddressesProvider}.${DRE.network.name}`).value()
      ).address,
    await getFirstSigner()
  );
};
export const getLendingPoolConfiguratorProxy = async (address?: tEthereumAddress) => {
  return await LendingPoolConfigurator__factory.connect(
    address ||
      (
        await getDb().get(`${eContractid.LendingPoolConfigurator}.${DRE.network.name}`).value()
      ).address,
    await getFirstSigner()
  );
};

export const getLendingPool = async (address?: tEthereumAddress) =>
  await LendingPool__factory.connect(
    address ||
      (
        await getDb().get(`${eContractid.LendingPool}.${DRE.network.name}`).value()
      ).address,
    await getFirstSigner()
  );

export const getPriceOracle = async (address?: tEthereumAddress) =>
  await PriceOracle__factory.connect(
    address ||
      (
        await getDb().get(`${eContractid.PriceOracle}.${DRE.network.name}`).value()
      ).address,
    await getFirstSigner()
  );

export const getAToken = async (address?: tEthereumAddress) =>
  await AToken__factory.connect(
    address || (await getDb().get(`${eContractid.AToken}.${DRE.network.name}`).value()).address,
    await getFirstSigner()
  );

export const getStableDebtToken = async (address?: tEthereumAddress) =>
  await StableDebtToken__factory.connect(
    address ||
      (
        await getDb().get(`${eContractid.StableDebtToken}.${DRE.network.name}`).value()
      ).address,
    await getFirstSigner()
  );

export const getVariableDebtToken = async (address?: tEthereumAddress) =>
  await VariableDebtToken__factory.connect(
    address ||
      (
        await getDb().get(`${eContractid.VariableDebtToken}.${DRE.network.name}`).value()
      ).address,
    await getFirstSigner()
  );

export const getMintableERC20 = async (address: tEthereumAddress) =>
  await MintableERC20__factory.connect(
    address ||
      (
        await getDb().get(`${eContractid.MintableERC20}.${DRE.network.name}`).value()
      ).address,
    await getFirstSigner()
  );

export const getIErc20Detailed = async (address: tEthereumAddress) =>
  await IERC20Detailed__factory.connect(
    address ||
      (
        await getDb().get(`${eContractid.IERC20Detailed}.${DRE.network.name}`).value()
      ).address,
    await getFirstSigner()
  );

export const getAaveProtocolDataProvider = async (address?: tEthereumAddress) =>
  await AaveProtocolDataProvider__factory.connect(
    address ||
      (
        await getDb().get(`${eContractid.AaveProtocolDataProvider}.${DRE.network.name}`).value()
      ).address,
    await getFirstSigner()
  );

export const getInterestRateStrategy = async (address?: tEthereumAddress) =>
  await DefaultReserveInterestRateStrategy__factory.connect(
    address ||
      (
        await getDb()
          .get(`${eContractid.DefaultReserveInterestRateStrategy}.${DRE.network.name}`)
          .value()
      ).address,
    await getFirstSigner()
  );

export const getMockFlashLoanReceiver = async (address?: tEthereumAddress) =>
  await MockFlashLoanReceiver__factory.connect(
    address ||
      (
        await getDb().get(`${eContractid.MockFlashLoanReceiver}.${DRE.network.name}`).value()
      ).address,
    await getFirstSigner()
  );

export const getLendingRateOracle = async (address?: tEthereumAddress) =>
  await LendingRateOracle__factory.connect(
    address ||
      (
        await getDb().get(`${eContractid.LendingRateOracle}.${DRE.network.name}`).value()
      ).address,
    await getFirstSigner()
  );

export const getMockedTokens = async (config: PoolConfiguration) => {
  const tokenSymbols = Object.keys(config.ReservesConfig);
  const db = getDb();
  const tokens: MockTokenMap = await tokenSymbols.reduce<Promise<MockTokenMap>>(
    async (acc, tokenSymbol) => {
      const accumulator = await acc;
      const address = db.get(`${tokenSymbol.toUpperCase()}.${DRE.network.name}`).value().address;
      accumulator[tokenSymbol] = await getMintableERC20(address);
      return Promise.resolve(acc);
    },
    Promise.resolve({})
  );
  return tokens;
};

export const getAllMockedTokens = async () => {
  const db = getDb();
  const tokens: MockTokenMap = await Object.keys(TokenContractId).reduce<Promise<MockTokenMap>>(
    async (acc, tokenSymbol) => {
      const accumulator = await acc;
      const address = db.get(`${tokenSymbol.toUpperCase()}.${DRE.network.name}`).value().address;
      accumulator[tokenSymbol] = await getMintableERC20(address);
      return Promise.resolve(acc);
    },
    Promise.resolve({})
  );
  return tokens;
};

export const getQuoteCurrencies = (oracleQuoteCurrency: string): string[] => {
  switch (oracleQuoteCurrency) {
    case 'USD':
      return ['USD'];
    case 'ETH':
    case 'WETH':
    default:
      return ['ETH', 'WETH'];
  }
};

export const getPairsTokenAggregator = (
  allAssetsAddresses: {
    [tokenSymbol: string]: tEthereumAddress;
  },
  aggregatorsAddresses: { [tokenSymbol: string]: tEthereumAddress },
  oracleQuoteCurrency: string
): [string[], string[]] => {
  const assetsWithoutQuoteCurrency = omit(
    allAssetsAddresses,
    getQuoteCurrencies(oracleQuoteCurrency)
  );

  const pairs = Object.entries(assetsWithoutQuoteCurrency).reduce<[string, string][]>(
    (acc, [tokenSymbol, tokenAddress]) => {
      const aggregatorAddressIndex = Object.keys(aggregatorsAddresses).findIndex(
        (value) => value === tokenSymbol
      );
      if (aggregatorAddressIndex >= 0) {
        const [, aggregatorAddress] = (
          Object.entries(aggregatorsAddresses) as [string, tEthereumAddress][]
        )[aggregatorAddressIndex];
        return [...acc, [tokenAddress, aggregatorAddress]];
      }
      return acc;
    },
    []
  );

  const mappedPairs = pairs.map(([asset]) => asset);
  const mappedAggregators = pairs.map(([, source]) => source);

  return [mappedPairs, mappedAggregators];
};

export const getLendingPoolAddressesProviderRegistry = async (address?: tEthereumAddress) =>
  await LendingPoolAddressesProviderRegistry__factory.connect(
    notFalsyOrZeroAddress(address)
      ? address
      : (
          await getDb()
            .get(`${eContractid.LendingPoolAddressesProviderRegistry}.${DRE.network.name}`)
            .value()
        ).address,
    await getFirstSigner()
  );

export const getReserveLogic = async (address?: tEthereumAddress) =>
  await ReserveLogic__factory.connect(
    address ||
      (
        await getDb().get(`${eContractid.ReserveLogic}.${DRE.network.name}`).value()
      ).address,
    await getFirstSigner()
  );

export const getGenericLogic = async (address?: tEthereumAddress) =>
  await GenericLogic__factory.connect(
    address ||
      (
        await getDb().get(`${eContractid.GenericLogic}.${DRE.network.name}`).value()
      ).address,
    await getFirstSigner()
  );

export const getStableAndVariableTokensHelper = async (address?: tEthereumAddress) =>
  await StableAndVariableTokensHelper__factory.connect(
    address ||
      (
        await getDb()
          .get(`${eContractid.StableAndVariableTokensHelper}.${DRE.network.name}`)
          .value()
      ).address,
    await getFirstSigner()
  );

export const getATokensAndRatesHelper = async (address?: tEthereumAddress) =>
  await ATokensAndRatesHelper__factory.connect(
    address ||
      (
        await getDb().get(`${eContractid.ATokensAndRatesHelper}.${DRE.network.name}`).value()
      ).address,
    await getFirstSigner()
  );

export const getWETHGateway = async (address?: tEthereumAddress) =>
  await WETHGateway__factory.connect(
    address ||
      (
        await getDb().get(`${eContractid.WETHGateway}.${DRE.network.name}`).value()
      ).address,
    await getFirstSigner()
  );

export const getWETHMocked = async (address?: tEthereumAddress) =>
  await WETH9Mocked__factory.connect(
    address || (await getDb().get(`${eContractid.WETHMocked}.${DRE.network.name}`).value()).address,
    await getFirstSigner()
  );

export const getMockAToken = async (address?: tEthereumAddress) =>
  await MockAToken__factory.connect(
    address || (await getDb().get(`${eContractid.MockAToken}.${DRE.network.name}`).value()).address,
    await getFirstSigner()
  );

export const getMockVariableDebtToken = async (address?: tEthereumAddress) =>
  await MockVariableDebtToken__factory.connect(
    address ||
      (
        await getDb().get(`${eContractid.MockVariableDebtToken}.${DRE.network.name}`).value()
      ).address,
    await getFirstSigner()
  );

export const getMockStableDebtToken = async (address?: tEthereumAddress) =>
  await MockStableDebtToken__factory.connect(
    address ||
      (
        await getDb().get(`${eContractid.MockStableDebtToken}.${DRE.network.name}`).value()
      ).address,
    await getFirstSigner()
  );

export const getSelfdestructTransferMock = async (address?: tEthereumAddress) =>
  await SelfdestructTransfer__factory.connect(
    address ||
      (
        await getDb().get(`${eContractid.SelfdestructTransferMock}.${DRE.network.name}`).value()
      ).address,
    await getFirstSigner()
  );

export const getProxy = async (address: tEthereumAddress) =>
  await InitializableAdminUpgradeabilityProxy__factory.connect(address, await getFirstSigner());

export const getLendingPoolImpl = async (address?: tEthereumAddress) =>
  await LendingPool__factory.connect(
    address ||
      (
        await getDb().get(`${eContractid.LendingPoolImpl}.${DRE.network.name}`).value()
      ).address,
    await getFirstSigner()
  );

export const getLendingPoolConfiguratorImpl = async (address?: tEthereumAddress) =>
  await LendingPoolConfigurator__factory.connect(
    address ||
      (
        await getDb().get(`${eContractid.LendingPoolConfiguratorImpl}.${DRE.network.name}`).value()
      ).address,
    await getFirstSigner()
  );

export const getLendingPoolCollateralManagerImpl = async (address?: tEthereumAddress) =>
  await LendingPoolCollateralManager__factory.connect(
    address ||
      (
        await getDb()
          .get(`${eContractid.LendingPoolCollateralManagerImpl}.${DRE.network.name}`)
          .value()
      ).address,
    await getFirstSigner()
  );

export const getWalletProvider = async (address?: tEthereumAddress) =>
  await WalletBalanceProvider__factory.connect(
    address ||
      (
        await getDb().get(`${eContractid.WalletBalanceProvider}.${DRE.network.name}`).value()
      ).address,
    await getFirstSigner()
  );

export const getLendingPoolCollateralManager = async (address?: tEthereumAddress) =>
  await LendingPoolCollateralManager__factory.connect(
    address ||
      (
        await getDb().get(`${eContractid.LendingPoolCollateralManager}.${DRE.network.name}`).value()
      ).address,
    await getFirstSigner()
  );

export const getAddressById = async (id: string): Promise<tEthereumAddress | undefined> =>
  (await getDb().get(`${id}.${DRE.network.name}`).value())?.address || undefined;

export const getAaveOracle = async (address?: tEthereumAddress) =>
  await AaveOracle__factory.connect(
    address || (await getDb().get(`${eContractid.AaveOracle}.${DRE.network.name}`).value()).address,
    await getFirstSigner()
  );

export const getMockUniswapRouter = async (address?: tEthereumAddress) =>
  await MockUniswapV2Router02__factory.connect(
    address ||
      (
        await getDb().get(`${eContractid.MockUniswapV2Router02}.${DRE.network.name}`).value()
      ).address,
    await getFirstSigner()
  );

export const getUniswapLiquiditySwapAdapter = async (address?: tEthereumAddress) =>
  await UniswapLiquiditySwapAdapter__factory.connect(
    address ||
      (
        await getDb().get(`${eContractid.UniswapLiquiditySwapAdapter}.${DRE.network.name}`).value()
      ).address,
    await getFirstSigner()
  );

export const getUniswapRepayAdapter = async (address?: tEthereumAddress) =>
  await UniswapRepayAdapter__factory.connect(
    address ||
      (
        await getDb().get(`${eContractid.UniswapRepayAdapter}.${DRE.network.name}`).value()
      ).address,
    await getFirstSigner()
  );

export const getFlashLiquidationAdapter = async (address?: tEthereumAddress) =>
  await FlashLiquidationAdapter__factory.connect(
    address ||
      (
        await getDb().get(`${eContractid.FlashLiquidationAdapter}.${DRE.network.name}`).value()
      ).address,
    await getFirstSigner()
  );

export const getMockParaSwapAugustus = async (address?: tEthereumAddress) =>
  await MockParaSwapAugustus__factory.connect(
    address ||
      (
        await getDb().get(`${eContractid.MockParaSwapAugustus}.${DRE.network.name}`).value()
      ).address,
    await getFirstSigner()
  );

export const getMockParaSwapAugustusRegistry = async (address?: tEthereumAddress) =>
  await MockParaSwapAugustusRegistry__factory.connect(
    address ||
      (
        await getDb().get(`${eContractid.MockParaSwapAugustusRegistry}.${DRE.network.name}`).value()
      ).address,
    await getFirstSigner()
  );

export const getParaSwapLiquiditySwapAdapter = async (address?: tEthereumAddress) =>
  await ParaSwapLiquiditySwapAdapter__factory.connect(
    address ||
      (
        await getDb().get(`${eContractid.ParaSwapLiquiditySwapAdapter}.${DRE.network.name}`).value()
      ).address,
    await getFirstSigner()
  );
