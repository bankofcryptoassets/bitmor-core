// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.30;

import {BaseLoanTest} from "./BaseLoan.t.sol";
import {DataTypes} from "@bitmor/libraries/types/DataTypes.sol";
import {Errors} from "@bitmor/libraries/helpers/Errors.sol";
import {IPriceOracleGetter} from "@bitmor/interfaces/IPriceOracleGetter.sol";
import {Loan} from "@bitmor/protocol/Loan.sol";

/// @title LoanContract
/// @notice Consolidated tests for core Loan contract functionality
contract LoanContract is BaseLoanTest {
    /// @notice Reverts on zero-address inputs for all Loan view functions that accept a user/LSA address.
    function test_loan_viewFunctions_zeroAddress_reverts() public {
        vm.expectRevert(Errors.ZeroAddress.selector);
        loan.getUserAllLoans(address(0));

        vm.expectRevert(Errors.ZeroAddress.selector);
        loan.getUserLoanCount(address(0));

        vm.expectRevert(Errors.ZeroAddress.selector);
        loan.getUserLoanAtIndex(address(0), 0);

        vm.expectRevert(Errors.ZeroAddress.selector);
        loan.getLoanByLSA(address(0));
    }

    /// @notice getUserAllLoans returns both loans created by the same user with correct borrower and duration fields.
    function test_loan_getUserAllLoans_multipleLoans_success() public mintDebtAssetToUser {
        uint256 collateralAmount = STANDARD_COLLATERAL_AMOUNT;
        uint256 t0 = block.timestamp;

        (,, uint256 minDeposit1) = loan.getLoanDetails(collateralAmount, 12);
        vm.prank(user);
        loan.initializeLoan(minDeposit1, PREMIUM_AMOUNT, collateralAmount, 12, DATA);

        vm.warp(t0 + 1000); // ensure a unique CREATE2 salt for the second loan
        (,, uint256 minDeposit2) = loan.getLoanDetails(collateralAmount, 6);
        vm.prank(user);
        loan.initializeLoan(minDeposit2, PREMIUM_AMOUNT, collateralAmount, 6, DATA);

        DataTypes.LoanData[] memory loans = loan.getUserAllLoans(user);
        assertEq(loans.length, 2, "Should return 2 loans");
        assertEq(loans[0].borrower, user, "First loan borrower mismatch");
        assertEq(loans[1].borrower, user, "Second loan borrower mismatch");
        assertEq(loans[0].duration, 12, "First loan duration mismatch");
        assertEq(loans[1].duration, 6, "Second loan duration mismatch");
    }

    /// @notice Fuzz: calculateStrikePrice returns a non-zero strike price and is non-increasing as deposit increases.
    /// @param loanAmount Bounded loan amount (1,000 USDC to 1,000,000 USDC).
    /// @param deposit Bounded deposit (100 USDC to 500,000 USDC).
    function test_loan_calculateStrikePrice_fuzz(uint256 loanAmount, uint256 deposit) public view {
        loanAmount = bound(loanAmount, 1000e6, 1_000_000e6);
        deposit = bound(deposit, 100e6, 500_000e6);

        uint256 strikePrice = loan.calculateStrikePrice(loanAmount, deposit);
        assertGt(strikePrice, 0, "Strike price should be > 0");

        if (deposit < 499_000e6) {
            uint256 higherDeposit = deposit + 1000e6;
            uint256 strikeLower = loan.calculateStrikePrice(loanAmount, higherDeposit);
            assertLe(strikeLower, strikePrice, "Higher deposit should give <= strike price");
        }
    }

    /// @notice calculateStrikePrice reverts with InvalidAssetPrice when the oracle returns zero.
    function test_loan_calculateStrikePrice_zeroOraclePrice_reverts() public {
        address oracle = loan.i_ORACLE();

        vm.mockCall(
            oracle, abi.encodeWithSelector(IPriceOracleGetter.getAssetPrice.selector, collateralAsset), abi.encode(0)
        );

        vm.expectRevert(Errors.InvalidAssetPrice.selector);
        loan.calculateStrikePrice(10_000e6, 5_000e6);

        vm.clearMockedCalls();
    }

    /// @notice calculateStrikePrice reverts with ZeroAmount when loanAmount and/or deposit is zero.
    function test_loan_calculateStrikePrice_zeroAmount_reverts() public {
        vm.expectRevert(Errors.ZeroAmount.selector);
        loan.calculateStrikePrice(0, 5_000e6);

        vm.expectRevert(Errors.ZeroAmount.selector);
        loan.calculateStrikePrice(10_000e6, 0);

        vm.expectRevert(Errors.ZeroAmount.selector);
        loan.calculateStrikePrice(0, 0);
    }

    /// @notice FlashLoanReceiver getters (ADDRESSES_PROVIDER and POOL) match the configured constructor values.
    function test_loan_flashLoanReceiver_getters_matchConstructor() public view {
        assertEq(address(loan.ADDRESSES_PROVIDER()), s_addressesProvider, "ADDRESSES_PROVIDER mismatch");
        assertEq(address(loan.POOL()), aavePool, "POOL mismatch");
    }

    /// @notice Constructor reverts with ZeroAddress when any required address parameter is set to address(0).
    function test_loan_constructor_zeroAddress_tableDriven_reverts() public {
        // Use individual getters to avoid stack depth issues with full struct destructuring
        address accessManager = config.getAccessManager();
        address bitmorPool = config.getBitmorPool();
        address aaveV3Pool = config.getAaveV3Pool();
        address aaveAddressesProvider = config.getAaveAddressesProvider();
        address oracle = config.getOracle();
        address collateralAssetAddr = config.getCollateralAsset();
        address debtAssetAddr = config.getDebtAsset();
        address btc = config.getCbBTC();
        address swapAdapterWrapper = config.getSwapAdapterWrapper();
        address zQuoter = config.getZQuoter();
        address premiumCollector = config.getPremiumCollector();
        uint256 preClosureFeeBps = config.getPreClosureFee();
        uint256 gracePeriod = config.getGracePeriod();
        uint256 liquidationBuffer = config.getLiquidationBuffer();

        // 0=aaveV3Pool, 1=bitmorPool, 2=oracle, 3=collateralAsset, 4=debtAsset, 5=swapAdapter, 6=premiumCollector
        for (uint256 i = 0; i < 7; i++) {
            address[8] memory params = [
                aaveV3Pool,
                bitmorPool,
                oracle,
                collateralAssetAddr,
                debtAssetAddr,
                btc,
                swapAdapterWrapper,
                premiumCollector
            ];

            params[i] = address(0);

            vm.expectRevert(Errors.ZeroAddress.selector);
            new Loan(
                accessManager,
                params[0], // aaveV3Pool
                aaveAddressesProvider,
                params[1], // bitmorPool
                params[2], // oracle
                params[3], // collateralAsset
                params[4], // debtAsset
                params[5], // btc
                zQuoter, // swapAdapterWrapper
                params[6], // allowed to be zero
                params[7], // premiumCollector
                preClosureFeeBps,
                gracePeriod,
                liquidationBuffer
            );
        }
    }

    /// @notice Verifies constructor rejects aaveAddressesProvider = address(0).
    /// @dev This was previously a known bug (accepted zero address), now fixed.
    function test_loan_constructor_zeroAaveAddressesProvider_reverts() public {
        // Use individual getters to avoid stack depth issues with full struct destructuring
        address accessManager = config.getAccessManager();
        address bitmorPool = config.getBitmorPool();
        address aaveV3Pool = config.getAaveV3Pool();
        address oracle = config.getOracle();
        address collateralAssetAddr = config.getCollateralAsset();
        address debtAssetAddr = config.getDebtAsset();
        address btc = config.getCbBTC();
        address swapAdapterWrapper = config.getSwapAdapterWrapper();
        address zQuoter = config.getZQuoter();
        address premiumCollector = config.getPremiumCollector();
        uint256 preClosureFeeBps = config.getPreClosureFee();
        uint256 gracePeriod = config.getGracePeriod();
        uint256 liquidationBuffer = config.getLiquidationBuffer();

        // BUG FIX VERIFIED: Constructor now correctly reverts with ZeroAddress
        vm.expectRevert(Errors.ZeroAddress.selector);
        new Loan(
            accessManager,
            aaveV3Pool,
            address(0), // aaveAddressesProvider = address(0)
            bitmorPool,
            oracle,
            collateralAssetAddr,
            debtAssetAddr,
            btc,
            swapAdapterWrapper,
            zQuoter,
            premiumCollector,
            preClosureFeeBps,
            gracePeriod,
            liquidationBuffer
        );
    }
}
