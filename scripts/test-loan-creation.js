const hre = require("hardhat");
const fs = require("fs");
const path = require("path");

async function main() {
  console.log("========================================");
  console.log("  TESTING LOAN CREATION");
  console.log("========================================\n");

  const [deployer] = await ethers.getSigners();
  console.log("Caller address:", deployer.address);
  console.log("Caller balance:", ethers.utils.formatEther(await deployer.getBalance()), "ETH\n");

  // Load deployment files
  const loanPath = path.join(__dirname, "../deployments/loan-sepolia.json");
  const aaveV2Path = path.join(__dirname, "../deployments/sepolia-aave-v2-FINAL.json");

  const loanDeployment = JSON.parse(fs.readFileSync(loanPath, "utf8"));
  const aaveV2 = JSON.parse(fs.readFileSync(aaveV2Path, "utf8"));

  const LOAN_ADDRESS = loanDeployment.contracts.Loan.address;
  const USDC_ADDRESS = aaveV2.reserves.USDC.underlyingAsset;

  // Test parameters
  const DEPOSIT_AMOUNT = ethers.utils.parseUnits("100", 6); // 100 USDC
  const COLLATERAL_AMOUNT = ethers.utils.parseUnits("0.001", 8); // 0.001 cbBTC
  const DURATION = 12; // 12 months
  const INSURANCE_ID = 1;

  console.log("Test Parameters:");
  console.log("  Loan Contract:", LOAN_ADDRESS);
  console.log("  USDC Address:", USDC_ADDRESS);
  console.log("  Deposit Amount:", ethers.utils.formatUnits(DEPOSIT_AMOUNT, 6), "USDC");
  console.log("  Collateral Amount:", ethers.utils.formatUnits(COLLATERAL_AMOUNT, 8), "cbBTC");
  console.log("  Duration:", DURATION, "months");
  console.log("  Insurance ID:", INSURANCE_ID);
  console.log();

  // Get contract instances
  const loan = await hre.ethers.getContractAt("Loan", LOAN_ADDRESS);
  const usdc = await hre.ethers.getContractAt("contracts/dependencies/openzeppelin/contracts/IERC20.sol:IERC20", USDC_ADDRESS);

  // Check USDC balance
  const usdcBalance = await usdc.balanceOf(deployer.address);
  console.log("Your USDC balance:", ethers.utils.formatUnits(usdcBalance, 6), "USDC");

  if (usdcBalance.lt(DEPOSIT_AMOUNT)) {
    console.log("\nInsufficient USDC balance. You need at least", ethers.utils.formatUnits(DEPOSIT_AMOUNT, 6), "USDC");
    return;
  }
  console.log();

  // Approve USDC
  console.log("Approving USDC...");
  const approveTx = await usdc.approve(LOAN_ADDRESS, DEPOSIT_AMOUNT);
  await approveTx.wait();
  console.log("USDC approved");
  console.log();

  // Initialize loan
  console.log("Calling initializeLoan()...");
  try {
    const tx = await loan.initializeLoan(
      DEPOSIT_AMOUNT,
      COLLATERAL_AMOUNT,
      DURATION,
      INSURANCE_ID,
      { gasLimit: 5000000 }
    );
    console.log("Transaction hash:", tx.hash);
    console.log("Waiting for confirmation...");

    const receipt = await tx.wait();
    console.log("Transaction confirmed in block:", receipt.blockNumber);
    console.log();

    // Find LoanCreated event
    const loanCreatedEvent = receipt.events.find(e => e.event === "LoanCreated");
    if (loanCreatedEvent) {
      const { borrower, lsa, loanAmount, collateralAmount } = loanCreatedEvent.args;
      console.log("Loan Created Successfully!");
      console.log("  Borrower:", borrower);
      console.log("  LSA Address:", lsa);
      console.log("  Loan Amount:", ethers.utils.formatUnits(loanAmount, 6), "USDC");
      console.log("  Collateral Amount:", ethers.utils.formatUnits(collateralAmount, 8), "cbBTC");
    }
    console.log();

  } catch (error) {
    console.log("Transaction failed (expected due to dummy Aave V3 Pool)");
    console.log("Error:", error.message);
    console.log();
  }

  console.log("========================================");
  console.log("  TEST COMPLETE");
  console.log("========================================");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
