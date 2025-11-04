const hre = require("hardhat");
const fs = require("fs");
const path = require("path");

async function main() {
  console.log("========================================");
  console.log("  DEPLOYING LOAN CONTRACT");
  console.log("========================================\n");

  const [deployer] = await ethers.getSigners();
  console.log("Deployer address:", deployer.address);
  console.log("Deployer balance:", ethers.utils.formatEther(await deployer.getBalance()), "ETH\n");

  // Load deployment files
  const aaveV2Path = path.join(__dirname, "../deployments/sepolia-aave-v2-FINAL.json");
  const factoryPath = path.join(__dirname, "../deployments/loan-vault-factory-sepolia.json");
  const escrowPath = path.join(__dirname, "../deployments/escrow-sepolia.json");
  const swapAdapterPath = path.join(__dirname, "../deployments/uniswap-v4-swap-adapter-wrapper-sepolia.json");

  if (!fs.existsSync(aaveV2Path)) {
    throw new Error("Aave V2 deployment not found. Run deploy-aave-v2.js first");
  }
  if (!fs.existsSync(factoryPath)) {
    throw new Error("LoanVaultFactory not deployed. Run deploy-loan-vault-factory.js first");
  }
  if (!fs.existsSync(escrowPath)) {
    throw new Error("Escrow not deployed. Run deploy-escrow.js first");
  }
  if (!fs.existsSync(swapAdapterPath)) {
    throw new Error("SwapAdapter not deployed. Run deploy-uniswap-v4-swap-adapter-wrapper.js first");
  }

  const aaveV2 = JSON.parse(fs.readFileSync(aaveV2Path, "utf8"));
  const factoryDeployment = JSON.parse(fs.readFileSync(factoryPath, "utf8"));
  const escrowDeployment = JSON.parse(fs.readFileSync(escrowPath, "utf8"));
  const swapAdapterDeployment = JSON.parse(fs.readFileSync(swapAdapterPath, "utf8"));

  // Configuration
  const AAVE_V3_POOL = "0x0000000000000000000000000000000000000001"; // Dummy address - flash loans will not work
  const AAVE_V2_POOL = aaveV2.contracts.core.LendingPool;
  const AAVE_ADDRESSES_PROVIDER = aaveV2.contracts.core.LendingPoolAddressesProvider;
  const COLLATERAL_ASSET = aaveV2.reserves.cbBTC.underlyingAsset;
  const DEBT_ASSET = aaveV2.reserves.USDC.underlyingAsset;
  const LOAN_VAULT_FACTORY = factoryDeployment.contracts.LoanVaultFactory.address;
  const ESCROW = escrowDeployment.contracts.Escrow.address;
  const SWAP_ADAPTER = swapAdapterDeployment.contracts.UniswapV4SwapAdapterWrapper.address;
  const Z_QUOTER = "0x0000000000000000000000000000000000000000";
  const MAX_LOAN_AMOUNT = "1000000000000"; // 1,000,000 USDC

  console.log("Configuration:");
  console.log("  Aave V3 Pool:", AAVE_V3_POOL, "(dummy)");
  console.log("  Aave V2 Pool:", AAVE_V2_POOL);
  console.log("  Aave Addresses Provider:", AAVE_ADDRESSES_PROVIDER);
  console.log("  Collateral Asset (cbBTC):", COLLATERAL_ASSET);
  console.log("  Debt Asset (USDC):", DEBT_ASSET);
  console.log("  Loan Vault Factory:", LOAN_VAULT_FACTORY);
  console.log("  Escrow:", ESCROW);
  console.log("  Swap Adapter:", SWAP_ADAPTER);
  console.log("  zQuoter:", Z_QUOTER);
  console.log("  Max Loan Amount:", ethers.utils.formatUnits(MAX_LOAN_AMOUNT, 6), "USDC");
  console.log();

  // Deploy Loan contract
  console.log("Deploying Loan contract...");
  const Loan = await hre.ethers.getContractFactory("Loan");
  const loan = await Loan.deploy(
    AAVE_V3_POOL,
    AAVE_V2_POOL,
    AAVE_ADDRESSES_PROVIDER,
    COLLATERAL_ASSET,
    DEBT_ASSET,
    LOAN_VAULT_FACTORY,
    ESCROW,
    SWAP_ADAPTER,
    Z_QUOTER,
    MAX_LOAN_AMOUNT
  );
  await loan.deployed();

  console.log("Loan contract deployed at:", loan.address);
  console.log();

  // Setup - Set Loan contract in Factory
  console.log("Setting Loan contract in LoanVaultFactory...");
  const factory = await hre.ethers.getContractAt("LoanVaultFactory", LOAN_VAULT_FACTORY);
  const factoryTx = await factory.setLoanContract(loan.address);
  await factoryTx.wait();
  console.log("LoanVaultFactory.setLoanContract() completed");
  console.log();

  // Setup - Set Loan contract in Escrow
  console.log("Setting Loan contract in Escrow...");
  const escrow = await hre.ethers.getContractAt("Escrow", ESCROW);
  const escrowTx = await escrow.setLoanContract(loan.address);
  await escrowTx.wait();
  console.log("Escrow.setLoanContract() completed");
  console.log();

  // Save deployment info
  const deploymentInfo = {
    network: "Base Sepolia",
    chainId: 84532,
    deployer: deployer.address,
    timestamp: new Date().toISOString(),
    contracts: {
      Loan: {
        address: loan.address,
        constructorArgs: {
          aaveV3Pool: AAVE_V3_POOL,
          aaveV2Pool: AAVE_V2_POOL,
          aaveAddressesProvider: AAVE_ADDRESSES_PROVIDER,
          collateralAsset: COLLATERAL_ASSET,
          debtAsset: DEBT_ASSET,
          loanVaultFactory: LOAN_VAULT_FACTORY,
          escrow: ESCROW,
          swapAdapter: SWAP_ADAPTER,
          zQuoter: Z_QUOTER,
          maxLoanAmount: MAX_LOAN_AMOUNT,
        },
      },
    },
    setupCompleted: {
      factorySetLoanContract: true,
      escrowSetLoanContract: true,
    },
    notes: "Flash loans will fail until Aave V3 Pool address is updated. Update via Loan.setAaveV3Pool() when available.",
  };

  const outputPath = path.join(__dirname, "../deployments/loan-sepolia.json");
  fs.writeFileSync(outputPath, JSON.stringify(deploymentInfo, null, 2));

  console.log("Deployment info saved to:", outputPath);
  console.log();

  console.log("========================================");
  console.log("  DEPLOYMENT COMPLETE");
  console.log("========================================");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
