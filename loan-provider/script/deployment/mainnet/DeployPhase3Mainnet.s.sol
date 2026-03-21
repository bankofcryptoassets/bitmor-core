// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {console2} from "forge-std/Script.sol";
import {MainnetRolesConfig} from "@bitmor-config/MainnetRolesConfig.sol";
import {DeploymentConstants} from "../DeploymentConstants.sol";
import {BitmorAccessManager} from "@bitmor/accessManager/BitmorAccessManager.sol";
import {USDCVault} from "@usdcVault/USDCVault.sol";
import {Loan} from "@bitmor/protocol/Loan.sol";
import {BitmorAddressesProvider} from "@bitmor/protocol/BitmorAddressesProvider.sol";
import {AutoRepayment} from "@bitmor/protocol/AutoRepayment.sol";
import {AaveTokenizedStrategy} from "@btcVault/TokenizedStrategy/AaveTokenizedStrategy.sol";
import {BTCVault} from "@btcVault/BTCVault.sol";
import {USDCStrategy} from "@usdcVault/USDCStrategy.sol";
import {ILoan} from "@bitmor/interfaces/ILoan.sol";
import {IBitmorAddressesProvider} from "@bitmor/interfaces/IBitmorAddressesProvider.sol";
import {DataTypes} from "@bitmor/libraries/types/DataTypes.sol";
import {Options} from "@openzeppelin-foundry-upgrades/Options.sol";
import {HelperConfig} from "../../HelperConfig.s.sol";

/**
 * @title DeployPhase3Mainnet
 * @author Bitmor Protocol
 * @notice Phase 3 mainnet deployment: USDCVault, Loan, BitmorAddressesProvider, AutoRepayment (all UUPS proxies),
 *         LoanVault beacon proxy, strategies, and AccessManager role wiring
 * @dev Deploys all Phase 3 contracts using real external protocol addresses from HelperConfig.
 *
 * Key differences from DeployPhase3Local:
 * - No mock deployments (no MockSwapAdapter, MockATokens, no mock token funding)
 * - Real Aave V3 Pool address (hardcoded constant in HelperConfig for mainnet)
 * - Real AaveOracle from lending-pool deployed-contracts.json (no mock oracle configuration)
 * - Real swap adapter address (TODO: set before deployment)
 * - Uses `_grantOperationalRoles()` with MainnetRolesConfig multisig-based grantees
 *
 * @custom:security For Base mainnet deployment (chainId 8453). Verify all addresses before broadcast.
 */
contract DeployPhase3Mainnet is MainnetRolesConfig {
    uint256 constant STRATEGY_CAP = type(uint96).max;

    // ============ Phase 1 Addresses (from deployments.json) ============

    /// @notice AccessManager deployed in Phase 1
    address public accessManager;

    /// @notice Real USDC token on Base mainnet
    address public usdc;

    /// @notice Real cbBTC token on Base mainnet
    address public cbBTC;

    /// @notice BTCVault proxy deployed in Phase 1
    address public btcVault;

    /// @notice BTCVault implementation address deployed in Phase 1
    address public btcVaultImpl;

    // ============ Lending Pool Addresses (from deployed-contracts.json) ============

    /// @notice Bitmor Lending Pool (Aave V2-based)
    address public bitmorPool;

    /// @notice AaveOracle used by the lending pool
    address public aaveOracle;

    /// @notice LendingPoolAddressesProvider for registering Loan and USDCVault
    address public lendingPoolAddressesProvider;

    // ============ External Protocol Addresses (from HelperConfig) ============

    /// @notice Aave V3 Pool (hardcoded constant for mainnet in HelperConfig)
    address public aaveV3Pool;

    /// @notice Aave V3 Addresses Provider (hardcoded constant for mainnet in HelperConfig)
    address public aaveAddressesProvider;

    // ============ Phase 3 Deployed Addresses ============

    /// @notice USDCVault proxy address
    address public usdcVault;

    /// @notice USDCVault implementation address
    address public usdcVaultImpl;

    /// @notice Swap adapter address
    address public swapAdapter;

    /// @notice Loan proxy address
    address public loan;

    /// @notice Loan implementation address
    address public loanImpl;

    /// @notice LoanVault implementation address
    address public loanVaultImpl;

    /// @notice UpgradeableBeacon for LoanVault proxies
    address public beacon;

    /// @notice BeaconController (AccessManaged wrapper for beacon upgrades)
    address public beaconController;

    /// @notice LoanVaultFactory address
    address public loanVaultFactory;

    /// @notice BitmorAddressesProvider proxy address
    address public bitmorAddressesProvider;

    /// @notice BitmorAddressesProvider implementation address
    address public bitmorAddressesProviderImpl;

    /// @notice AutoRepayment proxy address
    address public autoRepayment;

    /// @notice AutoRepayment implementation address
    address public autoRepaymentImpl;

    /// @notice AaveTokenizedStrategy address (non-proxied)
    address public aaveStrategy;

    /// @notice USDCStrategy address (non-proxied)
    address public usdcStrategy;

    // ============ Entry Point ============

    /**
     * @notice Main entry point for Phase 3 mainnet deployment
     * @dev Deploys all Phase 3 contracts as UUPS proxies (where applicable), configures
     *      AccessManager roles, and saves addresses to deployments.json.
     *
     * Deployment order:
     * 1. USDCVault (UUPS proxy)
     * 2. BitmorAddressesProvider (UUPS proxy) — deployed before Loan so address is available for InitParams
     * 3. Loan (UUPS proxy) — uses DataTypes.InitParams with all config in initializer
     * 4. LoanVault beacon proxy (impl + beacon + controller + factory)
     * 5. AutoRepayment (UUPS proxy)
     * 6. BAP post-init setters (setVaultFactory, setAutoRepayer) — before role wiring maps them to LPM_SLOW
     * 7. LendingPoolAddressesProvider registration
     * 8. Strategies (non-proxied)
     * 9. Wire strategies (pre-role-wiring, deployer holds ADMIN with 0 delay)
     * 10. AccessManager role wiring
     * 11. Address persistence
     */
    function run() external {
        _preflightPhase3(DeploymentConstants.BASE_MAINNET_CHAIN_ID);
        _preflightLendingPool();

        HelperConfig helperConfig = new HelperConfig();
        HelperConfig.ProtocolConfig memory pc = helperConfig.getProtocolConfig();

        // Mainnet address validation
        address swapAdapterAddr = helperConfig.getSwapAdapterAddress();
        address usdcAddr = helperConfig.getUSDC();
        require(swapAdapterAddr != address(0), "DeployPhase3Mainnet: set SWAP_ADAPTER_BASE_MAINNET in HelperConfig");
        require(usdcAddr != address(0), "DeployPhase3Mainnet: set USDC_BASE_MAINNET in HelperConfig");
        require(swapAdapterAddr.code.length > 0, "DeployPhase3Mainnet: swap adapter has no bytecode");
        require(usdcAddr.code.length > 0, "DeployPhase3Mainnet: USDC has no bytecode");

        console2.log("=== Phase 3: Mainnet Deployment (Upgradeable) ===");

        Phase1Addresses memory p1 = _loadPhase1Addresses();
        LendingPoolAddresses memory lp = _loadLendingPoolAddresses();

        // Assign to state variables
        accessManager = p1.accessManager;
        cbBTC = p1.cbBTC;
        btcVault = p1.btcVault;
        btcVaultImpl = p1.btcVaultImpl;
        aaveV3Pool = p1.aaveV3Pool;
        aaveAddressesProvider = p1.aaveAddressesProvider;
        bitmorPool = lp.bitmorPool;
        aaveOracle = lp.aaveOracle;
        lendingPoolAddressesProvider = lp.lendingPoolAddressesProvider;
        swapAdapter = swapAdapterAddr;
        usdc = usdcAddr;

        vm.startBroadcast();

        // 1. USDCVault (UUPS proxy)
        // Upgrades.deployUUPSProxy deploys the implementation internally — read its
        // address from the proxy's EIP-1967 slot rather than deploying a second copy.
        usdcVault =
            _deployUUPSProxy("USDCVault.sol", abi.encodeCall(USDCVault.initialize, (accessManager, usdc, bitmorPool)));
        usdcVaultImpl = _getProxyImplementation(usdcVault);
        console2.log("USDCVault proxy:", usdcVault);
        console2.log("USDCVault impl:", usdcVaultImpl);

        // 2. BitmorAddressesProvider (UUPS proxy) — deployed before Loan so its address
        // is available for Loan's InitParams.bitmorAddressesProvider field.
        // TODO: Replace msg.sender with actual premiumCollector and liquidationFeeCollector multisigs before deployment
        bitmorAddressesProvider = _deployUUPSProxy(
            "BitmorAddressesProvider.sol",
            abi.encodeCall(BitmorAddressesProvider.initialize, (accessManager, swapAdapter, msg.sender, msg.sender))
        );
        bitmorAddressesProviderImpl = _getProxyImplementation(bitmorAddressesProvider);
        console2.log("BitmorAddressesProvider proxy:", bitmorAddressesProvider);
        console2.log("BitmorAddressesProvider impl:", bitmorAddressesProviderImpl);

        // 3. Loan (UUPS proxy) — linked to LoanLogic library
        // unsafeAllow: "external-library-linking" is required because Loan.sol DELEGATECALLs
        // into LoanLogic (a public linked library). The plugin cannot verify library upgrade
        // safety automatically — we ensure it manually (LoanLogic is stateless, resolves
        // storage via bytes32 storageSlot passed from Loan.sol).
        Options memory loanOpts;
        loanOpts.unsafeAllow = "external-library-linking";
        DataTypes.InitParams memory loanInitParams = DataTypes.InitParams({
            manager: accessManager,
            aaveV3Pool: aaveV3Pool,
            aaveAddressesProvider: aaveAddressesProvider,
            bitmorPool: bitmorPool,
            oracle: aaveOracle,
            collateralAsset: btcVault, // bvBTC
            debtAsset: usdc, // USDC
            btc: cbBTC, // cbBTC
            bitmorAddressesProvider: bitmorAddressesProvider,
            maxBTCAmt: uint64(pc.maxBTCAmt),
            minBTCAmt: uint64(pc.minBTCAmt),
            gracePeriod: uint32(pc.gracePeriod),
            preClosureFeeBps: uint16(pc.preClosureFeeBps),
            liquidationFee: uint16(pc.liquidationFee),
            slippageSharesToAsset: uint16(pc.slippageSharesToAsset),
            slippageSwap: uint16(pc.slippageSwap),
            minDeposit: uint16(pc.minDepositBps),
            maxDuration: uint16(pc.maxDuration)
        });
        loan = _deployUUPSProxy("Loan.sol", abi.encodeCall(Loan.initialize, (loanInitParams)), loanOpts);
        loanImpl = _getProxyImplementation(loan);
        console2.log("Loan proxy:", loan);
        console2.log("Loan impl:", loanImpl);

        // 4. LoanVault beacon proxy (impl + beacon + controller + factory)
        (loanVaultImpl, beacon, beaconController, loanVaultFactory) = _deployBeaconProxy(accessManager, loan);
        console2.log("LoanVault impl:", loanVaultImpl);
        console2.log("Beacon:", beacon);
        console2.log("BeaconController:", beaconController);
        console2.log("LoanVaultFactory:", loanVaultFactory);

        // 5. AutoRepayment (UUPS proxy)
        autoRepayment = _deployUUPSProxy(
            "AutoRepayment.sol", abi.encodeCall(AutoRepayment.initialize, (accessManager, loan, usdc))
        );
        autoRepaymentImpl = _getProxyImplementation(autoRepayment);
        console2.log("AutoRepayment proxy:", autoRepayment);
        console2.log("AutoRepayment impl:", autoRepaymentImpl);

        // 6. BAP post-init setters — called before _setupAccessManagerRoles() maps
        // these functions to LPM_SLOW. Until role wiring, restricted functions default
        // to ADMIN_ROLE (0) which the deployer holds with 0 delay.
        BitmorAddressesProvider(bitmorAddressesProvider).setVaultFactory(loanVaultFactory);
        BitmorAddressesProvider(bitmorAddressesProvider).setAutoRepayer(autoRepayment);
        console2.log("BAP: setVaultFactory and setAutoRepayer configured");

        // 7a. Register Loan contract with LendingPoolAddressesProvider
        // Required for LendingPoolCollateralManager to query loan data during liquidation
        (bool okSetLoan,) = lendingPoolAddressesProvider.call(abi.encodeWithSignature("setBitmorLoan(address)", loan));
        require(okSetLoan, "Failed to setBitmorLoan");
        console2.log("Registered Loan with LendingPoolAddressesProvider");

        // 7b. Register USDCVault with LendingPoolAddressesProvider
        // Required for USDCReserveInterestRateStrategy.calculateInterestRates()
        (bool okSetUSDCVault,) =
            lendingPoolAddressesProvider.call(abi.encodeWithSignature("setUSDCVault(address)", usdcVault));
        require(okSetUSDCVault, "Failed to setUSDCVault");
        console2.log("Registered USDCVault with LendingPoolAddressesProvider");

        // 8. Strategies (non-proxied, deployed directly)
        aaveStrategy = address(new AaveTokenizedStrategy(aaveV3Pool, btcVault));
        usdcStrategy = address(new USDCStrategy(usdcVault, aaveV3Pool, bitmorPool));
        console2.log("AaveStrategy:", aaveStrategy);
        console2.log("USDCStrategy:", usdcStrategy);

        // 9. Wire strategies — called before _setupAccessManagerRoles() maps
        // these functions to BVC/UVC roles. Until role wiring, restricted functions
        // default to ADMIN_ROLE (0) which the deployer holds with 0 delay.
        BTCVault(btcVault).addStrategy(aaveStrategy, STRATEGY_CAP);
        console2.log("BTCVault strategy added (as ADMIN, pre-role-wiring)");
        USDCVault(usdcVault).setStrategy(usdcStrategy);
        console2.log("USDCVault strategy set (as ADMIN, pre-role-wiring)");

        // 10. AccessManager role wiring
        _setupAccessManagerRoles();

        vm.stopBroadcast();

        // 11. Save addresses
        _saveDeployments();

        // 12. Write deployment manifest
        _writeManifest("Phase3");

        console2.log("=== Phase 3 Deploy Complete ===");
    }

    // ============ Role Setup ============

    /**
     * @notice Sets up all AccessManager roles for the protocol
     * @dev Uses the shared role-wiring functions from DeploymentBase:
     * - `_grantOperationalRoles()` for target function mappings and role grants
     * - `_wireUpgraderRole()` for UUPS + beacon upgrade permissions
     * - `_setupGuardians()` for guardian-guarded delayed operations
     *
     * Role grantees come from MainnetRolesConfig._getRoleGrantees() which assigns
     * roles to different multisigs based on security level.
     *
     * @custom:security Strategy operations (addStrategy, setStrategy) are executed before role wiring
     * as the deployer holds ADMIN_ROLE with 0 delay. After role wiring, these functions are restricted
     * to BVC/UVC roles with production execution delays.
     */
    function _setupAccessManagerRoles() internal {
        BitmorAccessManager manager = BitmorAccessManager(accessManager);
        RoleGrantees memory g = _getRoleGrantees();

        // 10a. Grant operational roles and set target function mappings
        _grantOperationalRoles(
            manager, g, loan, btcVault, usdcVault, autoRepayment, bitmorAddressesProvider, bitmorPool
        );

        // 10b. Wire UPGRADER role across all UUPS proxies and BeaconController
        _wireUpgraderRole(
            manager, loan, btcVault, usdcVault, autoRepayment, bitmorAddressesProvider, beaconController, g.upgrader
        );

        // 10c. Set up guardian roles for delayed operations
        _setupGuardians(manager, g.admin);

        console2.log("AccessManager roles configured via DeploymentBase helpers");
    }

    // ============ Address Persistence ============

    /**
     * @notice Saves all deployed addresses to deployments.json using `_mergeAndSave()`
     * @dev Includes all proxy addresses, implementation addresses, beacon proxy addresses,
     * strategies, and external protocol addresses needed for HelperConfig resolution.
     */
    function _saveDeployments() internal {
        // Chunk 1: Phase 1 addresses (carried forward)
        string memory keys = string.concat(
            '"accessManager":"',
            vm.toString(accessManager),
            '",',
            '"collateralAsset":"',
            vm.toString(btcVault),
            '",',
            '"debtAsset":"',
            vm.toString(usdc),
            '",',
            '"cbBTC":"',
            vm.toString(cbBTC),
            '",',
            '"btc":"',
            vm.toString(cbBTC),
            '"'
        );

        // Chunk 2: Phase 3 proxy addresses
        keys = string.concat(
            keys,
            ',"usdcVault":"',
            vm.toString(usdcVault),
            '",',
            '"loan":"',
            vm.toString(loan),
            '",',
            '"bitmorAddressesProvider":"',
            vm.toString(bitmorAddressesProvider),
            '",',
            '"autoRepayment":"',
            vm.toString(autoRepayment),
            '"'
        );

        // Chunk 3: Implementation addresses (for upgrade tracking)
        keys = string.concat(
            keys,
            ',"btcVaultImpl":"',
            vm.toString(btcVaultImpl),
            '",',
            '"usdcVaultImpl":"',
            vm.toString(usdcVaultImpl),
            '",',
            '"loanImpl":"',
            vm.toString(loanImpl),
            '",',
            '"bitmorAddressesProviderImpl":"',
            vm.toString(bitmorAddressesProviderImpl),
            '",',
            '"autoRepaymentImpl":"',
            vm.toString(autoRepaymentImpl),
            '"'
        );

        // Chunk 4: Beacon proxy addresses
        keys = string.concat(
            keys,
            ',"loanVaultImpl":"',
            vm.toString(loanVaultImpl),
            '",',
            '"beacon":"',
            vm.toString(beacon),
            '",',
            '"beaconController":"',
            vm.toString(beaconController),
            '",',
            '"loanVaultFactory":"',
            vm.toString(loanVaultFactory),
            '"'
        );

        // Chunk 5: Strategies and swap adapter
        keys = string.concat(
            keys,
            ',"swapper":"',
            vm.toString(swapAdapter),
            '",',
            '"aaveStrategy":"',
            vm.toString(aaveStrategy),
            '",',
            '"usdcStrategy":"',
            vm.toString(usdcStrategy),
            '"'
        );

        // Chunk 6: Linked library addresses (carried forward from DeployLibraries)
        Phase1Addresses memory p1 = _loadPhase1Addresses();
        keys = string.concat(
            keys,
            ',"loanLogicLib":"',
            vm.toString(p1.loanLogicLib),
            '","repayLogicLib":"',
            vm.toString(p1.repayLogicLib),
            '","closeLoanLogicLib":"',
            vm.toString(p1.closeLoanLogicLib),
            '","flashLoanLogicLib":"',
            vm.toString(p1.flashLoanLogicLib),
            '"'
        );

        _mergeAndSave(keys, vm.toString(DeploymentConstants.BASE_MAINNET_CHAIN_ID), "base");
    }
}
