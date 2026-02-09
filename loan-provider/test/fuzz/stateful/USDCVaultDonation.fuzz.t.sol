// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {USDCVaultFuzzTestBase} from "../base/USDCVaultFuzzTestBase.sol";
import {FuzzConstants as FC} from "../helpers/FuzzConstants.sol";

/// @title USDCVaultDonationFuzzTest
/// @author Bitmor Protocol
/// @notice Fuzz tests for ERC-4626 donation/inflation attack resistance
/// @dev Verifies that direct USDC transfers to the vault cannot be used to
///      manipulate share pricing or extract value from other depositors.
///      USDCVault's `totalAssets()` includes idle vault balance, making it
///      a potential target. Solady's virtual shares (offset +1) mitigate this.
///
///      **FINDING:** USDCVault uses Solady's default `_decimalsOffset() = 0`,
///      which provides +1 virtual shares/assets offset. This means:
///      - Deposits smaller than the donation amount can round to 0 shares (total loss)
///      - Even when shares > 0, the maximum rounding loss per depositor is bounded by
///        approximately `donation / totalAssets`, which can be significant
///      Consider overriding `_decimalsOffset()` to return 6 (matching USDC decimals)
///      for stronger protection against donation attacks.
///
/// ## Test Coverage
/// - USDC-41: Victim recovers deposit after donation attack (loss bounded by donation/deposit ratio)
/// - USDC-42: Attacker cannot extract more than their total capital (deposit + donation)
/// - USDC-43: convertToAssets(convertToShares(x)) <= x even with donated balance
/// - USDC-44: First depositor after large donation is protected (loss bounded)
///
/// @custom:audit-category ERC-4626 Security, Donation Attack Resistance
contract USDCVaultDonationFuzzTest is USDCVaultFuzzTestBase {
    address internal attacker;
    address internal victim;

    function setUp() public override {
        super.setUp();
        attacker = makeAddr("ATTACKER");
        victim = makeAddr("VICTIM");
    }

    /// @notice Victim deposits after attacker donates. Victim's loss is bounded by donation/deposit ratio.
    /// @dev Attack vector: attacker sends USDC directly to vault, inflating totalAssets().
    ///      Victim then deposits and redeems. With Solady virtual shares (offset=0),
    ///      the maximum loss is approximately `donation / (donation + deposit + 1)`.
    /// @param donationSeed Seed for donation amount (1 USDC to 100k USDC)
    /// @param victimDepositSeed Seed for victim deposit amount (must be >= donation)
    /// @custom:audit-property USDC-41: Victim loss bounded by donation/deposit ratio
    /// @custom:audit-category ERC-4626 Security
    /// @custom:audit-severity Critical
    function testFuzz_DonationAttack_VictimRecovery(
        uint256 donationSeed,
        uint256 victimDepositSeed
    ) public {
        uint256 donationAmount = bound(donationSeed, 1e6, 100_000e6);
        // Deposit > donation ensures shares > 0 (Solady offset=0: shares = deposit / (donation+1))
        uint256 victimDeposit = bound(victimDepositSeed, donationAmount + 1, FC.MAX_USDC_AMOUNT);

        // Attacker donates directly to vault (bypasses deposit)
        mockUSDC.mint(address(vault), donationAmount);

        // Victim deposits normally
        uint256 victimShares = _depositToVault(victim, victimDeposit);
        assertGt(victimShares, 0, "victim should receive shares");

        // Victim immediately redeems
        vm.prank(victim);
        uint256 assetsReturned = vault.redeem(victimShares, victim, victim);

        // Maximum loss is bounded by donation / totalAssets ≈ donation / (donation + deposit)
        // We add a 1% buffer on top for rounding effects
        uint256 maxLossFromDonation = (victimDeposit * donationAmount) / (donationAmount + victimDeposit);
        uint256 roundingBuffer = victimDeposit / 100; // 1% rounding buffer
        uint256 maxAcceptableLoss = maxLossFromDonation + roundingBuffer;

        assertGe(
            assetsReturned,
            victimDeposit > maxAcceptableLoss ? victimDeposit - maxAcceptableLoss : 0,
            "victim loss should be bounded by donation/deposit ratio"
        );
    }

    /// @notice Attacker cannot extract more than their total capital committed (deposit + donation)
    /// @dev Attacker donates X, deposits Y (where Y >= X to get shares), victim deposits Z,
    ///      attacker redeems. The attacker's return should not exceed their deposit + donation.
    /// @param donationSeed Seed for donation amount
    /// @param attackerDepositSeed Seed for attacker deposit amount
    /// @param victimDepositSeed Seed for victim deposit amount
    /// @custom:audit-property USDC-42: Attacker return bounded by total capital committed
    /// @custom:audit-category ERC-4626 Security
    /// @custom:audit-severity Critical
    function testFuzz_DonationAttack_AttackerNoProfit(
        uint256 donationSeed,
        uint256 attackerDepositSeed,
        uint256 victimDepositSeed
    ) public {
        uint256 donationAmount = bound(donationSeed, 1e6, 50_000e6);
        // Deposits must be large enough to get meaningful shares
        uint256 attackerDeposit = bound(attackerDepositSeed, donationAmount * 2, FC.MAX_USDC_AMOUNT / 2);
        uint256 victimDeposit = bound(victimDepositSeed, donationAmount * 2, FC.MAX_USDC_AMOUNT / 2);

        // Step 1: Attacker donates to inflate share price
        mockUSDC.mint(address(vault), donationAmount);

        // Step 2: Attacker deposits normally
        uint256 attackerShares = _depositToVault(attacker, attackerDeposit);
        assertGt(attackerShares, 0, "attacker should receive shares");

        // Step 3: Victim deposits (target of the attack)
        _depositToVault(victim, victimDeposit);

        // Step 4: Attacker redeems
        vm.prank(attacker);
        uint256 attackerReturned = vault.redeem(attackerShares, attacker, attacker);

        // Attacker's return must not exceed their total committed capital
        uint256 totalCapitalCommitted = attackerDeposit + donationAmount;
        assertLe(
            attackerReturned,
            totalCapitalCommitted,
            "attacker should not profit beyond total capital committed (deposit + donation)"
        );
    }

    /// @notice Conversion roundtrip must not create free money even with donated balance
    /// @dev Even after a large donation inflates totalAssets, convertToAssets(convertToShares(x)) <= x
    /// @param donationSeed Seed for donation amount
    /// @param assetsSeed Seed for conversion amount
    /// @custom:audit-property USDC-43: No free money from conversion roundtrip after donation
    /// @custom:audit-category ERC-4626 Security
    /// @custom:audit-severity Critical
    function testFuzz_DonationAttack_ConversionInvariant(
        uint256 donationSeed,
        uint256 assetsSeed
    ) public {
        uint256 donationAmount = bound(donationSeed, 1e6, 100_000e6);
        uint256 assets = _boundUsdcAmount(assetsSeed);

        // Donate to vault
        mockUSDC.mint(address(vault), donationAmount);

        // Establish share price with a legitimate deposit
        _depositToVault(depositor, FC.MIN_USDC_AMOUNT);

        // Conversion roundtrip must not create value
        uint256 shares = vault.convertToShares(assets);
        uint256 assetsBack = vault.convertToAssets(shares);

        assertLe(assetsBack, assets, "conversion roundtrip must not create free money after donation");
    }

    /// @notice First depositor after a large donation is protected (loss bounded by ratio)
    /// @dev With an empty vault and large donation, the first deposit should still receive fair shares.
    ///      Solady's virtual shares (offset +1) provides protection proportional to the offset.
    ///      Deposit must be >= donation to avoid zero-share rounding.
    /// @param donationSeed Seed for donation amount
    /// @param firstDepositSeed Seed for first deposit amount
    /// @custom:audit-property USDC-44: First depositor after large donation is protected
    /// @custom:audit-category ERC-4626 Security
    /// @custom:audit-severity Critical
    function testFuzz_DonationAttack_FirstDepositorProtected(
        uint256 donationSeed,
        uint256 firstDepositSeed
    ) public {
        uint256 donationAmount = bound(donationSeed, 1_000e6, 1_000_000e6);
        // Deposit > donation to receive non-zero shares with offset=0
        uint256 firstDeposit = bound(firstDepositSeed, donationAmount + 1, FC.MAX_USDC_AMOUNT);

        // Large donation to empty vault
        mockUSDC.mint(address(vault), donationAmount);

        // First depositor
        uint256 shares = _depositToVault(depositor, firstDeposit);
        assertGt(shares, 0, "first depositor must receive non-zero shares even after donation");

        // Redeem should return close to deposit (loss bounded by donation/deposit ratio)
        vm.prank(depositor);
        uint256 returned = vault.redeem(shares, depositor, depositor);

        // Loss is bounded by donation / (donation + deposit) + rounding
        uint256 maxLossFromDonation = (firstDeposit * donationAmount) / (donationAmount + firstDeposit);
        uint256 roundingBuffer = firstDeposit / 100; // 1% rounding buffer
        uint256 maxAcceptableLoss = maxLossFromDonation + roundingBuffer;

        assertGe(
            returned,
            firstDeposit > maxAcceptableLoss ? firstDeposit - maxAcceptableLoss : 0,
            "first depositor should not be exploited beyond donation/deposit ratio"
        );
    }
}
