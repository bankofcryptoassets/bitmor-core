const hre = require("hardhat");
const fs = require("fs");
const path = require("path");

async function main() {
  console.log("========================================");
  console.log("  UPDATE LOAN CONTRACT - SET NEW ESCROW");
  console.log("========================================\n");

  const [deployer] = await ethers.getSigners();
  console.log("Caller address:", deployer.address);
  console.log("Caller balance:", ethers.utils.formatEther(await deployer.getBalance()), "ETH\n");

  // Load deployment files
  const loanPath = path.join(__dirname, "../deployments/loan-sepolia.json");
  const escrowPath = path.join(__dirname, "../deployments/escrow-sepolia.json");

  if (!fs.existsSync(loanPath)) {
    throw new Error("Loan deployment not found");
  }
  if (!fs.existsSync(escrowPath)) {
    throw new Error("Escrow deployment not found");
  }

  const loanDeployment = JSON.parse(fs.readFileSync(loanPath, "utf8"));
  const escrowDeployment = JSON.parse(fs.readFileSync(escrowPath, "utf8"));

  const LOAN_ADDRESS = loanDeployment.contracts.Loan.address;
  const NEW_ESCROW_ADDRESS = escrowDeployment.contracts.Escrow.address;

  console.log("Configuration:");
  console.log("  Loan Contract:", LOAN_ADDRESS);
  console.log("  New Escrow Address:", NEW_ESCROW_ADDRESS);
  console.log();

  // Get Loan contract instance
  const loan = await hre.ethers.getContractAt("Loan", LOAN_ADDRESS);

  // Check current escrow
  console.log("Checking current escrow...");
  const currentEscrow = await loan.escrow();
  console.log("  Current Escrow:", currentEscrow);
  console.log();

  if (currentEscrow.toLowerCase() === NEW_ESCROW_ADDRESS.toLowerCase()) {
    console.log("✅ Escrow is already set to the correct address!");
    return;
  }

  // Call setEscrow
  console.log("Calling setEscrow() on Loan contract...");
  const tx = await loan.setEscrow(NEW_ESCROW_ADDRESS);
  console.log("  Transaction hash:", tx.hash);
  
  console.log("  Waiting for confirmation...");
  const receipt = await tx.wait();
  console.log("  ✅ Transaction confirmed!");
  console.log("  Gas used:", receipt.gasUsed.toString());
  console.log();

  // Verify the update
  console.log("Verifying update...");
  const updatedEscrow = await loan.escrow();
  console.log("  New Escrow:", updatedEscrow);
  console.log();

  if (updatedEscrow.toLowerCase() === NEW_ESCROW_ADDRESS.toLowerCase()) {
    console.log("========================================");
    console.log("  ✅ ESCROW UPDATED SUCCESSFULLY");
    console.log("========================================");
  } else {
    console.log("========================================");
    console.log("  ❌ ESCROW UPDATE FAILED");
    console.log("========================================");
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

