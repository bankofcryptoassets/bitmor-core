const hre = require("hardhat");
const fs = require("fs");
const path = require("path");

async function main() {
  console.log("========================================");
  console.log("  SET LOAN VAULT FACTORY ON LOAN CONTRACT");
  console.log("========================================\n");

  const [deployer] = await ethers.getSigners();
  console.log("Caller address:", deployer.address);
  console.log("Caller balance:", ethers.utils.formatEther(await deployer.getBalance()), "ETH\n");

  // Load deployment files
  const loanPath = path.join(__dirname, "../deployments/loan-sepolia.json");
  const factoryPath = path.join(__dirname, "../deployments/loan-vault-factory-sepolia.json");

  if (!fs.existsSync(loanPath)) {
    throw new Error("Loan deployment not found");
  }
  if (!fs.existsSync(factoryPath)) {
    throw new Error("LoanVaultFactory deployment not found");
  }

  const loanDeployment = JSON.parse(fs.readFileSync(loanPath, "utf8"));
  const factoryDeployment = JSON.parse(fs.readFileSync(factoryPath, "utf8"));

  const LOAN_ADDRESS = loanDeployment.contracts.Loan.address;
  const FACTORY_ADDRESS = factoryDeployment.contracts.LoanVaultFactory.address;

  console.log("Configuration:");
  console.log("  Loan Contract:", LOAN_ADDRESS);
  console.log("  LoanVaultFactory Address:", FACTORY_ADDRESS);
  console.log();

  // Get Loan contract instance
  const loan = await hre.ethers.getContractAt("Loan", LOAN_ADDRESS);

  // Check current factory
  console.log("Checking current loanVaultFactory...");
  const currentFactory = await loan.loanVaultFactory();
  console.log("  Current Factory:", currentFactory);
  console.log();

  if (currentFactory.toLowerCase() === FACTORY_ADDRESS.toLowerCase()) {
    console.log("✅ LoanVaultFactory is already set to the correct address!");
    return;
  }

  if (currentFactory === "0x0000000000000000000000000000000000000000") {
    console.log("⚠️  LoanVaultFactory is currently NOT SET (zero address)");
    console.log("   This is why loan creation is failing!");
    console.log();
  }

  // Call setLoanVaultFactory
  console.log("Calling setLoanVaultFactory() on Loan contract...");
  const tx = await loan.setLoanVaultFactory(FACTORY_ADDRESS);
  console.log("  Transaction hash:", tx.hash);

  console.log("  Waiting for confirmation...");
  const receipt = await tx.wait();
  console.log("  ✅ Transaction confirmed!");
  console.log("  Gas used:", receipt.gasUsed.toString());
  console.log();

  // Verify the update
  console.log("Verifying update...");
  const updatedFactory = await loan.loanVaultFactory();
  console.log("  New Factory:", updatedFactory);
  console.log();

  if (updatedFactory.toLowerCase() === FACTORY_ADDRESS.toLowerCase()) {
    console.log("========================================");
    console.log("  ✅ LOAN VAULT FACTORY SET SUCCESSFULLY");
    console.log("========================================");
    console.log();
    console.log("💡 Next steps:");
    console.log("   1. Set the Escrow address using: npx hardhat run scripts/update-loan-escrow.js --network sepolia");
    console.log("   2. Test loan creation using: npx hardhat run scripts/test-loan-creation.js --network sepolia");
  } else {
    console.log("========================================");
    console.log("  ❌ UPDATE FAILED");
    console.log("========================================");
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
