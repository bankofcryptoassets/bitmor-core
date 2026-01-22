import { ethers } from 'hardhat';
import {
  getLendingPool,
  getLendingPoolAddressesProvider,
} from '../../../helpers/contracts-getters.js';
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
