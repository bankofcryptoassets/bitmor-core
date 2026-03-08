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
import {USDCStrategy} from "@usdcVault/USDCStrategy.sol";
import {IBitmorAddressesProvider} from "@bitmor/interfaces/IBitmorAddressesProvider.sol";
import {HelperConfig} from "../../HelperConfig.s.sol";

/**
 * @title DeployPhase3Mainnet
 * @author Bitmor Protocol
 * @notice Phase 3 mainnet deployment: USDCVault, Loan, BitmorAddressesProvider, AutoRepayment (all UUPS proxies),
 *         LoanVault beacon chain, strategies, and AccessManager role wiring
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
    // ============ Constants ============

    /// @notice Loan pre-closure fee in basis points (0.1%)
    uint256 constant PRE_CLOSURE_FEE = 10;

    /// @notice Grace period for monthly payments (7 days)
    uint256 constant GRACE_PERIOD = 7 days;

    /// @notice Maximum loan duration in months (5 years)
    uint256 constant MAX_DURATION = 60;

    /// @notice Liquidation buffer in basis points (0.5%)
    uint256 constant LIQUIDATION_BUFFER = 50;

    /// @notice Maximum strategy cap for mainnet
    /// @dev TODO: Set a realistic cap before mainnet deployment
    uint256 constant STRATEGY_CAP = type(uint256).max;

    /// @dev EIP-1967 implementation storage slot for reading proxy implementation address
    bytes32 internal constant IMPL_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    // ============ Mainnet External Addresses ============

    // TODO: Replace with actual Base mainnet swap adapter address before deployment
    address constant SWAP_ADAPTER_BASE_MAINNET = address(0);

    // TODO: Replace with actual Base mainnet USDC address before deployment
    address constant USDC_BASE_MAINNET = address(0);

    // ============ Phase 1 Addresses (from deployments.json) ============

    /// @notice AccessManager deployed in Phase 1
    address public accessManager;

    /// @notice Real USDC token on Base mainnet
    address public usdc;

    /// @notice Real cbBTC token on Base mainnet
    address public cbBTC;

    /// @notice BTCVault proxy deployed in Phase 1
    address public btcVault;

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

    /// @notice USDCVault implementation address (read from EIP-1967 slot)
    address public usdcVaultImpl;

    /// @notice Swap adapter address
    address public swapAdapter;

    /// @notice Loan proxy address
    address public loan;

    /// @notice Loan implementation address (read from EIP-1967 slot)
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

    /// @notice BitmorAddressesProvider implementation address (read from EIP-1967 slot)
    address public bitmorAddressesProviderImpl;

    /// @notice AutoRepayment proxy address
    address public autoRepayment;

    /// @notice AutoRepayment implementation address (read from EIP-1967 slot)
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
     * 2. Loan (UUPS proxy)
     * 3. LoanVault beacon chain (impl + beacon + controller + factory)
     * 4. BitmorAddressesProvider (UUPS proxy)
     * 5. AutoRepayment (UUPS proxy)
     * 6. LendingPoolAddressesProvider registration
     * 7. Strategies (non-proxied)
     * 8. AccessManager role wiring
     * 9. Address persistence
     */
    function run() external {
        _preflightPhase3(DeploymentConstants.BASE_MAINNET_CHAIN_ID);
        _preflightLendingPool();

        require(SWAP_ADAPTER_BASE_MAINNET != address(0), "DeployPhase3Mainnet: set SWAP_ADAPTER_BASE_MAINNET");
        require(USDC_BASE_MAINNET != address(0), "DeployPhase3Mainnet: set USDC_BASE_MAINNET");
        require(SWAP_ADAPTER_BASE_MAINNET.code.length > 0, "DeployPhase3Mainnet: swap adapter has no bytecode");
        require(USDC_BASE_MAINNET.code.length > 0, "DeployPhase3Mainnet: USDC has no bytecode");

        console2.log("=== Phase 3: Mainnet Deployment (Upgradeable) ===");

        _loadPhase1Addresses();
        _loadLendingPoolAddresses();
        _loadExternalProtocolAddresses();

        swapAdapter = SWAP_ADAPTER_BASE_MAINNET;
        usdc = USDC_BASE_MAINNET;

        vm.startBroadcast();

        // 1. USDCVault (UUPS proxy)
        usdcVault = _deployUUPSProxy(
            "src/vaults/usdc-vault/USDCVault.sol:USDCVault",
            abi.encodeCall(USDCVault.initialize, (accessManager, usdc, bitmorPool))
        );
        usdcVaultImpl = address(uint160(uint256(vm.load(usdcVault, IMPL_SLOT))));
        console2.log("USDCVault proxy:", usdcVault);
        console2.log("USDCVault impl:", usdcVaultImpl);

        // 2. Loan (UUPS proxy)
        loan = _deployUUPSProxy(
            "src/protocol/Loan.sol:Loan",
            abi.encodeCall(
                Loan.initialize,
                (
                    accessManager,
                    aaveV3Pool,
                    aaveAddressesProvider,
                    bitmorPool,
                    aaveOracle,
                    btcVault, // collateralAsset (bvBTC)
                    usdc, // debtAsset
                    cbBTC, // btc
                    PRE_CLOSURE_FEE,
                    GRACE_PERIOD
                )
            )
        );
        loanImpl = address(uint160(uint256(vm.load(loan, IMPL_SLOT))));
        console2.log("Loan proxy:", loan);
        console2.log("Loan impl:", loanImpl);

        // 3. LoanVault beacon chain (impl + beacon + controller + factory)
        (loanVaultImpl, beacon, beaconController, loanVaultFactory) = _deployBeaconChain(accessManager, loan);
        console2.log("LoanVault impl:", loanVaultImpl);
        console2.log("Beacon:", beacon);
        console2.log("BeaconController:", beaconController);
        console2.log("LoanVaultFactory:", loanVaultFactory);

        // 4. BitmorAddressesProvider (UUPS proxy)
        bitmorAddressesProvider = _deployUUPSProxy(
            "src/protocol/BitmorAddressesProvider.sol:BitmorAddressesProvider",
            abi.encodeCall(BitmorAddressesProvider.initialize, (accessManager, loan))
        );
        bitmorAddressesProviderImpl = address(uint160(uint256(vm.load(bitmorAddressesProvider, IMPL_SLOT))));
        console2.log("BitmorAddressesProvider proxy:", bitmorAddressesProvider);
        console2.log("BitmorAddressesProvider impl:", bitmorAddressesProviderImpl);

        // 5. AutoRepayment (UUPS proxy)
        autoRepayment = _deployUUPSProxy(
            "src/protocol/AutoRepayment.sol:AutoRepayment",
            abi.encodeCall(AutoRepayment.initialize, (accessManager, loan, usdc))
        );
        autoRepaymentImpl = address(uint160(uint256(vm.load(autoRepayment, IMPL_SLOT))));
        console2.log("AutoRepayment proxy:", autoRepayment);
        console2.log("AutoRepayment impl:", autoRepaymentImpl);

        // 6a. Register Loan contract with LendingPoolAddressesProvider
        // Required for LendingPoolCollateralManager to query loan data during liquidation
        (bool okSetLoan,) = lendingPoolAddressesProvider.call(abi.encodeWithSignature("setBitmorLoan(address)", loan));
        require(okSetLoan, "Failed to setBitmorLoan");
        console2.log("Registered Loan with LendingPoolAddressesProvider");

        // 6b. Register USDCVault with LendingPoolAddressesProvider
        // Required for USDCReserveInterestRateStrategy.calculateInterestRates()
        (bool okSetUSDCVault,) =
            lendingPoolAddressesProvider.call(abi.encodeWithSignature("setUSDCVault(address)", usdcVault));
        require(okSetUSDCVault, "Failed to setUSDCVault");
        console2.log("Registered USDCVault with LendingPoolAddressesProvider");

        // 7. Strategies (non-proxied, deployed directly)
        aaveStrategy = address(new AaveTokenizedStrategy(aaveV3Pool, btcVault));
        usdcStrategy = address(new USDCStrategy(usdcVault, aaveV3Pool, bitmorPool));
        console2.log("AaveStrategy:", aaveStrategy);
        console2.log("USDCStrategy:", usdcStrategy);

        // 8. AccessManager role wiring
        _setupAccessManagerRoles();

        vm.stopBroadcast();

        // 9. Save addresses
        _saveDeployments();

        // 10. Write deployment manifest
        _writeManifest("Phase3");

        console2.log("=== Phase 3 Deploy Complete ===");
        console2.log("Run SchedulePhase3Mainnet.s.sol next to schedule timelocked operations.");
    }

    // ============ Address Loading ============

    /// @notice Loads Phase 1 addresses from deployments.json
    /// @dev Reads the deployment file written by DeployPhase1Mainnet
    function _loadPhase1Addresses() internal {
        string memory json = vm.readFile("./deployments.json");
        string memory base = ".deployments.8453.networkConfig.";

        accessManager = vm.parseJsonAddress(json, string.concat(base, "accessManager"));
        cbBTC = vm.parseJsonAddress(json, string.concat(base, "cbBTC"));
        btcVault = vm.parseJsonAddress(json, string.concat(base, "collateralAsset"));

        require(accessManager != address(0), "DeployPhase3Mainnet: accessManager is zero");
        require(cbBTC != address(0), "DeployPhase3Mainnet: cbBTC is zero");
        require(btcVault != address(0), "DeployPhase3Mainnet: btcVault is zero");

        console2.log("Loaded Phase 1: AccessManager:", accessManager);
        console2.log("Loaded Phase 1: cbBTC:", cbBTC);
        console2.log("Loaded Phase 1: BTCVault:", btcVault);
    }

    /// @notice Loads lending pool addresses from deployed-contracts.json
    /// @dev Reads the deployment file written by the lending-pool Hardhat deployment.
    /// Uses "base" network key for mainnet.
    function _loadLendingPoolAddresses() internal {
        string memory json = vm.readFile("../lending-pool/deployed-contracts.json");

        bitmorPool = vm.parseJsonAddress(json, ".LendingPool.base.address");
        aaveOracle = vm.parseJsonAddress(json, ".AaveOracle.base.address");
        lendingPoolAddressesProvider = vm.parseJsonAddress(json, ".LendingPoolAddressesProvider.base.address");

        require(bitmorPool != address(0), "DeployPhase3Mainnet: LendingPool is zero");
        require(aaveOracle != address(0), "DeployPhase3Mainnet: AaveOracle is zero");
        require(lendingPoolAddressesProvider != address(0), "DeployPhase3Mainnet: LendingPoolAddressesProvider is zero");

        console2.log("Loaded LendingPool:", bitmorPool);
        console2.log("Loaded AaveOracle:", aaveOracle);
        console2.log("Loaded LendingPoolAddressesProvider:", lendingPoolAddressesProvider);
    }

    /// @notice Loads external protocol addresses using HelperConfig
    /// @dev For mainnet, HelperConfig returns hardcoded constants for Aave V3
    function _loadExternalProtocolAddresses() internal {
        HelperConfig config = new HelperConfig();
        aaveV3Pool = config.getAaveV3Pool();
        aaveAddressesProvider = config.getAaveAddressesProvider();

        require(aaveV3Pool != address(0), "DeployPhase3Mainnet: AaveV3Pool is zero");
        require(aaveAddressesProvider != address(0), "DeployPhase3Mainnet: AaveAddressesProvider is zero");

        console2.log("Loaded AaveV3Pool (mainnet constant):", aaveV3Pool);
        console2.log("Loaded AaveAddressesProvider (mainnet constant):", aaveAddressesProvider);
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
     * @custom:security Scheduling of timelocked operations is deferred to SchedulePhase3Mainnet
     * because Foundry simulates the entire script before broadcasting, so `schedule()` calls
     * would not see the role grants from this script.
     */
    function _setupAccessManagerRoles() internal {
        BitmorAccessManager manager = BitmorAccessManager(accessManager);
        RoleGrantees memory g = _getRoleGrantees();

        // 8a. Grant operational roles and set target function mappings
        _grantOperationalRoles(manager, g, loan, btcVault, usdcVault, autoRepayment, bitmorAddressesProvider, bitmorPool);

        // 8b. Wire UPGRADER role across all UUPS proxies and BeaconController
        _wireUpgraderRole(
            manager, loan, btcVault, usdcVault, autoRepayment, bitmorAddressesProvider, beaconController, g.upgrader
        );

        // 8c. Set up guardian roles for delayed operations
        _setupGuardians(manager, g.admin);

        console2.log("AccessManager roles configured via DeploymentBase helpers");
    }

    // ============ Address Persistence ============

    /**
     * @notice Saves all deployed addresses to deployments.json using `_mergeAndSave()`
     * @dev Includes all proxy addresses, implementation addresses, beacon chain addresses,
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
            vm.toString(address(uint160(uint256(vm.load(btcVault, IMPL_SLOT))))),
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

        // Chunk 4: Beacon chain addresses
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

        _mergeAndSave(keys, DeploymentConstants.BASE_MAINNET_CHAIN_ID, "base");
    }
}
