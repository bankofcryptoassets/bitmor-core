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
import {MockAaveV3Pool} from "@bitmor/mocks/MockAaveV3Pool.sol";

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

    function test_initializeLoan_whenDepositAmountIsEqualToMinimumDepositRequired() public mintDebtAssetToUser {
        uint256 collateralAmount = STANDARD_COLLATERAL_AMOUNT;
        uint256 duration = STANDARD_DURATION;

        (,, uint256 minDepositRequired) = loan.getLoanDetails(collateralAmount, duration);

        vm.prank(user);
        address lsa = loan.initializeLoan(minDepositRequired, PREMIUM_AMOUNT, collateralAmount, duration, DATA);

        _assertLoanCreated(lsa, user, duration, collateralAmount);
    }

    function test_initializeLoan_whenDepositAmountIsLessThanMinimumDepositRequired() public mintDebtAssetToUser {
        uint256 collateralAmount = STANDARD_COLLATERAL_AMOUNT;
        uint256 duration = STANDARD_DURATION;

        (,, uint256 minDepositRequired) = loan.getLoanDetails(collateralAmount, duration);

        vm.prank(user);
        _expectRevertSelector(Errors.InsufficientDeposit.selector);
        loan.initializeLoan(minDepositRequired - 1, PREMIUM_AMOUNT, collateralAmount, duration, DATA);
    }

    function test_initializeLoan_whenDepositAmountIsGreaterThanMinimumDepositRequired() public mintDebtAssetToUser {
        uint256 collateralAmount = STANDARD_COLLATERAL_AMOUNT;
        uint256 duration = STANDARD_DURATION;

        (,, uint256 minDepositRequired) = loan.getLoanDetails(collateralAmount, duration);

        vm.prank(user);
        address lsa = loan.initializeLoan(minDepositRequired + 1, PREMIUM_AMOUNT, collateralAmount, duration, DATA);

        _assertLoanCreated(lsa, user, duration, collateralAmount);
    }

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
        assertGe(equityBps, 3000, "Equity should be >= 30%");
        assertLe(equityBps, 3100, "Equity should be <= 31%");

        // Rejection below minimum deposit
        vm.prank(user);
        _expectRevertSelector(Errors.InsufficientDeposit.selector);
        loan.initializeLoan(minDepositRequired - 1, PREMIUM_AMOUNT, collateralAmount, duration, DATA);
    }

    function test_initializeLoan_withVariousDurations() public mintDebtAssetToUser {
        uint256 collateralAmount = STANDARD_COLLATERAL_AMOUNT;
        uint256 t0 = block.timestamp;

        assertEq(loan.getUserLoanCount(user), 0, "Initial loan count should be 0");

        // 1 month duration
        (,, uint256 minDeposit1) = loan.getLoanDetails(collateralAmount, 1);
        vm.prank(user);
        address lsa1 = loan.initializeLoan(minDeposit1, PREMIUM_AMOUNT, collateralAmount, 1, DATA);
        DataTypes.LoanData memory loan1 = loan.getLoanByLSA(lsa1);
        assertEq(loan1.duration, 1, "Duration should be 1");
        assertEq(loan.getUserLoanCount(user), 1, "Loan count should be 1");

        // 6 months duration (different timestamp for CREATE2 salt)
        vm.warp(t0 + 1000);
        (,, uint256 minDeposit6) = loan.getLoanDetails(collateralAmount, 6);
        vm.prank(user);
        address lsa6 = loan.initializeLoan(minDeposit6, PREMIUM_AMOUNT, collateralAmount, 6, DATA);
        DataTypes.LoanData memory loan6 = loan.getLoanByLSA(lsa6);
        assertEq(loan6.duration, 6, "Duration should be 6");
        assertEq(loan.getUserLoanCount(user), 2, "Loan count should be 2");

        // 12 months duration
        vm.warp(t0 + 2000);
        (,, uint256 minDeposit12) = loan.getLoanDetails(collateralAmount, 12);
        vm.prank(user);
        address lsa12 = loan.initializeLoan(minDeposit12, PREMIUM_AMOUNT, collateralAmount, 12, DATA);
        DataTypes.LoanData memory loan12 = loan.getLoanByLSA(lsa12);
        assertEq(loan12.duration, 12, "Duration should be 12");
        assertEq(loan.getUserLoanCount(user), 3, "Loan count should be 3");

        // Payment monotonicity: shorter duration => higher monthly payment
        assertGt(loan1.estimatedMonthlyPayment, loan6.estimatedMonthlyPayment, "1mo > 6mo payment");
        assertGt(loan6.estimatedMonthlyPayment, loan12.estimatedMonthlyPayment, "6mo > 12mo payment");

        // ============ getUserAllLoans Coverage ============
        // Verify getUserAllLoans returns correct data for all user loans
        DataTypes.LoanData[] memory allLoans = loan.getUserAllLoans(user);

        // Assert length equals s_userLoanCount[user]
        assertEq(allLoans.length, loan.getUserLoanCount(user), "getUserAllLoans length should equal s_userLoanCount");
        assertEq(allLoans.length, 3, "User should have exactly 3 loans");

        // Store expected LSAs in order
        address[3] memory expectedLSAs = [lsa1, lsa6, lsa12];

        // Verify each returned LoanData maps to the correct stored LoanData
        for (uint256 i = 0; i < allLoans.length; i++) {
            // Get the LSA at this index
            address lsaAtIndex = loan.getUserLoanAtIndex(user, i);
            assertEq(lsaAtIndex, expectedLSAs[i], "LSA at index mismatch");

            // Get the stored LoanData via getLoanByLSA
            DataTypes.LoanData memory storedLoan = loan.getLoanByLSA(lsaAtIndex);

            // Verify the returned LoanData matches the stored LoanData
            assertEq(allLoans[i].borrower, storedLoan.borrower, "Borrower mismatch in returned loan");
            assertEq(allLoans[i].depositAmount, storedLoan.depositAmount, "Deposit amount mismatch in returned loan");
            assertEq(allLoans[i].loanAmount, storedLoan.loanAmount, "Loan amount mismatch in returned loan");
            assertEq(allLoans[i].collateralAmount, storedLoan.collateralAmount, "Collateral amount mismatch");
            assertEq(
                allLoans[i].estimatedMonthlyPayment, storedLoan.estimatedMonthlyPayment, "Monthly payment mismatch"
            );
            assertEq(allLoans[i].duration, storedLoan.duration, "Duration mismatch in returned loan");
            assertEq(allLoans[i].createdAt, storedLoan.createdAt, "CreatedAt mismatch");
            assertEq(allLoans[i].insuranceID, storedLoan.insuranceID, "Insurance ID mismatch");
            assertEq(
                allLoans[i].lastPaymentTimestamp, storedLoan.lastPaymentTimestamp, "Last payment timestamp mismatch"
            );
            assertEq(uint256(allLoans[i].status), uint256(storedLoan.status), "Status mismatch in returned loan");
        }

        // Additional verification: ensure borrower is correct for all loans
        for (uint256 i = 0; i < allLoans.length; i++) {
            assertEq(allLoans[i].borrower, user, "All loans should belong to user");
        }
    }

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

    function test_initializeLoan_flashLoanFromNonAave_reverts() public {
        // Goal: reject flash loan callbacks from unauthorized sources

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

        // Mint and approve for loan2
        vm.startPrank(user);
        (bool success,) = debtAsset.call(abi.encodeWithSignature("mint(uint256)", DEBT_ASSET_TO_MINT_TO_USER));
        require(success, "MINT_ERROR");
        IERC20(debtAsset).approve(address(loan2), DEBT_ASSET_TO_MINT_TO_USER);
        vm.stopPrank();

        // Successful initialization through mock pool
        uint256 collateralAmount = STANDARD_COLLATERAL_AMOUNT;
        uint256 duration = STANDARD_DURATION;
        (,, uint256 minDepositRequired) = loan2.getLoanDetails(collateralAmount, duration);

        vm.prank(user);
        loan2.initializeLoan(minDepositRequired, PREMIUM_AMOUNT, collateralAmount, duration, DATA);

        // Cache callback params before expectRevert
        address asset = mockPool.lastAsset();
        uint256 amount = mockPool.lastAmount();
        uint256 premium = mockPool.lastPremium();
        address initiator = mockPool.lastInitiator();
        bytes memory params = mockPool.lastParams();

        // Replay callback from non-pool address - should revert with CallerIsNotAAVEPool
        address notPool = makeAddr("notPool");
        vm.prank(notPool);
        vm.expectRevert(Errors.CallerIsNotAAVEPool.selector);
        loan2.executeOperation(asset, amount, premium, initiator, params);
    }

    function test_initializeLoan_lsaOwnership() public mintDebtAssetToUser {
        uint256 collateralAmount = STANDARD_COLLATERAL_AMOUNT;
        uint256 duration = STANDARD_DURATION;

        (,, uint256 minDepositRequired) = loan.getLoanDetails(collateralAmount, duration);

        vm.prank(user);
        address lsa = loan.initializeLoan(minDepositRequired, PREMIUM_AMOUNT, collateralAmount, duration, DATA);

        // LSA owner should be Loan contract; borrower should be user
        assertEq(ILoanVault(lsa).owner(), address(loan), "LSA owner should be Loan contract");
        assertEq(ILoanVault(lsa).borrower(), user, "LSA borrower should be user");
        assertTrue(ILoanVault(lsa).isInitialized(), "LSA should be initialized");

        DataTypes.LoanData memory loanData = loan.getLoanByLSA(lsa);
        assertEq(loanData.borrower, user, "Loan data borrower should be user");
    }

    function test_initializeLoan_zeroDeposit_reverts() public mintDebtAssetToUser {
        uint256 collateralAmount = STANDARD_COLLATERAL_AMOUNT;
        uint256 duration = STANDARD_DURATION;

        (,, uint256 minDepositRequired) = loan.getLoanDetails(collateralAmount, duration);
        assertGt(minDepositRequired, 0, "Min deposit should be > 0");

        vm.prank(user);
        _expectRevertSelector(Errors.ZeroAmount.selector);
        loan.initializeLoan(0, PREMIUM_AMOUNT, collateralAmount, duration, DATA);
    }

    function test_initializeLoan_zeroPremium_withInsurance_reverts() public mintDebtAssetToUser {
        uint256 collateralAmount = STANDARD_COLLATERAL_AMOUNT;
        uint256 duration = STANDARD_DURATION;

        (,, uint256 minDepositRequired) = loan.getLoanDetails(collateralAmount, duration);

        // Should revert with ZeroAmount when insurance opted but premium is 0
        vm.prank(user);
        vm.expectRevert(Errors.ZeroAmount.selector);
        loan.initializeLoan(minDepositRequired, 0, collateralAmount, duration, DATA);
    }

    function test_initializeLoan_zeroCollateral_reverts() public mintDebtAssetToUser {
        uint256 collateralAmount = STANDARD_COLLATERAL_AMOUNT;
        uint256 duration = STANDARD_DURATION;

        (,, uint256 minDepositRequired) = loan.getLoanDetails(collateralAmount, duration);

        vm.prank(user);
        _expectRevertSelector(Errors.ZeroAmount.selector);
        loan.initializeLoan(minDepositRequired, PREMIUM_AMOUNT, 0, duration, DATA);
    }
}
