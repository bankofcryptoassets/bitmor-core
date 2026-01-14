import { task } from "hardhat/config";

export const bitmorSepolia = task("bitmor:sepolia", "Deploy Bitmor lending pool")
  .addFlag({ name: "verify", description: "Verify contracts at Etherscan" })
  .addFlag({
    name: "skipRegistry",
    description: "Skip addresses provider registration at Addresses Provider Registry",
  })
  .setAction(() => import("../actions/bitmor.action.js"))
  .build();
