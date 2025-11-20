const hre = require("hardhat");
const fs = require("fs");
const path = require("path");

async function main() {
  console.log("========================================");
  console.log("  INSURED LOAN UNHEALTHY TEST");
  console.log("  (Insured + HF < 1 = Should Not Liquidate)");
  console.log("========================================\n");

  const [liquidator] = await ethers.getSigners();
  console.log("Liquidator address:", liquidator.address);
  console.log("Liquidator balance:", ethers.utils.formatEther(await liquidator.getBalance()), "ETH");
  console.log();

  const bitmorContractsPath = path.join(__dirname, "../bitmor-deployed-contracts.json");
  const deployedContractsPath = path.join(__dirname, "../deployed-contracts.json");
  const usdcPath = path.join(__dirname, "../deployments/sepolia-usdc.json");
  const cbbtcPath = path.join(__dirname, "../deployments/sepolia-cbbtc.json");
  const mockAggregatorsPath = path.join(__dirname, "../deployments/mock-aggregators-sepolia.json");

  const bitmorContracts = JSON.parse(fs.readFileSync(bitmorContractsPath, "utf8"));
  const deployedContracts = JSON.parse(fs.readFileSync(deployedContractsPath, "utf8"));
  const usdcDeployment = JSON.parse(fs.readFileSync(usdcPath, "utf8"));
  const cbbtcDeployment = JSON.parse(fs.readFileSync(cbbtcPath, "utf8"));
  const mockAggregators = JSON.parse(fs.readFileSync(mockAggregatorsPath, "utf8"));

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

  const loanCount = await loan.getUserLoanCount(liquidator.address);
  console.log("Your total loans:", loanCount.toString());

  // Use the insured loan (latest one - index loanCount-1)
  const LSA_ADDRESS = await loan.getUserLoanAtIndex(liquidator.address, loanCount.sub(1));
  console.log("LSA Address (latest loan):", LSA_ADDRESS);
  console.log();

  // Step 1: Check loan status
  console.log("Step 1: Checking loan status...");
  const loanData = await loan.getLoanByLSA(LSA_ADDRESS);
  console.log("  Borrower:", loanData.borrower);
  console.log("  Collateral Amount:", ethers.utils.formatUnits(loanData.collateralAmount, 8), "cbBTC");
  console.log("  Loan Amount:", ethers.utils.formatUnits(loanData.loanAmount, 6), "USDC");
  console.log("  Insurance ID:", loanData.insuranceID.toString());
  console.log("  Is Insured:", loanData.insuranceID.gt(0) ? "Yes" : "No");

  if (!loanData.insuranceID.gt(0)) {
    console.log("\nERROR: This loan is NOT insured!");
    console.log("Please use an insured loan for this test.");
    return;
  }
  console.log();

  // Step 2: Check current price
  console.log("Step 2: Checking current cbBTC price...");
  const currentPrice = await cbBTCAggregator.latestAnswer();
  console.log("  Current Price:", ethers.utils.formatUnits(currentPrice, 8), "USD");
  console.log();

  // Step 3: Check current health
  console.log("Step 3: Checking current health...");
  const currentUserData = await lendingPool.getUserAccountData(LSA_ADDRESS);
  console.log("  Total Collateral:", ethers.utils.formatUnits(currentUserData.totalCollateralETH, 8), "USD");
  console.log("  Total Debt:", ethers.utils.formatUnits(currentUserData.totalDebtETH, 8), "USD");
  console.log("  Health Factor:", ethers.utils.formatUnits(currentUserData.healthFactor, 18));
  console.log();

  // Step 4: Crash price to make HF < 1
  console.log("Step 4: Crashing cbBTC price to make health factor < 1...");
  const newPrice = currentPrice.mul(80).div(100); // Keep 20% of value
  console.log("  New Price:", ethers.utils.formatUnits(newPrice, 8), "USD");

  const updateTx = await cbBTCAggregator.updateAnswer(newPrice);
  await updateTx.wait();
  console.log("  Price updated!");
  console.log();

  // Step 5: Verify new health factor is < 1
  console.log("Step 5: Checking new health factor...");
  const userData = await lendingPool.getUserAccountData(LSA_ADDRESS);
  console.log("  Total Collateral:", ethers.utils.formatUnits(userData.totalCollateralETH, 8), "USD");
  console.log("  Total Debt:", ethers.utils.formatUnits(userData.totalDebtETH, 8), "USD");
  console.log("  Health Factor:", ethers.utils.formatUnits(userData.healthFactor, 18));

  const isUnhealthy = userData.healthFactor.lt(ethers.utils.parseUnits("1", 18));
  console.log("  Health Factor < 1.0:", isUnhealthy ? "Yes" : "No");

  if (!isUnhealthy) {
    console.log("\nWARNING: Health factor is still >= 1.0");
    console.log("Need to crash price more. Try running again.");
    return;
  }
  console.log();

  // Step 6: Check protection status
  console.log("Step 6: Verifying protection status...");
  const isInsured = loanData.insuranceID.gt(0);
  console.log("  Insured:", isInsured ? "Yes" : "No");
  console.log("  Health Factor < 1.0:", isUnhealthy ? "Yes" : "No");

  if (isInsured && isUnhealthy) {
    console.log("  Status: INSURED but UNHEALTHY");
    console.log("  Expected: Should NOT be liquidatable (insurance protects)");
  }
  console.log();

  // Step 7: Check liquidation type
  console.log("Step 7: Checking liquidation type...");
  try {
    const liquidationType = await lendingPool.checkTypeOfLiquidation(LSA_ADDRESS);
    console.log("  Liquidation Type:", liquidationType.toString());
    console.log("  0 = Not liquidatable, 1 = Full liquidation, 2 = Micro liquidation");

    if (liquidationType.eq(0)) {
      console.log("  Correctly shows NOT liquidatable");
    } else {
      console.log("  WARNING: Shows liquidatable (type " + liquidationType.toString() + ")");
    }
  } catch (error) {
    console.log("  Error:", error.message);
  }
  console.log();

  // Step 8: Attempt liquidation (should fail)
  console.log("Step 8: Attempting liquidation (should fail)...");

  const totalDebtETH = userData.totalDebtETH;
  const debtAmountUSDC = totalDebtETH.div(ethers.BigNumber.from("10").pow(8 - 6));

  console.log("  Debt to cover:", ethers.utils.formatUnits(debtAmountUSDC, 6), "USDC");

  await usdc.mint(debtAmountUSDC);
  console.log("  Minted USDC for liquidation attempt");

  const approveTx = await usdc.approve(LENDING_POOL, debtAmountUSDC);
  await approveTx.wait();
  console.log("  Approved LendingPool");
  console.log();

  console.log("Step 9: Calling liquidationCall...");

  let liquidationTx;
  let success = false;
  let errorMessage = "";

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
    console.log("  Check on Tenderly: https://dashboard.tenderly.co/tx/base-sepolia/" + liquidationTx.hash);
    console.log();

    console.log("  Waiting for confirmation...");
    const receipt = await liquidationTx.wait();
    console.log("  Transaction confirmed!");
    console.log("  Status:", receipt.status === 1 ? "Success" : "Failed");
    console.log("  Gas used:", receipt.gasUsed.toString());
    success = receipt.status === 1;
  } catch (error) {
    console.log("  Transaction reverted!");
    errorMessage = error.reason || error.message;
    console.log("  Error:", errorMessage);
    if (error.receipt) {
      console.log("  Check on Tenderly: https://dashboard.tenderly.co/tx/base-sepolia/" + error.receipt.transactionHash);
    }
    success = false;
  }
  console.log();

  // Step 10: Verify results
  console.log("Step 10: Verifying results...");
  const newUserData = await lendingPool.getUserAccountData(LSA_ADDRESS);
  const newLoanData = await loan.getLoanByLSA(LSA_ADDRESS);

  console.log("  New Total Debt:", ethers.utils.formatUnits(newUserData.totalDebtETH, 8), "USD");
  console.log("  New Health Factor:", ethers.utils.formatUnits(newUserData.healthFactor, 18));
  console.log("  New Collateral Amount:", ethers.utils.formatUnits(newLoanData.collateralAmount, 8), "cbBTC");
  console.log();

  const debtChanged = !newUserData.totalDebtETH.eq(userData.totalDebtETH);
  const collateralChanged = !newLoanData.collateralAmount.eq(loanData.collateralAmount);

  console.log("========================================");
  if (!success || (!debtChanged && !collateralChanged)) {
    console.log("  TEST PASSED: INSURANCE PROTECTION WORKS");
    console.log("  The insured loan was NOT liquidated even");
    console.log("  though health factor < 1.0");
    console.log("  Insurance successfully protected the loan!");
  } else {
    console.log("  TEST FAILED: INSURED LOAN WAS LIQUIDATED");
    console.log("  The insured loan should NOT be liquidated");
    console.log("  even when health factor < 1.0!");
  }
  console.log("========================================");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
