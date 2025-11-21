const hre = require("hardhat");
const fs = require("fs");
const path = require("path");

async function main() {
  console.log("========================================");
  console.log("  DEPLOYING LOAN VAULT FACTORY");
  console.log("========================================\n");

  const [deployer] = await ethers.getSigners();
  console.log("Deployer address:", deployer.address);
  console.log("Deployer balance:", ethers.utils.formatEther(await deployer.getBalance()), "ETH\n");

  // Load LoanVault implementation address
  const implPath = path.join(__dirname, "../deployments/loan-vault-implementation-sepolia.json");
  if (!fs.existsSync(implPath)) {
    throw new Error("LoanVault implementation not deployed. Run deploy-loan-vault-implementation.js first");
  }

  const implDeployment = JSON.parse(fs.readFileSync(implPath, "utf8"));
  const LOAN_VAULT_IMPLEMENTATION = implDeployment.contracts.LoanVaultImplementation.address;

  // Load Loan deployment to get Loan contract address
  const loanPath = path.join(__dirname, "../deployments/loan-sepolia.json");
  if (!fs.existsSync(loanPath)) {
    throw new Error("Loan contract not deployed. Run deploy-loan.js first");
  }
  const loanDeployment = JSON.parse(fs.readFileSync(loanPath, "utf8"));
  const LOAN_CONTRACT = loanDeployment.contracts.Loan.address;

  console.log("Configuration:");
  console.log("  LoanVault Implementation:", LOAN_VAULT_IMPLEMENTATION);
  console.log("  Loan Contract:", LOAN_CONTRACT);
  console.log();

  // Deploy LoanVaultFactory with Loan contract address
  console.log("Deploying LoanVaultFactory...");
  const Factory = await hre.ethers.getContractFactory("LoanVaultFactory");
  const factory = await Factory.deploy(LOAN_VAULT_IMPLEMENTATION, LOAN_CONTRACT);
  await factory.deployed();

  console.log("LoanVaultFactory deployed at:", factory.address);
  console.log();

  // Save deployment info
  const deploymentInfo = {
    network: "Base Sepolia",
    chainId: 84532,
    deployer: deployer.address,
    timestamp: new Date().toISOString(),
    contracts: {
      LoanVaultFactory: {
        address: factory.address,
        implementation: LOAN_VAULT_IMPLEMENTATION,
        loanContract: LOAN_CONTRACT,
      },
    },
  };

  const outputPath = path.join(__dirname, "../deployments/loan-vault-factory-sepolia.json");
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
