const hre = require("hardhat");
const fs = require("fs");
const path = require("path");

async function main() {
  console.log("========================================");
  console.log("  DEPLOYING UNISWAP V4 SWAP ADAPTER WRAPPER");
  console.log("========================================\n");

  const [deployer] = await ethers.getSigners();
  console.log("Deployer address:", deployer.address);
  console.log("Deployer balance:", ethers.utils.formatEther(await deployer.getBalance()), "ETH\n");

  // Base Sepolia addresses
  const UNISWAP_V4_ADAPTER = "0x9d1b904192209b9ab2ab8d79bd8c46cf4dfa7785";

  console.log("Configuration:");
  console.log("  Uniswap V4 Adapter:", UNISWAP_V4_ADAPTER);
  console.log();

  // Deploy wrapper
  console.log("Deploying UniswapV4SwapAdapterWrapper...");
  const Wrapper = await hre.ethers.getContractFactory("UniswapV4SwapAdapterWrapper");
  const wrapper = await Wrapper.deploy(UNISWAP_V4_ADAPTER);
  await wrapper.deployed();

  console.log("UniswapV4SwapAdapterWrapper deployed at:", wrapper.address);
  console.log();

  // Save deployment info
  const deploymentInfo = {
    network: "Base Sepolia",
    chainId: 84532,
    deployer: deployer.address,
    timestamp: new Date().toISOString(),
    contracts: {
      UniswapV4SwapAdapterWrapper: {
        address: wrapper.address,
        uniswapAdapter: UNISWAP_V4_ADAPTER,
      },
    },
  };

  const outputPath = path.join(__dirname, "../deployments/uniswap-v4-swap-adapter-wrapper-sepolia.json");
  fs.mkdirSync(path.dirname(outputPath), { recursive: true });
  fs.writeFileSync(outputPath, JSON.stringify(deploymentInfo, null, 2));

  console.log("Deployment info saved to:", outputPath);
  console.log();

  console.log("========================================");
  console.log("  DEPLOYMENT COMPLETE");
  console.log("========================================");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
