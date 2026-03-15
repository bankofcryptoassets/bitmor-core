// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script, console2} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {Upgrades} from "@openzeppelin-foundry-upgrades/Upgrades.sol";
import {Options} from "@openzeppelin-foundry-upgrades/Options.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {BitmorAccessManager} from "@bitmor/accessManager/BitmorAccessManager.sol";
import {RolesData} from "@bitmor-config/RolesData.sol";
import {LoanVault} from "@bitmor/protocol/LoanVault.sol";
import {LoanVaultFactory} from "@bitmor/protocol/LoanVaultFactory.sol";
import {BeaconController} from "@bitmor/protocol/BeaconController.sol";
import {IBeaconController} from "@bitmor/interfaces/IBeaconController.sol";
import {ILoan} from "@bitmor/interfaces/ILoan.sol";
import {IBitmorAddressesProvider} from "@bitmor/interfaces/IBitmorAddressesProvider.sol";
import {DeploymentConstants} from "./DeploymentConstants.sol";
import {HelperConfig} from "../HelperConfig.s.sol";

/**
 * @title DeploymentBase
 * @author Bitmor Protocol
 * @notice Abstract base contract providing shared deployment utilities for all Bitmor deployment scripts
 * @dev Encapsulates common logic for proxy deployment, beacon proxy setup, AccessManager role wiring,
 * JSON persistence, and preflight validation. Concrete deployment scripts inherit from this and implement
 * `_getRoleGrantees()` to supply chain-specific role assignments.
 *
 * @custom:security Deployment scripts handle privileged operations (role grants, ownership transfers).
 * Ensure the deployer account is secured and review all role assignments before broadcast.
 */
abstract contract DeploymentBase is Script {
    using stdJson for string;

    // ============ Structs ============

    /**
     * @notice Addresses of all role grantees for AccessManager configuration
     * @dev Concrete deployment configs (LocalRolesConfig, MainnetRolesConfig) populate this struct.
     * Each field corresponds to an operational or administrative role in the protocol.
     */
    struct RoleGrantees {
        /// @dev Top-level administrator (ADMIN role, ID 0)
        address admin;
        /// @dev Loan initializer and insurance updater (EXECUTOR role, ID 1)
        address executor;
        /// @dev Lending pool collateral manager (LPCM role, ID 2)
        address lpcm;
        /// @dev Emergency pause for Loan (LPM_FAST role, ID 3)
        address lpmFast;
        /// @dev Delayed state updates for Loan (LPM_SLOW role, ID 30)
        address lpmSlow;
        /// @dev Auto repayment executor (ARE role, ID 4)
        address are;
        /// @dev Emergency pause/withdraw for BTCVault (BVM_FAST role, ID 11)
        address bvmFast;
        /// @dev Delayed fee/unpause for BTCVault (BVM_SLOW role, ID 110)
        address bvmSlow;
        /// @dev Strategy management for BTCVault (BVC role, ID 12)
        address bvc;
        /// @dev Immediate reallocation for BTCVault (BVA_FAST role, ID 13)
        address bvaFast;
        /// @dev Delayed queue config for BTCVault (BVA_SLOW role, ID 130)
        address bvaSlow;
        /// @dev Deposit operations for BTCVault (BVD role, ID 14)
        address bvd;
        /// @dev Emergency pause for USDCVault (UVM_FAST role, ID 21)
        address uvmFast;
        /// @dev Delayed unpause for USDCVault (UVM_SLOW role, ID 210)
        address uvmSlow;
        /// @dev Strategy/yield config for USDCVault (UVC role, ID 22)
        address uvc;
        /// @dev Immediate reallocation for USDCVault (UVA role, ID 23)
        address uva;
        /// @dev UUPS and beacon upgrade executor (UPGRADER role, ID 5)
        address upgrader;
    }

    /// @notice Addresses loaded from deployments.json (Phase 1 outputs)
    struct Phase1Addresses {
        address accessManager;
        address debtAsset; // USDC (mock or real)
        address cbBTC; // cbBTC (mock or real)
        address btcVault; // BTCVault proxy (collateralAsset)
        address btcVaultImpl; // BTCVault implementation
        address btcOracle; // BTC/USD oracle (local only, address(0) on mainnet)
        address usdcOracle; // USDC/USD oracle (local only, address(0) on mainnet)
        address aaveV3Pool; // Aave V3 Pool (mock or real)
        address aaveAddressesProvider; // Aave V3 Addresses Provider (mock or real)
        address loanLogicLib; // LoanLogic linked library (address(0) if not deployed)
        address repayLogicLib; // RepayLogic linked library (address(0) if not deployed)
        address closeLoanLogicLib; // CloseLoanLogic linked library (address(0) if not deployed)
        address flashLoanLogicLib; // FlashLoanLogic linked library (address(0) if not deployed)
    }

    /// @notice Addresses loaded from lending-pool/deployed-contracts.json
    struct LendingPoolAddresses {
        address bitmorPool;
        address aaveOracle;
        address lendingPoolAddressesProvider;
    }

    // ============ Abstract Functions ============

    /**
     * @notice Returns the role grantee addresses for the target deployment environment
     * @dev Must be implemented by concrete config contracts (e.g., LocalRolesConfig, MainnetRolesConfig)
     * @return grantees The populated RoleGrantees struct
     */
    function _getRoleGrantees() internal view virtual returns (RoleGrantees memory grantees);

    // ============ Proxy Deployment ============

    /**
     * @notice Deploys a UUPS proxy using the OpenZeppelin Foundry Upgrades library
     * @dev Wraps `Upgrades.deployUUPSProxy` for consistent usage across deployment scripts.
     * The `contractName` must match the Solidity file name (e.g., "Loan.sol:Loan").
     * @param contractName The contract name in the format expected by `Upgrades.deployUUPSProxy`
     * @param initData ABI-encoded initializer calldata (e.g., `abi.encodeCall(Loan.initialize, (...))`)
     * @return proxy The address of the deployed UUPS proxy
     */
    function _deployUUPSProxy(string memory contractName, bytes memory initData) internal returns (address proxy) {
        proxy = Upgrades.deployUUPSProxy(contractName, initData);
        console2.log("Deployed UUPS proxy for", contractName, "at:", proxy);
    }

    /**
     * @notice Returns the implementation address stored in a proxy's EIP-1967 slot
     * @dev Reads the implementation address using the OpenZeppelin Foundry Upgrades library.
     * Call this after `_deployUUPSProxy()` to obtain the actual implementation address
     * that the proxy delegates to (which is deployed internally by the Upgrades library).
     * @param proxy The proxy address to read from
     * @return impl The implementation address the proxy delegates to
     */
    function _getProxyImplementation(address proxy) internal view returns (address impl) {
        impl = Upgrades.getImplementationAddress(proxy);
    }

    /**
     * @notice Deploys a UUPS proxy with custom OpenZeppelin Upgrades options
     * @dev Use this overload for implementations that require special validation flags,
     * e.g. `unsafeAllow: "external-library-linking"` for contracts linked to external
     * libraries (Loan.sol → LoanLogic). The plugin does not verify linked library upgrade
     * safety — that must be ensured manually.
     * @param contractName The contract name in the format expected by `Upgrades.deployUUPSProxy`
     * @param initData ABI-encoded initializer calldata
     * @param opts OpenZeppelin Upgrades Options (e.g., `unsafeAllow`, `referenceContract`)
     * @return proxy The address of the deployed UUPS proxy
     */
    function _deployUUPSProxy(string memory contractName, bytes memory initData, Options memory opts)
        internal
        returns (address proxy)
    {
        proxy = Upgrades.deployUUPSProxy(contractName, initData, opts);
        console2.log("Deployed UUPS proxy for", contractName, "at:", proxy);
    }

    // ============ Beacon Proxy Deployment ============

    /**
     * @notice Deploys the complete LoanVault beacon proxy infrastructure: implementation, beacon, controller, and factory
     * @dev Deployment sequence:
     * 1. Deploy LoanVault implementation (disables initializers in constructor)
     * 2. Deploy UpgradeableBeacon with implementation, owned by this script temporarily
     * 3. Deploy BeaconController (AccessManaged wrapper for beacon upgrades)
     * 4. Transfer beacon ownership from script to BeaconController (critical handoff)
     * 5. Deploy LoanVaultFactory with beacon and loan proxy addresses
     *
     * @param accessManager The BitmorAccessManager address for the BeaconController
     * @param loanProxy The Loan proxy address that the factory will authorize for vault creation
     * @return loanVaultImpl The LoanVault implementation address
     * @return beacon The UpgradeableBeacon address
     * @return beaconController The BeaconController address (new beacon owner)
     * @return factory The LoanVaultFactory address
     */
    function _deployBeaconProxy(address accessManager, address loanProxy)
        internal
        returns (address loanVaultImpl, address beacon, address beaconController, address factory)
    {
        // 1. Deploy LoanVault implementation
        loanVaultImpl = address(new LoanVault());
        console2.log("LoanVault implementation deployed at:", loanVaultImpl);

        // 2. Deploy UpgradeableBeacon (owned by this script temporarily)
        beacon = address(new UpgradeableBeacon(loanVaultImpl, msg.sender));
        console2.log("UpgradeableBeacon deployed at:", beacon);

        // 3. Deploy BeaconController (AccessManaged wrapper)
        beaconController = address(new BeaconController(accessManager, beacon));
        console2.log("BeaconController deployed at:", beaconController);

        // 4. Transfer beacon ownership to BeaconController
        // CRITICAL: After this, only the BeaconController (via AccessManager) can upgrade the beacon
        UpgradeableBeacon(beacon).transferOwnership(beaconController);
        console2.log("Beacon ownership transferred to BeaconController");

        // 5. Deploy LoanVaultFactory
        factory = address(new LoanVaultFactory(beacon, loanProxy));
        console2.log("LoanVaultFactory deployed at:", factory);
    }

    // ============ Upgrader Role Wiring ============

    /**
     * @notice Configures the UPGRADER role across all upgradeable contracts
     * @dev Wires `upgradeToAndCall(address,bytes)` to the UPGRADER role on all 5 UUPS proxies,
     * and `IBeaconController.upgradeBeacon` on the BeaconController. Also sets up the
     * GUARDIAN_UPGRADER relationship for cancellation of pending upgrades.
     *
     * @param manager The BitmorAccessManager instance
     * @param loan Loan proxy address (UUPS)
     * @param btcVault BTCVault proxy address (UUPS)
     * @param usdcVault USDCVault proxy address (UUPS)
     * @param autoRepayment AutoRepayment proxy address (UUPS)
     * @param addressesProvider BitmorAddressesProvider proxy address (UUPS)
     * @param _beaconController BeaconController address (AccessManaged, not UUPS)
     * @param upgraderGrantee Address to receive the UPGRADER role
     * @custom:access Must be called by an account with ADMIN role on the AccessManager
     */
    function _wireUpgraderRole(
        BitmorAccessManager manager,
        address loan,
        address btcVault,
        address usdcVault,
        address autoRepayment,
        address addressesProvider,
        address _beaconController,
        address upgraderGrantee
    ) internal {
        RolesData rolesData = new RolesData();

        // Get UPGRADER role ID
        (,,,, uint64 upgraderId,,,,,) = rolesData.UPGRADER();

        // upgradeToAndCall selector (UUPS standard)
        bytes4[] memory uupsSelectors = new bytes4[](1);
        uupsSelectors[0] = bytes4(keccak256("upgradeToAndCall(address,bytes)"));

        // Map upgradeToAndCall to UPGRADER on all 5 UUPS proxies
        manager.setTargetFunctionRole(loan, uupsSelectors, upgraderId);
        console2.log("Set UPGRADER on Loan proxy");

        manager.setTargetFunctionRole(btcVault, uupsSelectors, upgraderId);
        console2.log("Set UPGRADER on BTCVault proxy");

        manager.setTargetFunctionRole(usdcVault, uupsSelectors, upgraderId);
        console2.log("Set UPGRADER on USDCVault proxy");

        manager.setTargetFunctionRole(autoRepayment, uupsSelectors, upgraderId);
        console2.log("Set UPGRADER on AutoRepayment proxy");

        manager.setTargetFunctionRole(addressesProvider, uupsSelectors, upgraderId);
        console2.log("Set UPGRADER on BitmorAddressesProvider proxy");

        // Map upgradeBeacon to UPGRADER on BeaconController
        bytes4[] memory beaconSelectors = new bytes4[](1);
        beaconSelectors[0] = IBeaconController.upgradeBeacon.selector;
        manager.setTargetFunctionRole(_beaconController, beaconSelectors, upgraderId);
        console2.log("Set UPGRADER on BeaconController");

        // Grant UPGRADER role with 2-day execution delay
        manager.grantRole(upgraderId, upgraderGrantee, uint32(2 days));
        console2.log("Granted UPGRADER role to:", upgraderGrantee);

        // Set up GUARDIAN_UPGRADER
        (, uint64 guardianId,) = rolesData.GUARDIAN_UPGRADER();
        manager.setRoleGuardian(upgraderId, guardianId);
        manager.grantRole(guardianId, upgraderGrantee, 0);
        console2.log("Set GUARDIAN_UPGRADER (id:", guardianId, ") on UPGRADER role");
    }

    // ============ Operational Roles ============

    /**
     * @notice Grants all operational roles and sets target function mappings for the protocol
     * @dev Extracted from the original DeployPhase3._grantLocalOperationalRoles() logic.
     * Handles three categories of role grants:
     * 1. Target function role mappings (which functions each role can call)
     * 2. Role grants to external grantees with appropriate delays
     * 3. Contract-to-contract grants (e.g., BVD to Loan, LPCM to bitmorPool)
     *
     * @param manager The BitmorAccessManager instance
     * @param g The RoleGrantees struct with all grantee addresses
     * @param loan Loan proxy address
     * @param btcVault BTCVault proxy address
     * @param usdcVault USDCVault proxy address
     * @param autoRepayment AutoRepayment proxy address
     * @param addressesProvider BitmorAddressesProvider proxy address
     * @param bitmorPool The Bitmor lending pool address (receives LPCM and UVA roles)
     * @custom:access Must be called by an account with ADMIN role on the AccessManager
     */
    function _grantOperationalRoles(
        BitmorAccessManager manager,
        RoleGrantees memory g,
        address loan,
        address btcVault,
        address usdcVault,
        address autoRepayment,
        address addressesProvider,
        address bitmorPool
    ) internal {
        RolesData rolesData = new RolesData();
        uint32 delay = uint32(DeploymentConstants.EXECUTION_DELAY);

        // Split into sub-functions to avoid stack-too-deep
        _grantLoanRoles(manager, rolesData, g, loan, bitmorPool, delay);
        _grantBTCVaultRoles(manager, rolesData, g, btcVault, loan, delay);
        _grantUSDCVaultRoles(manager, rolesData, g, usdcVault, bitmorPool, delay);
        _grantAutoRepaymentRoles(manager, rolesData, g, autoRepayment);
        _grantAddressesProviderRoles(manager, rolesData, addressesProvider);
    }

    function _grantLoanRoles(
        BitmorAccessManager manager,
        RolesData rolesData,
        RoleGrantees memory g,
        address loan,
        address bitmorPool,
        uint32 delay
    ) private {
        (,,,, uint64 executorId,,,,,) = rolesData.EXECUTOR();
        (,,,, uint64 lpcmId,,,,,) = rolesData.LPCM();
        (,,,, uint64 lpmFastId,,,,,) = rolesData.LPM_FAST();
        (,,,, uint64 lpmSlowId,,,,,) = rolesData.LPM_SLOW();

        manager.setTargetFunctionRole(loan, rolesData.getEXECUTOR_SELECTORS(), executorId);
        manager.setTargetFunctionRole(loan, rolesData.getLPCM_SELECTORS(), lpcmId);
        manager.setTargetFunctionRole(loan, rolesData.getLPM_FAST_SELECTORS(), lpmFastId);
        manager.setTargetFunctionRole(loan, rolesData.getLPM_SLOW_SELECTORS(), lpmSlowId);

        manager.grantRole(executorId, g.executor, 0);
        manager.grantRole(lpmFastId, g.lpmFast, 0);
        manager.grantRole(lpcmId, bitmorPool, 0);
        manager.grantRole(lpmSlowId, g.lpmSlow, delay);
        console2.log("Configured Loan roles");
    }

    function _grantBTCVaultRoles(
        BitmorAccessManager manager,
        RolesData rolesData,
        RoleGrantees memory g,
        address btcVault,
        address loan,
        uint32 delay
    ) private {
        (,,,, uint64 bvmFastId,,,,,) = rolesData.BVM_FAST();
        (,,,, uint64 bvmSlowId,,,,,) = rolesData.BVM_SLOW();
        (,,,, uint64 bvcId,,,,,) = rolesData.BVC();
        (,,,, uint64 bvaFastId,,,,,) = rolesData.BVA_FAST();
        (,,,, uint64 bvaSlowId,,,,,) = rolesData.BVA_SLOW();
        (,,,, uint64 bvdId,,,,,) = rolesData.BVD();

        manager.setTargetFunctionRole(btcVault, rolesData.getBVM_FAST_SELECTORS(), bvmFastId);
        manager.setTargetFunctionRole(btcVault, rolesData.getBVM_SLOW_SELECTORS(), bvmSlowId);
        manager.setTargetFunctionRole(btcVault, rolesData.getBVC_SELECTORS(), bvcId);
        manager.setTargetFunctionRole(btcVault, rolesData.getBVA_FAST_SELECTORS(), bvaFastId);
        manager.setTargetFunctionRole(btcVault, rolesData.getBVA_SLOW_SELECTORS(), bvaSlowId);
        manager.setTargetFunctionRole(btcVault, rolesData.getBVD_SELECTORS(), bvdId);

        manager.grantRole(bvmFastId, g.bvmFast, 0);
        manager.grantRole(bvaFastId, g.bvaFast, 0);
        manager.grantRole(bvmSlowId, g.bvmSlow, delay);
        manager.grantRole(bvcId, g.bvc, delay);
        manager.grantRole(bvaSlowId, g.bvaSlow, delay);
        manager.grantRole(bvdId, loan, 0);
        console2.log("Configured BTCVault roles");
    }

    function _grantUSDCVaultRoles(
        BitmorAccessManager manager,
        RolesData rolesData,
        RoleGrantees memory g,
        address usdcVault,
        address bitmorPool,
        uint32 delay
    ) private {
        (,,,, uint64 uvmFastId,,,,,) = rolesData.UVM_FAST();
        (,,,, uint64 uvmSlowId,,,,,) = rolesData.UVM_SLOW();
        (,,,, uint64 uvcId,,,,,) = rolesData.UVC();
        (,,,, uint64 uvaId,,,,,) = rolesData.UVA();

        manager.setTargetFunctionRole(usdcVault, rolesData.getUVM_FAST_SELECTORS(), uvmFastId);
        manager.setTargetFunctionRole(usdcVault, rolesData.getUVM_SLOW_SELECTORS(), uvmSlowId);
        manager.setTargetFunctionRole(usdcVault, rolesData.getUVC_SELECTORS(), uvcId);
        manager.setTargetFunctionRole(usdcVault, rolesData.getUVA_SELECTORS(), uvaId);

        manager.grantRole(uvmFastId, g.uvmFast, 0);
        manager.grantRole(uvmSlowId, g.uvmSlow, delay);
        manager.grantRole(uvcId, g.uvc, delay);
        manager.grantRole(uvaId, bitmorPool, 0);
        console2.log("Configured USDCVault roles");
    }

    function _grantAutoRepaymentRoles(
        BitmorAccessManager manager,
        RolesData rolesData,
        RoleGrantees memory g,
        address autoRepayment
    ) private {
        (,,,, uint64 areId,,,,,) = rolesData.ARE();
        manager.setTargetFunctionRole(autoRepayment, rolesData.getARE_SELECTORS(), areId);
        manager.grantRole(areId, g.are, 0);
        console2.log("Configured AutoRepayment roles");
    }

    function _grantAddressesProviderRoles(BitmorAccessManager manager, RolesData rolesData, address addressesProvider)
        private
    {
        (,,,, uint64 lpmSlowId,,,,,) = rolesData.LPM_SLOW();
        bytes4[] memory bapSelectors = new bytes4[](5);
        bapSelectors[0] = IBitmorAddressesProvider.setVaultFactory.selector;
        bapSelectors[1] = IBitmorAddressesProvider.setAutoRepayer.selector;
        bapSelectors[2] = IBitmorAddressesProvider.setLiquidationFeeCollector.selector;
        bapSelectors[3] = IBitmorAddressesProvider.setSwapper.selector;
        bapSelectors[4] = IBitmorAddressesProvider.setPremiumCollector.selector;
        manager.setTargetFunctionRole(addressesProvider, bapSelectors, lpmSlowId);
        console2.log("Configured BitmorAddressesProvider roles");
    }

    // ============ Guardian Setup ============

    /**
     * @notice Sets up all guardian roles for delayed operations across the protocol
     * @dev Configures 7 guardian relationships:
     * - GUARDIAN_LPM_SLOW guards LPM_SLOW
     * - GUARDIAN_BVM_SLOW guards BVM_SLOW
     * - GUARDIAN_BVC guards BVC
     * - GUARDIAN_BVA_SLOW guards BVA_SLOW
     * - GUARDIAN_UVM_SLOW guards UVM_SLOW
     * - GUARDIAN_UVC guards UVC
     * - GUARDIAN_UPGRADER guards UPGRADER (handled separately in `_wireUpgraderRole`)
     *
     * @param manager The BitmorAccessManager instance
     * @param guardianGrantee Address to receive all guardian roles (typically admin multisig)
     * @custom:security Guardians can cancel pending delayed operations before execution
     */
    function _setupGuardians(BitmorAccessManager manager, address guardianGrantee) internal {
        RolesData rolesData = new RolesData();

        // Extract guarded role IDs
        (,,,, uint64 lpmSlowId,,,,,) = rolesData.LPM_SLOW();
        (,,,, uint64 bvmSlowId,,,,,) = rolesData.BVM_SLOW();
        (,,,, uint64 bvcId,,,,,) = rolesData.BVC();
        (,,,, uint64 bvaSlowId,,,,,) = rolesData.BVA_SLOW();
        (,,,, uint64 uvmSlowId,,,,,) = rolesData.UVM_SLOW();
        (,,,, uint64 uvcId,,,,,) = rolesData.UVC();

        // Extract guardian IDs
        (, uint64 gLpmSlowId,) = rolesData.GUARDIAN_LPM_SLOW();
        (, uint64 gBvmSlowId,) = rolesData.GUARDIAN_BVM_SLOW();
        (, uint64 gBvcId,) = rolesData.GUARDIAN_BVC();
        (, uint64 gBvaSlowId,) = rolesData.GUARDIAN_BVA_SLOW();
        (, uint64 gUvmSlowId,) = rolesData.GUARDIAN_UVM_SLOW();
        (, uint64 gUvcId,) = rolesData.GUARDIAN_UVC();

        // Wire each guardian
        _setupOneGuardian(manager, guardianGrantee, lpmSlowId, gLpmSlowId);
        _setupOneGuardian(manager, guardianGrantee, bvmSlowId, gBvmSlowId);
        _setupOneGuardian(manager, guardianGrantee, bvcId, gBvcId);
        _setupOneGuardian(manager, guardianGrantee, bvaSlowId, gBvaSlowId);
        _setupOneGuardian(manager, guardianGrantee, uvmSlowId, gUvmSlowId);
        _setupOneGuardian(manager, guardianGrantee, uvcId, gUvcId);

        console2.log("Set up 6 guardian roles for guardianGrantee:", guardianGrantee);
    }

    /**
     * @notice Wires a single guardian relationship
     * @dev Grants the guardian role to the grantee and sets it as guardian for the guarded role
     * @param manager The BitmorAccessManager instance
     * @param guardianGrantee Address to receive the guardian role
     * @param guardedRoleId The role ID being guarded (operations can be cancelled)
     * @param guardianRoleId The guardian role ID
     */
    function _setupOneGuardian(
        BitmorAccessManager manager,
        address guardianGrantee,
        uint64 guardedRoleId,
        uint64 guardianRoleId
    ) private {
        manager.grantRole(guardianRoleId, guardianGrantee, 0);
        manager.setRoleGuardian(guardedRoleId, guardianRoleId);
    }

    // ============ Preflight Checks ============

    /**
     * @notice Validates that the script is running on the expected chain
     * @dev Reverts if `block.chainid` does not match the expected chain ID
     * @param expectedChainId The expected chain ID (e.g., 31337 for local, 8453 for Base mainnet)
     */
    function _preflightPhase1(uint256 expectedChainId) internal view {
        require(block.chainid == expectedChainId, "DeploymentBase: wrong chain");
    }

    /**
     * @notice Validates Phase 1 deployment is complete and deployer has ADMIN role
     * @dev Checks:
     * 1. Chain ID matches expected
     * 2. AccessManager is deployed (has bytecode)
     * 3. Collateral asset (BTCVault) is deployed (has bytecode)
     * 4. Deployer has ADMIN role on the AccessManager
     *
     * @param expectedChainId The expected chain ID
     */
    function _preflightPhase3(uint256 expectedChainId) internal view {
        _preflightPhase1(expectedChainId);

        string memory json = vm.readFile("./deployments.json");
        string memory base = string.concat(".deployments.", vm.toString(expectedChainId), ".networkConfig.");

        address accessManager = vm.parseJsonAddress(json, string.concat(base, "accessManager"));
        require(accessManager != address(0), "DeploymentBase: accessManager is zero");
        require(accessManager.code.length > 0, "DeploymentBase: accessManager has no bytecode");

        address collateralAsset = vm.parseJsonAddress(json, string.concat(base, "collateralAsset"));
        require(collateralAsset != address(0), "DeploymentBase: collateralAsset is zero");
        require(collateralAsset.code.length > 0, "DeploymentBase: collateralAsset has no bytecode");

        // Check deployer has ADMIN role (role ID 0)
        (bool isMember,) = BitmorAccessManager(accessManager).hasRole(0, msg.sender);
        require(isMember, "DeploymentBase: deployer lacks ADMIN role");
    }

    /**
     * @notice Validates that the Bitmor lending pool is deployed
     * @dev Reads `../lending-pool/deployed-contracts.json` and checks the LendingPool address.
     * Uses "localhost" key for local chain (31337) and "base" for mainnet (8453).
     */
    function _preflightLendingPool() internal {
        string memory json = vm.readFile("../lending-pool/deployed-contracts.json");

        HelperConfig helperConfig = new HelperConfig();
        string memory networkKey = helperConfig.getLendingPoolNetworkKey();

        address lendingPool = vm.parseJsonAddress(json, string.concat(".LendingPool.", networkKey, ".address"));
        require(lendingPool != address(0), "DeploymentBase: LendingPool is zero");
        require(lendingPool.code.length > 0, "DeploymentBase: LendingPool has no bytecode");
    }

    // ============ Shared Address Loaders ============

    /// @notice Loads Phase 1 addresses from deployments.json for the current chain
    /// @dev Uses `block.chainid` to construct the JSON path dynamically — no hardcoded chain ID strings.
    /// Fields that don't exist for certain chains (e.g., oracles on mainnet) return address(0).
    /// @return addrs The populated Phase1Addresses struct
    function _loadPhase1Addresses() internal returns (Phase1Addresses memory addrs) {
        string memory json = vm.readFile("./deployments.json");
        string memory base = string.concat(".deployments.", vm.toString(block.chainid), ".networkConfig.");

        addrs.accessManager = vm.parseJsonAddress(json, string.concat(base, "accessManager"));
        addrs.cbBTC = vm.parseJsonAddress(json, string.concat(base, "cbBTC"));
        addrs.btcVault = vm.parseJsonAddress(json, string.concat(base, "collateralAsset"));
        addrs.btcVaultImpl = vm.parseJsonAddress(json, string.concat(base, "btcVaultImpl"));

        // debtAsset may not exist in Phase 1 on mainnet (USDC is a known constant)
        try vm.parseJsonAddress(json, string.concat(base, "debtAsset")) returns (address parsed) {
            addrs.debtAsset = parsed;
        } catch {}

        // These only exist on local/testnet (mock deployments)
        try vm.parseJsonAddress(json, string.concat(base, "btcOracle")) returns (address parsed) {
            addrs.btcOracle = parsed;
        } catch {}
        try vm.parseJsonAddress(json, string.concat(base, "usdcOracle")) returns (address parsed) {
            addrs.usdcOracle = parsed;
        } catch {}
        try vm.parseJsonAddress(json, string.concat(base, "aaveV3Pool")) returns (address parsed) {
            addrs.aaveV3Pool = parsed;
        } catch {}
        try vm.parseJsonAddress(json, string.concat(base, "aaveAddressesProvider")) returns (address parsed) {
            addrs.aaveAddressesProvider = parsed;
        } catch {}
        try vm.parseJsonAddress(json, string.concat(base, "loanLogicLib")) returns (address parsed) {
            addrs.loanLogicLib = parsed;
        } catch {}
        try vm.parseJsonAddress(json, string.concat(base, "repayLogicLib")) returns (address parsed) {
            addrs.repayLogicLib = parsed;
        } catch {}
        try vm.parseJsonAddress(json, string.concat(base, "closeLoanLogicLib")) returns (address parsed) {
            addrs.closeLoanLogicLib = parsed;
        } catch {}
        try vm.parseJsonAddress(json, string.concat(base, "flashLoanLogicLib")) returns (address parsed) {
            addrs.flashLoanLogicLib = parsed;
        } catch {}

        // On mainnet, Aave addresses come from HelperConfig constants, not deployments.json
        if (block.chainid == DeploymentConstants.BASE_MAINNET_CHAIN_ID) {
            HelperConfig helperConfig = new HelperConfig();
            addrs.aaveV3Pool = helperConfig.getAaveV3Pool();
            addrs.aaveAddressesProvider = helperConfig.getAaveAddressesProvider();
            addrs.debtAsset = helperConfig.getUSDC();
        }

        console2.log("Loaded Phase 1: AccessManager:", addrs.accessManager);
        console2.log("Loaded Phase 1: BTCVault:", addrs.btcVault);
    }

    /// @notice Loads lending pool addresses from deployed-contracts.json for the current chain
    /// @dev Uses `HelperConfig.getLendingPoolNetworkKey()` for the JSON network key.
    /// @return addrs The populated LendingPoolAddresses struct
    function _loadLendingPoolAddresses() internal returns (LendingPoolAddresses memory addrs) {
        HelperConfig helperConfig = new HelperConfig();
        string memory networkKey = helperConfig.getLendingPoolNetworkKey();
        string memory json = vm.readFile("../lending-pool/deployed-contracts.json");

        addrs.bitmorPool = vm.parseJsonAddress(json, string.concat(".LendingPool.", networkKey, ".address"));
        addrs.aaveOracle = vm.parseJsonAddress(json, string.concat(".AaveOracle.", networkKey, ".address"));
        addrs.lendingPoolAddressesProvider =
            vm.parseJsonAddress(json, string.concat(".LendingPoolAddressesProvider.", networkKey, ".address"));

        console2.log("Loaded LendingPool:", addrs.bitmorPool);
        console2.log("Loaded AaveOracle:", addrs.aaveOracle);
        console2.log("Loaded LendingPoolAddressesProvider:", addrs.lendingPoolAddressesProvider);
    }

    // ============ JSON Persistence ============

    /**
     * @notice Merges deployment data into `deployments.json`
     * @dev Writes a JSON structure of the form:
     * `{"deployments":{"<chainId>":{"network":"<name>","networkConfig":{<keys>}}}}`
     *
     * For MVP, the caller passes all serialized keys for their deployment phase.
     * This function overwrites the existing file to avoid partial-merge complexity.
     *
     * @param keys Serialized JSON string of key-value pairs for `networkConfig` (e.g., `"accessManager":"0x..."`)
     * @param chainId The chain ID to store under
     * @param networkName Human-readable network name (e.g., "localhost", "base-mainnet")
     */
    function _mergeAndSave(string memory keys, uint256 chainId, string memory networkName) internal {
        string memory fullJson = string.concat(
            '{"deployments":{"',
            vm.toString(chainId),
            '":{"network":"',
            networkName,
            '","networkConfig":{',
            keys,
            "}}}}"
        );

        vm.writeFile("./deployments.json", fullJson);
        console2.log("Saved deployments to deployments.json for chain:", chainId);
    }

    /**
     * @notice Writes a deployment manifest file for audit trail and reproducibility
     * @dev Creates a JSON file at `./deployments/<chainId>-<timestamp>-<phase>.manifest.json`
     * containing deployment metadata: chain ID, block timestamp, phase name, git commit hash,
     * and deployer address. The directory is created if it does not exist.
     *
     * @param phase Human-readable phase name (e.g., "phase1", "phase3")
     */
    function _writeManifest(string memory phase) internal {
        // Ensure deployments directory exists
        vm.createDir("./deployments", true);

        // Get git commit hash via FFI
        string[] memory gitCmd = new string[](3);
        gitCmd[0] = "git";
        gitCmd[1] = "rev-parse";
        gitCmd[2] = "HEAD";
        bytes memory commitBytes = vm.ffi(gitCmd);
        string memory commitHash = string(commitBytes);

        // Build manifest path
        string memory manifestPath = string.concat(
            "./deployments/",
            vm.toString(block.chainid),
            "-",
            vm.toString(block.timestamp),
            "-",
            phase,
            ".manifest.json"
        );

        // Build manifest JSON
        string memory manifest = string.concat(
            '{"chainId":',
            vm.toString(block.chainid),
            ',"timestamp":',
            vm.toString(block.timestamp),
            ',"phase":"',
            phase,
            '","commitHash":"',
            commitHash,
            '","deployer":"',
            vm.toString(msg.sender),
            '"}'
        );

        vm.writeFile(manifestPath, manifest);
        console2.log("Written manifest to:", manifestPath);
    }
}
