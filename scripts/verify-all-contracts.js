const hre = require("hardhat");
const fs = require("fs");
const path = require("path");

async function verifyContract(address, constructorArgs, contractName) {
  console.log(`\nVerifying ${contractName} at ${address}...`);
  try {
    await hre.run("verify:verify", {
      address: address,
      constructorArguments: constructorArgs,
    });
    console.log(`✅ ${contractName} verified successfully`);
    return true;
  } catch (error) {
    if (error.message.includes("Already Verified")) {
      console.log(`✅ ${contractName} already verified`);
      return true;
    } else {
      console.log(`❌ ${contractName} verification failed:`, error.message);
      return false;
    }
  }
}

async function main() {
  console.log("========================================");
  console.log("  VERIFYING ALL CONTRACTS ON BASESCAN");
  console.log("========================================\n");

  const results = {
    success: [],
    failed: [],
    skipped: []
  };

  // Load deployment files
  const deployedContractsPath = path.join(__dirname, "../deployed-contracts.json");
  const loanPath = path.join(__dirname, "../deployments/loan-sepolia.json");
  const factoryPath = path.join(__dirname, "../deployments/loan-vault-factory-sepolia.json");
  const escrowPath = path.join(__dirname, "../deployments/escrow-sepolia.json");
  const implPath = path.join(__dirname, "../deployments/loan-vault-implementation-sepolia.json");
  const swapAdapterPath = path.join(__dirname, "../deployments/uniswap-v4-swap-adapter-wrapper-sepolia.json");

  const deployedContracts = JSON.parse(fs.readFileSync(deployedContractsPath, "utf8"));
  const loanDeployment = JSON.parse(fs.readFileSync(loanPath, "utf8"));
  const factoryDeployment = JSON.parse(fs.readFileSync(factoryPath, "utf8"));
  const escrowDeployment = JSON.parse(fs.readFileSync(escrowPath, "utf8"));
  const implDeployment = JSON.parse(fs.readFileSync(implPath, "utf8"));
  const swapAdapterDeployment = JSON.parse(fs.readFileSync(swapAdapterPath, "utf8"));

  console.log("=== BITMOR PROTOCOL CONTRACTS ===\n");

  // 1. LoanVault Implementation (no constructor args)
  const implAddress = implDeployment.contracts.LoanVaultImplementation.address;
  if (await verifyContract(implAddress, [], "LoanVaultImplementation")) {
    results.success.push("LoanVaultImplementation");
  } else {
    results.failed.push("LoanVaultImplementation");
  }

  // 2. Loan Contract
  const loanAddress = loanDeployment.contracts.Loan.address;
  const loanArgs = [
    loanDeployment.contracts.Loan.constructorArgs.aaveV3Pool,
    loanDeployment.contracts.Loan.constructorArgs.aaveV2Pool,
    loanDeployment.contracts.Loan.constructorArgs.aaveAddressesProvider,
    loanDeployment.contracts.Loan.constructorArgs.collateralAsset,
    loanDeployment.contracts.Loan.constructorArgs.debtAsset,
    loanDeployment.contracts.Loan.constructorArgs.swapAdapter,
    loanDeployment.contracts.Loan.constructorArgs.zQuoter,
    loanDeployment.contracts.Loan.constructorArgs.maxLoanAmount,
  ];
  if (await verifyContract(loanAddress, loanArgs, "Loan")) {
    results.success.push("Loan");
  } else {
    results.failed.push("Loan");
  }

  // 3. LoanVaultFactory
  const factoryAddress = factoryDeployment.contracts.LoanVaultFactory.address;
  const factoryArgs = [
    factoryDeployment.contracts.LoanVaultFactory.implementation,
    factoryDeployment.contracts.LoanVaultFactory.loanContract,
  ];
  if (await verifyContract(factoryAddress, factoryArgs, "LoanVaultFactory")) {
    results.success.push("LoanVaultFactory");
  } else {
    results.failed.push("LoanVaultFactory");
  }

  // 4. Escrow
  const escrowAddress = escrowDeployment.contracts.Escrow.address;
  const escrowArgs = [
    escrowDeployment.contracts.Escrow.acbBTC,
    escrowDeployment.contracts.Escrow.loanContract,
  ];
  if (await verifyContract(escrowAddress, escrowArgs, "Escrow")) {
    results.success.push("Escrow");
  } else {
    results.failed.push("Escrow");
  }

  // 5. UniswapV4SwapAdapterWrapper
  const swapAdapterAddress = swapAdapterDeployment.contracts.UniswapV4SwapAdapterWrapper.address;
  const swapAdapterArgs = [
    swapAdapterDeployment.contracts.UniswapV4SwapAdapterWrapper.uniswapAdapter,
  ];
  if (await verifyContract(swapAdapterAddress, swapAdapterArgs, "UniswapV4SwapAdapterWrapper")) {
    results.success.push("UniswapV4SwapAdapterWrapper");
  } else {
    results.failed.push("UniswapV4SwapAdapterWrapper");
  }

  console.log("\n=== AAVE V2 CORE CONTRACTS ===\n");

  // 6. LendingPoolAddressesProvider
  const addressesProviderAddress = deployedContracts.LendingPoolAddressesProvider.sepolia.address;
  const addressesProviderArgs = ["1"]; // market ID
  if (await verifyContract(addressesProviderAddress, addressesProviderArgs, "LendingPoolAddressesProvider")) {
    results.success.push("LendingPoolAddressesProvider");
  } else {
    results.failed.push("LendingPoolAddressesProvider");
  }

  // 7. LendingPool (Proxy - no constructor args needed)
  const lendingPoolAddress = deployedContracts.LendingPool.sepolia.address;
  console.log(`\n⚠️  LendingPool at ${lendingPoolAddress} is a proxy contract`);
  console.log("   Verify it manually or verify the implementation contract");
  results.skipped.push("LendingPool (Proxy)");

  // 8. AaveOracle
  const oracleAddress = deployedContracts.AaveOracle.sepolia.address;
  console.log(`\n⚠️  AaveOracle at ${oracleAddress}`);
  console.log("   This requires complex constructor args from deployment");
  results.skipped.push("AaveOracle");

  // 9. AaveProtocolDataProvider
  const dataProviderAddress = deployedContracts.AaveProtocolDataProvider.sepolia.address;
  const dataProviderArgs = [addressesProviderAddress];
  if (await verifyContract(dataProviderAddress, dataProviderArgs, "AaveProtocolDataProvider")) {
    results.success.push("AaveProtocolDataProvider");
  } else {
    results.failed.push("AaveProtocolDataProvider");
  }

  // 10. WETHGateway
  const wethGatewayAddress = deployedContracts.WETHGateway.sepolia.address;
  const wethGatewayArgs = [
    deployedContracts.WETHMocked.sepolia.address, // WETH
  ];
  if (await verifyContract(wethGatewayAddress, wethGatewayArgs, "WETHGateway")) {
    results.success.push("WETHGateway");
  } else {
    results.failed.push("WETHGateway");
  }

  console.log("\n========================================");
  console.log("  VERIFICATION SUMMARY");
  console.log("========================================\n");
  console.log(`✅ Successfully verified: ${results.success.length}`);
  results.success.forEach(name => console.log(`   - ${name}`));
  console.log(`\n❌ Failed verification: ${results.failed.length}`);
  results.failed.forEach(name => console.log(`   - ${name}`));
  console.log(`\n⚠️  Skipped (manual verification needed): ${results.skipped.length}`);
  results.skipped.forEach(name => console.log(`   - ${name}`));
  console.log();
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
