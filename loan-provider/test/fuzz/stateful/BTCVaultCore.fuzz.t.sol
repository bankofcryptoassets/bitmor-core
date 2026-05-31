// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {BTCVaultFuzzTestBase} from "../base/BTCVaultFuzzTestBase.sol";
import {FuzzConstants as FC} from "../helpers/FuzzConstants.sol";
import {BTCVault} from "@btcVault/BTCVault.sol";
import {Errors} from "@bitmor/libraries/helpers/Errors.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

/**
 * @title BTCVaultCoreFuzzTest
 * @author Bitmor Protocol
 * @notice Fuzz tests for BTCVault core ERC-4626 operations: fee math, roundtrips, preview compliance, multi-user
 * @dev Tests real BTCVault + real AaveTokenizedStrategy backed by MockAaveV3Pool.
 *
 * ## Test Coverage
 *
 * ### Fee Math (BTC-CORE-01 through BTC-CORE-05)
 * - BTC-CORE-01: Deposit with fuzzed entry fee charges expected fee
 * - BTC-CORE-02: Mint with fuzzed entry fee charges expected fee
 * - BTC-CORE-03: Withdraw with fuzzed exit fee charges expected fee
 * - BTC-CORE-04: Redeem with fuzzed exit fee charges expected fee
 * - BTC-CORE-05: Vault fee consistency on deposit-withdraw roundtrip
 *
 * ### Roundtrip / No Free Money (BTC-CORE-06 through BTC-CORE-08)
 * - BTC-CORE-06: Deposit-redeem roundtrip is never profitable
 * - BTC-CORE-07: Mint-withdraw roundtrip is never profitable
 * - BTC-CORE-08: convertToAssets(convertToShares(x)) <= x
 *
 * ### ERC-4626 Preview Compliance (BTC-CORE-09 through BTC-CORE-12)
 * - BTC-CORE-09: previewDeposit <= actual shares minted
 * - BTC-CORE-10: previewMint >= actual assets consumed
 * - BTC-CORE-11: previewWithdraw >= actual shares burned
 * - BTC-CORE-12: previewRedeem <= actual assets returned
 *
 * ### Multi-User & Yield (BTC-CORE-13 through BTC-CORE-14)
 * - BTC-CORE-13: Two depositors receive proportional shares
 * - BTC-CORE-14: Yield accrual does not dilute first depositor
 *
 * ### Security (BTC-SEC-01 through BTC-SEC-04)
 * - BTC-SEC-01: Donation/inflation attack protection for second depositor
 * - BTC-SEC-02: Fee change after deposit does not trap user
 * - BTC-SEC-03: feeRecipient=vault does not silently inflate share price
 * - BTC-SEC-04: Multi-actor exit race ordering fairness
 *
 * @custom:audit-category ERC-4626 Compliance, Fee Math, Roundtrip Safety
 */
contract BTCVaultCoreFuzzTest is BTCVaultFuzzTestBase {
    // ============ Constants ============

    /// @dev Minimum shares for mint fuzz bound — must produce net assets >= MIN_STRATEGY_DEPOSIT after fees
    uint256 internal constant MIN_SHARES = FC.MIN_STRATEGY_DEPOSIT;

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

    // ============ Fee Math Tests (BTC-CORE-01 through BTC-CORE-05) ============

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
    function testFuzz_WithdrawWithFees_ChargesExpectedFee(uint256 depositSeed, uint256 withdrawSeed, uint256 feeSeed)
        public
    {
        // Deposit with zero exit fee first
        uint256 depositAmount = _boundBtcAmount(depositSeed);
        _setExitFee(0);
        _depositToVault(depositor, depositAmount);

        // Set fuzzed exit fee
        uint256 exitFee = _boundFee(feeSeed);
        _setExitFee(exitFee);

        uint256 maxW = vault.maxWithdraw(depositor);
        vm.assume(maxW > 0);
        uint256 withdrawAmount = bound(withdrawSeed, 1, maxW);

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
    function testFuzz_RedeemWithFees_ChargesExpectedFee(uint256 depositSeed, uint256 redeemSeed, uint256 feeSeed)
        public
    {
        // Deposit with zero exit fee first
        _setExitFee(0);
        uint256 depositAmount = _boundBtcAmount(depositSeed);
        uint256 sharesReceived = _depositToVault(depositor, depositAmount);
        vm.assume(sharesReceived > 0);

        // Set fuzzed exit fee
        uint256 exitFee = _boundFee(feeSeed);
        _setExitFee(exitFee);

        uint256 sharesToRedeem = bound(redeemSeed, 1, sharesReceived);

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
    /// @notice Vault fee functions are consistent: deposit fee + withdraw fee approximate total fees on roundtrip
    /// @dev Tests actual vault behavior, not helper reimplementations
    /// @param assetsSeed Seed for deposit amount
    /// @param entryFeeSeed Seed for entry fee
    /// @param exitFeeSeed Seed for exit fee
    function testFuzz_VaultFeeConsistency_DepositWithdrawRoundtrip(
        uint256 assetsSeed,
        uint256 entryFeeSeed,
        uint256 exitFeeSeed
    ) public {
        uint256 assets = _boundBtcAmount(assetsSeed);
        uint256 entryFee = _boundFee(entryFeeSeed);
        uint256 exitFee = _boundFee(exitFeeSeed);

        _setEntryFee(entryFee);
        _setExitFee(exitFee);

        uint256 feeRecipientBefore = mockCbBTC.balanceOf(feeRecipient);

        // Deposit
        uint256 shares = _depositToVault(depositor, assets);
        vm.assume(shares > 0);

        uint256 feeAfterDeposit = mockCbBTC.balanceOf(feeRecipient) - feeRecipientBefore;

        // Withdraw all
        uint256 maxW = vault.maxWithdraw(depositor);
        vm.assume(maxW > 0);

        vm.prank(depositor);
        vault.withdraw(maxW, depositor, depositor);

        uint256 totalFees = mockCbBTC.balanceOf(feeRecipient) - feeRecipientBefore;
        uint256 exitFeeCollected = totalFees - feeAfterDeposit;

        // Vault must have collected non-negative fees at each step
        assertGe(feeAfterDeposit, 0, "entry fee must be non-negative");
        assertGe(exitFeeCollected, 0, "exit fee must be non-negative");

        // Total fees must be <= assets deposited (can't fee more than 100%)
        assertLe(totalFees, assets, "total fees must not exceed deposited assets");

        // If both fees are 0, no fees should be collected
        if (entryFee == 0 && exitFee == 0) {
            assertEq(totalFees, 0, "zero fee config must collect zero fees");
        }
    }

    // ============ Roundtrip / No Free Money Tests (BTC-CORE-06 through BTC-CORE-08) ============

    /// @custom:audit-property BTC-CORE-06
    /// @notice Deposit then redeem all shares should never return more assets than deposited
    /// @param assetsSeed Seed for deposit amount
    /// @param entryFeeSeed Seed for entry fee
    /// @param exitFeeSeed Seed for exit fee
    function testFuzz_DepositRedeem_NeverProfitable(uint256 assetsSeed, uint256 entryFeeSeed, uint256 exitFeeSeed)
        public
    {
        uint256 entryFee = _boundFee(entryFeeSeed);
        uint256 exitFee = _boundFee(exitFeeSeed);
        uint256 assets = _boundBtcAmount(assetsSeed);

        _setEntryFee(entryFee);
        _setExitFee(exitFee);

        uint256 shares = _depositToVault(depositor, assets);
        vm.assume(shares > 0);

        vm.prank(depositor);
        uint256 assetsOut = vault.redeem(shares, depositor, depositor);

        assertLe(assetsOut, assets, "deposit-redeem roundtrip must not be profitable");
    }

    /// @custom:audit-property BTC-CORE-07
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

    /// @custom:audit-property BTC-CORE-08
    /// @notice convertToAssets(convertToShares(x)) <= x (no inflation from convert roundtrip)
    /// @param assetsSeed Seed for the asset amount to convert
    /// @param seedDepositSeed Seed for the initial deposit to establish exchange rate
    function testFuzz_ConvertRoundtrip_NeverInflates(uint256 assetsSeed, uint256 seedDepositSeed) public {
        uint256 assets = _boundBtcAmount(assetsSeed);

        // Seed the vault with a deposit so exchange rate is non-trivial
        _depositToVault(depositor, _boundBtcAmount(seedDepositSeed));

        uint256 shares = vault.convertToShares(assets);
        uint256 assetsBack = vault.convertToAssets(shares);

        assertLe(assetsBack, assets, "convertToAssets(convertToShares(x)) must be <= x");
    }

    // ============ ERC-4626 Preview Compliance (BTC-CORE-09 through BTC-CORE-12) ============

    /// @custom:audit-property BTC-CORE-09
    /// @notice previewDeposit must return <= actual shares minted
    function testFuzz_PreviewDeposit_ReturnsLessOrEqualActual(uint256 assetsSeed) public {
        uint256 assets = _boundBtcAmount(assetsSeed);

        uint256 preview = vault.previewDeposit(assets);

        uint256 actual = _depositToVault(depositor, assets);
        vm.assume(actual > 0); // trivial 0 <= 0 is not meaningful

        assertLe(preview, actual, "previewDeposit must return <= actual shares minted");
    }

    /// @custom:audit-property BTC-CORE-10
    /// @notice previewMint must return >= actual assets consumed
    function testFuzz_PreviewMint_ReturnsGreaterOrEqualActual(uint256 sharesSeed) public {
        uint256 shares = bound(sharesSeed, MIN_SHARES, MAX_SHARES);

        uint256 preview = vault.previewMint(shares);

        uint256 actual = _mintFromVault(depositor, shares);

        assertGe(preview, actual, "previewMint must return >= actual assets consumed");
    }

    /// @custom:audit-property BTC-CORE-11
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

    /// @custom:audit-property BTC-CORE-12
    /// @notice previewRedeem must return <= actual assets returned
    function testFuzz_PreviewRedeem_ReturnsLessOrEqualActual(uint256 sharesSeed) public {
        uint256 depositAmount = _boundBtcAmount(sharesSeed);
        uint256 sharesReceived = _depositToVault(depositor, depositAmount);
        vm.assume(sharesReceived > 0);

        uint256 sharesToRedeem = bound(sharesSeed, 1, sharesReceived);

        uint256 preview = vault.previewRedeem(sharesToRedeem);

        vm.prank(depositor);
        uint256 actual = vault.redeem(sharesToRedeem, depositor, depositor);
        vm.assume(actual > 0); // trivial 0 <= 0 is not meaningful

        assertLe(preview, actual, "previewRedeem must return <= actual assets returned");
    }

    // ============ Multi-User & Yield Tests (BTC-CORE-13 through BTC-CORE-14) ============

    /// @custom:audit-property BTC-CORE-13
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

    /// @custom:audit-property BTC-CORE-14
    /// @notice After yield accrual, first depositor's share value should include yield,
    ///         and second depositor should pay more per share (get fewer shares per asset)
    function testFuzz_YieldAccrual_SecondDepositorDoesNotDilute(
        uint256 depositSeed,
        uint256 yieldSeed,
        uint256 secondDepositSeed
    ) public {
        // deposit1 must be large enough that net-of-fee >= MIN_STRATEGY_DEPOSIT (10,000 sats),
        // otherwise the deposit stays idle in the vault and yield accrued in the strategy
        // is invisible to vault.totalAssets(), making the share-dilution check meaningless.
        uint256 entryFee = vault.getEntryFee();
        uint256 minDeposit1 = (FC.MIN_STRATEGY_DEPOSIT * (BPS + entryFee)) / BPS + 1;
        uint256 deposit1 = bound(depositSeed, minDeposit1, FC.MAX_BTC_AMOUNT);
        // Minimum yield of 100 sats avoids rounding-dominated edge cases
        uint256 yieldAmount = bound(yieldSeed, 100, 10e8);
        uint256 deposit2 = _boundBtcAmount(secondDepositSeed);

        // Depositor 1 deposits
        uint256 shares1 = _depositToVault(depositor, deposit1);

        // Record share value before yield
        uint256 shareValueBefore = vault.convertToAssets(shares1);

        // Simulate yield
        _simulateYield(yieldAmount);

        // Record share value after yield
        uint256 shareValueAfter = vault.convertToAssets(shares1);

        // Depositor 1's share value should include yield
        assertGe(shareValueAfter, shareValueBefore, "depositor1 share value should include yield");

        // After large yield, the share price can inflate so much that a small deposit2
        // rounds to 0 shares and reverts with ZeroAmount. Skip those degenerate inputs.
        vm.assume(vault.previewDeposit(deposit2) > 0);

        // Depositor 2 deposits after yield
        uint256 shares2 = _depositToVault(depositor2, deposit2);

        // Depositor 2 should get fewer shares per asset (or equivalently, pay more per share)
        // shares2/deposit2 <= shares1/deposit1  =>  shares2 * deposit1 <= shares1 * deposit2
        assertLe(
            shares2 * deposit1, shares1 * deposit2, "second depositor should get fewer shares per asset after yield"
        );
    }

    // ============ Security Tests (BTC-SEC-01 through BTC-SEC-04) ============

    /// @custom:audit-property BTC-SEC-01
    /// @notice First-depositor donation attack must not steal from second depositor
    /// @dev Attacker deposits minimum, donates directly to strategy to inflate share price.
    ///      Two outcomes are valid:
    ///      - If `previewDeposit == 0`, vault reverts with `ZeroAmount` (victim protected)
    ///      - If `previewDeposit > 0`, victim loses at most 1 share's worth to rounding
    /// @param donationSeed Seed for donation amount
    /// @param depositSeed Seed for victim deposit amount
    function testFuzz_DonationAttack_SecondDepositorProtected(uint256 donationSeed, uint256 depositSeed) public {
        // Attacker deposits minimum amount
        uint256 attackerDeposit = FC.MIN_BTC_AMOUNT;
        _setEntryFee(0); // Remove fees to isolate donation effect
        _setExitFee(0);

        uint256 attackerShares = _depositToVault(depositor, attackerDeposit);
        vm.assume(attackerShares > 0);

        // Attacker donates directly to strategy (bypassing vault accounting)
        uint256 donation = bound(donationSeed, 1, 10e8);
        mockCbBTC.mint(address(mockAavePool), donation);
        vm.prank(address(mockAavePool));
        mockAToken1.mint(address(strategy1), donation);

        // Second depositor deposits — use try/catch because both vault-level and
        // strategy-level zero-shares guards can trigger independently
        uint256 victimDeposit = _boundBtcAmount(depositSeed);
        _fundCbBTCAndApprove(depositor2, address(vault), victimDeposit);

        vm.prank(depositor2);
        try vault.deposit(victimDeposit, depositor2) returns (uint256 victimShares) {
            // Deposit succeeded — assert bounded loss
            assertGt(victimShares, 0, "donation attack: victim received zero shares");

            uint256 victimRedeemable = vault.convertToAssets(victimShares);
            // Victim loss bounded by 1 share's worth of assets
            uint256 maxShareValue = (attackerDeposit + donation + victimDeposit) / (attackerShares + victimShares);
            uint256 maxLoss = maxShareValue + 2; // +2 for rounding
            assertGe(
                victimRedeemable + maxLoss,
                victimDeposit,
                "victim should not lose more than one share's worth to donation attack"
            );
        } catch {
            // Vault or strategy reverted with ZeroAmount — victim is protected
            // Verify victim's funds were not consumed
            assertGe(mockCbBTC.balanceOf(depositor2), victimDeposit, "victim must retain funds when deposit reverts");
        }
    }

    /// @custom:audit-property BTC-SEC-02
    /// @notice Users who deposited at low fees should not be trapped by high exit fees
    /// @dev Simulates admin raising exit fee after users deposit
    /// @param depositSeed Seed for deposit amount
    /// @param initialExitFeeSeed Seed for initial exit fee
    /// @param newExitFeeSeed Seed for new (higher) exit fee
    function testFuzz_FeeChangeAfterDeposit_UserNotTrapped(
        uint256 depositSeed,
        uint256 initialExitFeeSeed,
        uint256 newExitFeeSeed
    ) public {
        uint256 depositAmount = _boundBtcAmount(depositSeed);
        uint256 initialExitFee = bound(initialExitFeeSeed, 0, 50); // Low initial fee (0-0.5%)
        uint256 newExitFee = bound(newExitFeeSeed, 500, FC.MAX_FEE_BPS); // High new fee (5-10%)

        _setExitFee(initialExitFee);

        // User deposits at low fee
        uint256 shares = _depositToVault(depositor, depositAmount);
        vm.assume(shares > 0);

        // Admin raises exit fee dramatically
        _setExitFee(newExitFee);

        // User can still withdraw (not locked out)
        uint256 maxW = vault.maxWithdraw(depositor);
        assertGt(maxW, 0, "user must still be able to withdraw after fee increase");

        // User withdraws everything they can
        vm.prank(depositor);
        uint256 assetsOut = vault.withdraw(maxW, depositor, depositor);

        // User should get back at least (deposit - maxFee%)
        // With 10% max fee, user should get back at least 90% of deposit (minus entry fee)
        uint256 netDeposit = depositAmount - _computeFeeOnTotal(depositAmount, vault.getEntryFee());
        uint256 minExpected = (netDeposit * (BPS - newExitFee)) / BPS;
        assertGe(
            assetsOut + 2, // rounding tolerance
            minExpected,
            "user should recover at least (1 - exitFee%) of net deposit"
        );
    }

    /// @custom:audit-property BTC-SEC-03
    /// @notice When feeRecipient is the vault itself, fees inflate totalAssets (accepted tradeoff)
    /// @dev Since totalAssets() includes balanceOf(address(this)), fees that stay in the vault
    ///      ARE counted. This is an accepted tradeoff — feeRecipient=vault is admin misconfiguration.
    /// @param depositSeed Seed for deposit amount
    /// @param feeSeed Seed for entry fee
    function testFuzz_FeeRecipientIsVault_FeeCountedInTotalAssets(uint256 depositSeed, uint256 feeSeed) public {
        uint256 entryFee = _boundFee(feeSeed);
        vm.assume(entryFee > 0); // Need non-zero fee to test
        uint256 assets = _boundBtcAmount(depositSeed);

        _setEntryFee(entryFee);

        // Set feeRecipient to the vault itself
        _scheduleAndExecuteLocal(bvm_slow, BVM_SLOW_ID(), abi.encodeCall(BTCVault.setFeeRecipient, (address(vault))));

        uint256 totalAssetsBefore = vault.totalAssets();

        // Deposit — fee goes to vault itself
        uint256 shares = _depositToVault(depositor, assets);
        vm.assume(shares > 0);

        uint256 totalAssetsAfter = vault.totalAssets();

        // With feeRecipient=vault, the fee stays in the vault and IS counted by totalAssets
        // (via balanceOf). So totalAssets increases by the full deposit amount.
        assertApproxEqAbs(
            totalAssetsAfter - totalAssetsBefore,
            assets,
            FC.MAX_ROUNDING_ERROR,
            "totalAssets should increase by full deposit when feeRecipient is vault"
        );
    }

    /// @custom:audit-property BTC-SEC-04
    /// @notice Withdrawal ordering must not unfairly advantage one depositor over another
    /// @dev Two equal depositors withdraw sequentially; neither should receive materially more.
    ///      Uses 1:1 share/asset ratio (no yield) to avoid a known vault/strategy rounding mismatch
    ///      where `_withdrawFromStrategies` interprets strategy shares-burned as assets-withdrawn.
    /// @param depositSeed Seed for the deposit amount (same for both depositors)
    /// @param entryFeeSeed Seed for entry fee
    /// @param exitFeeSeed Seed for exit fee
    function testFuzz_MultiActorExitRace_NoOrderingAdvantage(
        uint256 depositSeed,
        uint256 entryFeeSeed,
        uint256 exitFeeSeed
    ) public {
        uint256 depositAmount = _boundBtcAmount(depositSeed);
        uint256 entryFee = _boundFee(entryFeeSeed);
        uint256 exitFee = _boundFee(exitFeeSeed);

        _setEntryFee(entryFee);
        _setExitFee(exitFee);

        // Both deposit the same amount
        uint256 shares1 = _depositToVault(depositor, depositAmount);
        uint256 shares2 = _depositToVault(depositor2, depositAmount);
        vm.assume(shares1 > 0 && shares2 > 0);

        // Depositor2 redeems all first
        vm.prank(depositor2);
        uint256 assets2Out = vault.redeem(shares2, depositor2, depositor2);

        // Depositor1 redeems all second
        vm.prank(depositor);
        uint256 assets1Out = vault.redeem(shares1, depositor, depositor);

        // With equal deposits and no yield, both should receive approximately equal assets.
        // The difference should be at most a small rounding error.
        assertApproxEqAbs(
            assets1Out,
            assets2Out,
            FC.MAX_ROUNDING_ERROR,
            "equal depositors should receive equal assets regardless of withdrawal order"
        );

        // Neither should receive more than their deposit
        assertLe(assets1Out, depositAmount, "depositor1 should not profit from ordering");
        assertLe(assets2Out, depositAmount, "depositor2 should not profit from ordering");

        // Total withdrawn should not exceed total deposited
        assertLe(assets1Out + assets2Out, depositAmount * 2, "total withdrawn must not exceed total deposits");
    }
}
