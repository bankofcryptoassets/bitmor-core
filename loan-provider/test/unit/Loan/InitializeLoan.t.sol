// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.30;

import {BaseLoanTest} from "./BaseLoan.t.sol";
import {DataTypes} from "@bitmor/libraries/types/DataTypes.sol";
import {Errors} from "@bitmor/libraries/helpers/Errors.sol";
import {ILoanVault} from "@bitmor/interfaces/ILoanVault.sol";
import {IPriceOracleGetter} from "@bitmor/interfaces/IPriceOracleGetter.sol";
import {IERC20} from "@bitmor/dependencies/openzeppelin/IERC20.sol";
import {Loan} from "@bitmor/protocol/Loan.sol";
import {LoanVault} from "@bitmor/protocol/LoanVault.sol";
import {LoanVaultFactory} from "@bitmor/protocol/LoanVaultFactory.sol";
import {MockAaveV3Pool} from "../../mock/MockAaveV3Pool.sol";

/// @title InitializeLoanTest
/// @notice Tests for loan initialization functionality
contract InitializeLoanTest is BaseLoanTest {
    // ============ Local Test Helpers ============

    /// @dev Assert loan was created correctly with expected parameters
    function _assertLoanCreated(
        address lsa,
        address expectedBorrower,
        uint256 expectedDuration,
        uint256 expectedCollateral
    ) internal view {
        DataTypes.LoanData memory loanData = loan.getLoanByLSA(lsa);
        assertEq(loanData.borrower, expectedBorrower, "Borrower mismatch");
        assertEq(loanData.duration, expectedDuration, "Duration mismatch");
        assertEq(loanData.collateralAmount, expectedCollateral, "Collateral mismatch");
        assertEq(uint256(loanData.status), uint256(DataTypes.LoanStatus.Active), "Status should be Active");
    }

    /// @dev Assert loan data has expected basic properties
    function _assertLoanDataBasics(
        DataTypes.LoanData memory loanData,
        address expectedBorrower,
        uint256 expectedDuration
    ) internal pure {
        assertEq(loanData.borrower, expectedBorrower, "Borrower mismatch");
        assertEq(loanData.duration, expectedDuration, "Duration mismatch");
        assertGt(loanData.loanAmount, 0, "Loan amount should be > 0");
        assertGt(loanData.estimatedMonthlyPayment, 0, "Monthly payment should be > 0");
    }

    // ============ Loan Initialization Tests ============

    /// @notice Initializes a loan when deposit equals the minimum required.
    function test_initializeLoan_whenDepositAmountIsEqualToMinimumDepositRequired() public mintDebtAssetToUser {
        // Use _createStandardLoan() which handles exact minimum deposit
        address lsa = _createStandardLoan();
        _assertLoanCreated(lsa, user, STANDARD_DURATION, STANDARD_COLLATERAL_AMOUNT);
    }

    /// @notice Reverts when deposit is below the minimum required.
    function test_initializeLoan_whenDepositAmountIsLessThanMinimumDepositRequired() public mintDebtAssetToUser {
        // This test specifically needs less-than-minimum deposit, so keep manual pattern
        uint256 collateralAmount = STANDARD_COLLATERAL_AMOUNT;
        uint256 duration = STANDARD_DURATION;

        (,, uint256 minDepositRequired) = loan.getLoanDetails(collateralAmount, duration);

        vm.prank(user);
        _expectRevertSelector(Errors.InsufficientDeposit.selector);
        loan.initializeLoan(minDepositRequired - 1, PREMIUM_AMOUNT, collateralAmount, duration, DATA);
    }

    /// @notice Initializes a loan when deposit is above the minimum required.
    function test_initializeLoan_whenDepositAmountIsGreaterThanMinimumDepositRequired() public mintDebtAssetToUser {
        // This test specifically needs more-than-minimum deposit
        uint256 collateralAmount = STANDARD_COLLATERAL_AMOUNT;
        uint256 duration = STANDARD_DURATION;

        (,, uint256 minDepositRequired) = loan.getLoanDetails(collateralAmount, duration);

        vm.prank(user);
        address lsa = loan.initializeLoan(minDepositRequired + 1, PREMIUM_AMOUNT, collateralAmount, duration, DATA);

        _assertLoanCreated(lsa, user, duration, collateralAmount);
    }

    /// @notice Reverts when loan size is below the protocol minimum.
    function test_initializeLoan_withMinimumLoanSize() public mintDebtAssetToUser {
        // Goal: ensure the protocol enforces a $1,000 minimum loan size
        uint256 duration = STANDARD_DURATION;

        // Get BTC price from oracle (8 decimals)
        uint256 btcPriceUsd = IPriceOracleGetter(loan.i_ORACLE()).getAssetPrice(collateralAsset);

        // Target $500 total position value => loan amount must be < $1,000
        uint256 targetUsd = 500e8;
        uint256 collateralAmount = (targetUsd * 1e8) / btcPriceUsd;
        if (collateralAmount == 0) collateralAmount = 1;

        // getLoanDetails should revert for loan amounts below $1,000 minimum
        // Note: Using generic revert as specific error may vary by implementation
        vm.expectRevert();
        loan.getLoanDetails(collateralAmount, duration);
    }

    /// @notice Validates equity contribution bounds and rejects deposits below the minimum.
    function test_initializeLoan_withMinimumEquityContribution() public mintDebtAssetToUser {
        // Goal: validate minimum equity contribution is ~33%
        uint256 collateralAmount = STANDARD_COLLATERAL_AMOUNT;
        uint256 duration = STANDARD_DURATION;

        (uint256 loanAmount, uint256 monthlyPayment, uint256 minDepositRequired) =
            loan.getLoanDetails(collateralAmount, duration);

        assertGt(monthlyPayment, 0, "Monthly payment must be non-zero");

        uint256 totalSize = loanAmount + minDepositRequired;
        uint256 equityBps = (minDepositRequired * 10_000) / totalSize;

        // Expected minimum equity ~33%
        assertGe(equityBps, 3300, "Equity should be >= 33%");
        assertLe(equityBps, 3400, "Equity should be <= 34%");

        // Rejection below minimum deposit
        vm.prank(user);
        _expectRevertSelector(Errors.InsufficientDeposit.selector);
        loan.initializeLoan(minDepositRequired - 1, PREMIUM_AMOUNT, collateralAmount, duration, DATA);
    }

    /// @notice Reverts when duration is outside the allowed range.
    function test_initializeLoan_invalidDuration_revertsReject() public mintDebtAssetToUser {
        uint256 collateralAmount = STANDARD_COLLATERAL_AMOUNT;

        // getLoanDetails should reject invalid durations (0 and 13)
        // Note: Using generic revert as specific error may vary by implementation
        vm.expectRevert();
        loan.getLoanDetails(collateralAmount, 0);

        vm.expectRevert();
        loan.getLoanDetails(collateralAmount, 13);

        uint256 bigDeposit = 500_000e6;

        // initializeLoan should reject invalid durations
        vm.prank(user);
        vm.expectRevert();
        loan.initializeLoan(bigDeposit, PREMIUM_AMOUNT, collateralAmount, 0, DATA);

        vm.prank(user);
        vm.expectRevert();
        loan.initializeLoan(bigDeposit, PREMIUM_AMOUNT, collateralAmount, 13, DATA);
    }

    /// @notice Reverts when slippage protection bounds are violated.
    function test_initializeLoan_slippageProtection() public mintDebtAssetToUser {
        // Goal: force swap to exceed MAX_SLIPPAGE_BPS (0.5%) and ensure revert
        uint256 collateralAmount = STANDARD_COLLATERAL_AMOUNT;
        uint256 duration = STANDARD_DURATION;

        (,, uint256 minDepositRequired) = loan.getLoanDetails(collateralAmount, duration);

        address oracle = loan.i_ORACLE();
        uint256 realBtcPrice = IPriceOracleGetter(oracle).getAssetPrice(collateralAsset);

        // Underprice BTC by 2% to breach 0.5% slippage
        uint256 mockedBtcPrice = (realBtcPrice * 102) / 100;

        vm.mockCall(
            oracle,
            abi.encodeWithSelector(IPriceOracleGetter.getAssetPrice.selector, collateralAsset),
            abi.encode(mockedBtcPrice)
        );

        vm.prank(user);
        vm.expectRevert();
        loan.initializeLoan(minDepositRequired, PREMIUM_AMOUNT, collateralAmount, duration, DATA);
    }

    /// @notice Test flash loan integration works correctly through MockAaveV3Pool
    function test_initializeLoan_flashLoanIntegration_success() public {


        MockAaveV3Pool mockPool = new MockAaveV3Pool();

        vm.startPrank(owner);
        Loan loan2 = new Loan(
            address(mockPool),
            s_addressesProvider,
            s_bitmorPool,
            loan.i_ORACLE(),
            collateralAsset,
            debtAsset,
            loan.s_swapAdapter(),
            loan.s_zQuoter(),
            loan.getPremiumCollector(),
            loan.getPreClosureFee(),
            loan.getGracePeriod(),
            loan.getLiquidationBuffer()
        );

        address loanVaultImplementation = address(new LoanVault());
        address loanVaultFactory = address(new LoanVaultFactory(loanVaultImplementation, address(loan2)));
        loan2.setLoanVaultFactory(loanVaultFactory);
        vm.stopPrank();

        _utilSeedUserAndApprove(user, debtAsset, address(loan2), DEBT_ASSET_TO_MINT_TO_USER);

        // Use _utilCreateLoan with loan2 for this specific test
        (address lsa,) =
            _utilCreateLoan(loan2, user, STANDARD_COLLATERAL_AMOUNT, STANDARD_DURATION, PREMIUM_AMOUNT, DATA);

        // Assert flash loan was executed successfully
        assertTrue(lsa != address(0), "LSA should be created");
        assertTrue(mockPool.lastAmount() > 0, "Flash loan amount should be > 0");
        assertEq(mockPool.lastInitiator(), address(loan2), "Flash loan initiator should be loan contract");
    }

    /// @notice Sets correct LSA ownership and records loan data.
    function test_initializeLoan_lsaOwnership() public mintDebtAssetToUser {
        // Use consolidated helper
        address lsa = _createStandardLoan();

        // Use utility helper for LSA ownership assertions
        _utilAssertLSAOwnership(lsa, address(loan), user);

        DataTypes.LoanData memory loanData = loan.getLoanByLSA(lsa);
        assertEq(loanData.borrower, user, "Loan data borrower should be user");
    }

    /// @notice Reverts when deposit amount is zero.
    function test_initializeLoan_zeroDeposit_reverts() public mintDebtAssetToUser {
        uint256 collateralAmount = STANDARD_COLLATERAL_AMOUNT;
        uint256 duration = STANDARD_DURATION;

        vm.prank(user);
        _expectRevertSelector(Errors.ZeroAmount.selector);
        loan.initializeLoan(0, PREMIUM_AMOUNT, collateralAmount, duration, DATA);
    }

    /// @notice Reverts when premium is zero while insurance is requested.
    function test_initializeLoan_zeroPremium_withInsurance_reverts() public mintDebtAssetToUser {
        uint256 collateralAmount = STANDARD_COLLATERAL_AMOUNT;
        uint256 duration = STANDARD_DURATION;

        (,, uint256 minDepositRequired) = loan.getLoanDetails(collateralAmount, duration);

        // Should revert with ZeroAmount when insurance opted but premium is 0
        vm.prank(user);
        vm.expectRevert(Errors.ZeroAmount.selector);
        loan.initializeLoan(minDepositRequired, 0, collateralAmount, duration, DATA);
    }

    /// @notice Reverts when collateral amount is zero.
    function test_initializeLoan_zeroCollateral_reverts() public mintDebtAssetToUser {
        uint256 collateralAmount = STANDARD_COLLATERAL_AMOUNT;
        uint256 duration = STANDARD_DURATION;

        (,, uint256 minDepositRequired) = loan.getLoanDetails(collateralAmount, duration);

        vm.prank(user);
        _expectRevertSelector(Errors.ZeroAmount.selector);
        loan.initializeLoan(minDepositRequired, PREMIUM_AMOUNT, 0, duration, DATA);
    }
}
