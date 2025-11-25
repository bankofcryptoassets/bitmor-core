const hre = require("hardhat");
const fs = require("fs");
const path = require("path");

async function main() {
    console.log("========================================");
    console.log("  CLOSE LOAN");
    console.log("========================================\n");

    const [user1, user2, user3, user4, deployer] = await ethers.getSigners();
    console.log("Caller address:", deployer.address);
    console.log("Caller balance:", ethers.utils.formatEther(await deployer.getBalance()), "ETH\n");

    const bitmorContractsPath = path.join(__dirname, "../bitmor-deployed-contracts.json");
    const usdcPath = path.join(__dirname, "../deployments/sepolia-usdc.json");
    const cbbtcPath = path.join(__dirname, "../deployments/sepolia-cbbtc.json");

    if (!fs.existsSync(bitmorContractsPath)) {
        throw new Error("Bitmor contracts not deployed. Run deploy-bitmor-loan-system.js first");
    }

    const bitmorContracts = JSON.parse(fs.readFileSync(bitmorContractsPath, "utf8"));
    const usdcDeployment = JSON.parse(fs.readFileSync(usdcPath, "utf8"));
    const cbbtcDeployment = JSON.parse(fs.readFileSync(cbbtcPath, "utf8"));

    const LOAN_ADDRESS = bitmorContracts.Loan.sepolia.address;
    const USDC_ADDRESS = usdcDeployment.address;
    const CBBTC_ADDRESS = cbbtcDeployment.address;

    console.log("Contract Addresses:");
    console.log("  Loan Contract:", LOAN_ADDRESS);
    console.log("  USDC Address:", USDC_ADDRESS);
    console.log("  cbBTC Address:", CBBTC_ADDRESS);
    console.log();

    const loan = await hre.ethers.getContractAt("Loan", LOAN_ADDRESS, deployer);
    const usdc = await hre.ethers.getContractAt("contracts/dependencies/openzeppelin/contracts/IERC20.sol:IERC20", USDC_ADDRESS, deployer);
    const cbbtc = await hre.ethers.getContractAt("contracts/dependencies/openzeppelin/contracts/IERC20.sol:IERC20", CBBTC_ADDRESS, deployer);

    const loanCount = await loan.getUserLoanCount(deployer.address);
    console.log("Your total loans:", loanCount.toString());

    if (loanCount.eq(0)) {
        console.log("You don't have any loans. Create a loan first using initialize-loan.js");
        return;
    }

    const LOAN_INDEX = 0;
    const lsaAddress = await loan.getUserLoanAtIndex(deployer.address, LOAN_INDEX);
    console.log("LSA Address (loan #" + LOAN_INDEX + "):", lsaAddress);
    console.log();

    console.log("Fetching loan details...");
    const loanData = await loan.getLoanByLSA(lsaAddress);

    console.log("Loan Details:");
    console.log("  Borrower:", loanData.borrower);
    console.log("  Deposit Amount:", ethers.utils.formatUnits(loanData.depositAmount, 6), "USDC");
    console.log("  Loan Amount:", ethers.utils.formatUnits(loanData.loanAmount, 6), "USDC");
    console.log("  Collateral Amount:", ethers.utils.formatUnits(loanData.collateralAmount, 8), "cbBTC");
    console.log("  Duration:", loanData.duration.toString(), "months");
    console.log("  Status:", loanData.status === 0 ? "Active" : loanData.status === 1 ? "Completed" : "Liquidated");
    console.log();

    if (loanData.status !== 0) {
        console.log("Loan is not active. Cannot close.");
        return;
    }

    console.log("Close Loan Configuration:");
    console.log("  Expected Collateral Return:", ethers.utils.formatUnits(loanData.collateralAmount, 8), "cbBTC");
    console.log("  Withdraw in collateral asset (cbBTC): true");
    console.log();

    const cbbtcBalanceBefore = await cbbtc.balanceOf(deployer.address);
    console.log("Your cbBTC balance (before):", ethers.utils.formatUnits(cbbtcBalanceBefore, 8), "cbBTC");
    console.log();

    console.log("Calling closeLoan()...");
    console.log("Note: The contract will handle debt repayment via flash loan");
    console.log();
    try {
        const withdrawInCollateralAsset = true; // Set to false if you want USDC instead
        const tx = await loan.closeLoan(lsaAddress, withdrawInCollateralAsset, { gasLimit: 5000000 });
        console.log("Transaction hash:", tx.hash);
        console.log("Waiting for confirmation...");

        const receipt = await tx.wait();
        console.log("Transaction confirmed in block:", receipt.blockNumber);
        console.log();

        const loanClosedEvent = receipt.events?.find(e => e.event === "Loan__ClosedLoan");
        if (loanClosedEvent) {
            const { lsa } = loanClosedEvent.args;
            console.log("Loan Closed Successfully!");
            console.log("  LSA:", lsa);
        } else {
            console.log("Loan closed successfully!");
            console.log("Note: Event details not captured");
        }
        console.log();

        const cbbtcBalanceAfter = await cbbtc.balanceOf(deployer.address);
        const usdcBalanceAfter = await usdc.balanceOf(deployer.address);

        console.log("Final Balances:");
        console.log("  cbBTC balance:", ethers.utils.formatUnits(cbbtcBalanceAfter, 8), "cbBTC");
        console.log("  cbBTC received:", ethers.utils.formatUnits(cbbtcBalanceAfter.sub(cbbtcBalanceBefore), 8), "cbBTC");
        console.log("  USDC balance:", ethers.utils.formatUnits(usdcBalanceAfter, 6), "USDC");
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
    console.log("  LOAN CLOSURE COMPLETE");
    console.log("========================================");
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
