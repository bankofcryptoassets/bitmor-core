const hre = require('hardhat');
const fs = require('fs');
const path = require('path');

async function main() {
  const [deployer] = await hre.ethers.getSigners();

  console.log('Deploying Aave V2 Protocol');
  console.log('Network:', hre.network.name);
  console.log('Deployer:', deployer.address);
  console.log('Balance:', hre.ethers.utils.formatEther(await deployer.getBalance()), 'ETH');

  console.log('\nStep 1: Deploying Address Provider...');
  await hre.run('full:deploy-address-provider', {
    pool: 'Bitmor',
    verify: false,
    skipRegistry: true,
  });

  console.log('\nStep 2: Deploying Lending Pool...');
  await hre.run('full:deploy-lending-pool', {
    pool: 'Bitmor',
    verify: false,
  });

  console.log('\nStep 3: Deploying Oracles...');
  await hre.run('full:deploy-oracles', {
    pool: 'Bitmor',
    verify: false,
  });

  console.log('\nStep 4: Deploying Data Provider...');
  await hre.run('full:data-provider', {
    pool: 'Bitmor',
    verify: false,
  });

  console.log('\nStep 5: Initializing Reserves...');
  await hre.run('full:initialize-lending-pool', {
    pool: 'Bitmor',
    verify: false,
  });

  console.log('\n=== Aave V2 Deployment Complete ===');
  console.log('\nFetching deployed addresses...');

  const deploymentData = {
    network: hre.network.name,
    deployer: deployer.address,
    timestamp: new Date().toISOString(),
    contracts: {},
  };

  try {
    const addressesProvider = await hre.ethers.getContract('LendingPoolAddressesProvider');
    deploymentData.contracts.LendingPoolAddressesProvider = addressesProvider.address;

    deploymentData.contracts.LendingPool = await addressesProvider.getLendingPool();
    deploymentData.contracts.LendingPoolConfigurator = await addressesProvider.getLendingPoolConfigurator();
    deploymentData.contracts.PriceOracle = await addressesProvider.getPriceOracle();
    deploymentData.contracts.LendingPoolCollateralManager = await addressesProvider.getLendingPoolCollateralManager();
    deploymentData.contracts.PoolAdmin = await addressesProvider.getPoolAdmin();
    deploymentData.contracts.EmergencyAdmin = await addressesProvider.getEmergencyAdmin();

    console.log('\nDeployed Contracts:');
    console.log('-------------------');
    Object.entries(deploymentData.contracts).forEach(([name, address]) => {
      console.log(`${name}: ${address}`);
    });

    const deploymentDir = path.join(__dirname, '../deployments');
    if (!fs.existsSync(deploymentDir)) {
      fs.mkdirSync(deploymentDir, { recursive: true });
    }

    const deploymentFile = path.join(deploymentDir, `${hre.network.name}-aave-v2.json`);
    fs.writeFileSync(deploymentFile, JSON.stringify(deploymentData, null, 2));
    console.log('\nDeployment info saved to:', deploymentFile);
  } catch (error) {
    console.error('Error fetching contract addresses:', error.message);
  }

  console.log('\nNext steps:');
  console.log('1. Update Loan contract with LendingPool address');
  console.log('2. Set BitmorLoan address in AddressesProvider');
  console.log('3. Test deposits and borrows with mock tokens');
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
