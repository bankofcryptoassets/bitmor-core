const hre = require('hardhat');

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
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
