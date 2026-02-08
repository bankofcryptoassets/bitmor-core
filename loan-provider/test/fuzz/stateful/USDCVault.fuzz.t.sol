// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {USDCStrategyFuzzTestBase} from "../base/USDCStrategyFuzzTestBase.sol";
import {FuzzConstants as FC} from "../helpers/FuzzConstants.sol";

/**
 * @title USDCVaultFuzzTest
 * @author Bitmor Protocol
 * @notice Fuzz tests for USDCVault contract using real vault + strategy
 * @dev Tests USDC vault ERC-4626 compliance with fuzzed parameters.
 *      Uses real `USDCVault` and `USDCStrategy` backed by `MockAaveV3Pool` and `MockBitmorLendingPool`.
 *
 * ## Test Coverage
 * - USDC-01: Deposit/withdraw roundtrip preserves value within slippage
 * - USDC-02: Shares minted proportional to deposit amount
 * - USDC-03: convertToAssets(convertToShares(x)) <= x (no free money)
 * - USDC-04: previewDeposit <= actual deposit shares
 * - USDC-05: previewRedeem <= actual redeem assets
 * - USDC-06: Withdrawal respects maxWithdraw limit
 * - USDC-07: Multiple users can deposit and withdraw independently
 *
 * @custom:audit-category ERC-4626 Compliance, Liquidity Management, Multi-User
 */
contract USDCVaultFuzzTest is USDCStrategyFuzzTestBase {
    // ============ Constants ============

    /// @dev Seed deposit to establish share price before fuzz tests that rely on conversions
    uint256 internal constant SEED_DEPOSIT = 1_000e6;

    // ============ Setup ============

    function setUp() public override {
        super.setUp();
    }

    // ============ Deposit/Withdraw Roundtrip Tests ============

    /**
     * @notice Verifies deposit/withdraw roundtrip preserves value within slippage
     * @dev Tests that depositing and then redeeming returns approximately the same assets.
     *      Uses real vault with strategy deployment (80/20 Aave/BLP split).
     * @param depositSeed Seed for bounded deposit amount
     * @custom:audit-property USDC-01: Deposit/withdraw roundtrip preserves value within slippage
     * @custom:audit-category ERC-4626 Compliance
     * @custom:audit-severity Critical
     */
    function testFuzz_DepositWithdraw_Roundtrip(uint256 depositSeed) public {
        uint256 depositAmount = _boundUsdcAmount(depositSeed);

        // Deposit via helper (mints USDC internally)
        uint256 shares = _depositToVault(depositor, depositAmount);
        assertGt(shares, 0, "should receive shares");

        uint256 assetsExpected = vault.previewRedeem(shares);

        // Redeem all shares
        vm.prank(depositor);
        uint256 assetsReceived = vault.redeem(shares, depositor, depositor);

        // Assert roundtrip: assets received should approximate original deposit
        assertApproxEqRel(
            assetsReceived,
            depositAmount,
            FC.MAX_ROUNDTRIP_SLIPPAGE,
            "USDC roundtrip should preserve value within slippage"
        );

        assertApproxEqRel(
            assetsExpected,
            assetsReceived,
            FC.MAX_ROUNDTRIP_SLIPPAGE,
            "preview redeem should match actual redeem within slippage"
        );
    }

    // ============ Proportionality Tests ============

    /**
     * @notice Verifies shares minted are proportional to deposit amount
     * @dev Tests that the ratio of shares to assets is consistent across different deposits.
     *      Both deposits happen sequentially into the real vault with strategy.
     * @param amount1Seed Seed for first deposit amount
     * @param amount2Seed Seed for second deposit amount
     * @custom:audit-property USDC-02: Shares minted proportional to deposit amount
     * @custom:audit-category ERC-4626 Compliance
     * @custom:audit-severity High
     */
    function testFuzz_Deposit_SharesProportional(uint256 amount1Seed, uint256 amount2Seed) public {
        uint256 amount1 = _boundUsdcAmount(amount1Seed);
        uint256 amount2 = _boundUsdcAmount(amount2Seed);

        // Ensure amounts are different and meaningful
        vm.assume(amount1 != amount2);
        vm.assume(amount1 > FC.MIN_USDC_AMOUNT && amount2 > FC.MIN_USDC_AMOUNT);

        // First deposit
        uint256 shares1 = _depositToVault(depositor, amount1);

        // Second deposit from different user
        uint256 shares2 = _depositToVault(depositor2, amount2);

        // Assert proportionality via cross-multiplication
        uint256 cross1 = shares1 * amount2;
        uint256 cross2 = shares2 * amount1;

        assertApproxEqRel(cross1, cross2, FC.MAX_ROUNDTRIP_SLIPPAGE, "USDC shares should be proportional to deposit");
    }

    // ============ ERC-4626 Invariant Tests ============

    /**
     * @notice Verifies conversion roundtrip does not create free money
     * @dev Tests that convertToAssets(convertToShares(x)) <= x.
     *      Requires an initial deposit so the vault has a non-trivial share price.
     * @param assetsSeed Seed for bounded asset amount
     * @custom:audit-property USDC-03: convertToAssets(convertToShares(x)) <= x
     * @custom:audit-category ERC-4626 Compliance
     * @custom:audit-severity Critical
     */
    function testFuzz_ConvertRoundtrip_NoFreeMoney(uint256 assetsSeed) public {
        // Seed deposit to establish share price
        _depositToVault(depositor, SEED_DEPOSIT);

        uint256 assets = _boundUsdcAmount(assetsSeed);

        uint256 shares = vault.convertToShares(assets);
        uint256 assetsBack = vault.convertToAssets(shares);

        assertLe(assetsBack, assets, "USDC roundtrip conversion should not create free money");
    }

    /**
     * @notice Verifies previewDeposit returns a conservative estimate
     * @dev Tests that actual shares >= previewDeposit (per ERC-4626 spec).
     *      Requires an initial deposit so the vault has a non-trivial share price.
     * @param depositSeed Seed for bounded deposit amount
     * @custom:audit-property USDC-04: previewDeposit <= actual deposit shares
     * @custom:audit-category ERC-4626 Compliance
     * @custom:audit-severity High
     */
    function testFuzz_PreviewDeposit_Conservative(uint256 depositSeed) public {
        // Seed deposit to establish share price
        _depositToVault(depositor, SEED_DEPOSIT);

        uint256 depositAmount = _boundUsdcAmount(depositSeed);

        // Preview before depositing
        uint256 previewShares = vault.previewDeposit(depositAmount);

        // Deposit from a different user
        uint256 actualShares = _depositToVault(depositor2, depositAmount);

        assertGe(actualShares, previewShares, "USDC actual shares should be >= preview");
    }

    /**
     * @notice Verifies previewRedeem returns a conservative estimate
     * @dev Tests that actual assets >= previewRedeem (per ERC-4626 spec)
     * @param depositSeed Seed for bounded deposit amount
     * @custom:audit-property USDC-05: previewRedeem <= actual redeem assets
     * @custom:audit-category ERC-4626 Compliance
     * @custom:audit-severity High
     */
    function testFuzz_PreviewRedeem_Conservative(uint256 depositSeed) public {
        uint256 depositAmount = _boundUsdcAmount(depositSeed);

        // Deposit first
        uint256 shares = _depositToVault(depositor, depositAmount);
        vm.assume(shares > 0);

        // Preview
        uint256 previewAssets = vault.previewRedeem(shares);

        // Redeem
        vm.prank(depositor);
        uint256 actualAssets = vault.redeem(shares, depositor, depositor);

        assertGe(actualAssets, previewAssets, "USDC actual assets should be >= preview");
    }

    // ============ Liquidity Tests ============

    /**
     * @notice Verifies withdrawal at maxWithdraw succeeds
     * @dev Tests that withdrawing exactly `maxWithdraw` does not revert.
     *      The real vault caps `maxWithdraw` at actual strategy liquidity.
     * @param depositSeed Seed for bounded deposit amount
     * @custom:audit-property USDC-06: Withdrawal respects available liquidity
     * @custom:audit-category Liquidity Management
     * @custom:audit-severity High
     */
    function testFuzz_Withdraw_RespectsMaxWithdraw(uint256 depositSeed) public {
        uint256 depositAmount = _boundUsdcAmount(depositSeed);

        // Deposit
        _depositToVault(depositor, depositAmount);

        // Get max withdraw
        uint256 maxWithdraw = vault.maxWithdraw(depositor);
        vm.assume(maxWithdraw > 0);

        // Withdraw at maxWithdraw should succeed
        vm.prank(depositor);
        vault.withdraw(maxWithdraw, depositor, depositor);

        // Verify balance received
        assertGe(mockUSDC.balanceOf(depositor), maxWithdraw, "depositor should receive at least maxWithdraw assets");
    }

    /**
     * @notice Verifies multiple users can deposit and withdraw independently
     * @dev Tests that concurrent user operations maintain correct share accounting.
     *      Uses all three depositor actors from USDCStrategyFuzzTestBase.
     * @param amount1Seed Seed for first user deposit amount
     * @param amount2Seed Seed for second user deposit amount
     * @param amount3Seed Seed for third user deposit amount
     * @custom:audit-property USDC-07: Multiple users can deposit and withdraw
     * @custom:audit-category Multi-User
     * @custom:audit-severity High
     */
    function testFuzz_MultiUser_DepositWithdraw(uint256 amount1Seed, uint256 amount2Seed, uint256 amount3Seed) public {
        uint256 amount1 = _boundUsdcAmount(amount1Seed);
        uint256 amount2 = _boundUsdcAmount(amount2Seed);
        uint256 amount3 = _boundUsdcAmount(amount3Seed);

        // All users deposit
        uint256 shares1 = _depositToVault(depositor, amount1);
        uint256 shares2 = _depositToVault(depositor2, amount2);
        uint256 shares3 = _depositToVault(depositor3, amount3);

        // Verify total supply
        uint256 totalSupply = vault.totalSupply();
        assertEq(totalSupply, shares1 + shares2 + shares3, "total supply should equal sum of shares");

        // All users redeem
        vm.prank(depositor);
        vault.redeem(shares1, depositor, depositor);

        vm.prank(depositor2);
        vault.redeem(shares2, depositor2, depositor2);

        vm.prank(depositor3);
        vault.redeem(shares3, depositor3, depositor3);

        // Verify vault is empty
        assertEq(vault.totalSupply(), 0, "vault should be empty after all withdrawals");
    }
}
