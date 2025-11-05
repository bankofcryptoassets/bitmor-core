const hre = require("hardhat");

async function main() {
  const USDC = "0x562937072309F8c929206a58e72732dFCA5b67D6";
  const AAVE_V2_POOL = "0x64688EAa8cBC3029D303b61D7e77f986E34742b3";
  const INTEREST_RATE_STRATEGY = "0xE8bB2bBf3C9350465069c3b945D993F6744B77DD";

  console.log("========================================");
  console.log("  CHECKING INTEREST RATE STRATEGY");
  console.log("========================================\n");

  const pool = await hre.ethers.getContractAt("ILendingPool", AAVE_V2_POOL);
  const strategy = await hre.ethers.getContractAt("DefaultReserveInterestRateStrategy", INTEREST_RATE_STRATEGY);

  // Get strategy parameters
  try {
    // Read public immutable variables and getter functions
    const optimalUtilizationRate = await strategy.OPTIMAL_UTILIZATION_RATE();
    const excessUtilizationRate = await strategy.EXCESS_UTILIZATION_RATE();
    const baseVariableBorrowRate = await strategy.baseVariableBorrowRate();
    const variableRateSlope1 = await strategy.variableRateSlope1();
    const variableRateSlope2 = await strategy.variableRateSlope2();

    console.log("Interest Rate Strategy Parameters:");
    console.log("  Address:", INTEREST_RATE_STRATEGY);
    console.log("  Optimal Utilization Rate:", optimalUtilizationRate.toString(), "ray");
    console.log("  Base Variable Borrow Rate:", baseVariableBorrowRate.toString(), "ray");
    console.log("  Variable Rate Slope 1:", variableRateSlope1.toString(), "ray");
    console.log("  Variable Rate Slope 2:", variableRateSlope2.toString(), "ray");
    console.log();

    // Get reserve data to calculate current rate
    const reserveData = await pool.getReserveData(USDC);
    const aTokenAddress = reserveData.aTokenAddress;

    const usdc = await hre.ethers.getContractAt("contracts/dependencies/openzeppelin/contracts/IERC20.sol:IERC20", USDC);
    const variableDebt = await hre.ethers.getContractAt("contracts/dependencies/openzeppelin/contracts/IERC20.sol:IERC20", reserveData.variableDebtTokenAddress);
    const stableDebt = await hre.ethers.getContractAt("contracts/dependencies/openzeppelin/contracts/IERC20.sol:IERC20", reserveData.stableDebtTokenAddress);

    const availableLiquidity = await usdc.balanceOf(aTokenAddress);
    const totalStableDebt = await stableDebt.totalSupply();
    const totalVariableDebt = await variableDebt.totalSupply();

    console.log("Reserve State:");
    console.log("  Available Liquidity:", hre.ethers.utils.formatUnits(availableLiquidity, 6), "USDC");
    console.log("  Total Stable Debt:", hre.ethers.utils.formatUnits(totalStableDebt, 6), "USDC");
    console.log("  Total Variable Debt:", hre.ethers.utils.formatUnits(totalVariableDebt, 6), "USDC");

    const totalDebt = totalStableDebt.add(totalVariableDebt);
    const totalLiquidity = availableLiquidity.add(totalDebt);

    console.log("  Total Debt:", hre.ethers.utils.formatUnits(totalDebt, 6), "USDC");
    console.log("  Total Liquidity:", hre.ethers.utils.formatUnits(totalLiquidity, 6), "USDC");

    if (totalLiquidity.gt(0)) {
      const utilizationRate = totalDebt.mul(hre.ethers.BigNumber.from("1000000000000000000000000000")).div(totalLiquidity);
      console.log("  Utilization Rate:", utilizationRate.toString(), "ray");
      console.log("  Utilization %:", utilizationRate.mul(100).div("1000000000000000000000000000").toString(), "%");
    } else {
      console.log("  Utilization Rate: 0 (no liquidity)");
    }
    console.log();

    // Calculate what the rate should be
    console.log("Calculating expected variable borrow rate...");
    const calcRate = await strategy.calculateInterestRates(
      USDC,
      availableLiquidity,
      totalStableDebt,
      totalVariableDebt,
      0, // average stable rate
      reserveData.configuration.data.shr(64).and(0xFFFF).mul(100) // reserve factor
    );

    console.log("  Expected Liquidity Rate:", calcRate.liquidityRate.toString());
    console.log("  Expected Variable Borrow Rate:", calcRate.variableBorrowRate.toString());
    console.log("  Expected Stable Borrow Rate:", calcRate.stableBorrowRate.toString());
    console.log();

    if (calcRate.variableBorrowRate.eq(0) && baseVariableBorrowRate.gt(0)) {
      console.log("⚠️  WARNING: Variable borrow rate should not be 0!");
      console.log("The interest rate strategy appears to be misconfigured or there's an issue with the reserve.");
    } else if (calcRate.variableBorrowRate.gt(0) && reserveData.currentVariableBorrowRate.eq(0)) {
      console.log("⚠️  The reserve needs to be updated!");
      console.log("Run: LendingPool.getReserveNormalizedIncome() to trigger rate update");
    }

  } catch (error) {
    console.error("Error checking strategy:", error.message);
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
