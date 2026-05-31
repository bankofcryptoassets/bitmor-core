// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script, console2} from "forge-std/Script.sol";
import {InitialSetup} from "../interaction/AccessManager/InitialSetup.s.sol";
import {StrategyConfig} from "../StrategyConfig.s.sol";
import {HelperConfig} from "../HelperConfig.s.sol";
import {RolesData} from "@bitmor-config/RolesData.sol";
import {BitmorAccessManager} from "@bitmor/accessManager/BitmorAccessManager.sol";
import {USDCVault} from "@usdcVault/USDCVault.sol";
import {MockUniswapV4SwapAdapter} from "../../test/mock/MockUniswapV4SwapAdapter.sol";
import {LoanVault} from "@bitmor/protocol/LoanVault.sol";
import {Loan} from "@bitmor/protocol/Loan.sol";
import {LoanVaultFactory} from "@bitmor/protocol/LoanVaultFactory.sol";
import {AaveTokenizedStrategy} from "@btcVault/TokenizedStrategy/AaveTokenizedStrategy.sol";
import {USDCStrategy} from "@usdcVault/USDCStrategy.sol";
import {ILoan} from "@bitmor/interfaces/ILoan.sol";
import {BitmorAddressesProvider} from "@bitmor/protocol/BitmorAddressesProvider.sol";
import {IBitmorAddressesProvider} from "@bitmor/interfaces/IBitmorAddressesProvider.sol";
import {AutoRepayment} from "@bitmor/protocol/AutoRepayment.sol";
import {DeploymentConstants} from "./DeploymentConstants.sol";
import {MintableERC20} from "../../test/mock/MintableERC20.sol";
import {MockAToken} from "../../test/mock/MockAToken.sol";
import {MockAaveV3Pool} from "../../test/mock/MockAaveV3Pool.sol";

/// @title DeployPhase3
/// @author Bitmor Protocol
/// @notice Consolidated Phase 3 deployment for local development
/// @dev Deploys: USDCVault, SwapAdapter, Loan system, Strategies + AccessManager setup
/// @custom:security Only for local Anvil deployments (chainId 31337)
contract DeployPhase3 is InitialSetup {
    // ===== Constants =====

    uint256 constant PRE_CLOSURE_FEE = 10; // 0.1% in bps
    uint256 constant GRACE_PERIOD = 7 days;
    uint256 constant MAX_DURATION = 60; // 5 years in months
    uint256 constant LIQUIDATION_BUFFER = 50; // 0.5% in bps
    uint256 constant STRATEGY_CAP = type(uint256).max; // Max cap for local testing

    // ===== Phase 1 Addresses (from deployments.json) =====

    address public accessManager;
    address public mockUsdc;
    address public mockCbBTC;
    address public btcVault;
    address public btcOracle;

    // ===== Lending Pool Addresses (from deployed-contracts.json) =====

    address public bitmorPool;
    address public aaveOracle;
    address public lendingPoolAddressesProvider;

    // ===== Oracles (from deployments.json Phase 1) =====

    address public usdcOracle;

    // ===== Aave V3 Mock (from deployments.json Phase 1) =====

    address public aaveV3Pool;
    address public aaveAddressesProvider;

    // ===== Phase 3 Deployed Addresses =====

    address public usdcVault;
    address public mockSwapAdapter;
    address public loanVaultImpl;
    address public loan;
    address public loanVaultFactory;
    address public aaveStrategy;
    address public usdcStrategy;
    address public bitmorAddressesProvider;
    address public autoRepayment;

    /// @notice Main entry point for Phase 3 deployment
    /// @dev Deploys all Phase 3 contracts, configures AccessManager, and saves addresses
    function run() public override {
        require(block.chainid == DeploymentConstants.LOCAL_CHAIN_ID, "DeployPhase3: only for local");

        console2.log("=== Phase 3: Local Deployment ===");

        _loadPhase1Addresses();
        _loadLendingPoolAddresses();

        vm.startBroadcast();

        // 1. USDCVault
        usdcVault = address(new USDCVault(accessManager, mockUsdc, bitmorPool));
        console2.log("USDCVault:", usdcVault);

        // 2. MockSwapAdapter
        mockSwapAdapter = address(new MockUniswapV4SwapAdapter(aaveOracle, mockCbBTC, mockUsdc));
        console2.log("MockSwapAdapter:", mockSwapAdapter);

        // Fund MockSwapAdapter with tokens for swaps
        MintableERC20(mockCbBTC).mint(mockSwapAdapter, 1000e8); // 1000 BTC
        MintableERC20(mockUsdc).mint(mockSwapAdapter, 100_000_000e6); // 100M USDC
        console2.log("Funded MockSwapAdapter with tokens");

        // Fund MockAaveV3Pool with USDC for flash loans
        MintableERC20(mockUsdc).mint(aaveV3Pool, 10_000_000e6); // 10M USDC
        console2.log("Funded MockAaveV3Pool with USDC for flash loans");

        // Configure AaveOracle for local deployment
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

        // 3. LoanVault implementation
        loanVaultImpl = address(new LoanVault());
        console2.log("LoanVault impl:", loanVaultImpl);

        // 4. Loan
        loan = address(
            new Loan(
                accessManager,
                aaveV3Pool, // MockAaveV3Pool from Phase 1
                aaveAddressesProvider, // MockAaveV3Pool (same address for local)
                bitmorPool, // bitmorPool
                aaveOracle,
                btcVault, // collateralAsset (bvBTC)
                mockUsdc, // debtAsset
                mockCbBTC, // btc
                PRE_CLOSURE_FEE,
                GRACE_PERIOD
            )
        );
        console2.log("Loan:", loan);

        // 5. LoanVaultFactory
        loanVaultFactory = address(new LoanVaultFactory(loanVaultImpl, loan));
        console2.log("LoanVaultFactory:", loanVaultFactory);

        // 5a. BitmorAddressesProvider
        bitmorAddressesProvider = address(new BitmorAddressesProvider(accessManager, loan));
        console2.log("BitmorAddressesProvider:", bitmorAddressesProvider);

        // 5d. AutoRepayment
        autoRepayment = address(new AutoRepayment(accessManager, loan, mockUsdc));
        console2.log("AutoRepayment:", autoRepayment);

        // 5b. Register Loan contract with LendingPoolAddressesProvider
        // Required for LendingPoolCollateralManager to query loan data during liquidation
        (bool okSetLoan,) = lendingPoolAddressesProvider.call(abi.encodeWithSignature("setBitmorLoan(address)", loan));
        require(okSetLoan, "Failed to setBitmorLoan");
        console2.log("Registered Loan with LendingPoolAddressesProvider");

        // 5c. Register USDCVault with LendingPoolAddressesProvider
        // Required for USDCReserveInterestRateStrategy.calculateInterestRates()
        (bool okSetUSDCVault,) =
            lendingPoolAddressesProvider.call(abi.encodeWithSignature("setUSDCVault(address)", usdcVault));
        require(okSetUSDCVault, "Failed to setUSDCVault");
        console2.log("Registered USDCVault with LendingPoolAddressesProvider");

        // 6. Strategies
        aaveStrategy = address(new AaveTokenizedStrategy(aaveV3Pool, btcVault));
        usdcStrategy = address(new USDCStrategy(usdcVault, aaveV3Pool, bitmorPool));
        console2.log("AaveStrategy:", aaveStrategy);
        console2.log("USDCStrategy:", usdcStrategy);

        // 6b. Initialize MockAaveV3Pool reserves for strategies
        // AaveTokenizedStrategy calls aaveV3Pool.getReserveAToken(cbBTC)
        // USDCStrategy calls aaveV3Pool.getReserveAToken(usdc) for its Aave allocation
        address aTokenCbBTC = address(new MockAToken("Aave Mock cbBTC", "amcbBTC", 8, mockCbBTC, aaveV3Pool));
        address aTokenUsdc = address(new MockAToken("Aave Mock USDC", "amUSDC", 6, mockUsdc, aaveV3Pool));
        MockAaveV3Pool(aaveV3Pool).initReserve(mockCbBTC, aTokenCbBTC);
        MockAaveV3Pool(aaveV3Pool).initReserve(mockUsdc, aTokenUsdc);
        // Fund pool with underlying for withdrawals
        MintableERC20(mockCbBTC).mint(aaveV3Pool, 1000e8);
        // Note: USDC already minted to aaveV3Pool on line 94 (10M for flash loans)
        console2.log("Initialized MockAaveV3Pool reserves: cbBTC aToken:", aTokenCbBTC, "USDC aToken:", aTokenUsdc);

        // 7. AccessManager setup (roles, grants, schedule)
        _setupAccessManagerRoles();

        vm.stopBroadcast();

        // 8. Save addresses (execution happens in separate script after time advance)
        _saveDeployments();

        console2.log("=== Phase 3a Deploy Complete ===");
        console2.log("Run SchedulePhase3.s.sol next to schedule operations.");
    }

    /// @notice Loads Phase 1 addresses from deployments.json
    function _loadPhase1Addresses() internal {
        string memory json = vm.readFile("./deployments.json");
        string memory base = ".deployments.31337.networkConfig.";

        accessManager = vm.parseJsonAddress(json, string.concat(base, "accessManager"));
        mockUsdc = vm.parseJsonAddress(json, string.concat(base, "debtAsset"));
        mockCbBTC = vm.parseJsonAddress(json, string.concat(base, "cbBTC"));
        btcVault = vm.parseJsonAddress(json, string.concat(base, "collateralAsset"));
        btcOracle = vm.parseJsonAddress(json, string.concat(base, "btcOracle"));
        usdcOracle = vm.parseJsonAddress(json, string.concat(base, "usdcOracle"));
        aaveV3Pool = vm.parseJsonAddress(json, string.concat(base, "aaveV3Pool"));
        aaveAddressesProvider = vm.parseJsonAddress(json, string.concat(base, "aaveAddressesProvider"));

        console2.log("Loaded Phase 1: AccessManager:", accessManager);
        console2.log("Loaded Phase 1: AaveV3Pool (mock):", aaveV3Pool);
    }

    /// @notice Loads lending pool addresses from deployed-contracts.json
    function _loadLendingPoolAddresses() internal {
        string memory json = vm.readFile("../lending-pool/deployed-contracts.json");

        bitmorPool = vm.parseJsonAddress(json, ".LendingPool.localhost.address");
        aaveOracle = vm.parseJsonAddress(json, ".AaveOracle.localhost.address");

        lendingPoolAddressesProvider = vm.parseJsonAddress(json, ".LendingPoolAddressesProvider.localhost.address");

        console2.log("Loaded LendingPool:", bitmorPool);
        console2.log("Loaded AaveOracle:", aaveOracle);
        console2.log("Loaded LendingPoolAddressesProvider:", lendingPoolAddressesProvider);
    }

    /// @notice Sets up AccessManager roles using simplified local setup
    /// @dev Skips _initialSetup() which has wrong target addresses; does direct setup instead
    /// @dev Scheduling moved to SchedulePhase3.s.sol to avoid Foundry simulation issues
    function _setupAccessManagerRoles() internal {
        // Initialize manager reference
        manager = BitmorAccessManager(accessManager);

        // For local deployment, we do a simplified setup:
        // 1. Set target function roles with actual deployed addresses
        // 2. Grant roles to deployer with execution delay
        // 3. Setup guardians
        // Note: Scheduling is done in separate script (SchedulePhase3.s.sol)
        // because Foundry simulates entire script before broadcasting,
        // so schedule() wouldn't see the role grants from this script.

        // Grant operational roles and set target function roles for actual deployed contracts
        _grantLocalOperationalRoles();

        // Setup simplified guardians for local
        _setupLocalGuardians();

        // NOTE: _scheduleLocalOperations() removed - now in SchedulePhase3.s.sol
    }

    /// @notice Grants operational roles to msg.sender for local deployment
    /// @dev Required so deployer can schedule operations on managed contracts
    function _grantLocalOperationalRoles() internal {
        address admin = msg.sender;
        RolesData rolesData = new RolesData();

        // Get role IDs
        (,,,, uint64 executorId,,,,,) = rolesData.EXECUTOR();
        (,,,, uint64 lpcmId,,,,,) = rolesData.LPCM();
        (,,,, uint64 lpmFastId,,,,,) = rolesData.LPM_FAST();
        (,,,, uint64 lpmSlowId,,,,,) = rolesData.LPM_SLOW();
        (,,,, uint64 bvcId,,,,,) = rolesData.BVC();
        (,,,, uint64 uvcId,,,,,) = rolesData.UVC();

        console2.log("Setting up roles - EXECUTOR:", executorId, "LPCM:", lpcmId);
        console2.log("Loan address:", loan);
        console2.log("BTCVault address:", btcVault);
        console2.log("USDCVault address:", usdcVault);

        // Loan selector mappings needed by integration tests + liquidation
        manager.setTargetFunctionRole(loan, rolesData.getEXECUTOR_SELECTORS(), executorId);
        console2.log("Set EXECUTOR selectors on Loan");
        manager.setTargetFunctionRole(loan, rolesData.getLPCM_SELECTORS(), lpcmId);
        console2.log("Set LPCM selectors on Loan");
        manager.setTargetFunctionRole(loan, rolesData.getLPM_FAST_SELECTORS(), lpmFastId);
        console2.log("Set LPM_FAST selectors on Loan");
        manager.setTargetFunctionRole(loan, rolesData.getLPM_SLOW_SELECTORS(), lpmSlowId);
        console2.log("Set LPM_SLOW selectors on Loan");

        // Existing vault mappings
        manager.setTargetFunctionRole(btcVault, rolesData.getBVC_SELECTORS(), bvcId);
        console2.log("Set BVC selectors on BTCVault");
        manager.setTargetFunctionRole(usdcVault, rolesData.getUVC_SELECTORS(), uvcId);
        console2.log("Set UVC selectors on USDCVault");

        // BitmorAddressesProvider: all setters controlled by LPM_SLOW
        bytes4[] memory bapSelectors = new bytes4[](5);
        bapSelectors[0] = IBitmorAddressesProvider.setVaultFactory.selector;
        bapSelectors[1] = IBitmorAddressesProvider.setSwapper.selector;
        bapSelectors[2] = IBitmorAddressesProvider.setPremiumCollector.selector;
        bapSelectors[3] = IBitmorAddressesProvider.setLiquidationFeeCollector.selector;
        bapSelectors[4] = IBitmorAddressesProvider.setAutoRepayer.selector;
        manager.setTargetFunctionRole(bitmorAddressesProvider, bapSelectors, lpmSlowId);
        console2.log("Set LPM_SLOW selectors on BitmorAddressesProvider");

        // BVD: Loan contract needs deposit/mint access to BTCVault
        (,,,, uint64 bvdId,,,,,) = rolesData.BVD();
        manager.setTargetFunctionRole(btcVault, rolesData.getBVD_SELECTORS(), bvdId);
        manager.grantRole(bvdId, loan, 0);
        console2.log("Granted BVD to Loan for BTCVault deposit access");

        // UVA: Bitmor Lending Pool calls reallocateAssets on USDCVault during borrow/repay
        (,,,, uint64 uvaId,,,,,) = rolesData.UVA();
        manager.setTargetFunctionRole(usdcVault, rolesData.getUVA_SELECTORS(), uvaId);
        manager.grantRole(uvaId, bitmorPool, 0);
        console2.log("Granted UVA to bitmorPool for USDCVault reallocateAssets");

        // Grants required for local integration tests
        manager.grantRole(executorId, admin, 0); // deployer can grant EXECUTOR in tests
        console2.log("Granted EXECUTOR to admin");
        manager.grantRole(lpmFastId, admin, 0); // deployer can pause immediately
        console2.log("Granted LPM_FAST to admin");
        manager.grantRole(lpcmId, bitmorPool, 0); // lending-pool can update loan state on liquidation
        console2.log("Granted LPCM to bitmorPool:", bitmorPool);

        // ARE: AutoRepayment executor role
        (,,,, uint64 areId,,,,,) = rolesData.ARE();
        manager.setTargetFunctionRole(autoRepayment, rolesData.getARE_SELECTORS(), areId);
        manager.grantRole(areId, admin, 0);
        console2.log("Set ARE selectors on AutoRepayment and granted to admin");

        // Existing delayed grants for timelocked ops
        uint32 delay = uint32(DeploymentConstants.EXECUTION_DELAY);
        manager.grantRole(lpmSlowId, admin, delay);
        console2.log("Granted LPM_SLOW to admin with delay:", delay);
        manager.grantRole(bvcId, admin, delay);
        console2.log("Granted BVC to admin with delay:", delay);
        manager.grantRole(uvcId, admin, delay);
        console2.log("Granted UVC to admin with delay:", delay);

        console2.log("Set target function roles and granted to deployer:", admin);
    }

    /// @notice Sets up guardian roles for local testing (simplified)
    /// @dev Grants all guardian roles to admin with 0 delay
    function _setupLocalGuardians() internal {
        address admin = msg.sender;
        RolesData rolesData = new RolesData();

        // Grant each guardian role to admin and set its guardian relationship
        {
            (, uint64 guardianId,) = rolesData.GUARDIAN_LPM_SLOW();
            (,,,, uint64 guardedId,,,,,) = rolesData.LPM_SLOW();
            manager.grantRole(guardianId, admin, 0);
            manager.setRoleGuardian(guardedId, guardianId);
        }
        {
            (, uint64 guardianId,) = rolesData.GUARDIAN_BVM_SLOW();
            (,,,, uint64 guardedId,,,,,) = rolesData.BVM_SLOW();
            manager.grantRole(guardianId, admin, 0);
            manager.setRoleGuardian(guardedId, guardianId);
        }
        {
            (, uint64 guardianId,) = rolesData.GUARDIAN_BVC();
            (,,,, uint64 guardedId,,,,,) = rolesData.BVC();
            manager.grantRole(guardianId, admin, 0);
            manager.setRoleGuardian(guardedId, guardianId);
        }
        {
            (, uint64 guardianId,) = rolesData.GUARDIAN_BVA_SLOW();
            (,,,, uint64 guardedId,,,,,) = rolesData.BVA_SLOW();
            manager.grantRole(guardianId, admin, 0);
            manager.setRoleGuardian(guardedId, guardianId);
        }
        {
            (, uint64 guardianId,) = rolesData.GUARDIAN_UVM_SLOW();
            (,,,, uint64 guardedId,,,,,) = rolesData.UVM_SLOW();
            manager.grantRole(guardianId, admin, 0);
            manager.setRoleGuardian(guardedId, guardianId);
        }
        {
            (, uint64 guardianId,) = rolesData.GUARDIAN_UVC();
            (,,,, uint64 guardedId,,,,,) = rolesData.UVC();
            manager.grantRole(guardianId, admin, 0);
            manager.setRoleGuardian(guardedId, guardianId);
        }
    }

    /// @notice Schedules all delayed operations for execution after timelock
    function _scheduleLocalOperations() internal {
        uint48 when = uint48(block.timestamp + DeploymentConstants.EXECUTION_DELAY);

        // LPM_SLOW Operations (Loan config)
        manager.schedule(loan, abi.encodeCall(ILoan.setBitmorAddressesProvider, (bitmorAddressesProvider)), when);
        manager.schedule(loan, abi.encodeCall(ILoan.setGracePeriod, (GRACE_PERIOD)), when);
        manager.schedule(loan, abi.encodeCall(ILoan.setPreClosureFee, (PRE_CLOSURE_FEE)), when);
        manager.schedule(loan, abi.encodeCall(ILoan.setMaxDuration, (MAX_DURATION)), when);

        // BitmorAddressesProvider Operations
        manager.schedule(
            bitmorAddressesProvider, abi.encodeCall(IBitmorAddressesProvider.setVaultFactory, (loanVaultFactory)), when
        );
        manager.schedule(
            bitmorAddressesProvider, abi.encodeCall(IBitmorAddressesProvider.setSwapper, (mockSwapAdapter)), when
        );
        manager.schedule(
            bitmorAddressesProvider, abi.encodeCall(IBitmorAddressesProvider.setPremiumCollector, (msg.sender)), when
        );
        manager.schedule(
            bitmorAddressesProvider, abi.encodeCall(IBitmorAddressesProvider.setAutoRepayer, (autoRepayment)), when
        );

        // BVC Operations (BTCVault strategy)
        manager.schedule(btcVault, abi.encodeWithSignature("setMaxStrategies(uint256)", 5), when);
        manager.schedule(
            btcVault, abi.encodeWithSignature("addStrategy(address,uint256)", aaveStrategy, STRATEGY_CAP), when
        );

        // UVC Operations (USDCVault strategy)
        manager.schedule(usdcVault, abi.encodeWithSignature("setStrategy(address)", usdcStrategy), when);

        console2.log("Operations scheduled for:", when);
    }

    /// @notice Saves all deployed addresses to deployments.json
    function _saveDeployments() internal {
        // Build JSON in chunks to avoid stack-too-deep from large string.concat
        string memory cfg = string.concat(
            '{"accessManager":"',
            vm.toString(accessManager),
            '","collateralAsset":"',
            vm.toString(btcVault),
            '","debtAsset":"',
            vm.toString(mockUsdc),
            '","cbBTC":"',
            vm.toString(mockCbBTC),
            '","btc":"',
            vm.toString(mockCbBTC),
            '"'
        );

        cfg = string.concat(
            cfg,
            ',"btcOracle":"',
            vm.toString(btcOracle),
            '","usdcOracle":"',
            vm.toString(usdcOracle),
            '","aaveV3Pool":"',
            vm.toString(aaveV3Pool),
            '","aaveAddressesProvider":"',
            vm.toString(aaveAddressesProvider),
            '","usdcVault":"',
            vm.toString(usdcVault),
            '"'
        );

        cfg = string.concat(
            cfg,
            ',"loan":"',
            vm.toString(loan),
            '","loanVaultFactory":"',
            vm.toString(loanVaultFactory),
            '","loanVaultImpl":"',
            vm.toString(loanVaultImpl),
            '","swapper":"',
            vm.toString(mockSwapAdapter),
            '","bitmorAddressesProvider":"',
            vm.toString(bitmorAddressesProvider),
            '","aaveStrategy":"',
            vm.toString(aaveStrategy),
            '","usdcStrategy":"',
            vm.toString(usdcStrategy),
            '","autoRepayment":"',
            vm.toString(autoRepayment),
            '"}'
        );

        string memory fullJson =
            string.concat('{"deployments":{"31337":{"network":"localhost","networkConfig":', cfg, "}}}");

        vm.writeFile("./deployments.json", fullJson);
        console2.log("Saved final addresses to deployments.json");
    }
}
