import "hardhat/types/config";
import "hardhat/types/hre";

declare module "hardhat/types/config" {
  export interface HttpNetworkUserConfig {
    tenderly?: boolean;
    tenderlyContractName?: string;
  }

  export interface HttpNetworkConfig {
    tenderly?: boolean;
    tenderlyContractName?: string;
  }
}

/**
 * Runtime typing for Tenderly plugin objects.
 * Keep this minimal & structural — Tenderly plugin versions vary.
 */
declare module "hardhat/types/hre" {
  export interface HardhatRuntimeEnvironment {
    tenderlyNetwork?: {
      getHead(): string;
      getFork(): string;
    };
    tenderly?: {
      network(): any;
    };
  }
}
