const hre = require("hardhat");

async function main() {
  const AAVE_V2_POOL = "0x64688EAa8cBC3029D303b61D7e77f986E34742b3";
  const USDC = "0x562937072309F8c929206a58e72732dFCA5b67D6";

  console.log("========================================");
  console.log("  CHECKING USDC RESERVE CONFIGURATION");
  console.log("========================================\n");

  const pool = await hre.ethers.getContractAt("ILendingPool", AAVE_V2_POOL);
  const reserveData = await pool.getReserveData(USDC);

  console.log("USDC Reserve Data:");
  console.log("  aTokenAddress:", reserveData.aTokenAddress);
  console.log("  stableDebtTokenAddress:", reserveData.stableDebtTokenAddress);
  console.log("  variableDebtTokenAddress:", reserveData.variableDebtTokenAddress);
  console.log("  interestRateStrategyAddress:", reserveData.interestRateStrategyAddress);
  console.log();
  console.log("Interest Rates:");
  console.log("  currentLiquidityRate:", reserveData.currentLiquidityRate.toString());
  console.log("  currentVariableBorrowRate:", reserveData.currentVariableBorrowRate.toString());
  console.log("  currentStableBorrowRate:", reserveData.currentStableBorrowRate.toString());
  console.log();

  // Check configuration
  const configData = reserveData.configuration.data;
  console.log("Configuration Data:", configData.toString());

  // Decode configuration bits
  const LTV = configData.and(0xFFFF);
  const liquidationThreshold = configData.shr(16).and(0xFFFF);
  const liquidationBonus = configData.shr(32).and(0xFFFF);
  const decimals = configData.shr(48).and(0xFF);
  const reserveActive = configData.shr(56).and(1).eq(1);
  const reserveFrozen = configData.shr(57).and(1).eq(1);
  const borrowingEnabled = configData.shr(58).and(1).eq(1);
  const stableBorrowRateEnabled = configData.shr(59).and(1).eq(1);
  const reserveFactor = configData.shr(64).and(0xFFFF);

  console.log();
  console.log("Configuration:");
  console.log("  Active:", reserveActive);
  console.log("  Frozen:", reserveFrozen);
  console.log("  Borrowing Enabled:", borrowingEnabled);
  console.log("  Stable Borrow Enabled:", stableBorrowRateEnabled);
  console.log("  LTV:", LTV.toString(), "bps");
  console.log("  Liquidation Threshold:", liquidationThreshold.toString(), "bps");
  console.log("  Liquidation Bonus:", liquidationBonus.toString(), "bps");
  console.log("  Reserve Factor:", reserveFactor.toString(), "bps");
  console.log();

  // Check liquidity
  const usdc = await hre.ethers.getContractAt("@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20", USDC);
  const aToken = await hre.ethers.getContractAt("@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20", reserveData.aTokenAddress);
  const totalLiquidity = await usdc.balanceOf(reserveData.aTokenAddress);
  console.log("Reserve Liquidity:", hre.ethers.utils.formatUnits(totalLiquidity, 6), "USDC");
  console.log();

  if (reserveData.currentVariableBorrowRate.eq(0)) {
    console.log("⚠️  WARNING: Variable borrow rate is 0!");
    console.log("This could be because:");
    console.log("  1. Borrowing is not enabled");
    console.log("  2. Interest rate strategy is not properly configured");
    console.log("  3. No liquidity in the reserve");
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
