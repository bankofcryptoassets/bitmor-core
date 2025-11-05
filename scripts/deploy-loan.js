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
  const aaveV2Path = path.join(__dirname, "../deployed-contracts.json");
  const swapAdapterPath = path.join(__dirname, "../deployments/uniswap-v4-swap-adapter-wrapper-sepolia.json");

  if (!fs.existsSync(aaveV2Path)) {
    throw new Error("Aave V2 deployment not found. Run deploy-aave-v2.js first");
  }
  if (!fs.existsSync(swapAdapterPath)) {
    throw new Error("SwapAdapter not deployed. Run deploy-uniswap-v4-swap-adapter-wrapper.js first");
  }

  const aaveV2 = JSON.parse(fs.readFileSync(aaveV2Path, "utf8"));
  const swapAdapterDeployment = JSON.parse(fs.readFileSync(swapAdapterPath, "utf8"));

  // Load token addresses
  const usdcPath = path.join(__dirname, "../deployments/sepolia-usdc.json");
  const cbbtcPath = path.join(__dirname, "../deployments/sepolia-cbbtc.json");

  if (!fs.existsSync(usdcPath)) {
    throw new Error("USDC deployment not found");
  }
  if (!fs.existsSync(cbbtcPath)) {
    throw new Error("cbBTC deployment not found");
  }

  const usdcDeployment = JSON.parse(fs.readFileSync(usdcPath, "utf8"));
  const cbbtcDeployment = JSON.parse(fs.readFileSync(cbbtcPath, "utf8"));

  // Configuration
  const AAVE_V3_POOL = "0xcFc53C27C1b813066F22D2fa70C3D0b4CAa70b7B"; // Aave V3 Pool Proxy
  const AAVE_V2_POOL = "0x64688EAa8cBC3029D303b61D7e77f986E34742b3"; // From deployed-contracts.json
  const AAVE_ADDRESSES_PROVIDER = "0x0F2a2Ea45C278727cBd73012297Bb2c690f834d9"; // From deployed-contracts.json
  const COLLATERAL_ASSET = cbbtcDeployment.address; // cbBTC: 0x39eF420a0467F8705D15065d4D542bC80ceA0356
  const DEBT_ASSET = usdcDeployment.address; // USDC: 0x562937072309F8c929206a58e72732dFCA5b67D6
  const SWAP_ADAPTER = swapAdapterDeployment.contracts.UniswapV4SwapAdapterWrapper.address;
  const Z_QUOTER = "0x0000000000000000000000000000000000000000"; // Not used on Base Sepolia
  const MAX_LOAN_AMOUNT = "1000000000000"; // 1,000,000 USDC (6 decimals)

  console.log("Configuration:");
  console.log("  Aave V3 Pool:", AAVE_V3_POOL);
  console.log("  Aave V2 Pool:", AAVE_V2_POOL);
  console.log("  Aave Addresses Provider:", AAVE_ADDRESSES_PROVIDER);
  console.log("  Collateral Asset (cbBTC):", COLLATERAL_ASSET);
  console.log("  Debt Asset (USDC):", DEBT_ASSET);
  console.log("  Swap Adapter:", SWAP_ADAPTER);
  console.log("  zQuoter:", Z_QUOTER);
  console.log("  Max Loan Amount:", ethers.utils.formatUnits(MAX_LOAN_AMOUNT, 6), "USDC");
  console.log();

  // Deploy Loan contract (without factory and escrow - they will be set later)
  console.log("Deploying Loan contract...");
  const Loan = await hre.ethers.getContractFactory("Loan");
  const loan = await Loan.deploy(
    AAVE_V3_POOL,
    AAVE_V2_POOL,
    AAVE_ADDRESSES_PROVIDER,
    COLLATERAL_ASSET,
    DEBT_ASSET,
    SWAP_ADAPTER,
    Z_QUOTER,
    MAX_LOAN_AMOUNT
  );
  await loan.deployed();

  console.log("Loan contract deployed at:", loan.address);
  console.log();
  console.log("NOTE: Deploy Factory and Escrow next, then set them in Loan contract");
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
          swapAdapter: SWAP_ADAPTER,
          zQuoter: Z_QUOTER,
          maxLoanAmount: MAX_LOAN_AMOUNT,
        },
      },
    },
    notes: "Loan deployed. Next: deploy Factory and Escrow with this Loan address, then run setup-loan-dependencies.js",
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
