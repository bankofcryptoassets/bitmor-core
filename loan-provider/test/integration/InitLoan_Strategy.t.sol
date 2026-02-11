// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.30;

import {IntegrationTestBase} from "../base/IntegrationTestBase.sol";
import {TestConstants as TC} from "../helpers/TestConstants.sol";
import {DataTypes} from "@bitmor/libraries/types/DataTypes.sol";
import {IERC20} from "@openzeppelin/interfaces/IERC20.sol";

/// @title InitLoan_StrategyTest
/// @notice Adversarial integration tests probing strategy-level attacks on loan health factors.
///         Failing tests are security findings, NOT test bugs.
contract InitLoan_StrategyTest is IntegrationTestBase {
    // ============ Setup ============

    function setUp() public override {
        super.setUp();
        _setupTestUser();
    }

    // ============ Helpers ============

    /// @notice Donates cbBTC to the AaveTokenizedStrategy by supplying to the external Aave pool
    ///         on behalf of the strategy address, inflating the strategy's aToken balance.
    /// @param amount The amount of cbBTC (8 decimals) to donate
    function _donateToStrategy(uint256 amount) internal {
        address strategyAddr = config.getAaveTokenizedStrategy();
        address donator = makeAddr("strategyDonator");
        _fundCbBTC(donator, amount);

        vm.prank(donator);
        cbBTC.approve(aaveV3Pool, amount);

        vm.prank(donator);
        (bool ok,) = aaveV3Pool.call(
            abi.encodeWithSignature(
                "supply(address,uint256,address,uint16)", address(cbBTC), amount, strategyAddr, 0
            )
        );
        require(ok, "strategy donation via aave supply failed");
    }

    /// @notice External wrapper for try/catch (Solidity requires external calls for try/catch)
    function createMinCollateralLoan() external returns (address lsa) {
        lsa = _createLoan(TC.MIN_COLLATERAL, TC.STANDARD_DURATION, TC.PREMIUM_AMOUNT);
    }

    // ============ Test 27: Strategy loss immediately after init ============

    /// @notice Strategy loss immediately after loan initialization should decrease the health factor.
    ///         A minimum-collateral loan is most vulnerable: even a moderate loss can push HF below 1.
    ///         This tests whether the protocol properly reflects strategy losses in health factor
    ///         calculations, i.e., the oracle/vault accounting correctly propagates reduced totalAssets.
    function test_Strategy_LossRightAfterInit_InstantUndercollateralization() public {
        // Arrange - create loan at boundary (minimum collateral)
        address lsa;
        try this.createMinCollateralLoan() returns (address _lsa) {
            lsa = _lsa;
        } catch {
            // If min collateral loan reverts, use standard collateral instead
            lsa = _createStandardLoan();
        }

        (,, uint256 healthFactorBefore) = _getUserAccountData(lsa);
        assertGt(healthFactorBefore, 1e18, "loan must be healthy at creation");

        // Act - simulate strategy loss by withdrawing cbBTC from strategy's Aave position
        // We prank as the strategy to call withdraw on the external Aave pool,
        // draining 50% of the vault's total assets to an unrelated address.
        address strategyAddr = config.getAaveTokenizedStrategy();
        uint256 totalAssetsBefore = btcVault.totalAssets();
        uint256 lossAmount = totalAssetsBefore / 2; // 50% loss

        vm.prank(strategyAddr);
        (bool ok,) = aaveV3Pool.call(
            abi.encodeWithSignature(
                "withdraw(address,uint256,address)", address(cbBTC), lossAmount, makeAddr("drain")
            )
        );
        require(ok, "strategy loss simulation via aave withdraw failed");

        // Assert - health factor must decrease after strategy loss
        (,, uint256 healthFactorAfter) = _getUserAccountData(lsa);

        assertLt(
            healthFactorAfter,
            healthFactorBefore,
            "FINDING: strategy loss must decrease health factor - vault accounting not propagating losses"
        );

        // Additional: if HF dropped below 1, the loan is instantly liquidatable from a strategy loss.
        // This is expected behavior for min collateral, but worth documenting.
        if (healthFactorAfter < 1e18) {
            // This is an expected consequence for boundary loans with 50% strategy loss.
            // The protocol should have mechanisms to handle this (e.g., emergency pause).
            assertTrue(true, "min collateral loan is liquidatable after 50% strategy loss (expected)");
        }
    }

    // ============ Test 28: Artificial yield injection prevents liquidation ============

    /// @notice A near-liquidation loan should NOT be rescued by injecting yield into the strategy.
    ///         If donating cbBTC to the strategy inflates the share price enough to push HF above 1,
    ///         an attacker could prevent legitimate liquidations by donating to the strategy.
    ///         assertLe(healthFactorAfterDonation, 1e18) FAILS if donation rescues the loan = finding.
    function test_Strategy_ArtificialYieldInjection_PreventsLiquidation() public {
        // Arrange - create loan with standard collateral
        address lsa = _createStandardLoan();

        // Drop price to make the loan liquidatable (HF < 1e18)
        (, int256 currentPrice,,,) = btcOracle.latestRoundData();
        require(currentPrice > 0, "oracle price must be positive");

        // Drop by 40% first
        int256 droppedPrice = currentPrice * 60 / 100;
        btcOracle.updateAnswer(droppedPrice);

        (,, uint256 healthFactorDropped) = _getUserAccountData(lsa);

        // If HF is still above 1e18 after 40% drop, drop more aggressively
        if (healthFactorDropped >= 1e18) {
            droppedPrice = currentPrice * 40 / 100;
            btcOracle.updateAnswer(droppedPrice);
            (,, healthFactorDropped) = _getUserAccountData(lsa);
        }

        // If still above 1e18 after 60% drop, use extreme drop
        if (healthFactorDropped >= 1e18) {
            droppedPrice = currentPrice * 20 / 100;
            btcOracle.updateAnswer(droppedPrice);
            (,, healthFactorDropped) = _getUserAccountData(lsa);
        }

        // Precondition: loan must be undercollateralized (HF < 1e18)
        assertLt(
            healthFactorDropped,
            1e18,
            "precondition failed: could not push loan below liquidation threshold via price drop"
        );

        // Act - attempt to rescue the loan by donating cbBTC to the strategy
        // This inflates the strategy's aToken balance, which increases share price,
        // which could increase the oracle valuation of the collateral.
        _donateToStrategy(TC.USER_CBBTC_BALANCE);

        // Assert - health factor must remain at or below 1e18
        // If donation pushes HF above 1, the strategy is a liquidation prevention vector.
        (,, uint256 healthFactorAfterDonation) = _getUserAccountData(lsa);

        assertLe(
            healthFactorAfterDonation,
            1e18,
            "FINDING: strategy donation rescued undercollateralized loan - artificial yield prevents liquidation"
        );
    }
}
