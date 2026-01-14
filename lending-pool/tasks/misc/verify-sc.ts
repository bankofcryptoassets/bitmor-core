import { task } from "hardhat/config";
import { ArgumentType } from "hardhat/types/arguments";

export const verifySc = task("verify-sc", "Verify a deployed smart contract")
  .addOption({
    name: "address",
    description: "Ethereum address of the smart contract",
    type: ArgumentType.STRING_WITHOUT_DEFAULT,
    defaultValue: undefined,
  })
  .addOption({
    name: "libraries",
    description: 'Stringified JSON map like {"Lib":"0x..."} (optional)',
    type: ArgumentType.STRING,
    defaultValue: "",
  })
  .addVariadicArgument({
    name: "constructorArguments",
    description: "Arguments for contract constructor",
    type: ArgumentType.STRING,
    defaultValue: [],
  })
  .setAction(() => import("../actions/verify-sc.action.js"))
  .build();
