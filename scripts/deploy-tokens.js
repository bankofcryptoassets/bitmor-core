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

  // Save deployment address
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

  return { address: token.address, contract: token };
}

async function main() {
  const [deployer] = await hre.ethers.getSigners();

  console.log('Deploying Mock Tokens');
  console.log('Network:', hre.network.name);
  console.log('Account:', deployer.address);
  console.log('Balance:', (await deployer.getBalance()).toString());

  // Deploy USDC
  const usdc = await deployToken('USD Coin', 'USDC', 6);

  // Deploy cbBTC
  const cbBTC = await deployToken('Coinbase Wrapped BTC', 'cbBTC', 8);

  console.log('\nDeployment Summary:');
  console.log('USDC:', usdc.address);
  console.log('cbBTC:', cbBTC.address);

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
