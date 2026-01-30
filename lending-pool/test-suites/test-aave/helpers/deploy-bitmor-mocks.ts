/**
 * Bitmor mock deployment helpers for Hardhat 3 / ethers v6.
 *
 * Provides:
 * - deployMockBitmorCallers(): Deploys MockLoanProvider and MockUSDCVault (from MockBitmorCaller.sol)
 *   and registers them with AddressesProvider
 * - deployBTCVault(): Deploys MockBTCVault for cbBTC collateral testing
 * - deployLoanContract(): Deploys MockLoan for liquidation testing
 *
 * ethers v6 patterns used:
 * - .getAddress() instead of .address
 * - .waitForDeployment() instead of .deployed()
 * - Fully qualified contract names for ambiguous artifacts
 */

import { DRE } from '../../../helpers/misc-utils.js';
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

  // In ethers v6, use .target for contract addresses
  const poolAddress = await pool.getAddress();
  const addressesProviderAddress = await addressesProvider.getAddress();

  // Deploy MockLoanProvider (uses DRE.ethers for Hardhat 3 compatibility)
  const MockLoanProviderFactory = await DRE.ethers.getContractFactory('MockLoanProvider');
  const mockLoanProvider = (await MockLoanProviderFactory.deploy(
    poolAddress
  )) as MockLoanProvider;
  await mockLoanProvider.waitForDeployment();

  // Deploy MockUSDCVault (from MockBitmorCaller.sol with single arg - use fully qualified name)
  const MockUSDCVaultFactory = await DRE.ethers.getContractFactory('contracts/mocks/MockBitmorCaller.sol:MockUSDCVault');
  const mockUSDCVault = (await MockUSDCVaultFactory.deploy(poolAddress)) as MockUSDCVault;
  await mockUSDCVault.waitForDeployment();

  // Get deployed addresses (ethers v6)
  const mockLoanProviderAddress = await mockLoanProvider.getAddress();
  const mockUSDCVaultAddress = await mockUSDCVault.getAddress();

  // Register with AddressesProvider
  await addressesProvider.setBitmorLoan(mockLoanProviderAddress);
  await addressesProvider.setUSDCVault(mockUSDCVaultAddress);

  console.log(`MockLoanProvider deployed at: ${mockLoanProviderAddress}`);
  console.log(`MockUSDCVault deployed at: ${mockUSDCVaultAddress}`);

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
