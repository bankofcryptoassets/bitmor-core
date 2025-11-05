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

  // Load Loan deployment to get Loan contract address
  const loanPath = path.join(__dirname, "../deployments/loan-sepolia.json");
  if (!fs.existsSync(loanPath)) {
    throw new Error("Loan contract not deployed. Run deploy-loan.js first");
  }
  const loanDeployment = JSON.parse(fs.readFileSync(loanPath, "utf8"));
  const LOAN_CONTRACT = loanDeployment.contracts.Loan.address;

  console.log("Configuration:");
  console.log("  acbBTC (AToken):", AC_CBBTC);
  console.log("  Loan Contract:", LOAN_CONTRACT);
  console.log();

  // Deploy Escrow with Loan contract address
  console.log("Deploying Escrow...");
  const Escrow = await hre.ethers.getContractFactory("Escrow");
  const escrow = await Escrow.deploy(AC_CBBTC, LOAN_CONTRACT);
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
        loanContract: LOAN_CONTRACT,
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
