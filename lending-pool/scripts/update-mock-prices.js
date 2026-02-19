const hre = require("hardhat");
const fs = require("fs");
const path = require("path");

async function main() {
  console.log("========================================");
  console.log("  UPDATE MOCK AGGREGATOR PRICES");
  console.log("========================================\n");

  const [deployer] = await ethers.getSigners();

  const mockAggregatorsPath = path.join(__dirname, "../deployments/mock-aggregators-sepolia.json");

  if (!fs.existsSync(mockAggregatorsPath)) {
    throw new Error("Mock aggregators not deployed. Run deploy-mock-aggregators.js first");
  }

  const mockAggregators = JSON.parse(fs.readFileSync(mockAggregatorsPath, "utf8"));

  const NEW_USDC_PRICE = ethers.utils.parseUnits("1.0", 8);
  const NEW_CBBTC_PRICE = ethers.utils.parseUnits("100000", 8);

  console.log("Deployer:", deployer.address);
  console.log();
  console.log("New Prices:");
  console.log("  USDC:", ethers.utils.formatUnits(NEW_USDC_PRICE, 8), "USD");
  console.log("  cbBTC:", ethers.utils.formatUnits(NEW_CBBTC_PRICE, 8), "USD");
  console.log();

  const usdcAggregator = await hre.ethers.getContractAt(
    "MockAggregator",
    mockAggregators.aggregators.USDC.address
  );

  const cbbtcAggregator = await hre.ethers.getContractAt(
    "MockAggregator",
    mockAggregators.aggregators.cbBTC.address
  );

  console.log("Current Prices:");
  const oldUsdcPrice = await usdcAggregator.latestAnswer();
  console.log("  USDC:", ethers.utils.formatUnits(oldUsdcPrice, 8), "USD");
  const oldCbbtcPrice = await cbbtcAggregator.latestAnswer();
  console.log("  cbBTC:", ethers.utils.formatUnits(oldCbbtcPrice, 8), "USD");
  console.log();

  console.log("Updating USDC price...");
  const tx1 = await usdcAggregator.updateAnswer(NEW_USDC_PRICE);
  await tx1.wait();
  console.log("  USDC price updated");
  
  const currentUsdcPrice = await usdcAggregator.latestAnswer();
  console.log("  New USDC price:", ethers.utils.formatUnits(currentUsdcPrice, 8), "USD");
  console.log();

  console.log("Updating cbBTC price...");
  const tx2 = await cbbtcAggregator.updateAnswer(NEW_CBBTC_PRICE);
  await tx2.wait();
  console.log("  cbBTC price updated");
  
  const currentCbbtcPrice = await cbbtcAggregator.latestAnswer();
  console.log("  New cbBTC price:", ethers.utils.formatUnits(currentCbbtcPrice, 8), "USD");
  console.log();

  console.log("========================================");
  console.log("  PRICES UPDATED SUCCESSFULLY");
  console.log("========================================");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

