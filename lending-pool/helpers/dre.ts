import type { HardhatRuntimeEnvironment } from "hardhat/types/hre";
import type { NetworkConnection } from "hardhat/types/network";
import type { HardhatEthersHelpers } from "@nomicfoundation/hardhat-ethers/types";

/**
 * DRE (Domain Runtime Environment)
 * In Hardhat v3, plugins (like hardhat-ethers) extend the NetworkConnection returned by `hre.network.connect()`.
 * We keep Aave/Bitmor's "global DRE" pattern by storing a merged object:
 *   - all HRE fields (tasks, config, artifacts, etc)
 *   - `network` replaced with the connected NetworkConnection (has `networkName`, `provider`, etc)
 *   - `ethers` taken from the connection (ethers v6 helpers)
 */
export type DREType = Omit<HardhatRuntimeEnvironment, "network" | "ethers"> & {
  network: NetworkConnection;
  ethers: HardhatEthersHelpers;

  // Optional Tenderly helpers (only present when Tenderly plugin is enabled)
  tenderlyNetwork?: {
    getHead(): string;
    getFork(): string;
  };
  tenderly?: {
    network(): any;
  };
};

// Lazily initialized (set by the set-DRE task/action)
export let DRE!: DREType;

export function setDRE(dre: DREType) {
  DRE = dre;
}
