const hre = require("hardhat");

async function main() {
  const deployedContracts = require("../deployed-contracts.json");
  const cbBTCDeployment = require("../deployments/sepolia-cbbtc.json");
  
  const AAVE_V2_POOL = deployedContracts.LendingPool.sepolia.address;
  const cbBTC = cbBTCDeployment.address;

  console.log("========================================");
  console.log("  CHECKING cbBTC RESERVE");
  console.log("========================================\n");
  console.log("LendingPool:", AAVE_V2_POOL);
  console.log("cbBTC:", cbBTC);
  console.log();

  const pool = await hre.ethers.getContractAt("ILendingPool", AAVE_V2_POOL);
  const reserveData = await pool.getReserveData(cbBTC);

  console.log("cbBTC Reserve Data:");
  console.log("  aTokenAddress (acbBTC):", reserveData.aTokenAddress);
  console.log("  stableDebtTokenAddress:", reserveData.stableDebtTokenAddress);
  console.log("  variableDebtTokenAddress:", reserveData.variableDebtTokenAddress);
  console.log("  liquidityIndex:", reserveData.liquidityIndex.toString());
  console.log("  variableBorrowIndex:", reserveData.variableBorrowIndex.toString());
  console.log();

  // Check liquidity
  const cbBTCToken = await hre.ethers.getContractAt("@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20", cbBTC);
  const totalLiquidity = await cbBTCToken.balanceOf(reserveData.aTokenAddress);
  
  console.log("🔍 CRITICAL:");
  console.log("  cbBTC Reserve Liquidity:", hre.ethers.utils.formatUnits(totalLiquidity, 8), "cbBTC");
  console.log("  cbBTC Reserve Liquidity (raw):", totalLiquidity.toString());
  console.log();

  if (totalLiquidity.eq(0)) {
    console.log("❌ PROBLEM FOUND!");
    console.log("   The cbBTC reserve has 0 liquidity!");
    console.log("   This is why your deposit is failing.");
    console.log();
    console.log("💡 SOLUTION:");
    console.log("   You need to add cbBTC liquidity to the Aave V2 pool first.");
    console.log("   Use: npx hardhat run scripts/add-cbbtc-liquidity.js --network sepolia");
  } else {
    console.log("✓ cbBTC reserve has liquidity");
  }

  // Check configuration
  const configData = reserveData.configuration.data;
  const reserveActive = configData.shr(56).and(1).eq(1);
  const reserveFrozen = configData.shr(57).and(1).eq(1);
  const borrowingEnabled = configData.shr(58).and(1).eq(1);

  console.log();
  console.log("Configuration:");
  console.log("  Active:", reserveActive);
  console.log("  Frozen:", reserveFrozen);
  console.log("  Borrowing Enabled:", borrowingEnabled);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
