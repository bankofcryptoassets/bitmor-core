// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.30;

import {BaseLoanTest} from "./BaseLoan.t.sol";
import {Errors} from "@bitmor/libraries/helpers/Errors.sol";
import {Loan} from "@bitmor/protocol/Loan.sol";
import {ILoan} from "@bitmor/interfaces/ILoan.sol";
import {TestConstants as TC} from "../../helpers/TestConstants.sol";
import {Vm} from "forge-std/Vm.sol";

/// @title OracleFreshnessTest
/// @author Bitmor Protocol
/// @notice Tests oracle freshness validation across all BTC price call sites
contract OracleFreshnessTest is BaseLoanTest {
    /// @notice Cached deposit amount computed while oracle is fresh, for use in staleness tests
    uint256 internal cachedMinDeposit;

    function setUp() public override {
        super.setUp();

        // Override the generous base staleness (365 days) with the real production value (1 hour)
        // This allows testing that staleness validation actually works
        bytes memory data = abi.encodeWithSelector(Loan.setMaxOracleStaleness.selector, TC.MAX_ORACLE_STALENESS);
        _scheduleAndExecute(address(loan), lpm_slow, LPM_SLOW_ID(), data);

        // Refresh Chainlink oracle timestamp after the time warp from _scheduleAndExecute
        mockChainlinkBTC.updateAnswer(int256(BTC_PRICE));

        // Cache the minimum deposit while oracle is still fresh
        // (getLoanDetails will revert when oracle is stale, so we compute it upfront)
        (,, cachedMinDeposit) = loan.getLoanDetails(STANDARD_COLLATERAL_AMOUNT, STANDARD_DURATION);
    }

    // ============ initializeLoan Staleness Tests ============

    /// @notice Verifies initializeLoan reverts when BTC oracle is stale
    function test_initializeLoan_RevertWhen_OracleStale() public {
        mockChainlinkBTC.makeStale(TC.STALE_ORACLE_SECONDS);

        vm.expectRevert(Errors.StaleOraclePrice.selector);
        vm.prank(user);
        loan.initializeLoan(cachedMinDeposit, PREMIUM_AMOUNT, STANDARD_COLLATERAL_AMOUNT, STANDARD_DURATION, "");
    }

    /// @notice Verifies initializeLoan succeeds with fresh oracle
    function test_initializeLoan_SucceedsWhen_OracleFresh() public {
        vm.prank(user);
        address lsa =
            loan.initializeLoan(cachedMinDeposit, PREMIUM_AMOUNT, STANDARD_COLLATERAL_AMOUNT, STANDARD_DURATION, "");
        assertTrue(lsa != address(0), "loan should be created with fresh oracle");
    }

    // ============ closeLoan Staleness Tests ============

    /// @notice Verifies closeLoan reverts when BTC oracle is stale
    function test_closeLoan_RevertWhen_OracleStale() public {
        address lsa = _createStandardLoan();

        mockChainlinkBTC.makeStale(TC.STALE_ORACLE_SECONDS);

        vm.expectRevert(Errors.StaleOraclePrice.selector);
        vm.prank(user);
        loan.closeLoan(lsa, false);
    }

    // ============ getLoanDetails Staleness Tests ============

    /// @notice Verifies getLoanDetails reverts when BTC oracle is stale
    function test_getLoanDetails_RevertWhen_OracleStale() public {
        mockChainlinkBTC.makeStale(TC.STALE_ORACLE_SECONDS);

        vm.expectRevert(Errors.StaleOraclePrice.selector);
        loan.getLoanDetails(STANDARD_COLLATERAL_AMOUNT, STANDARD_DURATION);
    }

    /// @notice Verifies getLoanDetails succeeds with fresh oracle
    function test_getLoanDetails_SucceedsWhen_OracleFresh() public view {
        (uint256 loanAmt, uint256 monthlyPay, uint256 minDeposit) =
            loan.getLoanDetails(STANDARD_COLLATERAL_AMOUNT, STANDARD_DURATION);
        assertGt(loanAmt, 0, "loan amount should be positive");
        assertGt(monthlyPay, 0, "monthly payment should be positive");
        assertGt(minDeposit, 0, "min deposit should be positive");
    }

    // ============ calculateStrikePrice Staleness Tests ============

    /// @notice Verifies calculateStrikePrice reverts when BTC oracle is stale
    function test_calculateStrikePrice_RevertWhen_OracleStale() public {
        mockChainlinkBTC.makeStale(TC.STALE_ORACLE_SECONDS);

        vm.expectRevert(Errors.StaleOraclePrice.selector);
        loan.calculateStrikePrice(50_000e6, 20_000e6);
    }

    // ============ Source address(0) Skips Freshness ============

    /// @notice Verifies freshness check is skipped when source is address(0)
    function test_oracleFreshness_SkipsWhen_NoChainlinkSource() public {
        // Remove Chainlink source for bvBTC to test address(0) skip behavior
        mockOracle.setSourceOfAsset(address(mockBTCVault), address(0));

        // Make the Chainlink oracle stale to ensure source(0) path doesn't check freshness
        mockChainlinkBTC.makeStale(TC.STALE_ORACLE_SECONDS);

        // getLoanDetails calls getValidatedPrice on collateralAsset (bvBTC)
        // With source=address(0), OracleLogic skips freshness check - should not revert
        (uint256 loanAmt,,) = loan.getLoanDetails(STANDARD_COLLATERAL_AMOUNT, STANDARD_DURATION);
        assertGt(loanAmt, 0, "should work when source is address(0)");
    }

    // ============ Admin Setter Tests ============

    /// @notice Verifies setMaxOracleStaleness updates the value
    function test_setMaxOracleStaleness_UpdatesValue() public {
        uint256 newStaleness = 7200;

        bytes memory data = abi.encodeWithSelector(Loan.setMaxOracleStaleness.selector, newStaleness);
        _scheduleAndExecute(address(loan), lpm_slow, LPM_SLOW_ID(), data);

        assertEq(loan.getMaxOracleStaleness(), newStaleness, "staleness should be updated");
    }

    /// @notice Verifies setMaxOracleStaleness emits event
    function test_setMaxOracleStaleness_EmitsEvent() public {
        uint256 newStaleness = 7200;

        bytes memory data = abi.encodeWithSelector(Loan.setMaxOracleStaleness.selector, newStaleness);

        vm.recordLogs();
        _scheduleAndExecute(address(loan), lpm_slow, LPM_SLOW_ID(), data);

        Vm.Log[] memory entries = vm.getRecordedLogs();

        // Find the Loan__MaxOracleStalenessUpdated event in the recorded logs
        bytes32 expectedTopic = keccak256("Loan__MaxOracleStalenessUpdated(uint256)");
        bool found = false;
        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].topics[0] == expectedTopic) {
                // Verify the indexed parameter matches
                assertEq(uint256(entries[i].topics[1]), newStaleness, "event should contain the new staleness value");
                found = true;
                break;
            }
        }
        assertTrue(found, "Loan__MaxOracleStalenessUpdated event should have been emitted");
    }

    /// @notice Verifies setMaxOracleStaleness reverts when zero
    function test_setMaxOracleStaleness_RevertWhen_Zero() public {
        bytes memory data = abi.encodeWithSelector(Loan.setMaxOracleStaleness.selector, 0);

        _scheduleAndExpectRevert(
            address(loan), lpm_slow, LPM_SLOW_ID(), data, abi.encodeWithSelector(Errors.ZeroAmount.selector)
        );
    }
}
