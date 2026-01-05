// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.30;

import {BaseLoanTest} from "./BaseLoanTest.t.sol";
import {DataTypes} from "@bitmor/libraries/types/DataTypes.sol";
import {Errors} from "@bitmor/libraries/helpers/Errors.sol";
import {IPriceOracleGetter} from "@bitmor/interfaces/IPriceOracleGetter.sol";
import {IPoolAddressesProvider} from "@bitmor/interfaces/IPool.sol";
import {IPool} from "@bitmor/interfaces/IPool.sol";
import {Loan} from "@bitmor/protocol/Loan.sol";
import {LoanVault} from "@bitmor/protocol/LoanVault.sol";
import {LoanVaultFactory} from "@bitmor/protocol/LoanVaultFactory.sol";

/// @title LoanContract
/// @notice Consolidated tests for core Loan contract functionality
/// @dev 8 focused tests covering view functions, constructor validation, and modifiers
contract LoanContract is BaseLoanTest {

    // ============ 1. Zero-Address Guards (Combined) ============

    /// @notice Validates zero-address guards across all view functions
    function test_loan_viewFunctions_zeroAddress_reverts() public {
        // getUserAllLoans
        vm.expectRevert(Errors.ZeroAddress.selector);
        loan.getUserAllLoans(address(0));

        // getUserLoanCount
        vm.expectRevert(Errors.ZeroAddress.selector);
        loan.getUserLoanCount(address(0));

        // getUserLoanAtIndex
        vm.expectRevert(Errors.ZeroAddress.selector);
        loan.getUserLoanAtIndex(address(0), 0);

        // getLoanByLSA
        vm.expectRevert(Errors.ZeroAddress.selector);
        loan.getLoanByLSA(address(0));
    }

    // ============ 2. getUserAllLoans Multiple Loans Success ============

    /// @notice Validates getUserAllLoans returns correct data for multiple loans
    function test_loan_getUserAllLoans_multipleLoans_success() public mintDebtAssetToUser {
        uint256 collateralAmount = STANDARD_COLLATERAL_AMOUNT;
        uint256 t0 = block.timestamp;

        // Create first loan (12 months)
        (,, uint256 minDeposit1) = loan.getLoanDetails(collateralAmount, 12);
        vm.prank(user);
        loan.initializeLoan(minDeposit1, PREMIUM_AMOUNT, collateralAmount, 12, DATA);

        // Warp for unique CREATE2 salt, create second loan (6 months)
        vm.warp(t0 + 1000);
        (,, uint256 minDeposit2) = loan.getLoanDetails(collateralAmount, 6);
        vm.prank(user);
        loan.initializeLoan(minDeposit2, PREMIUM_AMOUNT, collateralAmount, 6, DATA);

        // Verify
        DataTypes.LoanData[] memory loans = loan.getUserAllLoans(user);
        assertEq(loans.length, 2, "Should return 2 loans");
        assertEq(loans[0].borrower, user, "First loan borrower mismatch");
        assertEq(loans[1].borrower, user, "Second loan borrower mismatch");
        assertEq(loans[0].duration, 12, "First loan duration mismatch");
        assertEq(loans[1].duration, 6, "Second loan duration mismatch");
    }

    // ============ 3. calculateStrikePrice Success (Fuzz) ============

    /// @notice Fuzz test for calculateStrikePrice with valid inputs
    /// @param loanAmount Bounded loan amount (1000 USDC to 1M USDC)
    /// @param deposit Bounded deposit (100 USDC to 500k USDC)
    function test_loan_calculateStrikePrice_fuzz(uint256 loanAmount, uint256 deposit) public view {
        // Bound inputs to realistic ranges (USDC has 6 decimals)
        loanAmount = bound(loanAmount, 1000e6, 1_000_000e6);
        deposit = bound(deposit, 100e6, 500_000e6);

        uint256 strikePrice = loan.calculateStrikePrice(loanAmount, deposit);
        assertGt(strikePrice, 0, "Strike price should be > 0");

        // Monotonicity: higher deposit with same loan should give LOWER strike
        // (more equity = lower breakeven price)
        if (deposit < 499_000e6) {
            uint256 higherDeposit = deposit + 1000e6;
            uint256 strikeLower = loan.calculateStrikePrice(loanAmount, higherDeposit);
            assertLe(strikeLower, strikePrice, "Higher deposit should give <= strike price");
        }
    }

    // ============ 4. calculateStrikePrice Zero Oracle Price ============

    /// @notice Validates InvalidAssetPrice when oracle returns zero
    function test_loan_calculateStrikePrice_zeroOraclePrice_reverts() public {
        address oracle = loan.i_ORACLE();

        vm.mockCall(
            oracle,
            abi.encodeWithSelector(IPriceOracleGetter.getAssetPrice.selector, collateralAsset),
            abi.encode(0)
        );

        vm.expectRevert(Errors.InvalidAssetPrice.selector);
        loan.calculateStrikePrice(10_000e6, 5_000e6);

        vm.clearMockedCalls();
    }

    // ============ 5. calculateStrikePrice Zero Amount Guards (Combined) ============

    /// @notice Validates ZeroAmount for all zero-input combinations
    function test_loan_calculateStrikePrice_zeroAmount_reverts() public {
        // Zero loanAmount
        vm.expectRevert(Errors.ZeroAmount.selector);
        loan.calculateStrikePrice(0, 5_000e6);

        // Zero deposit
        vm.expectRevert(Errors.ZeroAmount.selector);
        loan.calculateStrikePrice(10_000e6, 0);

        // Both zero (reverts on first check)
        vm.expectRevert(Errors.ZeroAmount.selector);
        loan.calculateStrikePrice(0, 0);
    }

    // ============ 6. FlashLoanReceiver Getters ============

    /// @notice Validates ADDRESSES_PROVIDER and POOL match constructor values
    function test_loan_flashLoanReceiver_getters_matchConstructor() public view {
        assertEq(
            address(loan.ADDRESSES_PROVIDER()),
            s_addressesProvider,
            "ADDRESSES_PROVIDER mismatch"
        );
        assertEq(
            address(loan.POOL()),
            aavePool,
            "POOL mismatch"
        );
    }

    // ============ 7. Constructor Zero-Address Reverts (Table-Driven) ============

    /// @notice Table-driven test for constructor zero-address validation
    function test_loan_constructor_zeroAddress_tableDriven_reverts() public {
        // Get valid config
        (
            address bitmorPool,
            address aaveV3Pool,
            address aaveAddressesProvider,
            address oracle,
            address collateralAssetAddr,
            address debtAssetAddr,
            address swapAdapterWrapper,
            address zQuoter,
            address premiumCollector,
            uint256 preClosureFeeBps,
            uint256 gracePeriod,
            uint256 liquidationBuffer
        ) = config.networkConfig();

        // Test cases: index of parameter to zero out
        // 0=aaveV3Pool, 1=bitmorPool, 2=oracle, 3=collateralAsset, 4=debtAsset, 5=swapAdapter, 6=premiumCollector
        for (uint256 i = 0; i < 7; i++) {
            address[7] memory params = [
                aaveV3Pool,
                bitmorPool,
                oracle,
                collateralAssetAddr,
                debtAssetAddr,
                swapAdapterWrapper,
                premiumCollector
            ];

            // Zero out the i-th parameter
            params[i] = address(0);

            vm.expectRevert(Errors.ZeroAddress.selector);
            new Loan(
                params[0],              // aaveV3Pool
                aaveAddressesProvider,  // not tested (known bug)
                params[1],              // bitmorPool
                params[2],              // oracle
                params[3],              // collateralAsset
                params[4],              // debtAsset
                params[5],              // swapAdapterWrapper
                zQuoter,                // allowed to be zero
                params[6],              // premiumCollector
                preClosureFeeBps,
                gracePeriod,
                liquidationBuffer
            );
        }
    }

    // ============ 8. Known Bug: Missing aaveAddressesProvider Validation ============

    /// @notice Documents bug: aaveAddressesProvider not validated in LoanStorage constructor
    /// @dev Location: LoanStorage.sol lines 102-105
    /// @dev Fix: Add `|| _aaveAddressesProvider == address(0)` to validation check
    function test_loan_constructor_zeroAaveAddressesProvider_BUG() public {
        (
            address bitmorPool,
            address aaveV3Pool,
            ,  // aaveAddressesProvider - testing with address(0)
            address oracle,
            address collateralAssetAddr,
            address debtAssetAddr,
            address swapAdapterWrapper,
            address zQuoter,
            address premiumCollector,
            uint256 preClosureFeeBps,
            uint256 gracePeriod,
            uint256 liquidationBuffer
        ) = config.networkConfig();

        // BUG: This succeeds but should revert
        Loan buggyLoan = new Loan(
            aaveV3Pool,
            address(0),  // _aaveAddressesProvider = address(0) - NOT VALIDATED
            bitmorPool,
            oracle,
            collateralAssetAddr,
            debtAssetAddr,
            swapAdapterWrapper,
            zQuoter,
            premiumCollector,
            preClosureFeeBps,
            gracePeriod,
            liquidationBuffer
        );

        // Confirms bug: ADDRESSES_PROVIDER returns zero
        assertEq(
            address(buggyLoan.ADDRESSES_PROVIDER()),
            address(0),
            "BUG: aaveAddressesProvider accepted as zero"
        );
    }
}
