const hre = require("hardhat");
const fs = require("fs");
const path = require("path");

async function main() {
  console.log("========================================");
  console.log("  ADD LIQUIDITY TO AAVE V2 POOL");
  console.log("========================================\n");

  const [deployer] = await ethers.getSigners();
  console.log("Depositor address:", deployer.address);
  console.log("Depositor balance:", ethers.utils.formatEther(await deployer.getBalance()), "ETH\n");

  // Load deployment files
  const deployedContractsPath = path.join(__dirname, "../deployed-contracts.json");
  const usdcPath = path.join(__dirname, "../deployments/sepolia-usdc.json");

  if (!fs.existsSync(deployedContractsPath)) {
    throw new Error("deployed-contracts.json not found");
  }
  if (!fs.existsSync(usdcPath)) {
    throw new Error("USDC deployment not found");
  }

  const deployedContracts = JSON.parse(fs.readFileSync(deployedContractsPath, "utf8"));
  const usdcDeployment = JSON.parse(fs.readFileSync(usdcPath, "utf8"));

  // Configuration
  const LENDING_POOL = deployedContracts.LendingPool.sepolia.address;
  const USDC_ADDRESS = usdcDeployment.address;
  const DATA_PROVIDER = deployedContracts.AaveProtocolDataProvider.sepolia.address;
  
  // Amount to deposit
  const DEPOSIT_AMOUNT = process.env.DEPOSIT_AMOUNT || "100000000000";
  const amountToDeposit = ethers.utils.parseUnits(DEPOSIT_AMOUNT, 6);

  console.log("Configuration:");
  console.log("  Lending Pool:", LENDING_POOL);
  console.log("  USDC Address:", USDC_ADDRESS);
  console.log("  Data Provider:", DATA_PROVIDER);
  console.log("  Deposit Amount:", DEPOSIT_AMOUNT, "USDC");
  console.log();

  const usdc = await hre.ethers.getContractAt("contracts/mocks/tokens/MintableERC20.sol:MintableERC20", USDC_ADDRESS);
  const lendingPool = await hre.ethers.getContractAt("contracts/interfaces/ILendingPool.sol:ILendingPool", LENDING_POOL);
  const dataProvider = await hre.ethers.getContractAt("AaveProtocolDataProvider", DATA_PROVIDER);

  // Step 1: Check current USDC balance
  console.log("Step 1: Checking USDC balance...");
  const currentBalance = await usdc.balanceOf(deployer.address);
  console.log("  Current USDC balance:", ethers.utils.formatUnits(currentBalance, 6), "USDC");

  // Step 2: Mint USDC if needed
  if (currentBalance.lt(amountToDeposit)) {
    console.log("\nStep 2: Minting USDC tokens...");
    const mintAmount = amountToDeposit.sub(currentBalance);
    const mintTx = await usdc.mint(mintAmount);
    await mintTx.wait();
    console.log("  Minted:", ethers.utils.formatUnits(mintAmount, 6), "USDC");
    
    const newBalance = await usdc.balanceOf(deployer.address);
    console.log("  New USDC balance:", ethers.utils.formatUnits(newBalance, 6), "USDC");
  } else {
    console.log("\nStep 2: Sufficient USDC balance, skipping mint");
  }

  // Step 3: Approve LendingPool to spend USDC
  console.log("\nStep 3: Approving LendingPool to spend USDC...");
  const currentAllowance = await usdc.allowance(deployer.address, LENDING_POOL);
  
  if (currentAllowance.lt(amountToDeposit)) {
    const approveTx = await usdc.approve(LENDING_POOL, amountToDeposit);
    await approveTx.wait();
    console.log("  Approved:", ethers.utils.formatUnits(amountToDeposit, 6), "USDC");
  } else {
    console.log("  Already approved, skipping approval");
  }

  // Step 4: Get aToken address before deposit
  console.log("\nStep 4: Getting aToken information...");
  const reserveTokens = await dataProvider.getReserveTokensAddresses(USDC_ADDRESS);
  const aTokenAddress = reserveTokens.aTokenAddress;
  console.log("  aUSDC Address:", aTokenAddress);

  const aToken = await hre.ethers.getContractAt("contracts/dependencies/openzeppelin/contracts/IERC20.sol:IERC20", aTokenAddress);
  const aTokenBalanceBefore = await aToken.balanceOf(deployer.address);
  console.log("  aUSDC Balance (before):", ethers.utils.formatUnits(aTokenBalanceBefore, 6));

  // Step 5: Deposit USDC into Aave v2 pool
  console.log("\nStep 5: Depositing USDC into Aave v2 pool...");
  const depositTx = await lendingPool.deposit(
    USDC_ADDRESS,
    amountToDeposit,
    deployer.address,
    0 // referralCode
  ,{gasLimit: 5000000});
  const receipt = await depositTx.wait();
  console.log("  Deposit successful!");
  console.log("  Transaction hash:", receipt.transactionHash);
  console.log("  Gas used:", receipt.gasUsed.toString());

  // Step 6: Verify deposit
  console.log("\nStep 6: Verifying deposit...");
  const aTokenBalanceAfter = await aToken.balanceOf(deployer.address);
  console.log("  aUSDC Balance (after):", ethers.utils.formatUnits(aTokenBalanceAfter, 6));
  console.log("  aUSDC Received:", ethers.utils.formatUnits(aTokenBalanceAfter.sub(aTokenBalanceBefore), 6));

  // Get reserve data
  const reserveData = await dataProvider.getReserveData(USDC_ADDRESS);
  console.log("\nReserve Information:");
  console.log("  Available Liquidity:", ethers.utils.formatUnits(reserveData.availableLiquidity, 6), "USDC");
  console.log("  Total Stable Debt:", ethers.utils.formatUnits(reserveData.totalStableDebt, 6), "USDC");
  console.log("  Total Variable Debt:", ethers.utils.formatUnits(reserveData.totalVariableDebt, 6), "USDC");
  console.log("  Liquidity Rate:", ethers.utils.formatUnits(reserveData.liquidityRate, 27), "(RAY format)");
  console.log("  Variable Borrow Rate:", ethers.utils.formatUnits(reserveData.variableBorrowRate, 27), "(RAY format)");

  console.log("\n========================================");
  console.log("  LIQUIDITY ADDED SUCCESSFULLY");
  console.log("========================================");
  console.log("\nSummary:");
  console.log("  Deposited:", ethers.utils.formatUnits(amountToDeposit, 6), "USDC");
  console.log("  Received:", ethers.utils.formatUnits(aTokenBalanceAfter.sub(aTokenBalanceBefore), 6), "aUSDC");
  console.log("  Your aUSDC Balance:", ethers.utils.formatUnits(aTokenBalanceAfter, 6));
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

