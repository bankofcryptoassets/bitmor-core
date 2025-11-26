// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {Loan} from "@bitmor/loan/Loan.sol";
import {LoanVault} from "@bitmor/loan/LoanVault.sol";
import {LoanVaultFactory} from "@bitmor/loan/LoanVaultFactory.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {DataTypes} from "@bitmor/libraries/types/DataTypes.sol";
import {IERC20} from "@bitmor/dependencies/openzeppelin/IERC20.sol";
import {Errors} from "@bitmor/libraries/helpers/Errors.sol";

contract LoanTest is Test {
    HelperConfig config;
    Loan loan;

    address owner;
    address user;
    address debtAsset;
    address aavePool;

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
            address collateralAsset,
            address debtAssetAddr,
            address swapAdapterWrapper,
            address zQuoter,
            address premiumCollector,
            uint256 preClosureFeeBps,
            uint256 gracePeriod
        ) = config.networkConfig();

        debtAsset = debtAssetAddr;
        aavePool = aaveV3Pool;

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

    function test_initializeLoan_whenDepositAmountIsEqualToMinimumDepositRequired() public {
        /// @dev bcbBTC is of 8 decimals, therefore, 1e8 = 1 bcbBTC
        uint256 collateralAmount = 1e8;
        /// @dev Max Duration by default is set to 12. Therefore, this is to test with the max duration to get the least monthly payment amount.
        uint256 duration = 12;

        (,, uint256 minDepositRequired) = loan.getLoanDetails(collateralAmount, duration);

        vm.startBroadcast(user);
        (bool success,) = debtAsset.call(abi.encodeWithSignature("mint(uint256)", DEBT_ASSET_TO_MINT_TO_USER));
        if (!success) {
            revert("MINT_ERROR");
        }

        IERC20(debtAsset).approve(address(loan), DEBT_ASSET_TO_MINT_TO_USER);

        address lsa = loan.initializeLoan(minDepositRequired, PREMIUM_AMOUNT, collateralAmount, duration, INSURANCE_ID);
        vm.stopBroadcast();

        DataTypes.LoanData memory loanData = loan.getLoanByLSA(lsa);

        assertEq(user, loanData.borrower);
    }

    function test_initializeLoan_whenDepositAmountIsLessThanMinimumDepositRequired() public {
        /// @dev bcbBTC is of 8 decimals, therefore, 1e8 = 1 bcbBTC
        uint256 collateralAmount = 1e8;
        /// @dev Max Duration by default is set to 12. Therefore, this is to test with the max duration to get the least monthly payment amount.
        uint256 duration = 12;

        (,, uint256 minDepositRequired) = loan.getLoanDetails(collateralAmount, duration);

        vm.startBroadcast(user);
        (bool success,) = debtAsset.call(abi.encodeWithSignature("mint(uint256)", DEBT_ASSET_TO_MINT_TO_USER));
        if (!success) {
            revert("MINT_ERROR");
        }

        IERC20(debtAsset).approve(address(loan), DEBT_ASSET_TO_MINT_TO_USER);

        vm.expectRevert(Errors.InsufficientDeposit.selector);
        loan.initializeLoan(minDepositRequired - 1, PREMIUM_AMOUNT, collateralAmount, duration, INSURANCE_ID);
        vm.stopBroadcast();
    }

    function test_initializeLoan_whenDepositAmountIsGreaterThanMinimumDepositRequired() public {
        /// @dev bcbBTC is of 8 decimals, therefore, 1e8 = 1 bcbBTC
        uint256 collateralAmount = 1e8;
        /// @dev Max Duration by default is set to 12. Therefore, this is to test with the max duration to get the least monthly payment amount.
        uint256 duration = 12;

        (,, uint256 minDepositRequired) = loan.getLoanDetails(collateralAmount, duration);

        vm.startBroadcast(user);
        (bool success,) = debtAsset.call(abi.encodeWithSignature("mint(uint256)", DEBT_ASSET_TO_MINT_TO_USER));
        if (!success) {
            revert("MINT_ERROR");
        }

        IERC20(debtAsset).approve(address(loan), DEBT_ASSET_TO_MINT_TO_USER);

        address lsa =
            loan.initializeLoan(minDepositRequired + 1, PREMIUM_AMOUNT, collateralAmount, duration, INSURANCE_ID);
        vm.stopBroadcast();

        DataTypes.LoanData memory loanData = loan.getLoanByLSA(lsa);

        assertEq(user, loanData.borrower);
    }
}
