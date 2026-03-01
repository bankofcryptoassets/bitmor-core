/**
 * Test environment setup for Hardhat 3 / ethers v6.
 *
 * TestEnv additions for Bitmor testing:
 * - cbBTC: Underlying BTC token (8 decimals)
 * - btcVault: MockBTCVault for cbBTC → bvBTC vault shares
 * - mockLoan: MockLoan for liquidation testing (configurable loan state)
 * - mockLoanProvider, mockBitmorUSDCVault: Bitmor caller mocks
 *
 * cbBTC is retrieved from database (deployed in __setup.spec.ts, not as lending reserve).
 */

import { evmRevert, evmSnapshot, DRE, getDb } from '../../../helpers/misc-utils.js';
import {
  getLendingPool,
  getLendingPoolAddressesProvider,
  getAaveProtocolDataProvider,
  getAToken,
  getMintableERC20,
  getLendingPoolConfiguratorProxy,
  getAaveOracle,
  getLendingPoolAddressesProviderRegistry,
  getWETHMocked,
  getMockBTCVault,
  getMockLoan,
  getMockAggregator,
} from '../../../helpers/contracts-getters.js';
import type { eNetwork, SignerWithAddress } from '../../../helpers/types.js';
import type { LendingPool } from '../../../types/ethers-contracts/protocol/lendingpool/LendingPool.js';
import type { AaveProtocolDataProvider } from '../../../types/ethers-contracts/misc/AaveProtocolDataProvider.js';
import type { MintableERC20 } from '../../../types/ethers-contracts/mocks/tokens/MintableERC20.js';
import type { AToken } from '../../../types/ethers-contracts/protocol/tokenization/AToken.js';
import type { LendingPoolConfigurator } from '../../../types/ethers-contracts/protocol/lendingpool/LendingPoolConfigurator.js';

import * as chai from 'chai';
// @ts-ignore
import bignumberChai from 'chai-bignumber';
import { almostEqual } from './almost-equal.js';
import type { AaveOracle } from '../../../types/ethers-contracts/misc/AaveOracle.js';
import type { LendingPoolAddressesProvider } from '../../../types/ethers-contracts/protocol/configuration/LendingPoolAddressesProvider.js';
import type { LendingPoolAddressesProviderRegistry } from '../../../types/ethers-contracts/protocol/configuration/LendingPoolAddressesProviderRegistry.js';
import { getEthersSigners } from '../../../helpers/contracts-helpers.js';
import { getParamPerNetwork } from '../../../helpers/contracts-helpers.js';
import type { WETH9Mocked } from '../../../types/ethers-contracts/mocks/tokens/WETH9Mocked.js';
import { AaveConfig } from '../../../markets/aave/index.js';
import type { MockBTCVault } from '../../../types/ethers-contracts/mocks/vault/MockBTCVault.js';
import type { MockLoan } from '../../../types/ethers-contracts/mocks/MockLoan.js';
import type { MockAggregator } from '../../../types/ethers-contracts/mocks/oracle/CLAggregators/MockAggregator.js';
import { usingTenderly } from '../../../helpers/tenderly-utils.js';
import { deployMockBitmorCallers, BitmorMocks } from './deploy-bitmor-mocks.js';
import type { MockLoanProvider } from '../../../types/ethers-contracts/mocks/MockBitmorCaller.sol/MockLoanProvider.js';
import type { MockUSDCVault as MockBitmorUSDCVault } from '../../../types/ethers-contracts/mocks/vault/MockUSDCVault.js';

chai.use(bignumberChai());
chai.use(almostEqual());

export interface TestEnv {
  deployer: SignerWithAddress;
  users: SignerWithAddress[];
  pool: LendingPool;
  configurator: LendingPoolConfigurator;
  oracle: AaveOracle;
  helpersContract: AaveProtocolDataProvider;
  weth: WETH9Mocked;
  aWETH: AToken;
  dai: MintableERC20;
  aDai: AToken;
  usdc: MintableERC20;
  aUSDC: AToken;
  aave: MintableERC20;
  addressesProvider: LendingPoolAddressesProvider;
  registry: LendingPoolAddressesProviderRegistry;
  // Bitmor mock callers
  mockLoanProvider: MockLoanProvider;
  mockBitmorUSDCVault: MockBitmorUSDCVault;
  // BTC Vault infrastructure
  cbBTC: MintableERC20;      // Underlying BTC token (8 decimals) - used for minting vault shares
  bvBTC: MintableERC20;      // ERC4626 vault shares (btcVault as MintableERC20 interface)
  abvBTC: AToken;            // aToken for bvBTC vault shares (the actual collateral)
  btcVault: MockBTCVault;
  // Loan infrastructure
  mockLoan: MockLoan;
  // Price aggregators for test price manipulation
  aggregators: { [symbol: string]: MockAggregator };
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
  oracle: {} as AaveOracle,
  weth: {} as WETH9Mocked,
  aWETH: {} as AToken,
  dai: {} as MintableERC20,
  aDai: {} as AToken,
  usdc: {} as MintableERC20,
  aUSDC: {} as AToken,
  aave: {} as MintableERC20,
  addressesProvider: {} as LendingPoolAddressesProvider,
  registry: {} as LendingPoolAddressesProviderRegistry,
  mockLoanProvider: {} as MockLoanProvider,
  mockBitmorUSDCVault: {} as MockBitmorUSDCVault,
  cbBTC: {} as MintableERC20,
  bvBTC: {} as MintableERC20,
  abvBTC: {} as AToken,
  btcVault: {} as MockBTCVault,
  mockLoan: {} as MockLoan,
  aggregators: {} as { [symbol: string]: MockAggregator },
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
    // Use AaveOracle (protocol's actual oracle) instead of fallback PriceOracle
    testEnv.oracle = await getAaveOracle();
  }

  testEnv.helpersContract = await getAaveProtocolDataProvider();

  const allTokens = await testEnv.helpersContract.getAllATokens();

  const aDaiAddress = allTokens.find((aToken) => aToken.symbol === 'aDAI')?.tokenAddress;

  const abvBTCAddress = allTokens.find((aToken) => aToken.symbol === 'abvBTC')?.tokenAddress;

  const aUSDCAddress = allTokens.find((aToken) => aToken.symbol === 'aUSDC')?.tokenAddress;

  const aWEthAddress = allTokens.find((aToken) => aToken.symbol === 'aWETH')?.tokenAddress;

  const reservesTokens = await testEnv.helpersContract.getAllReservesTokens();

  const daiAddress = reservesTokens.find((token) => token.symbol === 'DAI')?.tokenAddress;
  const usdcAddress = reservesTokens.find((token) => token.symbol === 'USDC')?.tokenAddress;
  const aaveAddress = reservesTokens.find((token) => token.symbol === 'AAVE')?.tokenAddress;
  const wethAddress = reservesTokens.find((token) => token.symbol === 'WETH')?.tokenAddress;
  const bvBTCAddress = reservesTokens.find((token) => token.symbol === 'bvBTC')?.tokenAddress;

  if (!aDaiAddress || !aUSDCAddress || !aWEthAddress) {
    process.exit(1);
  }
  if (!daiAddress || !usdcAddress || !aaveAddress || !wethAddress) {
    process.exit(1);
  }

  testEnv.aDai = await getAToken(aDaiAddress);
  testEnv.aUSDC = await getAToken(aUSDCAddress);
  testEnv.aWETH = await getAToken(aWEthAddress);
  if (abvBTCAddress) {
    testEnv.abvBTC = await getAToken(abvBTCAddress);
  }

  testEnv.dai = await getMintableERC20(daiAddress);
  testEnv.usdc = await getMintableERC20(usdcAddress);
  testEnv.aave = await getMintableERC20(aaveAddress);
  testEnv.weth = await getWETHMocked(wethAddress);
  if (bvBTCAddress) {
    testEnv.bvBTC = await getMintableERC20(bvBTCAddress);
  }

  // Deploy Bitmor mock callers
  const bitmorMocks = await deployMockBitmorCallers(usdcAddress);
  testEnv.mockLoanProvider = bitmorMocks.mockLoanProvider;
  testEnv.mockBitmorUSDCVault = bitmorMocks.mockUSDCVault;

  // Get cbBTC token (deployed separately, not as a reserve)
  // NOTE: cbBTC is deployed in __setup.spec.ts but not initialized as a lending reserve.
  // We get it directly from the database where it was registered during setup.
  try {
    const cbBTCEntry = await getDb().get(`cbBTC.${DRE.network.networkName}`).value();
    if (cbBTCEntry && cbBTCEntry.address) {
      testEnv.cbBTC = await getMintableERC20(cbBTCEntry.address);
    }
  } catch (e) {
    console.log('cbBTC not found in database');
  }

  // Get BTC vault
  try {
    testEnv.btcVault = await getMockBTCVault();
  } catch (e) {
    console.log('MockBTCVault not deployed');
  }

  // Get Mock Loan
  try {
    testEnv.mockLoan = await getMockLoan();
  } catch (e) {
    console.log('MockLoan not deployed');
  }

  // Load price aggregators for test price manipulation
  // These are used instead of oracle.setAssetPrice() when using AaveOracle
  const aggregatorSymbols = ['USDC', 'cbBTC', 'WETH', 'DAI', 'AAVE'];
  for (const symbol of aggregatorSymbols) {
    try {
      testEnv.aggregators[symbol] = await getMockAggregator(symbol);
    } catch (e) {
      // Aggregator not deployed for this symbol
    }
  }
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
