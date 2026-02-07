// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {FuzzTestBase} from "../base/FuzzTestBase.sol";
import {FuzzConstants as FC} from "../helpers/FuzzConstants.sol";
import {MockUSDCVault} from "../../mock/MockUSDCVault.sol";

/**
 * @title USDCVaultFuzzTest
 * @author Bitmor Protocol
 * @notice Fuzz tests for USDCVault contract
 * @dev Tests USDC-specific vault operations with fuzzed parameters
 */
contract USDCVaultFuzzTest is FuzzTestBase {
    MockUSDCVault internal mockUSDCVault;
    address internal user;

    function setUp() public override {
        super.setUp();
        user = makeAddr("user");

        // Deploy MockUSDCVault with mockUSDC as underlying
        mockUSDCVault = new MockUSDCVault(address(mockUSDC), "Bitmor USDC Vault", "bvUSDC", mockUSDC.decimals());
    }

    // ============ Deposit/Withdraw Roundtrip Tests ============

    /**
     * @notice Verifies deposit/withdraw roundtrip preserves value within slippage
     * @dev Tests that depositing and then withdrawing returns approximately the same assets
     * @param depositSeed Seed for bounded deposit amount
     * @custom:audit-property USDC-01: Deposit/withdraw roundtrip preserves value within slippage
     * @custom:audit-category ERC-4626 Compliance
     * @custom:audit-severity Critical
     */
    function testFuzz_DepositWithdraw_Roundtrip(uint256 depositSeed) public {
        uint256 depositAmount = _boundUsdcAmount(depositSeed);

        // Fund user
        _fundUSDCAndApprove(user, address(mockUSDCVault), depositAmount);

        uint256 balanceBefore = mockUSDC.balanceOf(user);

        // Deposit
        vm.prank(user);
        uint256 shares = mockUSDCVault.deposit(depositAmount, user);

        assertGt(shares, 0, "should receive shares");

        uint256 assetsExpected = mockUSDCVault.previewRedeem(shares);

        // Withdraw all shares
        vm.prank(user);
        uint256 assetsReceived = mockUSDCVault.redeem(shares, user, user);

        uint256 balanceAfter = mockUSDC.balanceOf(user);

        // Assert roundtrip within slippage
        assertApproxEqRel(
            balanceAfter,
            balanceBefore,
            FC.MAX_ROUNDTRIP_SLIPPAGE,
            "USDC roundtrip should preserve value within slippage"
        );

        // Assert roundtrip within slippage
        assertApproxEqRel(
            assetsExpected,
            assetsReceived,
            FC.MAX_ROUNDTRIP_SLIPPAGE,
            "USDC roundtrip should preserve value within slippage"
        );
    }

    // ============ Proportionality Tests ============

    /**
     * @notice Verifies shares minted are proportional to deposit amount
     * @dev Tests that the ratio of shares to assets is consistent across different deposits
     * @param amount1Seed Seed for first deposit amount
     * @param amount2Seed Seed for second deposit amount
     * @custom:audit-property USDC-02: Shares minted proportional to deposit amount
     * @custom:audit-category ERC-4626 Compliance
     * @custom:audit-severity High
     */
    function testFuzz_Deposit_SharesProportional(uint256 amount1Seed, uint256 amount2Seed) public {
        uint256 amount1 = _boundUsdcAmount(amount1Seed);
        uint256 amount2 = _boundUsdcAmount(amount2Seed);

        // Ensure amounts are different
        vm.assume(amount1 != amount2);
        vm.assume(amount1 > FC.MIN_USDC_AMOUNT && amount2 > FC.MIN_USDC_AMOUNT);

        // First deposit
        _fundUSDCAndApprove(user, address(mockUSDCVault), amount1);
        vm.prank(user);
        uint256 shares1 = mockUSDCVault.deposit(amount1, user);

        // Second deposit from different user
        address user2 = makeAddr("user2");
        _fundUSDCAndApprove(user2, address(mockUSDCVault), amount2);
        vm.prank(user2);
        uint256 shares2 = mockUSDCVault.deposit(amount2, user2);

        // Assert proportionality
        uint256 cross1 = shares1 * amount2;
        uint256 cross2 = shares2 * amount1;

        assertApproxEqRel(cross1, cross2, FC.MAX_ROUNDTRIP_SLIPPAGE, "USDC shares should be proportional to deposit");
    }

    // ============ ERC-4626 Invariant Tests ============

    /**
     * @notice Verifies conversion roundtrip does not create free money
     * @dev Tests that convertToAssets(convertToShares(x)) <= x
     * @param assetsSeed Seed for bounded asset amount
     * @custom:audit-property USDC-03: convertToAssets(convertToShares(x)) <= x
     * @custom:audit-category ERC-4626 Compliance
     * @custom:audit-severity Critical
     */
    function testFuzz_ConvertRoundtrip_NoFreeMoney(uint256 assetsSeed) public view {
        uint256 assets = _boundUsdcAmount(assetsSeed);

        uint256 shares = mockUSDCVault.convertToShares(assets);
        uint256 assetsBack = mockUSDCVault.convertToAssets(shares);

        assertLe(assetsBack, assets, "USDC roundtrip conversion should not create free money");
    }

    /**
     * @notice Verifies previewDeposit returns a conservative estimate
     * @dev Tests that actual shares >= previewDeposit (per ERC-4626 spec)
     * @param depositSeed Seed for bounded deposit amount
     * @custom:audit-property USDC-04: previewDeposit <= actual deposit shares
     * @custom:audit-category ERC-4626 Compliance
     * @custom:audit-severity High
     */
    function testFuzz_PreviewDeposit_Conservative(uint256 depositSeed) public {
        uint256 depositAmount = _boundUsdcAmount(depositSeed);

        // Preview
        uint256 previewShares = mockUSDCVault.previewDeposit(depositAmount);

        // Fund and deposit
        _fundUSDCAndApprove(user, address(mockUSDCVault), depositAmount);
        vm.prank(user);
        uint256 actualShares = mockUSDCVault.deposit(depositAmount, user);

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

        // Setup: deposit first
        _fundUSDCAndApprove(user, address(mockUSDCVault), depositAmount);
        vm.prank(user);
        uint256 shares = mockUSDCVault.deposit(depositAmount, user);

        vm.assume(shares > 0);

        // Preview
        uint256 previewAssets = mockUSDCVault.previewRedeem(shares);

        // Redeem
        vm.prank(user);
        uint256 actualAssets = mockUSDCVault.redeem(shares, user, user);

        assertGe(actualAssets, previewAssets, "USDC actual assets should be >= preview");
    }

    // ============ Liquidity Tests ============

    /**
     * @notice Verifies withdrawal respects maxWithdraw limit
     * @dev Tests that attempting to withdraw more than maxWithdraw reverts appropriately
     * @param depositSeed Seed for bounded deposit amount
     * @custom:audit-property USDC-06: Withdrawal respects available liquidity
     * @custom:audit-category Liquidity Management
     * @custom:audit-severity High
     */
    function testFuzz_Withdraw_RespectsMaxWithdraw(uint256 depositSeed) public {
        uint256 depositAmount = _boundUsdcAmount(depositSeed);

        // Setup: deposit
        _fundUSDCAndApprove(user, address(mockUSDCVault), depositAmount);
        vm.prank(user);
        mockUSDCVault.deposit(depositAmount, user);

        // Get max withdraw
        uint256 maxWithdraw = mockUSDCVault.maxWithdraw(user);

        // Attempting to withdraw more than max should revert
        if (maxWithdraw < depositAmount) {
            vm.expectRevert();
            vm.prank(user);
            mockUSDCVault.withdraw(depositAmount, user, user);
        }
    }

    /**
     * @notice Verifies multiple users can deposit and withdraw independently
     * @dev Tests that concurrent user operations maintain correct balances
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

        address user2 = makeAddr("user2");
        address user3 = makeAddr("user3");

        // All users deposit
        _fundUSDCAndApprove(user, address(mockUSDCVault), amount1);
        vm.prank(user);
        uint256 shares1 = mockUSDCVault.deposit(amount1, user);

        _fundUSDCAndApprove(user2, address(mockUSDCVault), amount2);
        vm.prank(user2);
        uint256 shares2 = mockUSDCVault.deposit(amount2, user2);

        _fundUSDCAndApprove(user3, address(mockUSDCVault), amount3);
        vm.prank(user3);
        uint256 shares3 = mockUSDCVault.deposit(amount3, user3);

        // Verify total supply
        uint256 totalSupply = mockUSDCVault.totalSupply();
        assertEq(totalSupply, shares1 + shares2 + shares3, "total supply should equal sum of shares");

        // All users withdraw
        vm.prank(user);
        mockUSDCVault.redeem(shares1, user, user);

        vm.prank(user2);
        mockUSDCVault.redeem(shares2, user2, user2);

        vm.prank(user3);
        mockUSDCVault.redeem(shares3, user3, user3);

        // Verify vault is empty
        assertEq(mockUSDCVault.totalSupply(), 0, "vault should be empty after all withdrawals");
    }
}
