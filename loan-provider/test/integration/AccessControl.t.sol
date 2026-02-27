// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IntegrationTestBase} from "../base/IntegrationTestBase.sol";
import {TestConstants as TC} from "../helpers/TestConstants.sol";
import {IAccessManaged} from "@openzeppelin/access/manager/IAccessManaged.sol";
import {Pausable} from "@openzeppelin/utils/Pausable.sol";

/// @title AccessControlTest
/// @notice Integration tests for role-protected operations with real AccessManager
/// @dev Validates all role-path access control against pre-deployed contracts on local Anvil.
///      Covers EXECUTOR, LPCM, LPM_FAST, LPM_SLOW, BVC, BVD, UVC, and UVA roles.
contract AccessControlTest is IntegrationTestBase {
    // ============ Admin Role ============

    /// @notice Verifies deployer holds the ADMIN role (role 0) on the AccessManager
    function test_AdminHasAdminRole() public view {
        // Admin role is role 0 in OZ AccessManager
        (bool isAdmin,) = manager.hasRole(0, admin);
        assertTrue(isAdmin, "admin should have ADMIN_ROLE");
    }

    // ============ Executor Role ============

    /// @notice Authorized EXECUTOR can initialize a loan
    function test_ExecutorCanInitializeLoan() public {
        // testUser was granted EXECUTOR role in _setupTestUser()
        address lsa = _createStandardLoan();
        assertTrue(lsa != address(0), "executor should be able to create loan");
    }

    /// @notice Unauthorized address cannot initialize a loan
    function test_RevertWhen_NonExecutorInitializesLoan() public {
        // Arrange
        address unauthorized = makeAddr("unauthorized");
        _fundUSDC(unauthorized, TC.USER_USDC_BALANCE);

        vm.prank(unauthorized);
        usdc.approve(address(loanContract), type(uint256).max);

        (,, uint256 minDeposit) = loanContract.getLoanDetails(TC.STANDARD_COLLATERAL, TC.STANDARD_DURATION);

        // Act + Assert
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, unauthorized));
        vm.prank(unauthorized);
        loanContract.initializeLoan(minDeposit, TC.PREMIUM_AMOUNT, TC.STANDARD_COLLATERAL, TC.STANDARD_DURATION, "");
    }

    // ============ Pause / Unpause ============

    /// @notice Admin with LPM_FAST can pause the loan contract immediately
    function test_PauseWithAdmin() public {
        vm.prank(admin);
        loanContract.pause();

        assertTrue(loanContract.paused(), "loan should be paused");
    }

    /// @notice Loan initialization reverts when the contract is paused
    function test_RevertWhen_LoanIsPaused() public {
        vm.prank(admin);
        loanContract.pause();

        (,, uint256 minDeposit) = loanContract.getLoanDetails(TC.STANDARD_COLLATERAL, TC.STANDARD_DURATION);

        vm.expectRevert(Pausable.EnforcedPause.selector);
        vm.prank(testUser);
        loanContract.initializeLoan(minDeposit, TC.PREMIUM_AMOUNT, TC.STANDARD_COLLATERAL, TC.STANDARD_DURATION, "");
    }

    // ============ Delayed Operations ============

    /// @notice LPM_SLOW role can unpause loan via schedule/execute pattern with 1-day delay
    function test_UnpauseWithLPMSlow_DelayedExecution() public {
        // Arrange: Pause the loan contract (LPM_FAST, instant)
        vm.prank(admin);
        loanContract.pause();
        assertTrue(loanContract.paused(), "loan should be paused");

        // Act: schedule + execute unpause via _scheduleAndExecute helper
        bytes memory unpauseData = abi.encodeWithSignature("unpause()");
        _scheduleAndExecute(address(loanContract), admin, LPM_SLOW_ID(), unpauseData);

        // Assert
        assertFalse(loanContract.paused(), "loan should be unpaused after delayed execution");
    }

    // ============ LPCM Role Enforcement ============

    /// @notice Unauthorized address cannot call `updateLoanDataForFullLiquidation` (LPCM-protected)
    function test_RevertWhen_NonLPCM_UpdatesLiquidation() public {
        // Arrange
        address lsa = _createStandardLoan();
        address unauthorized = makeAddr("unauthorized");

        // Act + Assert
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, unauthorized));
        vm.prank(unauthorized);
        loanContract.updateLoanDataForFullLiquidation(lsa);
    }

    // ============ UVC Role: USDCVault.setStrategy (delayed) ============

    /// @notice Unauthorized address cannot call `setStrategy` on USDCVault
    function test_RevertWhen_NonUVC_SetsUSDCStrategy() public {
        // Arrange
        address unauthorized = makeAddr("unauthorized");
        address bogusStrategy = makeAddr("bogusStrategy");

        // Act + Assert
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, unauthorized));
        vm.prank(unauthorized);
        usdcVault.setStrategy(bogusStrategy);
    }

    /// @notice Authorized UVC role-holder can set strategy on USDCVault via schedule/execute
    /// @dev Uses the already-deployed USDCStrategy to avoid breaking state. After schedule/execute,
    ///      the strategy getter should still return the same address (idempotent re-set).
    function test_UVC_CanSetStrategy_WithDelay() public {
        // Arrange: use the currently deployed strategy so we do not break downstream tests
        address currentStrategy = usdcVault.getStrategy();
        assertTrue(currentStrategy != address(0), "usdc vault should already have a strategy");

        // Act: schedule + execute setStrategy via _scheduleAndExecute helper
        bytes memory setStrategyData = abi.encodeCall(usdcVault.setStrategy, (currentStrategy));
        _scheduleAndExecute(address(usdcVault), admin, UVC_ID(), setStrategyData);

        // Assert: strategy is still the same (idempotent operation)
        assertEq(usdcVault.getStrategy(), currentStrategy, "strategy should remain the deployed one");
    }

    // ============ BVC Role: BTCVault.addStrategy (delayed) ============

    /// @notice Unauthorized address cannot call `addStrategy` on BTCVault
    function test_RevertWhen_NonBVC_AddsBTCStrategy() public {
        // Arrange
        address unauthorized = makeAddr("unauthorized");
        address bogusStrategy = makeAddr("bogusStrategy");
        uint256 cap = TC.MAX_COLLATERAL;

        // Act + Assert
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, unauthorized));
        vm.prank(unauthorized);
        btcVault.addStrategy(bogusStrategy, cap);
    }

    /// @notice Authorized BVC role-holder can call `setMaxStrategies` on BTCVault via schedule/execute
    /// @dev Uses `setMaxStrategies` as a safer BVC-delayed test that does not require deploying
    ///      a valid tokenized strategy contract. The function is BVC-restricted with 1-day delay.
    function test_BVC_CanSetMaxStrategies_WithDelay() public {
        // Arrange
        uint256 currentMax = btcVault.getMaxStrategies();
        uint256 newMax = currentMax + 1;

        // Act: schedule + execute setMaxStrategies via _scheduleAndExecute helper
        bytes memory setMaxData = abi.encodeCall(btcVault.setMaxStrategies, (newMax));
        _scheduleAndExecute(address(btcVault), admin, BVC_ID(), setMaxData);

        // Assert
        assertEq(btcVault.getMaxStrategies(), newMax, "max strategies should be updated");
    }

    /// @notice Unauthorized address cannot call `changeStrategyCap` on BTCVault (BVC-restricted)
    function test_RevertWhen_NonBVC_ChangesStrategyCap() public {
        // Arrange
        address unauthorized = makeAddr("unauthorized");
        address aaveStrategy = config.getAaveTokenizedStrategy();

        // Act + Assert
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, unauthorized));
        vm.prank(unauthorized);
        btcVault.changeStrategyCap(aaveStrategy, 500e8);
    }

    // ============ UVA Role: USDCVault.reallocateAssets ============

    /// @notice Unauthorized address cannot call `reallocateAssets()` on USDCVault
    function test_RevertWhen_NonUVA_ReallocatesUSDCVault() public {
        // Arrange
        address unauthorized = makeAddr("unauthorized");

        // Act + Assert
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, unauthorized));
        vm.prank(unauthorized);
        usdcVault.reallocateAssets();
    }

    /// @notice Verifies `bitmorPool` holds the UVA role required for reallocation calls
    function test_UVA_BitmorPool_HasRole() public view {
        // Arrange + Assert
        (bool hasUVA,) = manager.hasRole(UVA_ID(), bitmorPool);
        assertTrue(hasUVA, "bitmorPool should have UVA role");
    }

    /// @notice Unauthorized address cannot call `reallocateAssets(uint256)` on USDCVault
    function test_RevertWhen_NonUVA_ReallocatesUSDCVault_WithAmount() public {
        // Arrange
        address unauthorized = makeAddr("unauthorized");
        uint256 amountToWithdraw = 1000e6;

        // Act + Assert
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, unauthorized));
        vm.prank(unauthorized);
        usdcVault.reallocateAssets(amountToWithdraw);
    }

    // ============ BVD Role: BTCVault deposit path ============

    /// @notice Verifies the Loan contract holds the BVD role for BTCVault deposit operations
    function test_BVD_LoanHasDepositAccess() public view {
        // Arrange + Assert
        (bool hasBVD,) = manager.hasRole(BVD_ID(), address(loanContract));
        assertTrue(hasBVD, "loan should have BVD role");
    }

    /// @notice Unauthorized address cannot call `deposit` on BTCVault (BVD-restricted)
    function test_RevertWhen_NonBVD_DepositsToBTCVault() public {
        // Arrange
        address unauthorized = makeAddr("unauthorized");

        // Act + Assert: revert on access check before any token transfer
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, unauthorized));
        vm.prank(unauthorized);
        btcVault.deposit(1e8, unauthorized);
    }

    /// @notice Unauthorized address cannot call `mint` on BTCVault (BVD-restricted)
    function test_RevertWhen_NonBVD_MintsBTCVault() public {
        // Arrange
        address unauthorized = makeAddr("unauthorized");

        // Act + Assert
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, unauthorized));
        vm.prank(unauthorized);
        btcVault.mint(1e8, unauthorized);
    }

    // ============ LPCM Role: Micro Liquidation ============

    /// @notice Unauthorized address cannot call `updateLoanDataForMicroLiquidation` (LPCM-protected)
    function test_RevertWhen_NonLPCM_UpdatesMicroLiquidation() public {
        // Arrange
        address lsa = _createStandardLoan();
        address unauthorized = makeAddr("unauthorized");

        // Act + Assert
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, unauthorized));
        vm.prank(unauthorized);
        loanContract.updateLoanDataForMicroLiquidation(lsa);
    }

    /// @notice Verifies `bitmorPool` holds the LPCM role for liquidation data updates
    function test_LPCM_BitmorPool_HasRole() public view {
        // Arrange + Assert
        (bool hasLPCM,) = manager.hasRole(LPCM_ID(), bitmorPool);
        assertTrue(hasLPCM, "bitmorPool should have LPCM role");
    }

    // ============ Multi-Role Admin Grants ============

    /// @notice Verifies `admin` holds all expected operational roles
    function test_AdminHoldsExpectedRoles() public view {
        // EXECUTOR
        (bool hasExec,) = manager.hasRole(EXECUTOR_ID(), admin);
        assertTrue(hasExec, "admin should have EXECUTOR role");

        // LPM_FAST
        (bool hasLPMFast,) = manager.hasRole(LPM_FAST_ID(), admin);
        assertTrue(hasLPMFast, "admin should have LPM_FAST role");

        // LPM_SLOW (with delay)
        (bool hasLPMSlow, uint32 lpmSlowDelay) = manager.hasRole(LPM_SLOW_ID(), admin);
        assertTrue(hasLPMSlow, "admin should have LPM_SLOW role");
        assertGt(lpmSlowDelay, 0, "LPM_SLOW should have non-zero delay");

        // BVC (with delay)
        (bool hasBVC, uint32 bvcDelay) = manager.hasRole(BVC_ID(), admin);
        assertTrue(hasBVC, "admin should have BVC role");
        assertGt(bvcDelay, 0, "BVC should have non-zero delay");

        // UVC (with delay)
        (bool hasUVC, uint32 uvcDelay) = manager.hasRole(UVC_ID(), admin);
        assertTrue(hasUVC, "admin should have UVC role");
        assertGt(uvcDelay, 0, "UVC should have non-zero delay");
    }

    // ============ Unauthorized Pause Attempts ============

    /// @notice Unauthorized address cannot pause BTCVault
    function test_RevertWhen_NonBVMFast_PausesBTCVault() public {
        // Arrange
        address unauthorized = makeAddr("unauthorized");

        // Act + Assert
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, unauthorized));
        vm.prank(unauthorized);
        btcVault.pause();
    }

    /// @notice Unauthorized address cannot pause USDCVault
    function test_RevertWhen_NonUVMFast_PausesUSDCVault() public {
        // Arrange
        address unauthorized = makeAddr("unauthorized");

        // Act + Assert
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, unauthorized));
        vm.prank(unauthorized);
        usdcVault.pause();
    }
}
