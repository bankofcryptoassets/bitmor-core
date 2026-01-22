// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {BitmorAccessManager} from "@bitmor/accessManager/BitmorAccessManager.sol";
import {RolesData} from "@bitmor/accessManager/RolesData.sol";

/// @title BitmorTestBase
/// @author Bitmor Protocol
/// @notice Unified base test contract providing AccessManager configuration for all protocol contracts
/// @dev Utilizes RolesData.sol for function selectors and maintains role ID/delay constants matching RolesData.
///      All test base files (BaseLoan, BaseTestForBTCVault, BaseTestForUSDCVault) inherit from this.
abstract contract BitmorTestBase is Test {
    // ============ Access Manager ============

    /// @notice The BitmorAccessManager instance used across all tests
    BitmorAccessManager internal manager;

    // ============ Roles Data ============

    /// @notice RolesData contract for accessing function selectors
    RolesData internal rolesData;

    // ============ Role ID Constants (matching RolesData.sol) ============

    // Loan Provider roles
    uint64 internal constant EXECUTOR_ID = 1;
    uint64 internal constant LPCM_ID = 2;
    uint64 internal constant LPM_FAST_ID = 3;
    uint64 internal constant LPM_SLOW_ID = 30;

    // Auto Repayment roles
    uint64 internal constant ARE_ID = 4;

    // BTC Vault roles
    uint64 internal constant BVM_FAST_ID = 11;
    uint64 internal constant BVM_SLOW_ID = 110;
    uint64 internal constant BVC_ID = 12;
    uint64 internal constant BVA_FAST_ID = 13;
    uint64 internal constant BVA_SLOW_ID = 130;
    uint64 internal constant BVD_ID = 14;

    // USDC Vault roles
    uint64 internal constant UVM_FAST_ID = 21;
    uint64 internal constant UVM_SLOW_ID = 210;
    uint64 internal constant UVC_ID = 22;
    uint64 internal constant UVA_ID = 23;

    // ============ Role Delay Constants ============

    /// @notice Standard time delay of 1 day for sensitive operations
    uint32 internal constant ONE_DAY_DELAY = 1 days;
    uint32 internal constant NO_DELAY = 0;

    // ============ Role Addresses (created with makeAddr) ============

    // Loan Provider roles
    address internal executor;
    address internal lpcm;
    address internal lpm_fast;
    address internal lpm_slow;

    // Auto Repayment roles
    address internal are;

    // BTC Vault roles
    address internal bvm_fast;
    address internal bvm_slow;
    address internal bvc;
    address internal bva_fast;
    address internal bva_slow;
    address internal bvd;

    // USDC Vault roles
    address internal uvm_fast;
    address internal uvm_slow;
    address internal uvc;
    address internal uva;

    // ============ Setup ============

    /// @notice Override this function in derived test contracts
    /// @dev Base implementation is empty - child classes implement their specific setup
    function setUp() public virtual {}

    // ============ Initialization Functions ============

    /// @notice Deploy AccessManager and RolesData, then create all role actor addresses
    /// @param initialAdmin The initial admin address for the AccessManager
    function _initializeAccessManager(address initialAdmin) internal virtual {
        manager = new BitmorAccessManager(initialAdmin);
        rolesData = new RolesData();
        _createRoleActors();
    }

    /// @notice Creates all role actor addresses using makeAddr
    /// @dev Called automatically by _initializeAccessManager
    function _createRoleActors() internal {
        // Loan Provider roles
        executor = makeAddr("EXECUTOR");
        lpcm = makeAddr("LPCM");
        lpm_fast = makeAddr("LPM_FAST");
        lpm_slow = makeAddr("LPM_SLOW");

        // Auto Repayment roles
        are = makeAddr("ARE");

        // BTC Vault roles
        bvm_fast = makeAddr("BVM_FAST");
        bvm_slow = makeAddr("BVM_SLOW");
        bvc = makeAddr("BVC");
        bva_fast = makeAddr("BVA_FAST");
        bva_slow = makeAddr("BVA_SLOW");
        bvd = makeAddr("BVD");

        // USDC Vault roles
        uvm_fast = makeAddr("UVM_FAST");
        uvm_slow = makeAddr("UVM_SLOW");
        uvc = makeAddr("UVC");
        uva = makeAddr("UVA");
    }

    // ============ Loan Provider Role Configuration ============

    /// @notice Grant Loan Provider roles to test actors
    /// @param user Additional user address to grant EXECUTOR role (for creating loans)
    function _setLoanRoles(address user) internal {
        manager.grantRole(EXECUTOR_ID, executor, NO_DELAY);
        manager.grantRole(EXECUTOR_ID, user, NO_DELAY); // Grant to user so they can create loans
        manager.grantRole(LPCM_ID, lpcm, NO_DELAY);
        manager.grantRole(LPM_FAST_ID, lpm_fast, NO_DELAY);
        manager.grantRole(LPM_SLOW_ID, lpm_slow, ONE_DAY_DELAY);
    }

    /// @notice Set target function selectors for Loan contract roles
    /// @param loanContract The Loan contract address
    function _setLoanTargetSelectors(address loanContract) internal {
        // Use selectors from RolesData for consistency with production
        manager.setTargetFunctionRole(loanContract, rolesData.getEXECUTOR_SELECTORS(), EXECUTOR_ID);
        manager.setTargetFunctionRole(loanContract, rolesData.getLPCM_SELECTORS(), LPCM_ID);
        manager.setTargetFunctionRole(loanContract, rolesData.getLPM_FAST_SELECTORS(), LPM_FAST_ID);
        manager.setTargetFunctionRole(loanContract, rolesData.getLPM_SLOW_SELECTORS(), LPM_SLOW_ID);
    }

    // ============ Auto Repayment Role Configuration ============

    /// @notice Grant Auto Repayment roles to test actors
    function _setAutoRepaymentRoles() internal {
        manager.grantRole(ARE_ID, are, NO_DELAY);
    }

    /// @notice Set target function selectors for AutoRepayment contract roles
    /// @param autoRepaymentContract The AutoRepayment contract address
    function _setAutoRepaymentTargetSelectors(address autoRepaymentContract) internal {
        manager.setTargetFunctionRole(autoRepaymentContract, rolesData.getARE_SELECTORS(), ARE_ID);
    }

    // ============ BTC Vault Role Configuration ============

    /// @notice Grant BTC Vault roles to test actors
    /// @param user Additional user address to grant BVD role (for deposits)
    function _setBTCVaultRoles(address user) internal {
        manager.grantRole(BVM_FAST_ID, bvm_fast, NO_DELAY);
        manager.grantRole(BVM_SLOW_ID, bvm_slow, ONE_DAY_DELAY);
        manager.grantRole(BVC_ID, bvc, ONE_DAY_DELAY);
        manager.grantRole(BVA_FAST_ID, bva_fast, NO_DELAY);
        manager.grantRole(BVA_SLOW_ID, bva_slow, ONE_DAY_DELAY);
        manager.grantRole(BVD_ID, bvd, NO_DELAY);
        manager.grantRole(BVD_ID, user, NO_DELAY); // Allow user to deposit
    }

    /// @notice Set target function selectors for BTCVault contract roles
    /// @param btcVaultContract The BTCVault contract address
    function _setBTCVaultTargetSelectors(address btcVaultContract) internal {
        manager.setTargetFunctionRole(btcVaultContract, rolesData.getBVM_FAST_SELECTORS(), BVM_FAST_ID);
        manager.setTargetFunctionRole(btcVaultContract, rolesData.getBVM_SLOW_SELECTORS(), BVM_SLOW_ID);
        manager.setTargetFunctionRole(btcVaultContract, rolesData.getBVC_SELECTORS(), BVC_ID);
        manager.setTargetFunctionRole(btcVaultContract, rolesData.getBVA_FAST_SELECTORS(), BVA_FAST_ID);
        manager.setTargetFunctionRole(btcVaultContract, rolesData.getBVA_SLOW_SELECTORS(), BVA_SLOW_ID);
        manager.setTargetFunctionRole(btcVaultContract, rolesData.getBVD_SELECTORS(), BVD_ID);
    }

    // ============ USDC Vault Role Configuration ============

    /// @notice Grant USDC Vault roles to test actors
    function _setUSDCVaultRoles() internal {
        manager.grantRole(UVM_FAST_ID, uvm_fast, NO_DELAY);
        manager.grantRole(UVM_SLOW_ID, uvm_slow, ONE_DAY_DELAY);
        manager.grantRole(UVC_ID, uvc, ONE_DAY_DELAY);
        manager.grantRole(UVA_ID, uva, NO_DELAY);
    }

    /// @notice Set target function selectors for USDCVault contract roles
    /// @param usdcVaultContract The USDCVault contract address
    function _setUSDCVaultTargetSelectors(address usdcVaultContract) internal {
        manager.setTargetFunctionRole(usdcVaultContract, rolesData.getUVM_FAST_SELECTORS(), UVM_FAST_ID);
        manager.setTargetFunctionRole(usdcVaultContract, rolesData.getUVM_SLOW_SELECTORS(), UVM_SLOW_ID);
        manager.setTargetFunctionRole(usdcVaultContract, rolesData.getUVC_SELECTORS(), UVC_ID);
        manager.setTargetFunctionRole(usdcVaultContract, rolesData.getUVA_SELECTORS(), UVA_ID);
    }

    // ============ Common Helper Functions ============

    /// @notice Schedule and execute a delayed operation through AccessManager
    /// @param target The target contract
    /// @param caller The address calling the operation
    /// @param roleId The role ID of the caller
    /// @param data The encoded function call data
    function _scheduleAndExecute(address target, address caller, uint64 roleId, bytes memory data) internal {
        (, uint32 delay,,) = manager.getAccess(roleId, caller);
        uint48 when = uint48(block.timestamp + delay);

        vm.startPrank(caller);
        if (delay > 0) {
            manager.schedule(target, data, when);
            vm.warp(when);
        }
        manager.execute(target, data);
        vm.stopPrank();
    }

    /// @notice Schedule an operation and expect it to revert
    /// @param target The target contract
    /// @param caller The address calling the operation
    /// @param roleId The role ID of the caller
    /// @param data The encoded function call data
    /// @param revertData The expected revert data
    function _scheduleAndExpectRevert(
        address target,
        address caller,
        uint64 roleId,
        bytes memory data,
        bytes memory revertData
    ) internal {
        (, uint32 delay,,) = manager.getAccess(roleId, caller);
        uint48 when = uint48(block.timestamp + delay);

        vm.startPrank(caller);
        if (delay > 0) {
            manager.schedule(target, data, when);
            vm.warp(when);
        }
        vm.expectRevert(revertData);
        manager.execute(target, data);
        vm.stopPrank();
    }

    /// @notice Get role ID by role name (convenience accessor)
    /// @param roleName The name of the role
    /// @return The role ID
    function _getRoleId(string memory roleName) internal pure returns (uint64) {
        bytes32 nameHash = keccak256(bytes(roleName));

        if (nameHash == keccak256("EXECUTOR")) return EXECUTOR_ID;
        if (nameHash == keccak256("LPCM")) return LPCM_ID;
        if (nameHash == keccak256("LPM_FAST")) return LPM_FAST_ID;
        if (nameHash == keccak256("LPM_SLOW")) return LPM_SLOW_ID;
        if (nameHash == keccak256("ARE")) return ARE_ID;
        if (nameHash == keccak256("BVM_FAST")) return BVM_FAST_ID;
        if (nameHash == keccak256("BVM_SLOW")) return BVM_SLOW_ID;
        if (nameHash == keccak256("BVC")) return BVC_ID;
        if (nameHash == keccak256("BVA_FAST")) return BVA_FAST_ID;
        if (nameHash == keccak256("BVA_SLOW")) return BVA_SLOW_ID;
        if (nameHash == keccak256("BVD")) return BVD_ID;
        if (nameHash == keccak256("UVM_FAST")) return UVM_FAST_ID;
        if (nameHash == keccak256("UVM_SLOW")) return UVM_SLOW_ID;
        if (nameHash == keccak256("UVC")) return UVC_ID;
        if (nameHash == keccak256("UVA")) return UVA_ID;

        revert("Unknown role");
    }

    /// @notice Get execution delay for a role by name
    /// @param roleName The name of the role
    /// @return The execution delay in seconds
    function _getRoleDelay(string memory roleName) internal pure returns (uint32) {
        bytes32 nameHash = keccak256(bytes(roleName));

        // Roles with NO_DELAY
        if (nameHash == keccak256("EXECUTOR")) return NO_DELAY;
        if (nameHash == keccak256("LPCM")) return NO_DELAY;
        if (nameHash == keccak256("LPM_FAST")) return NO_DELAY;
        if (nameHash == keccak256("ARE")) return NO_DELAY;
        if (nameHash == keccak256("BVM_FAST")) return NO_DELAY;
        if (nameHash == keccak256("BVA_FAST")) return NO_DELAY;
        if (nameHash == keccak256("BVD")) return NO_DELAY;
        if (nameHash == keccak256("UVM_FAST")) return NO_DELAY;
        if (nameHash == keccak256("UVA")) return NO_DELAY;

        // Roles with ONE_DAY_DELAY
        if (nameHash == keccak256("LPM_SLOW")) return ONE_DAY_DELAY;
        if (nameHash == keccak256("BVM_SLOW")) return ONE_DAY_DELAY;
        if (nameHash == keccak256("BVC")) return ONE_DAY_DELAY;
        if (nameHash == keccak256("BVA_SLOW")) return ONE_DAY_DELAY;
        if (nameHash == keccak256("UVM_SLOW")) return ONE_DAY_DELAY;
        if (nameHash == keccak256("UVC")) return ONE_DAY_DELAY;

        revert("Unknown role");
    }
}
