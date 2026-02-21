/**
 * Tests for micro-liquidation functionality.
 */

import { makeSuite } from './helpers/make-suite.js';
import type { TestEnv } from './helpers/make-suite.js';
import { APPROVAL_AMOUNT_LENDING_POOL } from '../../helpers/constants.js';
import { convertToCurrencyDecimals, getContractAddress } from '../../helpers/contracts-helpers.js';
import { ProtocolErrors } from '../../helpers/types.js';
import { DRE } from '../../helpers/misc-utils.js';
import { parseEther, parseUnits, AbiCoder, MaxUint256 } from 'ethers';
import BigNumber from 'bignumber.js';
import chai from 'chai';

const { expect } = chai;

makeSuite('Micro-Liquidation', (testEnv: TestEnv) => {
  const abiCoder = new AbiCoder();

  /**
   * Setup a user with bvBTC collateral and USDC debt (for checkTypeOfLiquidation tests).
   * These tests only check the liquidation type, they don't execute the actual liquidation.
   * Uses bvBTC (vault shares) as collateral since that's what the lending pool recognizes.
   */
  async function setupUserWithDebt(
    testEnv: TestEnv,
    userIndex: number,
    collateralAmount: string,
    borrowAmount: string
  ) {
    const { users, pool, usdc, btcVault, addressesProvider, mockBitmorUSDCVault, deployer } = testEnv;
    const user = users[userIndex];

    // First, ensure there's USDC liquidity in the pool (deployer acts as liquidity provider)
    const liquidityAmount = await convertToCurrencyDecimals(getContractAddress(usdc), '100000');
    await usdc.connect(deployer.signer).mint(liquidityAmount);
    await usdc.connect(deployer.signer).approve(getContractAddress(pool), APPROVAL_AMOUNT_LENDING_POOL);
    await addressesProvider.setUSDCVault(deployer.address);
    await pool.connect(deployer.signer).deposit(getContractAddress(usdc), liquidityAmount, deployer.address, '0');

    // Mint and deposit bvBTC (vault shares) as collateral
    const bvBTCAmount = await convertToCurrencyDecimals(getContractAddress(btcVault), collateralAmount);
    await btcVault.mint(user.address, bvBTCAmount);
    await btcVault.connect(user.signer).approve(getContractAddress(pool), APPROVAL_AMOUNT_LENDING_POOL);

    // Set user as vault to bypass vault check for deposit
    await addressesProvider.setUSDCVault(user.address);
    await pool.connect(user.signer).deposit(getContractAddress(btcVault), bvBTCAmount, user.address, '0');

    // Borrow USDC
    const usdcAmount = await convertToCurrencyDecimals(getContractAddress(usdc), borrowAmount);
    await addressesProvider.setBitmorLoan(user.address);
    await addressesProvider.setUSDCVault(mockBitmorUSDCVault.target);
    await pool.connect(user.signer).borrow(getContractAddress(usdc), usdcAmount, 2, 0, user.address);

    return { user, bvBTCAmount, usdcAmount };
  }

  /**
   * Setup a user with bvBTC vault collateral and USDC debt (for execution tests).
   * These tests actually execute micro-liquidation, so collateral must be ERC4626 vault shares
   * because the CollateralManager calls IERC4626.previewRedeem() and IERC4626.redeem().
   */
  async function setupUserWithVaultDebt(
    testEnv: TestEnv,
    userIndex: number,
    collateralAmount: string,
    borrowAmount: string
  ) {
    const { users, pool, usdc, btcVault, addressesProvider, mockBitmorUSDCVault, mockLoanProvider, deployer } = testEnv;
    const user = users[userIndex];

    // 1. Ensure USDC liquidity in the pool
    const liquidityAmount = await convertToCurrencyDecimals(getContractAddress(usdc), '100000');
    await usdc.connect(deployer.signer).mint(liquidityAmount);
    await usdc.connect(deployer.signer).approve(getContractAddress(pool), APPROVAL_AMOUNT_LENDING_POOL);
    await addressesProvider.setUSDCVault(deployer.address);
    await pool.connect(deployer.signer).deposit(getContractAddress(usdc), liquidityAmount, deployer.address, '0');

    // 2. Deposit bvBTC (vault shares) as collateral via mockLoanProvider
    const bvBTCAmount = await convertToCurrencyDecimals(getContractAddress(btcVault), collateralAmount);
    await btcVault.mint(user.address, bvBTCAmount);
    await btcVault.connect(user.signer).approve(getContractAddress(mockLoanProvider), APPROVAL_AMOUNT_LENDING_POOL);
    await addressesProvider.setBitmorLoan(getContractAddress(mockLoanProvider));
    await mockLoanProvider
      .connect(user.signer)
      .deposit(getContractAddress(btcVault), bvBTCAmount, user.address, '0');

    // 3. Borrow USDC
    const usdcAmount = await convertToCurrencyDecimals(getContractAddress(usdc), borrowAmount);
    await addressesProvider.setBitmorLoan(user.address);
    await addressesProvider.setUSDCVault(mockBitmorUSDCVault.target);
    await pool.connect(user.signer).borrow(getContractAddress(usdc), usdcAmount, 2, 0, user.address);

    return { user, bvBTCAmount, usdcAmount };
  }

  describe('checkTypeOfLiquidation', () => {
    it('Returns 0 when loan status is not Active', async () => {
      const { pool, users, mockLoan, addressesProvider, btcVault, usdc } = testEnv;
      const user = users[0];

      // Setup MockLoan with Completed status
      await mockLoan.setCollateralAssetAddress(getContractAddress(btcVault));
      await mockLoan.setDebtAssetAddress(getContractAddress(usdc));
      await addressesProvider.setBitmorLoan(getContractAddress(mockLoan));

      // Create a loan with Completed status
      await mockLoan.createActiveLoan(
        user.address,
        user.address,
        parseUnits('1', 8), // 1 bvBTC
        parseUnits('50000', 6), // 50k USDC
        12, // 12 months
        parseUnits('4500', 6) // ~4500 USDC monthly
      );
      await mockLoan.setLoanStatus(user.address, 1); // 1 = Completed

      const liquidationType = await pool.checkTypeOfLiquidation(user.address);
      expect(liquidationType).to.equal(0n);
    });

    it('Returns 0 when loan is not overdue', async () => {
      const { pool, users, mockLoan, addressesProvider, btcVault, usdc } = testEnv;
      const user = users[1];

      // Setup MockLoan
      await mockLoan.setCollateralAssetAddress(getContractAddress(btcVault));
      await mockLoan.setDebtAssetAddress(getContractAddress(usdc));
      await addressesProvider.setBitmorLoan(getContractAddress(mockLoan));

      // Create an active loan that's NOT overdue (lastPaymentTimestamp = now)
      await mockLoan.createActiveLoan(
        user.address,
        user.address,
        parseUnits('1', 8),
        parseUnits('50000', 6),
        12,
        parseUnits('4500', 6)
      );

      const liquidationType = await pool.checkTypeOfLiquidation(user.address);
      expect(liquidationType).to.equal(0n);
    });

    it('Returns 1 (full liquidation) when uninsured and health factor < 1', async () => {
      const { pool, users, mockLoan, addressesProvider, btcVault, usdc, aggregators } = testEnv;
      const user = users[2];

      // Setup user with collateral and debt
      await setupUserWithDebt(testEnv, 2, '1', '45000');

      // Setup MockLoan with uninsured loan
      await mockLoan.setCollateralAssetAddress(getContractAddress(btcVault));
      await mockLoan.setDebtAssetAddress(getContractAddress(usdc));
      await addressesProvider.setBitmorLoan(getContractAddress(mockLoan));

      await mockLoan.createActiveLoan(
        user.address,
        user.address,
        parseUnits('1', 8),
        parseUnits('45000', 6),
        12,
        parseUnits('4000', 6)
      );
      // Ensure uninsured (insuranceID = 0)
      await mockLoan.setInsuranceId(user.address, 0);

      // Drop bvBTC price by dropping cbBTC price (bvBTC price = cbBTC price × previewRedeem)
      const cbBTCAggregator = aggregators['cbBTC'];
      const currentPrice = await cbBTCAggregator.latestAnswer();
      await cbBTCAggregator.updateAnswer((currentPrice * 30n) / 100n);

      const liquidationType = await pool.checkTypeOfLiquidation(user.address);
      expect(liquidationType).to.equal(1n); // Full liquidation

      // Restore price
      await cbBTCAggregator.updateAnswer(currentPrice);
    });

    it('Returns 2 (micro-liquidation) when loan is overdue with sufficient collateral', async () => {
      const { pool, users, mockLoan, addressesProvider, btcVault, usdc } = testEnv;
      const user = users[3];

      // Setup user with collateral and debt
      await setupUserWithDebt(testEnv, 3, '1', '30000');

      // Setup MockLoan
      await mockLoan.setCollateralAssetAddress(getContractAddress(btcVault));
      await mockLoan.setDebtAssetAddress(getContractAddress(usdc));
      await addressesProvider.setBitmorLoan(getContractAddress(mockLoan));

      await mockLoan.createActiveLoan(
        user.address,
        user.address,
        parseUnits('1', 8),
        parseUnits('30000', 6),
        12,
        parseUnits('2800', 6)
      );

      // Make loan overdue
      await mockLoan.makeLoanOverdue(user.address, 1);

      const liquidationType = await pool.checkTypeOfLiquidation(user.address);
      expect(liquidationType).to.equal(2n); // Micro-liquidation
    });
  });

  describe('microLiquidationCall', () => {
    it('Successfully executes micro-liquidation for overdue loan', async () => {
      const { pool, users, mockLoan, addressesProvider, cbBTC, btcVault, usdc, deployer } = testEnv;
      const borrower = users[4];
      const liquidator = deployer;

      // Setup borrower with bvBTC vault collateral and USDC debt
      await setupUserWithVaultDebt(testEnv, 4, '1', '25000');

      // Setup MockLoan with bvBTC as collateral asset
      await mockLoan.setCollateralAssetAddress(getContractAddress(btcVault));
      await mockLoan.setDebtAssetAddress(getContractAddress(usdc));
      await addressesProvider.setBitmorLoan(getContractAddress(mockLoan));

      await mockLoan.createActiveLoan(
        borrower.address,
        borrower.address,
        parseUnits('1', 8),
        parseUnits('25000', 6),
        6, // 6 months duration
        parseUnits('4500', 6)
      );

      // Make loan overdue
      await mockLoan.makeLoanOverdue(borrower.address, 1);

      // Verify it's eligible for micro-liquidation
      const liquidationType = await pool.checkTypeOfLiquidation(borrower.address);
      expect(liquidationType).to.equal(2n);

      // Liquidator needs USDC to pay the debt
      const monthlyPayment = parseUnits('4500', 6);
      await usdc.connect(liquidator.signer).mint(monthlyPayment);
      await usdc.connect(liquidator.signer).approve(getContractAddress(pool), APPROVAL_AMOUNT_LENDING_POOL);

      // Fund vault with cbBTC for redemption during micro-liquidation
      const fundAmount = await convertToCurrencyDecimals(getContractAddress(cbBTC), '10');
      await cbBTC.mint(fundAmount);
      await cbBTC.transfer(getContractAddress(btcVault), fundAmount);

      // Encode micro-liquidation call data with bvBTC as collateral
      const callData = abiCoder.encode(
        ['address', 'address', 'address'],
        [getContractAddress(btcVault), getContractAddress(usdc), borrower.address]
      );

      // Execute micro-liquidation (should succeed without reverting)
      await pool.connect(liquidator.signer).microLiquidationCall(callData);

      // Verify MockLoan was updated
      const microLiqCount = await mockLoan.microLiquidationCount(borrower.address);
      expect(microLiqCount).to.equal(1n);
    });

    it('Reverts micro-liquidation when loan is not overdue', async () => {
      const { pool, users, mockLoan, addressesProvider, btcVault, usdc, deployer } = testEnv;
      const borrower = users[5];
      const liquidator = deployer;

      // Setup borrower with collateral and debt
      await setupUserWithDebt(testEnv, 5, '1', '25000');

      // Setup MockLoan (NOT overdue - fresh loan)
      await mockLoan.setCollateralAssetAddress(getContractAddress(btcVault));
      await mockLoan.setDebtAssetAddress(getContractAddress(usdc));
      await addressesProvider.setBitmorLoan(getContractAddress(mockLoan));

      await mockLoan.createActiveLoan(
        borrower.address,
        borrower.address,
        parseUnits('1', 8),
        parseUnits('25000', 6),
        6,
        parseUnits('4500', 6)
      );

      // Liquidator needs USDC
      const monthlyPayment = parseUnits('4500', 6);
      await usdc.connect(liquidator.signer).mint(monthlyPayment);
      await usdc.connect(liquidator.signer).approve(getContractAddress(pool), APPROVAL_AMOUNT_LENDING_POOL);

      // Encode call data
      const callData = abiCoder.encode(
        ['address', 'address', 'address'],
        [getContractAddress(btcVault), getContractAddress(usdc), borrower.address]
      );

      // Should revert because loan is not overdue (type = 0)
      let reverted = false;
      try {
        await pool.connect(liquidator.signer).microLiquidationCall(callData);
      } catch (e) {
        reverted = true;
      }
      expect(reverted).to.equal(true, 'Expected micro-liquidation to revert for non-overdue loan');
    });

    it('Completes loan when duration becomes 0 after micro-liquidation', async () => {
      const { pool, users, mockLoan, addressesProvider, cbBTC, btcVault, usdc, deployer } = testEnv;
      const borrower = users[6];
      const liquidator = deployer;

      // Setup borrower with bvBTC vault collateral and USDC debt
      await setupUserWithVaultDebt(testEnv, 6, '1', '5000');

      // Setup MockLoan with duration = 1 (last month), bvBTC as collateral
      await mockLoan.setCollateralAssetAddress(getContractAddress(btcVault));
      await mockLoan.setDebtAssetAddress(getContractAddress(usdc));
      await addressesProvider.setBitmorLoan(getContractAddress(mockLoan));

      await mockLoan.createActiveLoan(
        borrower.address,
        borrower.address,
        parseUnits('1', 8),
        parseUnits('5000', 6),
        1, // Only 1 month remaining
        parseUnits('5000', 6)
      );

      // Make loan overdue
      await mockLoan.makeLoanOverdue(borrower.address, 1);

      // Liquidator needs USDC
      await usdc.connect(liquidator.signer).mint(parseUnits('5000', 6));
      await usdc.connect(liquidator.signer).approve(getContractAddress(pool), APPROVAL_AMOUNT_LENDING_POOL);

      // Fund vault with cbBTC for redemption during micro-liquidation
      const fundAmount = await convertToCurrencyDecimals(getContractAddress(cbBTC), '10');
      await cbBTC.mint(fundAmount);
      await cbBTC.transfer(getContractAddress(btcVault), fundAmount);

      // Encode call data with bvBTC as collateral
      const callData = abiCoder.encode(
        ['address', 'address', 'address'],
        [getContractAddress(btcVault), getContractAddress(usdc), borrower.address]
      );

      // Execute micro-liquidation
      await pool.connect(liquidator.signer).microLiquidationCall(callData);

      // When duration was 1, micro-liquidation completes the loan (not full liquidation)
      const completionCount = await mockLoan.microLiquidationCompletionCount(borrower.address);
      expect(completionCount).to.equal(1n, 'micro-liquidation completion should be called once');

      // Verify full liquidation was NOT called
      const fullLiqCount = await mockLoan.fullLiquidationCount(borrower.address);
      expect(fullLiqCount).to.equal(0n, 'full liquidation should not be triggered');
    });
  });

  describe('validateMicroLiquidationCall edge cases', () => {
    const {
      LPCM_COLLATERAL_CANNOT_BE_LIQUIDATED,
      LPCM_SPECIFIED_CURRENCY_NOT_BORROWED_BY_USER,
    } = ProtocolErrors;

    it('Reverts micro-liquidation when collateral is not enabled for user', async () => {
      const { pool, users, mockLoan, addressesProvider, btcVault, usdc, deployer } = testEnv;
      const user = users[0];

      // Give user a real pool position (bvBTC collateral + USDC debt) so that
      // checkTypeOfLiquidation reads real aToken balance and returns type 2.
      await setupUserWithDebt(testEnv, 0, '1', '30000');

      await mockLoan.setCollateralAssetAddress(getContractAddress(btcVault));
      await mockLoan.setDebtAssetAddress(getContractAddress(usdc));
      await addressesProvider.setBitmorLoan(getContractAddress(mockLoan));

      await mockLoan.createActiveLoan(
        user.address,
        user.address,
        parseUnits('1', 8),
        parseUnits('30000', 6),
        12,
        parseUnits('2800', 6)
      );

      await mockLoan.makeLoanOverdue(user.address, 1);

      // Pass USDC as collateral - user deposited bvBTC not USDC, so USDC is not enabled as collateral.
      // checkTypeOfLiquidation uses the real collateral asset (bvBTC) from mockLoan and returns type 2,
      // but validateMicroLiquidationCall checks the passed collateral (USDC) which is not enabled.
      const callData = abiCoder.encode(
        ['address', 'address', 'address'],
        [getContractAddress(usdc), getContractAddress(usdc), user.address]
      );

      await expect(
        pool.connect(deployer.signer).microLiquidationCall(callData)
      ).to.be.revertedWith(LPCM_COLLATERAL_CANNOT_BE_LIQUIDATED);
    });

    it('Reverts micro-liquidation when user has no debt in specified currency', async () => {
      const { pool, users, mockLoan, addressesProvider, btcVault, usdc, deployer } = testEnv;
      // Reuse user[2] who has bvBTC as collateral and USDC debt (no bvBTC debt)
      const user = users[2];

      await mockLoan.setCollateralAssetAddress(getContractAddress(btcVault));
      await mockLoan.setDebtAssetAddress(getContractAddress(usdc));
      await addressesProvider.setBitmorLoan(getContractAddress(mockLoan));

      await mockLoan.createActiveLoan(
        user.address,
        user.address,
        parseUnits('1', 8),
        parseUnits('45000', 6),
        12,
        parseUnits('4000', 6)
      );

      await mockLoan.makeLoanOverdue(user.address, 1);

      // Pass bvBTC as BOTH collateral and debt - user has bvBTC as collateral
      // but has no bvBTC debt (they only borrowed USDC)
      const callData = abiCoder.encode(
        ['address', 'address', 'address'],
        [getContractAddress(btcVault), getContractAddress(btcVault), user.address]
      );

      await expect(
        pool.connect(deployer.signer).microLiquidationCall(callData)
      ).to.be.revertedWith(LPCM_SPECIFIED_CURRENCY_NOT_BORROWED_BY_USER);
    });
  });

  describe('LendingPoolCollateralManager: collateral capping in micro-liquidation', () => {
    it('Routes to full liquidation when payment exceeds collateral value (vuln-21 fix)', async () => {
      const { pool, users, mockLoan, addressesProvider, btcVault, usdc, deployer, aggregators } = testEnv;
      const user = users[1];

      // Set up user[1] with small bvBTC collateral (0.05 bvBTC) and USDC debt
      await setupUserWithVaultDebt(testEnv, 1, '0.05', '3000');

      // MockLoan: insured, large monthly payment relative to actual collateral
      await mockLoan.setCollateralAssetAddress(getContractAddress(btcVault));
      await mockLoan.setDebtAssetAddress(getContractAddress(usdc));
      await addressesProvider.setBitmorLoan(getContractAddress(mockLoan));

      await mockLoan.createActiveLoan(
        user.address,
        user.address,
        parseUnits('1', 8),
        parseUnits('50000', 6),
        12,
        parseUnits('10000', 6)
      );
      await mockLoan.setInsuranceId(user.address, 1);
      await mockLoan.makeLoanOverdue(user.address, 1);

      // Drop bvBTC price by dropping cbBTC price (bvBTC price = cbBTC price x previewRedeem)
      const cbBTCAggregator = aggregators['cbBTC'];
      const currentPrice = await cbBTCAggregator.latestAnswer();
      await cbBTCAggregator.updateAnswer((currentPrice * 50n) / 100n);

      // With the vuln-21 fix, checkTypeOfLiquidation now reads real aToken balance (0.05 bvBTC)
      // instead of stale loanData.collateralAmount (1 bvBTC). At 50% price drop, the real
      // collateral value ($2,500) cannot cover the monthly payment + bonus ($10,500), so the
      // function correctly returns type 1 (full liquidation) instead of type 2.
      const liquidationType = await pool.checkTypeOfLiquidation(user.address);
      expect(liquidationType).to.equal(1n);

      // Restore price
      await cbBTCAggregator.updateAnswer(currentPrice);
    });
  });

  describe('LendingPoolCollateralManager: NOT_ENOUGH_LIQUIDITY', () => {
    const {
      LPCM_NOT_ENOUGH_LIQUIDITY_TO_LIQUIDATE,
    } = ProtocolErrors;

    it('Full liquidation reverts when pool lacks collateral liquidity', async () => {
      const { pool, users, mockLoan, addressesProvider, btcVault, usdc, deployer, configurator, abvBTC, mockBitmorUSDCVault, aggregators } =
        testEnv;
      const user = users[3];

      // Enable bvBTC borrowing so we can drain pool liquidity
      await configurator.enableBorrowingOnReserve(getContractAddress(btcVault), false);

      // Deposit extra USDC for deployer's borrow capacity
      await usdc.connect(deployer.signer).mint(parseUnits('1000000', 6));
      await usdc.connect(deployer.signer).approve(getContractAddress(pool), APPROVAL_AMOUNT_LENDING_POOL);
      await addressesProvider.setUSDCVault(deployer.address);
      await pool.connect(deployer.signer).deposit(getContractAddress(usdc), parseUnits('1000000', 6), deployer.address, '0');

      // Restore vault address before borrow (LendingPool calls IERC4626(vault).asset() during borrow)
      await addressesProvider.setUSDCVault(getContractAddress(mockBitmorUSDCVault));

      // Borrow most bvBTC to drain pool — leave only 0.001 bvBTC
      const availableBvBTC = await btcVault.balanceOf(getContractAddress(abvBTC));
      const borrowAmount = availableBvBTC - parseUnits('0.001', 8);

      await addressesProvider.setBitmorLoan(deployer.address);
      await pool.connect(deployer.signer).borrow(getContractAddress(btcVault), borrowAmount, 2, 0, deployer.address);

      // Setup mockLoan: uninsured, overdue → type=1 when HF < 1
      await mockLoan.setCollateralAssetAddress(getContractAddress(btcVault));
      await mockLoan.setDebtAssetAddress(getContractAddress(usdc));
      await addressesProvider.setBitmorLoan(getContractAddress(mockLoan));

      await mockLoan.createActiveLoan(
        user.address,
        user.address,
        parseUnits('1', 8),
        parseUnits('30000', 6),
        12,
        parseUnits('3000', 6)
      );
      await mockLoan.setInsuranceId(user.address, 0);
      await mockLoan.makeLoanOverdue(user.address, 1);

      // Drop bvBTC price by dropping cbBTC price (bvBTC price = cbBTC price × previewRedeem)
      const cbBTCAggregator = aggregators['cbBTC'];
      const currentPrice = await cbBTCAggregator.latestAnswer();
      await cbBTCAggregator.updateAnswer((currentPrice * 25n) / 100n);

      const userData = await pool.getUserAccountData(user.address);
      expect(userData.healthFactor).to.be.lessThan(parseEther('1'));

      const liquidationType = await pool.checkTypeOfLiquidation(user.address);
      expect(liquidationType).to.equal(1n);

      await usdc.connect(deployer.signer).mint(parseUnits('50000', 6));
      await usdc.connect(deployer.signer).approve(getContractAddress(pool), APPROVAL_AMOUNT_LENDING_POOL);

      // Pass MaxUint256 to satisfy the full debt coverage check (contract caps to actual debt).
      // The NOT_ENOUGH_LIQUIDITY error is hit after the debt coverage check passes.
      await expect(
        pool.liquidationCall(
          getContractAddress(btcVault),
          getContractAddress(usdc),
          user.address,
          MaxUint256,
          false
        )
      ).to.be.revertedWith(LPCM_NOT_ENOUGH_LIQUIDITY_TO_LIQUIDATE);

      // Restore price
      await cbBTCAggregator.updateAnswer(currentPrice);
    });

    it('Micro-liquidation reverts when pool lacks collateral liquidity', async () => {
      const { pool, users, mockLoan, addressesProvider, btcVault, usdc, deployer } = testEnv;
      // Pool is still drained from the previous test
      const user = users[3];

      // Setup mockLoan: insured, overdue → type=2
      await mockLoan.setCollateralAssetAddress(getContractAddress(btcVault));
      await mockLoan.setDebtAssetAddress(getContractAddress(usdc));
      await addressesProvider.setBitmorLoan(getContractAddress(mockLoan));

      await mockLoan.createActiveLoan(
        user.address,
        user.address,
        parseUnits('1', 8),
        parseUnits('30000', 6),
        12,
        parseUnits('3000', 6)
      );
      await mockLoan.setInsuranceId(user.address, 1);
      await mockLoan.makeLoanOverdue(user.address, 1);

      const liquidationType = await pool.checkTypeOfLiquidation(user.address);
      expect(liquidationType).to.equal(2n);

      await usdc.connect(deployer.signer).mint(parseUnits('5000', 6));
      await usdc.connect(deployer.signer).approve(getContractAddress(pool), APPROVAL_AMOUNT_LENDING_POOL);

      const callData = abiCoder.encode(
        ['address', 'address', 'address'],
        [getContractAddress(btcVault), getContractAddress(usdc), user.address]
      );

      await expect(
        pool.connect(deployer.signer).microLiquidationCall(callData)
      ).to.be.revertedWith(LPCM_NOT_ENOUGH_LIQUIDITY_TO_LIQUIDATE);
    });
  });
});
