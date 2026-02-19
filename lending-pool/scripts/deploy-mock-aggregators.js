const hre = require("hardhat");
const fs = require("fs");
const path = require("path");

async function main() {
  console.log("========================================");
  console.log("  DEPLOY MOCK AGGREGATORS");
  console.log("========================================\n");

  const [deployer] = await ethers.getSigners();
  console.log("Deployer:", deployer.address);
  console.log("Balance:", ethers.utils.formatEther(await deployer.getBalance()), "ETH\n");

  // Initial prices (8 decimals for USD)
  const USDC_PRICE = "100000000";         // $1.00
  const CBBTC_PRICE = "10000000000000";   // $100,000.00

  console.log("Initial Prices:");
  console.log("  USDC:  $1.00");
  console.log("  cbBTC: $100,000.00");
  console.log();

  const MockAggregator = await ethers.getContractFactory("MockAggregator");
  
  console.log("Deploying USDC MockAggregator...");
  const usdcAggregator = await MockAggregator.deploy(USDC_PRICE);
  await usdcAggregator.deployed();
  console.log("  Address:", usdcAggregator.address);

  console.log("\nDeploying cbBTC MockAggregator...");
  const cbBTCAggregator = await MockAggregator.deploy(CBBTC_PRICE);
  await cbBTCAggregator.deployed();
  console.log("  Address:", cbBTCAggregator.address);

  // Save to file
  const outputPath = path.join(__dirname, "../deployments/mock-aggregators-sepolia.json");
  const data = {
    network: "base-sepolia",
    deployer: deployer.address,
    deployedAt: new Date().toISOString(),
    aggregators: {
      USDC: {
        address: usdcAggregator.address,
        initialPrice: USDC_PRICE,
        decimals: 8
      },
      cbBTC: {
        address: cbBTCAggregator.address,
        initialPrice: CBBTC_PRICE,
        decimals: 8
      }
    }
  };

  fs.writeFileSync(outputPath, JSON.stringify(data, null, 2));

  console.log("\n========================================");
  console.log("  DEPLOYMENT COMPLETE");
  console.log("========================================");
  console.log("\nAddresses saved to:", outputPath);
  console.log("\nNEXT STEP:");
  console.log("Update markets/bitmor/commons.ts with these addresses:");
  console.log("\nChainlinkAggregator: {");
  console.log("  [eBaseNetwork.sepolia]: {");
  console.log(`    USDC: '${usdcAggregator.address}',`);
  console.log(`    cbBTC: '${cbBTCAggregator.address}',`);
  console.log("  },");
  console.log("}\n");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

