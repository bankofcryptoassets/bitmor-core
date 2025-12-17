const fs = require('fs');
const path = require('path');

// Network configurations
const NETWORKS = {
  84532: 'base-sepolia',
  8453: 'base',
  11155111: 'sepolia',
  1: 'mainnet',
  31337: 'localhost',
  1337: 'localhost'
};

// Contract deployment script mappings
const CONTRACT_SCRIPTS = {
  UniswapV4SwapAdapterWrapper: 'DeploySwapAdapterWrapper.s.sol',
  LoanVault: 'DeployLoanVault.s.sol',
  Loan: 'DeployLoan.s.sol',
  LoanVaultFactory: 'DeployLoanVaultFactory.s.sol',
  MockUSDC: 'DeployMockTokens.s.sol',
  MockCbBTC: 'DeployMockTokens.s.sol'
};

/**
 * Get deployed address from broadcast files (mimics DevOpsTools.get_most_recent_deployment)
 * @param {string} contractName - Name of the contract
 * @param {string} chainId - Chain ID
 * @returns {string|null} Contract address or null if not found
 */
function getDeployedAddress(contractName, chainId) {
  const scriptName = CONTRACT_SCRIPTS[contractName];
  if (!scriptName) {
    console.warn(`No script mapping found for contract: ${contractName}`);
    return null;
  }

  const broadcastPath = path.join(__dirname, `../broadcast/${scriptName}/${chainId}/run-latest.json`);

  try {
    if (!fs.existsSync(broadcastPath)) {
      console.warn(`Broadcast file not found: ${broadcastPath}`);
      return null;
    }

    const broadcastData = JSON.parse(fs.readFileSync(broadcastPath, 'utf8'));

    // Find the contract creation transaction
    const createTx = broadcastData.transactions?.find(tx =>
      tx.transactionType === 'CREATE' && tx.contractName === contractName
    );

    if (createTx && createTx.contractAddress) {
      return createTx.contractAddress;
    }

    console.warn(`Contract ${contractName} not found in broadcast file`);
    return null;
  } catch (error) {
    console.warn(`Error reading broadcast file for ${contractName}:`, error.message);
    return null;
  }
}

/**
 * Get deployed address with optional fallback (for contracts that may not exist)
 * @param {string} contractName - Name of the contract
 * @param {string} chainId - Chain ID
 * @returns {string|null} Contract address or null if not found
 */
function getDeployedAddressOptional(contractName, chainId) {
  const scriptName = CONTRACT_SCRIPTS[contractName];
  if (!scriptName) return null;

  const broadcastPath = path.join(__dirname, `../broadcast/${scriptName}/${chainId}/run-latest.json`);

  if (!fs.existsSync(broadcastPath)) {
    return null;
  }

  return getDeployedAddress(contractName, chainId);
}

/**
 * Fetch all deployed addresses from broadcast files and save to deployments.json
 * This function mimics the behavior of SaveDeployedAddresses.s.sol but in JavaScript.
 *
 * Usage:
 *   node scripts/saveDeployments.js [chainId]
 *
 * Examples:
 *   node scripts/saveDeployments.js 84532    # Base Sepolia
 *   node scripts/saveDeployments.js 8453     # Base Mainnet
 *
 * @param {string} chainId - The chain ID
 */
function fetchAndSaveDeployments(chainId) {
  const deploymentsPath = path.join(__dirname, '../deployments.json');

  console.log('=== Fetching Deployed Addresses ===');

  // Fetch deployed addresses from broadcast files
  const swapAdapterWrapper = getDeployedAddress('UniswapV4SwapAdapterWrapper', chainId);
  const loanVault = getDeployedAddress('LoanVault', chainId);
  const loan = getDeployedAddress('Loan', chainId);
  const loanVaultFactory = getDeployedAddress('LoanVaultFactory', chainId);

  // Optional: Mock tokens (may not always be deployed)
  const mockUSDC = getDeployedAddressOptional('MockUSDC', chainId);
  const mockCbBTC = getDeployedAddressOptional('MockCbBTC', chainId);

  console.log('SwapAdapterWrapper:', swapAdapterWrapper);
  console.log('LoanVault:', loanVault);
  console.log('Loan:', loan);
  console.log('LoanVaultFactory:', loanVaultFactory);
  if (mockUSDC) console.log('MockUSDC:', mockUSDC);
  if (mockCbBTC) console.log('MockCbBTC:', mockCbBTC);

  // Check if we have the required addresses
  if (!swapAdapterWrapper || !loanVault || !loan || !loanVaultFactory) {
    throw new Error('Missing required contract addresses');
  }

  // Build deployment data
  const networkName = NETWORKS[chainId] || 'unknown';
  const deploymentData = {
    network: networkName,
    deployedContracts: {
      swapAdapterWrapper,
      loanVault,
      loan,
      loanVaultFactory
    },
    timestamp: new Date().toISOString()
  };

  // Add mock tokens if they exist
  if (mockUSDC || mockCbBTC) {
    deploymentData.mockTokens = {};
    if (mockUSDC) deploymentData.mockTokens.USDC = mockUSDC;
    if (mockCbBTC) deploymentData.mockTokens.cbBTC = mockCbBTC;
  }

  // Read existing deployments
  let deployments = {};
  try {
    if (fs.existsSync(deploymentsPath)) {
      const content = fs.readFileSync(deploymentsPath, 'utf8');
      deployments = JSON.parse(content);
    }
  } catch (error) {
    console.warn('Could not read existing deployments.json, creating new file');
  }

  // Update deployment for this chain
  deployments[chainId] = deploymentData;

  // Write back to file with proper formatting
  fs.writeFileSync(deploymentsPath, JSON.stringify(deployments, null, 2));

  console.log(`\n✅ Addresses saved to: ${deploymentsPath}`);
  console.log(`📍 Network: ${networkName} (Chain ID: ${chainId})`);
  console.log('📋 Contracts:', Object.keys(deploymentData.deployedContracts).join(', '));

  return deploymentData;
}

/**
 * Save deployment addresses to deployments.json (legacy function for manual use)
 * @param {string} chainId - The chain ID
 * @param {Object} addresses - Object containing deployed contract addresses
 * @param {Object} config - Optional network configuration
 */
function saveDeployments(chainId, addresses, config = {}) {
  const deploymentsPath = path.join(__dirname, '../deployments.json');

  // Read existing deployments or create new structure
  let deployments = {};

  try {
    if (fs.existsSync(deploymentsPath)) {
      const content = fs.readFileSync(deploymentsPath, 'utf8');
      deployments = JSON.parse(content);
    }
  } catch (error) {
    console.warn('Could not read existing deployments.json, creating new file');
  }

  // Create deployment entry for this network
  const networkName = NETWORKS[chainId] || 'unknown';

  deployments[chainId] = {
    network: networkName,
    deployedContracts: addresses,
    timestamp: new Date().toISOString(),
    ...config
  };

  // Write back to file with proper formatting
  fs.writeFileSync(deploymentsPath, JSON.stringify(deployments, null, 2));

  console.log(`✅ Deployment addresses saved to ${deploymentsPath}`);
  console.log(`📍 Network: ${networkName} (Chain ID: ${chainId})`);
  console.log('📋 Contracts:', Object.keys(addresses).join(', '));
}

/**
 * Get deployment addresses for a specific network
 * @param {string} chainId - The chain ID
 * @returns {Object|null} Deployment data or null if not found
 */
function getDeployments(chainId) {
  const deploymentsPath = path.join(__dirname, '../deployments.json');

  try {
    const content = fs.readFileSync(deploymentsPath, 'utf8');
    const deployments = JSON.parse(content);
    return deployments[chainId] || null;
  } catch (error) {
    console.warn('Could not read deployments.json');
    return null;
  }
}

// Example usage
if (require.main === module) {
  const chainId = process.argv[2] || '84532'; // Default to Base Sepolia

  console.log(`Fetching deployed addresses for chain ID: ${chainId}`);

  try {
    fetchAndSaveDeployments(chainId);
    console.log('\n🎉 Successfully updated deployments.json!');
  } catch (error) {
    console.error('❌ Error:', error.message);
    process.exit(1);
  }
}

module.exports = {
  fetchAndSaveDeployments,
  saveDeployments,
  getDeployments,
  getDeployedAddress,
  getDeployedAddressOptional
};
