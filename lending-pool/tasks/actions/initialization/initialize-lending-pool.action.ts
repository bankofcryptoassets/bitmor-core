import type { HardhatRuntimeEnvironment } from 'hardhat/types/hre';
import { getParamPerNetwork, getContractAddress } from '../../../helpers/contracts-helpers.js';
import {
  deployLendingPoolCollateralManager,
  deployWalletBalancerProvider,
  authorizeWETHGateway,
} from '../../../helpers/contracts-deployments.js';
import { loadPoolConfig, ConfigNames, getTreasuryAddress } from '../../../helpers/configuration.js';
import { getWETHGateway } from '../../../helpers/contracts-getters.js';
import { eNetwork, ICommonConfiguration } from '../../../helpers/types.js';
import { notFalsyOrZeroAddress, waitForTx } from '../../../helpers/misc-utils.js';
import { initReservesByHelper, configureReservesByHelper } from '../../../helpers/init-helpers.js';
import {
  getAaveProtocolDataProvider,
  getLendingPoolAddressesProvider,
} from '../../../helpers/contracts-getters.js';

type Args = {
  verify: boolean;
  pool: string;
};

export default async function initializeLendingPoolAction(
  { verify, pool }: Args,
  hre: HardhatRuntimeEnvironment
) {
  try {
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
      ReserveAssets,
      ReservesConfig,
      LendingPoolCollateralManager,
      WethGateway,
      IncentivesController,
    } = poolConfig as ICommonConfiguration;

    const reserveAssets = await getParamPerNetwork(ReserveAssets, network);
    const incentivesController = await getParamPerNetwork(IncentivesController, network);
    const addressesProvider = await getLendingPoolAddressesProvider();

    const testHelpers = await getAaveProtocolDataProvider();

    const admin = await addressesProvider.getPoolAdmin();
    const oracle = await addressesProvider.getPriceOracle();

    if (!reserveAssets) {
      throw 'Reserve assets is undefined. Check ReserveAssets configuration at config directory';
    }

    const treasuryAddress = await getTreasuryAddress(poolConfig);

    await initReservesByHelper(
      ReservesConfig,
      reserveAssets,
      ATokenNamePrefix,
      StableDebtTokenNamePrefix,
      VariableDebtTokenNamePrefix,
      SymbolPrefix,
      admin,
      treasuryAddress,
      incentivesController,
      pool as ConfigNames,
      verify
    );
    await configureReservesByHelper(ReservesConfig, reserveAssets, testHelpers, admin);

    let collateralManagerAddress = await getParamPerNetwork(
      LendingPoolCollateralManager,
      network
    );
    if (!notFalsyOrZeroAddress(collateralManagerAddress)) {
      const collateralManager = await deployLendingPoolCollateralManager(verify);
      collateralManagerAddress = getContractAddress(collateralManager);
    }
    // Seems unnecessary to register the collateral manager in the JSON db

    console.log(
      '\tSetting lending pool collateral manager implementation with address',
      collateralManagerAddress
    );
    await waitForTx(
      await addressesProvider.setLendingPoolCollateralManager(collateralManagerAddress)
    );

    console.log(
      '\tSetting AaveProtocolDataProvider at AddressesProvider at id: 0x01',
      collateralManagerAddress
    );
    const aaveProtocolDataProvider = await getAaveProtocolDataProvider();
    await waitForTx(
      await addressesProvider.setAddress(
        '0x0100000000000000000000000000000000000000000000000000000000000000',
        getContractAddress(aaveProtocolDataProvider)
      )
    );

    await deployWalletBalancerProvider(verify);

    const lendingPoolAddress = await addressesProvider.getLendingPool();

    let gateWay = getParamPerNetwork(WethGateway, network);
    if (!notFalsyOrZeroAddress(gateWay)) {
      try {
        const wethGateway = await getWETHGateway();
        if (wethGateway) {
          gateWay = getContractAddress(wethGateway);
        }
      } catch (e) {
        console.log('No WETH Gateway found, skipping authorization');
      }
    }
    if (notFalsyOrZeroAddress(gateWay)) {
      await authorizeWETHGateway(gateWay, lendingPoolAddress);
    }
  } catch (err) {
    console.error(err);
    throw err;
  }
}
