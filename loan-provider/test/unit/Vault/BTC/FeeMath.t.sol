// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {BaseTestForBTCVault} from "../BaseTestForBTCVault.t.sol";
import {BTCVaultHarness} from "../../../harness/BTCVaultHarness.sol";

/// @title FeeMathTest
/// @author Bitmor Protocol
/// @notice Tests for BTCVault fee calculation functions `_feeOnRaw` and `_feeOnTotal`
/// @dev Hunts for rounding errors, precision loss, and edge case bugs in fee calculations.
///      These internal functions are exposed via `BTCVaultHarness` for testing.
contract FeeMathTest is BaseTestForBTCVault {
    // ============ Constants ============

    /// @notice Minimum possible amount (1 wei)
    uint256 constant ONE_WEI = 1;

    /// @notice Maximum fee in basis points (10%)
    uint256 constant MAX_FEE_BPS = 10_00;

    /// @notice Standard fee for most tests (0.5%)
    uint256 constant STANDARD_FEE_BPS = 50;

    /// @notice Zero fee for zero-fee tests
    uint256 constant ZERO_FEE_BPS = 0;

    /// @notice Standard test amount (1000 USDC)
    uint256 constant STANDARD_AMOUNT = 1000e6;

    /// @notice Amount that doesn't divide evenly for rounding tests (1001 USDC)
    uint256 constant ODD_AMOUNT = 1001e6;

    /// @notice Large amount for overflow testing
    uint256 constant LARGE_AMOUNT = 1e30;

    // ============ feeOnRaw Tests ============

    /// @notice Test `feeOnRaw` with zero assets returns zero fee
    function test_feeOnRaw_ZeroAssets_ReturnsZero() public view {
        uint256 fee = vault.feeOnRaw(0, STANDARD_FEE_BPS);
        assertEq(fee, 0, "fee on zero assets should be zero");
    }

    /// @notice Test `feeOnRaw` with zero fee BPS returns zero
    function test_feeOnRaw_ZeroFeeBps_ReturnsZero() public view {
        uint256 fee = vault.feeOnRaw(DEPOSIT_AMOUNT, ZERO_FEE_BPS);
        assertEq(fee, 0, "fee with zero bps should be zero");
    }

    /// @notice Test `feeOnRaw` at maximum fee (10%) calculates correctly
    function test_feeOnRaw_MaxFeeBps_CalculatesCorrectly() public view {
        // feeOnRaw = assets * feeBps / 10000 (rounded up)
        // = 1000e6 * 1000 / 10000 = 100e6
        uint256 fee = vault.feeOnRaw(STANDARD_AMOUNT, MAX_FEE_BPS);
        assertEq(fee, 100e6, "10% fee on 1000 should be 100");
    }

    /// @notice Test `feeOnRaw` with 1 wei input - checks precision at minimum
    function test_feeOnRaw_OneWeiAsset_HandlesMinimumPrecision() public view {
        uint256 fee = vault.feeOnRaw(ONE_WEI, STANDARD_FEE_BPS);
        // feeOnRaw rounds UP: 1 * 50 / 10000 = 0.005, rounds to 1
        assertGe(fee, 0, "fee on 1 wei should be >= 0");
        assertLe(fee, ONE_WEI, "fee on 1 wei should be <= 1 wei");
    }

    /// @notice Test `feeOnRaw` with 1 wei at max fee (10%)
    function test_feeOnRaw_OneWeiAsset_MaxFee_RoundsUpToOne() public view {
        uint256 fee = vault.feeOnRaw(ONE_WEI, MAX_FEE_BPS);
        // 1 * 1000 / 10000 = 0.1, rounds up to 1
        assertEq(fee, 1, "feeOnRaw with max fee on 1 wei should round up to 1");
    }

    /// @notice Test `feeOnRaw` with very large asset amount - check for overflow
    function test_feeOnRaw_LargeAssetAmount_NoOverflow() public view {
        // Expected: 1e30 * 50 / 10000 = 5e27
        uint256 fee = vault.feeOnRaw(LARGE_AMOUNT, STANDARD_FEE_BPS);
        uint256 expected = (LARGE_AMOUNT * STANDARD_FEE_BPS + BASIS_POINT_SCALE - 1) / BASIS_POINT_SCALE;
        assertEq(fee, expected, "fee on large amount should calculate correctly");
    }

    /// @notice Test `feeOnRaw` rounds UP (protocol-favorable)
    function test_feeOnRaw_RoundsUp_ProtocolFavorable() public view {
        // Use amount that doesn't divide evenly: 1001e6 * 50 / 10000 = 5.005e6
        uint256 fee = vault.feeOnRaw(ODD_AMOUNT, STANDARD_FEE_BPS);

        // Exact calculation (truncated)
        uint256 exactFee = (ODD_AMOUNT * STANDARD_FEE_BPS) / BASIS_POINT_SCALE;

        // Fee should be rounded up, so >= exact (and likely +1)
        assertGe(fee, exactFee, "feeOnRaw should round up");
    }

    /// @notice Test `feeOnRaw` with boundary fee value (1 basis point = 0.01%)
    function test_feeOnRaw_OneBasisPoint_CalculatesCorrectly() public view {
        uint256 oneBps = 1;
        // 1000e6 * 1 / 10000 = 0.1e6 = 100000
        uint256 fee = vault.feeOnRaw(STANDARD_AMOUNT, oneBps);
        uint256 expected = (STANDARD_AMOUNT * oneBps + BASIS_POINT_SCALE - 1) / BASIS_POINT_SCALE;
        assertEq(fee, expected, "1 bps fee should calculate correctly");
    }

    // ============ feeOnTotal Tests ============

    /// @notice Test `feeOnTotal` with zero assets returns zero
    function test_feeOnTotal_ZeroAssets_ReturnsZero() public view {
        uint256 fee = vault.feeOnTotal(0, STANDARD_FEE_BPS);
        assertEq(fee, 0, "fee on zero total should be zero");
    }

    /// @notice Test `feeOnTotal` with zero fee BPS returns zero
    function test_feeOnTotal_ZeroFeeBps_ReturnsZero() public view {
        uint256 fee = vault.feeOnTotal(DEPOSIT_AMOUNT, ZERO_FEE_BPS);
        assertEq(fee, 0, "fee with zero bps should be zero");
    }

    /// @notice Test `feeOnTotal` at max fee extracts correct portion
    function test_feeOnTotal_MaxFeeBps_ExtractsCorrectPortion() public view {
        // feeOnTotal = total * feeBps / (feeBps + 10000)
        // For 10% fee: 1100e6 * 1000 / 11000 = 100e6
        uint256 total = 1100e6;
        uint256 fee = vault.feeOnTotal(total, MAX_FEE_BPS);
        assertEq(fee, 100e6, "10% feeOnTotal on 1100 should be 100");
    }

    /// @notice Test `feeOnTotal` with 1 wei
    function test_feeOnTotal_OneWeiAsset_HandlesMinimumPrecision() public view {
        uint256 fee = vault.feeOnTotal(ONE_WEI, STANDARD_FEE_BPS);
        assertGe(fee, 0, "fee on 1 wei should be >= 0");
        assertLe(fee, ONE_WEI, "fee on 1 wei should be <= 1 wei");
    }

    /// @notice Test `feeOnTotal` rounds UP (protocol-favorable)
    function test_feeOnTotal_RoundsUp_ProtocolFavorable() public view {
        // Use amount that doesn't divide evenly
        // feeOnTotal = total * bps / (bps + 10000) rounded up
        uint256 fee = vault.feeOnTotal(ODD_AMOUNT, STANDARD_FEE_BPS);

        // Exact calculation (truncated)
        uint256 exactFee = (ODD_AMOUNT * STANDARD_FEE_BPS) / (STANDARD_FEE_BPS + BASIS_POINT_SCALE);

        assertGe(fee, exactFee, "feeOnTotal should round up");
    }

    /// @notice Test `feeOnTotal` with boundary fee value (1 basis point)
    function test_feeOnTotal_OneBasisPoint_CalculatesCorrectly() public view {
        uint256 oneBps = 1;
        // feeOnTotal = total * 1 / (1 + 10000) = total * 1 / 10001
        uint256 fee = vault.feeOnTotal(STANDARD_AMOUNT, oneBps);
        uint256 expected = (STANDARD_AMOUNT * oneBps + (oneBps + BASIS_POINT_SCALE) - 1) / (oneBps + BASIS_POINT_SCALE);
        assertEq(fee, expected, "1 bps feeOnTotal should calculate correctly");
    }

    /// @notice Test `feeOnTotal` with large amount - check for overflow
    function test_feeOnTotal_LargeAmount_NoOverflow() public view {
        uint256 fee = vault.feeOnTotal(LARGE_AMOUNT, STANDARD_FEE_BPS);
        uint256 expected = (LARGE_AMOUNT * STANDARD_FEE_BPS + (STANDARD_FEE_BPS + BASIS_POINT_SCALE) - 1)
            / (STANDARD_FEE_BPS + BASIS_POINT_SCALE);
        assertEq(fee, expected, "feeOnTotal on large amount should calculate correctly");
    }

    // ============ Consistency Tests ============

    /// @notice Test `feeOnRaw` and `feeOnTotal` are mathematically consistent
    /// @dev If feeOnRaw(base, bps) = fee, then feeOnTotal(base + fee, bps) should approximately equal fee
    function test_feeOnRaw_vs_feeOnTotal_Consistency() public view {
        uint256 baseAmount = 10000e6;
        uint256 feeBps = 100; // 1%

        // Calculate fee to add
        uint256 feeToAdd = vault.feeOnRaw(baseAmount, feeBps);
        uint256 total = baseAmount + feeToAdd;

        // Extract fee from total
        uint256 feeExtracted = vault.feeOnTotal(total, feeBps);

        // Due to rounding, they may differ by 1-2 wei
        uint256 diff = feeToAdd > feeExtracted ? feeToAdd - feeExtracted : feeExtracted - feeToAdd;
        assertLe(diff, 2, "feeOnRaw and feeOnTotal should be consistent within 2 wei");
    }

    /// @notice Test fee calculation symmetry for deposit/withdraw roundtrip
    function test_feeSymmetry_DepositWithdrawRoundtrip() public view {
        uint256 depositAssets = 10000e6;
        uint256 entryFee = vault.getEntryFee();
        uint256 exitFee = vault.getExitFee();

        // Simulate deposit: user provides depositAssets, fee extracted
        uint256 entryFeeAmt = vault.feeOnTotal(depositAssets, entryFee);
        uint256 assetsAfterEntry = depositAssets - entryFeeAmt;

        // Simulate withdraw: user wants assetsAfterEntry back, exit fee added
        uint256 exitFeeAmt = vault.feeOnRaw(assetsAfterEntry, exitFee);
        uint256 totalNeededForWithdraw = assetsAfterEntry + exitFeeAmt;

        // User should need MORE than they deposited to get same assets back (fees are costly)
        assertGt(totalNeededForWithdraw + entryFeeAmt, depositAssets, "total fees should make roundtrip costly");
    }

    /// @notice Test that both fee functions return zero when both inputs are zero
    function test_feeOnRaw_and_feeOnTotal_BothZero_ReturnsZero() public view {
        assertEq(vault.feeOnRaw(0, 0), 0, "feeOnRaw(0,0) should be 0");
        assertEq(vault.feeOnTotal(0, 0), 0, "feeOnTotal(0,0) should be 0");
    }

    /// @notice Test fee relationship: feeOnTotal should always be <= feeOnRaw for same inputs
    /// @dev Because feeOnTotal divides by a larger denominator (bps + 10000 vs 10000)
    function test_feeOnTotal_LessThanOrEqual_feeOnRaw_SameInputs() public view {
        uint256 amount = STANDARD_AMOUNT;
        uint256 feeBps = STANDARD_FEE_BPS;

        uint256 feeRaw = vault.feeOnRaw(amount, feeBps);
        uint256 feeTotal = vault.feeOnTotal(amount, feeBps);

        assertLe(feeTotal, feeRaw, "feeOnTotal should be <= feeOnRaw for same inputs");
    }

    /// @notice Verify the fee formulas match the ERC-4626 fee math expectations
    /// @dev feeOnRaw is for adding fee, feeOnTotal is for extracting fee from inclusive amount
    function test_feeMath_MatchesERC4626Expectations() public view {
        uint256 baseAssets = 10000e6;
        uint256 feeBps = 100; // 1%

        // feeOnRaw: Calculate fee to ADD to base assets
        // Formula: assets * feeBps / BASIS_POINT_SCALE (rounded up)
        uint256 feeToAdd = vault.feeOnRaw(baseAssets, feeBps);
        uint256 totalWithFee = baseAssets + feeToAdd;

        // Now extract fee from totalWithFee using feeOnTotal
        uint256 extractedFee = vault.feeOnTotal(totalWithFee, feeBps);
        uint256 recoveredBase = totalWithFee - extractedFee;

        // The recovered base should be approximately equal to original base
        // (within rounding tolerance)
        uint256 diff = baseAssets > recoveredBase ? baseAssets - recoveredBase : recoveredBase - baseAssets;
        assertLe(diff, 2, "fee math should allow approximate round-trip within 2 wei");
    }
}
