// tasks/actions/print-config.action.ts
import { HardhatRuntimeEnvironment } from "hardhat/types/hre";
import { ConfigNames, loadPoolConfig } from "../../../helpers/configuration.js";
import {
  getAaveProtocolDataProvider,
  getLendingPoolAddressesProvider,
  getLendingPoolAddressesProviderRegistry,
} from "../../../helpers/contracts-getters.js";
import { getParamPerNetwork } from "../../../helpers/contracts-helpers.js";
import { eNetwork } from "../../../helpers/types.js";

type Args = {
  dataProvider: string;
  pool: string;
};

function asConfigName(pool: string): ConfigNames {
  // Validate: pool must be one of the enum values
  if (!Object.values(ConfigNames).includes(pool as ConfigNames)) {
    throw new Error(
      `Invalid --pool "${pool}". Supported: ${Object.values(ConfigNames).join(", ")}`
    );
  }
  return pool as ConfigNames;
}

export default async function printConfigAction(
  { pool, dataProvider }: Args,
  hre: HardhatRuntimeEnvironment
) {
  // v3 way to run another task:
  await hre.tasks.getTask("set-DRE").run({});

  if (!pool) {
    throw new Error(`Missing --pool. Supported: ${Object.values(ConfigNames).join(", ")}`);
  }
  if (!dataProvider) {
    throw new Error("Missing --data-provider (aka --dataProvider depending on CLI).");
  }

  const conn = await hre.network.connect();
  const network = (process.env.FORK ? process.env.FORK : conn.networkName) as eNetwork;

  const poolName = asConfigName(pool);
  const poolConfig = loadPoolConfig(poolName);

  const providerRegistryAddress = getParamPerNetwork(poolConfig.ProviderRegistry, network);
  const providerRegistry = await getLendingPoolAddressesProviderRegistry(providerRegistryAddress);

  const providers = await providerRegistry.getAddressesProvidersList();
  const addressesProvider = await getLendingPoolAddressesProvider(providers[0]);

  console.log("Addresses Providers", providers.join(", "));
  console.log("Market Id: ", await addressesProvider.getMarketId());
  console.log("LendingPool Proxy:", await addressesProvider.getLendingPool());
  console.log("Lending Pool Collateral Manager", await addressesProvider.getLendingPoolCollateralManager());
  console.log("Lending Pool Configurator proxy", await addressesProvider.getLendingPoolConfigurator());
  console.log("Pool admin", await addressesProvider.getPoolAdmin());
  console.log("Emergency admin", await addressesProvider.getEmergencyAdmin());
  console.log("Price Oracle", await addressesProvider.getPriceOracle());
  console.log("Lending Rate Oracle", await addressesProvider.getLendingRateOracle());
  console.log("Lending Pool Data Provider", dataProvider);

  const protocolDataProvider = await getAaveProtocolDataProvider(dataProvider);

  const fields = [
    "decimals",
    "ltv",
    "liquidationThreshold",
    "liquidationBonus",
    "reserveFactor",
    "usageAsCollateralEnabled",
    "borrowingEnabled",
    "stableBorrowRateEnabled",
    "isActive",
    "isFrozen",
  ] as const;

  const tokensFields = ["aToken", "stableDebtToken", "variableDebtToken"] as const;

  const reserveAssets = getParamPerNetwork(poolConfig.ReserveAssets, network as eNetwork);

  for (const [symbol, address] of Object.entries(reserveAssets)) {
    console.log(`- ${symbol} asset config`);
    console.log(`  - reserve address: ${address}`);

    const reserveData: any = await protocolDataProvider.getReserveConfigurationData(address);
    const tokensAddresses: any = await protocolDataProvider.getReserveTokensAddresses(address);

    for (const field of fields) {
      console.log(`  - ${field}:`, reserveData[field].toString());
    }

    tokensFields.forEach((field, index) => {
      console.log(`  - ${field}:`, tokensAddresses[index]);
    });
  }
}
