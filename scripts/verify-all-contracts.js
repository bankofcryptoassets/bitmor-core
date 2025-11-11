const hre = require("hardhat");
const fs = require("fs");
const path = require("path");

async function verifyContract(address, constructorArgs, contractName, contractPath) {
  console.log(`\n${"=".repeat(60)}`);
  console.log(`Verifying: ${contractName}`);
  console.log(`Address: ${address}`);
  console.log(`Constructor Args: ${JSON.stringify(constructorArgs)}`);
  if (contractPath) {
    console.log(`Contract: ${contractPath}`);
  }
  console.log(`${"=".repeat(60)}`);

  try {
    const verifyParams = {
      address: address,
      constructorArguments: constructorArgs,
    };

    if (contractPath) {
      verifyParams.contract = contractPath;
    }

    await hre.run("verify:verify", verifyParams);
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
  const bitmorContractsPath = path.join(__dirname, "../bitmor-deployed-contracts.json");
  const swapAdapterPath = path.join(__dirname, "../deployments/uniswap-v4-swap-adapter-wrapper-sepolia.json");

  console.log("Loading deployment files...\n");

  const deployedContracts = JSON.parse(fs.readFileSync(deployedContractsPath, "utf8"));

  // Verify Bitmor Loan System contracts
  if (fs.existsSync(bitmorContractsPath)) {
    const bitmorContracts = JSON.parse(fs.readFileSync(bitmorContractsPath, "utf8"));

    // 1. LoanVault Implementation
    if (bitmorContracts.LoanVaultImplementation?.sepolia) {
      const implAddress = bitmorContracts.LoanVaultImplementation.sepolia.address;
      const result1 = await verifyContract(implAddress, [], "LoanVaultImplementation");
      results.push(result1);
    }

    // 2. Loan Contract
    if (bitmorContracts.Loan?.sepolia) {
      const loanAddress = bitmorContracts.Loan.sepolia.address;
      const loanArgs = [
        bitmorContracts.Loan.sepolia.constructorArgs.aaveV3Pool,
        bitmorContracts.Loan.sepolia.constructorArgs.aaveV2Pool,
        bitmorContracts.Loan.sepolia.constructorArgs.aaveAddressesProvider,
        bitmorContracts.Loan.sepolia.constructorArgs.collateralAsset,
        bitmorContracts.Loan.sepolia.constructorArgs.debtAsset,
        bitmorContracts.Loan.sepolia.constructorArgs.swapAdapter,
        bitmorContracts.Loan.sepolia.constructorArgs.zQuoter,
        bitmorContracts.Loan.sepolia.constructorArgs.maxLoanAmount,
      ];
      const result2 = await verifyContract(loanAddress, loanArgs, "Loan", "contracts/bitmor/loan/Loan.sol:Loan");
      results.push(result2);
    }

    // 3. LoanVaultFactory
    if (bitmorContracts.LoanVaultFactory?.sepolia) {
      const factoryAddress = bitmorContracts.LoanVaultFactory.sepolia.address;
      const factoryArgs = [
        bitmorContracts.LoanVaultFactory.sepolia.implementation,
        bitmorContracts.LoanVaultFactory.sepolia.loanContract,
      ];
      const result3 = await verifyContract(factoryAddress, factoryArgs, "LoanVaultFactory");
      results.push(result3);
    }
  } else {
    console.log("WARNING: Bitmor contracts file not found at bitmor-deployed-contracts.json");
  }

  // 4. UniswapV4SwapAdapterWrapper
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

  // 10. LendingPoolImpl (Implementation with library linking)
  if (deployedContracts.LendingPoolImpl?.sepolia) {
    const address = deployedContracts.LendingPoolImpl.sepolia.address;
    const result = await verifyContract(address, [], "LendingPoolImpl");
    results.push(result);
  }

  // 11. LendingPool (Proxy - no constructor args for proxy)
  if (deployedContracts.LendingPool?.sepolia) {
    const address = deployedContracts.LendingPool.sepolia.address;
    console.log("\nNOTE: LendingPool is a proxy - verify as proxy on Basescan");
    console.log(`   Address: ${address}`);
  }

  // 12. LendingPoolConfiguratorImpl (Implementation with library linking)
  if (deployedContracts.LendingPoolConfiguratorImpl?.sepolia) {
    const address = deployedContracts.LendingPoolConfiguratorImpl.sepolia.address;
    const result = await verifyContract(address, [], "LendingPoolConfiguratorImpl");
    results.push(result);
  }

  // 13. LendingPoolConfigurator (Proxy - no constructor args for proxy)
  if (deployedContracts.LendingPoolConfigurator?.sepolia) {
    const address = deployedContracts.LendingPoolConfigurator.sepolia.address;
    console.log("\nNOTE: LendingPoolConfigurator is a proxy - verify as proxy on Basescan");
    console.log(`   Address: ${address}`);
  }

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
  if (deployedContracts.AaveOracle?.sepolia) {
    const address = deployedContracts.AaveOracle.sepolia.address;
    const USDC = "0x562937072309F8c929206a58e72732dFCA5b67D6";
    const CBBTC = "0x39eF420a0467F8705D15065d4D542bC80ceA0356";
    const USD_BASE = "0x10F7Fc1F91Ba351f9C629c5947AD69bD03C05b96";

    // Constructor: assets[], sources[], fallbackOracle, baseCurrency, baseCurrencyUnit
    const args = [
      [USDC, CBBTC, USD_BASE],
      ["0xd30e2101a97dcbAeBCBC04F14C3f624E67A35165", "0x0FB99723Aee6f420beAD13e6bBB79b7E6F034298", "0x0FB99723Aee6f420beAD13e6bBB79b7E6F034298"],
      "0x0000000000000000000000000000000000000000",
      USD_BASE,
      ethers.utils.parseUnits("1", 18).toString()
    ];
    const result = await verifyContract(address, args, "AaveOracle");
    results.push(result);
  }

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
    const providerAddress = deployedContracts.LendingPoolAddressesProvider.sepolia.address;

    // Constructor: provider, optimalUtilizationRate, baseVariableBorrowRate, variableRateSlope1, variableRateSlope2, stableRateSlope1, stableRateSlope2
    const args = [
      providerAddress,
      "900000000000000000000000000", // 90% optimal utilization
      "0",
      "40000000000000000000000000", // 4% slope 1
      "600000000000000000000000000", // 60% slope 2
      "0",
      "0"
    ];
    const result = await verifyContract(address, args, "DefaultReserveInterestRateStrategy (USDC)", "contracts/protocol/lendingpool/DefaultReserveInterestRateStrategy.sol:DefaultReserveInterestRateStrategy");
    results.push(result);
  }

  // 27. DefaultReserveInterestRateStrategy (cbBTC)
  if (deployedContracts.rateStrategyCBBTC?.sepolia) {
    const address = deployedContracts.rateStrategyCBBTC.sepolia.address;
    const providerAddress = deployedContracts.LendingPoolAddressesProvider.sepolia.address;

    // Constructor: provider, optimalUtilizationRate, baseVariableBorrowRate, variableRateSlope1, variableRateSlope2, stableRateSlope1, stableRateSlope2
    const args = [
      providerAddress,
      "650000000000000000000000000", // 65% optimal utilization
      "0",
      "80000000000000000000000000", // 8% slope 1
      "3000000000000000000000000000", // 300% slope 2
      "0",
      "0"
    ];
    const result = await verifyContract(address, args, "DefaultReserveInterestRateStrategy (cbBTC)", "contracts/protocol/lendingpool/DefaultReserveInterestRateStrategy.sol:DefaultReserveInterestRateStrategy");
    results.push(result);
  }

  // 28. LendingPoolCollateralManagerImpl (with library linking)
  if (deployedContracts.LendingPoolCollateralManagerImpl?.sepolia) {
    const address = deployedContracts.LendingPoolCollateralManagerImpl.sepolia.address;
    const result = await verifyContract(address, [], "LendingPoolCollateralManagerImpl");
    results.push(result);
  }

  // 29. WalletBalanceProvider
  if (deployedContracts.WalletBalanceProvider?.sepolia) {
    const address = deployedContracts.WalletBalanceProvider.sepolia.address;
    const result = await verifyContract(address, [], "WalletBalanceProvider");
    results.push(result);
  }

  // 30. UiPoolDataProvider
  if (deployedContracts.UiPoolDataProvider?.sepolia) {
    const address = deployedContracts.UiPoolDataProvider.sepolia.address;
    const oracleAddress = deployedContracts.AaveOracle.sepolia.address;

    // Constructor: incentivesController, oracle
    const args = [
      "0x0000000000000000000000000000000000000000", // No incentives controller
      oracleAddress
    ];
    const result = await verifyContract(address, args, "UiPoolDataProvider");
    results.push(result);
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
