// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.30;

import {BaseLoanTest} from "./BaseLoan.t.sol";
import {Errors} from "@bitmor/libraries/helpers/Errors.sol";

/// @title LoanLogicEdgeCasesTest
/// @notice Tests for LoanLogic edge cases and boundary conditions
contract LoanLogicEdgeCasesTest is BaseLoanTest {
    function setUp() public override {
        super.setUp();
    }

    // ============ Zero Premium Tests ============

    function test_initializeLoan_zeroPremium_success() public {
        (,, uint256 minDeposit) = loan.getLoanDetails(STANDARD_COLLATERAL_AMOUNT, STANDARD_DURATION);
        uint256 zeroPremium = 0;

        _mintDebtAssetToUser();

        vm.prank(user);
        address lsa = loan.initializeLoan(minDeposit, zeroPremium, STANDARD_COLLATERAL_AMOUNT, STANDARD_DURATION, "");

        assertTrue(lsa != address(0), "LSA should be created with zero premium");
    }

    // ============ Max Collateral Boundary Tests ============

    function test_initializeLoan_exactMaxCollateral_success() public {
        uint256 maxBTC = loan.getMaxBTCAmount();
        (uint256 loanAmt,, uint256 minDeposit) = loan.getLoanDetails(maxBTC, STANDARD_DURATION);

        _mintDebtAssetToUser();

        vm.prank(user);
        address lsa = loan.initializeLoan(minDeposit, PREMIUM_AMOUNT, maxBTC, STANDARD_DURATION, "");

        assertTrue(lsa != address(0), "Max collateral should succeed");
        assertGt(loanAmt, 0, "Loan amount should be positive");
    }

    function test_initializeLoan_aboveMaxCollateral_reverts() public {
        uint256 maxBTC = loan.getMaxBTCAmount();
        uint256 aboveMax = maxBTC + 1;

        // Test getLoanDetails path (calculateLoanDetails)
        vm.expectRevert(Errors.GreaterThanMaxCollateralAllowed.selector);
        loan.getLoanDetails(aboveMax, STANDARD_DURATION);
    }

    function test_initializeLoan_aboveMaxCollateral_executeInitializeLoan_reverts() public {
        uint256 maxBTC = loan.getMaxBTCAmount();
        uint256 aboveMax = maxBTC + 1;

        _mintDebtAssetToUser();

        // Test initializeLoan path (executeInitializeLoan) - this hits LoanLogic line 80-81
        vm.prank(user);
        vm.expectRevert(Errors.GreaterThanMaxCollateralAllowed.selector);
        loan.initializeLoan(100_000e6, PREMIUM_AMOUNT, aboveMax, STANDARD_DURATION, "");
    }

    function test_initializeLoan_belowMinCollateral_executeInitializeLoan_reverts() public {
        uint256 minBTC = loan.getMinBTCAmount();
        uint256 belowMin = minBTC - 1;

        _mintDebtAssetToUser();

        // Test initializeLoan path (executeInitializeLoan) - this hits LoanLogic line 76-77
        vm.prank(user);
        vm.expectRevert(Errors.LessThanMinimumCollateralAllowed.selector);
        loan.initializeLoan(100_000e6, PREMIUM_AMOUNT, belowMin, STANDARD_DURATION, "");
    }

    function test_initializeLoan_zeroCollateral_executeInitializeLoan_reverts() public {
        _mintDebtAssetToUser();

        // Test initializeLoan path (executeInitializeLoan) - this hits LoanLogic line 72-73
        vm.prank(user);
        vm.expectRevert(Errors.ZeroAmount.selector);
        loan.initializeLoan(100_000e6, PREMIUM_AMOUNT, 0, STANDARD_DURATION, "");
    }

    function test_initializeLoan_zeroDeposit_executeInitializeLoan_reverts() public {
        _mintDebtAssetToUser();

        // Test initializeLoan path - zero deposit hits LoanLogic line 72-73
        vm.prank(user);
        vm.expectRevert(Errors.ZeroAmount.selector);
        loan.initializeLoan(0, PREMIUM_AMOUNT, STANDARD_COLLATERAL_AMOUNT, STANDARD_DURATION, "");
    }

    function test_initializeLoan_zeroDuration_executeInitializeLoan_reverts() public {
        _mintDebtAssetToUser();

        // Test initializeLoan path - zero duration hits LoanLogic line 72-73
        vm.prank(user);
        vm.expectRevert(Errors.ZeroAmount.selector);
        loan.initializeLoan(100_000e6, PREMIUM_AMOUNT, STANDARD_COLLATERAL_AMOUNT, 0, "");
    }

    // ============ Access Control Tests ============

    function test_initializeLoan_withoutExecutorRole_reverts() public {
        address noRoleUser = makeAddr("noRoleUser");

        _fundUSDC(noRoleUser, DEBT_ASSET_TO_MINT_TO_USER);

        vm.startPrank(noRoleUser);
        mockUSDC.approve(address(loan), type(uint256).max);

        (,, uint256 minDeposit) = loan.getLoanDetails(STANDARD_COLLATERAL_AMOUNT, STANDARD_DURATION);

        vm.expectRevert();
        loan.initializeLoan(minDeposit, PREMIUM_AMOUNT, STANDARD_COLLATERAL_AMOUNT, STANDARD_DURATION, "");
        vm.stopPrank();
    }

    // ============ Oracle Price Edge Cases ============

    function test_calculateLoanDetails_collateralPriceZero_reverts() public {
        // The collateral asset in Loan is mockBTCVault, not mockCbBTC
        mockOracle.setAssetPrice(address(mockBTCVault), 0);

        vm.expectRevert(Errors.InvalidAssetPrice.selector);
        loan.getLoanDetails(STANDARD_COLLATERAL_AMOUNT, STANDARD_DURATION);
    }

    function test_calculateLoanDetails_debtPriceZero_reverts() public {
        mockOracle.setAssetPrice(address(mockUSDC), 0);

        vm.expectRevert(Errors.InvalidAssetPrice.selector);
        loan.getLoanDetails(STANDARD_COLLATERAL_AMOUNT, STANDARD_DURATION);
    }

    // ============ Collateral Boundary Tests ============

    function test_calculateLoanDetails_collateralBoundaries_tableDriven() public {
        uint256 minBTC = loan.getMinBTCAmount();
        uint256 maxBTC = loan.getMaxBTCAmount();
        uint256 duration = 12;

        // Below min - should revert
        vm.expectRevert(Errors.LessThanMinimumCollateralAllowed.selector);
        loan.getLoanDetails(minBTC - 1, duration);

        // Exactly min - should succeed
        (uint256 loanAmt,,) = loan.getLoanDetails(minBTC, duration);
        assertGt(loanAmt, 0, "Min boundary should return valid loan");

        // Exactly max - should succeed
        (loanAmt,,) = loan.getLoanDetails(maxBTC, duration);
        assertGt(loanAmt, 0, "Max boundary should return valid loan");

        // Above max - should revert
        vm.expectRevert(Errors.GreaterThanMaxCollateralAllowed.selector);
        loan.getLoanDetails(maxBTC + 1, duration);
    }

    // ============ Duration Edge Cases ============

    function test_calculateLoanDetails_durationOne_success() public {
        uint256 collateral = STANDARD_COLLATERAL_AMOUNT;
        uint256 duration = 1;

        (uint256 loanAmt, uint256 monthlyPayment, uint256 minDeposit) = loan.getLoanDetails(collateral, duration);

        assertGt(loanAmt, 0, "Loan amount should be positive");
        assertGt(monthlyPayment, 0, "Monthly payment should be positive");
        assertGt(minDeposit, 0, "Min deposit should be positive");
    }
}
