// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {console2} from "forge-std/Script.sol";
import {TestnetRolesConfig} from "@bitmor-config/TestnetRolesConfig.sol";
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
import {MockUniswapV4SwapAdapter} from "../../../test/mock/MockUniswapV4SwapAdapter.sol";
import {MintableERC20} from "../../../test/mock/MintableERC20.sol";
import {MockAToken} from "../../../test/mock/MockAToken.sol";
import {MockAaveV3Pool} from "../../../test/mock/MockAaveV3Pool.sol";

/**
 * @title DeployPhase3Testnet
 * @author Bitmor Protocol
 * @notice Phase 3 Base Sepolia testnet deployment: USDCVault, Loan, BitmorAddressesProvider, AutoRepayment
 *         (all UUPS proxies), LoanVault beacon proxy, strategies, mock infrastructure, and AccessManager role wiring
 * @dev Replaces the original DeployPhase3.s.sol for the upgradeable architecture.
 *
 * Key changes from the original:
 * - USDCVault, Loan, BitmorAddressesProvider, AutoRepayment deploy as UUPS proxies via `_deployUUPSProxy()`
 * - LoanVault uses beacon proxy via `_deployBeaconProxy()` (impl + beacon + controller + factory)
 * - Role setup uses `_grantOperationalRoles()`, `_wireUpgraderRole()`, and `_setupGuardians()` from DeploymentBase
 * - Address persistence uses `_mergeAndSave()` instead of manual JSON building
 * - Saves implementation addresses directly from deployed contracts
 *
 * @custom:security Only for Base Sepolia testnet deployments (chainId 84532)
 */
contract DeployPhase3Testnet is TestnetRolesConfig {
    uint256 constant STRATEGY_CAP = type(uint96).max;

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

    /// @notice RepayLogic linked library address (deployed externally before this script)
    address public repayLogicLib;

    /// @notice CloseLoanLogic linked library address (deployed externally before this script)
    address public closeLoanLogicLib;

    /// @notice FlashLoanLogic linked library address (deployed externally before this script)
    address public flashLoanLogicLib;

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
     * @notice Main entry point for Phase 3 Base Sepolia testnet deployment
     * @dev Deploys all Phase 3 contracts as UUPS proxies (where applicable), configures
     *      AccessManager roles, and saves addresses to deployments.json.
     *
     * Deployment order:
     * 1. USDCVault (UUPS proxy)
     * 2. MockSwapAdapter (direct deploy)
     * 3. Mock token funding
     * 4. AaveOracle configuration
     * 5. BitmorAddressesProvider (UUPS proxy) — deployed before Loan so address is available for InitParams
     * 6. Loan (UUPS proxy) — uses DataTypes.InitParams with all config in initializer
     * 7. LoanVault beacon proxy (impl + beacon + controller + factory)
     * 8. AutoRepayment (UUPS proxy)
     * 9. BAP post-init setters (setVaultFactory, setAutoRepayer) — before role wiring maps them to LPM_SLOW
     * 10. LendingPoolAddressesProvider registration
     * 11. Strategies (non-proxied)
     * 12. MockAaveV3Pool reserves
     * 13. Wire strategies (addStrategy/setStrategy) — before role wiring, deployer holds ADMIN_ROLE
     * 14. Reconfigure AaveOracle for real bvBTC pricing path
     * 15. AccessManager role wiring
     * 16. Address persistence
     */
    function run() external {
        _preflightPhase3(DeploymentConstants.BASE_SEPOLIA_CHAIN_ID);
        _preflightLendingPool();

        console2.log("=== Phase 3: Base Sepolia Testnet Deployment (Upgradeable) ===");

        HelperConfig helperConfig = new HelperConfig();
        HelperConfig.ProtocolConfig memory pc = helperConfig.getProtocolConfig();

        Phase1Addresses memory p1 = _loadPhase1Addresses();
        LendingPoolAddresses memory lp = _loadLendingPoolAddresses();

        // Assign to state variables for _saveDeployments() and _setupAccessManagerRoles()
        accessManager = p1.accessManager;
        mockUsdc = p1.debtAsset;
        mockCbBTC = p1.cbBTC;
        btcVault = p1.btcVault;
        btcVaultImpl = p1.btcVaultImpl;
        btcOracle = p1.btcOracle;
        usdcOracle = p1.usdcOracle;
        aaveV3Pool = p1.aaveV3Pool;
        aaveAddressesProvider = p1.aaveAddressesProvider;
        loanLogicLib = p1.loanLogicLib;
        repayLogicLib = p1.repayLogicLib;
        closeLoanLogicLib = p1.closeLoanLogicLib;
        flashLoanLogicLib = p1.flashLoanLogicLib;
        bitmorPool = lp.bitmorPool;
        aaveOracle = lp.aaveOracle;
        lendingPoolAddressesProvider = lp.lendingPoolAddressesProvider;

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

        // 4. Configure AaveOracle for testnet deployment
        //
        // AaveOracle has a special bvBTC path: if asset == s_bvBTC, it computes
        //   price = _getAssetPrice(s_btc) * BTCVault.convertToAssets(1e8) / 1e8
        // But convertToAssets() calls totalAssets() which queries AaveTokenizedStrategy,
        // which calls getReserveAToken(cbBTC) on the external Aave mock.
        // For testnet testing, we disable the special path and use direct oracle sources.
        //
        // Fix: Clear s_bvBTC so the special path is never triggered, and instead
        // use direct assetsSources mapping for btcVault pricing.
        (bool okBtc,) = aaveOracle.call(abi.encodeWithSignature("setBTC(address)", mockCbBTC));
        require(okBtc, "Failed to setBTC");
        (bool okBvBtc,) = aaveOracle.call(abi.encodeWithSignature("setbvBTC(address)", address(0)));
        require(okBvBtc, "Failed to clear setbvBTC");
        console2.log("Cleared AaveOracle s_bvBTC (special path disabled for testnet)");

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

        // 5. BitmorAddressesProvider (UUPS proxy) — deployed before Loan so its address
        // is available for Loan's InitParams.bitmorAddressesProvider field.
        bitmorAddressesProvider = _deployUUPSProxy(
            "BitmorAddressesProvider.sol",
            abi.encodeCall(BitmorAddressesProvider.initialize, (accessManager, mockSwapAdapter, msg.sender, msg.sender))
        );
        bitmorAddressesProviderImpl = _getProxyImplementation(bitmorAddressesProvider);
        console2.log("BitmorAddressesProvider proxy:", bitmorAddressesProvider);
        console2.log("BitmorAddressesProvider impl:", bitmorAddressesProviderImpl);

        // 6. Loan (UUPS proxy) — linked to LoanLogic library
        // unsafeAllow: "external-library-linking" is required because Loan.sol DELEGATECALLs
        // into LoanLogic (a public linked library). The plugin cannot verify library upgrade
        // safety automatically — we ensure it manually (LoanLogic is stateless, resolves
        // storage via bytes32 storageSlot passed from Loan.sol).
        Options memory loanOpts;
        loanOpts.unsafeAllow = "external-library-linking";
        DataTypes.InitParams memory loanInitParams = DataTypes.InitParams({
            manager: accessManager,
            aaveV3Pool: aaveV3Pool, // MockAaveV3Pool from Phase 1
            aaveAddressesProvider: aaveAddressesProvider, // MockAaveV3Pool (same address for testnet)
            bitmorPool: bitmorPool,
            oracle: aaveOracle,
            collateralAsset: btcVault, // bvBTC
            debtAsset: mockUsdc, // USDC
            btc: mockCbBTC, // cbBTC
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

        // 7. LoanVault beacon proxy (impl + beacon + controller + factory)
        (loanVaultImpl, beacon, beaconController, loanVaultFactory) = _deployBeaconProxy(accessManager, loan);
        console2.log("LoanVault impl:", loanVaultImpl);
        console2.log("Beacon:", beacon);
        console2.log("BeaconController:", beaconController);
        console2.log("LoanVaultFactory:", loanVaultFactory);

        // 8. AutoRepayment (UUPS proxy)
        autoRepayment = _deployUUPSProxy(
            "AutoRepayment.sol", abi.encodeCall(AutoRepayment.initialize, (accessManager, loan, mockUsdc))
        );
        autoRepaymentImpl = _getProxyImplementation(autoRepayment);
        console2.log("AutoRepayment proxy:", autoRepayment);
        console2.log("AutoRepayment impl:", autoRepaymentImpl);

        // 9. BAP post-init setters — called before _setupAccessManagerRoles() maps
        // these functions to LPM_SLOW. Until role wiring, restricted functions default
        // to ADMIN_ROLE (0) which the deployer holds with 0 delay.
        BitmorAddressesProvider(bitmorAddressesProvider).setVaultFactory(loanVaultFactory);
        BitmorAddressesProvider(bitmorAddressesProvider).setAutoRepayer(autoRepayment);
        console2.log("BAP: setVaultFactory and setAutoRepayer configured");

        // 10a. Register Loan contract with LendingPoolAddressesProvider
        // Required for LendingPoolCollateralManager to query loan data during liquidation
        (bool okSetLoan,) = lendingPoolAddressesProvider.call(abi.encodeWithSignature("setBitmorLoan(address)", loan));
        require(okSetLoan, "Failed to setBitmorLoan");
        console2.log("Registered Loan with LendingPoolAddressesProvider");

        // 10b. Register USDCVault with LendingPoolAddressesProvider
        // Required for USDCReserveInterestRateStrategy.calculateInterestRates()
        (bool okSetUSDCVault,) =
            lendingPoolAddressesProvider.call(abi.encodeWithSignature("setUSDCVault(address)", usdcVault));
        require(okSetUSDCVault, "Failed to setUSDCVault");
        console2.log("Registered USDCVault with LendingPoolAddressesProvider");

        // 11. Strategies (non-proxied, deployed directly)
        aaveStrategy = address(new AaveTokenizedStrategy(aaveV3Pool, btcVault));
        usdcStrategy = address(new USDCStrategy(usdcVault, aaveV3Pool, bitmorPool));
        console2.log("AaveStrategy:", aaveStrategy);
        console2.log("USDCStrategy:", usdcStrategy);

        // 12. Initialize MockAaveV3Pool reserves for strategies
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

        // 13. Wire strategies — called before _setupAccessManagerRoles() maps
        // these functions to BVC/UVC roles. Until role wiring, restricted functions
        // default to ADMIN_ROLE (0) which the deployer holds with 0 delay.
        BTCVault(btcVault).addStrategy(aaveStrategy, STRATEGY_CAP);
        console2.log("BTCVault strategy added (as ADMIN, pre-role-wiring)");
        USDCVault(usdcVault).setStrategy(usdcStrategy);
        console2.log("USDCVault strategy set (as ADMIN, pre-role-wiring)");

        // 14. Reconfigure AaveOracle for real bvBTC pricing path
        // Now that BTCVault has a strategy wired, convertToAssets() works correctly.
        // Enable the special bvBTC pricing: price = btcPrice * BTCVault.convertToAssets(1e8) / 1e8
        _reconfigureOracleForBvBTC();

        // 15. AccessManager role wiring
        _setupAccessManagerRoles();

        vm.stopBroadcast();

        // 16. Save addresses
        _saveDeployments();

        // 17. Write deployment manifest
        _writeManifest("Phase3");

        console2.log("=== Phase 3 Deploy Complete ===");
    }

    // ============ Oracle Reconfiguration ============

    /// @notice Reconfigures AaveOracle to use the real bvBTC pricing path
    /// @dev Called after addStrategy so BTCVault.convertToAssets() works correctly.
    ///      In step 4, the bvBTC path was disabled (setbvBTC(address(0))) because
    ///      the strategy wasn't wired yet. Now we enable it:
    ///      1. Set s_bvBTC = btcVault so getAssetPrice detects the bvBTC path
    ///      2. Set s_btc = mockCbBTC so btcPrice lookup works
    ///      3. Remove btcVault from direct assetsSources (no longer needs direct oracle)
    function _reconfigureOracleForBvBTC() internal {
        console2.log("Reconfiguring AaveOracle for real bvBTC pricing path...");

        // Enable the special bvBTC pricing path
        (bool okBvBtc,) = aaveOracle.call(abi.encodeWithSignature("setbvBTC(address)", btcVault));
        require(okBvBtc, "Failed to setbvBTC");
        console2.log("  setbvBTC:", btcVault);

        // Ensure s_btc is set
        (bool okBtc2,) = aaveOracle.call(abi.encodeWithSignature("setBTC(address)", mockCbBTC));
        require(okBtc2, "Failed to setBTC");
        console2.log("  setBTC:", mockCbBTC);

        // Update assetsSources: remove btcVault from direct pricing (it now uses convertToAssets path).
        // Keep mockCbBTC and mockUsdc with their direct oracle sources.
        address[] memory assets2 = new address[](2);
        address[] memory sources2 = new address[](2);
        assets2[0] = mockCbBTC;
        assets2[1] = mockUsdc;
        sources2[0] = btcOracle;
        sources2[1] = usdcOracle;
        (bool ok2,) =
            aaveOracle.call(abi.encodeWithSignature("setAssetSources(address[],address[])", assets2, sources2));
        require(ok2, "Failed to update oracle sources");
        console2.log("  Updated assetsSources (cbBTC, USDC direct; bvBTC via convertToAssets)");
        console2.log("AaveOracle bvBTC pricing path active.");
    }

    // ============ Role Setup ============

    /**
     * @notice Sets up all AccessManager roles for the protocol
     * @dev Uses the shared role-wiring functions from DeploymentBase:
     * - `_grantOperationalRoles()` for target function mappings and role grants
     * - `_wireUpgraderRole()` for UUPS + beacon upgrade permissions
     * - `_setupGuardians()` for guardian-guarded delayed operations
     *
     * Role grantees come from TestnetRolesConfig._getRoleGrantees() which assigns
     * all roles to `msg.sender` for testnet testing convenience.
     *
     * Strategy wiring (addStrategy/setStrategy) is done BEFORE this function is called,
     * while the deployer still holds ADMIN_ROLE (0) with 0 delay. Once role wiring maps
     * those functions to BVC/UVC roles, they require the proper role + delay.
     */
    function _setupAccessManagerRoles() internal {
        BitmorAccessManager manager = BitmorAccessManager(accessManager);
        RoleGrantees memory g = _getRoleGrantees();

        // 15a. Grant operational roles and set target function mappings
        _grantOperationalRoles(
            manager, g, loan, btcVault, usdcVault, autoRepayment, bitmorAddressesProvider, bitmorPool
        );

        // 15b. Wire UPGRADER role across all UUPS proxies and BeaconController
        _wireUpgraderRole(
            manager, loan, btcVault, usdcVault, autoRepayment, bitmorAddressesProvider, beaconController, g.upgrader
        );

        // 15c. Set up guardian roles for delayed operations
        _setupGuardians(manager, g.admin);

        console2.log("AccessManager roles configured via DeploymentBase helpers");
    }

    // ============ Address Persistence ============

    /**
     * @notice Saves all deployed addresses to deployments.json using `_mergeAndSave()`
     * @dev Includes all keys from the original DeployPhase3._saveDeployments() plus new keys:
     * - `loanImpl`, `usdcVaultImpl`, `autoRepaymentImpl`, `bitmorAddressesProviderImpl` (implementation addresses)
     * - `beacon`, `beaconController` (beacon proxy addresses)
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
            '","repayLogicLib":"',
            vm.toString(repayLogicLib),
            '","closeLoanLogicLib":"',
            vm.toString(closeLoanLogicLib),
            '","flashLoanLogicLib":"',
            vm.toString(flashLoanLogicLib),
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

        // Chunk 5: Beacon proxy addresses
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

        _mergeAndSave(keys, vm.toString(DeploymentConstants.BASE_SEPOLIA_CHAIN_ID), "base-sepolia");
    }
}
