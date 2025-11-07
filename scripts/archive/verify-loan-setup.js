const hre = require("hardhat");

async function main() {
  const LOAN_ADDRESS = "0xe5DA7ed24f1ec9b39143A3631D25ECE60aB5Ea9A";

  const loan = await hre.ethers.getContractAt("Loan", LOAN_ADDRESS);

  console.log("Checking Loan contract state:");
  console.log("  loanVaultFactory:", await loan.loanVaultFactory());
  console.log("  escrow:", await loan.escrow());
  console.log("  swapAdapter:", await loan.swapAdapter());
  console.log("  AAVE_V2_POOL:", await loan.AAVE_V2_POOL());
  console.log("  AAVE_V3_POOL:", await loan.AAVE_V3_POOL());
}

main().then(() => process.exit(0)).catch(e => { console.error(e); process.exit(1); });
