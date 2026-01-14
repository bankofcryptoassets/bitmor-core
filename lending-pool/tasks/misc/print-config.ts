// tasks/misc/print-config.ts
import { task } from "hardhat/config";
import { ArgumentType } from "hardhat/types/arguments";
import { ConfigNames } from "../../helpers/configuration.js";

// NOTE: In HH3 addOption requires a defaultValue (see types).
// We keep defaults empty-string + validate in the action.
export const printConfigTask = task("print-config", "Prints pool configuration")
  .addOption({
    name: "dataProvider",
    description: "Address of AaveProtocolDataProvider",
    type: ArgumentType.STRING,
    defaultValue: "",
  })
  .addOption({
    name: "pool",
    description: `Pool name to retrieve configuration, supported: ${Object.values(ConfigNames).join(", ")}`,
    type: ArgumentType.STRING,
    defaultValue: "",
  })
  .setAction(() => import("../actions/print-config.action.js"))
  .build();
