const hre = require("hardhat");
const fs = require("fs");
const path = require("path");

async function verifyContract(address, constructorArgs, contractName) {
  console.log(`\n${"=".repeat(60)}`);
  console.log(`Verifying: ${contractName}`);
  console.log(`Address: ${address}`);
  console.log(`Constructor Args: ${JSON.stringify(constructorArgs)}`);
  console.log(`${"=".repeat(60)}`);

  try {
    await hre.run("verify:verify", {
      address: address,
      constructorArguments: constructorArgs,
    });
    console.log(`✅ ${contractName} verified successfully`);
    return { contract: contractName, status: "success", address };
  } catch (error) {
    if (error.message.includes("Already Verified")) {
      console.log(`✅ ${contractName} already verified`);
      return { contract: contractName, status: "already_verified", address };
    } else {
      console.log(`❌ ${contractName} verification failed:`, error.message);
      return { contract: contractName, status: "failed", address, error: error.message };
    }
  }
}

async function main() {
  console.log("\n");
  console.log("═".repeat(70));
  console.log("  BITMOR PROTOCOL - CONTRACT VERIFICATION");
  console.log("═".repeat(70));
  console.log("\n");

  const results = [];

  // Load deployment files
  const deployedContractsPath = path.join(__dirname, "../deployed-contracts.json");
  const loanPath = path.join(__dirname, "../deployments/loan-sepolia.json");
  const factoryPath = path.join(__dirname, "../deployments/loan-vault-factory-sepolia.json");
  const escrowPath = path.join(__dirname, "../deployments/escrow-sepolia.json");
  const implPath = path.join(__dirname, "../deployments/loan-vault-implementation-sepolia.json");
  const swapAdapterPath = path.join(__dirname, "../deployments/uniswap-v4-swap-adapter-wrapper-sepolia.json");

  console.log("📂 Loading deployment files...\n");

  const deployedContracts = JSON.parse(fs.readFileSync(deployedContractsPath, "utf8"));

  // 1. LoanVault Implementation (no constructor args)
  if (fs.existsSync(implPath)) {
    const implDeployment = JSON.parse(fs.readFileSync(implPath, "utf8"));
    const implAddress = implDeployment.contracts.LoanVaultImplementation.address;
    const result = await verifyContract(implAddress, [], "LoanVaultImplementation");
    results.push(result);
  } else {
    console.log("⚠️  LoanVaultImplementation deployment file not found");
  }

  // 2. Loan Contract
  if (fs.existsSync(loanPath)) {
    const loanDeployment = JSON.parse(fs.readFileSync(loanPath, "utf8"));
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
    const result = await verifyContract(loanAddress, loanArgs, "Loan");
    results.push(result);
  } else {
    console.log("⚠️  Loan deployment file not found");
  }

  // 3. LoanVaultFactory
  if (fs.existsSync(factoryPath)) {
    const factoryDeployment = JSON.parse(fs.readFileSync(factoryPath, "utf8"));
    const factoryAddress = factoryDeployment.contracts.LoanVaultFactory.address;
    const factoryArgs = [
      factoryDeployment.contracts.LoanVaultFactory.implementation,
      factoryDeployment.contracts.LoanVaultFactory.loanContract,
    ];
    const result = await verifyContract(factoryAddress, factoryArgs, "LoanVaultFactory");
    results.push(result);
  } else {
    console.log("⚠️  LoanVaultFactory deployment file not found");
  }

  // 4. Escrow
  if (fs.existsSync(escrowPath)) {
    const escrowDeployment = JSON.parse(fs.readFileSync(escrowPath, "utf8"));
    const escrowAddress = escrowDeployment.contracts.Escrow.address;
    const escrowArgs = [
      escrowDeployment.contracts.Escrow.acbBTC,
      escrowDeployment.contracts.Escrow.loanContract,
    ];
    const result = await verifyContract(escrowAddress, escrowArgs, "Escrow");
    results.push(result);
  } else {
    console.log("⚠️  Escrow deployment file not found");
  }

  // 5. UniswapV4SwapAdapterWrapper
  if (fs.existsSync(swapAdapterPath)) {
    const swapAdapterDeployment = JSON.parse(fs.readFileSync(swapAdapterPath, "utf8"));
    const swapAdapterAddress = swapAdapterDeployment.contracts.UniswapV4SwapAdapterWrapper.address;
    const swapAdapterArgs = [
      swapAdapterDeployment.contracts.UniswapV4SwapAdapterWrapper.uniswapAdapter,
    ];
    const result = await verifyContract(swapAdapterAddress, swapAdapterArgs, "UniswapV4SwapAdapterWrapper");
    results.push(result);
  } else {
    console.log("⚠️  UniswapV4SwapAdapterWrapper deployment file not found");
  }

  console.log("\n\n" + "═".repeat(70));
  console.log("  AAVE V2 CONTRACTS VERIFICATION");
  console.log("═".repeat(70) + "\n");

  // 6. LendingPoolAddressesProvider
  if (deployedContracts.LendingPoolAddressesProvider?.sepolia) {
    const address = deployedContracts.LendingPoolAddressesProvider.sepolia.address;
    const args = ["1"]; // Market ID
    const result = await verifyContract(address, args, "LendingPoolAddressesProvider");
    results.push(result);
  }

  // 7. ReserveLogic Library
  if (deployedContracts.ReserveLogic?.sepolia) {
    const address = deployedContracts.ReserveLogic.sepolia.address;
    const result = await verifyContract(address, [], "ReserveLogic");
    results.push(result);
  }

  // 8. GenericLogic Library
  if (deployedContracts.GenericLogic?.sepolia) {
    const address = deployedContracts.GenericLogic.sepolia.address;
    const result = await verifyContract(address, [], "GenericLogic");
    results.push(result);
  }

  // 9. ValidationLogic Library
  if (deployedContracts.ValidationLogic?.sepolia) {
    const address = deployedContracts.ValidationLogic.sepolia.address;
    const result = await verifyContract(address, [], "ValidationLogic");
    results.push(result);
  }

  // 10. LendingPoolImpl (Implementation - requires library linking info)
  console.log("\n⚠️  LendingPoolImpl requires library linking - verify manually on Basescan");
  console.log(`   Address: ${deployedContracts.LendingPoolImpl?.sepolia?.address}`);

  // 11. LendingPool (Proxy)
  console.log("\n⚠️  LendingPool is a proxy contract - verify the implementation separately");
  console.log(`   Address: ${deployedContracts.LendingPool?.sepolia?.address}`);

  // 12. LendingPoolConfiguratorImpl (Implementation)
  console.log("\n⚠️  LendingPoolConfiguratorImpl requires library linking - verify manually");
  console.log(`   Address: ${deployedContracts.LendingPoolConfiguratorImpl?.sepolia?.address}`);

  // 13. LendingPoolConfigurator (Proxy)
  console.log("\n⚠️  LendingPoolConfigurator is a proxy - verify the implementation");
  console.log(`   Address: ${deployedContracts.LendingPoolConfigurator?.sepolia?.address}`);

  // 14. LendingPoolAddressesProviderRegistry
  if (deployedContracts.LendingPoolAddressesProviderRegistry?.sepolia) {
    const address = deployedContracts.LendingPoolAddressesProviderRegistry.sepolia.address;
    const result = await verifyContract(address, [], "LendingPoolAddressesProviderRegistry");
    results.push(result);
  }

  // 15. StableAndVariableTokensHelper
  if (deployedContracts.StableAndVariableTokensHelper?.sepolia) {
    const address = deployedContracts.StableAndVariableTokensHelper.sepolia.address;
    const poolAddress = deployedContracts.LendingPool.sepolia.address;
    const providerAddress = deployedContracts.LendingPoolAddressesProvider.sepolia.address;
    const args = [poolAddress, providerAddress];
    const result = await verifyContract(address, args, "StableAndVariableTokensHelper");
    results.push(result);
  }

  // 16. ATokensAndRatesHelper
  if (deployedContracts.ATokensAndRatesHelper?.sepolia) {
    const address = deployedContracts.ATokensAndRatesHelper.sepolia.address;
    const poolAddress = deployedContracts.LendingPool.sepolia.address;
    const providerAddress = deployedContracts.LendingPoolAddressesProvider.sepolia.address;
    const configuratorAddress = deployedContracts.LendingPoolConfigurator.sepolia.address;
    const args = [poolAddress, providerAddress, configuratorAddress];
    const result = await verifyContract(address, args, "ATokensAndRatesHelper");
    results.push(result);
  }

  // 17. AToken Implementation
  if (deployedContracts.AToken?.sepolia) {
    const address = deployedContracts.AToken.sepolia.address;
    const result = await verifyContract(address, [], "AToken");
    results.push(result);
  }

  // 18. DelegationAwareAToken Implementation
  if (deployedContracts.DelegationAwareAToken?.sepolia) {
    const address = deployedContracts.DelegationAwareAToken.sepolia.address;
    const result = await verifyContract(address, [], "DelegationAwareAToken");
    results.push(result);
  }

  // 19. StableDebtToken Implementation
  if (deployedContracts.StableDebtToken?.sepolia) {
    const address = deployedContracts.StableDebtToken.sepolia.address;
    const result = await verifyContract(address, [], "StableDebtToken");
    results.push(result);
  }

  // 20. VariableDebtToken Implementation
  if (deployedContracts.VariableDebtToken?.sepolia) {
    const address = deployedContracts.VariableDebtToken.sepolia.address;
    const result = await verifyContract(address, [], "VariableDebtToken");
    results.push(result);
  }

  // 21. WETHMocked
  if (deployedContracts.WETHMocked?.sepolia) {
    const address = deployedContracts.WETHMocked.sepolia.address;
    const result = await verifyContract(address, [], "WETHMocked");
    results.push(result);
  }

  // 22. AaveOracle
  console.log("\n⚠️  AaveOracle requires complex constructor args - verify manually");
  console.log(`   Address: ${deployedContracts.AaveOracle?.sepolia?.address}`);

  // 23. LendingRateOracle
  if (deployedContracts.LendingRateOracle?.sepolia) {
    const address = deployedContracts.LendingRateOracle.sepolia.address;
    const result = await verifyContract(address, [], "LendingRateOracle");
    results.push(result);
  }

  // 24. WETHGateway
  if (deployedContracts.WETHGateway?.sepolia) {
    const address = deployedContracts.WETHGateway.sepolia.address;
    const wethAddress = deployedContracts.WETHMocked.sepolia.address;
    const args = [wethAddress];
    const result = await verifyContract(address, args, "WETHGateway");
    results.push(result);
  }

  // 25. AaveProtocolDataProvider
  if (deployedContracts.AaveProtocolDataProvider?.sepolia) {
    const address = deployedContracts.AaveProtocolDataProvider.sepolia.address;
    const providerAddress = deployedContracts.LendingPoolAddressesProvider.sepolia.address;
    const args = [providerAddress];
    const result = await verifyContract(address, args, "AaveProtocolDataProvider");
    results.push(result);
  }

  // 26. DefaultReserveInterestRateStrategy (USDC)
  if (deployedContracts.rateStrategyUSDC?.sepolia) {
    const address = deployedContracts.rateStrategyUSDC.sepolia.address;
    console.log("\n⚠️  DefaultReserveInterestRateStrategy (USDC) requires rate params - verify manually");
    console.log(`   Address: ${address}`);
  }

  // 27. DefaultReserveInterestRateStrategy (cbBTC)
  if (deployedContracts.rateStrategyCBBTC?.sepolia) {
    const address = deployedContracts.rateStrategyCBBTC.sepolia.address;
    console.log("\n⚠️  DefaultReserveInterestRateStrategy (cbBTC) requires rate params - verify manually");
    console.log(`   Address: ${address}`);
  }

  // 28. LendingPoolCollateralManagerImpl
  console.log("\n⚠️  LendingPoolCollateralManagerImpl requires library linking - verify manually");
  console.log(`   Address: ${deployedContracts.LendingPoolCollateralManagerImpl?.sepolia?.address}`);

  // 29. WalletBalanceProvider
  if (deployedContracts.WalletBalanceProvider?.sepolia) {
    const address = deployedContracts.WalletBalanceProvider.sepolia.address;
    const result = await verifyContract(address, [], "WalletBalanceProvider");
    results.push(result);
  }

  // 30. UiPoolDataProvider
  if (deployedContracts.UiPoolDataProvider?.sepolia) {
    const address = deployedContracts.UiPoolDataProvider.sepolia.address;
    console.log("\n⚠️  UiPoolDataProvider requires complex constructor - verify manually");
    console.log(`   Address: ${address}`);
  }

  // 31. UiIncentiveDataProviderV2V3
  if (deployedContracts.UiIncentiveDataProviderV2V3?.sepolia) {
    const address = deployedContracts.UiIncentiveDataProviderV2V3.sepolia.address;
    const result = await verifyContract(address, [], "UiIncentiveDataProviderV2V3");
    results.push(result);
  }

  // Summary
  console.log("\n\n");
  console.log("═".repeat(70));
  console.log("  VERIFICATION SUMMARY");
  console.log("═".repeat(70));
  console.log("\n");

  const successful = results.filter(r => r.status === "success" || r.status === "already_verified");
  const failed = results.filter(r => r.status === "failed");

  console.log(`✅ Successfully Verified: ${successful.length}/${results.length}`);
  successful.forEach(r => {
    console.log(`   • ${r.contract}: ${r.address}`);
  });

  if (failed.length > 0) {
    console.log(`\n❌ Failed: ${failed.length}/${results.length}`);
    failed.forEach(r => {
      console.log(`   • ${r.contract}: ${r.address}`);
      console.log(`     Error: ${r.error.substring(0, 100)}...`);
    });
  }

  console.log("\n");
  console.log("═".repeat(70));
  console.log("\n");

  // Save results
  const outputPath = path.join(__dirname, "../deployments/verification-results.json");
  fs.writeFileSync(outputPath, JSON.stringify({
    timestamp: new Date().toISOString(),
    network: "Base Sepolia",
    results
  }, null, 2));
  console.log(`📄 Verification results saved to: ${outputPath}\n`);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
