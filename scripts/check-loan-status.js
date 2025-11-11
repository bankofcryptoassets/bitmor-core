const hre = require("hardhat");
const fs = require("fs");
const path = require("path");

async function main() {
  console.log("========================================");
  console.log("  CHECK LOAN STATUS");
  console.log("========================================\n");

  const [deployer] = await hre.ethers.getSigners();
  console.log("Checking loans for:", deployer.address);
  console.log();

  // Load deployment files
  const bitmorContractsPath = path.join(__dirname, "../bitmor-deployed-contracts.json");

  if (!fs.existsSync(bitmorContractsPath)) {
    throw new Error("Bitmor contracts not deployed. Run deploy-bitmor-loan-system.js first");
  }

  const bitmorContracts = JSON.parse(fs.readFileSync(bitmorContractsPath, "utf8"));
  const LOAN_ADDRESS = bitmorContracts.Loan.sepolia.address;

  console.log("Loan Contract:", LOAN_ADDRESS);
  console.log();

  // Get contract instance
  const loan = await hre.ethers.getContractAt("Loan", LOAN_ADDRESS);

  // Get user's loan count
  const loanCount = await loan.getUserLoanCount(deployer.address);
  console.log("Total Loans:", loanCount.toString());
  console.log();

  if (loanCount.eq(0)) {
    console.log("You don't have any loans yet. Create a loan first using initialize-loan.js");
    return;
  }

  // Loop through all loans
  for (let i = 0; i < loanCount.toNumber(); i++) {
    console.log("========================================");
    console.log(`  LOAN #${i}`);
    console.log("========================================\n");

    // Get LSA address
    const lsaAddress = await loan.getUserLoanAtIndex(deployer.address, i);
    console.log("LSA Address:", lsaAddress);
    console.log();

    // Get loan data
    const loanData = await loan.getLoanByLSA(lsaAddress);

    // Display all loan data fields
    console.log("LOAN DATA:");
    console.log("─────────────────────────────────────────");
    console.log("borrower:                ", loanData.borrower);
    console.log("depositAmount:           ", ethers.utils.formatUnits(loanData.depositAmount, 6), "USDC");
    console.log("loanAmount:              ", ethers.utils.formatUnits(loanData.loanAmount, 6), "USDC");
    console.log("collateralAmount:        ", ethers.utils.formatUnits(loanData.collateralAmount, 8), "cbBTC");
    console.log("estimatedMonthlyPayment: ", ethers.utils.formatUnits(loanData.estimatedMonthlyPayment, 6), "USDC");
    console.log("duration:                ", loanData.duration.toString(), "months");
    console.log("insuranceID:             ", loanData.insuranceID.toString());
    console.log("createdAt:               ", new Date(loanData.createdAt.toNumber() * 1000).toLocaleString());
    console.log("nextDueTimestamp:        ", new Date(loanData.nextDueTimestamp.toNumber() * 1000).toLocaleString());
    
    const lastPaymentText = loanData.lastDueTimestamp.eq(0) 
      ? "No payments made yet" 
      : new Date(loanData.lastDueTimestamp.toNumber() * 1000).toLocaleString();
    console.log("lastDueTimestamp:        ", lastPaymentText);
    
    const statusText = loanData.status === 0 ? "Active" : loanData.status === 1 ? "Completed" : "Liquidated";
    console.log("status:                  ", statusText, `(${loanData.status})`);
    console.log("─────────────────────────────────────────");
    console.log();

    // Additional calculated info
    const now = Math.floor(Date.now() / 1000);
    const nextDue = loanData.nextDueTimestamp.toNumber();
    
    if (loanData.status === 0) { // Active
      const daysUntilNextPayment = Math.floor((nextDue - now) / 86400);
      
      console.log("TIME INFO:");
      console.log("─────────────────────────────────────────");
      console.log("Days until next payment: ", daysUntilNextPayment, "days");
      
      if (daysUntilNextPayment < 0) {
        console.log("⚠️  Payment is OVERDUE by", Math.abs(daysUntilNextPayment), "days!");
      } else if (daysUntilNextPayment < 7) {
        console.log("⚠️  Payment due soon!");
      }
      console.log("─────────────────────────────────────────");
      console.log();
    }

    // Financial summary
    console.log("FINANCIAL SUMMARY:");
    console.log("─────────────────────────────────────────");
    const totalToPay = loanData.estimatedMonthlyPayment.mul(loanData.duration);
    console.log("Total to pay over life:  ", ethers.utils.formatUnits(totalToPay, 6), "USDC");
    console.log("Total interest (est):    ", ethers.utils.formatUnits(totalToPay.sub(loanData.loanAmount), 6), "USDC");
    console.log("─────────────────────────────────────────");
    console.log();
  }

  console.log("========================================");
  console.log("  STATUS CHECK COMPLETE");
  console.log("========================================");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

