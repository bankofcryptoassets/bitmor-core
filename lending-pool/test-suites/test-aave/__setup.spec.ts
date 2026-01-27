import {network, artifacts} from 'hardhat';
import {
  insertContractAddressInDb,
  getEthersSigners,
  registerContractInJsonDb,
  getEthersSignersAddresses,
  getContractAddress,
} from '../../helpers/contracts-helpers.js';
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
  deployWETHGateway,
  deployWETHMocked,
  deployMockUniswapRouter,
  deployUniswapLiquiditySwapAdapter,
  deployUniswapRepayAdapter,
  deployFlashLiquidationAdapter,
  deployMockParaSwapAugustus,
  deployMockParaSwapAugustusRegistry,
  deployParaSwapLiquiditySwapAdapter,
  authorizeWETHGateway,
  deployATokenImplementations,
  deployAaveOracle,
  deployMockUSDCVault,
  deployMockActualUSDCVault,
  deployMockWETHVault,
  deployMockBTCVault,
  deployMockLoan,
} from '../../helpers/contracts-deployments.js';
import type { Signer } from 'ethers';
import { TokenContractId, eContractid, AavePools } from '../../helpers/types.js';
import type { tEthereumAddress } from '../../helpers/types.js';
import type { MintableERC20, WETH9Mocked } from '../../types/ethers-contracts/index.js';
import {
  ConfigNames,
  getReservesConfigByPool,
  getTreasuryAddress,
  loadPoolConfig,
} from '../../helpers/configuration.js';
import { initializeMakeSuite } from './helpers/make-suite.js';

import {
  setInitialAssetPricesInOracle,
  deployAllMockAggregators,
  setInitialMarketRatesInRatesOracleByHelper,
} from '../../helpers/oracles-helpers.js';
import { DRE, waitForTx, setDRE } from '../../helpers/misc-utils.js';
import { initReservesByHelper, configureReservesByHelper } from '../../helpers/init-helpers.js';
import AaveConfig from '../../markets/aave/index.js';
import { oneEther, ZERO_ADDRESS } from '../../helpers/constants.js';
import {
  getLendingPool,
  getLendingPoolConfiguratorProxy,
  getPairsTokenAggregator,
} from '../../helpers/contracts-getters.js';

const MOCK_USD_PRICE_IN_WEI = AaveConfig.ProtocolGlobalParams.MockUsdPriceInWei;
const ALL_ASSETS_INITIAL_PRICES = AaveConfig.Mocks.AllAssetsInitialPrices;
const USD_ADDRESS = AaveConfig.ProtocolGlobalParams.UsdAddress;
const LENDING_RATE_ORACLE_RATES_COMMON = AaveConfig.LendingRateOracleRatesCommon;

const deployAllMockTokens = async (deployer: Signer) => {
  const tokens: { [symbol: string]: MintableERC20 | WETH9Mocked } = {};

  const protoConfigData = getReservesConfigByPool(AavePools.proto);

  for (const tokenSymbol of Object.keys(TokenContractId)) {
    if (tokenSymbol === 'WETH') {
      tokens[tokenSymbol] = await deployWETHMocked();
      await registerContractInJsonDb(tokenSymbol.toUpperCase(), tokens[tokenSymbol]);
      continue;
    }
    let decimals = 18;

    let configData = (protoConfigData as any)[tokenSymbol];

    if (!configData) {
      decimals = 18;
    }

    tokens[tokenSymbol] = await deployMintableERC20([
      tokenSymbol,
      tokenSymbol,
      configData ? configData.reserveDecimals : 18,
    ]);
    await registerContractInJsonDb(tokenSymbol.toUpperCase(), tokens[tokenSymbol]);
  }

  return tokens;
};

const buildTestEnv = async (deployer: Signer, secondaryWallet: Signer) => {
  console.time('setup');
  const aaveAdmin = await deployer.getAddress();
  const config = loadPoolConfig(ConfigNames.Aave);

  // Deploy cbBTC mock token (8 decimals like real cbBTC)
  console.log('Deploying cbBTC mock token...');
  const cbBTC = await deployMintableERC20(['cbBTC', 'cbBTC', '8']);
  await registerContractInJsonDb('cbBTC', cbBTC);

  console.log('cbBTC mock token deployed:: ', cbBTC.target);

    const mockTokens: {
    [symbol: string]: MintableERC20 | WETH9Mocked;
  } = {
    ...(await deployAllMockTokens(deployer)),
    "cbBTC": cbBTC,
  };

  const addressesProvider = await deployLendingPoolAddressesProvider(AaveConfig.MarketId);
  await waitForTx(await addressesProvider.setPoolAdmin(aaveAdmin));

  //setting users[1] as emergency admin, which is in position 2 in the DRE addresses list
  const addressList = await getEthersSignersAddresses();

  await waitForTx(await addressesProvider.setEmergencyAdmin(addressList[2]));

  const addressesProviderRegistry = await deployLendingPoolAddressesProviderRegistry();
  await waitForTx(
    await addressesProviderRegistry.registerAddressesProvider(getContractAddress(addressesProvider), 1)
  );

  const lendingPoolImpl = await deployLendingPool();

  await waitForTx(await addressesProvider.setLendingPoolImpl(getContractAddress(lendingPoolImpl)));

  const lendingPoolAddress = await addressesProvider.getLendingPool();
  console.log('LendingPool address:: ', lendingPoolAddress);
  const lendingPoolProxy = await getLendingPool(lendingPoolAddress);

  console.log('LendingPool proxy address:: ', getContractAddress(lendingPoolProxy));

  await insertContractAddressInDb(eContractid.LendingPool, getContractAddress(lendingPoolProxy));

  const lendingPoolConfiguratorImpl = await deployLendingPoolConfigurator();
  await waitForTx(
    await addressesProvider.setLendingPoolConfiguratorImpl(getContractAddress(lendingPoolConfiguratorImpl))
  );

  const lendingPoolConfiguratorProxy = await getLendingPoolConfiguratorProxy(
    await addressesProvider.getLendingPoolConfigurator()
  );
  await insertContractAddressInDb(
    eContractid.LendingPoolConfigurator,
    getContractAddress(lendingPoolConfiguratorProxy)
  );

  // Deploy deployment helpers
  await deployStableAndVariableTokensHelper([getContractAddress(lendingPoolProxy), getContractAddress(addressesProvider)]);
  await deployATokensAndRatesHelper([
    getContractAddress(lendingPoolProxy),
    getContractAddress(addressesProvider),
    getContractAddress(lendingPoolConfiguratorProxy),
  ]);

  const fallbackOracle = await deployPriceOracle();
  await waitForTx(await fallbackOracle.setEthUsdPrice(MOCK_USD_PRICE_IN_WEI));
  await setInitialAssetPricesInOracle(
    ALL_ASSETS_INITIAL_PRICES,
    {
      WETH: getContractAddress(mockTokens.WETH),
      DAI: getContractAddress(mockTokens.DAI),
      TUSD: getContractAddress(mockTokens.TUSD),
      USDC: getContractAddress(mockTokens.USDC),
      USDT: getContractAddress(mockTokens.USDT),
      SUSD: getContractAddress(mockTokens.SUSD),
      AAVE: getContractAddress(mockTokens.AAVE),
      BAT: getContractAddress(mockTokens.BAT),
      MKR: getContractAddress(mockTokens.MKR),
      LINK: getContractAddress(mockTokens.LINK),
      KNC: getContractAddress(mockTokens.KNC),
      WBTC: getContractAddress(mockTokens.WBTC),
      MANA: getContractAddress(mockTokens.MANA),
      ZRX: getContractAddress(mockTokens.ZRX),
      SNX: getContractAddress(mockTokens.SNX),
      BUSD: getContractAddress(mockTokens.BUSD),
      YFI: getContractAddress(mockTokens.BUSD),
      REN: getContractAddress(mockTokens.REN),
      UNI: getContractAddress(mockTokens.UNI),
      ENJ: getContractAddress(mockTokens.ENJ),
      // DAI: getContractAddress(mockTokens.LpDAI),
      // USDC: getContractAddress(mockTokens.LpUSDC),
      // USDT: getContractAddress(mockTokens.LpUSDT),
      // WBTC: getContractAddress(mockTokens.LpWBTC),
      // WETH: getContractAddress(mockTokens.LpWETH),
      UniDAIWETH: getContractAddress(mockTokens.UniDAIWETH),
      UniWBTCWETH: getContractAddress(mockTokens.UniWBTCWETH),
      UniAAVEWETH: getContractAddress(mockTokens.UniAAVEWETH),
      UniBATWETH: getContractAddress(mockTokens.UniBATWETH),
      UniDAIUSDC: getContractAddress(mockTokens.UniDAIUSDC),
      UniCRVWETH: getContractAddress(mockTokens.UniCRVWETH),
      UniLINKWETH: getContractAddress(mockTokens.UniLINKWETH),
      UniMKRWETH: getContractAddress(mockTokens.UniMKRWETH),
      UniRENWETH: getContractAddress(mockTokens.UniRENWETH),
      UniSNXWETH: getContractAddress(mockTokens.UniSNXWETH),
      UniUNIWETH: getContractAddress(mockTokens.UniUNIWETH),
      UniUSDCWETH: getContractAddress(mockTokens.UniUSDCWETH),
      UniWBTCUSDC: getContractAddress(mockTokens.UniWBTCUSDC),
      UniYFIWETH: getContractAddress(mockTokens.UniYFIWETH),
      BptWBTCWETH: getContractAddress(mockTokens.BptWBTCWETH),
      BptBALWETH: getContractAddress(mockTokens.BptBALWETH),
      WMATIC: getContractAddress(mockTokens.WMATIC),
      USD: USD_ADDRESS,
      STAKE: getContractAddress(mockTokens.STAKE),
      xSUSHI: getContractAddress(mockTokens.xSUSHI),
      WAVAX: getContractAddress(mockTokens.WAVAX),
      cbBTC: getContractAddress(cbBTC),
    },
    fallbackOracle
  );

  // Set cbBTC price ($100,000 in ETH terms - similar to WBTC pricing)
  // Using same format as other prices: oneEther.multipliedBy(price_in_ETH)
  await waitForTx(
    await fallbackOracle.setAssetPrice(getContractAddress(cbBTC), oneEther.multipliedBy('47.332685').toFixed())
  );
  console.log('cbBTC price set in fallback oracle');

  // Deploy MockBTCVault (wraps cbBTC → bvBTC) - needs to be before AaveOracle
  console.log('Deploying MockBTCVault...');
  const mockBTCVault = await deployMockBTCVault(
    [getContractAddress(addressesProvider), getContractAddress(cbBTC)],
    false
  );
  console.log('MockBTCVault deployed');

  // Set bvBTC price (same as cbBTC for 1:1 share ratio)
  await waitForTx(
    await fallbackOracle.setAssetPrice(getContractAddress(mockBTCVault), oneEther.multipliedBy('47.332685').toFixed())
  );

  const mockAggregators = await deployAllMockAggregators(ALL_ASSETS_INITIAL_PRICES);
  const allTokenAddresses = Object.entries(mockTokens).reduce(
    (accum: { [tokenSymbol: string]: tEthereumAddress }, [tokenSymbol, tokenContract]) => ({
      ...accum,
      [tokenSymbol]: getContractAddress(tokenContract),
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

  await deployAaveOracle([
    tokens,
    aggregators,
    getContractAddress(cbBTC), // btc - cbBTC token
    getContractAddress(mockBTCVault), // bvBTC - vault shares
    getContractAddress(fallbackOracle),
    getContractAddress(mockTokens.WETH),
    oneEther.toString(),
  ]);
  await waitForTx(await addressesProvider.setPriceOracle(getContractAddress(fallbackOracle)));

  // Register BTCVault in addresses provider
  await waitForTx(await addressesProvider.setBTCVault(getContractAddress(mockBTCVault)));
  console.log('MockBTCVault registered in addresses provider');

  const lendingRateOracle = await deployLendingRateOracle();
  await waitForTx(await addressesProvider.setLendingRateOracle(getContractAddress(lendingRateOracle)));

  const { USD, ...tokensAddressesWithoutUsd } = allTokenAddresses;
  console.log("\n\n\n");
  console.log("tokensAddressesWithoutUsd:: ", tokensAddressesWithoutUsd);
  console.log("\n\n\n");
  const allReservesAddresses = {
    ...tokensAddressesWithoutUsd,
  };
  await setInitialMarketRatesInRatesOracleByHelper(
    LENDING_RATE_ORACLE_RATES_COMMON,
    allReservesAddresses,
    lendingRateOracle,
    aaveAdmin
  );

  // Reserve params from AAVE pool + mocked tokens
  const reservesParams = {
    ...config.ReservesConfig,
  };

  const testHelpers = await deployAaveProtocolDataProvider(getContractAddress(addressesProvider));

  await deployATokenImplementations(ConfigNames.Aave, reservesParams, false);

  const admin = await deployer.getAddress();

  const { ATokenNamePrefix, StableDebtTokenNamePrefix, VariableDebtTokenNamePrefix, SymbolPrefix } =
    config;
  const treasuryAddress = await getTreasuryAddress(config);

  await initReservesByHelper(
    reservesParams,
    allReservesAddresses,
    ATokenNamePrefix,
    StableDebtTokenNamePrefix,
    VariableDebtTokenNamePrefix,
    SymbolPrefix,
    admin,
    treasuryAddress,
    ZERO_ADDRESS,
    ConfigNames.Aave,
    false
  );

  await configureReservesByHelper(reservesParams, allReservesAddresses, testHelpers, admin);

  const collateralManager = await deployLendingPoolCollateralManager();
  await waitForTx(
    await addressesProvider.setLendingPoolCollateralManager(getContractAddress(collateralManager))
  );

  // Deploy vault for DAI
  const mockUSDCVault = await deployMockUSDCVault([
    getContractAddress(addressesProvider),
    getContractAddress(mockTokens.DAI),
  ]);
  await waitForTx(await addressesProvider.setUSDCVault(getContractAddress(mockUSDCVault)));
  console.log('MockUSDCVault (DAI) deployed and configured');

  // Deploy vault for actual USDC
  const mockActualUSDCVault = await deployMockActualUSDCVault([
    getContractAddress(addressesProvider),
    getContractAddress(mockTokens.USDC),
  ]);
  console.log('MockActualUSDCVault (USDC) deployed');

  // Deploy vault for WETH
  const mockWETHVault = await deployMockWETHVault([
    getContractAddress(addressesProvider),
    getContractAddress(mockTokens.WETH),
  ]);
  console.log('MockWETHVault deployed');

  // Deploy MockLoan for liquidation testing
  console.log('Deploying MockLoan...');
  const mockLoan = await deployMockLoan(
    [getContractAddress(mockBTCVault), getContractAddress(mockTokens.USDC)], // collateral = bvBTC, debt = USDC
    false
  );

  // Register MockLoan as BitmorLoan in addresses provider
  await waitForTx(await addressesProvider.setBitmorLoan(getContractAddress(mockLoan)));
  console.log('MockLoan deployed and registered as BitmorLoan');

  await deployMockFlashLoanReceiver(getContractAddress(addressesProvider));

  const mockUniswapRouter = await deployMockUniswapRouter();

  const adapterParams: [string, string, string] = [
    getContractAddress(addressesProvider),
    getContractAddress(mockUniswapRouter),
    getContractAddress(mockTokens.WETH),
  ];

  await deployUniswapLiquiditySwapAdapter(adapterParams);
  await deployUniswapRepayAdapter(adapterParams);
  await deployFlashLiquidationAdapter(adapterParams);

  const augustus = await deployMockParaSwapAugustus();

  const augustusRegistry = await deployMockParaSwapAugustusRegistry([getContractAddress(augustus)]);

  await deployParaSwapLiquiditySwapAdapter([getContractAddress(addressesProvider), getContractAddress(augustusRegistry)]);

  await deployWalletBalancerProvider();

  const gateWay = await deployWETHGateway([getContractAddress(mockTokens.WETH)]);
  await authorizeWETHGateway(getContractAddress(gateWay), lendingPoolAddress);

  console.timeEnd('setup');
};

before(async () => {
  // In Hardhat 3, connect to network to get ethers
  const connectedNetwork = await network.connect();
  const { ethers } = connectedNetwork;

  // Create hre object with ethers, network, and artifacts attached
  const hre = {
    ethers,
    network: connectedNetwork,
    artifacts,
  };

  setDRE(hre);
  console.log('  - Network:', connectedNetwork.networkName);

  const [deployer, secondaryWallet] = await getEthersSigners();
  const FORK = process.env.FORK;

  if (FORK) {
    // TODO: Need to migrate aave:mainnet task to Hardhat 3
    throw new Error('Fork mode not yet supported in Hardhat 3 migration');
  } else {
    console.log('-> Deploying test environment...');
    await buildTestEnv(deployer, secondaryWallet);
  }

  await initializeMakeSuite();
  console.log('\n***************');
  console.log('Setup and snapshot finished');
  console.log('***************\n');
});
