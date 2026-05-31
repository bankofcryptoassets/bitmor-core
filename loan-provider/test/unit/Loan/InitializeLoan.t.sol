// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {console2} from "forge-std/console2.sol";
import {BaseLoanTest} from "./BaseLoan.t.sol";
import {TestConstants as TC} from "../../helpers/TestConstants.sol";
import {DataTypes} from "@bitmor/libraries/types/DataTypes.sol";
import {Errors} from "@bitmor/libraries/helpers/Errors.sol";
import {ILoanVault} from "@bitmor/interfaces/ILoanVault.sol";
import {IPriceOracleGetter} from "@bitmor/interfaces/IPriceOracleGetter.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import {Loan} from "@bitmor/protocol/Loan.sol";
import {ILoan} from "@bitmor/interfaces/ILoan.sol";
import {LoanVault} from "@bitmor/protocol/LoanVault.sol";
import {LoanVaultFactory} from "@bitmor/protocol/LoanVaultFactory.sol";
import {BitmorAddressesProvider} from "@bitmor/protocol/BitmorAddressesProvider.sol";
import {MockAaveV3Pool} from "../../mock/MockAaveV3Pool.sol";
import {BitmorAccessManager} from "@bitmor/accessManager/BitmorAccessManager.sol";

import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";

/// @title InitializeLoanTest
/// @author Bitmor Protocol
/// @notice Tests for `Loan.initializeLoan` covering deposits, collateral boundaries, access control, and flash loans
contract InitializeLoanTest is BaseLoanTest {
    // ============ Local Test Helpers ============

    /// @notice Asserts that a loan at `lsa` was created with the expected borrower, duration, and collateral
    function _assertLoanCreated(
        address lsa,
        address expectedBorrower,
        uint256 expectedDuration,
        uint256 expectedCollateral
    ) internal view {
        DataTypes.LoanData memory loanData = loan.getLoanByLSA(lsa);
        assertEq(loanData.borrower, expectedBorrower, "Borrower mismatch");
        assertEq(loanData.duration, expectedDuration, "Duration mismatch");
        assertEq(loanData.btcAmount, expectedCollateral, "Collateral mismatch");
        assertEq(uint256(loanData.status), uint256(DataTypes.LoanStatus.Active), "Status should be Active");
    }

    /// @notice Asserts that `loanData` has the expected borrower, duration, and non-zero loan amount and payment
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

    /// @notice Initializes a loan with zero premium amount
    function test_initializeLoan_ZeroPremium() public {
        (uint256 expectedLoanAmt,, uint256 minDeposit) =
            loan.getLoanDetails(STANDARD_COLLATERAL_AMOUNT, STANDARD_DURATION);
        uint256 zeroPremium = 0;

        _mintDebtAssetToUser();

        vm.prank(user);
        address lsa = loan.initializeLoan(minDeposit, zeroPremium, STANDARD_COLLATERAL_AMOUNT, STANDARD_DURATION, "");

        assertNotEq(lsa, address(0), "LSA should be created");

        DataTypes.LoanData memory data = loan.getLoanByLSA(lsa);
        assertEq(data.borrower, user, "Borrower should match");
        assertEq(data.btcAmount, STANDARD_COLLATERAL_AMOUNT, "Collateral should match");
        assertEq(data.loanAmount, expectedLoanAmt, "Loan amount should match");
        assertEq(data.duration, STANDARD_DURATION, "Duration should match");
        assertEq(uint8(data.status), uint8(DataTypes.LoanStatus.Active), "Status should be Active");
    }

    /// @notice Reverts when deposit is below the minimum required.
    function test_initializeLoan_RevertWhen_DepositBelowMinimum() public mintDebtAssetToUser {
        // This test specifically needs less-than-minimum deposit, so keep manual pattern
        uint256 btcAmount = STANDARD_COLLATERAL_AMOUNT;
        uint256 duration = STANDARD_DURATION;

        (,, uint256 minDepositRequired) = loan.getLoanDetails(btcAmount, duration);

        vm.prank(user);
        _expectRevertSelector(Errors.InsufficientDeposit.selector);
        loan.initializeLoan(minDepositRequired - 1, PREMIUM_AMOUNT, btcAmount, duration, DATA);
    }

    /// @notice Initializes a loan when deposit is above the minimum required.
    function test_initializeLoan_whenDepositAmountIsGreaterThanMinimumDepositRequired() public mintDebtAssetToUser {
        // This test specifically needs more-than-minimum deposit
        uint256 btcAmount = STANDARD_COLLATERAL_AMOUNT;
        uint256 duration = STANDARD_DURATION;

        (,, uint256 minDepositRequired) = loan.getLoanDetails(btcAmount, duration);

        vm.prank(user);
        address lsa = loan.initializeLoan(minDepositRequired + 1, PREMIUM_AMOUNT, btcAmount, duration, DATA);

        _assertLoanCreated(lsa, user, duration, btcAmount);
    }

    /// @notice Reverts when loan size is below the protocol minimum.
    function test_initializeLoan_RevertWhen_LoanSizeBelowMinimum() public mintDebtAssetToUser {
        uint256 duration = STANDARD_DURATION;

        uint256 btcAmount = loan.getMinBTCAmount() - 1;

        vm.expectRevert(Errors.LessThanMinBTCAllowed.selector);
        loan.getLoanDetails(btcAmount, duration);
    }

    // ============ Max Collateral Boundary Tests ============

    /// @notice Initializes a loan with exact maximum collateral amount
    function test_initializeLoan_ExactMaxCollateral() public {
        uint256 maxBTC = loan.getMaxBTCAmount();
        (uint256 expectedLoanAmt, uint256 expectedMonthly, uint256 minDeposit) =
            loan.getLoanDetails(maxBTC, STANDARD_DURATION);

        _mintDebtAssetToUser();

        vm.prank(user);
        address lsa = loan.initializeLoan(minDeposit, PREMIUM_AMOUNT, maxBTC, STANDARD_DURATION, "");

        assertNotEq(lsa, address(0), "LSA should be created");

        DataTypes.LoanData memory data = loan.getLoanByLSA(lsa);
        assertEq(data.btcAmount, maxBTC, "Collateral should be exact max");
        assertEq(data.loanAmount, expectedLoanAmt, "Loan amount should match calculation");
        assertGt(data.estimatedMonthlyPayment, 0, "Monthly payment should be positive");
        assertEq(data.duration, STANDARD_DURATION, "Duration should match");
    }

    /// @notice Reverts when collateral exceeds maximum (executeInitializeLoan path)
    function test_initializeLoan_RevertWhen_CollateralAboveMax() public {
        uint256 maxBTC = loan.getMaxBTCAmount();
        uint256 aboveMax = maxBTC + 1;

        _mintDebtAssetToUser();

        vm.prank(user);
        vm.expectRevert(Errors.GreaterThanMaxBTCAllowed.selector);
        loan.initializeLoan(100_000e6, PREMIUM_AMOUNT, aboveMax, STANDARD_DURATION, "");
    }

    /// @notice Reverts when collateral is below minimum (executeInitializeLoan path)
    function test_initializeLoan_RevertWhen_CollateralBelowMin() public {
        uint256 minBTC = loan.getMinBTCAmount();
        uint256 belowMin = minBTC - 1;

        _mintDebtAssetToUser();

        vm.prank(user);
        vm.expectRevert(Errors.LessThanMinBTCAllowed.selector);
        loan.initializeLoan(100_000e6, PREMIUM_AMOUNT, belowMin, STANDARD_DURATION, "");
    }

    /// @notice Table-driven test for collateral boundaries
    function test_calculateLoanDetails_collateralBoundaries_tableDriven() public {
        uint256 minBTC = loan.getMinBTCAmount();
        uint256 maxBTC = loan.getMaxBTCAmount();
        uint256 duration = 12;

        // Below min - should revert
        vm.expectRevert(Errors.LessThanMinBTCAllowed.selector);
        loan.getLoanDetails(minBTC - 1, duration);

        // Exactly min - should succeed
        (uint256 loanAmt,,) = loan.getLoanDetails(minBTC, duration);
        assertGt(loanAmt, 0, "Min boundary should return valid loan");

        // Exactly max - should succeed
        (loanAmt,,) = loan.getLoanDetails(maxBTC, duration);
        assertGt(loanAmt, 0, "Max boundary should return valid loan");

        // Above max - should revert
        vm.expectRevert(Errors.GreaterThanMaxBTCAllowed.selector);
        loan.getLoanDetails(maxBTC + 1, duration);
    }

    /// @notice Validates minimum deposit percentage calculation
    function test_initializeLoan_revertWhenThanMinimumDownpayment() public mintDebtAssetToUser {
        uint256 btcAmount = STANDARD_COLLATERAL_AMOUNT;
        uint256 duration = STANDARD_DURATION;

        (, uint256 monthlyPayment, uint256 minDepositRequired) = loan.getLoanDetails(btcAmount, duration);

        console2.log("minDepositRequired:", minDepositRequired);

        assertGt(monthlyPayment, 0, "Monthly payment must be non-zero");

        uint256 btcPrice = _getBtcPrice();
        uint256 totalSizeUSD =
            (btcAmount * btcPrice) / (TC.PRICE_PRECISION * (10 ** IERC20Metadata(mockCbBTC).decimals()));
        console2.log("totalSizeUSD: ", totalSizeUSD);

        uint256 usdPrice = _getUsdcPrice();
        uint256 minDepositRequiredUSD =
            (minDepositRequired * usdPrice) / (TC.PRICE_PRECISION * (10 ** IERC20Metadata(mockUSDC).decimals()));

        uint256 ownershipBps = (minDepositRequiredUSD * 10_000) / (totalSizeUSD);

        assertEq(ownershipBps, loan.getMinDepositBps());

        // Rejection below minimum deposit
        vm.prank(user);
        _expectRevertSelector(Errors.InsufficientDeposit.selector);
        loan.initializeLoan(minDepositRequired - 1, PREMIUM_AMOUNT, btcAmount, duration, DATA);
    }

    /// @notice Reverts when duration is zero
    function test_initializeLoan_RevertWhen_DurationIsZero() public mintDebtAssetToUser {
        uint256 btcAmount = STANDARD_COLLATERAL_AMOUNT;

        // getLoanDetails reverts for duration 0
        _expectRevertSelector(Errors.Loan__InvalidDuration.selector);
        loan.getLoanDetails(btcAmount, 0);

        // initializeLoan reverts for duration 0
        uint256 bigDeposit = 500_000e6;
        vm.prank(user);
        _expectRevertSelector(Errors.Loan__InvalidDuration.selector);
        loan.initializeLoan(bigDeposit, PREMIUM_AMOUNT, btcAmount, 0, DATA);
    }

    /// @notice Reverts when duration exceeds the maximum allowed
    function test_initializeLoan_RevertWhen_DurationExceedsMax() public mintDebtAssetToUser {
        uint256 btcAmount = STANDARD_COLLATERAL_AMOUNT;
        uint256 maxDuration = loan.getMaxDuration();

        // One above max reverts in getLoanDetails
        _expectRevertSelector(Errors.Loan__InvalidDuration.selector);
        loan.getLoanDetails(btcAmount, maxDuration + 1);

        // type(uint256).max reverts in initializeLoan (the exploit case)
        uint256 bigDeposit = 500_000e6;
        vm.prank(user);
        _expectRevertSelector(Errors.Loan__InvalidDuration.selector);
        loan.initializeLoan(bigDeposit, PREMIUM_AMOUNT, btcAmount, type(uint256).max, DATA);
    }

    /// @notice Successfully calculates loan details at the maximum allowed duration
    function test_initializeLoan_AtMaxDuration() public {
        uint256 btcAmount = STANDARD_COLLATERAL_AMOUNT;
        uint256 maxDuration = loan.getMaxDuration();

        (uint256 loanAmt,,) = loan.getLoanDetails(btcAmount, maxDuration);
        assertGt(loanAmt, 0, "Max duration should return valid loan details");
    }

    /// @notice Successfully calculates loan details with minimum duration (1 month)
    function test_calculateLoanDetails_DurationOne() public {
        uint256 collateral = STANDARD_COLLATERAL_AMOUNT;
        uint256 duration = 1;

        (uint256 loanAmt, uint256 monthlyPayment, uint256 minDeposit) = loan.getLoanDetails(collateral, duration);

        assertGt(loanAmt, 0, "Loan amount should be positive");
        assertGt(monthlyPayment, 0, "Monthly payment should be positive");
        assertGt(minDeposit, 0, "Min deposit should be positive");
    }

    /// @notice Reverts when slippage protection bounds are violated.
    function test_initializeLoan_slippageProtection() public mintDebtAssetToUser {
        // Goal: force swap to exceed s_slippage_swap (0.5%) and ensure revert
        uint256 btcAmount = STANDARD_COLLATERAL_AMOUNT;
        uint256 duration = STANDARD_DURATION;

        (,, uint256 minDepositRequired) = loan.getLoanDetails(btcAmount, duration);

        address oracle = address(mockOracle);
        uint256 realBtcPrice = IPriceOracleGetter(oracle).getAssetPrice(btc);

        // Underprice BTC by 2% to breach 0.5% slippage
        uint256 mockedBtcPrice = (realBtcPrice * 102) / 100;

        vm.mockCall(
            oracle, abi.encodeWithSelector(IPriceOracleGetter.getAssetPrice.selector, btc), abi.encode(mockedBtcPrice)
        );

        vm.prank(user);
        vm.expectRevert();
        loan.initializeLoan(minDepositRequired, PREMIUM_AMOUNT, btcAmount, duration, DATA);
    }

    /// @notice Test flash loan integration works correctly through MockAaveV3Pool
    function test_initializeLoan_FlashLoanIntegration() public {
        MockAaveV3Pool mockPool = new MockAaveV3Pool();

        // Create a new AccessManager for loan2
        BitmorAccessManager manager2 = new BitmorAccessManager(admin);

        vm.startPrank(admin);

        // Deploy BitmorAddressesProvider FIRST via UUPS proxy (Loan.initialize needs its address)
        BitmorAddressesProvider provider2 = _deployAddressesProviderProxy(
            address(manager2), address(mockSwapAdapter), premiumCollector, premiumCollector
        );

        Loan loan2 = _deployLoanProxy(
            DataTypes.InitParams({
                manager: address(manager2),
                aaveV3Pool: address(mockPool),
                aaveAddressesProvider: s_addressesProvider,
                bitmorPool: s_bitmorPool,
                oracle: address(mockOracle),
                collateralAsset: collateralAsset,
                debtAsset: debtAsset,
                btc: btc,
                bitmorAddressesProvider: address(provider2),
                maxBTCAmt: uint64(TC.MAX_COLLATERAL),
                minBTCAmt: uint64(TC.MIN_COLLATERAL),
                gracePeriod: uint32(loan.getGracePeriod()),
                preClosureFeeBps: uint16(loan.getPreClosureFee()),
                liquidationFee: 0,
                slippageSharesToAsset: uint16(TC.SLIPPAGE_SHARES_TO_ASSET),
                slippageSwap: uint16(TC.SLIPPAGE_SWAP),
                minDeposit: uint16(TC.MIN_DEPOSIT),
                maxDuration: uint16(TC.MAX_DURATION)
            })
        );

        // Set up LoanVaultFactory for loan2
        address loanVaultImpl2 = address(new LoanVault());
        address beacon2 = address(new UpgradeableBeacon(loanVaultImpl2, address(this)));
        address loanVaultFactory2 = address(new LoanVaultFactory(beacon2, address(loan2)));

        // BAP post-init setters
        provider2.setVaultFactory(loanVaultFactory2);
        provider2.setAutoRepayer(autoRepayer);

        // Now set up roles and target selectors
        manager2.grantRole(EXECUTOR_ID(), user, NO_DELAY);
        manager2.setTargetFunctionRole(address(loan2), rolesData.getEXECUTOR_SELECTORS(), EXECUTOR_ID());

        vm.stopPrank();

        // Register loan2 in addresses provider (required for borrow access control)
        mockAddressesProvider.setBitmorLoan(address(loan2));

        // Fund the new mockPool with USDC for flash loans
        mockUSDC.mint(address(mockPool), TC.LENDING_POOL_USDC_BALANCE);

        _utilSeedUserAndApprove(user, debtAsset, address(loan2), USER_USDC_FUNDING);

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
    function test_initializeLoan_RevertWhen_DepositIsZero() public mintDebtAssetToUser {
        uint256 btcAmount = STANDARD_COLLATERAL_AMOUNT;
        uint256 duration = STANDARD_DURATION;

        vm.prank(user);
        _expectRevertSelector(Errors.ZeroAmount.selector);
        loan.initializeLoan(0, PREMIUM_AMOUNT, btcAmount, duration, DATA);
    }

    /// @notice Reverts when collateral amount is zero.
    function test_initializeLoan_RevertWhen_CollateralIsZero() public mintDebtAssetToUser {
        uint256 btcAmount = STANDARD_COLLATERAL_AMOUNT;
        uint256 duration = STANDARD_DURATION;

        (,, uint256 minDepositRequired) = loan.getLoanDetails(btcAmount, duration);

        vm.prank(user);
        _expectRevertSelector(Errors.ZeroAmount.selector);
        loan.initializeLoan(minDepositRequired, PREMIUM_AMOUNT, 0, duration, DATA);
    }

    // ============ Oracle Price Edge Cases ============

    /// @notice Reverts when collateral asset price is zero
    function test_calculateLoanDetails_RevertWhen_CollateralPriceIsZero() public {
        // The collateral asset in Loan is mockBTCVault, not mockCbBTC
        mockOracle.setAssetPrice(address(mockCbBTC), 0);

        vm.expectRevert(Errors.InvalidAssetPrice.selector);
        loan.getLoanDetails(STANDARD_COLLATERAL_AMOUNT, STANDARD_DURATION);
    }

    /// @notice Reverts when debt asset price is zero
    function test_calculateLoanDetails_RevertWhen_DebtPriceIsZero() public {
        mockOracle.setAssetPrice(address(mockUSDC), 0);

        vm.expectRevert(Errors.InvalidAssetPrice.selector);
        loan.getLoanDetails(STANDARD_COLLATERAL_AMOUNT, STANDARD_DURATION);
    }

    // ============ Access Control Tests ============

    /// @notice Test that flash loan callback reverts when initiator is not the Loan contract
    /// @dev Covers FlashLoanLogic.sol:100 WrongFLInitiator error
    function test_RevertWhen_InitLoanWrongFlashLoanInitiator() public {
        // Arrange - prepare flash loan params with wrong initiator
        address wrongInitiator = makeAddr("wrongInitiator");
        address mockLsa = makeAddr("mockLsa");
        bytes memory flData = abi.encode(mockLsa, TC.TEST_BTC_SWAP_AMOUNT);
        bytes memory params = abi.encode(true, flData); // true = initializingLoan

        // Act & Assert - call from Aave pool (correct caller) but with wrong initiator
        vm.prank(address(mockAavePool));
        vm.expectRevert(Errors.WrongFLInitiator.selector);
        loan.executeOperation(debtAsset, TC.FLASH_LOAN_AMOUNT, TC.FLASH_LOAN_PREMIUM, wrongInitiator, params);
    }
}
