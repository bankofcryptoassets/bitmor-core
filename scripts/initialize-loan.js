const hre = require("hardhat");
const fs = require("fs");
const path = require("path");

async function main() {
  console.log("========================================");
  console.log("  INITIALIZE LOAN");
  console.log("========================================\n");

  const [user1, user2, user3, user4, user5] = await ethers.getSigners();
  console.log("Caller address:", user5.address);
  console.log("Caller balance:", ethers.utils.formatEther(await user5.getBalance()), "ETH\n");

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

  const DEPOSIT_AMOUNT = ethers.utils.parseUnits("40000", 6);
  const PREMIUM_AMOUNT = ethers.utils.parseUnits("1000", 6);
  const COLLATERAL_AMOUNT = ethers.utils.parseUnits("1", 8);
  const DURATION = 12;
  const INSURANCE_ID = 1;
  const PREMIUM_COLLECTOR = "0x64e4e1d6ea4d7d4be5022510408bec5b24765176";

  console.log("Test Parameters:");
  console.log("  Loan Contract:", LOAN_ADDRESS);
  console.log("  USDC Address:", USDC_ADDRESS);
  console.log("  Deposit Amount:", ethers.utils.formatUnits(DEPOSIT_AMOUNT, 6), "USDC");
  console.log("  Premium Amount:", ethers.utils.formatUnits(PREMIUM_AMOUNT, 6), "USDC");
  console.log("  Collateral Amount:", ethers.utils.formatUnits(COLLATERAL_AMOUNT, 8), "cbBTC");
  console.log("  Duration:", DURATION, "months");
  console.log("  Insurance ID:", INSURANCE_ID);
  console.log("  Premium Collector:", PREMIUM_COLLECTOR);
  console.log();

  const loan = await hre.ethers.getContractAt("Loan", LOAN_ADDRESS, user5);
  const usdc = await hre.ethers.getContractAt("contracts/dependencies/openzeppelin/contracts/IERC20.sol:IERC20", USDC_ADDRESS, user5);

  const usdcBalance = await usdc.balanceOf(user5.address);
  console.log("Your USDC balance:", ethers.utils.formatUnits(usdcBalance, 6), "USDC");

  const totalAmount = DEPOSIT_AMOUNT.add(PREMIUM_AMOUNT);
  if (usdcBalance.lt(totalAmount)) {
    console.log("\nInsufficient USDC balance. You need at least", ethers.utils.formatUnits(totalAmount, 6), "USDC");
    return;
  }
  console.log();

  console.log("Approving USDC...");
  const approveTx = await usdc.approve(LOAN_ADDRESS, totalAmount);
  await approveTx.wait();
  console.log("USDC approved");
  console.log();

  console.log("Calling initializeLoan()...");
  try {
    const tx = await loan.initializeLoan(
      DEPOSIT_AMOUNT,
      PREMIUM_AMOUNT,
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
    console.log("Transaction failed!");
    console.log("Error:", error.message);
    if (error.error && error.error.data) {
      console.log("Error data:", error.error.data);
    }
    console.log();
  }

  console.log("========================================");
  console.log("  LOAN INITIALIZATION COMPLETE");
  console.log("========================================");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
