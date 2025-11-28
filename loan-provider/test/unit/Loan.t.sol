// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {Loan} from "@bitmor/protocol/Loan.sol";
import {LoanVault} from "@bitmor/protocol/LoanVault.sol";
import {LoanVaultFactory} from "@bitmor/protocol/LoanVaultFactory.sol";
import {DataTypes} from "@bitmor/libraries/types/DataTypes.sol";
import {IERC20} from "@bitmor/dependencies/openzeppelin/IERC20.sol";
import {Errors} from "@bitmor/libraries/helpers/Errors.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {FixedPointMathLib} from "@solady/utils/FixedPointMathLib.sol";

contract LoanTest is Test {
    using FixedPointMathLib for uint256;

    HelperConfig config;
    Loan loan;

    address owner;
    address user;
    address debtAsset;
    address aavePool;
    address collateralAsset;

    /// @dev Premium amount is arbitary as it calculated offchain.
    /// Premium amount is required in debtAsset, bUSDC, which is of 6 decimals. Therefore 1000e6 = 1000 bUSDC
    uint256 PREMIUM_AMOUNT = 1000e6;
    /// @dev Insurance id is arbitary. Anything greater than 0 indicates that user had opted in for insurance.
    uint256 INSURANCE_ID = 1;

    uint256 DEBT_ASSET_TO_MINT_TO_USER = 1_000_000 * 1e6;

    function setUp() public {
        config = new HelperConfig();

        owner = makeAddr("owner");
        user = makeAddr("user");

        vm.startBroadcast(owner);

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
            uint256 gracePeriod
        ) = config.networkConfig();

        debtAsset = debtAssetAddr;
        aavePool = aaveV3Pool;
        collateralAsset = collateralAssetAddr;

        loan = new Loan(
            aaveV3Pool,
            aaveAddressesProvider,
            bitmorPool,
            oracle,
            collateralAsset,
            debtAsset,
            swapAdapterWrapper,
            zQuoter,
            premiumCollector,
            preClosureFeeBps,
            gracePeriod
        );

        address loanVaultImplementation = address(new LoanVault());

        address loanVaultFactory = address(new LoanVaultFactory(loanVaultImplementation, address(loan)));

        loan.setLoanVaultFactory(loanVaultFactory);

        vm.stopBroadcast();
    }

    // ============ Modifiers ============

    modifier mintDebtAssetToUser() {
        _mintDebtAssetToUser();
        _;
    }

    modifier setUpLoanForUser() {
        _setUpLoanForUser();
        _;
    }

    // ============ Loan Initialization ============

    function test_initializeLoan_whenDepositAmountIsEqualToMinimumDepositRequired() public mintDebtAssetToUser {
        /// @dev bcbBTC is of 8 decimals, therefore, 1e8 = 1 bcbBTC
        uint256 collateralAmount = 1e8;
        /// @dev Max Duration by default is set to 12. Therefore, this is to test with the max duration to get the least monthly payment amount.
        uint256 duration = 12;

        (,, uint256 minDepositRequired) = loan.getLoanDetails(collateralAmount, duration);

        vm.broadcast(user);
        address lsa = loan.initializeLoan(minDepositRequired, PREMIUM_AMOUNT, collateralAmount, duration, INSURANCE_ID);

        DataTypes.LoanData memory loanData = loan.getLoanByLSA(lsa);

        assertEq(user, loanData.borrower);
    }

    function test_initializeLoan_whenDepositAmountIsLessThanMinimumDepositRequired() public mintDebtAssetToUser {
        /// @dev bcbBTC is of 8 decimals, therefore, 1e8 = 1 bcbBTC
        uint256 collateralAmount = 1e8;
        /// @dev Max Duration by default is set to 12. Therefore, this is to test with the max duration to get the least monthly payment amount.
        uint256 duration = 12;

        (,, uint256 minDepositRequired) = loan.getLoanDetails(collateralAmount, duration);

        vm.broadcast(user);
        vm.expectRevert(Errors.InsufficientDeposit.selector);
        loan.initializeLoan(minDepositRequired - 1, PREMIUM_AMOUNT, collateralAmount, duration, INSURANCE_ID);
    }

    function test_initializeLoan_whenDepositAmountIsGreaterThanMinimumDepositRequired() public mintDebtAssetToUser {
        /// @dev bcbBTC is of 8 decimals, therefore, 1e8 = 1 bcbBTC
        uint256 collateralAmount = 1e8;
        /// @dev Max Duration by default is set to 12. Therefore, this is to test with the max duration to get the least monthly payment amount.
        uint256 duration = 12;

        (,, uint256 minDepositRequired) = loan.getLoanDetails(collateralAmount, duration);

        vm.broadcast(user);
        address lsa =
            loan.initializeLoan(minDepositRequired + 1, PREMIUM_AMOUNT, collateralAmount, duration, INSURANCE_ID);

        DataTypes.LoanData memory loanData = loan.getLoanByLSA(lsa);

        assertEq(user, loanData.borrower);
    }

    // ============ Loan Repayment ============

    function test_repay_exactlyEstimatedMonthlyAmount() public setUpLoanForUser {
        /// @dev Since we have set up only one loan in `setUpLoanForUser` the index will be equal to 0;
        uint256 index = 0;

        /// Get LSA address
        address lsa = loan.getUserLoanAtIndex(user, index);

        /// Get user LSA details before repayment.
        DataTypes.LoanData memory loanDataBefore = loan.getLoanByLSA(lsa);

        /// Loan duration before repayment.
        uint256 durationBefore = loanDataBefore.duration;

        /// Repay the loan with exactly `loanData.estimatedMonthlyPayment`
        uint256 repayAmount = loanDataBefore.estimatedMonthlyPayment;

        vm.broadcast(user);
        uint256 finalAmountRepaid = loan.repay(lsa, repayAmount);

        /// Get user LSA details after repayment.
        DataTypes.LoanData memory loanDataAfter = loan.getLoanByLSA(lsa);

        /// Loan duration after repayment.
        uint256 durationAfter = loanDataAfter.duration;

        /// Amount of loan duration the user paid for.
        uint256 periodsPaidFor = finalAmountRepaid.mulDiv(1, loanDataBefore.estimatedMonthlyPayment);

        assertEq(durationBefore - durationAfter, periodsPaidFor);
        assertEq(finalAmountRepaid, repayAmount);
    }

    function test_repay_lessThanEstimatedMonthlyAmount() public setUpLoanForUser {
        /// @dev Since we have set up only one loan in `setUpLoanForUser` the index will be equal to 0;
        uint256 index = 0;

        /// Get LSA address
        address lsa = loan.getUserLoanAtIndex(user, index);

        /// Get user LSA details before repayment.
        DataTypes.LoanData memory loanDataBefore = loan.getLoanByLSA(lsa);

        /// Loan duration before repayment.
        uint256 durationBefore = loanDataBefore.duration;

        /// Repay the loan with less than `loanData.estimatedMonthlyPayment`
        uint256 repayAmount = loanDataBefore.estimatedMonthlyPayment - 1;

        vm.broadcast(user);
        uint256 finalAmountRepaid = loan.repay(lsa, repayAmount);

        /// Get user LSA details after repayment.
        DataTypes.LoanData memory loanDataAfter = loan.getLoanByLSA(lsa);

        /// Loan duration after repayment.
        uint256 durationAfter = loanDataAfter.duration;

        /// Amount of loan duration the user paid for.
        uint256 periodsPaidFor = finalAmountRepaid.mulDiv(1, loanDataBefore.estimatedMonthlyPayment);

        assertEq(durationBefore - durationAfter, periodsPaidFor);
        assertEq(finalAmountRepaid, repayAmount);
    }

    function test_repay_moreThanEstimatedMonthlyAmount() public setUpLoanForUser {
        /// @dev Since we have set up only one loan in `setUpLoanForUser` the index will be equal to 0;
        uint256 index = 0;

        /// Get LSA address
        address lsa = loan.getUserLoanAtIndex(user, index);

        /// Get user LSA details before repayment.
        DataTypes.LoanData memory loanDataBefore = loan.getLoanByLSA(lsa);

        /// Loan duration before repayment.
        uint256 durationBefore = loanDataBefore.duration;

        /// Repay the loan with more than `loanData.estimatedMonthlyPayment`. Here we are testing for twice the amount.
        uint256 repayAmount = loanDataBefore.estimatedMonthlyPayment * 2;

        vm.broadcast(user);
        uint256 finalAmountRepaid = loan.repay(lsa, repayAmount);

        /// Get user LSA details after repayment.
        DataTypes.LoanData memory loanDataAfter = loan.getLoanByLSA(lsa);

        /// Loan duration after repayment.
        uint256 durationAfter = loanDataAfter.duration;

        /// Amount of loan duration the user paid for.
        uint256 periodsPaidFor = finalAmountRepaid.mulDiv(1, loanDataBefore.estimatedMonthlyPayment);

        assertEq(durationBefore - durationAfter, periodsPaidFor);
        assertEq(finalAmountRepaid, repayAmount);
    }

    // ============ Close Loan ============

    // TODO!: This is currently testing only the state update. We need to test the exact amount of collateral received.
    function test_closeLoan_withWithdrawingAssetInCollateralAsset() public setUpLoanForUser {
        /// @dev Since we have set up only one loan in `setUpLoanForUser` the index will be equal to 0;
        uint256 index = 0;

        /// Get LSA address
        address lsa = loan.getUserLoanAtIndex(user, index);

        /// Withdrawing in collateral asset.
        bool withdrawInCollateralAsset = true;

        /// Collateral Asset amount before.
        uint256 collateralAssetAmountBefore = IERC20(collateralAsset).balanceOf(user);

        vm.broadcast(user);
        loan.closeLoan(lsa, withdrawInCollateralAsset);

        uint256 collateralAssetAmountAfter = IERC20(collateralAsset).balanceOf(user);

        /// Get user LSA details after closing the loan.
        DataTypes.LoanData memory loanDataAfter = loan.getLoanByLSA(lsa);

        assertGt(collateralAssetAmountAfter - collateralAssetAmountBefore, 0);
        assertEq(uint256(loanDataAfter.status), uint256(DataTypes.LoanStatus.Completed));
    }

    // TODO!: This is currently testing only the state update. We need to test the exact amount of debt asset received.
    function test_closeLoan_withoutWithdrawingAssetInCollateralAsset() public setUpLoanForUser {
        /// @dev Since we have set up only one loan in `setUpLoanForUser` the index will be equal to 0;
        uint256 index = 0;

        /// Get LSA address
        address lsa = loan.getUserLoanAtIndex(user, index);

        /// Withdrawing in debt asset.
        bool withdrawInCollateralAsset = false;

        /// Collateral Asset amount before.
        uint256 debtAssetAmountBefore = IERC20(debtAsset).balanceOf(user);

        vm.broadcast(user);
        loan.closeLoan(lsa, withdrawInCollateralAsset);

        uint256 debtAssetAmountAfter = IERC20(debtAsset).balanceOf(user);

        /// Get user LSA details after closing the loan.
        DataTypes.LoanData memory loanDataAfter = loan.getLoanByLSA(lsa);

        assertGt(debtAssetAmountAfter - debtAssetAmountBefore, 0);
        assertEq(uint256(loanDataAfter.status), uint256(DataTypes.LoanStatus.Completed));
    }

    // ============ Internal Functions ============

    function _mintDebtAssetToUser() internal {
        vm.startBroadcast(user);
        (bool success,) = debtAsset.call(abi.encodeWithSignature("mint(uint256)", DEBT_ASSET_TO_MINT_TO_USER));
        if (!success) {
            revert("MINT_ERROR");
        }

        IERC20(debtAsset).approve(address(loan), DEBT_ASSET_TO_MINT_TO_USER);
        vm.stopBroadcast();
    }

    function _setUpLoanForUser() internal {
        _mintDebtAssetToUser();

        uint256 collateralAmount = 1e8;
        uint256 duration = 12;

        (,, uint256 minDepositRequired) = loan.getLoanDetails(collateralAmount, duration);

        vm.broadcast(user);
        loan.initializeLoan(minDepositRequired, PREMIUM_AMOUNT, collateralAmount, duration, INSURANCE_ID);
    }
}
