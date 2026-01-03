import type { Contract } from 'ethers';
import { DRE, notFalsyOrZeroAddress } from './misc-utils';
import {
  eContractid,
  AavePools,
  TokenContractId,
  eEthereumNetwork,
} from './types.js';
import type {
  tEthereumAddress,
  tStringTokenSmallUnits,
  iMultiPoolsAssets,
  IReserveParams,
  PoolConfiguration,
} from './types.js';
import type { MintableERC20 } from '../types/ethers-contracts/index.js';
import { MockContract } from 'ethereum-waffle';
import { ConfigNames, getReservesConfigByPool, loadPoolConfig } from './configuration';
import { getFirstSigner } from './contracts-getters';
import {
  AaveProtocolDataProvider__factory,
  AToken__factory,
  ATokensAndRatesHelper__factory,
  AaveOracle__factory,
  DefaultReserveInterestRateStrategy__factory,
  DelegationAwareAToken__factory,
  InitializableAdminUpgradeabilityProxy__factory,
  LendingPoolAddressesProvider__factory,
  LendingPoolAddressesProviderRegistry__factory,
  LendingPoolCollateralManager__factory,
  LendingPoolConfigurator__factory,
  LendingPool__factory,
  LendingRateOracle__factory,
  MintableDelegationERC20__factory,
  MintableERC20__factory,
  MockAggregator__factory,
  MockAToken__factory,
  MockFlashLoanReceiver__factory,
  MockParaSwapAugustus__factory,
  MockParaSwapAugustusRegistry__factory,
  MockStableDebtToken__factory,
  MockVariableDebtToken__factory,
  MockUniswapV2Router02__factory,
  ParaSwapLiquiditySwapAdapter__factory,
  PriceOracle__factory,
  ReserveLogic__factory,
  SelfdestructTransfer__factory,
  StableDebtToken__factory,
  UniswapLiquiditySwapAdapter__factory,
  UniswapRepayAdapter__factory,
  VariableDebtToken__factory,
  WalletBalanceProvider__factory,
  WETH9Mocked__factory,
  WETHGateway__factory,
  FlashLiquidationAdapter__factory,
  UiPoolDataProviderV2__factory,
  UiPoolDataProviderV2V3__factory,
  UiIncentiveDataProviderV2__factory,
} from '../types/ethers-contracts/index.js';
import type { UiIncentiveDataProviderV2V3 } from '../types/ethers-contracts/index.js';
import {
  withSaveAndVerify,
  registerContractInJsonDb,
  linkBytecode,
  insertContractAddressInDb,
  deployContract,
  verifyContract,
  getOptionalParamAddressPerNetwork,
} from './contracts-helpers';
import { StableAndVariableTokensHelper__factory } from '../types/ethers-contracts/index.js';
import type { MintableDelegationERC20 } from '../types/ethers-contracts/index.js';
import { HardhatRuntimeEnvironment } from 'hardhat/types';
import type { LendingPoolLibraryAddresses } from '../types/ethers-contracts/factories/protocol/lendingpool/LendingPool__factory.js';
import type { UiPoolDataProvider } from '../types/ethers-contracts/index.js';
import { eNetwork } from './types.js';

export const deployUiIncentiveDataProviderV2 = async (verify?: boolean) =>
  withSaveAndVerify(
    await new UiIncentiveDataProviderV2__factory(await getFirstSigner()).deploy(),
    eContractid.UiIncentiveDataProviderV2,
    [],
    verify
  );

export const deployUiIncentiveDataProviderV2V3 = async (verify?: boolean) => {
  const id = eContractid.UiIncentiveDataProviderV2V3;
  const instance = await deployContract<UiIncentiveDataProviderV2V3>(id, []);
  if (verify) {
    await verifyContract(id, instance, []);
  }
  return instance;
};

export const deployUiPoolDataProviderV2 = async (
  chainlinkAggregatorProxy: string,
  chainlinkEthUsdAggregatorProxy: string,
  verify?: boolean
) =>
  withSaveAndVerify(
    await new UiPoolDataProviderV2__factory(await getFirstSigner()).deploy(
      chainlinkAggregatorProxy,
      chainlinkEthUsdAggregatorProxy
    ),
    eContractid.UiPoolDataProvider,
    [chainlinkAggregatorProxy, chainlinkEthUsdAggregatorProxy],
    verify
  );

export const deployUiPoolDataProviderV2V3 = async (
  chainlinkAggregatorProxy: string,
  chainlinkEthUsdAggregatorProxy: string,
  verify?: boolean
) =>
  withSaveAndVerify(
    await new UiPoolDataProviderV2V3__factory(await getFirstSigner()).deploy(
      chainlinkAggregatorProxy,
      chainlinkEthUsdAggregatorProxy
    ),
    eContractid.UiPoolDataProvider,
    [chainlinkAggregatorProxy, chainlinkEthUsdAggregatorProxy],
    verify
  );

export const deployUiPoolDataProvider = async (
  [incentivesController, aaveOracle]: [tEthereumAddress, tEthereumAddress],
  verify?: boolean
) => {
  const id = eContractid.UiPoolDataProvider;
  const args: string[] = [incentivesController, aaveOracle];
  const instance = await deployContract<UiPoolDataProvider>(id, args);
  if (verify) {
    await verifyContract(id, instance, args);
  }
  return instance;
};

const readArtifact = async (id: string) => {
  return (DRE as HardhatRuntimeEnvironment).artifacts.readArtifact(id);
};

export const deployLendingPoolAddressesProvider = async (marketId: string, verify?: boolean) =>
  withSaveAndVerify(
    await new LendingPoolAddressesProvider__factory(await getFirstSigner()).deploy(marketId),
    eContractid.LendingPoolAddressesProvider,
    [marketId],
    verify
  );

export const deployLendingPoolAddressesProviderRegistry = async (verify?: boolean) =>
  withSaveAndVerify(
    await new LendingPoolAddressesProviderRegistry__factory(await getFirstSigner()).deploy(),
    eContractid.LendingPoolAddressesProviderRegistry,
    [],
    verify
  );

export const deployLendingPoolConfigurator = async (verify?: boolean) => {
  const lendingPoolConfiguratorImpl = await new LendingPoolConfigurator__factory(
    await getFirstSigner()
  ).deploy();
  await insertContractAddressInDb(
    eContractid.LendingPoolConfiguratorImpl,
    lendingPoolConfiguratorImpl.address
  );
  return withSaveAndVerify(
    lendingPoolConfiguratorImpl,
    eContractid.LendingPoolConfigurator,
    [],
    verify
  );
};

export const deployReserveLogicLibrary = async (verify?: boolean) =>
  withSaveAndVerify(
    await new ReserveLogic__factory(await getFirstSigner()).deploy(),
    eContractid.ReserveLogic,
    [],
    verify
  );

export const deployGenericLogic = async (reserveLogic: Contract, verify?: boolean) => {
  const genericLogicArtifact = await readArtifact(eContractid.GenericLogic);

  const linkedGenericLogicByteCode = linkBytecode(genericLogicArtifact, {
    [eContractid.ReserveLogic]: reserveLogic.address,
  });

  const genericLogicFactory = await DRE.ethers.getContractFactory(
    genericLogicArtifact.abi,
    linkedGenericLogicByteCode
  );

  const genericLogic = await (
    await genericLogicFactory.connect(await getFirstSigner()).deploy()
  ).deployed();
  return withSaveAndVerify(genericLogic, eContractid.GenericLogic, [], verify);
};

export const deployValidationLogic = async (
  reserveLogic: Contract,
  genericLogic: Contract,
  verify?: boolean
) => {
  const validationLogicArtifact = await readArtifact(eContractid.ValidationLogic);

  const linkedValidationLogicByteCode = linkBytecode(validationLogicArtifact, {
    [eContractid.ReserveLogic]: reserveLogic.address,
    [eContractid.GenericLogic]: genericLogic.address,
  });

  const validationLogicFactory = await DRE.ethers.getContractFactory(
    validationLogicArtifact.abi,
    linkedValidationLogicByteCode
  );

  const validationLogic = await (
    await validationLogicFactory.connect(await getFirstSigner()).deploy()
  ).deployed();

  return withSaveAndVerify(validationLogic, eContractid.ValidationLogic, [], verify);
};

export const deployAaveLibraries = async (
  verify?: boolean
): Promise<LendingPoolLibraryAddresses> => {
  const reserveLogic = await deployReserveLogicLibrary(verify);
  const genericLogic = await deployGenericLogic(reserveLogic, verify);
  const validationLogic = await deployValidationLogic(reserveLogic, genericLogic, verify);

  // Hardcoded solidity placeholders, if any library changes path this will fail.
  // The '__$PLACEHOLDER$__ can be calculated via solidity keccak, but the LendingPoolLibraryAddresses Type seems to
  // require a hardcoded string.
  //
  //  how-to:
  //  1. PLACEHOLDER = solidityKeccak256(['string'], `${libPath}:${libName}`).slice(2, 36)
  //  2. LIB_PLACEHOLDER = `__$${PLACEHOLDER}$__`
  // or grab placeholdes from LendingPoolLibraryAddresses at Typechain generation.
  //
  // libPath example: contracts/libraries/logic/GenericLogic.sol
  // libName example: GenericLogic
  return {
    ['__$de8c0cf1a7d7c36c802af9a64fb9d86036$__']: validationLogic.address,
    ['__$22cd43a9dda9ce44e9b92ba393b88fb9ac$__']: reserveLogic.address,
  };
};

export const deployLendingPool = async (verify?: boolean) => {
  const libraries = await deployAaveLibraries(verify);
  const lendingPoolImpl = await new LendingPool__factory(libraries, await getFirstSigner()).deploy();
  await insertContractAddressInDb(eContractid.LendingPoolImpl, lendingPoolImpl.address);
  return withSaveAndVerify(lendingPoolImpl, eContractid.LendingPool, [], verify);
};

export const deployPriceOracle = async (verify?: boolean) =>
  withSaveAndVerify(
    await new PriceOracle__factory(await getFirstSigner()).deploy(),
    eContractid.PriceOracle,
    [],
    verify
  );

export const deployLendingRateOracle = async (verify?: boolean) =>
  withSaveAndVerify(
    await new LendingRateOracle__factory(await getFirstSigner()).deploy(),
    eContractid.LendingRateOracle,
    [],
    verify
  );

export const deployMockAggregator = async (price: tStringTokenSmallUnits, verify?: boolean) =>
  withSaveAndVerify(
    await new MockAggregator__factory(await getFirstSigner()).deploy(price),
    eContractid.MockAggregator,
    [price],
    verify
  );

export const deployAaveOracle = async (
  args: [tEthereumAddress[], tEthereumAddress[], tEthereumAddress, tEthereumAddress, string],
  verify?: boolean
) =>
  withSaveAndVerify(
    await new AaveOracle__factory(await getFirstSigner()).deploy(...args),
    eContractid.AaveOracle,
    args,
    verify
  );

export const deployLendingPoolCollateralManager = async (verify?: boolean) => {
  const collateralManagerImpl = await new LendingPoolCollateralManager__factory(
    await getFirstSigner()
  ).deploy();
  await insertContractAddressInDb(
    eContractid.LendingPoolCollateralManagerImpl,
    collateralManagerImpl.address
  );
  return withSaveAndVerify(
    collateralManagerImpl,
    eContractid.LendingPoolCollateralManager,
    [],
    verify
  );
};

export const deployInitializableAdminUpgradeabilityProxy = async (verify?: boolean) =>
  withSaveAndVerify(
    await new InitializableAdminUpgradeabilityProxy__factory(await getFirstSigner()).deploy(),
    eContractid.InitializableAdminUpgradeabilityProxy,
    [],
    verify
  );

export const deployMockFlashLoanReceiver = async (
  addressesProvider: tEthereumAddress,
  verify?: boolean
) =>
  withSaveAndVerify(
    await new MockFlashLoanReceiver__factory(await getFirstSigner()).deploy(addressesProvider),
    eContractid.MockFlashLoanReceiver,
    [addressesProvider],
    verify
  );

export const deployWalletBalancerProvider = async (verify?: boolean) =>
  withSaveAndVerify(
    await new WalletBalanceProvider__factory(await getFirstSigner()).deploy(),
    eContractid.WalletBalanceProvider,
    [],
    verify
  );

export const deployAaveProtocolDataProvider = async (
  addressesProvider: tEthereumAddress,
  verify?: boolean
) =>
  withSaveAndVerify(
    await new AaveProtocolDataProvider__factory(await getFirstSigner()).deploy(addressesProvider),
    eContractid.AaveProtocolDataProvider,
    [addressesProvider],
    verify
  );

export const deployMintableERC20 = async (
  args: [string, string, string],
  verify?: boolean
): Promise<MintableERC20> =>
  withSaveAndVerify(
    await new MintableERC20__factory(await getFirstSigner()).deploy(...args),
    eContractid.MintableERC20,
    args,
    verify
  );

export const deployMintableDelegationERC20 = async (
  args: [string, string, string],
  verify?: boolean
): Promise<MintableDelegationERC20> =>
  withSaveAndVerify(
    await new MintableDelegationERC20__factory(await getFirstSigner()).deploy(...args),
    eContractid.MintableDelegationERC20,
    args,
    verify
  );
export const deployDefaultReserveInterestRateStrategy = async (
  args: [tEthereumAddress, string, string, string, string, string, string],
  verify: boolean
) =>
  withSaveAndVerify(
    await new DefaultReserveInterestRateStrategy__factory(await getFirstSigner()).deploy(...args),
    eContractid.DefaultReserveInterestRateStrategy,
    args,
    verify
  );

export const deployStableDebtToken = async (
  args: [tEthereumAddress, tEthereumAddress, tEthereumAddress, string, string],
  verify: boolean
) => {
  const instance = await withSaveAndVerify(
    await new StableDebtToken__factory(await getFirstSigner()).deploy(),
    eContractid.StableDebtToken,
    [],
    verify
  );

  await instance.initialize(args[0], args[1], args[2], '18', args[3], args[4], '0x10');

  return instance;
};

export const deployVariableDebtToken = async (
  args: [tEthereumAddress, tEthereumAddress, tEthereumAddress, string, string],
  verify: boolean
) => {
  const instance = await withSaveAndVerify(
    await new VariableDebtToken__factory(await getFirstSigner()).deploy(),
    eContractid.VariableDebtToken,
    [],
    verify
  );

  await instance.initialize(args[0], args[1], args[2], '18', args[3], args[4], '0x10');

  return instance;
};

export const deployGenericStableDebtToken = async (verify?: boolean) =>
  withSaveAndVerify(
    await new StableDebtToken__factory(await getFirstSigner()).deploy(),
    eContractid.StableDebtToken,
    [],
    verify
  );

export const deployGenericVariableDebtToken = async (verify?: boolean) =>
  withSaveAndVerify(
    await new VariableDebtToken__factory(await getFirstSigner()).deploy(),
    eContractid.VariableDebtToken,
    [],
    verify
  );

export const deployGenericAToken = async (
  [poolAddress, underlyingAssetAddress, treasuryAddress, incentivesController, name, symbol]: [
    tEthereumAddress,
    tEthereumAddress,
    tEthereumAddress,
    tEthereumAddress,
    string,
    string
  ],
  verify: boolean
) => {
  const instance = await withSaveAndVerify(
    await new AToken__factory(await getFirstSigner()).deploy(),
    eContractid.AToken,
    [],
    verify
  );

  await instance.initialize(
    poolAddress,
    treasuryAddress,
    underlyingAssetAddress,
    incentivesController,
    '18',
    name,
    symbol,
    '0x10'
  );

  return instance;
};

export const deployGenericATokenImpl = async (verify: boolean) =>
  withSaveAndVerify(
    await new AToken__factory(await getFirstSigner()).deploy(),
    eContractid.AToken,
    [],
    verify
  );

export const deployDelegationAwareAToken = async (
  [pool, underlyingAssetAddress, treasuryAddress, incentivesController, name, symbol]: [
    tEthereumAddress,
    tEthereumAddress,
    tEthereumAddress,
    tEthereumAddress,
    string,
    string
  ],
  verify: boolean
) => {
  const instance = await withSaveAndVerify(
    await new DelegationAwareAToken__factory(await getFirstSigner()).deploy(),
    eContractid.DelegationAwareAToken,
    [],
    verify
  );

  await instance.initialize(
    pool,
    treasuryAddress,
    underlyingAssetAddress,
    incentivesController,
    '18',
    name,
    symbol,
    '0x10'
  );

  return instance;
};

export const deployDelegationAwareATokenImpl = async (verify: boolean) =>
  withSaveAndVerify(
    await new DelegationAwareAToken__factory(await getFirstSigner()).deploy(),
    eContractid.DelegationAwareAToken,
    [],
    verify
  );

export const deployAllMockTokens = async (verify?: boolean) => {
  const tokens: { [symbol: string]: MockContract | MintableERC20 } = {};

  const protoConfigData = getReservesConfigByPool(AavePools.proto);

  for (const tokenSymbol of Object.keys(TokenContractId)) {
    let decimals = '18';

    let configData = (<any>protoConfigData)[tokenSymbol];

    tokens[tokenSymbol] = await deployMintableERC20(
      [tokenSymbol, tokenSymbol, configData ? configData.reserveDecimals : decimals],
      verify
    );
    await registerContractInJsonDb(tokenSymbol.toUpperCase(), tokens[tokenSymbol]);
  }
  return tokens;
};

export const deployMockTokens = async (config: PoolConfiguration, verify?: boolean) => {
  const tokens: { [symbol: string]: MockContract | MintableERC20 } = {};
  const defaultDecimals = 18;

  const configData = config.ReservesConfig;

  for (const tokenSymbol of Object.keys(configData)) {
    tokens[tokenSymbol] = await deployMintableERC20(
      [
        tokenSymbol,
        tokenSymbol,
        configData[tokenSymbol as keyof iMultiPoolsAssets<IReserveParams>].reserveDecimals ||
          defaultDecimals.toString(),
      ],
      verify
    );
    await registerContractInJsonDb(tokenSymbol.toUpperCase(), tokens[tokenSymbol]);
  }
  return tokens;
};

export const deployStableAndVariableTokensHelper = async (
  args: [tEthereumAddress, tEthereumAddress],
  verify?: boolean
) =>
  withSaveAndVerify(
    await new StableAndVariableTokensHelper__factory(await getFirstSigner()).deploy(...args),
    eContractid.StableAndVariableTokensHelper,
    args,
    verify
  );

export const deployATokensAndRatesHelper = async (
  args: [tEthereumAddress, tEthereumAddress, tEthereumAddress],
  verify?: boolean
) =>
  withSaveAndVerify(
    await new ATokensAndRatesHelper__factory(await getFirstSigner()).deploy(...args),
    eContractid.ATokensAndRatesHelper,
    args,
    verify
  );

export const deployWETHGateway = async (args: [tEthereumAddress], verify?: boolean) =>
  withSaveAndVerify(
    await new WETHGateway__factory(await getFirstSigner()).deploy(...args),
    eContractid.WETHGateway,
    args,
    verify
  );

export const authorizeWETHGateway = async (
  wethGateWay: tEthereumAddress,
  lendingPool: tEthereumAddress
) =>
  await new WETHGateway__factory(await getFirstSigner())
    .attach(wethGateWay)
    .authorizeLendingPool(lendingPool);

export const deployMockStableDebtToken = async (
  args: [tEthereumAddress, tEthereumAddress, tEthereumAddress, string, string, string],
  verify?: boolean
) => {
  const instance = await withSaveAndVerify(
    await new MockStableDebtToken__factory(await getFirstSigner()).deploy(),
    eContractid.MockStableDebtToken,
    [],
    verify
  );

  await instance.initialize(args[0], args[1], args[2], '18', args[3], args[4], args[5]);

  return instance;
};

export const deployWETHMocked = async (verify?: boolean) =>
  withSaveAndVerify(
    await new WETH9Mocked__factory(await getFirstSigner()).deploy(),
    eContractid.WETHMocked,
    [],
    verify
  );

export const deployMockVariableDebtToken = async (
  args: [tEthereumAddress, tEthereumAddress, tEthereumAddress, string, string, string],
  verify?: boolean
) => {
  const instance = await withSaveAndVerify(
    await new MockVariableDebtToken__factory(await getFirstSigner()).deploy(),
    eContractid.MockVariableDebtToken,
    [],
    verify
  );

  await instance.initialize(args[0], args[1], args[2], '18', args[3], args[4], args[5]);

  return instance;
};

export const deployMockAToken = async (
  args: [
    tEthereumAddress,
    tEthereumAddress,
    tEthereumAddress,
    tEthereumAddress,
    string,
    string,
    string
  ],
  verify?: boolean
) => {
  const instance = await withSaveAndVerify(
    await new MockAToken__factory(await getFirstSigner()).deploy(),
    eContractid.MockAToken,
    [],
    verify
  );

  await instance.initialize(args[0], args[2], args[1], args[3], '18', args[4], args[5], args[6]);

  return instance;
};

export const deploySelfdestructTransferMock = async (verify?: boolean) =>
  withSaveAndVerify(
    await new SelfdestructTransfer__factory(await getFirstSigner()).deploy(),
    eContractid.SelfdestructTransferMock,
    [],
    verify
  );

export const deployMockUniswapRouter = async (verify?: boolean) =>
  withSaveAndVerify(
    await new MockUniswapV2Router02__factory(await getFirstSigner()).deploy(),
    eContractid.MockUniswapV2Router02,
    [],
    verify
  );

export const deployUniswapLiquiditySwapAdapter = async (
  args: [tEthereumAddress, tEthereumAddress, tEthereumAddress],
  verify?: boolean
) =>
  withSaveAndVerify(
    await new UniswapLiquiditySwapAdapter__factory(await getFirstSigner()).deploy(...args),
    eContractid.UniswapLiquiditySwapAdapter,
    args,
    verify
  );

export const deployUniswapRepayAdapter = async (
  args: [tEthereumAddress, tEthereumAddress, tEthereumAddress],
  verify?: boolean
) =>
  withSaveAndVerify(
    await new UniswapRepayAdapter__factory(await getFirstSigner()).deploy(...args),
    eContractid.UniswapRepayAdapter,
    args,
    verify
  );

export const deployFlashLiquidationAdapter = async (
  args: [tEthereumAddress, tEthereumAddress, tEthereumAddress],
  verify?: boolean
) =>
  withSaveAndVerify(
    await new FlashLiquidationAdapter__factory(await getFirstSigner()).deploy(...args),
    eContractid.FlashLiquidationAdapter,
    args,
    verify
  );

export const chooseATokenDeployment = (id: eContractid) => {
  switch (id) {
    case eContractid.AToken:
      return deployGenericATokenImpl;
    case eContractid.DelegationAwareAToken:
      return deployDelegationAwareATokenImpl;
    default:
      throw Error(`Missing aToken implementation deployment script for: ${id}`);
  }
};

export const deployATokenImplementations = async (
  pool: ConfigNames,
  reservesConfig: { [key: string]: IReserveParams },
  verify = false
) => {
  const poolConfig = loadPoolConfig(pool);
  const network = <eNetwork>DRE.network.name;

  // Obtain the different AToken implementations of all reserves inside the Market config
  const aTokenImplementations = [
    ...Object.entries(reservesConfig).reduce<Set<eContractid>>((acc, [, entry]) => {
      acc.add(entry.aTokenImpl);
      return acc;
    }, new Set<eContractid>()),
  ];

  for (let x = 0; x < aTokenImplementations.length; x++) {
    const aTokenAddress = getOptionalParamAddressPerNetwork(
      poolConfig[aTokenImplementations[x].toString()],
      network
    );
    if (!notFalsyOrZeroAddress(aTokenAddress)) {
      const deployImplementationMethod = chooseATokenDeployment(aTokenImplementations[x]);
      console.log(`Deploying implementation`, aTokenImplementations[x]);
      await deployImplementationMethod(verify);
    }
  }

  // Debt tokens, for now all Market configs follows same implementations
  const genericStableDebtTokenAddress = getOptionalParamAddressPerNetwork(
    poolConfig.StableDebtTokenImplementation,
    network
  );
  const geneticVariableDebtTokenAddress = getOptionalParamAddressPerNetwork(
    poolConfig.VariableDebtTokenImplementation,
    network
  );

  if (!notFalsyOrZeroAddress(genericStableDebtTokenAddress)) {
    await deployGenericStableDebtToken(verify);
  }
  if (!notFalsyOrZeroAddress(geneticVariableDebtTokenAddress)) {
    await deployGenericVariableDebtToken(verify);
  }
};

export const deployRateStrategy = async (
  strategyName: string,
  args: [tEthereumAddress, string, string, string, string, string, string],
  verify: boolean
): Promise<tEthereumAddress> => {
  switch (strategyName) {
    default:
      return await (
        await deployDefaultReserveInterestRateStrategy(args, verify)
      ).address;
  }
};
export const deployMockParaSwapAugustus = async (verify?: boolean) =>
  withSaveAndVerify(
    await new MockParaSwapAugustus__factory(await getFirstSigner()).deploy(),
    eContractid.MockParaSwapAugustus,
    [],
    verify
  );

export const deployMockParaSwapAugustusRegistry = async (
  args: [tEthereumAddress],
  verify?: boolean
) =>
  withSaveAndVerify(
    await new MockParaSwapAugustusRegistry__factory(await getFirstSigner()).deploy(...args),
    eContractid.MockParaSwapAugustusRegistry,
    args,
    verify
  );

export const deployParaSwapLiquiditySwapAdapter = async (
  args: [tEthereumAddress, tEthereumAddress],
  verify?: boolean
) =>
  withSaveAndVerify(
    await new ParaSwapLiquiditySwapAdapter__factory(await getFirstSigner()).deploy(...args),
    eContractid.ParaSwapLiquiditySwapAdapter,
    args,
    verify
  );
