// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.30;

import {IntegrationTestBase} from "../base/IntegrationTestBase.sol";
import {TestConstants as TC} from "../helpers/TestConstants.sol";
import {DataTypes} from "@bitmor/libraries/types/DataTypes.sol";

/// @title InitLoan_OracleTest
/// @author Bitmor Protocol
/// @notice Adversarial integration tests for oracle edge cases during loan initialization
/// @dev Failing tests = security findings, NOT test bugs. Do NOT weaken assertions.
contract InitLoan_OracleTest is IntegrationTestBase {
    // ============ Constants ============

    uint256 constant STALE_THRESHOLD_SECONDS = 7200; // 2 hours
    int256 constant INFLATED_BTC_PRICE = 500_000e8; // 5x normal ($500k)
    uint256 constant PRICE_DROP_30_PERCENT = 30;

    // ============ Setup ============

    function setUp() public override {
        super.setUp();
        _setupTestUser();
    }

    // ============ Test 13: Stale Oracle Price ============

    /// @notice System MUST reject stale oracle prices during loan initialization.
    /// @dev If this test fails (loan succeeds with stale price), it is a FINDING:
    ///      the protocol has no staleness check and accepts arbitrarily old oracle data,
    ///      allowing collateral to be valued at a price that no longer reflects reality.
    function test_Oracle_StalePrice_AllowsOvervaluedCollateral() public {
        // Arrange - make oracle stale by 2 hours
        btcOracle.makeStale(STALE_THRESHOLD_SECONDS);

        // Act + Assert - system MUST reject stale prices
        vm.expectRevert();
        _createStandardLoan();
        // If vm.expectRevert() does not match (i.e., loan succeeds), the test fails.
        // FINDING: loan created with stale oracle price -- no staleness check.
    }

    // ============ Test 14: Zero Oracle Price ============

    /// @notice System MUST revert when oracle returns zero price.
    /// @dev A zero price means infinite collateral value or division-by-zero.
    ///      If loan creation succeeds, the protocol is dangerously misconfigured.
    function test_Oracle_ZeroPrice_LoanInitReverts() public {
        // Arrange - set BTC price to zero
        btcOracle.updateAnswer(0);

        // Act + Assert - system MUST reject zero price
        vm.expectRevert();
        _createStandardLoan();
    }

    // ============ Test 15: Sudden Price Jump - Loan Terms Bounded ============

    /// @notice Verifies that a 5x oracle price inflation produces loan terms that become
    ///         undercollateralized once the price corrects. Demonstrates oracle manipulation risk.
    function test_Oracle_SuddenPriceJump_LoanTermsBounded() public {
        // Arrange - capture reference loan at normal price
        (, int256 normalPrice,,,) = btcOracle.latestRoundData();
        uint256 snapshotId = vm.snapshot();

        address refLsa = _createStandardLoan();
        (uint256 refCollateral, uint256 refDebt, uint256 refHealthFactor) = _getUserAccountData(refLsa);

        // Revert to pre-loan state
        vm.revertTo(snapshotId);

        // Act - inflate oracle price to 5x and create same loan
        btcOracle.updateAnswer(INFLATED_BTC_PRICE);

        address inflatedLsa = _createStandardLoan();
        (uint256 inflatedCollateral, uint256 inflatedDebt, uint256 inflatedHealthFactor) =
            _getUserAccountData(inflatedLsa);

        // Assert - sanity: inflated collateral valuation must exceed reference
        assertGt(
            inflatedCollateral,
            refCollateral,
            "inflated collateral valuation must exceed reference at normal price"
        );

        // Assert - health factor at inflated price must be above 1 (loan appears healthy)
        assertGt(inflatedHealthFactor, TC.PRECISION, "health factor at inflated price must be above 1e18");

        // Act - correct oracle back to normal price
        btcOracle.updateAnswer(normalPrice);

        // Assert - health factor must decrease once price corrects
        (, uint256 correctedDebt, uint256 correctedHealthFactor) = _getUserAccountData(inflatedLsa);
        assertLt(
            correctedHealthFactor,
            inflatedHealthFactor,
            "health factor must decrease when inflated price corrects to normal"
        );
    }

    // ============ Test 16: Different Price Keys - cbBTC vs bvBTC ============

    /// @notice Verifies that a cbBTC price drop propagates through to bvBTC oracle price
    ///         and impacts health factor. The BLP oracle prices bvBTC based on the underlying
    ///         cbBTC price; if these are decoupled, collateral can be mispriced.
    function test_Oracle_DifferentPriceKeys_CbBTC_Vs_BvBTC() public {
        // Arrange - create loan and capture baseline
        address lsa = _createStandardLoan();
        (, uint256 debtBefore, uint256 healthFactorBefore) = _getUserAccountData(lsa);
        uint256 bvBTCPriceBefore = _getOraclePrice(address(btcVault));

        // Act - drop cbBTC price by 30%
        (, int256 currentBtcPrice,,,) = btcOracle.latestRoundData();
        int256 droppedPrice = currentBtcPrice * int256(100 - PRICE_DROP_30_PERCENT) / 100;
        btcOracle.updateAnswer(droppedPrice);

        // Assert - bvBTC oracle price must reflect cbBTC drop
        uint256 bvBTCPriceAfter = _getOraclePrice(address(btcVault));
        assertLt(
            bvBTCPriceAfter,
            bvBTCPriceBefore,
            "cbBTC drop must propagate to bvBTC oracle price"
        );

        // Assert - health factor must decrease after BTC price drop
        (, uint256 debtAfter, uint256 healthFactorAfter) = _getUserAccountData(lsa);
        assertLt(
            healthFactorAfter,
            healthFactorBefore,
            "health factor must decrease after BTC price drop"
        );
    }
}
