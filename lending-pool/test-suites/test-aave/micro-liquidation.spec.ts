/**
 * Tests for micro-liquidation functionality.
 */

import { makeSuite } from './helpers/make-suite.js';
import type { TestEnv } from './helpers/make-suite.js';
import { APPROVAL_AMOUNT_LENDING_POOL } from '../../helpers/constants.js';
import { convertToCurrencyDecimals, getContractAddress } from '../../helpers/contracts-helpers.js';
import { ProtocolErrors } from '../../helpers/types.js';
import { parseEther, parseUnits, AbiCoder } from 'ethers';
import BigNumber from 'bignumber.js';
import chai from 'chai';

const { expect } = chai;

makeSuite('Micro-Liquidation', (testEnv: TestEnv) => {
  const abiCoder = new AbiCoder();

  /**
   * Setup a user with collateral and debt for liquidation testing
   */
  async function setupUserWithDebt(
    testEnv: TestEnv,
    userIndex: number,
    collateralAmount: string,
    borrowAmount: string
  ) {
    const { users, pool, usdc, cbBTC, addressesProvider, mockBitmorUSDCVault, deployer } = testEnv;
    const user = users[userIndex];

    // First, ensure there's USDC liquidity in the pool (deployer acts as liquidity provider)
    const liquidityAmount = await convertToCurrencyDecimals(getContractAddress(usdc), '100000');
    await usdc.connect(deployer.signer).mint(liquidityAmount);
    await usdc.connect(deployer.signer).approve(getContractAddress(pool), APPROVAL_AMOUNT_LENDING_POOL);
    await addressesProvider.setUSDCVault(deployer.address);
    await pool.connect(deployer.signer).deposit(getContractAddress(usdc), liquidityAmount, deployer.address, '0');

    // Mint and deposit cbBTC as collateral
    const cbBTCAmount = await convertToCurrencyDecimals(getContractAddress(cbBTC), collateralAmount);
    await cbBTC.connect(user.signer).mint(cbBTCAmount);
    await cbBTC.connect(user.signer).approve(getContractAddress(pool), APPROVAL_AMOUNT_LENDING_POOL);

    // Set user as vault to bypass vault check for deposit
    await addressesProvider.setUSDCVault(user.address);
    await pool.connect(user.signer).deposit(getContractAddress(cbBTC), cbBTCAmount, user.address, '0');

    // Borrow USDC
    const usdcAmount = await convertToCurrencyDecimals(getContractAddress(usdc), borrowAmount);
    await addressesProvider.setBitmorLoan(user.address);
    await addressesProvider.setUSDCVault(mockBitmorUSDCVault.target);
    await pool.connect(user.signer).borrow(getContractAddress(usdc), usdcAmount, 2, 0, user.address);

    return { user, cbBTCAmount, usdcAmount };
  }

  describe('checkTypeOfLiquidation', () => {
    it('Returns 0 when loan status is not Active', async () => {
      const { pool, users, mockLoan, addressesProvider, cbBTC, usdc } = testEnv;
      const user = users[0];

      // Setup MockLoan with Completed status
      await mockLoan.setCollateralAssetAddress(getContractAddress(cbBTC));
      await mockLoan.setDebtAssetAddress(getContractAddress(usdc));
      await addressesProvider.setBitmorLoan(getContractAddress(mockLoan));

      // Create a loan with Completed status
      await mockLoan.createActiveLoan(
        user.address,
        user.address,
        parseUnits('1', 8), // 1 cbBTC
        parseUnits('50000', 6), // 50k USDC
        12, // 12 months
        parseUnits('4500', 6) // ~4500 USDC monthly
      );
      await mockLoan.setLoanStatus(user.address, 1); // 1 = Completed

      const liquidationType = await pool.checkTypeOfLiquidation(user.address);
      expect(liquidationType).to.equal(0n);
    });

    it('Returns 0 when loan is not overdue', async () => {
      const { pool, users, mockLoan, addressesProvider, cbBTC, usdc } = testEnv;
      const user = users[1];

      // Setup MockLoan
      await mockLoan.setCollateralAssetAddress(getContractAddress(cbBTC));
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
      const { pool, users, mockLoan, addressesProvider, cbBTC, usdc, oracle } = testEnv;
      const user = users[2];

      // Setup user with collateral and debt
      await setupUserWithDebt(testEnv, 2, '1', '45000');

      // Setup MockLoan with uninsured loan
      await mockLoan.setCollateralAssetAddress(getContractAddress(cbBTC));
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

      // Drop cbBTC price significantly to make HF < 1
      const currentPrice = await oracle.getAssetPrice(getContractAddress(cbBTC));
      await oracle.setAssetPrice(
        getContractAddress(cbBTC),
        new BigNumber(currentPrice.toString()).multipliedBy(0.3).toFixed(0)
      );

      const liquidationType = await pool.checkTypeOfLiquidation(user.address);
      expect(liquidationType).to.equal(1n); // Full liquidation

      // Restore price
      await oracle.setAssetPrice(getContractAddress(cbBTC), currentPrice);
    });

    it('Returns 2 (micro-liquidation) when loan is overdue with sufficient collateral', async () => {
      const { pool, users, mockLoan, addressesProvider, cbBTC, usdc } = testEnv;
      const user = users[3];

      // Setup user with collateral and debt
      await setupUserWithDebt(testEnv, 3, '1', '30000');

      // Setup MockLoan
      await mockLoan.setCollateralAssetAddress(getContractAddress(cbBTC));
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
      const { pool, users, mockLoan, addressesProvider, cbBTC, usdc, deployer } = testEnv;
      const borrower = users[4];
      const liquidator = deployer;

      // Setup borrower with collateral and debt
      await setupUserWithDebt(testEnv, 4, '1', '25000');

      // Setup MockLoan
      await mockLoan.setCollateralAssetAddress(getContractAddress(cbBTC));
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

      // Encode micro-liquidation call data
      const callData = abiCoder.encode(
        ['address', 'address', 'address'],
        [getContractAddress(cbBTC), getContractAddress(usdc), borrower.address]
      );

      // Execute micro-liquidation (should succeed without reverting)
      await pool.connect(liquidator.signer).microLiquidationCall(callData);

      // Verify MockLoan was updated
      const microLiqCount = await mockLoan.microLiquidationCount(borrower.address);
      expect(microLiqCount).to.equal(1n);
    });

    it('Reverts micro-liquidation when loan is not overdue', async () => {
      const { pool, users, mockLoan, addressesProvider, cbBTC, usdc, deployer } = testEnv;
      const borrower = users[5];
      const liquidator = deployer;

      // Setup borrower with collateral and debt
      await setupUserWithDebt(testEnv, 5, '1', '25000');

      // Setup MockLoan (NOT overdue - fresh loan)
      await mockLoan.setCollateralAssetAddress(getContractAddress(cbBTC));
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
        [getContractAddress(cbBTC), getContractAddress(usdc), borrower.address]
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

    it('Triggers full liquidation update when duration becomes 0 after micro-liquidation', async () => {
      const { pool, users, mockLoan, addressesProvider, cbBTC, usdc, deployer } = testEnv;
      const borrower = users[6];
      const liquidator = deployer;

      // Setup borrower with collateral and debt
      await setupUserWithDebt(testEnv, 6, '1', '5000');

      // Setup MockLoan with duration = 1 (last month)
      await mockLoan.setCollateralAssetAddress(getContractAddress(cbBTC));
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

      // Encode call data
      const callData = abiCoder.encode(
        ['address', 'address', 'address'],
        [getContractAddress(cbBTC), getContractAddress(usdc), borrower.address]
      );

      // Execute micro-liquidation
      await pool.connect(liquidator.signer).microLiquidationCall(callData);

      // When duration was 1, after micro-liq it becomes 0, triggering full liquidation update
      const fullLiqCount = await mockLoan.fullLiquidationCount(borrower.address);
      expect(fullLiqCount).to.equal(1n);
    });
  });

  describe('validateMicroLiquidationCall edge cases', () => {
    const {
      LPCM_COLLATERAL_CANNOT_BE_LIQUIDATED,
      LPCM_SPECIFIED_CURRENCY_NOT_BORROWED_BY_USER,
    } = ProtocolErrors;

    it('Reverts micro-liquidation when collateral is not enabled for user', async () => {
      const { pool, users, mockLoan, addressesProvider, cbBTC, usdc, deployer } = testEnv;
      // Use user[0] who has NO pool position (never deposited/borrowed)
      // checkTypeOfLiquidation still returns 2 because it reads from mockLoan data
      const user = users[0];

      await mockLoan.setCollateralAssetAddress(getContractAddress(cbBTC));
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

      // Pass USDC as collateral - user never deposited USDC, so it's not enabled as collateral
      const callData = abiCoder.encode(
        ['address', 'address', 'address'],
        [getContractAddress(usdc), getContractAddress(usdc), user.address]
      );

      await expect(
        pool.connect(deployer.signer).microLiquidationCall(callData)
      ).to.be.revertedWith(LPCM_COLLATERAL_CANNOT_BE_LIQUIDATED);
    });

    it('Reverts micro-liquidation when user has no debt in specified currency', async () => {
      const { pool, users, mockLoan, addressesProvider, cbBTC, usdc, deployer } = testEnv;
      // Reuse user[2] who has cbBTC as collateral and USDC debt (no cbBTC debt)
      const user = users[2];

      await mockLoan.setCollateralAssetAddress(getContractAddress(cbBTC));
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

      // Pass cbBTC as BOTH collateral and debt - user has cbBTC as collateral
      // but has no cbBTC debt (they only borrowed USDC)
      const callData = abiCoder.encode(
        ['address', 'address', 'address'],
        [getContractAddress(cbBTC), getContractAddress(cbBTC), user.address]
      );

      await expect(
        pool.connect(deployer.signer).microLiquidationCall(callData)
      ).to.be.revertedWith(LPCM_SPECIFIED_CURRENCY_NOT_BORROWED_BY_USER);
    });
  });

  describe('LendingPoolCollateralManager: collateral capping in micro-liquidation', () => {
    it('Caps debt and consumes all collateral when payment exceeds collateral value', async () => {
      const { pool, users, mockLoan, addressesProvider, cbBTC, usdc, oracle, deployer, acbBTC } = testEnv;
      const user = users[1];

      // Set up user[1] with small cbBTC collateral (0.05 cbBTC ≈ $5000) and USDC debt
      await setupUserWithDebt(testEnv, 1, '0.05', '4000');

      // MockLoan: 1 cbBTC in loan data (sufficient for type=2 check), insured, large monthly payment
      await mockLoan.setCollateralAssetAddress(getContractAddress(cbBTC));
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

      // Drop cbBTC price to 50% so collateral can't cover monthly payment + bonus
      const currentPrice = await oracle.getAssetPrice(getContractAddress(cbBTC));
      await oracle.setAssetPrice(
        getContractAddress(cbBTC),
        new BigNumber(currentPrice.toString()).multipliedBy(0.5).toFixed(0)
      );

      const liquidationType = await pool.checkTypeOfLiquidation(user.address);
      expect(liquidationType).to.equal(2n);

      const collateralBefore = await acbBTC.balanceOf(user.address);
      expect(collateralBefore).to.be.greaterThan(0n);

      // Liquidator prepares USDC
      await usdc.connect(deployer.signer).mint(parseUnits('10000', 6));
      await usdc.connect(deployer.signer).approve(getContractAddress(pool), APPROVAL_AMOUNT_LENDING_POOL);

      const callData = abiCoder.encode(
        ['address', 'address', 'address'],
        [getContractAddress(cbBTC), getContractAddress(usdc), user.address]
      );
      await pool.connect(deployer.signer).microLiquidationCall(callData);

      // All collateral consumed — covers lines 304-306 (debt capped) and 359-362 (collateral disabled)
      const collateralAfter = await acbBTC.balanceOf(user.address);
      expect(collateralAfter).to.equal(0n);

      await oracle.setAssetPrice(getContractAddress(cbBTC), currentPrice);
    });
  });

  describe('LendingPoolCollateralManager: NOT_ENOUGH_LIQUIDITY', () => {
    const {
      LPCM_NOT_ENOUGH_LIQUIDITY_TO_LIQUIDATE,
    } = ProtocolErrors;

    it('Full liquidation reverts when pool lacks collateral liquidity', async () => {
      const { pool, users, mockLoan, addressesProvider, cbBTC, usdc, oracle, deployer, configurator, acbBTC, mockBitmorUSDCVault } =
        testEnv;
      const user = users[3];

      // Enable cbBTC borrowing so we can drain pool liquidity
      await configurator.enableBorrowingOnReserve(getContractAddress(cbBTC), false);

      // Deposit extra USDC for deployer's borrow capacity
      await usdc.connect(deployer.signer).mint(parseUnits('1000000', 6));
      await usdc.connect(deployer.signer).approve(getContractAddress(pool), APPROVAL_AMOUNT_LENDING_POOL);
      await addressesProvider.setUSDCVault(deployer.address);
      await pool.connect(deployer.signer).deposit(getContractAddress(usdc), parseUnits('1000000', 6), deployer.address, '0');

      // Restore vault address before borrow (LendingPool calls IERC4626(vault).asset() during borrow)
      await addressesProvider.setUSDCVault(getContractAddress(mockBitmorUSDCVault));

      // Borrow most cbBTC to drain pool — leave only 0.001 cbBTC
      const availableCbBTC = await cbBTC.balanceOf(getContractAddress(acbBTC));
      const borrowAmount = availableCbBTC - parseUnits('0.001', 8);

      await addressesProvider.setBitmorLoan(deployer.address);
      await pool.connect(deployer.signer).borrow(getContractAddress(cbBTC), borrowAmount, 2, 0, deployer.address);

      // Setup mockLoan: uninsured, overdue → type=1 when HF < 1
      await mockLoan.setCollateralAssetAddress(getContractAddress(cbBTC));
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

      // Drop cbBTC price to 25% to make HF < 1
      const currentPrice = await oracle.getAssetPrice(getContractAddress(cbBTC));
      await oracle.setAssetPrice(
        getContractAddress(cbBTC),
        new BigNumber(currentPrice.toString()).multipliedBy(0.25).toFixed(0)
      );

      const userData = await pool.getUserAccountData(user.address);
      expect(userData.healthFactor).to.be.lessThan(parseEther('1'));

      const liquidationType = await pool.checkTypeOfLiquidation(user.address);
      expect(liquidationType).to.equal(1n);

      await usdc.connect(deployer.signer).mint(parseUnits('50000', 6));
      await usdc.connect(deployer.signer).approve(getContractAddress(pool), APPROVAL_AMOUNT_LENDING_POOL);

      await expect(
        pool.liquidationCall(
          getContractAddress(cbBTC),
          getContractAddress(usdc),
          user.address,
          parseUnits('30000', 6),
          false
        )
      ).to.be.revertedWith(LPCM_NOT_ENOUGH_LIQUIDITY_TO_LIQUIDATE);

      await oracle.setAssetPrice(getContractAddress(cbBTC), currentPrice);
    });

    it('Micro-liquidation reverts when pool lacks collateral liquidity', async () => {
      const { pool, users, mockLoan, addressesProvider, cbBTC, usdc, deployer } = testEnv;
      // Pool is still drained from the previous test
      const user = users[3];

      // Setup mockLoan: insured, overdue → type=2
      await mockLoan.setCollateralAssetAddress(getContractAddress(cbBTC));
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
        [getContractAddress(cbBTC), getContractAddress(usdc), user.address]
      );

      await expect(
        pool.connect(deployer.signer).microLiquidationCall(callData)
      ).to.be.revertedWith(LPCM_NOT_ENOUGH_LIQUIDITY_TO_LIQUIDATE);
    });
  });
});
