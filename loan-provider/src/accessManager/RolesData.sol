// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.30;

import {ILoan} from "../interfaces/ILoan.sol";
import {IAutoRepayment} from "../interfaces/IAutoRepayment.sol";
import {BTCVault} from "../vaults/btc-vault/BTCVault.sol";
import {USDCVault} from "../vaults/usdc-vault/USDCVault.sol";
import {ISimpleStrategy} from "../interfaces/ISimpleStrategy.sol";

/// @title RolesData
/// @author Bitmor Protocol
/// @notice Defines all role-based access control data for the Bitmor Protocol ecosystem
/// @dev Contains role definitions for AccessManager controlling LoanProvider, BTC Vault, USDC Vault, and AutoRepayment contracts
/// @custom:security All roles follow OpenZeppelin AccessManager v5.5.0 patterns with proper time delays and guardian protections
contract RolesData {
    /// @notice Guardian role configuration for operations that can be cancelled
    /// @dev Guardians provide security by being able to cancel delayed operations before execution
    struct RoleGuardian {
        address grantee;
        /// @dev The address assigned the guardian role
        uint64 id;
        /// @dev The guardian role ID (follows pattern 9XXX where XXX is the role being guarded)
        bool isContract;
    }

    /// @dev True if grantee is a contract (multisig), false if EOA

    /// @notice Complete role configuration for access control
    /// @dev Defines permissions, delays, and guardianship for protocol functions
    struct RoleData {
        address target;
        /// @dev The target contract this role can interact with
        bool isContract;
        /// @dev True if the role grantee should be a contract
        uint32 executionDelay;
        /// @dev Time delay before operations can be executed (0 = immediate, 1 DAY = delayed)
        uint32 grantDelay;
        /// @dev Time delay before role can be granted (typically 0)
        uint64 id;
        /// @dev Unique role identifier matching README specifications
        string label;
        /// @dev Human-readable role name matching README labels
        bytes4[] selectors;
        /// @dev Function selectors this role is authorized to call
        bool isGuarded;
        /// @dev True if this role has guardian protection for cancelling operations
        RoleGuardian guardian;
        /// @dev Guardian configuration if isGuarded is true
        address grantee;
        /// @dev Initial address to be granted this role (typically initial admin)
        uint64 adminRoleId;
    }
    /// @dev Role ID that can manage this role (typically 0 for ADMIN)

    /// @notice Initial admin address for the AccessManager deployment
    /// @dev This address gets the ADMIN role (0) and can grant all other roles
    //! TODO: Verify this admin address is correct for production deployment
    address public constant INITIAL_ADMIN = 0x2Acdf6a2f893687CcD341a1Ad7e27102b665d8c4;

    /// @notice Standard time delay of 1 day for sensitive operations
    uint32 constant ONE_DAY = 1 days;

    /// @notice Empty selector array for roles without specific function restrictions
    bytes4[] EMPTY_SELECTORS = new bytes4[](0);

    /// @notice Default guardian configuration for roles without guardian protection
    /// @dev Uses ID 900 as a placeholder for "no guardian"
    RoleGuardian public NO_GUARDIAN = RoleGuardian({grantee: address(0), isContract: false, id: 900});

    // ===== GUARDIAN ROLE DEFINITIONS =====

    /// @notice Guardian for LPM_SLOW operations - can cancel delayed loan provider management operations
    /// @dev Protects against malicious or erroneous state changes in LoanProvider contract
    RoleGuardian public GUARDIAN_LPM_SLOW = RoleGuardian({grantee: INITIAL_ADMIN, isContract: true, id: 930});

    /// @notice Guardian for BVM_SLOW operations - can cancel delayed BTC vault management operations
    /// @dev Protects against malicious fee recipient changes and unpause operations
    RoleGuardian public GUARDIAN_BVM_SLOW = RoleGuardian({grantee: INITIAL_ADMIN, isContract: true, id: 9110});

    /// @notice Guardian for BVC operations - can cancel delayed BTC vault curation operations
    /// @dev Protects against malicious strategy changes and cap modifications
    RoleGuardian public GUARDIAN_BVC = RoleGuardian({grantee: INITIAL_ADMIN, isContract: true, id: 912});

    /// @notice Guardian for BVA_SLOW operations - can cancel delayed BTC vault allocation operations
    /// @dev Protects against malicious queue configuration changes
    RoleGuardian public GUARDIAN_BVA_SLOW = RoleGuardian({grantee: INITIAL_ADMIN, isContract: true, id: 9130});

    /// @notice Guardian for UVM_SLOW operations - can cancel delayed USDC vault management operations
    /// @dev Protects against malicious unpause operations in USDC vault
    RoleGuardian public GUARDIAN_UVM_SLOW = RoleGuardian({grantee: INITIAL_ADMIN, isContract: true, id: 9210});

    /// @notice Guardian for UVC operations - can cancel delayed USDC vault curation operations
    /// @dev Protects against malicious strategy and yield source allocation changes
    RoleGuardian public GUARDIAN_UVC = RoleGuardian({grantee: INITIAL_ADMIN, isContract: true, id: 922});

    // ===== ADMINISTRATIVE ROLE DEFINITIONS =====

    /// @notice Top-level administrative role controlling the AccessManager itself
    /// @dev Can grant/revoke all other roles and cancel operations. Should be a multisig for security
    RoleData public ADMIN = RoleData({
        target: INITIAL_ADMIN,
        isContract: true,
        executionDelay: 0,
        grantDelay: 0,
        id: 0,
        isGuarded: false,
        label: "ADMIN",
        guardian: NO_GUARDIAN,
        selectors: EMPTY_SELECTORS,
        grantee: INITIAL_ADMIN,
        adminRoleId: 0
    });

    // ===== LOAN PROVIDER ROLE DEFINITIONS =====

    /// @notice Executor role for loan initialization and insurance updates
    /// @dev EOA role for immediate execution of loan operations
    RoleData public EXECUTOR = RoleData({
        target: INITIAL_ADMIN, // Will be updated to actual LoanProvider address
        isContract: false,
        executionDelay: 0,
        grantDelay: 0,
        id: 1,
        isGuarded: false,
        label: "EXECUTOR",
        guardian: NO_GUARDIAN,
        selectors: getEXECUTOR_SELECTORS(),
        grantee: INITIAL_ADMIN,
        adminRoleId: 0
    });

    /// @notice Lending Pool Collateral Manager role for loan data updates
    /// @dev Contract-based role for automated loan data management
    RoleData public LPCM = RoleData({
        target: INITIAL_ADMIN, // Will be updated to actual LoanProvider address
        isContract: true,
        executionDelay: 0,
        grantDelay: 0,
        id: 2,
        isGuarded: false,
        label: "LPCM",
        guardian: NO_GUARDIAN,
        selectors: getLPCM_SELECTORS(),
        grantee: INITIAL_ADMIN,
        adminRoleId: 0
    });

    /// @notice Fast Loan Provider Manager role for immediate pause operations
    /// @dev Multisig role for emergency pause functionality
    RoleData public LPM_FAST = RoleData({
        target: INITIAL_ADMIN, // Will be updated to actual LoanProvider address
        isContract: true,
        executionDelay: 0,
        grantDelay: 0,
        id: 3,
        isGuarded: false,
        label: "LPM_FAST",
        guardian: NO_GUARDIAN,
        selectors: getLPM_FAST_SELECTORS(),
        grantee: INITIAL_ADMIN,
        adminRoleId: 0
    });

    /// @notice Slow Loan Provider Manager role for delayed state variable updates
    /// @dev Multisig role with 1-day delay for critical parameter changes
    RoleData public LPM_SLOW = RoleData({
        target: INITIAL_ADMIN, // Will be updated to actual LoanProvider address
        isContract: true,
        executionDelay: ONE_DAY,
        grantDelay: 0,
        id: 30,
        label: "LPM_SLOW",
        guardian: GUARDIAN_LPM_SLOW,
        isGuarded: true,
        selectors: getLPM_SLOW_SELECTORS(),
        grantee: INITIAL_ADMIN,
        adminRoleId: 0
    });

    // ===== AUTO REPAYMENT ROLE DEFINITIONS =====

    /// @notice Auto Repayment Executor role for executing automated repayments
    /// @dev EOA role for immediate execution of auto repayment operations
    RoleData public ARE = RoleData({
        target: INITIAL_ADMIN, // Will be updated to actual AutoRepayment address
        isContract: false,
        executionDelay: 0,
        grantDelay: 0,
        id: 4,
        isGuarded: false,
        label: "ARE",
        guardian: NO_GUARDIAN,
        selectors: getARE_SELECTORS(),
        grantee: INITIAL_ADMIN,
        adminRoleId: 0
    });

    // ===== BTC VAULT ROLE DEFINITIONS =====

    /// @notice Fast BTC Vault Manager role for immediate pause and emergency operations
    /// @dev Multisig role for emergency controls in BTC vault
    RoleData public BVM_FAST = RoleData({
        target: INITIAL_ADMIN, // Will be updated to actual BTC Vault address
        isContract: true,
        executionDelay: 0,
        grantDelay: 0,
        id: 11,
        isGuarded: false,
        label: "BVM_FAST",
        guardian: NO_GUARDIAN,
        selectors: getBVM_FAST_SELECTORS(),
        grantee: INITIAL_ADMIN,
        adminRoleId: 0
    });

    /// @notice Slow BTC Vault Manager role for delayed fee recipient and unpause operations
    /// @dev Multisig role with 1-day delay for critical parameter changes
    RoleData public BVM_SLOW = RoleData({
        target: INITIAL_ADMIN, // Will be updated to actual BTC Vault address
        isContract: true,
        executionDelay: ONE_DAY,
        grantDelay: 0,
        id: 110,
        isGuarded: true,
        label: "BVM_SLOW",
        guardian: GUARDIAN_BVM_SLOW,
        selectors: getBVM_SLOW_SELECTORS(),
        grantee: INITIAL_ADMIN,
        adminRoleId: 0
    });

    /// @notice BTC Vault Curator role for strategy management with delays
    /// @dev Multisig role with 1-day delay for strategy additions, removals, and cap changes
    RoleData public BVC = RoleData({
        target: INITIAL_ADMIN, // Will be updated to actual BTC Vault address
        isContract: true,
        executionDelay: ONE_DAY,
        grantDelay: 0,
        id: 12,
        isGuarded: true,
        label: "BVC",
        guardian: GUARDIAN_BVC,
        selectors: getBVC_SELECTORS(),
        grantee: INITIAL_ADMIN,
        adminRoleId: 0
    });

    /// @notice Fast BTC Vault Allocator role for immediate asset reallocation
    /// @dev Role for immediate asset reallocation operations (TBD if EOA or contract)
    RoleData public BVA_FAST = RoleData({
        target: INITIAL_ADMIN, // Will be updated to actual BTC Vault address
        isContract: false, // TBD in README
        executionDelay: 0,
        grantDelay: 0,
        id: 13,
        isGuarded: false,
        label: "BVA_FAST",
        guardian: NO_GUARDIAN,
        selectors: getBVA_FAST_SELECTORS(),
        grantee: INITIAL_ADMIN,
        adminRoleId: 0
    });

    /// @notice Slow BTC Vault Allocator role for delayed queue configuration
    /// @dev Role with 1-day delay for supply/withdraw queue configuration (TBD if EOA or contract)
    RoleData public BVA_SLOW = RoleData({
        target: INITIAL_ADMIN, // Will be updated to actual BTC Vault address
        isContract: false, // TBD in README
        executionDelay: ONE_DAY,
        grantDelay: 0,
        id: 130,
        isGuarded: true,
        label: "BVA_SLOW",
        guardian: GUARDIAN_BVA_SLOW,
        selectors: getBVA_SLOW_SELECTORS(),
        grantee: INITIAL_ADMIN,
        adminRoleId: 0
    });

    /// @notice BTC Vault Deposit role for BTC vault deposit operations
    /// @dev Contract-based role typically assigned to LoanProvider contract
    RoleData public BVD = RoleData({
        target: INITIAL_ADMIN, // Will be updated to actual BTC Vault address
        isContract: true,
        executionDelay: 0,
        grantDelay: 0,
        id: 14,
        isGuarded: false,
        label: "BVD",
        guardian: NO_GUARDIAN,
        selectors: getBVD_SELECTORS(),
        grantee: INITIAL_ADMIN,
        adminRoleId: 0
    });

    // ===== USDC VAULT ROLE DEFINITIONS =====

    /// @notice Fast USDC Vault Manager role for immediate pause and fund withdrawal
    /// @dev Multisig role for emergency controls in USDC vault
    RoleData public UVM_FAST = RoleData({
        target: INITIAL_ADMIN, // Will be updated to actual USDC Vault address
        isContract: true,
        executionDelay: 0,
        grantDelay: 0,
        id: 21,
        isGuarded: false,
        label: "UVM_FAST",
        guardian: NO_GUARDIAN,
        selectors: getUVM_FAST_SELECTORS(),
        grantee: INITIAL_ADMIN,
        adminRoleId: 0
    });

    /// @notice Slow USDC Vault Manager role for delayed unpause operations
    /// @dev Multisig role with 1-day delay for unpause operations
    RoleData public UVM_SLOW = RoleData({
        target: INITIAL_ADMIN, // Will be updated to actual USDC Vault address
        isContract: true,
        executionDelay: ONE_DAY,
        grantDelay: 0,
        id: 210,
        isGuarded: true,
        label: "UVM_SLOW",
        guardian: GUARDIAN_UVM_SLOW,
        selectors: getUVM_SLOW_SELECTORS(),
        grantee: INITIAL_ADMIN,
        adminRoleId: 0
    });

    /// @notice USDC Vault Curator role for strategy and yield source management
    /// @dev Multisig role with 1-day delay for strategy configuration changes
    RoleData public UVC = RoleData({
        target: INITIAL_ADMIN, // Will be updated to actual USDC Vault address
        isContract: true,
        executionDelay: ONE_DAY,
        grantDelay: 0,
        id: 22,
        isGuarded: true,
        label: "UVC",
        guardian: GUARDIAN_UVC,
        selectors: getUVC_SELECTORS(),
        grantee: INITIAL_ADMIN,
        adminRoleId: 0
    });

    /// @notice USDC Vault Allocator role for immediate asset reallocation
    /// @dev Role for immediate asset reallocation operations (TBD if EOA or contract)
    RoleData public UVA = RoleData({
        target: INITIAL_ADMIN, // Will be updated to actual USDC Vault address
        isContract: false, // TBD in README
        executionDelay: 0,
        grantDelay: 0,
        id: 23,
        isGuarded: false,
        label: "UVA",
        guardian: NO_GUARDIAN,
        selectors: getUVA_SELECTORS(),
        grantee: INITIAL_ADMIN,
        adminRoleId: 0
    });

    // ===== ROLE ACCESSOR FUNCTIONS =====

    /// @notice Returns all role configurations for the Bitmor Protocol
    /// @dev Returns all 16 operational roles (excludes guardian roles)
    /// @return roles Array of all RoleData configurations
    function getAllRoles() external view returns (RoleData[] memory roles) {
        roles = new RoleData[](16);
        roles[0] = ADMIN;
        roles[1] = EXECUTOR;
        roles[2] = LPCM;
        roles[3] = LPM_FAST;
        roles[4] = LPM_SLOW;
        roles[5] = ARE;
        roles[6] = BVM_FAST;
        roles[7] = BVM_SLOW;
        roles[8] = BVC;
        roles[9] = BVA_FAST;
        roles[10] = BVA_SLOW;
        roles[11] = BVD;
        roles[12] = UVM_FAST;
        roles[13] = UVM_SLOW;
        roles[14] = UVC;
        roles[15] = UVA;
    }

    // ===== FUNCTION SELECTOR DEFINITIONS =====

    /// @notice Returns function selectors for EXECUTOR role
    /// @dev Selectors for initializeLoan and updateInsuranceId functions
    /// @return selectors Array of function selectors
    function getEXECUTOR_SELECTORS() public pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](2);
        selectors[0] = ILoan.initializeLoan.selector;
        selectors[1] = ILoan.updateInsuranceId.selector;
    }

    /// @notice Returns function selectors for LPCM role
    /// @dev Selectors for updateLoanData function
    /// @return selectors Array of function selectors
    function getLPCM_SELECTORS() public pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](2);
        selectors[0] = ILoan.updateLoanDataForFullLiquidation.selector;
        selectors[1] = ILoan.updateLoanDataForMicroLiquidation.selector;
    }

    /// @notice Returns function selectors for LPM_FAST role
    /// @dev Selectors for pause function (uses Pausable interface via Loan contract)
    /// @return selectors Array of function selectors
    function getLPM_FAST_SELECTORS() public pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](1);
        // pause() selector is 0x8456cb59
        selectors[0] = bytes4(keccak256("pause()"));
    }

    /// @notice Returns function selectors for LPM_SLOW role
    /// @dev Selectors for state variable updates and unpause function
    /// @return selectors Array of function selectors
    function getLPM_SLOW_SELECTORS() public pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](13);
        selectors[0] = ILoan.setLoanVaultFactory.selector;
        selectors[1] = ILoan.setPremiumCollector.selector;
        selectors[2] = ILoan.setGracePeriod.selector;
        selectors[3] = ILoan.setPreClosureFee.selector;
        selectors[4] = bytes4(keccak256("unpause()"));
        selectors[5] = ILoan.setMaxBTCAmount.selector;
        selectors[6] = ILoan.setMinBTCAmount.selector;
        selectors[7] = ILoan.setSlippageForSwap.selector;
        selectors[8] = ILoan.setSlippageForSharesToAsset.selector;
        selectors[9] = ILoan.setMinDepositBps.selector;
        selectors[10] = ILoan.setLiquidationFeeBps.selector;
        selectors[11] = ILoan.setLiquidationFeeCollector.selector;
        selectors[12] = ILoan.setSwapper.selector;
    }

    /// @notice Returns function selectors for ARE role
    /// @dev Selectors for executeAutoRepayment function
    /// @return selectors Array of function selectors
    function getARE_SELECTORS() public pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](1);
        selectors[0] = IAutoRepayment.executeAutoRepayment.selector;
    }

    /// @notice Returns function selectors for BVM_FAST role
    /// @dev Selectors for pause and emergencyWithdrawFunds functions on BTCVault
    /// @return selectors Array of function selectors
    function getBVM_FAST_SELECTORS() public pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](2);
        selectors[0] = bytes4(keccak256("pause()"));
        selectors[1] = BTCVault.emergencyWithdrawFunds.selector;
    }

    /// @notice Returns function selectors for BVM_SLOW role
    /// @dev Selectors for setFeeRecipient and unpause functions on BTCVault
    /// @return selectors Array of function selectors
    function getBVM_SLOW_SELECTORS() public pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](2);
        selectors[0] = BTCVault.setFeeRecipient.selector;
        selectors[1] = bytes4(keccak256("unpause()"));
    }

    /// @notice Returns function selectors for BVC role
    /// @dev Selectors for strategy management functions on BTCVault
    /// @return selectors Array of function selectors
    function getBVC_SELECTORS() public pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](3);
        selectors[0] = BTCVault.addStrategy.selector;
        selectors[1] = BTCVault.changeStrategyCap.selector;
        selectors[2] = BTCVault.setMaxStrategies.selector;
    }

    /// @notice Returns function selectors for BVA_FAST role
    /// @dev Selectors for reallocateFunds function on BTCVault
    /// @return selectors Array of function selectors
    function getBVA_FAST_SELECTORS() public pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](1);
        selectors[0] = BTCVault.reallocateFunds.selector;
    }

    /// @notice Returns function selectors for BVA_SLOW role
    /// @dev Selectors for queue management functions on BTCVault
    /// @return selectors Array of function selectors
    function getBVA_SLOW_SELECTORS() public pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](2);
        selectors[0] = BTCVault.updateSupplyQueue.selector;
        selectors[1] = BTCVault.updateWithdrawQueue.selector;
    }

    /// @notice Returns function selectors for BVD role
    /// @dev Selectors for deposit function on BTCVault (ERC4626 standard)
    /// @return selectors Array of function selectors
    function getBVD_SELECTORS() public pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](2);
        selectors[0] = BTCVault.deposit.selector;
        selectors[1] = BTCVault.mint.selector;
    }

    /// @notice Returns function selectors for UVM_FAST role
    /// @dev Selectors for pause function on USDCVault
    /// @return selectors Array of function selectors
    function getUVM_FAST_SELECTORS() public pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](1);
        selectors[0] = bytes4(keccak256("pause()"));
        // Note: withdrawAllFunds() is not implemented on USDCVault (only on ISimpleStrategy)
    }

    /// @notice Returns function selectors for UVM_SLOW role
    /// @dev Selectors for unpause function
    /// @return selectors Array of function selectors
    function getUVM_SLOW_SELECTORS() public pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](1);
        selectors[0] = bytes4(keccak256("unpause()"));
    }

    /// @notice Returns function selectors for UVC role
    /// @dev Selectors for strategy management functions on USDCVault
    /// @return selectors Array of function selectors
    function getUVC_SELECTORS() public pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](3);
        selectors[0] = USDCVault.setStrategy.selector;
        selectors[1] = USDCVault.updateMinimumDeltaRequired.selector;
        selectors[2] = USDCVault.updateExternalAllocation.selector;
    }

    /// @notice Returns function selectors for UVA role
    /// @dev Selectors for reallocateAssets functions on USDCVault (both overloads)
    /// @return selectors Array of function selectors
    function getUVA_SELECTORS() public pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](2);
        selectors[0] = bytes4(keccak256("reallocateAssets()"));
        selectors[1] = bytes4(keccak256("reallocateAssets(uint256)"));
    }
}
