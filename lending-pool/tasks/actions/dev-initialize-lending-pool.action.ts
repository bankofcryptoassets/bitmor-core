import type { HardhatRuntimeEnvironment } from 'hardhat/types/hre';
import {
  deployLendingPoolCollateralManager,
  deployMockFlashLoanReceiver,
  deployWalletBalancerProvider,
  deployAaveProtocolDataProvider,
  authorizeWETHGateway,
} from '../../helpers/contracts-deployments.js';
import { getParamPerNetwork, insertContractAddressInDb, getContractAddress } from '../../helpers/contracts-helpers.js';
import { eNetwork } from '../../helpers/types.js';
import {
  ConfigNames,
  getTreasuryAddress,
  loadPoolConfig,
  getEmergencyAdmin,
} from '../../helpers/configuration.js';

import { tEthereumAddress, eContractid } from '../../helpers/types.js';
import { waitForTx, filterMapBy, notFalsyOrZeroAddress } from '../../helpers/misc-utils.js';
import { configureReservesByHelper, initReservesByHelper } from '../../helpers/init-helpers.js';
import { getAllTokenAddresses } from '../../helpers/mock-helpers.js';
import { ZERO_ADDRESS } from '../../helpers/constants.js';
import {
  getAllMockedTokens,
  getLendingPoolAddressesProvider,
  getLendingPoolConfiguratorProxy,
  getWETHGateway,
} from '../../helpers/contracts-getters.js';

type Args = {
  verify: boolean;
  pool: string;
};

export default async function devInitializeLendingPoolAction(
  { verify, pool }: Args,
  hre: HardhatRuntimeEnvironment
) {
  await hre.tasks.getTask('set-DRE').run({});

  // Validate pool name
  if (!pool || !Object.values(ConfigNames).includes(pool as ConfigNames)) {
    throw new Error(
      `Invalid --pool "${pool}". Supported: ${Object.values(ConfigNames).join(', ')}`
    );
  }

  const conn = await hre.network.connect();
  const network = conn.networkName as eNetwork;
  const poolConfig = loadPoolConfig(pool as ConfigNames);
  const {
    ATokenNamePrefix,
    StableDebtTokenNamePrefix,
    VariableDebtTokenNamePrefix,
    SymbolPrefix,
    WethGateway,
    ReservesConfig,
  } = poolConfig;

  // Get all mock tokens from database (Aave's approach for dev/localhost)
  const mockTokens = await getAllMockedTokens();
  const allTokenAddresses = getAllTokenAddresses(mockTokens);

  const addressesProvider = await getLendingPoolAddressesProvider();

  // Filter out UNI tokens for pool reserves
  const protoPoolReservesAddresses = <{ [symbol: string]: tEthereumAddress }>(
    filterMapBy(allTokenAddresses, (key: string) => !key.includes('UNI_'))
  );

  const testHelpers = await deployAaveProtocolDataProvider(getContractAddress(addressesProvider), verify);
  await insertContractAddressInDb(eContractid.AaveProtocolDataProvider, getContractAddress(testHelpers));

  const admin = await addressesProvider.getPoolAdmin();

  const treasuryAddress = await getTreasuryAddress(poolConfig);

  await initReservesByHelper(
    ReservesConfig,
    protoPoolReservesAddresses,
    ATokenNamePrefix,
    StableDebtTokenNamePrefix,
    VariableDebtTokenNamePrefix,
    SymbolPrefix,
    admin,
    treasuryAddress,
    ZERO_ADDRESS,
    pool as ConfigNames,
    verify
  );
  await configureReservesByHelper(ReservesConfig, protoPoolReservesAddresses, testHelpers, admin);

  const collateralManager = await deployLendingPoolCollateralManager(verify);
  await waitForTx(
    await addressesProvider.setLendingPoolCollateralManager(getContractAddress(collateralManager))
  );

  const mockFlashLoanReceiver = await deployMockFlashLoanReceiver(
    getContractAddress(addressesProvider),
    verify
  );
  await insertContractAddressInDb(
    eContractid.MockFlashLoanReceiver,
    getContractAddress(mockFlashLoanReceiver)
  );

  await deployWalletBalancerProvider(verify);

  const lendingPoolAddress = await addressesProvider.getLendingPool();

  let gateway = getParamPerNetwork(WethGateway, network);
  if (!notFalsyOrZeroAddress(gateway)) {
    gateway = getContractAddress(await getWETHGateway());
  }
  await authorizeWETHGateway(gateway, lendingPoolAddress);

  // Unpause protocol using emergency admin signer (required by onlyEmergencyAdmin modifier)
  const emergencyAdminAddress = await getEmergencyAdmin(poolConfig);
  const emergencyAdmin = await conn.ethers.getSigner(emergencyAdminAddress);
  const poolConfigurator = await getLendingPoolConfiguratorProxy();
  await waitForTx(await poolConfigurator.connect(emergencyAdmin).setPoolPause(false));
}
