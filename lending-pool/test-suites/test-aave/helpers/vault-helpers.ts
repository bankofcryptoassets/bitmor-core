/**
 * Vault deposit helpers for Hardhat 3 / ethers v6 test infrastructure.
 *
 * BITMOR ARCHITECTURE:
 * - USDC deposits: Use mockBitmorUSDCVault (ERC-4626, registered as USDCVault)
 * - bvBTC (DAI, WETH, vault shares): Use mockLoanProvider (pass-through, registered as BitmorLoan)
 *
 * Usage: Call depositViaVault() instead of pool.deposit() in tests - it handles
 * the full flow: mint → approve → vault.deposit (vault receives aTokens, user gets shares)
 */

import type { MintableERC20, WETH9Mocked } from '../../../types/ethers-contracts/index.js';
import type { SignerWithAddress } from '../../../helpers/types.js';
import type { TestEnv } from './make-suite.js';
import { parseEther } from 'ethers';
import { APPROVAL_AMOUNT_LENDING_POOL } from '../../../helpers/constants.js';

/**
 * @notice One-call helper: mint → approve → deposit via vault
 * @dev This is the main function tests should use instead of pool.deposit()
 *
 * Flow:
 * 1. Mint tokens to user
 * 2. User approves vault
 * 3. Vault deposits to pool (vault receives aTokens)
 * 4. User receives vault shares (for USDC) or direct aTokens (for CBBTC via mockLoanProvider)
 *
 * BITMOR ARCHITECTURE:
 * - USDC: mockBitmorUSDCVault.deposit(amount, user)
 * - bvBTC: mockLoanProvider.deposit(asset, amount, user, 0)
 *
 * @param asset The ERC20 token to deposit
 * @param amount The amount to deposit
 * @param user The user performing the deposit
 * @param testEnv The test environment
 * @returns The amount of shares/aTokens minted to user
 */
export async function depositViaVault(
  asset: MintableERC20 | WETH9Mocked,
  amount: bigint,
  user: SignerWithAddress,
  testEnv: TestEnv
): Promise<bigint> {
  const { mockBitmorUSDCVault, mockLoanProvider, usdc, btcVault, addressesProvider, deployer } = testEnv;

  const assetAddress = await asset.getAddress();
  const usdcAddress = await usdc.getAddress();
  const btcVaultAddress = await btcVault.getAddress();

  // Determine if this is USDC or other asset
  const isUSDC = assetAddress.toLowerCase() === usdcAddress.toLowerCase();
  const isBvBTC = assetAddress.toLowerCase() === btcVaultAddress.toLowerCase();

  let vaultAddress: string;
  let usesBitmorLoanPath = !isUSDC;

  if (isUSDC) {
    vaultAddress = await mockBitmorUSDCVault.getAddress();
  } else {
    vaultAddress = await mockLoanProvider.getAddress();
  }

  // Register vault in appropriate slot for pool access control
  // LendingPool.deposit() checks: msg.sender == usdcVault OR msg.sender == bitmorLoan
  if (usesBitmorLoanPath) {
    // For CBBTC, register mockLoanProvider as BitmorLoan
    const currentLoan = await addressesProvider.getBitmorLoan();
    if (currentLoan.toLowerCase() !== vaultAddress.toLowerCase()) {
      await addressesProvider.connect(deployer.signer).setBitmorLoan(vaultAddress);
    }
  } else {
    // For USDC, register mockBitmorUSDCVault as USDCVault
    const currentVault = await addressesProvider.getUSDCVault();
    if (currentVault.toLowerCase() !== vaultAddress.toLowerCase()) {
      await addressesProvider.connect(deployer.signer).setUSDCVault(vaultAddress);
    }
  }

  // 1. Mint tokens to user
  if (isBvBTC) {
    await btcVault.mint(user.address, amount);
  } else {
    await asset.connect(user.signer).mint(amount);
  }

  // 2. User approves vault
  await asset.connect(user.signer).approve(vaultAddress, APPROVAL_AMOUNT_LENDING_POOL);

  // 3. Deposit via vault
  if (isUSDC) {
    // deposit(assets, receiver) → vault receives aTokens, user receives shares
    const tx = await mockBitmorUSDCVault.connect(user.signer).deposit(amount, user.address);
    await tx.wait();
  } else {
    const tx = await mockLoanProvider.connect(user.signer).deposit(assetAddress, amount, user.address, 0);
    await tx.wait();
  }

  // Return amount (1:1 for mock vaults)
  return amount;
}

/**
 * @notice Helper for BTC collateral tests: deposit bvBTC + borrow USDC
 *
 * @param btcAmount The amount of bvBTC (vault shares) to deposit as collateral
 * @param borrowAmount The amount of USDC to borrow
 * @param user The user performing the operations
 * @param testEnv The test environment
 */
export async function setupBTCCollateralAndBorrow(
  btcAmount: bigint,
  borrowAmount: bigint,
  user: SignerWithAddress,
  testEnv: TestEnv
): Promise<void> {
  const { pool, btcVault, usdc } = testEnv;

  // 1. Deposit bvBTC (vault shares) as collateral
  await depositViaVault(btcVault as any, btcAmount, user, testEnv);

  // 2. Borrow USDC
  const usdcAddress = await usdc.getAddress();
  await pool.connect(user.signer).borrow(usdcAddress, borrowAmount, 2, 0, user.address);
}
