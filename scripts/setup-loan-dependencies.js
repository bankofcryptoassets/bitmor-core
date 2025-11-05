const hre = require("hardhat");
const fs = require("fs");
const path = require("path");

async function main() {
  console.log("========================================");
  console.log("  SETTING UP LOAN DEPENDENCIES");
  console.log("========================================\n");

  const [deployer] = await ethers.getSigners();
  console.log("Deployer address:", deployer.address);
  console.log("Deployer balance:", ethers.utils.formatEther(await deployer.getBalance()), "ETH\n");

  // Load deployment files
  const loanPath = path.join(__dirname, "../deployments/loan-sepolia.json");
  const factoryPath = path.join(__dirname, "../deployments/loan-vault-factory-sepolia.json");
  const escrowPath = path.join(__dirname, "../deployments/escrow-sepolia.json");

  if (!fs.existsSync(loanPath)) {
    throw new Error("Loan not deployed. Run deploy-loan.js first");
  }
  if (!fs.existsSync(factoryPath)) {
    throw new Error("Factory not deployed. Run deploy-loan-vault-factory.js first");
  }
  if (!fs.existsSync(escrowPath)) {
    throw new Error("Escrow not deployed. Run deploy-escrow.js first");
  }

  const loanDeployment = JSON.parse(fs.readFileSync(loanPath, "utf8"));
  const factoryDeployment = JSON.parse(fs.readFileSync(factoryPath, "utf8"));
  const escrowDeployment = JSON.parse(fs.readFileSync(escrowPath, "utf8"));

  const LOAN_ADDRESS = loanDeployment.contracts.Loan.address;
  const FACTORY_ADDRESS = factoryDeployment.contracts.LoanVaultFactory.address;
  const ESCROW_ADDRESS = escrowDeployment.contracts.Escrow.address;

  console.log("Configuration:");
  console.log("  Loan:", LOAN_ADDRESS);
  console.log("  Factory:", FACTORY_ADDRESS);
  console.log("  Escrow:", ESCROW_ADDRESS);
  console.log();

  // Get Loan contract instance
  const loan = await hre.ethers.getContractAt("Loan", LOAN_ADDRESS);

  // Set Factory in Loan
  console.log("Setting LoanVaultFactory in Loan contract...");
  const setFactoryTx = await loan.setLoanVaultFactory(FACTORY_ADDRESS);
  await setFactoryTx.wait();
  console.log("✓ LoanVaultFactory set successfully");
  console.log();

  // Set Escrow in Loan
  console.log("Setting Escrow in Loan contract...");
  const setEscrowTx = await loan.setEscrow(ESCROW_ADDRESS);
  await setEscrowTx.wait();
  console.log("✓ Escrow set successfully");
  console.log();

  // Verify setup
  const currentFactory = await loan.loanVaultFactory();
  const currentEscrow = await loan.escrow();

  console.log("Verification:");
  console.log("  Loan.loanVaultFactory():", currentFactory);
  console.log("  Loan.escrow():", currentEscrow);
  console.log();

  if (currentFactory === FACTORY_ADDRESS && currentEscrow === ESCROW_ADDRESS) {
    console.log("✅ Setup completed successfully!");
    console.log("All contracts are now linked and ready to use");
  } else {
    console.log("⚠️  Warning: Addresses don't match!");
  }

  console.log();
  console.log("========================================");
  console.log("  SETUP COMPLETE");
  console.log("========================================");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
