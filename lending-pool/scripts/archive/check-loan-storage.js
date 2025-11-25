const hre = require("hardhat");
const fs = require("fs");
const path = require("path");

async function main() {
  console.log("========================================");
  console.log("  CHECK LOAN CONTRACT STORAGE");
  console.log("========================================\n");

  const loanPath = path.join(__dirname, "../deployments/loan-sepolia.json");
  const loanDeployment = JSON.parse(fs.readFileSync(loanPath, "utf8"));
  const LOAN_ADDRESS = loanDeployment.contracts.Loan.address;

  console.log("Loan Address:", LOAN_ADDRESS);
  console.log();

  const loan = await hre.ethers.getContractAt("Loan", LOAN_ADDRESS);

  // Check all the addresses
  console.log("📋 Contract State:");
  const escrow = await loan.escrow();
  const owner = await loan.owner();
  const factory = await loan.loanVaultFactory();
  const swapAdapter = await loan.swapAdapter();

  console.log("  Escrow:", escrow);
  console.log("  Owner:", owner);
  console.log("  Factory:", factory);
  console.log("  Swap Adapter:", swapAdapter);
  console.log();

  // Check if contract code exists
  const code = await hre.ethers.provider.getCode(LOAN_ADDRESS);
  console.log("Contract bytecode length:", code.length);
  console.log();

  // Get the transaction receipt for the setEscrow call
  const txHash = "0xf63ac3a65e198b4a7f8302fc121962d85b6e703967ec7c83159f3f983ea137f9";
  console.log("Checking transaction:", txHash);
  const receipt = await hre.ethers.provider.getTransactionReceipt(txHash);
  
  if (receipt) {
    console.log("  Status:", receipt.status === 1 ? "Success" : "Failed");
    console.log("  Gas Used:", receipt.gasUsed.toString());
    console.log("  Logs count:", receipt.logs.length);
    
    if (receipt.logs.length > 0) {
      console.log("\n  Event Logs:");
      for (let i = 0; i < receipt.logs.length; i++) {
        console.log(`    Log ${i}:`, receipt.logs[i].topics[0]);
      }
    }
  }
  console.log();

  // Try to read the escrow address again
  console.log("Reading escrow address again...");
  const escrowNow = await loan.escrow();
  console.log("  Escrow:", escrowNow);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

