import { ethers } from 'hardhat';
import {
  getLendingPool,
  getLendingPoolAddressesProvider,
} from '../../../helpers/contracts-getters.js';
import { deployMockBTCVault, deployMockLoan } from '../../../helpers/contracts-deployments.js';
import type { MockLoanProvider } from '../../../types/ethers-contracts/mocks/MockBitmorCaller.sol/MockLoanProvider.js';
import type { MockUSDCVault } from '../../../types/ethers-contracts/mocks/MockBitmorCaller.sol/MockUSDCVault.js';

export interface BitmorMocks {
  mockLoanProvider: MockLoanProvider;
  mockUSDCVault: MockUSDCVault;
}

/**
 * Deploys mock Bitmor caller contracts and registers them with the AddressesProvider
 * @returns The deployed mock contracts
 */
export async function deployMockBitmorCallers(): Promise<BitmorMocks> {
  const pool = await getLendingPool();
  const addressesProvider = await getLendingPoolAddressesProvider();

  // Deploy MockLoanProvider
  const MockLoanProviderFactory = await ethers.getContractFactory('MockLoanProvider');
  const mockLoanProvider = (await MockLoanProviderFactory.deploy(
    pool.address
  )) as MockLoanProvider;
  await mockLoanProvider.deployed();

  // Deploy MockUSDCVault
  const MockUSDCVaultFactory = await ethers.getContractFactory('MockUSDCVault');
  const mockUSDCVault = (await MockUSDCVaultFactory.deploy(pool.address)) as MockUSDCVault;
  await mockUSDCVault.deployed();

  // Register with AddressesProvider
  await addressesProvider.setBitmorLoan(mockLoanProvider.address);
  await addressesProvider.setUSDCVault(mockUSDCVault.address);

  console.log(`MockLoanProvider deployed at: ${mockLoanProvider.address}`);
  console.log(`MockUSDCVault deployed at: ${mockUSDCVault.address}`);

  return { mockLoanProvider, mockUSDCVault };
}

/**
 * @notice Deploy MockBTCVault for testing
 * @param addressesProvider The LendingPoolAddressesProvider address
 * @param cbBTCAddress The cbBTC token address
 */
export async function deployBTCVault(
  addressesProvider: string,
  cbBTCAddress: string
): Promise<string> {
  const btcVault = await deployMockBTCVault([addressesProvider, cbBTCAddress], false);
  return btcVault.address;
}

/**
 * @notice Deploy MockLoan for testing liquidation logic
 * @param collateralAsset The collateral asset address (bvBTC)
 * @param debtAsset The debt asset address (USDC)
 */
export async function deployLoanContract(
  collateralAsset: string,
  debtAsset: string
): Promise<string> {
  const mockLoan = await deployMockLoan([collateralAsset, debtAsset], false);
  return mockLoan.address;
}
