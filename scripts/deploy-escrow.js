const hre = require("hardhat");
const fs = require("fs");
const path = require("path");

async function main() {
  console.log("========================================");
  console.log("  DEPLOYING ESCROW");
  console.log("========================================\n");

  const [deployer] = await ethers.getSigners();
  console.log("Deployer address:", deployer.address);
  console.log("Deployer balance:", ethers.utils.formatEther(await deployer.getBalance()), "ETH\n");

  // Load deployed contracts to get acbBTC address
  const deployedContractsPath = path.join(__dirname, "../deployed-contracts.json");
  if (!fs.existsSync(deployedContractsPath)) {
    throw new Error("deployed-contracts.json not found");
  }
  const deployedContracts = JSON.parse(fs.readFileSync(deployedContractsPath, "utf8"));

  // Base Sepolia addresses - acbBTC is the AToken for cbBTC
  const AC_CBBTC = deployedContracts.AToken.sepolia.address;

  console.log("Configuration:");
  console.log("  acbBTC (AToken):", AC_CBBTC);
  console.log();

  // Deploy Escrow
  console.log("Deploying Escrow...");
  const Escrow = await hre.ethers.getContractFactory("Escrow");
  const escrow = await Escrow.deploy(AC_CBBTC);
  await escrow.deployed();

  console.log("Escrow deployed at:", escrow.address);
  console.log();

  // Save deployment info
  const deploymentInfo = {
    network: "Base Sepolia",
    chainId: 84532,
    deployer: deployer.address,
    timestamp: new Date().toISOString(),
    contracts: {
      Escrow: {
        address: escrow.address,
        acbBTC: AC_CBBTC,
        note: "Loan contract not set yet - will be set after Loan deployment",
      },
    },
  };

  const outputPath = path.join(__dirname, "../deployments/escrow-sepolia.json");
  fs.writeFileSync(outputPath, JSON.stringify(deploymentInfo, null, 2));

  console.log("Deployment info saved to:", outputPath);
  console.log();

  console.log("========================================");
  console.log("  DEPLOYMENT COMPLETE");
  console.log("========================================");
  console.log("\nAll prerequisite contracts deployed successfully");
  console.log("Ready for Loan contract deployment");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
