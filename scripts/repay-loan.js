const hre = require("hardhat");
const fs = require("fs");
const path = require("path");

async function main() {
  console.log("========================================");
  console.log("  REPAY LOAN");
  console.log("========================================\n");

  const [deployer] = await hre.ethers.getSigners();
  console.log("Caller address:", deployer.address);
  console.log("Caller balance:", ethers.utils.formatEther(await deployer.getBalance()), "ETH\n");

  // Load deployment files
  const bitmorContractsPath = path.join(__dirname, "../bitmor-deployed-contracts.json");
  const usdcPath = path.join(__dirname, "../deployments/sepolia-usdc.json");

  if (!fs.existsSync(bitmorContractsPath)) {
    throw new Error("Bitmor contracts not deployed. Run deploy-bitmor-loan-system.js first");
  }

  const bitmorContracts = JSON.parse(fs.readFileSync(bitmorContractsPath, "utf8"));
  const usdcDeployment = JSON.parse(fs.readFileSync(usdcPath, "utf8"));

  const LOAN_ADDRESS = bitmorContracts.Loan.sepolia.address;
  const USDC_ADDRESS = usdcDeployment.address;

  console.log("Contract Addresses:");
  console.log("  Loan Contract:", LOAN_ADDRESS);
  console.log("  USDC Address:", USDC_ADDRESS);
  console.log();

  // Get contract instances
  const loan = await hre.ethers.getContractAt("Loan", LOAN_ADDRESS);
  const usdc = await hre.ethers.getContractAt("contracts/dependencies/openzeppelin/contracts/IERC20.sol:IERC20", USDC_ADDRESS);

  // Get user's loan count
  const loanCount = await loan.getUserLoanCount(deployer.address);
  console.log("Your total loans:", loanCount.toString());

  if (loanCount.eq(0)) {
    console.log("You don't have any loans. Create a loan first using initialize-loan.js");
    return;
  }

  // Get the first loan's LSA address (you can change index if you have multiple loans)
  const LOAN_INDEX = 0; // Change this if you want to repay a different loan
  const lsaAddress = await loan.getUserLoanAtIndex(deployer.address, LOAN_INDEX);
  console.log("LSA Address (loan #" + LOAN_INDEX + "):", lsaAddress);
  console.log();

  // Get loan data
  console.log("Fetching loan details...");
  const loanData = await loan.getLoanByLSA(lsaAddress);
  
  console.log("Loan Details:");
  console.log("  Borrower:", loanData.borrower);
  console.log("  Deposit Amount:", ethers.utils.formatUnits(loanData.depositAmount, 6), "USDC");
  console.log("  Loan Amount:", ethers.utils.formatUnits(loanData.loanAmount, 6), "USDC");
  console.log("  Collateral Amount:", ethers.utils.formatUnits(loanData.collateralAmount, 8), "cbBTC");
  console.log("  Estimated Monthly Payment:", ethers.utils.formatUnits(loanData.estimatedMonthlyPayment, 6), "USDC");
  console.log("  Duration:", loanData.duration.toString(), "months");
  console.log("  Status:", loanData.status === 0 ? "Active" : loanData.status === 1 ? "Completed" : "Liquidated");
  console.log("  Next Due Timestamp:", new Date(loanData.nextDueTimestamp.toNumber() * 1000).toLocaleString());
  console.log();

  // Check if loan is active
  if (loanData.status !== 0) {
    console.log("Loan is not active. Cannot repay.");
    return;
  }

  // Decide repayment amount (you can change this to repay full loan or custom amount)
  const REPAY_MONTHLY = true; // Set to false to repay full loan amount
  const amountToRepay = REPAY_MONTHLY ? loanData.estimatedMonthlyPayment : loanData.loanAmount;

  console.log("Repayment Configuration:");
  console.log("  Repay Type:", REPAY_MONTHLY ? "Monthly Payment" : "Full Loan Amount");
  console.log("  Amount to Repay:", ethers.utils.formatUnits(amountToRepay, 6), "USDC");
  console.log();

  // Check USDC balance
  const usdcBalance = await usdc.balanceOf(deployer.address);
  console.log("Your USDC balance:", ethers.utils.formatUnits(usdcBalance, 6), "USDC");

  if (usdcBalance.lt(amountToRepay)) {
    console.log("\nInsufficient USDC balance. You need at least", ethers.utils.formatUnits(amountToRepay, 6), "USDC");
    return;
  }
  console.log();

  // Approve USDC
  console.log("Approving USDC...");
  const approveTx = await usdc.approve(LOAN_ADDRESS, amountToRepay);
  await approveTx.wait();
  console.log("USDC approved");
  console.log();

  // Repay loan
  console.log("Calling repay()...");
  try {
    const tx = await loan.repay(lsaAddress, amountToRepay, { gasLimit: 3000000 });
    console.log("Transaction hash:", tx.hash);
    console.log("Waiting for confirmation...");

    const receipt = await tx.wait();
    console.log("Transaction confirmed in block:", receipt.blockNumber);
    console.log();

    // Find LoanRepaid event
    const loanRepaidEvent = receipt.events?.find(e => e.event === "LoanRepaid");
    if (loanRepaidEvent) {
      const { lsa, amountRepaid, nextDueTimestamp } = loanRepaidEvent.args;
      console.log("Loan Repayment Successful!");
      console.log("  LSA:", lsa);
      console.log("  Amount Repaid:", ethers.utils.formatUnits(amountRepaid, 6), "USDC");
      console.log("  Next Due Date:", new Date(nextDueTimestamp.toNumber() * 1000).toLocaleString());
    } else {
      console.log("Repayment successful!");
      console.log("Note: Event details not captured");
    }
    console.log();

    // Get updated loan data
    console.log("Fetching updated loan details...");
    const updatedLoanData = await loan.getLoanByLSA(lsaAddress);
    console.log("Updated Loan Status:", updatedLoanData.status === 0 ? "Active" : updatedLoanData.status === 1 ? "Completed" : "Liquidated");
    if (updatedLoanData.status === 0) {
      console.log("Next Due Timestamp:", new Date(updatedLoanData.nextDueTimestamp.toNumber() * 1000).toLocaleString());
    }
    console.log();

  } catch (error) {
    console.log("Transaction failed!");
    console.log("Error:", error.message);
    if (error.error && error.error.data) {
      console.log("Error data:", error.error.data);
    }
    console.log();
  }

  console.log("========================================");
  console.log("  LOAN REPAYMENT COMPLETE");
  console.log("========================================");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
