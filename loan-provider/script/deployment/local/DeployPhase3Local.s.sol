// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {console2} from "forge-std/Script.sol";
import {LocalRolesConfig} from "@bitmor-config/LocalRolesConfig.sol";
import {DeploymentConstants} from "../DeploymentConstants.sol";
import {BitmorAccessManager} from "@bitmor/accessManager/BitmorAccessManager.sol";
import {USDCVault} from "@usdcVault/USDCVault.sol";
import {Loan} from "@bitmor/protocol/Loan.sol";
import {BitmorAddressesProvider} from "@bitmor/protocol/BitmorAddressesProvider.sol";
import {AutoRepayment} from "@bitmor/protocol/AutoRepayment.sol";
import {AaveTokenizedStrategy} from "@btcVault/TokenizedStrategy/AaveTokenizedStrategy.sol";
import {USDCStrategy} from "@usdcVault/USDCStrategy.sol";
import {IBitmorAddressesProvider} from "@bitmor/interfaces/IBitmorAddressesProvider.sol";
import {Options} from "@openzeppelin-foundry-upgrades/Options.sol";
import {MockUniswapV4SwapAdapter} from "../../../test/mock/MockUniswapV4SwapAdapter.sol";
import {MintableERC20} from "../../../test/mock/MintableERC20.sol";
import {MockAToken} from "../../../test/mock/MockAToken.sol";
import {MockAaveV3Pool} from "../../../test/mock/MockAaveV3Pool.sol";

/**
 * @title DeployPhase3Local
 * @author Bitmor Protocol
 * @notice Phase 3 local deployment: USDCVault, Loan, BitmorAddressesProvider, AutoRepayment (all UUPS proxies),
 *         LoanVault beacon chain, strategies, mock infrastructure, and AccessManager role wiring
 * @dev Replaces the original DeployPhase3.s.sol for the upgradeable architecture.
 *
 * Key changes from the original:
 * - USDCVault, Loan, BitmorAddressesProvider, AutoRepayment deploy as UUPS proxies via `_deployUUPSProxy()`
 * - LoanVault uses beacon chain via `_deployBeaconChain()` (impl + beacon + controller + factory)
 * - Role setup uses `_grantOperationalRoles()`, `_wireUpgraderRole()`, and `_setupGuardians()` from DeploymentBase
 * - Address persistence uses `_mergeAndSave()` instead of manual JSON building
 * - Saves implementation addresses directly from deployed contracts
 *
 * @custom:security Only for local Anvil deployments (chainId 31337)
 */
contract DeployPhase3Local is LocalRolesConfig {
    // ============ Constants ============

    /// @notice Loan pre-closure fee in basis points (0.1%)
    uint256 constant PRE_CLOSURE_FEE = 10;

    /// @notice Grace period for monthly payments (7 days)
    uint256 constant GRACE_PERIOD = 7 days;

    /// @notice Maximum loan duration in months (5 years)
    uint256 constant MAX_DURATION = 60;

    /// @notice Liquidation buffer in basis points (0.5%)
    uint256 constant LIQUIDATION_BUFFER = 50;

    /// @notice Maximum strategy cap for local testing (unlimited)
    uint256 constant STRATEGY_CAP = type(uint256).max;

    // ============ Phase 1 Addresses (from deployments.json) ============

    /// @notice AccessManager deployed in Phase 1
    address public accessManager;

    /// @notice Mock USDC token deployed in Phase 1
    address public mockUsdc;

    /// @notice Mock cbBTC token deployed in Phase 1
    address public mockCbBTC;

    /// @notice BTCVault proxy deployed in Phase 1
    address public btcVault;

    /// @notice BTCVault implementation address deployed in Phase 1
    address public btcVaultImpl;

    /// @notice BTC/USD mock oracle deployed in Phase 1
    address public btcOracle;

    /// @notice USDC/USD mock oracle deployed in Phase 1
    address public usdcOracle;

    /// @notice Mock Aave V3 pool deployed in Phase 1
    address public aaveV3Pool;

    /// @notice Mock Aave V3 addresses provider deployed in Phase 1
    address public aaveAddressesProvider;

    // ============ Lending Pool Addresses (from deployed-contracts.json) ============

    /// @notice Bitmor Lending Pool (Aave V2-based)
    address public bitmorPool;

    /// @notice AaveOracle used by the lending pool
    address public aaveOracle;

    /// @notice LendingPoolAddressesProvider for registering Loan and USDCVault
    address public lendingPoolAddressesProvider;

    // ============ Phase 3 Deployed Addresses ============

    /// @notice USDCVault proxy address
    address public usdcVault;

    /// @notice USDCVault implementation address
    address public usdcVaultImpl;

    /// @notice MockSwapAdapter address
    address public mockSwapAdapter;

    /// @notice LoanLogic linked library address (deployed externally before this script)
    address public loanLogicLib;

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
     * @notice Main entry point for Phase 3 local deployment
     * @dev Deploys all Phase 3 contracts as UUPS proxies (where applicable), configures
     *      AccessManager roles, and saves addresses to deployments.json.
     *
     * Deployment order:
     * 1. USDCVault (UUPS proxy)
     * 2. MockSwapAdapter (direct deploy)
     * 3. Mock token funding
     * 4. AaveOracle configuration
     * 5. Loan (UUPS proxy)
     * 6. LoanVault beacon chain (impl + beacon + controller + factory)
     * 7. BitmorAddressesProvider (UUPS proxy)
     * 8. AutoRepayment (UUPS proxy)
     * 9. LendingPoolAddressesProvider registration
     * 10. Strategies (non-proxied)
     * 11. MockAaveV3Pool reserves
     * 12. AccessManager role wiring
     * 13. Address persistence
     */
    function run() external {
        _preflightPhase3(DeploymentConstants.LOCAL_CHAIN_ID);
        _preflightLendingPool();

        console2.log("=== Phase 3: Local Deployment (Upgradeable) ===");

        _loadPhase1Addresses();
        _loadLendingPoolAddresses();

        vm.startBroadcast();

        // 1. USDCVault (UUPS proxy)
        // Upgrades.deployUUPSProxy deploys the implementation internally — read its
        // address from the proxy's EIP-1967 slot rather than deploying a second copy.
        usdcVault = _deployUUPSProxy(
            "USDCVault.sol", abi.encodeCall(USDCVault.initialize, (accessManager, mockUsdc, bitmorPool))
        );
        usdcVaultImpl = _getProxyImplementation(usdcVault);
        console2.log("USDCVault proxy:", usdcVault);
        console2.log("USDCVault impl:", usdcVaultImpl);

        // 2. MockSwapAdapter
        mockSwapAdapter = address(new MockUniswapV4SwapAdapter(aaveOracle, mockCbBTC, mockUsdc));
        console2.log("MockSwapAdapter:", mockSwapAdapter);

        // 3. Fund MockSwapAdapter with tokens for swaps
        MintableERC20(mockCbBTC).mint(mockSwapAdapter, 1000e8); // 1000 BTC
        MintableERC20(mockUsdc).mint(mockSwapAdapter, 100_000_000e6); // 100M USDC
        console2.log("Funded MockSwapAdapter with tokens");

        // Fund MockAaveV3Pool with USDC for flash loans
        MintableERC20(mockUsdc).mint(aaveV3Pool, 10_000_000e6); // 10M USDC
        console2.log("Funded MockAaveV3Pool with USDC for flash loans");

        // 4. Configure AaveOracle for local deployment
        //
        // AaveOracle has a special bvBTC path: if asset == s_bvBTC, it computes
        //   price = _getAssetPrice(s_btc) * BTCVault.convertToAssets(1e8) / 1e8
        // But convertToAssets() calls totalAssets() which queries AaveTokenizedStrategy,
        // which calls getReserveAToken(cbBTC) on the external Aave mock.
        // For local testing, we disable the special path and use direct oracle sources.
        //
        // Fix: Clear s_bvBTC so the special path is never triggered, and instead
        // use direct assetsSources mapping for btcVault pricing.
        (bool okBtc,) = aaveOracle.call(abi.encodeWithSignature("setBTC(address)", mockCbBTC));
        require(okBtc, "Failed to setBTC");
        (bool okBvBtc,) = aaveOracle.call(abi.encodeWithSignature("setbvBTC(address)", address(0)));
        require(okBvBtc, "Failed to clear setbvBTC");
        console2.log("Cleared AaveOracle s_bvBTC (special path disabled for local)");

        // Set Chainlink price sources via direct assetsSources mapping
        //   - btcVault: direct BTC price (since special bvBTC path is disabled)
        //   - mockCbBTC: BTC price (for any direct cbBTC price lookups)
        //   - mockUsdc: USDC price (for Loan contract debt pricing)
        address[] memory assets = new address[](3);
        address[] memory sources = new address[](3);
        assets[0] = btcVault; // bvBTC priced directly via BTC oracle
        assets[1] = mockCbBTC; // Raw cbBTC
        assets[2] = mockUsdc; // USDC (debt asset)
        sources[0] = btcOracle; // BTC/USD Chainlink mock
        sources[1] = btcOracle; // BTC/USD Chainlink mock
        sources[2] = usdcOracle; // USDC/USD Chainlink mock
        (bool ok,) = aaveOracle.call(abi.encodeWithSignature("setAssetSources(address[],address[])", assets, sources));
        require(ok, "Failed to set oracle sources");
        console2.log("Configured AaveOracle price sources for bvBTC, cbBTC, and USDC");

        // 5. Loan (UUPS proxy) — linked to LoanLogic library
        // unsafeAllow: "external-library-linking" is required because Loan.sol DELEGATECALLs
        // into LoanLogic (a public linked library). The plugin cannot verify library upgrade
        // safety automatically — we ensure it manually (LoanLogic is stateless, resolves
        // storage via bytes32 storageSlot passed from Loan.sol).
        Options memory loanOpts;
        loanOpts.unsafeAllow = "external-library-linking";
        loan = _deployUUPSProxy(
            "Loan.sol",
            abi.encodeCall(
                Loan.initialize,
                (
                    accessManager,
                    aaveV3Pool, // MockAaveV3Pool from Phase 1
                    aaveAddressesProvider, // MockAaveV3Pool (same address for local)
                    bitmorPool,
                    aaveOracle,
                    btcVault, // collateralAsset (bvBTC)
                    mockUsdc, // debtAsset
                    mockCbBTC, // btc
                    PRE_CLOSURE_FEE,
                    GRACE_PERIOD
                )
            ),
            loanOpts
        );
        loanImpl = _getProxyImplementation(loan);
        console2.log("Loan proxy:", loan);
        console2.log("Loan impl:", loanImpl);

        // 6. LoanVault beacon chain (impl + beacon + controller + factory)
        (loanVaultImpl, beacon, beaconController, loanVaultFactory) = _deployBeaconChain(accessManager, loan);
        console2.log("LoanVault impl:", loanVaultImpl);
        console2.log("Beacon:", beacon);
        console2.log("BeaconController:", beaconController);
        console2.log("LoanVaultFactory:", loanVaultFactory);

        // 7. BitmorAddressesProvider (UUPS proxy)
        bitmorAddressesProvider = _deployUUPSProxy(
            "BitmorAddressesProvider.sol", abi.encodeCall(BitmorAddressesProvider.initialize, (accessManager, loan))
        );
        bitmorAddressesProviderImpl = _getProxyImplementation(bitmorAddressesProvider);
        console2.log("BitmorAddressesProvider proxy:", bitmorAddressesProvider);
        console2.log("BitmorAddressesProvider impl:", bitmorAddressesProviderImpl);

        // 8. AutoRepayment (UUPS proxy)
        autoRepayment = _deployUUPSProxy(
            "AutoRepayment.sol", abi.encodeCall(AutoRepayment.initialize, (accessManager, loan, mockUsdc))
        );
        autoRepaymentImpl = _getProxyImplementation(autoRepayment);
        console2.log("AutoRepayment proxy:", autoRepayment);
        console2.log("AutoRepayment impl:", autoRepaymentImpl);

        // 9a. Register Loan contract with LendingPoolAddressesProvider
        // Required for LendingPoolCollateralManager to query loan data during liquidation
        (bool okSetLoan,) = lendingPoolAddressesProvider.call(abi.encodeWithSignature("setBitmorLoan(address)", loan));
        require(okSetLoan, "Failed to setBitmorLoan");
        console2.log("Registered Loan with LendingPoolAddressesProvider");

        // 9b. Register USDCVault with LendingPoolAddressesProvider
        // Required for USDCReserveInterestRateStrategy.calculateInterestRates()
        (bool okSetUSDCVault,) =
            lendingPoolAddressesProvider.call(abi.encodeWithSignature("setUSDCVault(address)", usdcVault));
        require(okSetUSDCVault, "Failed to setUSDCVault");
        console2.log("Registered USDCVault with LendingPoolAddressesProvider");

        // 10. Strategies (non-proxied, deployed directly)
        aaveStrategy = address(new AaveTokenizedStrategy(aaveV3Pool, btcVault));
        usdcStrategy = address(new USDCStrategy(usdcVault, aaveV3Pool, bitmorPool));
        console2.log("AaveStrategy:", aaveStrategy);
        console2.log("USDCStrategy:", usdcStrategy);

        // 11. Initialize MockAaveV3Pool reserves for strategies
        // AaveTokenizedStrategy calls aaveV3Pool.getReserveAToken(cbBTC)
        // USDCStrategy calls aaveV3Pool.getReserveAToken(usdc) for its Aave allocation
        address aTokenCbBTC = address(new MockAToken("Aave Mock cbBTC", "amcbBTC", 8, mockCbBTC, aaveV3Pool));
        address aTokenUsdc = address(new MockAToken("Aave Mock USDC", "amUSDC", 6, mockUsdc, aaveV3Pool));
        MockAaveV3Pool(aaveV3Pool).initReserve(mockCbBTC, aTokenCbBTC);
        MockAaveV3Pool(aaveV3Pool).initReserve(mockUsdc, aTokenUsdc);
        // Fund pool with underlying for withdrawals
        MintableERC20(mockCbBTC).mint(aaveV3Pool, 1000e8);
        // Note: USDC already minted to aaveV3Pool above (10M for flash loans)
        console2.log("Initialized MockAaveV3Pool reserves: cbBTC aToken:", aTokenCbBTC, "USDC aToken:", aTokenUsdc);

        // 12. AccessManager role wiring
        _setupAccessManagerRoles();

        vm.stopBroadcast();

        // 13. Save addresses
        _saveDeployments();

        // 14. Write deployment manifest
        _writeManifest("Phase3");

        console2.log("=== Phase 3 Deploy Complete ===");
        console2.log("Run SchedulePhase3Local.s.sol next to schedule operations.");
    }

    // ============ Address Loading ============

    /// @notice Loads Phase 1 addresses from deployments.json
    /// @dev Reads the deployment file written by DeployPhase1Local
    function _loadPhase1Addresses() internal {
        string memory json = vm.readFile("./deployments.json");
        string memory base = ".deployments.31337.networkConfig.";

        accessManager = vm.parseJsonAddress(json, string.concat(base, "accessManager"));
        mockUsdc = vm.parseJsonAddress(json, string.concat(base, "debtAsset"));
        mockCbBTC = vm.parseJsonAddress(json, string.concat(base, "cbBTC"));
        btcVault = vm.parseJsonAddress(json, string.concat(base, "collateralAsset"));
        btcVaultImpl = vm.parseJsonAddress(json, string.concat(base, "btcVaultImpl"));
        btcOracle = vm.parseJsonAddress(json, string.concat(base, "btcOracle"));
        usdcOracle = vm.parseJsonAddress(json, string.concat(base, "usdcOracle"));
        aaveV3Pool = vm.parseJsonAddress(json, string.concat(base, "aaveV3Pool"));
        aaveAddressesProvider = vm.parseJsonAddress(json, string.concat(base, "aaveAddressesProvider"));
        loanLogicLib = vm.parseJsonAddress(json, string.concat(base, "loanLogicLib"));

        console2.log("Loaded Phase 1: AccessManager:", accessManager);
        console2.log("Loaded Phase 1: AaveV3Pool (mock):", aaveV3Pool);
        console2.log("Loaded LoanLogic (linked library):", loanLogicLib);
    }

    /// @notice Loads lending pool addresses from deployed-contracts.json
    /// @dev Reads the deployment file written by the lending-pool Hardhat deployment
    function _loadLendingPoolAddresses() internal {
        string memory json = vm.readFile("../lending-pool/deployed-contracts.json");

        bitmorPool = vm.parseJsonAddress(json, ".LendingPool.localhost.address");
        aaveOracle = vm.parseJsonAddress(json, ".AaveOracle.localhost.address");
        lendingPoolAddressesProvider = vm.parseJsonAddress(json, ".LendingPoolAddressesProvider.localhost.address");

        console2.log("Loaded LendingPool:", bitmorPool);
        console2.log("Loaded AaveOracle:", aaveOracle);
        console2.log("Loaded LendingPoolAddressesProvider:", lendingPoolAddressesProvider);
    }

    // ============ Role Setup ============

    /**
     * @notice Sets up all AccessManager roles for the protocol
     * @dev Uses the shared role-wiring functions from DeploymentBase:
     * - `_grantOperationalRoles()` for target function mappings and role grants
     * - `_wireUpgraderRole()` for UUPS + beacon upgrade permissions
     * - `_setupGuardians()` for guardian-guarded delayed operations
     *
     * Role grantees come from LocalRolesConfig._getRoleGrantees() which assigns
     * all roles to `msg.sender` for local testing convenience.
     *
     * @custom:security Scheduling of timelocked operations is deferred to SchedulePhase3Local
     * because Foundry simulates the entire script before broadcasting, so `schedule()` calls
     * would not see the role grants from this script.
     */
    function _setupAccessManagerRoles() internal {
        BitmorAccessManager manager = BitmorAccessManager(accessManager);
        RoleGrantees memory g = _getRoleGrantees();

        // 12a. Grant operational roles and set target function mappings
        _grantOperationalRoles(
            manager, g, loan, btcVault, usdcVault, autoRepayment, bitmorAddressesProvider, bitmorPool
        );

        // 12b. Wire UPGRADER role across all UUPS proxies and BeaconController
        _wireUpgraderRole(
            manager, loan, btcVault, usdcVault, autoRepayment, bitmorAddressesProvider, beaconController, g.upgrader
        );

        // 12c. Set up guardian roles for delayed operations
        _setupGuardians(manager, g.admin);

        console2.log("AccessManager roles configured via DeploymentBase helpers");
    }

    // ============ Address Persistence ============

    /**
     * @notice Saves all deployed addresses to deployments.json using `_mergeAndSave()`
     * @dev Includes all keys from the original DeployPhase3._saveDeployments() plus new keys:
     * - `loanImpl`, `usdcVaultImpl`, `autoRepaymentImpl`, `bitmorAddressesProviderImpl` (implementation addresses)
     * - `beacon`, `beaconController` (beacon chain addresses)
     *
     * Implementation addresses are stored directly from the deployed implementation contracts.
     */
    function _saveDeployments() internal {
        // Build JSON keys in chunks to avoid stack-too-deep
        // Chunk 1: Phase 1 addresses (carried forward)
        string memory keys = string.concat(
            '"accessManager":"',
            vm.toString(accessManager),
            '",',
            '"collateralAsset":"',
            vm.toString(btcVault),
            '",',
            '"debtAsset":"',
            vm.toString(mockUsdc),
            '",',
            '"cbBTC":"',
            vm.toString(mockCbBTC),
            '",',
            '"btc":"',
            vm.toString(mockCbBTC),
            '"'
        );

        // Chunk 2: Phase 1 oracles and Aave mocks
        keys = string.concat(
            keys,
            ',"btcOracle":"',
            vm.toString(btcOracle),
            '",',
            '"usdcOracle":"',
            vm.toString(usdcOracle),
            '",',
            '"aaveV3Pool":"',
            vm.toString(aaveV3Pool),
            '",',
            '"aaveAddressesProvider":"',
            vm.toString(aaveAddressesProvider),
            '"'
        );

        // Chunk 3: Phase 3 proxy addresses
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

        // Chunk 4: Implementation addresses and linked libraries
        keys = string.concat(
            keys,
            ',"loanLogicLib":"',
            vm.toString(loanLogicLib),
            '",',
            '"btcVaultImpl":"',
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

        // Chunk 5: Beacon chain addresses
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

        // Chunk 6: Strategies and remaining addresses
        keys = string.concat(
            keys,
            ',"swapper":"',
            vm.toString(mockSwapAdapter),
            '",',
            '"aaveStrategy":"',
            vm.toString(aaveStrategy),
            '",',
            '"usdcStrategy":"',
            vm.toString(usdcStrategy),
            '"'
        );

        _mergeAndSave(keys, DeploymentConstants.LOCAL_CHAIN_ID, "localhost");
    }
}
