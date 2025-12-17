const hre = require("hardhat");
const fs = require("fs");
const path = require("path");

async function main() {
    console.log("========================================");
    console.log("  INSURED LOAN LIQUIDATION PROTECTION TEST");
    console.log("  (Insured + Healthy = Should Not Liquidate)");
    console.log("========================================\n");

    const [user1, user2, liquidator] = await ethers.getSigners();
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
    console.log();

    // Step 2: Check current price
    console.log("Step 2: Checking current cbBTC price...");
    const currentPrice = await cbBTCAggregator.latestAnswer();
    console.log("  Current Price:", ethers.utils.formatUnits(currentPrice, 8), "USD");
    console.log();

    // Step 3: Check account health
    console.log("Step 3: Checking user account health...");
    const userData = await lendingPool.getUserAccountData(LSA_ADDRESS);
    console.log("  Total Collateral:", ethers.utils.formatUnits(userData.totalCollateralETH, 8), "USD");
    console.log("  Total Debt:", ethers.utils.formatUnits(userData.totalDebtETH, 8), "USD");
    console.log("  Health Factor:", ethers.utils.formatUnits(userData.healthFactor, 18));
    console.log();

    // Step 4: Verify protection conditions
    console.log("Step 4: Verifying protection conditions...");
    const isInsured = loanData.insuranceID.gt(0);
    const isHealthy = userData.healthFactor.gte(ethers.utils.parseUnits("1", 18));

    console.log("  Insured:", isInsured ? "Yes" : "No");
    console.log("  Health Factor >= 1.0:", isHealthy ? "Yes" : "No");

    if (isInsured && isHealthy) {
        console.log("  Status: Loan is PROTECTED from liquidation");
    } else {
        console.log("  Status: Loan can be liquidated");
    }
    console.log();

    // Step 5: Attempt liquidation
    console.log("Step 5: Attempting liquidation (should fail or do nothing)...");

    const totalDebtETH = userData.totalDebtETH;
    const debtAmountUSDC = totalDebtETH.div(ethers.BigNumber.from("10").pow(8 - 6));
    // Convert from 8 to 6 decimals

    console.log("  Debt to cover:", ethers.utils.formatUnits(debtAmountUSDC, 6), "USDC");

    await usdc.mint(debtAmountUSDC);
    console.log("  Minted USDC for liquidation attempt");

    const approveTx = await usdc.approve(LENDING_POOL, debtAmountUSDC);
    await approveTx.wait();
    console.log("  Approved LendingPool");
    console.log();

    console.log("Step 6: Calling liquidationCall...");

    let liquidationTx;
    let success = false;

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
        console.log("  Error:", error.reason || error.message);
        if (error.receipt) {
            console.log("  Check on Tenderly: https://dashboard.tenderly.co/tx/base-sepolia/" + error.receipt.transactionHash);
        }
        success = false;
    }
    console.log();

    // Step 7: Verify results
    console.log("Step 7: Verifying results...");
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
        console.log("  TEST PASSED: INSURED LOAN PROTECTED");
        console.log("  The insured loan with healthy collateral");
        console.log("  was NOT liquidated as expected.");
    } else {
        console.log("  TEST FAILED: INSURED LOAN WAS LIQUIDATED");
        console.log("  The insured loan should NOT have been liquidated!");
    }
    console.log("========================================");
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
