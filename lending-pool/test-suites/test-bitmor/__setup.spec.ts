import rawBRE from 'hardhat';
import { MockContract } from 'ethereum-waffle';
import {
  insertContractAddressInDb,
  getEthersSigners,
  registerContractInJsonDb,
  getEthersSignersAddresses,
} from '../../helpers/contracts-helpers';
import {
  deployLendingPoolAddressesProvider,
  deployMintableERC20,
  deployLendingPoolAddressesProviderRegistry,
  deployLendingPoolConfigurator,
  deployLendingPool,
  deployPriceOracle,
  deployLendingPoolCollateralManager,
  deployMockFlashLoanReceiver,
  deployWalletBalancerProvider,
  deployAaveProtocolDataProvider,
  deployLendingRateOracle,
  deployStableAndVariableTokensHelper,
  deployATokensAndRatesHelper,
  deployWETHMocked,
  deployATokenImplementations,
  deployAaveOracle,
} from '../../helpers/contracts-deployments';
import { Signer } from 'ethers';
import { eContractid, tEthereumAddress } from '../../helpers/types';
import { MintableERC20 } from '../../types/MintableERC20';
import {
  ConfigNames,
  getTreasuryAddress,
  loadPoolConfig,
} from '../../helpers/configuration';
import { initializeMakeSuite } from './helpers/make-suite';
import {
  setInitialAssetPricesInOracle,
  deployAllMockAggregators,
  setInitialMarketRatesInRatesOracleByHelper,
} from '../../helpers/oracles-helpers';
import { DRE, waitForTx } from '../../helpers/misc-utils';
import { initReservesByHelper, configureReservesByHelper } from '../../helpers/init-helpers';
import BitmorConfig from '../../markets/bitmor';
import { oneEther, ZERO_ADDRESS } from '../../helpers/constants';
import {
  getLendingPool,
  getLendingPoolConfiguratorProxy,
  getPairsTokenAggregator,
} from '../../helpers/contracts-getters';
import { WETH9Mocked } from '../../types/WETH9Mocked';

const MOCK_USD_PRICE_IN_WEI = BitmorConfig.ProtocolGlobalParams.MockUsdPriceInWei;
const LENDING_RATE_ORACLE_RATES_COMMON = BitmorConfig.LendingRateOracleRatesCommon;

// USD prices for Bitmor (8 decimals - Chainlink standard)
const USD_PRICES_8_DECIMALS = {
  USDC: '100000000',         // $1.00
  cbBTC: '10000000000000',   // $100,000.00
};

// Global variable to store aggregator addresses for test access
declare global {
  var mockAggregators: { [key: string]: string };
}

// Deploy only the tokens needed for Bitmor: USDC, cbBTC, WETH
const deployBitmorMockTokens = async (deployer: Signer) => {
  const tokens: { [symbol: string]: MockContract | MintableERC20 | WETH9Mocked } = {};

  // Deploy WETH for Aave oracle initialisation
  tokens['WETH'] = await deployWETHMocked();
  await registerContractInJsonDb('WETH', tokens['WETH']);

  // Deploy USDC (6 decimals)
  tokens['USDC'] = await deployMintableERC20(['USDC', 'USDC', '6']);
  await registerContractInJsonDb('USDC', tokens['USDC']);

  // Deploy cbBTC (8 decimals - same as BTC)
  tokens['cbBTC'] = await deployMintableERC20(['cbBTC', 'cbBTC', '8']);
  await registerContractInJsonDb('cbBTC', tokens['cbBTC']);

  return tokens;
};

const buildTestEnv = async (deployer: Signer, secondaryWallet: Signer) => {
  console.time('setup');
  const aaveAdmin = await deployer.getAddress();
  const config = loadPoolConfig(ConfigNames.Bitmor);
  const {
    ATokenNamePrefix,
    StableDebtTokenNamePrefix,
    VariableDebtTokenNamePrefix,
    SymbolPrefix,
    ReservesConfig,
  } = config;

  // Deploy mock tokens for Bitmor
  const mockTokens = await deployBitmorMockTokens(deployer);

  // Deploy Addresses Provider
  const addressesProvider = await deployLendingPoolAddressesProvider(BitmorConfig.MarketId);
  await waitForTx(await addressesProvider.setPoolAdmin(aaveAdmin));

  // Set emergency admin (user at index 2)
  const addressList = await getEthersSignersAddresses();
  await waitForTx(await addressesProvider.setEmergencyAdmin(addressList[2]));

  // Deploy Registry
  const addressesProviderRegistry = await deployLendingPoolAddressesProviderRegistry();
  await waitForTx(
    await addressesProviderRegistry.registerAddressesProvider(addressesProvider.address, 100) // ProviderId = 100 for Bitmor
  );

  // Deploy Lending Pool
  const lendingPoolImpl = await deployLendingPool();
  await waitForTx(await addressesProvider.setLendingPoolImpl(lendingPoolImpl.address));
  const lendingPoolAddress = await addressesProvider.getLendingPool();
  const lendingPoolProxy = await getLendingPool(lendingPoolAddress);
  await insertContractAddressInDb(eContractid.LendingPool, lendingPoolProxy.address);

  // Deploy Lending Pool Configurator
  const lendingPoolConfiguratorImpl = await deployLendingPoolConfigurator();
  await waitForTx(
    await addressesProvider.setLendingPoolConfiguratorImpl(lendingPoolConfiguratorImpl.address)
  );
  const lendingPoolConfiguratorProxy = await getLendingPoolConfiguratorProxy(
    await addressesProvider.getLendingPoolConfigurator()
  );
  await insertContractAddressInDb(
    eContractid.LendingPoolConfigurator,
    lendingPoolConfiguratorProxy.address
  );

  // Deploy helpers for batch operations
  await deployStableAndVariableTokensHelper([lendingPoolProxy.address, addressesProvider.address]);
  await deployATokensAndRatesHelper([
    lendingPoolProxy.address,
    addressesProvider.address,
    lendingPoolConfiguratorProxy.address,
  ]);

  // Deploy and configure Price Oracle
  const fallbackOracle = await deployPriceOracle();
  await waitForTx(await fallbackOracle.setEthUsdPrice(MOCK_USD_PRICE_IN_WEI));

  // Set initial USD prices for Bitmor reserves (8 decimals)
  await setInitialAssetPricesInOracle(
    USD_PRICES_8_DECIMALS,
    {
      USDC: mockTokens.USDC.address,
      cbBTC: mockTokens.cbBTC.address,
    },
    fallbackOracle
  );

  // Deploy Chainlink mock aggregators with USD prices (8 decimals)
  const mockAggregators = await deployAllMockAggregators(USD_PRICES_8_DECIMALS);

  global.mockAggregators = mockAggregators;

  const allTokenAddresses = Object.entries(mockTokens).reduce(
    (accum: { [tokenSymbol: string]: tEthereumAddress }, [tokenSymbol, tokenContract]) => ({
      ...accum,
      [tokenSymbol]: tokenContract.address,
    }),
    {}
  );

  const allAggregatorsAddresses = Object.entries(mockAggregators).reduce(
    (accum: { [tokenSymbol: string]: tEthereumAddress }, [tokenSymbol, aggregator]) => ({
      ...accum,
      [tokenSymbol]: aggregator,
    }),
    {}
  );

  const [tokens, aggregators] = getPairsTokenAggregator(
    allTokenAddresses,
    allAggregatorsAddresses,
    config.OracleQuoteCurrency
  );

  // Deploy Aave Oracle
  await deployAaveOracle([
    tokens,
    aggregators,
    fallbackOracle.address,
    mockTokens.WETH.address,
    oneEther.toString(),
  ]);
  await waitForTx(await addressesProvider.setPriceOracle(fallbackOracle.address));

  // Deploy Lending Rate Oracle
  const lendingRateOracle = await deployLendingRateOracle();
  await waitForTx(await addressesProvider.setLendingRateOracle(lendingRateOracle.address));

  // Set initial market rates
  const { USD, ...tokensAddressesWithoutUsd } = allTokenAddresses;
  const allReservesAddresses = { ...tokensAddressesWithoutUsd };

  await setInitialMarketRatesInRatesOracleByHelper(
    LENDING_RATE_ORACLE_RATES_COMMON,
    allReservesAddresses,
    lendingRateOracle,
    aaveAdmin
  );

  // Deploy AToken implementations
  await deployATokenImplementations(ConfigNames.Bitmor, ReservesConfig);

  // Deploy Protocol Data Provider
  const testHelpers = await deployAaveProtocolDataProvider(addressesProvider.address);
  await insertContractAddressInDb(eContractid.AaveProtocolDataProvider, testHelpers.address);

  const admin = await deployer.getAddress();
  console.log('Initialize configuration');

  const treasuryAddress = await getTreasuryAddress(config);

  // Initialize reserves (USDC and cbBTC)
  await initReservesByHelper(
    ReservesConfig,
    allReservesAddresses,
    ATokenNamePrefix,
    StableDebtTokenNamePrefix,
    VariableDebtTokenNamePrefix,
    SymbolPrefix,
    admin,
    treasuryAddress,
    ZERO_ADDRESS,
    ConfigNames.Bitmor,
    false
  );

  // Configure reserves with interest rate strategies
  await configureReservesByHelper(ReservesConfig, allReservesAddresses, testHelpers, admin);

  // Deploy Collateral Manager
  const collateralManager = await deployLendingPoolCollateralManager();
  await waitForTx(
    await addressesProvider.setLendingPoolCollateralManager(collateralManager.address)
  );

  // Deploy Mock Flash Loan Receiver
  await deployMockFlashLoanReceiver(addressesProvider.address);

  // Deploy Wallet Balance Provider
  await deployWalletBalancerProvider();

  console.timeEnd('setup');
}

before(async () => {
    await rawBRE.run('set-DRE');
    const [deployer, secondaryWallet] = await getEthersSigners();
    const FORK = process.env.FORK;

    if(FORK) {
        await rawBRE.run('bitmor:mainnet', { skipRegistry: true });
    } else {
        console.log('-> Deploying test environment...');
        await buildTestEnv(deployer, secondaryWallet);
    }

    await initializeMakeSuite();
    console.log('\n***************');
    console.log('Setup and snapshot finished');
    console.log('***************\n');
})
