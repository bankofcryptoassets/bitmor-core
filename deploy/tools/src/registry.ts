import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";

export interface Registry {
  network: string;
  chainId: number;
  timestamp: number;
  commit: string;
  deployer: string;
  loanProvider: Record<string, any>;
  lendingPool: Record<string, any>;
  tokens: Record<string, any>;
  external: Record<string, any>;
}

export function readRegistry(deploymentsDir: string, chainKey: string): Registry | null {
  const latestPath = join(deploymentsDir, chainKey, "latest.json");
  if (!existsSync(latestPath)) return null;
  return JSON.parse(readFileSync(latestPath, "utf-8"));
}

export function writeRegistry(deploymentsDir: string, chainKey: string, data: Registry): void {
  const chainDir = join(deploymentsDir, chainKey);
  mkdirSync(chainDir, { recursive: true });

  const latestPath = join(chainDir, "latest.json");
  const content = JSON.stringify(data, null, 2) + "\n";
  writeFileSync(latestPath, content);

  // Create timestamped snapshot
  const snapshotPath = join(chainDir, `${data.timestamp}.json`);
  writeFileSync(snapshotPath, content);
}

/**
 * Deep merge dot-path updates into an existing registry.
 * E.g., "loanProvider.loan" -> sets registry.loanProvider.loan
 */
export function mergeIntoRegistry(
  existing: Registry,
  updates: Record<string, string>,
  timestamp: number,
  commit: string,
  deployer?: string
): Registry {
  const result = JSON.parse(JSON.stringify(existing)) as Registry;
  result.timestamp = timestamp;
  result.commit = commit;
  if (deployer) result.deployer = deployer;

  for (const [dotPath, value] of Object.entries(updates)) {
    setNestedValue(result, dotPath, value);
  }

  return result;
}

function setNestedValue(obj: any, dotPath: string, value: any): void {
  const parts = dotPath.split(".");
  let current = obj;
  for (let i = 0; i < parts.length - 1; i++) {
    if (!(parts[i] in current) || typeof current[parts[i]] !== "object") {
      current[parts[i]] = {};
    }
    current = current[parts[i]];
  }
  current[parts[parts.length - 1]] = value;
}

/**
 * Create a fresh empty registry for a chain.
 */
export function createEmptyRegistry(chainId: number, network: string, deployer: string): Registry {
  return {
    network,
    chainId,
    timestamp: Date.now(),
    commit: "",
    deployer,
    loanProvider: {},
    lendingPool: {},
    tokens: {},
    external: {},
  };
}
