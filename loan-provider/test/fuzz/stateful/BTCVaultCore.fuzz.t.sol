// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {BTCVaultFuzzTestBase} from "../base/BTCVaultFuzzTestBase.sol";
import {FuzzConstants as FC} from "../helpers/FuzzConstants.sol";
import {BTCVault} from "@btcVault/BTCVault.sol";
import {IERC20} from "@openzeppelin/interfaces/IERC20.sol";

/**
 * @title BTCVaultCoreFuzzTest
 * @author Bitmor Protocol
 * @notice Fuzz tests for BTCVault core ERC-4626 operations: fee math, roundtrips, preview compliance, multi-user
 * @dev Tests real BTCVault + real AaveTokenizedStrategy backed by MockAaveV3Pool.
 *
 * ## Test Coverage
 *
 * ### Fee Math (BTC-CORE-01 through BTC-CORE-07)
 * - BTC-CORE-01: Deposit with fuzzed entry fee charges expected fee
 * - BTC-CORE-02: Mint with fuzzed entry fee charges expected fee
 * - BTC-CORE-03: Withdraw with fuzzed exit fee charges expected fee
 * - BTC-CORE-04: Redeem with fuzzed exit fee charges expected fee
 * - BTC-CORE-05: feeOnRaw and feeOnTotal are approximate inverses
 * - BTC-CORE-06: feeRecipient receives exact fee on deposit
 * - BTC-CORE-07: feeRecipient receives exact fee on withdraw
 *
 * ### Roundtrip / No Free Money (BTC-CORE-08 through BTC-CORE-10)
 * - BTC-CORE-08: Deposit-redeem roundtrip is never profitable
 * - BTC-CORE-09: Mint-withdraw roundtrip is never profitable
 * - BTC-CORE-10: convertToAssets(convertToShares(x)) <= x
 *
 * ### ERC-4626 Preview Compliance (BTC-CORE-11 through BTC-CORE-14)
 * - BTC-CORE-11: previewDeposit <= actual shares minted
 * - BTC-CORE-12: previewMint >= actual assets consumed
 * - BTC-CORE-13: previewWithdraw >= actual shares burned
 * - BTC-CORE-14: previewRedeem <= actual assets returned
 *
 * ### Multi-User & Yield (BTC-CORE-15 through BTC-CORE-16)
 * - BTC-CORE-15: Two depositors receive proportional shares
 * - BTC-CORE-16: Yield accrual does not dilute first depositor
 *
 * @custom:audit-category ERC-4626 Compliance, Fee Math, Roundtrip Safety
 */
contract BTCVaultCoreFuzzTest is BTCVaultFuzzTestBase {
    // ============ Constants ============

    /// @dev Minimum shares for mint fuzz bound
    uint256 internal constant MIN_SHARES = 1;

    /// @dev Maximum shares for mint fuzz bound
    uint256 internal constant MAX_SHARES = 50e8;

    /// @dev BPS denominator (10,000 = 100%)
    uint256 internal constant BPS = 10_000;

    // ============ Fee Math Helpers ============

    /// @notice Replicates `_feeOnTotal(assets, bps)` = mulDivUp(assets, bps, bps + 10000)
    function _computeFeeOnTotal(uint256 assets, uint256 bps) internal pure returns (uint256) {
        if (bps == 0) return 0;
        return (assets * bps + (bps + BPS) - 1) / (bps + BPS);
    }

    /// @notice Replicates `_feeOnRaw(assets, bps)` = mulDivUp(assets, bps, 10000)
    function _computeFeeOnRaw(uint256 assets, uint256 bps) internal pure returns (uint256) {
        if (bps == 0) return 0;
        return (assets * bps + BPS - 1) / BPS;
    }

    // ============ Fee Math Tests (BTC-CORE-01 through BTC-CORE-07) ============

    /// @custom:audit-property BTC-CORE-01
    /// @notice Deposit with fuzzed entry fee charges the expected fee to feeRecipient
    function testFuzz_DepositWithFees_ChargesExpectedFee(uint256 assetsSeed, uint256 feeSeed) public {
        uint256 entryFee = _boundFee(feeSeed);
        uint256 assets = _boundBtcAmount(assetsSeed);

        _setEntryFee(entryFee);

        uint256 feeRecipientBefore = mockCbBTC.balanceOf(feeRecipient);

        _fundCbBTCAndApprove(depositor, address(vault), assets);
        uint256 depositorBefore = mockCbBTC.balanceOf(depositor);

        vm.prank(depositor);
        vault.deposit(assets, depositor);

        uint256 depositorAfter = mockCbBTC.balanceOf(depositor);
        uint256 feeRecipientDelta = mockCbBTC.balanceOf(feeRecipient) - feeRecipientBefore;
        uint256 expectedFee = _computeFeeOnTotal(assets, entryFee);

        assertApproxEqAbs(
            feeRecipientDelta, expectedFee, FC.MAX_ROUNDING_ERROR, "fee recipient should receive expected entry fee"
        );
        assertEq(depositorBefore - depositorAfter, assets, "depositor should spend exactly assets amount");
    }

    /// @custom:audit-property BTC-CORE-02
    /// @notice Mint with fuzzed entry fee charges the expected fee to feeRecipient
    function testFuzz_MintWithFees_ChargesExpectedFee(uint256 sharesSeed, uint256 feeSeed) public {
        uint256 entryFee = _boundFee(feeSeed);
        uint256 shares = bound(sharesSeed, MIN_SHARES, MAX_SHARES);

        _setEntryFee(entryFee);

        uint256 feeRecipientBefore = mockCbBTC.balanceOf(feeRecipient);

        uint256 assetsConsumed = _mintFromVault(depositor, shares);

        uint256 feeRecipientDelta = mockCbBTC.balanceOf(feeRecipient) - feeRecipientBefore;

        // For mint: the raw assets (before fee) come from super.previewMint(shares),
        // then feeOnRaw is added. So fee = feeOnRaw(rawAssets, entryFee).
        // rawAssets = assetsConsumed - fee, and fee = feeOnRaw(rawAssets, entryFee).
        // Equivalently: fee = feeOnTotal(assetsConsumed, entryFee)
        uint256 expectedFee = _computeFeeOnTotal(assetsConsumed, entryFee);

        assertApproxEqAbs(
            feeRecipientDelta, expectedFee, FC.MAX_ROUNDING_ERROR, "fee recipient should receive entry fee on mint"
        );
    }

    /// @custom:audit-property BTC-CORE-03
    /// @notice Withdraw with fuzzed exit fee charges expected fee to feeRecipient
    function testFuzz_WithdrawWithFees_ChargesExpectedFee(uint256 assetsSeed, uint256 feeSeed) public {
        // Deposit with zero exit fee first
        uint256 depositAmount = _boundBtcAmount(assetsSeed);
        _setExitFee(0);
        _depositToVault(depositor, depositAmount);

        // Set fuzzed exit fee
        uint256 exitFee = _boundFee(feeSeed);
        _setExitFee(exitFee);

        uint256 maxW = vault.maxWithdraw(depositor);
        vm.assume(maxW > 0);
        uint256 withdrawAmount = bound(assetsSeed, 1, maxW);

        uint256 feeRecipientBefore = mockCbBTC.balanceOf(feeRecipient);

        vm.prank(depositor);
        vault.withdraw(withdrawAmount, depositor, depositor);

        uint256 feeRecipientDelta = mockCbBTC.balanceOf(feeRecipient) - feeRecipientBefore;
        uint256 expectedFee = _computeFeeOnRaw(withdrawAmount, exitFee);

        assertApproxEqAbs(
            feeRecipientDelta, expectedFee, FC.MAX_ROUNDING_ERROR, "fee recipient should receive expected exit fee"
        );
    }

    /// @custom:audit-property BTC-CORE-04
    /// @notice Redeem with fuzzed exit fee charges expected fee to feeRecipient
    function testFuzz_RedeemWithFees_ChargesExpectedFee(uint256 sharesSeed, uint256 feeSeed) public {
        // Deposit with zero exit fee first
        _setExitFee(0);
        uint256 depositAmount = _boundBtcAmount(sharesSeed);
        uint256 sharesReceived = _depositToVault(depositor, depositAmount);
        vm.assume(sharesReceived > 0);

        // Set fuzzed exit fee
        uint256 exitFee = _boundFee(feeSeed);
        _setExitFee(exitFee);

        uint256 sharesToRedeem = bound(sharesSeed, 1, sharesReceived);

        uint256 feeRecipientBefore = mockCbBTC.balanceOf(feeRecipient);

        vm.prank(depositor);
        uint256 assetsReturned = vault.redeem(sharesToRedeem, depositor, depositor);

        uint256 feeRecipientDelta = mockCbBTC.balanceOf(feeRecipient) - feeRecipientBefore;

        // For redeem: the raw assets from super.previewRedeem(shares) have feeOnTotal extracted.
        // Fee = feeOnRaw(assetsReturned, exitFee)
        uint256 expectedFee = _computeFeeOnRaw(assetsReturned, exitFee);

        assertApproxEqAbs(
            feeRecipientDelta, expectedFee, FC.MAX_ROUNDING_ERROR, "fee recipient should receive exit fee on redeem"
        );
    }

    /// @custom:audit-property BTC-CORE-05
    /// @notice feeOnRaw and feeOnTotal are approximate inverses
    function testFuzz_FeeOnRawVsFeeOnTotal_Inverses(uint256 assetsSeed, uint256 feeSeed) public pure {
        uint256 fee = bound(feeSeed, 1, FC.MAX_FEE_BPS);
        uint256 totalAmount = bound(assetsSeed, 1, FC.MAX_BTC_AMOUNT);

        // Extract fee from total via feeOnTotal
        uint256 feeFromTotal = _computeFeeOnTotal(totalAmount, fee);
        uint256 netAmount = totalAmount - feeFromTotal;

        // Compute feeOnRaw on the net amount
        uint256 feeFromRaw = _computeFeeOnRaw(netAmount, fee);

        // They should reconstruct the original total (within rounding)
        // netAmount + feeFromRaw should approximate totalAmount
        uint256 reconstructed = netAmount + feeFromRaw;

        // Allow rounding tolerance of 2 (one for each mulDivUp)
        assertApproxEqAbs(
            reconstructed,
            totalAmount,
            FC.MAX_ROUNDING_ERROR,
            "feeOnRaw(net, bps) + net should approximate total"
        );
    }

    /// @custom:audit-property BTC-CORE-06
    /// @notice feeRecipient receives exact fee on deposit (cbBTC balance delta check)
    function testFuzz_FeeRecipientReceivesExactFee_OnDeposit(uint256 assetsSeed, uint256 feeSeed) public {
        uint256 entryFee = _boundFee(feeSeed);
        uint256 assets = _boundBtcAmount(assetsSeed);

        _setEntryFee(entryFee);

        uint256 feeRecipientBefore = mockCbBTC.balanceOf(feeRecipient);

        _depositToVault(depositor, assets);

        uint256 feeRecipientDelta = mockCbBTC.balanceOf(feeRecipient) - feeRecipientBefore;
        uint256 expectedFee = _computeFeeOnTotal(assets, entryFee);

        assertApproxEqAbs(
            feeRecipientDelta, expectedFee, FC.MAX_ROUNDING_ERROR, "fee recipient delta should equal feeOnTotal"
        );
    }

    /// @custom:audit-property BTC-CORE-07
    /// @notice feeRecipient receives exact fee on withdraw
    function testFuzz_FeeRecipientReceivesExactFee_OnWithdraw(uint256 assetsSeed, uint256 feeSeed) public {
        // Deposit with no exit fee
        uint256 depositAmount = _boundBtcAmount(assetsSeed);
        _setExitFee(0);
        _depositToVault(depositor, depositAmount);

        // Set fuzzed exit fee
        uint256 exitFee = _boundFee(feeSeed);
        _setExitFee(exitFee);

        uint256 maxW = vault.maxWithdraw(depositor);
        vm.assume(maxW > 0);
        uint256 withdrawAmount = bound(assetsSeed, 1, maxW);

        uint256 feeRecipientBefore = mockCbBTC.balanceOf(feeRecipient);

        vm.prank(depositor);
        vault.withdraw(withdrawAmount, depositor, depositor);

        uint256 feeRecipientDelta = mockCbBTC.balanceOf(feeRecipient) - feeRecipientBefore;
        uint256 expectedFee = _computeFeeOnRaw(withdrawAmount, exitFee);

        assertApproxEqAbs(
            feeRecipientDelta, expectedFee, FC.MAX_ROUNDING_ERROR, "fee recipient delta should equal feeOnRaw"
        );
    }

    // ============ Roundtrip / No Free Money Tests (BTC-CORE-08 through BTC-CORE-10) ============

    /// @custom:audit-property BTC-CORE-08
    /// @notice Deposit then redeem all shares should never return more assets than deposited
    function testFuzz_DepositRedeem_NeverProfitable(uint256 assetsSeed, uint256 feeSeed) public {
        uint256 entryFee = _boundFee(feeSeed);
        uint256 exitFee = _boundFee(feeSeed >> 128);
        uint256 assets = _boundBtcAmount(assetsSeed);

        _setEntryFee(entryFee);
        _setExitFee(exitFee);

        uint256 shares = _depositToVault(depositor, assets);
        vm.assume(shares > 0);

        vm.prank(depositor);
        uint256 assetsOut = vault.redeem(shares, depositor, depositor);

        assertLe(assetsOut, assets, "deposit-redeem roundtrip must not be profitable");
    }

    /// @custom:audit-property BTC-CORE-09
    /// @notice Mint then withdraw maxWithdraw should never return more than was consumed
    function testFuzz_MintWithdraw_NeverProfitable(uint256 sharesSeed, uint256 feeSeed) public {
        uint256 entryFee = _boundFee(feeSeed);
        uint256 exitFee = _boundFee(feeSeed >> 128);
        uint256 shares = bound(sharesSeed, MIN_SHARES, MAX_SHARES);

        _setEntryFee(entryFee);
        _setExitFee(exitFee);

        uint256 assetsIn = _mintFromVault(depositor, shares);

        uint256 maxW = vault.maxWithdraw(depositor);

        assertLe(maxW, assetsIn, "mint-withdraw roundtrip must not be profitable");
    }

    /// @custom:audit-property BTC-CORE-10
    /// @notice convertToAssets(convertToShares(x)) <= x (no inflation from convert roundtrip)
    function testFuzz_ConvertRoundtrip_NeverInflates(uint256 assetsSeed) public {
        uint256 assets = _boundBtcAmount(assetsSeed);

        // Seed the vault with a deposit so exchange rate is non-trivial
        _depositToVault(depositor, _boundBtcAmount(assetsSeed >> 128));

        uint256 shares = vault.convertToShares(assets);
        uint256 assetsBack = vault.convertToAssets(shares);

        assertLe(assetsBack, assets, "convertToAssets(convertToShares(x)) must be <= x");
    }

    // ============ ERC-4626 Preview Compliance (BTC-CORE-11 through BTC-CORE-14) ============

    /// @custom:audit-property BTC-CORE-11
    /// @notice previewDeposit must return <= actual shares minted
    function testFuzz_PreviewDeposit_ReturnsLessOrEqualActual(uint256 assetsSeed) public {
        uint256 assets = _boundBtcAmount(assetsSeed);

        uint256 preview = vault.previewDeposit(assets);

        uint256 actual = _depositToVault(depositor, assets);

        assertLe(preview, actual, "previewDeposit must return <= actual shares minted");
    }

    /// @custom:audit-property BTC-CORE-12
    /// @notice previewMint must return >= actual assets consumed
    function testFuzz_PreviewMint_ReturnsGreaterOrEqualActual(uint256 sharesSeed) public {
        uint256 shares = bound(sharesSeed, MIN_SHARES, MAX_SHARES);

        uint256 preview = vault.previewMint(shares);

        uint256 actual = _mintFromVault(depositor, shares);

        assertGe(preview, actual, "previewMint must return >= actual assets consumed");
    }

    /// @custom:audit-property BTC-CORE-13
    /// @notice previewWithdraw must return >= actual shares burned
    function testFuzz_PreviewWithdraw_ReturnsGreaterOrEqualActual(uint256 assetsSeed) public {
        uint256 depositAmount = _boundBtcAmount(assetsSeed);
        _depositToVault(depositor, depositAmount);

        uint256 maxW = vault.maxWithdraw(depositor);
        vm.assume(maxW > 0);
        uint256 withdrawAmount = bound(assetsSeed, 1, maxW);

        uint256 preview = vault.previewWithdraw(withdrawAmount);

        vm.prank(depositor);
        uint256 actual = vault.withdraw(withdrawAmount, depositor, depositor);

        assertGe(preview, actual, "previewWithdraw must return >= actual shares burned");
    }

    /// @custom:audit-property BTC-CORE-14
    /// @notice previewRedeem must return <= actual assets returned
    function testFuzz_PreviewRedeem_ReturnsLessOrEqualActual(uint256 sharesSeed) public {
        uint256 depositAmount = _boundBtcAmount(sharesSeed);
        uint256 sharesReceived = _depositToVault(depositor, depositAmount);
        vm.assume(sharesReceived > 0);

        uint256 sharesToRedeem = bound(sharesSeed, 1, sharesReceived);

        uint256 preview = vault.previewRedeem(sharesToRedeem);

        vm.prank(depositor);
        uint256 actual = vault.redeem(sharesToRedeem, depositor, depositor);

        assertLe(preview, actual, "previewRedeem must return <= actual assets returned");
    }

    // ============ Multi-User & Yield Tests (BTC-CORE-15 through BTC-CORE-16) ============

    /// @custom:audit-property BTC-CORE-15
    /// @notice Two depositors should receive shares proportional to their deposit amounts
    function testFuzz_TwoDepositors_SharesProportional(uint256 amount1Seed, uint256 amount2Seed) public {
        uint256 amount1 = _boundBtcAmount(amount1Seed);
        uint256 amount2 = _boundBtcAmount(amount2Seed);

        uint256 shares1 = _depositToVault(depositor, amount1);
        uint256 shares2 = _depositToVault(depositor2, amount2);

        vm.assume(shares1 > 0 && shares2 > 0);

        // Cross-multiply check: shares1 * amount2 ~= shares2 * amount1
        // This holds because no state changes between deposits (no yield accrual).
        assertApproxEqRel(
            shares1 * amount2,
            shares2 * amount1,
            FC.MAX_ROUNDTRIP_SLIPPAGE,
            "shares should be proportional to deposit amounts"
        );
    }

    /// @custom:audit-property BTC-CORE-16
    /// @notice After yield accrual, first depositor's share value should include yield,
    ///         and second depositor should pay more per share (get fewer shares per asset)
    function testFuzz_YieldAccrual_SecondDepositorDoesNotDilute(
        uint256 depositSeed,
        uint256 yieldSeed,
        uint256 secondDepositSeed
    ) public {
        uint256 deposit1 = _boundBtcAmount(depositSeed);
        // Minimum yield of 100 sats avoids rounding-dominated edge cases
        uint256 yieldAmount = bound(yieldSeed, 100, 10e8);
        uint256 deposit2 = _boundBtcAmount(secondDepositSeed);

        // Depositor 1 deposits
        uint256 shares1 = _depositToVault(depositor, deposit1);
        vm.assume(shares1 > 0);

        // Record share value before yield
        uint256 shareValueBefore = vault.convertToAssets(shares1);

        // Simulate yield
        _simulateYield(yieldAmount);

        // Record share value after yield
        uint256 shareValueAfter = vault.convertToAssets(shares1);

        // Depositor 1's share value should include yield
        assertGe(shareValueAfter, shareValueBefore, "depositor1 share value should include yield");

        // Depositor 2 deposits after yield
        uint256 shares2 = _depositToVault(depositor2, deposit2);
        vm.assume(shares2 > 0);

        // Depositor 2 should get fewer shares per asset (or equivalently, pay more per share)
        // shares2/deposit2 <= shares1/deposit1  =>  shares2 * deposit1 <= shares1 * deposit2
        assertLe(
            shares2 * deposit1,
            shares1 * deposit2,
            "second depositor should get fewer shares per asset after yield"
        );
    }
}
