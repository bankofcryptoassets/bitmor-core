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
import {AutoRepayment} from "@bitmor/protocol/AutoRepayment.sol";
import {IAutoRepayment} from "@bitmor/interfaces/IAutoRepayment.sol";

contract AutoRepaymentTest is Test {
    Loan loan;
    AutoRepayment autoRepay;
    HelperConfig config;

    address owner;
    address user;
    address executor;
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
        executor = makeAddr("executor");

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

        autoRepay = new AutoRepayment(address(loan), debtAsset, executor);

        vm.stopBroadcast();
    }

    modifier setUpLoanForUser() {
        _setUpLoanForUser();
        _;
    }

    modifier setUpAutoRepayment() {
        _setupAutoRepayment();
        _;
    }

    function test_createAutoRepayment() public setUpLoanForUser {
        /// @dev Since we have set up only one loan in `setUpLoanForUser` the index will be equal to 0;
        uint256 index = 0;

        /// Get LSA address
        address lsa = loan.getUserLoanAtIndex(user, index);

        vm.broadcast(user);
        vm.expectEmit(true, true, false, false);
        emit IAutoRepayment.AutoRepayment__RepaymentCreated(lsa, user);
        autoRepay.createAutoRepayment(lsa);
    }

    function test_executeAutoRepayment() public setUpAutoRepayment {
        /// @dev Since we have set up only one loan in `setUpLoanForUser` the index will be equal to 0;
        uint256 index = 0;

        /// Get LSA address
        address lsa = loan.getUserLoanAtIndex(user, index);

        /// Get user LSA details before repayment
        DataTypes.LoanData memory loanDataBefore = loan.getLoanByLSA(lsa);

        /// Loan duration before repayment.
        uint256 durationBefore = loanDataBefore.duration;

        vm.broadcast(executor);
        autoRepay.executeAutoRepayment(lsa, user, loanDataBefore.estimatedMonthlyPayment);

        /// Get user LSA details after repayment.
        DataTypes.LoanData memory loanDataAfter = loan.getLoanByLSA(lsa);

        /// Loan duration after repayment.
        uint256 durationAfter = loanDataAfter.duration;

        assertEq(durationBefore - durationAfter, 1);
    }

    function _mintDebtAssetToUser() internal {
        vm.startBroadcast(user);
        (bool success,) = debtAsset.call(abi.encodeWithSignature("mint(uint256)", DEBT_ASSET_TO_MINT_TO_USER));
        if (!success) {
            revert("MINT_ERROR");
        }

        IERC20(debtAsset).approve(address(loan), DEBT_ASSET_TO_MINT_TO_USER);
        vm.stopBroadcast();
    }

    function _setUpLoanForUser() internal returns (address lsa) {
        _mintDebtAssetToUser();

        uint256 collateralAmount = 1e8;
        uint256 duration = 12;

        (,, uint256 minDepositRequired) = loan.getLoanDetails(collateralAmount, duration);

        vm.broadcast(user);
        lsa = loan.initializeLoan(minDepositRequired, PREMIUM_AMOUNT, collateralAmount, duration, INSURANCE_ID);
    }

    function _setupAutoRepayment() internal {
        address lsa = _setUpLoanForUser();

        vm.startBroadcast(user);
        IERC20(debtAsset).approve(address(autoRepay), DEBT_ASSET_TO_MINT_TO_USER);
        autoRepay.createAutoRepayment(lsa);
        vm.stopBroadcast();
    }
}
