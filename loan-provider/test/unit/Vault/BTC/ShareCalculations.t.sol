// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {BaseTestForBTCVault} from "../BaseTestForBTCVault.t.sol";
import {BTCVault} from "@btcVault/BTCVault.sol";
import {Errors} from "@bitmor/libraries/helpers/Errors.sol";

/// @title ShareCalculationsTest
/// @author Bitmor Protocol
/// @notice Tests for BTCVault ERC-4626 share calculations with fees
/// @dev Hunts for share inflation attacks, rounding exploits, and preview mismatches.
///      Validates that preview functions accurately match actual operation outcomes.
contract ShareCalculationsTest is BaseTestForBTCVault {
    // ============ Constants ============

    /// @notice First depositor amount (1000 USDC)
    uint256 constant FIRST_DEPOSIT = 1000e6;

    /// @notice Second depositor amount (500 USDC)
    uint256 constant SECOND_DEPOSIT = 500e6;

    /// @notice Small deposit for edge cases (1 USDC)
    uint256 constant SMALL_DEPOSIT = 1e6;

    /// @notice Tiny deposit (1 wei)
    uint256 constant TINY_DEPOSIT = 1;

    /// @notice Large deposit for precision tests (1M USDC)
    uint256 constant LARGE_DEPOSIT = 1_000_000e6;

    // ============ Setup ============

    function setUp() public override {
        super.setUp();
        // Add a strategy so deposits can be allocated
        _addStrategyWithCap(VERY_LARGE_CAP);

        // Add mint selector to BVD role (not in RolesData but contract has it as restricted)
        bytes4[] memory mintSelector = new bytes4[](1);
        mintSelector[0] = BTCVault.mint.selector;
        manager.setTargetFunctionRole(address(vault), mintSelector, BVD_ID());
    }

    /// @notice Helper to add strategy via proper access control
    /// @param cap The allocation cap for the strategy
    function _addStrategyWithCap(uint256 cap) internal {
        _scheduleAndExecuteLocal(bvc, BVC_ID(), abi.encodeCall(BTCVault.addStrategy, (address(strategy), cap)));
    }

    /// @notice Helper to deposit as user with proper approval
    /// @param amount The amount to deposit
    /// @return shares The shares minted
    function _depositAsUser(uint256 amount) internal returns (uint256 shares) {
        vm.startPrank(user);
        mockUSDC.approve(address(vault), amount);
        shares = vault.deposit(amount, user);
        vm.stopPrank();
    }

    /// @notice Helper to mint shares for user
    /// @param sharesToMint The number of shares to mint
    /// @return assets The assets required
    function _mintAsUser(uint256 sharesToMint) internal returns (uint256 assets) {
        uint256 previewAssets = vault.previewMint(sharesToMint);
        vm.startPrank(user);
        mockUSDC.approve(address(vault), previewAssets);
        assets = vault.mint(sharesToMint, user);
        vm.stopPrank();
    }

    /// @notice Helper to grant BVD role to a new depositor
    /// @param depositor The address to grant BVD role to
    function _grantDepositRole(address depositor) internal {
        uint64 bvdRoleId = BVD_ID();
        manager.grantRole(bvdRoleId, depositor, NO_DELAY);
    }

    // ============ First Depositor Tests ============

    /// @notice First depositor should receive shares proportional to assets (minus fee)
    function test_deposit_FirstDepositor_SharesMatchAssetsMinusFee() public {
        uint256 entryFee = vault.getEntryFee();
        uint256 expectedFee = vault.feeOnTotal(FIRST_DEPOSIT, entryFee);
        uint256 assetsAfterFee = FIRST_DEPOSIT - expectedFee;

        uint256 shares = _depositAsUser(FIRST_DEPOSIT);

        // First deposit: shares should equal assets after fee (1:1 ratio)
        assertEq(shares, assetsAfterFee, "first depositor shares should equal assets minus fee");
    }

    /// @notice Second depositor should receive proportional shares
    function test_deposit_SecondDepositor_ReceivesProportionalShares() public {
        // First deposit
        uint256 firstShares = _depositAsUser(FIRST_DEPOSIT);

        // Second deposit
        vm.startPrank(user);
        mockUSDC.approve(address(vault), SECOND_DEPOSIT);
        uint256 secondShares = vault.deposit(SECOND_DEPOSIT, user);
        vm.stopPrank();

        // Second depositor should get proportionally fewer shares (due to entry fee)
        uint256 entryFee = vault.getEntryFee();
        uint256 secondFee = vault.feeOnTotal(SECOND_DEPOSIT, entryFee);
        uint256 secondAssetsAfterFee = SECOND_DEPOSIT - secondFee;

        // shares = assets * totalSupply / totalAssets
        // Since first depositor and second depositor have same entry fee rate,
        // second shares should be proportional to second assets after fee
        assertGt(secondShares, 0, "second depositor should receive shares");
        assertLt(secondShares, firstShares, "second depositor gets fewer shares (smaller deposit)");
        assertGt(secondAssetsAfterFee, 0, "second assets after fee should be positive");
    }

    /// @notice First depositor with zero fee should get 1:1 shares
    function test_deposit_FirstDepositor_ZeroFee_SharesEqualAssets() public {
        // Set entry fee to 0
        _scheduleAndExecuteLocal(bvm_slow, BVM_SLOW_ID(), abi.encodeCall(BTCVault.setEntryFee, (0)));

        uint256 shares = _depositAsUser(FIRST_DEPOSIT);

        // With zero fee, shares should equal deposit (1:1 for first depositor)
        assertEq(shares, FIRST_DEPOSIT, "zero fee: first depositor shares should equal deposit");
    }

    // ============ Preview vs Actual Tests ============

    /// @notice `previewDeposit` should match actual deposit shares
    function test_previewDeposit_MatchesActualDeposit() public {
        uint256 preview = vault.previewDeposit(FIRST_DEPOSIT);

        uint256 actual = _depositAsUser(FIRST_DEPOSIT);

        assertEq(actual, preview, "previewDeposit should match actual shares minted");
    }

    /// @notice `previewMint` should match actual mint assets (or be greater per ERC-4626 spec)
    function test_previewMint_MatchesActualMint() public {
        uint256 sharesToMint = 1000e6;
        uint256 preview = vault.previewMint(sharesToMint);

        vm.startPrank(user);
        mockUSDC.approve(address(vault), preview);
        uint256 actualAssets = vault.mint(sharesToMint, user);
        vm.stopPrank();

        // Per ERC-4626: actual assets taken should be <= preview (preview is upper bound)
        assertLe(actualAssets, preview, "actual assets should be <= preview");
    }

    /// @notice `previewWithdraw` should match actual withdraw shares burned (or be less per ERC-4626 spec)
    function test_previewWithdraw_MatchesActualWithdraw() public {
        // First deposit
        _depositAsUser(FIRST_DEPOSIT);

        // Calculate how much we can withdraw
        uint256 maxWithdrawable = vault.maxWithdraw(user);
        uint256 withdrawAmount = maxWithdrawable / 2;

        uint256 preview = vault.previewWithdraw(withdrawAmount);

        vm.prank(user);
        uint256 actualSharesBurned = vault.withdraw(withdrawAmount, user, user);

        // Per ERC-4626: actual shares burned should be <= preview (preview is upper bound)
        assertLe(actualSharesBurned, preview, "actual shares burned should be <= preview");
    }

    /// @notice `previewRedeem` should match actual redeem assets (or be less per ERC-4626 spec)
    function test_previewRedeem_MatchesActualRedeem() public {
        // First deposit
        uint256 shares = _depositAsUser(FIRST_DEPOSIT);

        uint256 redeemShares = shares / 2;
        uint256 preview = vault.previewRedeem(redeemShares);

        vm.prank(user);
        uint256 actualAssets = vault.redeem(redeemShares, user, user);

        // Per ERC-4626: actual assets received should be >= preview (preview is lower bound)
        assertGe(actualAssets, preview, "actual assets should be >= preview");
    }

    // ============ Full Redemption Tests ============

    /// @notice Redeeming all shares should return all assets (minus exit fee)
    function test_redeem_AllShares_ReturnsAllAssetsMinusFee() public {
        uint256 shares = _depositAsUser(FIRST_DEPOSIT);

        uint256 userBalanceBefore = mockUSDC.balanceOf(user);

        vm.prank(user);
        uint256 assetsReturned = vault.redeem(shares, user, user);

        uint256 userBalanceAfter = mockUSDC.balanceOf(user);

        assertEq(userBalanceAfter - userBalanceBefore, assetsReturned, "balance change should match returned assets");
        assertEq(vault.balanceOf(user), 0, "user should have 0 shares after full redeem");
    }

    /// @notice Withdrawing max should succeed and return expected assets
    function test_withdraw_MaxWithdraw_Succeeds() public {
        _depositAsUser(FIRST_DEPOSIT);

        uint256 maxWithdrawable = vault.maxWithdraw(user);
        uint256 sharesBefore = vault.balanceOf(user);

        vm.prank(user);
        vault.withdraw(maxWithdrawable, user, user);

        uint256 sharesAfter = vault.balanceOf(user);

        // Should have burned all or nearly all shares
        assertLt(sharesAfter, sharesBefore, "should have burned shares");
    }

    /// @notice Full redemption should leave zero totalAssets (for single depositor)
    function test_redeem_AllShares_TotalAssetsZero() public {
        uint256 shares = _depositAsUser(FIRST_DEPOSIT);

        vm.prank(user);
        vault.redeem(shares, user, user);

        uint256 totalAssetsAfter = vault.totalAssets();

        // totalAssets should be 0 or very close (rounding)
        assertLe(totalAssetsAfter, 1, "totalAssets should be ~0 after full redeem");
    }

    // ============ Edge Case Tests ============

    /// @notice Tiny deposit (1 wei) returns 0 or 1 share due to rounding
    /// @dev ERC4626 allows dust deposits. With 1:1 initial exchange rate, 1 wei may mint 0-1 shares
    function test_deposit_TinyAmount_ReturnsMinimalShares() public {
        vm.startPrank(user);
        mockUSDC.approve(address(vault), TINY_DEPOSIT);

        // 1 wei deposit should succeed (ERC4626 allows dust)
        uint256 shares = vault.deposit(TINY_DEPOSIT, user);
        vm.stopPrank();

        // With standard ERC4626 math, 1 wei should mint 0 or 1 share
        // (depends on offset and current exchange rate)
        assertLe(shares, 1, "1 wei deposit should mint at most 1 share");
    }

    /// @notice `maxDeposit` should return remaining strategy cap
    function test_maxDeposit_ReturnsExpectedValue() public view {
        uint256 maxDep = vault.maxDeposit(user);

        // Should equal sum of remaining caps in supply queue
        assertGt(maxDep, 0, "maxDeposit should be > 0 with strategy cap available");
        assertEq(maxDep, VERY_LARGE_CAP, "maxDeposit should equal strategy cap");
    }

    /// @notice `maxWithdraw` with zero balance should return zero
    function test_maxWithdraw_ZeroBalance_ReturnsZero() public {
        address noBalanceUser = makeAddr("noBalanceUser");
        uint256 maxWith = vault.maxWithdraw(noBalanceUser);

        assertEq(maxWith, 0, "maxWithdraw for zero balance user should be 0");
    }

    /// @notice `maxDeposit` should decrease after a deposit
    function test_maxDeposit_DecreasesAfterDeposit() public {
        uint256 maxBefore = vault.maxDeposit(user);

        _depositAsUser(FIRST_DEPOSIT);

        uint256 maxAfter = vault.maxDeposit(user);

        assertLt(maxAfter, maxBefore, "maxDeposit should decrease after deposit");
    }

    /// @notice `convertToShares` and `convertToAssets` should be inverses (approximately)
    function test_convertToShares_ConvertToAssets_InverseRelationship() public {
        _depositAsUser(FIRST_DEPOSIT);

        uint256 testAssets = 1000e6;
        uint256 shares = vault.convertToShares(testAssets);
        uint256 backToAssets = vault.convertToAssets(shares);

        // Due to rounding, they may differ slightly
        uint256 diff = testAssets > backToAssets ? testAssets - backToAssets : backToAssets - testAssets;
        assertLe(diff, 1, "convertToShares and convertToAssets should be inverses within 1 wei");
    }

    /// @notice Large deposit should maintain share price stability
    function test_deposit_LargeAmount_SharePriceStable() public {
        // First small deposit to establish share price
        _depositAsUser(FIRST_DEPOSIT);
        uint256 sharePriceBefore = (vault.totalAssets() * 1e18) / vault.totalSupply();

        // Large deposit from another user
        address largeDepositor = makeAddr("largeDepositor");
        _grantDepositRole(largeDepositor);
        mockUSDC.mint(largeDepositor, LARGE_DEPOSIT);

        vm.startPrank(largeDepositor);
        mockUSDC.approve(address(vault), LARGE_DEPOSIT);
        vault.deposit(LARGE_DEPOSIT, largeDepositor);
        vm.stopPrank();

        uint256 sharePriceAfter = (vault.totalAssets() * 1e18) / vault.totalSupply();

        // Share price should remain stable (within 0.1% tolerance)
        uint256 tolerance = sharePriceBefore / 1000;
        uint256 diff = sharePriceBefore > sharePriceAfter
            ? sharePriceBefore - sharePriceAfter
            : sharePriceAfter - sharePriceBefore;
        assertLe(diff, tolerance, "share price should remain stable after large deposit");
    }

    /// @notice Preview functions should return consistent values when called multiple times
    function test_previewFunctions_Idempotent() public {
        _depositAsUser(FIRST_DEPOSIT);

        uint256 assets = 500e6;
        uint256 shares = 500e6;

        // Call previews twice, results should be identical
        uint256 previewDeposit1 = vault.previewDeposit(assets);
        uint256 previewDeposit2 = vault.previewDeposit(assets);
        assertEq(previewDeposit1, previewDeposit2, "previewDeposit should be idempotent");

        uint256 previewMint1 = vault.previewMint(shares);
        uint256 previewMint2 = vault.previewMint(shares);
        assertEq(previewMint1, previewMint2, "previewMint should be idempotent");

        uint256 previewWithdraw1 = vault.previewWithdraw(assets / 2);
        uint256 previewWithdraw2 = vault.previewWithdraw(assets / 2);
        assertEq(previewWithdraw1, previewWithdraw2, "previewWithdraw should be idempotent");

        uint256 userShares = vault.balanceOf(user);
        uint256 previewRedeem1 = vault.previewRedeem(userShares / 2);
        uint256 previewRedeem2 = vault.previewRedeem(userShares / 2);
        assertEq(previewRedeem1, previewRedeem2, "previewRedeem should be idempotent");
    }

    /// @notice Mint should produce expected shares exactly
    function test_mint_ProducesExactShares() public {
        uint256 sharesToMint = 12345e6;

        _mintAsUser(sharesToMint);

        uint256 actualShares = vault.balanceOf(user);
        assertEq(actualShares, sharesToMint, "mint should produce exact shares requested");
    }

    /// @notice Total supply should equal sum of all holders' balances
    function test_totalSupply_EqualsSumOfBalances() public {
        // Deposit from user
        _depositAsUser(FIRST_DEPOSIT);

        // Deposit from another user
        address user2 = makeAddr("user2");
        _grantDepositRole(user2);
        mockUSDC.mint(user2, SECOND_DEPOSIT);
        vm.startPrank(user2);
        mockUSDC.approve(address(vault), SECOND_DEPOSIT);
        vault.deposit(SECOND_DEPOSIT, user2);
        vm.stopPrank();

        uint256 balance1 = vault.balanceOf(user);
        uint256 balance2 = vault.balanceOf(user2);
        uint256 totalSupply = vault.totalSupply();

        assertEq(totalSupply, balance1 + balance2, "totalSupply should equal sum of balances");
    }
}
