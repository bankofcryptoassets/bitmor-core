import { DRE, setDRE } from "../../../helpers/dre.js";
import type { HardhatRuntimeEnvironment } from "hardhat/types/hre";

type EdrSimulatedNetworkConfig = {
  type: "edr-simulated";
  forking?: { url?: string };
};

function isEdrSimulatedNetworkConfig(x: unknown): x is EdrSimulatedNetworkConfig {
  return (
    typeof x === "object" &&
    x !== null &&
    (x as any).type === "edr-simulated"
  );
}

export default async function setDREAction(_args: {}, hre: HardhatRuntimeEnvironment) {
  // DRE already initialized
  if (typeof DRE !== "undefined") {
    return;
  }

  // Create a network connection (Hardhat v3 pattern)
  const conn = await hre.network.connect();

  // Build the merged DRE object:
  // - keep HRE (tasks/config/artifacts/etc)
  // - use NetworkConnection (has `networkName`)
  // - use ethers helpers from the connection (added by hardhat-ethers plugin)
  const dre = {
    ...hre,
    network: conn,
    // hardhat-ethers adds `ethers` to the NetworkConnection, not to hre
    ethers: (conn as any).ethers,
    viem: (conn as any).viem,
  };

  // Optional: Tenderly integration (kept permissive because Tenderly's runtime types vary by plugin version)
  if (conn.networkName.includes("tenderly") || process.env.TENDERLY === "true") {
    console.log("- Setting up Tenderly provider");
    const net = (hre as any).tenderly?.network?.();
    if (net) {
      if (process.env.TENDERLY_FORK_ID && process.env.TENDERLY_HEAD_ID) {
        console.log("- Connecting to a Tenderly Fork");
        await net.setFork(process.env.TENDERLY_FORK_ID);
        await net.setHead(process.env.TENDERLY_HEAD_ID);
      } else {
        console.log("- Creating a new Tenderly Fork");
        await net.initializeFork();
      }

      // Ethers v6 provider already exists on `dre.ethers.provider` — only override if the Tenderly plugin requires it.
      // If you DO need to override, do it on the connection's ethers provider, not on hre.ethers.
      const provider = new (dre.ethers as any).providers.Web3Provider(net);
      (dre.ethers as any).provider = provider;

      console.log("- Initialized Tenderly fork:");
      console.log("  - Fork: ", net.getFork());
      console.log("  - Head: ", net.getHead());
    }
  }

  console.log("- Environment");
  if (process.env.FORK) {
    console.log("  - Fork Mode activated at network: ", process.env.FORK);

    // In HH3, forking config exists only for edr-simulated networks.
    const hardhatCfgUnknown = (hre.config.networks as any)?.hardhat as unknown;
    if (isEdrSimulatedNetworkConfig(hardhatCfgUnknown) && hardhatCfgUnknown.forking?.url) {
      console.log("  - Provider URL:", hardhatCfgUnknown.forking.url.split("/")[2]);
    } else {
      console.warn(
        `[FORK][Warn] No forking URL configured for hardhat network (edr-simulated).`
      );
    }
  }

  console.log("  - Network :", conn.networkName);

  setDRE(dre as any);
  return dre as any;
}
