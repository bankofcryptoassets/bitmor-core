// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {FuzzTestBase} from "../base/FuzzTestBase.sol";
import {FuzzConstants as FC} from "../helpers/FuzzConstants.sol";
import {MockBTCVault} from "../../mock/MockBTCVault.sol";

/**
 * @title BTCVaultFuzzTest
 * @author Bitmor Protocol
 * @notice Fuzz tests for BTCVault contract (ERC-4626)
 * @dev Tests deposit, withdraw, mint, redeem with fuzzed parameters
 */
contract BTCVaultFuzzTest is FuzzTestBase {
    // ============ Vault Infrastructure ============

    /// @dev Mock BTC vault for testing
    MockBTCVault public mockBTCVault;

    /// @dev Standard test user
    address public user;

    function setUp() public override {
        super.setUp();

        user = makeAddr("vaultUser");

        // Deploy BTCVault that wraps cbBTC -> bvBTC shares
        vm.startPrank(admin);
        mockBTCVault = new MockBTCVault(
            address(mockCbBTC),
            "Bitmor BTC Vault",
            "bvBTC",
            8 // Same decimals as cbBTC
        );
        vm.stopPrank();
    }

    // ============ Deposit/Withdraw Roundtrip Tests ============

    /// @custom:audit-property BTC-01: Deposit/withdraw roundtrip preserves value within slippage
    /// @custom:audit-category ERC-4626 Compliance
    /// @custom:audit-severity Critical
    function testFuzz_DepositWithdraw_Roundtrip(uint256 depositSeed) public {
        uint256 depositAmount = _boundBtcAmount(depositSeed);

        // Fund user
        _fundCbBTCAndApprove(user, address(mockBTCVault), depositAmount);

        uint256 balanceBefore = mockCbBTC.balanceOf(user);

        // Deposit
        vm.prank(user);
        uint256 shares = mockBTCVault.deposit(depositAmount, user);

        assertGt(shares, 0, "should receive shares");

        // Withdraw all shares
        vm.prank(user);
        uint256 assetsReceived = mockBTCVault.redeem(shares, user, user);

        uint256 balanceAfter = mockCbBTC.balanceOf(user);

        // Assert roundtrip within slippage
        assertApproxEqRel(
            balanceAfter, balanceBefore, FC.MAX_ROUNDTRIP_SLIPPAGE, "roundtrip should preserve value within slippage"
        );
    }

    /// @custom:audit-property BTC-02: Mint/redeem roundtrip preserves value within slippage
    /// @custom:audit-category ERC-4626 Compliance
    /// @custom:audit-severity Critical
    function testFuzz_MintRedeem_Roundtrip(uint256 sharesSeed) public {
        uint256 sharesToMint = bound(sharesSeed, FC.MIN_BTC_AMOUNT, FC.MAX_BTC_AMOUNT);

        // Preview assets needed
        uint256 assetsNeeded = mockBTCVault.previewMint(sharesToMint);
        vm.assume(assetsNeeded > 0 && assetsNeeded <= FC.MAX_BTC_AMOUNT);

        // Fund user
        _fundCbBTCAndApprove(user, address(mockBTCVault), assetsNeeded);

        uint256 balanceBefore = mockCbBTC.balanceOf(user);

        // Mint shares
        vm.prank(user);
        mockBTCVault.mint(sharesToMint, user);

        // Redeem all shares
        vm.prank(user);
        mockBTCVault.redeem(sharesToMint, user, user);

        uint256 balanceAfter = mockCbBTC.balanceOf(user);

        // Assert roundtrip within slippage
        assertApproxEqRel(
            balanceAfter, balanceBefore, FC.MAX_ROUNDTRIP_SLIPPAGE, "mint/redeem roundtrip should preserve value"
        );
    }

    // ============ Proportionality Tests ============

    /// @custom:audit-property BTC-03: Shares minted proportional to deposit amount
    /// @custom:audit-category ERC-4626 Compliance
    /// @custom:audit-severity High
    function testFuzz_Deposit_SharesProportional(uint256 amount1Seed, uint256 amount2Seed) public {
        uint256 amount1 = _boundBtcAmount(amount1Seed);
        uint256 amount2 = _boundBtcAmount(amount2Seed);

        // Ensure amounts are different for meaningful test
        vm.assume(amount1 != amount2);
        vm.assume(amount1 > FC.MIN_BTC_AMOUNT && amount2 > FC.MIN_BTC_AMOUNT);

        // First deposit
        _fundCbBTCAndApprove(user, address(mockBTCVault), amount1);
        vm.prank(user);
        uint256 shares1 = mockBTCVault.deposit(amount1, user);

        // Second deposit from different user
        address user2 = makeAddr("user2");
        _fundCbBTCAndApprove(user2, address(mockBTCVault), amount2);
        vm.prank(user2);
        uint256 shares2 = mockBTCVault.deposit(amount2, user2);

        // Assert proportionality (within tolerance for rounding)
        // shares1/amount1 ≈ shares2/amount2
        // => shares1 * amount2 ≈ shares2 * amount1
        uint256 cross1 = shares1 * amount2;
        uint256 cross2 = shares2 * amount1;

        assertApproxEqRel(cross1, cross2, FC.MAX_ROUNDTRIP_SLIPPAGE, "shares should be proportional to deposit");
    }

    // ============ ERC-4626 Invariant Tests ============

    /// @custom:audit-property BTC-04: convertToAssets(convertToShares(x)) <= x (no free money)
    /// @custom:audit-category ERC-4626 Compliance
    /// @custom:audit-severity Critical
    function testFuzz_ConvertRoundtrip_NoFreeMoney(uint256 assetsSeed) public view {
        uint256 assets = _boundBtcAmount(assetsSeed);

        uint256 shares = mockBTCVault.convertToShares(assets);
        uint256 assetsBack = mockBTCVault.convertToAssets(shares);

        assertLe(assetsBack, assets, "roundtrip conversion should not create free money");
    }

    /// @custom:audit-property BTC-05: previewDeposit <= actual deposit shares
    /// @custom:audit-category ERC-4626 Compliance
    /// @custom:audit-severity High
    function testFuzz_PreviewDeposit_Conservative(uint256 depositSeed) public {
        uint256 depositAmount = _boundBtcAmount(depositSeed);

        // Preview
        uint256 previewShares = mockBTCVault.previewDeposit(depositAmount);

        // Fund and deposit
        _fundCbBTCAndApprove(user, address(mockBTCVault), depositAmount);
        vm.prank(user);
        uint256 actualShares = mockBTCVault.deposit(depositAmount, user);

        assertGe(actualShares, previewShares, "actual shares should be >= preview");
    }

    /// @custom:audit-property BTC-06: previewWithdraw >= actual withdraw shares
    /// @custom:audit-category ERC-4626 Compliance
    /// @custom:audit-severity High
    function testFuzz_PreviewWithdraw_Conservative(uint256 depositSeed) public {
        uint256 depositAmount = _boundBtcAmount(depositSeed);

        // Setup: deposit first
        _fundCbBTCAndApprove(user, address(mockBTCVault), depositAmount);
        vm.prank(user);
        mockBTCVault.deposit(depositAmount, user);

        uint256 maxWithdraw = mockBTCVault.maxWithdraw(user);
        vm.assume(maxWithdraw > 0);

        uint256 withdrawAmount = bound(depositSeed, 1, maxWithdraw);

        // Preview
        uint256 previewShares = mockBTCVault.previewWithdraw(withdrawAmount);

        // Withdraw
        vm.prank(user);
        uint256 actualShares = mockBTCVault.withdraw(withdrawAmount, user, user);

        assertLe(actualShares, previewShares, "actual shares should be <= preview");
    }

    // ============ Max Functions Tests ============

    /// @custom:audit-property BTC-07: maxDeposit returns valid limit
    /// @custom:audit-category ERC-4626 Compliance
    /// @custom:audit-severity Medium
    function testFuzz_MaxDeposit_Respected(uint256 depositSeed) public {
        uint256 maxDeposit = mockBTCVault.maxDeposit(user);
        vm.assume(maxDeposit > 0);

        uint256 depositAmount = bound(depositSeed, 1, maxDeposit);

        _fundCbBTCAndApprove(user, address(mockBTCVault), depositAmount);

        // Should not revert
        vm.prank(user);
        uint256 shares = mockBTCVault.deposit(depositAmount, user);

        assertGt(shares, 0, "deposit within max should succeed");
    }
}
