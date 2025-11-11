const hre = require("hardhat");

async function main() {
  console.log("========================================");
  console.log("  CHECKING AAVE ORACLE CONFIGURATION");
  console.log("========================================\n");

  const AAVE_ORACLE = "0xdDa04c79e6bA7CEb638F0D897E617378E61563a4";
  const USDC = "0x562937072309F8c929206a58e72732dFCA5b67D6";
  const CBBTC = "0x39eF420a0467F8705D15065d4D542bC80ceA0356";

  const oracle = await hre.ethers.getContractAt("AaveOracle", AAVE_ORACLE);

  console.log("Oracle Address:", AAVE_ORACLE);
  console.log();

  try {
    const baseCurrency = await oracle.BASE_CURRENCY();
    console.log("BASE_CURRENCY:", baseCurrency);

    const baseCurrencyUnit = await oracle.BASE_CURRENCY_UNIT();
    console.log("BASE_CURRENCY_UNIT:", baseCurrencyUnit.toString());
    console.log();

    const usdcSource = await oracle.getSourceOfAsset(USDC);
    console.log("USDC asset:", USDC);
    console.log("USDC price source:", usdcSource);
    console.log();

    const cbbtcSource = await oracle.getSourceOfAsset(CBBTC);
    console.log("cbBTC asset:", CBBTC);
    console.log("cbBTC price source:", cbbtcSource);
    console.log();

    const fallback = await oracle.getFallbackOracle();
    console.log("Fallback oracle:", fallback);
    console.log();

    console.log("========================================");
    console.log("  CONSTRUCTOR ARGS FOR VERIFICATION");
    console.log("========================================");
    console.log("\nAssets array:");
    console.log("  [USDC, cbBTC, baseCurrency]");
    console.log(`  ["${USDC}", "${CBBTC}", "${baseCurrency}"]`);
    console.log("\nSources array:");
    console.log(`  ["${usdcSource}", "${cbbtcSource}", "${cbbtcSource}"]`);
    console.log("\nFallback oracle:");
    console.log(`  "${fallback}"`);
    console.log("\nBase currency:");
    console.log(`  "${baseCurrency}"`);
    console.log("\nBase currency unit:");
    console.log(`  "${baseCurrencyUnit.toString()}"`);
    console.log();

  } catch (error) {
    console.log("Error querying oracle:", error.message);
  }

  console.log("========================================");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
