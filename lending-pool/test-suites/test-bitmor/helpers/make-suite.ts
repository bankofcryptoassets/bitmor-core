import { evmRevert, evmSnapshot, DRE } from '../../../helpers/misc-utils';
import { Signer } from 'ethers';
import {
  getLendingPool,
  getLendingPoolAddressesProvider,
  getAaveProtocolDataProvider,
  getAToken,
  getMintableERC20,
  getLendingPoolConfiguratorProxy,
  getPriceOracle,
  getLendingPoolAddressesProviderRegistry,
} from '../../../helpers/contracts-getters';
import { eNetwork, tEthereumAddress } from '../../../helpers/types';
import { LendingPool } from '../../../types/LendingPool';
import { AaveProtocolDataProvider } from '../../../types/AaveProtocolDataProvider';
import { MintableERC20 } from '../../../types/MintableERC20';
import { AToken } from '../../../types/AToken';
import { LendingPoolConfigurator } from '../../../types/LendingPoolConfigurator';

import chai from 'chai';
// @ts-ignore
import bignumberChai from 'chai-bignumber';
import { almostEqual } from './almost-equal';
import { PriceOracle } from '../../../types/PriceOracle';
import { LendingPoolAddressesProvider } from '../../../types/LendingPoolAddressesProvider';
import { LendingPoolAddressesProviderRegistry } from '../../../types/LendingPoolAddressesProviderRegistry';
import { getEthersSigners } from '../../../helpers/contracts-helpers';
import { getParamPerNetwork } from '../../../helpers/contracts-helpers';
import { solidity } from 'ethereum-waffle';
import BitmorConfig from '../../../markets/bitmor';
import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { usingTenderly } from '../../../helpers/tenderly-utils';

chai.use(bignumberChai());
chai.use(almostEqual());
chai.use(solidity);

export interface SignerWithAddress {
  signer: Signer;
  address: tEthereumAddress;
}
export interface TestEnv {
  deployer: SignerWithAddress;
  users: SignerWithAddress[];
  pool: LendingPool;
  configurator: LendingPoolConfigurator;
  oracle: PriceOracle;
  helpersContract: AaveProtocolDataProvider;
  usdc: MintableERC20;
  aUsdc: AToken;
  cbBTC: MintableERC20;
  aCbBTC: AToken;
  addressesProvider: LendingPoolAddressesProvider;
  registry: LendingPoolAddressesProviderRegistry;
  // Mock aggregators for price manipulation
  usdcAggregator?: any;
  cbBTCAggregator?: any;
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
  usdc: {} as MintableERC20,
  aUsdc: {} as AToken,
  cbBTC: {} as MintableERC20,
  aCbBTC: {} as AToken,
  addressesProvider: {} as LendingPoolAddressesProvider,
  registry: {} as LendingPoolAddressesProviderRegistry,
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
      getParamPerNetwork(BitmorConfig.ProviderRegistry, process.env.FORK as eNetwork)
    );
  } else {
    testEnv.registry = await getLendingPoolAddressesProviderRegistry();
    testEnv.oracle = await getPriceOracle();
  }

  testEnv.helpersContract = await getAaveProtocolDataProvider();

  const allTokens = await testEnv.helpersContract.getAllATokens();
  
  // Find Bitmor-specific aTokens (only USDC and cbBTC)
  const aUsdcAddress = allTokens.find((aToken) => aToken.symbol === 'aUSDC')?.tokenAddress;
  const aCbBTCAddress = allTokens.find((aToken) => aToken.symbol === 'acbBTC')?.tokenAddress;

  const reservesTokens = await testEnv.helpersContract.getAllReservesTokens();

  const usdcAddress = reservesTokens.find((token) => token.symbol === 'USDC')?.tokenAddress;
  const cbBTCAddress = reservesTokens.find((token) => token.symbol === 'cbBTC')?.tokenAddress;

  if (!aUsdcAddress || !aCbBTCAddress) {
    console.error('Missing aTokens for Bitmor! Expected: aUSDC, acbBTC');
    process.exit(1);
  }
  if (!usdcAddress || !cbBTCAddress) {
    console.error('Missing reserve tokens for Bitmor! Expected: USDC, cbBTC');
    process.exit(1);
  }

  testEnv.aUsdc = await getAToken(aUsdcAddress);
  testEnv.aCbBTC = await getAToken(aCbBTCAddress);

  testEnv.usdc = await getMintableERC20(usdcAddress);
  testEnv.cbBTC = await getMintableERC20(cbBTCAddress);
  
  // Attach mock aggregators
  if ((global as any).mockAggregators) {
    const { MockAggregatorFactory } = await import('../../../types/MockAggregatorFactory');
    const [signer] = await getEthersSigners();
    testEnv.usdcAggregator = MockAggregatorFactory.connect((global as any).mockAggregators.USDC, signer);
    testEnv.cbBTCAggregator = MockAggregatorFactory.connect((global as any).mockAggregators.cbBTC, signer);
  }
}

const setSnapshot = async () => {
  const hre = DRE as HardhatRuntimeEnvironment;
  if (usingTenderly()) {
    setBuidlerevmSnapshotId((await hre.tenderlyNetwork.getHead()) || '0x1');
    return;
  }
  setBuidlerevmSnapshotId(await evmSnapshot());
};

const revertHead = async () => {
  const hre = DRE as HardhatRuntimeEnvironment;
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
