const hre = require("hardhat");
const fs = require("fs");
const path = require("path");

async function main() {
  console.log("========================================");
  console.log("  DEPLOYING LOAN VAULT IMPLEMENTATION");
  console.log("========================================\n");

  const [deployer] = await ethers.getSigners();
  console.log("Deployer address:", deployer.address);
  console.log("Deployer balance:", ethers.utils.formatEther(await deployer.getBalance()), "ETH\n");

  // Deploy LoanVault implementation
  console.log("Deploying LoanVault implementation...");
  const LoanVault = await hre.ethers.getContractFactory("LoanVault");
  const loanVault = await LoanVault.deploy();
  await loanVault.deployed();

  console.log("LoanVault implementation deployed at:", loanVault.address);
  console.log();

  // Save deployment info
  const deploymentInfo = {
    network: "Base Sepolia",
    chainId: 84532,
    deployer: deployer.address,
    timestamp: new Date().toISOString(),
    contracts: {
      LoanVaultImplementation: {
        address: loanVault.address,
        note: "This is the implementation contract for LoanVault clones",
      },
    },
  };

  const outputPath = path.join(__dirname, "../deployments/loan-vault-implementation-sepolia.json");
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
