import { readFileSync } from "node:fs";

const CHAIN_TO_NETWORK: Record<string, string> = {
  "31337": "localhost",
  "31337-fork": "localhost",
  "84532": "sepolia",
  "8453": "base",
};

const LP_CONTRACTS: Record<string, string> = {
  LendingPool: "lendingPool.pool",
  LendingPoolAddressesProvider: "lendingPool.addressesProvider",
  AaveOracle: "lendingPool.oracle",
  LendingPoolConfigurator: "lendingPool.configurator",
};

/**
 * Parse lending-pool/deployed-contracts.json and return dot-path -> address map.
 */
export function parseLendingPool(filePath: string, chainKey: string): Record<string, string> {
  const json = JSON.parse(readFileSync(filePath, "utf-8"));
  const network = CHAIN_TO_NETWORK[chainKey];
  if (!network) throw new Error(`Unknown chain key for lending-pool: ${chainKey}`);

  const result: Record<string, string> = {};

  for (const [contractName, registryPath] of Object.entries(LP_CONTRACTS)) {
    const entry = json[contractName]?.[network];
    if (entry?.address) {
      result[registryPath] = entry.address;
    }
  }

  return result;
}
