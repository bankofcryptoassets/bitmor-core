// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {BitmorAccessManager} from "@bitmor/accessManager/BitmorAccessManager.sol";
import {RolesData} from "@bitmor-config/RolesData.sol";
import {TestConstants} from "../helpers/TestConstants.sol";

/// @title BitmorTestBase
/// @author Bitmor Protocol
/// @notice Unified base test contract providing AccessManager configuration for all protocol contracts
/// @dev Reads role IDs and delays dynamically from RolesData.sol to stay in sync with production.
///      All test base files (BaseLoan, BaseTestForBTCVault, BaseTestForUSDCVault) inherit from this.
abstract contract BitmorTestBase is Test {
    // ============ Access Manager ============

    /// @notice The BitmorAccessManager instance used across all tests
    BitmorAccessManager internal manager;

    // ============ Roles Data ============

    /// @notice RolesData contract - single source of truth for role definitions
    RolesData internal rolesData;

    // ============ Role Delay Constants ============

    /// @notice Standard time delay of 1 day for sensitive operations
    uint32 internal constant ONE_DAY_DELAY = 1 days;
    /// @notice Zero delay for non-sensitive operations
    uint32 internal constant NO_DELAY = 0;

    // ============ Role Addresses (created with makeAddr) ============

    /// @dev Loan Provider role actors
    address internal executor;
    address internal lpcm;
    address internal lpm_fast;
    address internal lpm_slow;

    /// @dev Auto Repayment role actor
    address internal are;

    /// @dev BTC Vault role actors
    address internal bvm_fast;
    address internal bvm_slow;
    address internal bvc;
    address internal bva_fast;
    address internal bva_slow;
    address internal bvd;

    /// @dev USDC Vault role actors
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

    /// @notice Creates all role actor addresses using labels from RolesData
    /// @dev Called automatically by _initializeAccessManager
    function _createRoleActors() internal {
        // Loan Provider roles - use labels from RolesData for consistency
        executor = makeAddr(_getLabel_EXECUTOR());
        lpcm = makeAddr(_getLabel_LPCM());
        lpm_fast = makeAddr(_getLabel_LPM_FAST());
        lpm_slow = makeAddr(_getLabel_LPM_SLOW());

        // Auto Repayment roles
        are = makeAddr(_getLabel_ARE());

        // BTC Vault roles
        bvm_fast = makeAddr(_getLabel_BVM_FAST());
        bvm_slow = makeAddr(_getLabel_BVM_SLOW());
        bvc = makeAddr(_getLabel_BVC());
        bva_fast = makeAddr(_getLabel_BVA_FAST());
        bva_slow = makeAddr(_getLabel_BVA_SLOW());
        bvd = makeAddr(_getLabel_BVD());

        // USDC Vault roles
        uvm_fast = makeAddr(_getLabel_UVM_FAST());
        uvm_slow = makeAddr(_getLabel_UVM_SLOW());
        uvc = makeAddr(_getLabel_UVC());
        uva = makeAddr(_getLabel_UVA());
    }

    // ============ Dynamic Role ID Accessors ============
    // These read directly from RolesData to stay in sync with production

    /// @notice Returns EXECUTOR role ID from RolesData
    function EXECUTOR_ID() internal view returns (uint64 id) {
        (,,,, id,,,,,) = rolesData.EXECUTOR();
    }

    /// @notice Returns LPCM role ID from RolesData
    function LPCM_ID() internal view returns (uint64 id) {
        (,,,, id,,,,,) = rolesData.LPCM();
    }

    /// @notice Returns LPM_FAST role ID from RolesData
    function LPM_FAST_ID() internal view returns (uint64 id) {
        (,,,, id,,,,,) = rolesData.LPM_FAST();
    }

    /// @notice Returns LPM_SLOW role ID from RolesData
    function LPM_SLOW_ID() internal view returns (uint64 id) {
        (,,,, id,,,,,) = rolesData.LPM_SLOW();
    }

    /// @notice Returns ARE role ID from RolesData
    function ARE_ID() internal view returns (uint64 id) {
        (,,,, id,,,,,) = rolesData.ARE();
    }

    /// @notice Returns BVM_FAST role ID from RolesData
    function BVM_FAST_ID() internal view returns (uint64 id) {
        (,,,, id,,,,,) = rolesData.BVM_FAST();
    }

    /// @notice Returns BVM_SLOW role ID from RolesData
    function BVM_SLOW_ID() internal view returns (uint64 id) {
        (,,,, id,,,,,) = rolesData.BVM_SLOW();
    }

    /// @notice Returns BVC role ID from RolesData
    function BVC_ID() internal view returns (uint64 id) {
        (,,,, id,,,,,) = rolesData.BVC();
    }

    /// @notice Returns BVA_FAST role ID from RolesData
    function BVA_FAST_ID() internal view returns (uint64 id) {
        (,,,, id,,,,,) = rolesData.BVA_FAST();
    }

    /// @notice Returns BVA_SLOW role ID from RolesData
    function BVA_SLOW_ID() internal view returns (uint64 id) {
        (,,,, id,,,,,) = rolesData.BVA_SLOW();
    }

    /// @notice Returns BVD role ID from RolesData
    function BVD_ID() internal view returns (uint64 id) {
        (,,,, id,,,,,) = rolesData.BVD();
    }

    /// @notice Returns UVM_FAST role ID from RolesData
    function UVM_FAST_ID() internal view returns (uint64 id) {
        (,,,, id,,,,,) = rolesData.UVM_FAST();
    }

    /// @notice Returns UVM_SLOW role ID from RolesData
    function UVM_SLOW_ID() internal view returns (uint64 id) {
        (,,,, id,,,,,) = rolesData.UVM_SLOW();
    }

    /// @notice Returns UVC role ID from RolesData
    function UVC_ID() internal view returns (uint64 id) {
        (,,,, id,,,,,) = rolesData.UVC();
    }

    /// @notice Returns UVA role ID from RolesData
    function UVA_ID() internal view returns (uint64 id) {
        (,,,, id,,,,,) = rolesData.UVA();
    }

    // ============ Dynamic Execution Delay Accessors ============

    /// @notice Returns LPM_SLOW execution delay from RolesData
    function _getDelay_LPM_SLOW() internal view returns (uint32 delay) {
        (,, delay,,,,,,,) = rolesData.LPM_SLOW();
    }

    /// @notice Returns BVM_SLOW execution delay from RolesData
    function _getDelay_BVM_SLOW() internal view returns (uint32 delay) {
        (,, delay,,,,,,,) = rolesData.BVM_SLOW();
    }

    /// @notice Returns BVC execution delay from RolesData
    function _getDelay_BVC() internal view returns (uint32 delay) {
        (,, delay,,,,,,,) = rolesData.BVC();
    }

    /// @notice Returns BVA_SLOW execution delay from RolesData
    function _getDelay_BVA_SLOW() internal view returns (uint32 delay) {
        (,, delay,,,,,,,) = rolesData.BVA_SLOW();
    }

    /// @notice Returns UVM_SLOW execution delay from RolesData
    function _getDelay_UVM_SLOW() internal view returns (uint32 delay) {
        (,, delay,,,,,,,) = rolesData.UVM_SLOW();
    }

    /// @notice Returns UVC execution delay from RolesData
    function _getDelay_UVC() internal view returns (uint32 delay) {
        (,, delay,,,,,,,) = rolesData.UVC();
    }

    // ============ Dynamic Label Accessors ============

    /// @notice Returns EXECUTOR label from RolesData
    function _getLabel_EXECUTOR() internal view returns (string memory label) {
        (,,,,, label,,,,) = rolesData.EXECUTOR();
    }

    /// @notice Returns LPCM label from RolesData
    function _getLabel_LPCM() internal view returns (string memory label) {
        (,,,,, label,,,,) = rolesData.LPCM();
    }

    /// @notice Returns LPM_FAST label from RolesData
    function _getLabel_LPM_FAST() internal view returns (string memory label) {
        (,,,,, label,,,,) = rolesData.LPM_FAST();
    }

    /// @notice Returns LPM_SLOW label from RolesData
    function _getLabel_LPM_SLOW() internal view returns (string memory label) {
        (,,,,, label,,,,) = rolesData.LPM_SLOW();
    }

    /// @notice Returns ARE label from RolesData
    function _getLabel_ARE() internal view returns (string memory label) {
        (,,,,, label,,,,) = rolesData.ARE();
    }

    /// @notice Returns BVM_FAST label from RolesData
    function _getLabel_BVM_FAST() internal view returns (string memory label) {
        (,,,,, label,,,,) = rolesData.BVM_FAST();
    }

    /// @notice Returns BVM_SLOW label from RolesData
    function _getLabel_BVM_SLOW() internal view returns (string memory label) {
        (,,,,, label,,,,) = rolesData.BVM_SLOW();
    }

    /// @notice Returns BVC label from RolesData
    function _getLabel_BVC() internal view returns (string memory label) {
        (,,,,, label,,,,) = rolesData.BVC();
    }

    /// @notice Returns BVA_FAST label from RolesData
    function _getLabel_BVA_FAST() internal view returns (string memory label) {
        (,,,,, label,,,,) = rolesData.BVA_FAST();
    }

    /// @notice Returns BVA_SLOW label from RolesData
    function _getLabel_BVA_SLOW() internal view returns (string memory label) {
        (,,,,, label,,,,) = rolesData.BVA_SLOW();
    }

    /// @notice Returns BVD label from RolesData
    function _getLabel_BVD() internal view returns (string memory label) {
        (,,,,, label,,,,) = rolesData.BVD();
    }

    /// @notice Returns UVM_FAST label from RolesData
    function _getLabel_UVM_FAST() internal view returns (string memory label) {
        (,,,,, label,,,,) = rolesData.UVM_FAST();
    }

    /// @notice Returns UVM_SLOW label from RolesData
    function _getLabel_UVM_SLOW() internal view returns (string memory label) {
        (,,,,, label,,,,) = rolesData.UVM_SLOW();
    }

    /// @notice Returns UVC label from RolesData
    function _getLabel_UVC() internal view returns (string memory label) {
        (,,,,, label,,,,) = rolesData.UVC();
    }

    /// @notice Returns UVA label from RolesData
    function _getLabel_UVA() internal view returns (string memory label) {
        (,,,,, label,,,,) = rolesData.UVA();
    }

    // ============ Loan Provider Role Configuration ============

    /// @notice Grant Loan Provider roles to test actors
    /// @param user Additional user address to grant EXECUTOR role (for creating loans)
    function _setLoanRoles(address user) internal {
        manager.grantRole(EXECUTOR_ID(), executor, NO_DELAY);
        manager.grantRole(EXECUTOR_ID(), user, NO_DELAY); // Grant to user so they can create loans
        manager.grantRole(LPCM_ID(), lpcm, NO_DELAY);
        manager.grantRole(LPM_FAST_ID(), lpm_fast, NO_DELAY);
        manager.grantRole(LPM_SLOW_ID(), lpm_slow, _getDelay_LPM_SLOW());
    }

    /// @notice Set target function selectors for Loan contract roles
    /// @param loanContract The Loan contract address
    function _setLoanTargetSelectors(address loanContract) internal {
        // Use selectors from RolesData for consistency with production
        manager.setTargetFunctionRole(loanContract, rolesData.getEXECUTOR_SELECTORS(), EXECUTOR_ID());
        manager.setTargetFunctionRole(loanContract, rolesData.getLPCM_SELECTORS(), LPCM_ID());
        manager.setTargetFunctionRole(loanContract, rolesData.getLPM_FAST_SELECTORS(), LPM_FAST_ID());
        manager.setTargetFunctionRole(loanContract, rolesData.getLPM_SLOW_SELECTORS(), LPM_SLOW_ID());
    }

    // ============ Auto Repayment Role Configuration ============

    /// @notice Grant Auto Repayment roles to test actors
    function _setAutoRepaymentRoles() internal {
        manager.grantRole(ARE_ID(), are, NO_DELAY);
    }

    /// @notice Set target function selectors for AutoRepayment contract roles
    /// @param autoRepaymentContract The AutoRepayment contract address
    function _setAutoRepaymentTargetSelectors(address autoRepaymentContract) internal {
        manager.setTargetFunctionRole(autoRepaymentContract, rolesData.getARE_SELECTORS(), ARE_ID());
    }

    // ============ BTC Vault Role Configuration ============

    /// @notice Grant BTC Vault roles to test actors
    /// @param user Additional user address to grant BVD role (for deposits)
    function _setBTCVaultRoles(address user) internal {
        manager.grantRole(BVM_FAST_ID(), bvm_fast, NO_DELAY);
        manager.grantRole(BVM_SLOW_ID(), bvm_slow, _getDelay_BVM_SLOW());
        manager.grantRole(BVC_ID(), bvc, _getDelay_BVC());
        manager.grantRole(BVA_FAST_ID(), bva_fast, NO_DELAY);
        manager.grantRole(BVA_SLOW_ID(), bva_slow, _getDelay_BVA_SLOW());
        manager.grantRole(BVD_ID(), bvd, NO_DELAY);
        manager.grantRole(BVD_ID(), user, NO_DELAY); // Allow user to deposit
    }

    /// @notice Set target function selectors for BTCVault contract roles
    /// @param btcVaultContract The BTCVault contract address
    function _setBTCVaultTargetSelectors(address btcVaultContract) internal {
        manager.setTargetFunctionRole(btcVaultContract, rolesData.getBVM_FAST_SELECTORS(), BVM_FAST_ID());
        manager.setTargetFunctionRole(btcVaultContract, rolesData.getBVM_SLOW_SELECTORS(), BVM_SLOW_ID());
        manager.setTargetFunctionRole(btcVaultContract, rolesData.getBVC_SELECTORS(), BVC_ID());
        manager.setTargetFunctionRole(btcVaultContract, rolesData.getBVA_FAST_SELECTORS(), BVA_FAST_ID());
        manager.setTargetFunctionRole(btcVaultContract, rolesData.getBVA_SLOW_SELECTORS(), BVA_SLOW_ID());
        manager.setTargetFunctionRole(btcVaultContract, rolesData.getBVD_SELECTORS(), BVD_ID());
    }

    // ============ USDC Vault Role Configuration ============

    /// @notice Grant USDC Vault roles to test actors
    function _setUSDCVaultRoles() internal {
        manager.grantRole(UVM_FAST_ID(), uvm_fast, NO_DELAY);
        manager.grantRole(UVM_SLOW_ID(), uvm_slow, _getDelay_UVM_SLOW());
        manager.grantRole(UVC_ID(), uvc, _getDelay_UVC());
        manager.grantRole(UVA_ID(), uva, NO_DELAY);
    }

    /// @notice Set target function selectors for USDCVault contract roles
    /// @param usdcVaultContract The USDCVault contract address
    function _setUSDCVaultTargetSelectors(address usdcVaultContract) internal {
        manager.setTargetFunctionRole(usdcVaultContract, rolesData.getUVM_FAST_SELECTORS(), UVM_FAST_ID());
        manager.setTargetFunctionRole(usdcVaultContract, rolesData.getUVM_SLOW_SELECTORS(), UVM_SLOW_ID());
        manager.setTargetFunctionRole(usdcVaultContract, rolesData.getUVC_SELECTORS(), UVC_ID());
        manager.setTargetFunctionRole(usdcVaultContract, rolesData.getUVA_SELECTORS(), UVA_ID());
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

    /// @notice Get role ID by role name dynamically from RolesData
    /// @param roleName The name of the role (must match RolesData labels)
    /// @return roleId The role ID
    function _getRoleId(string memory roleName) internal view returns (uint64 roleId) {
        bytes32 nameHash = keccak256(bytes(roleName));

        if (nameHash == keccak256(bytes(_getLabel_EXECUTOR()))) return EXECUTOR_ID();
        if (nameHash == keccak256(bytes(_getLabel_LPCM()))) return LPCM_ID();
        if (nameHash == keccak256(bytes(_getLabel_LPM_FAST()))) return LPM_FAST_ID();
        if (nameHash == keccak256(bytes(_getLabel_LPM_SLOW()))) return LPM_SLOW_ID();
        if (nameHash == keccak256(bytes(_getLabel_ARE()))) return ARE_ID();
        if (nameHash == keccak256(bytes(_getLabel_BVM_FAST()))) return BVM_FAST_ID();
        if (nameHash == keccak256(bytes(_getLabel_BVM_SLOW()))) return BVM_SLOW_ID();
        if (nameHash == keccak256(bytes(_getLabel_BVC()))) return BVC_ID();
        if (nameHash == keccak256(bytes(_getLabel_BVA_FAST()))) return BVA_FAST_ID();
        if (nameHash == keccak256(bytes(_getLabel_BVA_SLOW()))) return BVA_SLOW_ID();
        if (nameHash == keccak256(bytes(_getLabel_BVD()))) return BVD_ID();
        if (nameHash == keccak256(bytes(_getLabel_UVM_FAST()))) return UVM_FAST_ID();
        if (nameHash == keccak256(bytes(_getLabel_UVM_SLOW()))) return UVM_SLOW_ID();
        if (nameHash == keccak256(bytes(_getLabel_UVC()))) return UVC_ID();
        if (nameHash == keccak256(bytes(_getLabel_UVA()))) return UVA_ID();

        revert("BitmorTestBase: Unknown role");
    }

    /// @notice Get execution delay for a role by name dynamically from RolesData
    /// @param roleName The name of the role (must match RolesData labels)
    /// @return delay The execution delay in seconds
    function _getRoleDelay(string memory roleName) internal view returns (uint32 delay) {
        bytes32 nameHash = keccak256(bytes(roleName));

        // Roles with delays - read from RolesData
        if (nameHash == keccak256(bytes(_getLabel_LPM_SLOW()))) return _getDelay_LPM_SLOW();
        if (nameHash == keccak256(bytes(_getLabel_BVM_SLOW()))) return _getDelay_BVM_SLOW();
        if (nameHash == keccak256(bytes(_getLabel_BVC()))) return _getDelay_BVC();
        if (nameHash == keccak256(bytes(_getLabel_BVA_SLOW()))) return _getDelay_BVA_SLOW();
        if (nameHash == keccak256(bytes(_getLabel_UVM_SLOW()))) return _getDelay_UVM_SLOW();
        if (nameHash == keccak256(bytes(_getLabel_UVC()))) return _getDelay_UVC();

        // All other roles have NO_DELAY
        if (nameHash == keccak256(bytes(_getLabel_EXECUTOR()))) return NO_DELAY;
        if (nameHash == keccak256(bytes(_getLabel_LPCM()))) return NO_DELAY;
        if (nameHash == keccak256(bytes(_getLabel_LPM_FAST()))) return NO_DELAY;
        if (nameHash == keccak256(bytes(_getLabel_ARE()))) return NO_DELAY;
        if (nameHash == keccak256(bytes(_getLabel_BVM_FAST()))) return NO_DELAY;
        if (nameHash == keccak256(bytes(_getLabel_BVA_FAST()))) return NO_DELAY;
        if (nameHash == keccak256(bytes(_getLabel_BVD()))) return NO_DELAY;
        if (nameHash == keccak256(bytes(_getLabel_UVM_FAST()))) return NO_DELAY;
        if (nameHash == keccak256(bytes(_getLabel_UVA()))) return NO_DELAY;

        revert("BitmorTestBase: Unknown role");
    }

    // ============ Loan Configuration Helpers ============

    /// @notice Configure loan parameters using proper setters via AccessManager delayed operations
    /// @param loanContract The Loan contract address
    /// @param maxBTC Maximum BTC amount (in 8 decimals)
    /// @param minBTC Minimum BTC amount (in 8 decimals)
    /// @param slippage Slippage in basis points for swaps
    /// @param minDepositBps Minimum deposit in basis points
    function _configureLoanParameters(
        address loanContract,
        uint256 maxBTC,
        uint256 minBTC,
        uint256 slippage,
        uint256 minDepositBps
    ) internal {
        _scheduleAndExecute(
            loanContract, lpm_slow, LPM_SLOW_ID(), abi.encodeWithSignature("setMaxBTCAmount(uint64)", uint64(maxBTC))
        );
        _scheduleAndExecute(
            loanContract, lpm_slow, LPM_SLOW_ID(), abi.encodeWithSignature("setMinBTCAmount(uint64)", uint64(minBTC))
        );
        _scheduleAndExecute(
            loanContract,
            lpm_slow,
            LPM_SLOW_ID(),
            abi.encodeWithSignature("setSlippageForSwap(uint16)", uint16(slippage))
        );
        _scheduleAndExecute(
            loanContract,
            lpm_slow,
            LPM_SLOW_ID(),
            abi.encodeWithSignature("setMinDepositBps(uint16)", uint16(minDepositBps))
        );
        _scheduleAndExecute(
            loanContract,
            lpm_slow,
            LPM_SLOW_ID(),
            abi.encodeWithSignature(
                "setSlippageForSharesToAsset(uint16)", uint16(TestConstants.SLIPPAGE_SHARES_TO_ASSET)
            )
        );

        _scheduleAndExecute(
            loanContract,
            lpm_slow,
            LPM_SLOW_ID(),
            abi.encodeWithSignature("setMaxDuration(uint16)", uint16(TestConstants.MAX_DURATION))
        );
    }
}
