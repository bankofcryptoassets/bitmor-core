import type { MintableERC20, WETH9Mocked } from '../../../types/ethers-contracts/index.js';
import type { SignerWithAddress } from '../../../helpers/types.js';
import type { TestEnv } from './make-suite.js';
import { parseEther } from 'ethers';

/**
 * @notice One-call helper: mint → approve → deposit via vault
 * @dev This is the main function tests should use instead of pool.deposit()
 *
 * Flow:
 * 1. Mint tokens to user
 * 2. User approves vault
 * 3. Vault deposits to pool (vault receives aTokens)
 * 4. User receives vault shares
 *
 * BITMOR: Automatically selects the correct vault based on the asset being deposited.
 * - For DAI/stablecoins: uses usdcVault (DAI vault)
 * - For USDC: uses actualUSDCVault
 * - For WETH: uses wethVault
 * - For cbBTC: uses btcVault (registered as BitmorLoan for pool access)
 *
 * @param asset The ERC20 token to deposit
 * @param amount The amount to deposit
 * @param user The user performing the deposit
 * @param testEnv The test environment
 * @returns The amount of shares minted to user
 */
export async function depositViaVault(
  asset: MintableERC20 | WETH9Mocked,
  amount: bigint,
  user: SignerWithAddress,
  testEnv: TestEnv
): Promise<bigint> {
  const { usdcVault, actualUSDCVault, wethVault, btcVault, weth, usdc, cbBTC, addressesProvider, deployer } = testEnv;

  const assetAddress = await asset.getAddress();
  const wethAddress = await weth.getAddress();
  const usdcAddress = await usdc.getAddress();
  const cbBTCAddress = cbBTC ? await cbBTC.getAddress() : null;

  // Select correct vault and registration method based on asset
  let vault;
  let usesBitmorLoanPath = false;

  if (cbBTCAddress && assetAddress.toLowerCase() === cbBTCAddress.toLowerCase()) {
    vault = btcVault;
    usesBitmorLoanPath = true; // BTC uses loanProvider path for pool access
  } else if (assetAddress.toLowerCase() === wethAddress.toLowerCase()) {
    vault = wethVault;
  } else if (assetAddress.toLowerCase() === usdcAddress.toLowerCase()) {
    vault = actualUSDCVault;
  } else {
    vault = usdcVault; // DAI and other tokens
  }

  const vaultAddress = await vault.getAddress();

  // Register vault in appropriate slot for pool access control
  // LendingPool.deposit() checks: msg.sender == usdcVault OR msg.sender == bitmorLoan
  if (usesBitmorLoanPath) {
    // For BTC deposits, register vault as BitmorLoan
    const currentLoan = await addressesProvider.getBitmorLoan();
    if (currentLoan.toLowerCase() !== vaultAddress.toLowerCase()) {
      await addressesProvider.connect(deployer.signer).setBitmorLoan(vaultAddress);
    }
  } else {
    // For USDC/WETH/DAI, register as USDCVault
    const currentVault = await addressesProvider.getUSDCVault();
    if (currentVault.toLowerCase() !== vaultAddress.toLowerCase()) {
      await addressesProvider.connect(deployer.signer).setUSDCVault(vaultAddress);
    }
  }

  // 1. Mint tokens to user
  await asset.connect(user.signer).mint(amount);

  // 2. User approves vault
  await asset.connect(user.signer).approve(vaultAddress, amount);

  // 3. Deposit via vault (returns shares)
  const tx = await vault.connect(user.signer).deposit(amount, user.address);
  await tx.wait();

  // For 1:1 mock vault, shares = amount
  return amount;
}

/**
 * @notice Helper for BTC collateral tests: deposit bvBTC + borrow USDC
 *
 * @param btcAmount The amount of cbBTC to deposit as collateral
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
  const { pool, cbBTC, usdc } = testEnv;

  // 1. Deposit cbBTC via vault (user gets bvBTC shares, vault gets aTokens)
  await depositViaVault(cbBTC, btcAmount, user, testEnv);

  // 2. Borrow USDC
  const usdcAddress = await usdc.getAddress();
  await pool.connect(user.signer).borrow(usdcAddress, borrowAmount, 2, 0, user.address);
}

/**
 * @notice Helper for liquidation tests: deposit collateral + borrow
 *
 * @param collateralAsset The asset to use as collateral
 * @param collateralAmount The amount of collateral to deposit
 * @param borrowAsset The asset to borrow
 * @param borrowAmount The amount to borrow
 * @param user The user performing the operations
 * @param testEnv The test environment
 */
export async function setupCollateralAndBorrow(
  collateralAsset: MintableERC20,
  collateralAmount: bigint,
  borrowAsset: MintableERC20,
  borrowAmount: bigint,
  user: SignerWithAddress,
  testEnv: TestEnv
): Promise<void> {
  const { pool } = testEnv;

  // 1. Deposit collateral via vault
  await depositViaVault(collateralAsset, collateralAmount, user, testEnv);

  // 2. Borrow
  const borrowAssetAddress = await borrowAsset.getAddress();
  await pool.connect(user.signer).borrow(borrowAssetAddress, borrowAmount, 2, 0, user.address);
}

/**
 * @notice Helper for flash loan tests: setup liquidity in the pool
 *
 * @param testEnv The test environment
 * @param amounts Optional amounts to deposit for each asset
 */
export async function setupFlashLoanLiquidity(
  testEnv: TestEnv,
  amounts?: {
    weth?: bigint;
    dai?: bigint;
    usdc?: bigint;
  }
): Promise<void> {
  const { weth, dai, usdc, deployer } = testEnv;

  const defaultAmounts = {
    weth: amounts?.weth || parseEther('1000'),
    dai: amounts?.dai || parseEther('1000000'),
    usdc: amounts?.usdc || parseEther('1000000'),
  };

  // Deposit liquidity for flash loans
  if (defaultAmounts.weth) {
    await depositViaVault(weth, defaultAmounts.weth, deployer, testEnv);
  }
  if (defaultAmounts.dai) {
    await depositViaVault(dai, defaultAmounts.dai, deployer, testEnv);
  }
  if (defaultAmounts.usdc) {
    await depositViaVault(usdc, defaultAmounts.usdc, deployer, testEnv);
  }
}
