const hre = require('hardhat');
const fs = require('fs');
const path = require('path');

async function deployToken(name, symbol, decimals) {
  const [deployer] = await hre.ethers.getSigners();

  console.log(`\nDeploying ${symbol}...`);
  console.log('Deployer:', deployer.address);

  const MintableERC20 = await hre.ethers.getContractFactory('MintableERC20');
  const token = await MintableERC20.deploy(name, symbol, decimals);

  await token.deployed();

  console.log(`${symbol} deployed to:`, token.address);

  // Save deployment address to individual file
  const deploymentDir = path.join(__dirname, '../deployments');
  if (!fs.existsSync(deploymentDir)) {
    fs.mkdirSync(deploymentDir, { recursive: true });
  }

  const deploymentFile = path.join(deploymentDir, `${hre.network.name}-${symbol.toLowerCase()}.json`);
  const deploymentData = {
    network: hre.network.name,
    address: token.address,
    deployer: deployer.address,
    timestamp: new Date().toISOString(),
    decimals: decimals,
    symbol: symbol,
    name: name
  };

  fs.writeFileSync(deploymentFile, JSON.stringify(deploymentData, null, 2));
  console.log('Deployment info saved to:', deploymentFile);

  // Update deployed-contracts.json
  const deployedContractsPath = path.join(__dirname, '../deployed-contracts.json');
  let deployedContracts = {};

  if (fs.existsSync(deployedContractsPath)) {
    deployedContracts = JSON.parse(fs.readFileSync(deployedContractsPath, 'utf8'));
  }

  if (!deployedContracts[symbol]) {
    deployedContracts[symbol] = {};
  }

  deployedContracts[symbol][hre.network.name] = {
    address: token.address,
    deployer: deployer.address
  };

  fs.writeFileSync(deployedContractsPath, JSON.stringify(deployedContracts, null, 2));
  console.log('Address added to deployed-contracts.json');

  return { address: token.address, contract: token };
}

async function main() {
  const [deployer] = await hre.ethers.getSigners();

  console.log('Deploying Mock Tokens');
  console.log('Network:', hre.network.name);
  console.log('Account:', deployer.address);
  console.log('Balance:', (await deployer.getBalance()).toString());

  // Deploy USDC
  const usdc = await deployToken('Bitmor USDC', 'bUSDC', 6);

  // Deploy cbBTC
  const cbBTC = await deployToken('Bitmor cbBTC', 'bcbBTC', 8);

  console.log('\nDeployment Summary:');
  console.log('bUSDC:', usdc.address);
  console.log('bcbBTC:', cbBTC.address);

  return {
    usdc: usdc.address,
    cbBTC: cbBTC.address
  };
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

/**
 * !TODO: If new mock tokens are deployed, they need to be set in the deployed oracle. The caller will be the deployer address. 
 * Params will be:
 * assets:[debtAssetAddress, collateralAssetAddress]
 * sources: ["0xd30e2101a97dcbAeBCBC04F14C3f624E67A35165","0x0fb99723aee6f420bead13e6bbb79b7e6f034298"]
 */