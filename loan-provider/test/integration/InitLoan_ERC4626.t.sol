// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.30;

import {IntegrationTestBase} from "../base/IntegrationTestBase.sol";
import {TestConstants as TC} from "../helpers/TestConstants.sol";
import {DataTypes} from "@bitmor/libraries/types/DataTypes.sol";
import {IERC20} from "@openzeppelin/interfaces/IERC20.sol";

/// @title InitLoan_ERC4626Test
/// @notice Adversarial ERC-4626 vault integration tests for the Loan initialization flow.
/// @dev Failing tests represent security findings, NOT test bugs.
///      These tests verify BTCVault resilience against share inflation attacks,
///      minimum collateral rounding exploits, and round-trip conversion precision loss.
contract InitLoan_ERC4626Test is IntegrationTestBase {
    // ============ Constants ============

    uint256 constant MAX_ROUNDING_LOSS_SATOSHI = 100;
    uint256 constant SHARE_PRICE_IMPACT_TOLERANCE = 0.01e18; // 1%

    // ============ Setup ============

    function setUp() public override {
        super.setUp();
        _setupTestUser();
    }

    // ============ Test 24: First Depositor Inflation Attack ============

    /// @notice Classic ERC-4626 inflation attack: attacker inflates share price via donation
    ///         then victim deposits and loses value to rounding.
    /// @dev Security finding if victim receives 0 shares or an unhealthy loan after inflation.
    function test_ERC4626_FirstDepositorAttack_BTCVault() public {
        // Arrange - Step 1: Attacker creates first loan with minimum collateral
        address lsaAttacker = _createLoan(TC.MIN_COLLATERAL, TC.STANDARD_DURATION, TC.PREMIUM_AMOUNT);

        // Arrange - Step 2: Donate cbBTC to strategy to inflate share price
        address strategyAddr = config.getAaveTokenizedStrategy();
        uint256 donationAmount = TC.USER_CBBTC_BALANCE;
        address donator = makeAddr("donator");
        _fundCbBTC(donator, donationAmount);

        vm.prank(donator);
        cbBTC.approve(aaveV3Pool, donationAmount);

        vm.prank(donator);
        (bool ok,) = aaveV3Pool.call(
            abi.encodeWithSignature(
                "supply(address,uint256,address,uint16)", address(cbBTC), donationAmount, strategyAddr, 0
            )
        );
        require(ok, "strategy donation supply failed");

        // Arrange - Step 3: Verify inflation occurred
        uint256 inflatedAssets = btcVault.convertToAssets(1e8);
        assertGt(inflatedAssets, 1e8, "share price should be inflated after donation");

        // Arrange - Step 4: Advance time for unique salt
        vm.warp(block.timestamp + 1);

        // Act - Victim creates loan with standard collateral into the inflated vault
        address lsaVictim = _createLoan(TC.STANDARD_COLLATERAL, TC.STANDARD_DURATION, TC.PREMIUM_AMOUNT);

        // Assert - Victim must receive non-zero shares
        uint256 shares = btcVault.balanceOf(lsaVictim);
        assertGt(shares, 0, "BTCVault must protect against inflation attack via strategy donation");

        // Assert - Victim loan must remain healthy
        (,, uint256 healthFactor) = _getUserAccountData(lsaVictim);
        assertGt(healthFactor, 1e18, "victim loan must be healthy after inflated deposit");
    }

    // ============ Test 25: Minimum Collateral Rounding Exploitation ============

    /// @notice Verifies that the smallest allowed collateral produces a healthy loan
    ///         despite entry fees and vault rounding.
    /// @dev Security finding if min collateral loans are immediately unhealthy.
    function test_ERC4626_MinCollateralRoundingExploitation() public {
        // Act - Create loan with the absolute minimum collateral
        address lsa = _createLoan(TC.MIN_COLLATERAL, TC.STANDARD_DURATION, TC.PREMIUM_AMOUNT);

        // Assert - Loan must be healthy even at minimum collateral
        (,, uint256 healthFactor) = _getUserAccountData(lsa);
        assertGt(healthFactor, 1e18, "min collateral loan must be healthy after entry fees and rounding");
    }

    // ============ Test 26: Large Deposit Rounding Accumulation ============

    /// @notice Verifies that share<->asset round-trip conversions do not lose
    ///         more than dust after yield injection creates a non-round share price.
    /// @dev Security finding if rounding loss exceeds MAX_ROUNDING_LOSS_SATOSHI.
    function test_ERC4626_LargeDepositRoundingAccumulation() public {
        // Arrange - Inject yield to create a non-round share price
        address strategyAddr = config.getAaveTokenizedStrategy();
        uint256 yieldAmount = 1e8; // 1 BTC of yield
        address donator = makeAddr("yieldDonator");
        _fundCbBTC(donator, yieldAmount);

        vm.prank(donator);
        cbBTC.approve(aaveV3Pool, yieldAmount);

        vm.prank(donator);
        (bool ok,) = aaveV3Pool.call(
            abi.encodeWithSignature(
                "supply(address,uint256,address,uint16)", address(cbBTC), yieldAmount, strategyAddr, 0
            )
        );
        require(ok, "yield injection supply failed");

        // Act - Create loan with standard collateral into yield-shifted vault
        address lsa = _createLoan(TC.STANDARD_COLLATERAL, TC.STANDARD_DURATION, TC.PREMIUM_AMOUNT);

        // Assert - Round-trip conversion must not lose more than dust
        uint256 shares = btcVault.balanceOf(lsa);
        assertGt(shares, 0, "loan must receive non-zero shares");

        uint256 assetsFromShares = btcVault.convertToAssets(shares);
        uint256 sharesFromAssets = btcVault.convertToShares(assetsFromShares);

        // shares -> assets -> shares should be lossless or near-lossless
        assertApproxEqAbs(
            sharesFromAssets,
            shares,
            MAX_ROUNDING_LOSS_SATOSHI,
            "round-trip conversion must not lose more than dust"
        );
    }
}
