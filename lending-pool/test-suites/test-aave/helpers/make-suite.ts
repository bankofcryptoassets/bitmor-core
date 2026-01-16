import { evmRevert, evmSnapshot, DRE } from '../../../helpers/misc-utils.js';
import {
  getLendingPool,
  getLendingPoolAddressesProvider,
  getAaveProtocolDataProvider,
  getAToken,
  getMintableERC20,
  getLendingPoolConfiguratorProxy,
  getPriceOracle,
  getLendingPoolAddressesProviderRegistry,
  getWETHMocked,
  getWETHGateway,
  getUniswapLiquiditySwapAdapter,
  getUniswapRepayAdapter,
  getFlashLiquidationAdapter,
  getParaSwapLiquiditySwapAdapter,
} from '../../../helpers/contracts-getters.js';
import type { eNetwork, SignerWithAddress } from '../../../helpers/types.js';
import type { LendingPool } from '../../../types/ethers-contracts/protocol/lendingpool/LendingPool.js';
import type { AaveProtocolDataProvider } from '../../../types/ethers-contracts/misc/AaveProtocolDataProvider.js';
import type { MintableERC20 } from '../../../types/ethers-contracts/mocks/tokens/MintableERC20.js';
import type { AToken } from '../../../types/ethers-contracts/protocol/tokenization/AToken.js';
import type { LendingPoolConfigurator } from '../../../types/ethers-contracts/protocol/lendingpool/LendingPoolConfigurator.js';

import chai from 'chai';
// @ts-ignore
import bignumberChai from 'chai-bignumber';
import { almostEqual } from './almost-equal.js';
import type { PriceOracle } from '../../../types/ethers-contracts/mocks/oracle/PriceOracle.js';
import type { LendingPoolAddressesProvider } from '../../../types/ethers-contracts/protocol/configuration/LendingPoolAddressesProvider.js';
import type { LendingPoolAddressesProviderRegistry } from '../../../types/ethers-contracts/protocol/configuration/LendingPoolAddressesProviderRegistry.js';
import { getEthersSigners } from '../../../helpers/contracts-helpers.js';
import type { UniswapLiquiditySwapAdapter } from '../../../types/ethers-contracts/adapters/UniswapLiquiditySwapAdapter.js';
import type { UniswapRepayAdapter } from '../../../types/ethers-contracts/adapters/UniswapRepayAdapter.js';
import type { ParaSwapLiquiditySwapAdapter } from '../../../types/ethers-contracts/adapters/ParaSwapLiquiditySwapAdapter.js';
import { getParamPerNetwork } from '../../../helpers/contracts-helpers.js';
import type { WETH9Mocked } from '../../../types/ethers-contracts/mocks/tokens/WETH9Mocked.js';
import type { WETHGateway } from '../../../types/ethers-contracts/misc/WETHGateway.js';
import { AaveConfig } from '../../../markets/aave/index.js';
import type { FlashLiquidationAdapter } from '../../../types/ethers-contracts/adapters/FlashLiquidationAdapter.js';
import { usingTenderly } from '../../../helpers/tenderly-utils.js';

chai.use(bignumberChai());
chai.use(almostEqual());

export interface TestEnv {
  deployer: SignerWithAddress;
  users: SignerWithAddress[];
  pool: LendingPool;
  configurator: LendingPoolConfigurator;
  oracle: PriceOracle;
  helpersContract: AaveProtocolDataProvider;
  weth: WETH9Mocked;
  aWETH: AToken;
  dai: MintableERC20;
  aDai: AToken;
  usdc: MintableERC20;
  aave: MintableERC20;
  addressesProvider: LendingPoolAddressesProvider;
  uniswapLiquiditySwapAdapter: UniswapLiquiditySwapAdapter;
  uniswapRepayAdapter: UniswapRepayAdapter;
  registry: LendingPoolAddressesProviderRegistry;
  wethGateway: WETHGateway;
  flashLiquidationAdapter: FlashLiquidationAdapter;
  paraswapLiquiditySwapAdapter: ParaSwapLiquiditySwapAdapter;
}

let buidlerevmSnapshotId: string = '0x1';
const setBuidlerevmSnapshotId = (id: string) => {
  buidlerevmSnapshotId = id;
};

const testEnv: TestEnv = {
  deployer: {} as SignerWithAddress,
  users: [] as SignerWithAddress[],
  pool: {} as LendingPool,
  configurator: {} as LendingPoolConfigurator,
  helpersContract: {} as AaveProtocolDataProvider,
  oracle: {} as PriceOracle,
  weth: {} as WETH9Mocked,
  aWETH: {} as AToken,
  dai: {} as MintableERC20,
  aDai: {} as AToken,
  usdc: {} as MintableERC20,
  aave: {} as MintableERC20,
  addressesProvider: {} as LendingPoolAddressesProvider,
  uniswapLiquiditySwapAdapter: {} as UniswapLiquiditySwapAdapter,
  uniswapRepayAdapter: {} as UniswapRepayAdapter,
  flashLiquidationAdapter: {} as FlashLiquidationAdapter,
  paraswapLiquiditySwapAdapter: {} as ParaSwapLiquiditySwapAdapter,
  registry: {} as LendingPoolAddressesProviderRegistry,
  wethGateway: {} as WETHGateway,
} as TestEnv;

export async function initializeMakeSuite() {
  const [_deployer, ...restSigners] = await getEthersSigners();
  const deployer: SignerWithAddress = {
    address: await _deployer.getAddress(),
    signer: _deployer,
  };

  for (const signer of restSigners) {
    testEnv.users.push({
      signer,
      address: await signer.getAddress(),
    });
  }
  testEnv.deployer = deployer;
  testEnv.pool = await getLendingPool();

  testEnv.configurator = await getLendingPoolConfiguratorProxy();

  testEnv.addressesProvider = await getLendingPoolAddressesProvider();

  if (process.env.FORK) {
    testEnv.registry = await getLendingPoolAddressesProviderRegistry(
      getParamPerNetwork(AaveConfig.ProviderRegistry, process.env.FORK as eNetwork)
    );
  } else {
    testEnv.registry = await getLendingPoolAddressesProviderRegistry();
    testEnv.oracle = await getPriceOracle();
  }

  testEnv.helpersContract = await getAaveProtocolDataProvider();

  const allTokens = await testEnv.helpersContract.getAllATokens();
  const aDaiAddress = allTokens.find((aToken) => aToken.symbol === 'aDAI')?.tokenAddress;

  const aWEthAddress = allTokens.find((aToken) => aToken.symbol === 'aWETH')?.tokenAddress;

  const reservesTokens = await testEnv.helpersContract.getAllReservesTokens();

  const daiAddress = reservesTokens.find((token) => token.symbol === 'DAI')?.tokenAddress;
  const usdcAddress = reservesTokens.find((token) => token.symbol === 'USDC')?.tokenAddress;
  const aaveAddress = reservesTokens.find((token) => token.symbol === 'AAVE')?.tokenAddress;
  const wethAddress = reservesTokens.find((token) => token.symbol === 'WETH')?.tokenAddress;

  if (!aDaiAddress || !aWEthAddress) {
    process.exit(1);
  }
  if (!daiAddress || !usdcAddress || !aaveAddress || !wethAddress) {
    process.exit(1);
  }

  testEnv.aDai = await getAToken(aDaiAddress);
  testEnv.aWETH = await getAToken(aWEthAddress);

  testEnv.dai = await getMintableERC20(daiAddress);
  testEnv.usdc = await getMintableERC20(usdcAddress);
  testEnv.aave = await getMintableERC20(aaveAddress);
  testEnv.weth = await getWETHMocked(wethAddress);
  testEnv.wethGateway = await getWETHGateway();

  testEnv.uniswapLiquiditySwapAdapter = await getUniswapLiquiditySwapAdapter();
  testEnv.uniswapRepayAdapter = await getUniswapRepayAdapter();
  testEnv.flashLiquidationAdapter = await getFlashLiquidationAdapter();

  testEnv.paraswapLiquiditySwapAdapter = await getParaSwapLiquiditySwapAdapter();
}

const setSnapshot = async () => {
  const hre = DRE;
  if (usingTenderly()) {
    setBuidlerevmSnapshotId((await hre.tenderlyNetwork.getHead()) || '0x1');
    return;
  }
  setBuidlerevmSnapshotId(await evmSnapshot());
};

const revertHead = async () => {
  const hre = DRE;
  if (usingTenderly()) {
    await hre.tenderlyNetwork.setHead(buidlerevmSnapshotId);
    return;
  }
  await evmRevert(buidlerevmSnapshotId);
};

export function makeSuite(name: string, tests: (testEnv: TestEnv) => void) {
  describe(name, () => {
    before(async () => {
      await setSnapshot();
    });
    tests(testEnv);
    after(async () => {
      await revertHead();
    });
  });
}

// Re-export for backward compatibility
export type { SignerWithAddress };
