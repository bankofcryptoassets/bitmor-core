import { execFileSync } from "node:child_process";

/**
 * Reserve token addresses extracted from LendingPool.getReserveData()
 */
export interface ReserveTokens {
  underlying: string;
  aToken: string;
  variableDebtToken: string;
}

/**
 * Query LendingPool for all reserve token addresses using cast.
 *
 * 1. Call getReservesList() to get all underlying asset addresses
 * 2. For each asset, call getReserveData(asset) to get aToken + VDT addresses
 */
export function queryReserveTokens(poolAddress: string, rpcUrl: string): ReserveTokens[] {
  const reservesListRaw = execFileSync(
    "cast",
    ["call", poolAddress, "getReservesList()(address[])", "--rpc-url", rpcUrl],
    { encoding: "utf-8" }
  ).trim();

  const reserveAddresses = parseAddressArray(reservesListRaw);

  if (reserveAddresses.length === 0) {
    throw new Error("No reserves found in LendingPool");
  }

  const results: ReserveTokens[] = [];

  for (const asset of reserveAddresses) {
    const reserveDataRaw = execFileSync(
      "cast",
      [
        "call",
        poolAddress,
        "getReserveData(address)((uint256,uint128,uint128,uint128,uint128,uint128,uint40,address,address,address,address,uint8))",
        asset,
        "--rpc-url",
        rpcUrl,
      ],
      { encoding: "utf-8" }
    ).trim();

    const { aToken, variableDebtToken } = parseTupleAddresses(reserveDataRaw);

    results.push({
      underlying: asset.toLowerCase(),
      aToken: aToken.toLowerCase(),
      variableDebtToken: variableDebtToken.toLowerCase(),
    });
  }

  return results;
}

/**
 * Identify a reserve by querying the aToken symbol via cast.
 * Fallback for fork deployments where tokens.usdc is not in the registry.
 */
export function identifyReserve(aTokenAddress: string, rpcUrl: string): string | null {
  try {
    const symbol = execFileSync(
      "cast",
      ["call", aTokenAddress, "symbol()(string)", "--rpc-url", rpcUrl],
      { encoding: "utf-8" }
    ).trim();

    const lower = symbol.toLowerCase();
    if (lower.includes("usdc")) return "usdc";
    if (lower.includes("bvbtc") || lower.includes("btc")) return "bvBTC";
    return null;
  } catch {
    return null;
  }
}

/**
 * Map reserve tokens to registry dot-paths.
 *
 * Uses knownAssets (underlying address → name) as primary lookup.
 * Falls back to aToken symbol identification via RPC when underlying is unknown.
 */
export function mapReservesToRegistry(
  reserves: ReserveTokens[],
  knownAssets: Record<string, string>,
  rpcUrl?: string
): Record<string, string> {
  const result: Record<string, string> = {};

  for (const reserve of reserves) {
    let name = knownAssets[reserve.underlying];

    if (!name && rpcUrl) {
      name = identifyReserve(reserve.aToken, rpcUrl) ?? (undefined as any);
    }

    if (!name) {
      console.warn(`[bitmor-deploy] Unknown reserve underlying: ${reserve.underlying}, skipping`);
      continue;
    }

    result[`lendingPool.reserves.${name}.aToken`] = reserve.aToken;
    result[`lendingPool.reserves.${name}.variableDebtToken`] = reserve.variableDebtToken;
  }

  return result;
}

/**
 * Parse cast output of address[] — cast returns: [0xAddr1, 0xAddr2]
 */
export function parseAddressArray(raw: string): string[] {
  const inner = raw.replace(/^\[/, "").replace(/\]$/, "").trim();
  if (!inner) return [];
  return inner
    .split(/,\s*/)
    .map((s) => s.trim())
    .filter((s) => s.startsWith("0x"));
}

/**
 * Parse cast output of ReserveData tuple to extract aToken and variableDebtToken.
 *
 * cast returns a single-line tuple like:
 * (74354491629445928, 1e27, ..., 0x50778..., 0xb54B4..., 0x097A4..., 0x95401..., 1)
 *
 * Addresses are the 4 consecutive 0x-prefixed fields: aToken, stableDebt, varDebt, strategy.
 */
export function parseTupleAddresses(raw: string): { aToken: string; variableDebtToken: string } {
  const inner = raw.replace(/^\(/, "").replace(/\)$/, "").trim();
  const fields = inner.split(/,\s*/);

  const addresses = fields.filter((f) => f.startsWith("0x"));
  if (addresses.length < 3) {
    throw new Error(`Expected at least 3 addresses in ReserveData tuple, got ${addresses.length}: ${raw}`);
  }

  return {
    aToken: addresses[0],
    variableDebtToken: addresses[2],
  };
}
