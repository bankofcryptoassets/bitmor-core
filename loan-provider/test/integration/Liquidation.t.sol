// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.30;

import {IntegrationTestBase} from "../base/IntegrationTestBase.sol";
import {TestConstants as TC} from "../helpers/TestConstants.sol";
import {DataTypes} from "@bitmor/libraries/types/DataTypes.sol";
import {IERC20} from "@openzeppelin/interfaces/IERC20.sol";

/// @title LiquidationTest
/// @notice Integration tests for liquidation flows against the real Bitmor Lending Pool
/// @dev Tests exercise the Hardhat-deployed LendingPool + LendingPoolCollateralManager
///      with MockChainlinkOracle for price manipulation. Liquidation calls use low-level
///      `call` due to Solidity version mismatch (lending pool is 0.6.12, tests are 0.8.30).
contract LiquidationTest is IntegrationTestBase {
    function setUp() public override {
        super.setUp();
        _setupTestUser();
        _setupLiquidator();
    }

    // ============ Oracle Price Manipulation ============

    function test_OraclePriceDropIsReflected() public {
        (, int256 priceBefore,,,) = btcOracle.latestRoundData();

        _dropOraclePrice(50);

        (, int256 priceAfter,,,) = btcOracle.latestRoundData();
        assertEq(priceAfter, priceBefore / 2, "price should drop by 50%");
    }

    // ============ Healthy Loan ============

    function test_NoLiquidation_WhenHealthy() public {
        (address lsa,) = _createLoanWithData(TC.STANDARD_COLLATERAL, TC.STANDARD_DURATION, TC.PREMIUM_AMOUNT);

        DataTypes.LoanData memory loanData = loanContract.getLoanByLSA(lsa);
        assertEq(uint256(loanData.status), uint256(DataTypes.LoanStatus.Active), "loan should be active");
    }

    // ============ Undercollateralization ============

    function test_LoanBecomesUndercollateralized_AfterPriceDrop() public {
        (address lsa,) = _createLoanWithData(TC.STANDARD_COLLATERAL, TC.STANDARD_DURATION, TC.PREMIUM_AMOUNT);

        // Drop price by 90% to make loan severely undercollateralized
        _dropOraclePrice(90);

        // Loan data should still be active (not yet liquidated - requires liquidation call)
        DataTypes.LoanData memory loanData = loanContract.getLoanByLSA(lsa);
        assertEq(
            uint256(loanData.status), uint256(DataTypes.LoanStatus.Active), "loan still active before liquidation call"
        );
    }

    // ============ Liquidation Type Detection ============

    /// @notice Validates checkTypeOfLiquidation returns non-zero after severe price drop
    function test_FullLiquidation_TypeDetected_AfterPriceDrop() public {
        (address lsa,) = _createLoanWithData(TC.STANDARD_COLLATERAL, TC.STANDARD_DURATION, TC.PREMIUM_AMOUNT);

        // Drop BTC price severely to trigger undercollateralization
        _dropOraclePrice(TC.PRICE_DROP_FULL);

        // Check liquidation type from Bitmor LP
        uint256 liquidationType = _checkTypeOfLiquidation(lsa);
        // Type should be non-zero (either full=1 or micro=2)
        assertGt(liquidationType, 0, "liquidation should be triggered after price drop");
    }

    /// @notice Validates checkTypeOfLiquidation returns micro-liquidation type for overdue loan
    function test_MicroLiquidation_TypeDetected_WhenOverdue() public {
        (address lsa,) = _createLoanWithData(TC.STANDARD_COLLATERAL, TC.STANDARD_DURATION, TC.PREMIUM_AMOUNT);

        // Make the loan overdue by advancing past grace period + payment interval
        _advanceDays(30 + 7 + 1); // 30 days interval + 7 days grace + 1

        // Check liquidation type
        uint256 liquidationType = _checkTypeOfLiquidation(lsa);
        // Overdue loan should trigger micro-liquidation (type 2)
        assertEq(liquidationType, TC.LIQUIDATION_TYPE_MICRO, "overdue loan should be micro-liquidatable");
    }

    // ============ Full Liquidation Execution ============

    /// @notice Executes a full liquidation via the real Bitmor Lending Pool after price crash
    /// @dev Creates loan, crashes BTC price, then calls liquidationCall on the lending pool.
    ///      Verifies loan status transitions to Liquidated and collateral/debt are affected.
    function test_FullLiquidation_ExecuteViaLendingPool() public {
        // Arrange: create loan and capture pre-liquidation state
        (address lsa, DataTypes.LoanData memory loanDataBefore) =
            _createLoanWithData(TC.STANDARD_COLLATERAL, TC.STANDARD_DURATION, TC.PREMIUM_AMOUNT);
        assertEq(
            uint256(loanDataBefore.status),
            uint256(DataTypes.LoanStatus.Active),
            "loan should be active before liquidation"
        );

        // Capture pre-liquidation account data
        (uint256 collateralBefore, uint256 debtBefore,) = _getUserAccountData(lsa);
        assertGt(collateralBefore, 0, "LSA should have collateral before liquidation");
        assertGt(debtBefore, 0, "LSA should have debt before liquidation");

        // Drop BTC price by 90% to make loan severely undercollateralized
        _dropOraclePrice(90);

        // Verify liquidation type is triggered
        uint256 liquidationType = _checkTypeOfLiquidation(lsa);
        assertGt(liquidationType, 0, "liquidation should be triggered after 90% price drop");

        // Act: execute liquidationCall via low-level call
        // The liquidator covers the entire debt (type(uint256).max for max coverage)
        vm.prank(testLiquidator);
        (bool success, bytes memory result) = bitmorPool.call(
            abi.encodeWithSignature(
                "liquidationCall(address,address,address,uint256,bool)",
                address(btcVault), // collateralAsset (bvBTC)
                address(usdc), // debtAsset (USDC)
                lsa, // user (the LSA)
                type(uint256).max, // debtToCover (max = liquidate all)
                false // receiveAToken = false (receive underlying)
            )
        );
        assertTrue(success, "liquidationCall should not revert");

        // Assert: loan status should be Liquidated
        DataTypes.LoanData memory loanDataAfter = loanContract.getLoanByLSA(lsa);
        assertEq(
            uint256(loanDataAfter.status),
            uint256(DataTypes.LoanStatus.Liquidated),
            "loan should be liquidated after liquidationCall"
        );
        assertEq(loanDataAfter.duration, 0, "remaining duration should be 0 after full liquidation");

        // Assert: collateral should be reduced (liquidated)
        (uint256 collateralAfter,,) = _getUserAccountData(lsa);
        assertLt(collateralAfter, collateralBefore, "collateral should decrease after liquidation");
    }

    // ============ Micro Liquidation Execution ============

    /// @notice Executes a micro liquidation via the real Bitmor Lending Pool for overdue loan
    /// @dev Creates loan, advances time past grace period, then calls microLiquidationCall.
    ///      Verifies loan duration decreases and lastPaymentTimestamp updates.
    function test_MicroLiquidation_ExecuteViaLendingPool() public {
        // Arrange: create loan
        (address lsa, DataTypes.LoanData memory loanDataBefore) =
            _createLoanWithData(TC.STANDARD_COLLATERAL, TC.STANDARD_DURATION, TC.PREMIUM_AMOUNT);
        uint256 durationBefore = loanDataBefore.duration;

        // Advance time past grace period + payment interval to make overdue
        _advanceDays(30 + 7 + 1);

        // Verify micro-liquidation type
        uint256 liquidationType = _checkTypeOfLiquidation(lsa);
        assertEq(liquidationType, TC.LIQUIDATION_TYPE_MICRO, "should be micro-liquidatable when overdue");

        // Capture pre-liquidation debt
        (, uint256 debtBefore,) = _getUserAccountData(lsa);
        assertGt(debtBefore, 0, "LSA should have debt before micro-liquidation");

        // Act: execute microLiquidationCall via low-level call
        // Encode the data: (collateralAsset, debtAsset, user)
        bytes memory microLiqData = abi.encode(address(btcVault), address(usdc), lsa);
        vm.prank(testLiquidator);
        (bool success, bytes memory result) =
            bitmorPool.call(abi.encodeWithSignature("microLiquidationCall(bytes)", microLiqData));
        assertTrue(success, "microLiquidationCall should not revert");

        // Assert: loan duration should decrease by 1 (micro-liquidation pays one installment)
        DataTypes.LoanData memory loanDataAfter = loanContract.getLoanByLSA(lsa);
        assertEq(loanDataAfter.duration, durationBefore - 1, "duration should decrease by 1 after micro-liquidation");

        // Loan should still be active (micro-liquidation doesn't close the loan unless duration reaches 0)
        if (durationBefore > 1) {
            assertEq(
                uint256(loanDataAfter.status),
                uint256(DataTypes.LoanStatus.Active),
                "loan should remain active after micro-liquidation (duration > 0)"
            );
        }

        // lastPaymentTimestamp should be updated
        assertGt(
            loanDataAfter.lastPaymentTimestamp,
            loanDataBefore.lastPaymentTimestamp,
            "lastPaymentTimestamp should update after micro-liquidation"
        );

        // Debt should decrease (liquidator covered one installment)
        (, uint256 debtAfter,) = _getUserAccountData(lsa);
        assertLt(debtAfter, debtBefore, "debt should decrease after micro-liquidation");
    }

    // ============ Liquidation Safety: Healthy Loan Cannot Be Liquidated ============

    /// @notice Verifies that a healthy loan cannot be liquidated
    /// @dev Calls liquidationCall on a healthy loan and expects it to revert or return error
    function test_FullLiquidation_RevertsWhenHealthy() public {
        // Arrange: create healthy loan (no price drop)
        (address lsa,) = _createLoanWithData(TC.STANDARD_COLLATERAL, TC.STANDARD_DURATION, TC.PREMIUM_AMOUNT);

        // Verify no liquidation type
        uint256 liquidationType = _checkTypeOfLiquidation(lsa);
        assertEq(liquidationType, TC.LIQUIDATION_TYPE_NONE, "healthy loan should have no liquidation type");

        // Act: attempt liquidation on healthy loan
        vm.prank(testLiquidator);
        (bool success,) = bitmorPool.call(
            abi.encodeWithSignature(
                "liquidationCall(address,address,address,uint256,bool)",
                address(btcVault),
                address(usdc),
                lsa,
                type(uint256).max,
                false
            )
        );
        // The lending pool should revert since ValidationLogic.validateLiquidationCall will fail
        assertFalse(success, "liquidationCall should revert for healthy loan");
    }

}
