const hre = require("hardhat");
const fs = require("fs");
const path = require("path");

async function main() {
  console.log("========================================");
  console.log("  FULL LIQUIDATION TEST");
  console.log("  (Uninsured Loan + Price Crash)");
  console.log("========================================\n");

  const [user1, user2, liquidator] = await ethers.getSigners();
  console.log("Liquidator address:", liquidator.address);
  console.log("Liquidator balance:", ethers.utils.formatEther(await liquidator.getBalance()), "ETH\n");

  // Load deployment files
  const bitmorContractsPath = path.join(__dirname, "../bitmor-deployed-contracts.json");
  const mockAggregatorsPath = path.join(__dirname, "../deployments/mock-aggregators-sepolia.json");
  const deployedContractsPath = path.join(__dirname, "../deployed-contracts.json");
  const usdcPath = path.join(__dirname, "../deployments/sepolia-usdc.json");
  const cbbtcPath = path.join(__dirname, "../deployments/sepolia-cbbtc.json");

  const bitmorContracts = JSON.parse(fs.readFileSync(bitmorContractsPath, "utf8"));
  const mockAggregators = JSON.parse(fs.readFileSync(mockAggregatorsPath, "utf8"));
  const deployedContracts = JSON.parse(fs.readFileSync(deployedContractsPath, "utf8"));
  const usdcDeployment = JSON.parse(fs.readFileSync(usdcPath, "utf8"));
  const cbbtcDeployment = JSON.parse(fs.readFileSync(cbbtcPath, "utf8"));

  const LOAN_ADDRESS = bitmorContracts.Loan.sepolia.address;
  const LENDING_POOL = deployedContracts.LendingPool.sepolia.address;
  const USDC_ADDRESS = usdcDeployment.address;
  const CBBTC_ADDRESS = cbbtcDeployment.address;
  const CBBTC_AGGREGATOR = mockAggregators.aggregators.cbBTC.address;

  console.log("Configuration:");
  console.log("  Loan Contract:", LOAN_ADDRESS);
  console.log("  LendingPool:", LENDING_POOL);
  console.log("  cbBTC Aggregator:", CBBTC_AGGREGATOR);
  console.log();

  const loan = await hre.ethers.getContractAt("Loan", LOAN_ADDRESS);
  const lendingPool = await hre.ethers.getContractAt("contracts/protocol/lendingpool/LendingPool.sol:LendingPool", LENDING_POOL);
  const cbBTCAggregator = await hre.ethers.getContractAt("MockAggregator", CBBTC_AGGREGATOR);
  const usdc = await hre.ethers.getContractAt("contracts/mocks/tokens/MintableERC20.sol:MintableERC20", USDC_ADDRESS);

  // Get user's loan
  const loanCount = await loan.getUserLoanCount(liquidator.address);
  console.log("Your total loans:", loanCount.toString());

  if (loanCount.eq(0)) {
    console.log("You don't have any loans. Create a loan first using initialize-loan.js");
    return;
  }

  const LOAN_INDEX = 2;
  const LSA_ADDRESS = await loan.getUserLoanAtIndex(liquidator.address, LOAN_INDEX);
  console.log("LSA Address (loan #" + LOAN_INDEX + "):", LSA_ADDRESS);
  console.log();

  // Step 1: Check current loan status
  console.log("Step 1: Checking loan status...");
  const loanData = await loan.getLoanByLSA(LSA_ADDRESS);
  console.log("  Borrower:", loanData.borrower);
  console.log("  Collateral Amount:", ethers.utils.formatUnits(loanData.collateralAmount, 8), "cbBTC");
  console.log("  Loan Amount:", ethers.utils.formatUnits(loanData.loanAmount, 6), "USDC");
  console.log("  Insurance ID:", loanData.insuranceID.toString());
  console.log("  Is Insured:", loanData.insuranceID.gt(0) ? "Yes" : "No");
  console.log();

  // Step 2: Check current price
  console.log("Step 2: Checking current cbBTC price...");
  const currentPrice = await cbBTCAggregator.latestAnswer();
  console.log("  Current Price:", ethers.utils.formatUnits(currentPrice, 8), "USD");
  console.log();

  console.log("Step 3: Crashing cbBTC price by 50% (keeping 50% of value)...");
  const newPrice = currentPrice.mul(40).div(100); // Keep 50% of value
  console.log("  New Price:", ethers.utils.formatUnits(newPrice, 8), "USD");
  
  const updateTx = await cbBTCAggregator.updateAnswer(newPrice);
  await updateTx.wait();
  console.log("  Price updated!");
  console.log();

  // Step 4: Check user account data
  console.log("Step 4: Checking user account health...");
  const userData = await lendingPool.getUserAccountData(LSA_ADDRESS);
  console.log("  Total Collateral:", ethers.utils.formatUnits(userData.totalCollateralETH, 8), "USD");
  console.log("  Total Debt:", ethers.utils.formatUnits(userData.totalDebtETH, 8), "USD");
  console.log("  Health Factor:", ethers.utils.formatUnits(userData.healthFactor, 18));
  console.log();

  // Step 5: Verify liquidation conditions
  console.log("Step 5: Verifying liquidation conditions...");
  if (loanData.insuranceID.gt(0)) {
    console.log("  Loan is insured. Full liquidation not possible.");
    return;
  }
  if (userData.healthFactor.gte(ethers.utils.parseUnits("1", 18))) {
    console.log("  Health factor above 1.0. Not liquidatable.");
    return;
  }
  console.log("  Uninsured loan with health factor < 1.0");
  console.log("  Proceeding with full liquidation attempt...");
  console.log();

  // Step 6: Prepare liquidator funds (full debt amount)
  console.log("Step 6: Preparing liquidator funds...");
  const debtAmountUSD = userData.totalDebtETH; // 8 decimals USD
  console.log("  Total debt:", ethers.utils.formatUnits(debtAmountUSD, 8), "USD");
  
  // Convert USD debt to USDC amount (USDC has 6 decimals, debt is 8 decimals USD)
  const debtAmountUSDC = debtAmountUSD.div(100); // Convert from 8 to 6 decimals
  
  const mintTx = await usdc.mint(debtAmountUSDC);
  await mintTx.wait();
  console.log("  Minted:", ethers.utils.formatUnits(debtAmountUSDC, 6), "USDC");
  console.log("  Debt to cover:", ethers.utils.formatUnits(debtAmountUSDC, 6), "USDC");
  
  const approveTx = await usdc.approve(LENDING_POOL, debtAmountUSDC);
  await approveTx.wait();
  console.log("  Approved LendingPool");
  console.log();

  // Step 7: Execute full liquidation (force send)
  console.log("Step 7: Executing full liquidation ...");
  
  let liquidationTx;
  let receipt;
  
  try {
    liquidationTx = await lendingPool.liquidationCall(
      CBBTC_ADDRESS,
      USDC_ADDRESS,
      LSA_ADDRESS,
      debtAmountUSDC,
      false,
      { gasLimit: 5000000 }
    );
    console.log("  Transaction sent! Hash:", liquidationTx.hash);
  } catch (error) {
    if (error.transaction && error.transaction.hash) {
      console.log("  Transaction sent but reverted! Hash:", error.transaction.hash);
      console.log("  Check on Tenderly: https://dashboard.tenderly.co/tx/base-sepolia/" + error.transaction.hash);
      throw error;
    }
    throw error;
  }
  
  console.log("  Check on Tenderly: https://dashboard.tenderly.co/tx/base-sepolia/" + liquidationTx.hash);
  console.log();
  
  console.log("  Waiting for confirmation...");
  try {
    receipt = await liquidationTx.wait();
    console.log("  Transaction confirmed!");
    console.log("  Status:", receipt.status === 1 ? "Success" : "Failed");
    console.log("  Gas used:", receipt.gasUsed.toString());
  } catch (error) {
    console.log("  Transaction failed!");
    if (error.receipt) {
      console.log("  Transaction hash:", error.receipt.transactionHash);
      console.log("  Check on Tenderly: https://dashboard.tenderly.co/tx/base-sepolia/" + error.receipt.transactionHash);
    }
    throw error;
  }
  console.log();

  // Step 8: Verify results
  console.log("Step 8: Verifying results...");
  const newUserData = await lendingPool.getUserAccountData(LSA_ADDRESS);
  const newLoanData = await loan.getLoanByLSA(LSA_ADDRESS);
  
  console.log("  New Total Debt:", ethers.utils.formatUnits(newUserData.totalDebtETH, 8), "USD");
  console.log("  New Health Factor:", ethers.utils.formatUnits(newUserData.healthFactor, 18));
  console.log("  New Collateral Amount:", ethers.utils.formatUnits(newLoanData.collateralAmount, 8), "cbBTC");
  console.log();

  console.log("========================================");
  console.log("  FULL LIQUIDATION COMPLETE");
  console.log("========================================");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

