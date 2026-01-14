import { verifyEtherscanContract, checkVerification } from "../../helpers/etherscan-verification.js";
import type { HardhatRuntimeEnvironment } from "hardhat/types/hre";

type Args = {
  address: string;
  libraries: string;
  constructorArguments: string[];
};

export default async function verifyScAction(
  { address, constructorArguments = [], libraries }: Args,
  hre: HardhatRuntimeEnvironment
) {
  await hre.tasks.getTask("set-DRE").run({});
  checkVerification();

  const libs = libraries?.trim() ? libraries : undefined;
  return verifyEtherscanContract(address, constructorArguments, libs as any);
}
