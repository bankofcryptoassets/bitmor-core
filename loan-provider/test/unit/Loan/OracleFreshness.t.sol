// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.30;

import {BaseLoanTest} from "./BaseLoan.t.sol";
import {TestConstants as TC} from "../../helpers/TestConstants.sol";
import {DataTypes} from "@bitmor/libraries/types/DataTypes.sol";
import {Errors} from "@bitmor/libraries/helpers/Errors.sol";
import {ILoan} from "@bitmor/interfaces/ILoan.sol";
import {Vm} from "forge-std/Vm.sol";

/// @title OracleFreshnessTest
/// @author Bitmor Protocol
/// @notice Tests for oracle price staleness validation across all oracle call sites
contract OracleFreshnessTest is BaseLoanTest {
    // ============ Setup ============

    function setUp() public override {
        super.setUp();
    }

    // ============ Helpers ============

    /// @notice Sets max oracle staleness via LPM_SLOW role (schedule + execute)
    function _setMaxOracleStaleness(uint256 staleness) internal {
        bytes memory data = abi.encodeCall(loan.setMaxOracleStaleness, (staleness));
        _scheduleAndExecute(address(loan), lpm_slow, LPM_SLOW_ID(), data);
    }

    /// @notice Makes both BTC and USDC oracle prices stale
    function _makeBothPricesStale() internal {
        uint256 staleTimestamp = block.timestamp - TC.STALE_PRICE_AGE;
        mockOracle.makeStale(address(mockCbBTC), staleTimestamp);
        mockOracle.makeStale(address(mockUSDC), staleTimestamp);
    }

    /// @notice Makes only BTC oracle price stale
    function _makeBtcPriceStale() internal {
        uint256 staleTimestamp = block.timestamp - TC.STALE_PRICE_AGE;
        mockOracle.makeStale(address(mockCbBTC), staleTimestamp);
    }

    /// @notice Makes only USDC oracle price stale
    function _makeDebtAssetPriceStale() internal {
        uint256 staleTimestamp = block.timestamp - TC.STALE_PRICE_AGE;
        mockOracle.makeStale(address(mockUSDC), staleTimestamp);
    }

    // ============ setMaxOracleStaleness Tests ============

    function test_SetMaxOracleStaleness_EmitsEvent() public {
        // Record logs during schedule + execute
        vm.recordLogs();
        _setMaxOracleStaleness(TC.DEFAULT_MAX_ORACLE_STALENESS);

        // Check that the event was emitted somewhere in the logs
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 eventSig = keccak256("Loan__MaxOracleStalenessUpdated(uint256)");
        bool found;
        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].topics[0] == eventSig) {
                assertEq(uint256(entries[i].topics[1]), TC.DEFAULT_MAX_ORACLE_STALENESS, "event value should match");
                found = true;
                break;
            }
        }
        assertTrue(found, "Loan__MaxOracleStalenessUpdated event should be emitted");
    }

    function test_SetMaxOracleStaleness_UpdatesStorage() public {
        _setMaxOracleStaleness(TC.DEFAULT_MAX_ORACLE_STALENESS);
        assertEq(loan.getMaxOracleStaleness(), TC.DEFAULT_MAX_ORACLE_STALENESS, "staleness should be updated");
    }

    function test_SetMaxOracleStaleness_RevertsWhen_ExceedsUpperBound() public {
        uint256 tooLarge = 86_401; // MAX_ORACLE_STALENESS + 1

        bytes memory data = abi.encodeCall(loan.setMaxOracleStaleness, (tooLarge));
        _scheduleAndExpectRevert(
            address(loan), lpm_slow, LPM_SLOW_ID(), data, abi.encodeWithSelector(Errors.InvalidInputs.selector)
        );
    }

    function test_SetMaxOracleStaleness_SucceedsAt_UpperBound() public {
        uint256 maxAllowed = 86_400; // Exactly MAX_ORACLE_STALENESS
        _setMaxOracleStaleness(maxAllowed);
        assertEq(loan.getMaxOracleStaleness(), maxAllowed, "should accept max staleness value");
    }

    // ============ initializeLoan Tests ============

    function test_InitializeLoan_RevertsWhen_OracleStale() public {
        // Arrange
        _setMaxOracleStaleness(TC.DEFAULT_MAX_ORACLE_STALENESS);
        _makeBothPricesStale();
        _mintDebtAssetToUser();

        // Act + Assert
        vm.expectRevert(Errors.StaleOraclePrice.selector);
        vm.prank(user);
        loan.initializeLoan(TC.USER_USDC_BALANCE, PREMIUM_AMOUNT, STANDARD_COLLATERAL_AMOUNT, STANDARD_DURATION, DATA);
    }

    function test_InitializeLoan_SucceedsWhen_OracleFresh() public {
        // Arrange
        _setMaxOracleStaleness(TC.DEFAULT_MAX_ORACLE_STALENESS);
        // Prices are fresh by default (mock returns block.timestamp)
        _mintDebtAssetToUser();

        // Act
        (,, uint256 minDeposit) = loan.getLoanDetails(STANDARD_COLLATERAL_AMOUNT, STANDARD_DURATION);
        vm.prank(user);
        address lsa =
            loan.initializeLoan(minDeposit, PREMIUM_AMOUNT, STANDARD_COLLATERAL_AMOUNT, STANDARD_DURATION, DATA);

        // Assert
        DataTypes.LoanData memory loanData = loan.getLoanByLSA(lsa);
        assertEq(loanData.borrower, user, "loan should be created for user");
    }

    function test_InitializeLoan_SucceedsWhen_StalenessDisabled() public {
        // Arrange: staleness = 0 (default, disabled), but oracle is stale
        _makeBothPricesStale();
        _mintDebtAssetToUser();

        // Act: should succeed because staleness check is disabled
        (,, uint256 minDeposit) = loan.getLoanDetails(STANDARD_COLLATERAL_AMOUNT, STANDARD_DURATION);
        vm.prank(user);
        address lsa =
            loan.initializeLoan(minDeposit, PREMIUM_AMOUNT, STANDARD_COLLATERAL_AMOUNT, STANDARD_DURATION, DATA);

        // Assert
        DataTypes.LoanData memory loanData = loan.getLoanByLSA(lsa);
        assertEq(loanData.borrower, user, "loan should be created despite stale oracle when disabled");
    }

    // ============ closeLoan Tests ============

    function test_CloseLoan_RevertsWhen_OracleStale() public {
        // Arrange: create a loan first with staleness disabled
        _mintDebtAssetToUser();
        (,, uint256 minDeposit) = loan.getLoanDetails(STANDARD_COLLATERAL_AMOUNT, STANDARD_DURATION);
        vm.prank(user);
        address lsa =
            loan.initializeLoan(minDeposit, PREMIUM_AMOUNT, STANDARD_COLLATERAL_AMOUNT, STANDARD_DURATION, DATA);

        // Enable staleness and make prices stale
        _setMaxOracleStaleness(TC.DEFAULT_MAX_ORACLE_STALENESS);
        _makeBothPricesStale();

        // Act + Assert
        vm.expectRevert(Errors.StaleOraclePrice.selector);
        vm.prank(user);
        loan.closeLoan(lsa, false);
    }

    // ============ getLoanDetails Tests ============

    function test_GetLoanDetails_RevertsWhen_OracleStale() public {
        // Arrange
        _setMaxOracleStaleness(TC.DEFAULT_MAX_ORACLE_STALENESS);
        _makeBothPricesStale();

        // Act + Assert
        vm.expectRevert(Errors.StaleOraclePrice.selector);
        loan.getLoanDetails(STANDARD_COLLATERAL_AMOUNT, STANDARD_DURATION);
    }

    // ============ calculateStrikePrice Tests ============

    function test_CalculateStrikePrice_RevertsWhen_OracleStale() public {
        // Arrange
        _setMaxOracleStaleness(TC.DEFAULT_MAX_ORACLE_STALENESS);
        _makeBtcPriceStale();

        // Act + Assert
        vm.expectRevert(Errors.StaleOraclePrice.selector);
        loan.calculateStrikePrice(100_000e6, 50_000e6);
    }

    // ============ Per-Asset Staleness Tests ============

    function test_DebtAssetStale_BtcFresh_Reverts() public {
        // Arrange: only USDC is stale, BTC is fresh
        _setMaxOracleStaleness(TC.DEFAULT_MAX_ORACLE_STALENESS);
        _makeDebtAssetPriceStale();
        // BTC stays fresh (default)

        _mintDebtAssetToUser();

        // Act + Assert: should revert because USDC price is stale
        vm.expectRevert(Errors.StaleOraclePrice.selector);
        vm.prank(user);
        loan.initializeLoan(TC.USER_USDC_BALANCE, PREMIUM_AMOUNT, STANDARD_COLLATERAL_AMOUNT, STANDARD_DURATION, DATA);
    }

    function test_BtcStale_DebtAssetFresh_Reverts() public {
        // Arrange: only BTC is stale, USDC is fresh
        _setMaxOracleStaleness(TC.DEFAULT_MAX_ORACLE_STALENESS);
        _makeBtcPriceStale();
        // USDC stays fresh (default)

        _mintDebtAssetToUser();

        // Act + Assert: should revert because BTC price is stale
        vm.expectRevert(Errors.StaleOraclePrice.selector);
        vm.prank(user);
        loan.initializeLoan(TC.USER_USDC_BALANCE, PREMIUM_AMOUNT, STANDARD_COLLATERAL_AMOUNT, STANDARD_DURATION, DATA);
    }

    // ============ Disable-After-Enable Tests ============

    function test_InitializeLoan_SucceedsWhen_StalenessDisabledAfterEnable() public {
        // Arrange: enable staleness, then disable it (set back to 0)
        _setMaxOracleStaleness(TC.DEFAULT_MAX_ORACLE_STALENESS);
        assertEq(loan.getMaxOracleStaleness(), TC.DEFAULT_MAX_ORACLE_STALENESS, "staleness should be enabled");

        _setMaxOracleStaleness(0);
        assertEq(loan.getMaxOracleStaleness(), 0, "staleness should be disabled");

        // Make prices stale — should not matter since staleness is disabled
        _makeBothPricesStale();
        _mintDebtAssetToUser();

        // Act: should succeed because staleness is disabled again
        (,, uint256 minDeposit) = loan.getLoanDetails(STANDARD_COLLATERAL_AMOUNT, STANDARD_DURATION);
        vm.prank(user);
        address lsa =
            loan.initializeLoan(minDeposit, PREMIUM_AMOUNT, STANDARD_COLLATERAL_AMOUNT, STANDARD_DURATION, DATA);

        // Assert
        DataTypes.LoanData memory loanData = loan.getLoanByLSA(lsa);
        assertEq(loanData.borrower, user, "loan should succeed after staleness re-disabled");
    }

    // ============ Per-Asset Staleness for closeLoan ============

    function test_CloseLoan_RevertsWhen_OnlyBtcStale() public {
        // Arrange: create loan with staleness disabled
        _mintDebtAssetToUser();
        (,, uint256 minDeposit) = loan.getLoanDetails(STANDARD_COLLATERAL_AMOUNT, STANDARD_DURATION);
        vm.prank(user);
        address lsa =
            loan.initializeLoan(minDeposit, PREMIUM_AMOUNT, STANDARD_COLLATERAL_AMOUNT, STANDARD_DURATION, DATA);

        // Enable staleness, make only BTC stale
        _setMaxOracleStaleness(TC.DEFAULT_MAX_ORACLE_STALENESS);
        _makeBtcPriceStale();

        // Act + Assert
        vm.expectRevert(Errors.StaleOraclePrice.selector);
        vm.prank(user);
        loan.closeLoan(lsa, false);
    }

    function test_CloseLoan_RevertsWhen_OnlyDebtAssetStale() public {
        // Arrange: create loan with staleness disabled
        _mintDebtAssetToUser();
        (,, uint256 minDeposit) = loan.getLoanDetails(STANDARD_COLLATERAL_AMOUNT, STANDARD_DURATION);
        vm.prank(user);
        address lsa =
            loan.initializeLoan(minDeposit, PREMIUM_AMOUNT, STANDARD_COLLATERAL_AMOUNT, STANDARD_DURATION, DATA);

        // Enable staleness, make only debt asset stale
        _setMaxOracleStaleness(TC.DEFAULT_MAX_ORACLE_STALENESS);
        _makeDebtAssetPriceStale();

        // Act + Assert
        vm.expectRevert(Errors.StaleOraclePrice.selector);
        vm.prank(user);
        loan.closeLoan(lsa, false);
    }
}
