const hre = require("hardhat");
const fs = require("fs");
const path = require("path");
// Run this file using command: `npx hardhat run scripts/deploy-bitmor-loan-system.js --network sepolia`
async function main() {
  console.log("\n========================================");
  console.log("  BITMOR LOAN SYSTEM DEPLOYMENT");
  console.log("========================================\n");

  const [deployer] = await ethers.getSigners();
  console.log("Deployer:", deployer.address);
  console.log("Balance:", ethers.utils.formatEther(await deployer.getBalance()), "ETH\n");

  // Load required deployment files
  const deployedContractsPath = path.join(__dirname, "../deployed-contracts.json");
  const usdcPath = path.join(__dirname, "../deployments/sepolia-usdc.json");
  const cbbtcPath = path.join(__dirname, "../deployments/sepolia-cbbtc.json");
  const swapAdapterPath = path.join(__dirname, "../deployments/uniswap-v4-swap-adapter-wrapper-sepolia.json");

  // Validate prerequisites
  if (!fs.existsSync(deployedContractsPath)) {
    throw new Error("Aave V2 not deployed. Run deploy-aave-v2.js first");
  }
  if (!fs.existsSync(usdcPath) || !fs.existsSync(cbbtcPath)) {
    throw new Error("Tokens not deployed. Run deploy-tokens.js first");
  }
  if (!fs.existsSync(swapAdapterPath)) {
    throw new Error("SwapAdapter not deployed. Run deploy-uniswap-v4-swap-adapter-wrapper.js first");
  }

  const aaveV2 = JSON.parse(fs.readFileSync(deployedContractsPath, "utf8"));
  const usdcDeployment = JSON.parse(fs.readFileSync(usdcPath, "utf8"));
  const cbbtcDeployment = JSON.parse(fs.readFileSync(cbbtcPath, "utf8"));
  const swapAdapterDeployment = JSON.parse(fs.readFileSync(swapAdapterPath, "utf8"));

  // Configuration
  const config = {
    aaveV3Pool: "0xcFc53C27C1b813066F22D2fa70C3D0b4CAa70b7B",
    aaveV2Pool: aaveV2.LendingPool.sepolia.address,
    oracle: aaveV2.AaveOracle.sepolia.address,
    collateralAsset: cbbtcDeployment.address,
    debtAsset: usdcDeployment.address,
    swapAdapter: swapAdapterDeployment.contracts.UniswapV4SwapAdapterWrapper.address,
    zQuoter: "0x0000000000000000000000000000000000000000",
    maxLoanAmount: "1000000000000", // 1M USDC
  };

  console.log("Configuration:");
  console.log("  Aave V3 Pool:", config.aaveV3Pool);
  console.log("  Aave V2 Pool:", config.aaveV2Pool);
  console.log("  Oracle:", config.oracle);
  console.log("  Collateral (cbBTC):", config.collateralAsset);
  console.log("  Debt (USDC):", config.debtAsset);
  console.log("  Swap Adapter:", config.swapAdapter);
  console.log("  Max Loan:", ethers.utils.formatUnits(config.maxLoanAmount, 6), "USDC\n");

  // Load existing Bitmor contracts file or create new one
  const bitmorContractsPath = path.join(__dirname, "../bitmor-deployed-contracts.json");
  let bitmorContracts = {};

  if (fs.existsSync(bitmorContractsPath)) {
    bitmorContracts = JSON.parse(fs.readFileSync(bitmorContractsPath, "utf8"));
    console.log("Loading existing bitmor-deployed-contracts.json\n");
  } else {
    console.log("Creating new bitmor-deployed-contracts.json\n");
  }

  // Step 1: Deploy LoanVault Implementation
  console.log("1/3 Deploying LoanVault Implementation...");
  const LoanVaultImpl = await hre.ethers.getContractFactory("LoanVault");
  const loanVaultImpl = await LoanVaultImpl.deploy();
  await loanVaultImpl.deployed();
  console.log("    Deployed LoanVaultImplementation:", loanVaultImpl.address);

  bitmorContracts.LoanVaultImplementation = bitmorContracts.LoanVaultImplementation || {};
  bitmorContracts.LoanVaultImplementation.sepolia = {
    address: loanVaultImpl.address,
    deployer: deployer.address,
  };

  // Step 2: Deploy Loan Contract
  console.log("\n2/3 Deploying Loan Contract...");
  const Loan = await hre.ethers.getContractFactory("Loan");
  const loan = await Loan.deploy(
    config.aaveV3Pool,
    config.aaveV2Pool,
    config.oracle,
    config.collateralAsset,
    config.debtAsset,
    config.swapAdapter,
    config.zQuoter,
    config.maxLoanAmount
  );
  await loan.deployed();
  console.log("    Deployed Loan:", loan.address);

  bitmorContracts.Loan = bitmorContracts.Loan || {};
  bitmorContracts.Loan.sepolia = {
    address: loan.address,
    deployer: deployer.address,
    constructorArgs: {
      aaveV3Pool: config.aaveV3Pool,
      aaveV2Pool: config.aaveV2Pool,
      oracle: config.oracle,
      collateralAsset: config.collateralAsset,
      debtAsset: config.debtAsset,
      swapAdapter: config.swapAdapter,
      zQuoter: config.zQuoter,
      maxLoanAmount: config.maxLoanAmount,
    },
  };

  // Step 3: Deploy LoanVaultFactory
  console.log("\n3/3 Deploying LoanVaultFactory...");
  const Factory = await hre.ethers.getContractFactory("LoanVaultFactory");
  const factory = await Factory.deploy(loanVaultImpl.address, loan.address);
  await factory.deployed();
  console.log("    Deployed LoanVaultFactory:", factory.address);

  bitmorContracts.LoanVaultFactory = bitmorContracts.LoanVaultFactory || {};
  bitmorContracts.LoanVaultFactory.sepolia = {
    address: factory.address,
    deployer: deployer.address,
    implementation: loanVaultImpl.address,
    loanContract: loan.address,
  };

  // Step 4: Initialize Loan Contract
  console.log("\n4/4 Initializing Loan Contract...");

  console.log("    Setting LoanVaultFactory...");
  const setFactoryTx = await loan.setLoanVaultFactory(factory.address, {
    gasLimit: 500000
  });
  await setFactoryTx.wait();
  console.log("    Factory set successfully");

  // Verification
  console.log("\nVerifying Setup...");
  console.log("    LoanVaultFactory initialized correctly");

  // Save all Bitmor contracts to centralized file
  fs.writeFileSync(bitmorContractsPath, JSON.stringify(bitmorContracts, null, 2));

  console.log("\n========================================");
  console.log("  DEPLOYMENT COMPLETE");
  console.log("========================================");
  console.log("\nDeployed Contracts:");
  console.log("  LoanVaultImplementation:", loanVaultImpl.address);
  console.log("  Loan:", loan.address);
  console.log("  LoanVaultFactory:", factory.address);
  console.log("\nAll Bitmor contracts saved to: bitmor-deployed-contracts.json");
  console.log("\nNext Steps:");
  console.log("  1. Verify contracts: npx hardhat run scripts/verify-all-contracts.js --network sepolia");
  console.log("  2. Initialize loan: npx hardhat run scripts/initialize-loan.js --network sepolia\n");
  console.log("  3. Repay loan: npx hardhat run scripts/repay-loan.js --network sepolia\n");
  console.log("  4. Close loan: npx hardhat run scripts/close-loan.js --network sepolia\n");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
