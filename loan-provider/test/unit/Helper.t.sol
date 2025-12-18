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
import {ILendingPool} from "@bitmor/interfaces/ILendingPool.sol";
import {ILendingPoolAddressesProvider} from "@bitmor/interfaces/ILendingPoolAddressesProvider.sol";
import {IPriceOracleGetter} from "@bitmor/interfaces/IPriceOracleGetter.sol";

/// @title Helper
/// @notice Base test contract with shared setup, state variables, and helper functions
/// @dev Other test contracts should inherit from this contract
abstract contract Helper is Test {
    using FixedPointMathLib for uint256;

    // ============ State Variables ============

    HelperConfig config;
    Loan loan;

    address owner;
    address user;
    address debtAsset;
    address aavePool;
    address collateralAsset;

    address s_bitmorPool;
    address s_addressesProvider;
    address liquidator;
    uint256 s_gracePeriod;

    /// @dev Premium amount is arbitary as it calculated offchain.
    /// Premium amount is required in debtAsset, bUSDC, which is of 6 decimals. Therefore 1000e6 = 1000 bUSDC
    uint256 constant PREMIUM_AMOUNT = 1000e6;

    /// @dev Insurance id is arbitary. Anything greater than 0 indicates that user had opted in for insurance.
    uint256 constant INSURANCE_ID = 1;

    uint256 constant DEBT_ASSET_TO_MINT_TO_USER = 1_000_000 * 1e6;

    uint256 constant LOAN_REPAYMENT_INTERVAL = 30 days;

    // ============ Setup ============

    function setUp() public virtual {
        config = new HelperConfig();

        owner = makeAddr("owner");
        user = makeAddr("user");
        liquidator = makeAddr("liquidator");

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
        s_bitmorPool = bitmorPool;
        s_gracePeriod = gracePeriod;
        s_addressesProvider = aaveAddressesProvider;

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

    // ============ Internal Helper Functions ============

    /// @dev Mint debt asset to user and approve loan contract
    function _mintDebtAssetToUser() internal {
        vm.startBroadcast(user);
        (bool success,) = debtAsset.call(abi.encodeWithSignature("mint(uint256)", DEBT_ASSET_TO_MINT_TO_USER));
        if (!success) {
            revert("MINT_ERROR");
        }

        IERC20(debtAsset).approve(address(loan), DEBT_ASSET_TO_MINT_TO_USER);
        vm.stopBroadcast();
    }

    /// @dev Set up a standard loan for user (1 BTC, 12 months)
    function _setUpLoanForUser() internal {
        _mintDebtAssetToUser();

        uint256 collateralAmount = 1e8;
        uint256 duration = 12;

        (,, uint256 minDepositRequired) = loan.getLoanDetails(collateralAmount, duration);

        vm.broadcast(user);
        loan.initializeLoan(minDepositRequired, PREMIUM_AMOUNT, collateralAmount, duration, INSURANCE_ID);
    }

    /// @dev Update the Bitmor Lending Pool's AddressesProvider to point to our test's Loan contract
    /// This is necessary because the forked testnet's AddressesProvider points to the OLD deployed Loan contract
    function _updateAddressesProviderBitmorLoan() internal {
        address addressesProvider = ILendingPool(s_bitmorPool).getAddressesProvider();

        console2.log("=== Updating AddressesProvider ===");
        console2.log("AddressesProvider:", addressesProvider);
        console2.log("Old Bitmor Loan:", ILendingPoolAddressesProvider(addressesProvider).getBitmorLoan());
        console2.log("New Bitmor Loan (test):", address(loan));

        address poolAdmin = ILendingPoolAddressesProvider(addressesProvider).getPoolAdmin();
        console2.log("Pool Admin:", poolAdmin);

        vm.prank(poolAdmin);
        ILendingPoolAddressesProvider(addressesProvider).setBitmorLoan(address(loan));

        address updatedLoan = ILendingPoolAddressesProvider(addressesProvider).getBitmorLoan();
        console2.log("Updated Bitmor Loan:", updatedLoan);
        assertEq(updatedLoan, address(loan), "AddressesProvider should point to test Loan contract");
        console2.log("");
    }

    /// @dev Warp time past the grace period to trigger micro-liquidation eligibility (with logging)
    function _warpPastGracePeriod() internal {
        uint256 timeToWarp = LOAN_REPAYMENT_INTERVAL + s_gracePeriod + 1 days;

        console2.log("");
        console2.log("=== Time Warp Details ===");
        console2.log("Repayment Interval (seconds):", LOAN_REPAYMENT_INTERVAL);
        console2.log("Grace Period (seconds):", s_gracePeriod);
        console2.log("Total Time Warped (seconds):", timeToWarp);

        vm.warp(block.timestamp + timeToWarp);
        console2.log("Current Block Timestamp:", block.timestamp);
    }

    /// @dev Warp time past the grace period without logging (for repeated calls)
    function _warpPastGracePeriodSilent() internal {
        uint256 timeToWarp = LOAN_REPAYMENT_INTERVAL + s_gracePeriod + 1 days;
        vm.warp(block.timestamp + timeToWarp);
    }

    /// @dev Fund the liquidator with debt asset and approve spending
    function _fundLiquidator() internal {
        vm.startPrank(liquidator);
        (bool mintSuccess,) = debtAsset.call(abi.encodeWithSignature("mint(uint256)", DEBT_ASSET_TO_MINT_TO_USER));
        require(mintSuccess, "MINT_ERROR");
        IERC20(debtAsset).approve(s_bitmorPool, type(uint256).max);
        vm.stopPrank();
    }

    /// @dev Execute the micro liquidation call
    function _executeMicroLiquidation(address lsa) internal {
        bytes memory liquidationData = abi.encode(collateralAsset, debtAsset, lsa);
        vm.prank(liquidator);
        ILendingPool(s_bitmorPool).microLiquidationCall(liquidationData);
    }

    /// @dev Execute the full liquidation call
    /// @param lsa The Loan Smart Account address (user being liquidated)
    /// @param debtToCover The amount of debt the liquidator wants to cover (use type(uint256).max to cover max possible)
    /// @param receiveAToken True if liquidator wants aTokens, false for underlying collateral
    function _executeFullLiquidation(address lsa, uint256 debtToCover, bool receiveAToken) internal {
        vm.prank(liquidator);
        ILendingPool(s_bitmorPool).liquidationCall(
            collateralAsset,
            debtAsset,
            lsa,
            debtToCover,
            receiveAToken
        );
    }

    /// @dev Get BTC price from oracle
    function _getBtcPrice() internal view returns (uint256) {
        address addressesProvider = ILendingPool(s_bitmorPool).getAddressesProvider();
        address oracleAddress = ILendingPoolAddressesProvider(addressesProvider).getPriceOracle();
        return IPriceOracleGetter(oracleAddress).getAssetPrice(collateralAsset);
    }

    /// @dev Get USDC price from oracle
    function _getUsdcPrice() internal view returns (uint256) {
        address addressesProvider = ILendingPool(s_bitmorPool).getAddressesProvider();
        address oracleAddress = ILendingPoolAddressesProvider(addressesProvider).getPriceOracle();
        return IPriceOracleGetter(oracleAddress).getAssetPrice(debtAsset);
    }
}
