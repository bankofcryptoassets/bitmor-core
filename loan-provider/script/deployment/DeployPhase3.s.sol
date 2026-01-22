// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script, console2} from "forge-std/Script.sol";
import {InitialSetup} from "../interaction/AccessManager/InitialSetup.s.sol";
import {StrategyConfig} from "../StrategyConfig.s.sol";
import {HelperConfig} from "../HelperConfig.s.sol";
import {RolesData} from "@bitmor/accessManager/RolesData.sol";
import {BitmorAccessManager} from "@bitmor/accessManager/BitmorAccessManager.sol";
import {USDCVault} from "@usdcVault/USDCVault.sol";
import {MockUniswapV4SwapAdapter} from "@bitmor/mocks/MockUniswapV4SwapAdapter.sol";
import {UniswapV4SwapAdapterWrapper} from "@bitmor/adapters/UniswapV4SwapAdapterWrapper.sol";
import {LoanVault} from "@bitmor/protocol/LoanVault.sol";
import {Loan} from "@bitmor/protocol/Loan.sol";
import {LoanVaultFactory} from "@bitmor/protocol/LoanVaultFactory.sol";
import {AaveTokenizedStrategy} from "@btcVault/TokenizedStrategy/AaveTokenizedStrategy.sol";
import {USDCStrategy} from "@usdcVault/USDCStrategy.sol";
import {ILoan} from "@bitmor/interfaces/ILoan.sol";
import {DeploymentConstants} from "./DeploymentConstants.sol";

/// @title DeployPhase3
/// @author Bitmor Protocol
/// @notice Consolidated Phase 3 deployment for local development
/// @dev Deploys: USDCVault, SwapAdapter, Loan system, Strategies + AccessManager setup
/// @custom:security Only for local Anvil deployments (chainId 31337)
contract DeployPhase3 is InitialSetup {
    // ===== Constants =====

    uint256 constant PRE_CLOSURE_FEE = 10; // 0.1% in bps
    uint256 constant GRACE_PERIOD = 7 days;
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

    // ===== Phase 3 Deployed Addresses =====

    address public usdcVault;
    address public mockSwapAdapter;
    address public swapAdapterWrapper;
    address public loanVaultImpl;
    address public loan;
    address public loanVaultFactory;
    address public aaveStrategy;
    address public usdcStrategy;

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

        // 3. SwapAdapterWrapper
        swapAdapterWrapper = address(new UniswapV4SwapAdapterWrapper(mockSwapAdapter));
        console2.log("SwapAdapterWrapper:", swapAdapterWrapper);

        // 4. LoanVault implementation
        loanVaultImpl = address(new LoanVault());
        console2.log("LoanVault impl:", loanVaultImpl);

        // 5. Loan
        loan = address(
            new Loan(
                accessManager,
                bitmorPool, // aaveV3Pool placeholder (flash loans won't work locally)
                bitmorPool, // aaveAddressesProvider placeholder
                bitmorPool, // bitmorPool
                aaveOracle,
                btcVault, // collateralAsset (bvBTC)
                mockUsdc, // debtAsset
                mockCbBTC, // btc
                swapAdapterWrapper,
                address(0), // zQuoter (not used locally)
                msg.sender, // premiumCollector
                PRE_CLOSURE_FEE,
                GRACE_PERIOD,
                LIQUIDATION_BUFFER
            )
        );
        console2.log("Loan:", loan);

        // 6. LoanVaultFactory
        loanVaultFactory = address(new LoanVaultFactory(loanVaultImpl, loan));
        console2.log("LoanVaultFactory:", loanVaultFactory);

        // 7. Strategies
        aaveStrategy = address(new AaveTokenizedStrategy(bitmorPool, btcVault));
        usdcStrategy = address(new USDCStrategy(usdcVault, bitmorPool, bitmorPool));
        console2.log("AaveStrategy:", aaveStrategy);
        console2.log("USDCStrategy:", usdcStrategy);

        // 8. AccessManager setup (roles, grants, schedule)
        _setupAccessManagerRoles();

        vm.stopBroadcast();

        // 9. Save addresses (execution happens in separate script after time advance)
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

        console2.log("Loaded Phase 1: AccessManager:", accessManager);
    }

    /// @notice Loads lending pool addresses from deployed-contracts.json
    function _loadLendingPoolAddresses() internal {
        string memory json = vm.readFile("../lending-pool/deployed-contracts.json");

        bitmorPool = vm.parseJsonAddress(json, ".LendingPool.localhost.address");
        aaveOracle = vm.parseJsonAddress(json, ".AaveOracle.localhost.address");

        console2.log("Loaded LendingPool:", bitmorPool);
        console2.log("Loaded AaveOracle:", aaveOracle);
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

        // Get role IDs for scheduling operations
        (,,,, uint64 lpmSlowId,,,,,) = rolesData.LPM_SLOW();
        (,,,, uint64 bvcId,,,,,) = rolesData.BVC();
        (,,,, uint64 uvcId,,,,,) = rolesData.UVC();

        console2.log("Setting up roles - LPM_SLOW:", lpmSlowId, "BVC:", bvcId);
        console2.log("Loan address:", loan);
        console2.log("BTCVault address:", btcVault);
        console2.log("USDCVault address:", usdcVault);

        // Set target function roles for actual deployed contracts
        // (RolesData has INITIAL_ADMIN as placeholder, we need actual addresses)
        manager.setTargetFunctionRole(loan, rolesData.getLPM_SLOW_SELECTORS(), lpmSlowId);
        console2.log("Set LPM_SLOW selectors on Loan");
        manager.setTargetFunctionRole(btcVault, rolesData.getBVC_SELECTORS(), bvcId);
        console2.log("Set BVC selectors on BTCVault");
        manager.setTargetFunctionRole(usdcVault, rolesData.getUVC_SELECTORS(), uvcId);
        console2.log("Set UVC selectors on USDCVault");

        // Grant roles with execution delays (enables schedule() - requires non-zero delay)
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

        // Get guardian role IDs (tuple: grantee, id, isContract)
        (, uint64 guardianLpmSlowId,) = rolesData.GUARDIAN_LPM_SLOW();
        (, uint64 guardianBvmSlowId,) = rolesData.GUARDIAN_BVM_SLOW();
        (, uint64 guardianBvcId,) = rolesData.GUARDIAN_BVC();
        (, uint64 guardianBvaSlowId,) = rolesData.GUARDIAN_BVA_SLOW();
        (, uint64 guardianUvmSlowId,) = rolesData.GUARDIAN_UVM_SLOW();
        (, uint64 guardianUvcId,) = rolesData.GUARDIAN_UVC();

        // Get guarded role IDs (tuple with 10 elements)
        (,,,, uint64 lpmSlowId,,,,,) = rolesData.LPM_SLOW();
        (,,,, uint64 bvmSlowId,,,,,) = rolesData.BVM_SLOW();
        (,,,, uint64 bvcId,,,,,) = rolesData.BVC();
        (,,,, uint64 bvaSlowId,,,,,) = rolesData.BVA_SLOW();
        (,,,, uint64 uvmSlowId,,,,,) = rolesData.UVM_SLOW();
        (,,,, uint64 uvcId,,,,,) = rolesData.UVC();

        // Grant guardian roles to admin
        manager.grantRole(guardianLpmSlowId, admin, 0);
        manager.grantRole(guardianBvmSlowId, admin, 0);
        manager.grantRole(guardianBvcId, admin, 0);
        manager.grantRole(guardianBvaSlowId, admin, 0);
        manager.grantRole(guardianUvmSlowId, admin, 0);
        manager.grantRole(guardianUvcId, admin, 0);

        // Set guardian relationships
        manager.setRoleGuardian(lpmSlowId, guardianLpmSlowId);
        manager.setRoleGuardian(bvmSlowId, guardianBvmSlowId);
        manager.setRoleGuardian(bvcId, guardianBvcId);
        manager.setRoleGuardian(bvaSlowId, guardianBvaSlowId);
        manager.setRoleGuardian(uvmSlowId, guardianUvmSlowId);
        manager.setRoleGuardian(uvcId, guardianUvcId);
    }

    /// @notice Schedules all delayed operations for execution after timelock
    function _scheduleLocalOperations() internal {
        uint48 when = uint48(block.timestamp + DeploymentConstants.EXECUTION_DELAY);

        // LPM_SLOW Operations (Loan config)
        manager.schedule(loan, abi.encodeCall(ILoan.setLoanVaultFactory, (loanVaultFactory)), when);
        manager.schedule(loan, abi.encodeCall(ILoan.setGracePeriod, (GRACE_PERIOD)), when);
        manager.schedule(loan, abi.encodeCall(ILoan.setLiquidationBuffer, (LIQUIDATION_BUFFER)), when);
        manager.schedule(loan, abi.encodeCall(ILoan.setPremiumCollector, (msg.sender)), when);
        manager.schedule(loan, abi.encodeCall(ILoan.setPreClosureFee, (PRE_CLOSURE_FEE)), when);

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
        // Build updated networkConfig with all addresses
        string memory networkConfig = string.concat(
            "{",
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
            '",',
            '"btcOracle":"',
            vm.toString(btcOracle),
            '",',
            '"usdcVault":"',
            vm.toString(usdcVault),
            '",',
            '"loan":"',
            vm.toString(loan),
            '",',
            '"loanVaultFactory":"',
            vm.toString(loanVaultFactory),
            '",',
            '"loanVaultImpl":"',
            vm.toString(loanVaultImpl),
            '",',
            '"swapAdapterWrapper":"',
            vm.toString(swapAdapterWrapper),
            '",',
            '"aaveStrategy":"',
            vm.toString(aaveStrategy),
            '",',
            '"usdcStrategy":"',
            vm.toString(usdcStrategy),
            '"',
            "}"
        );

        string memory fullJson =
            string.concat('{"deployments":{"31337":{"network":"localhost","networkConfig":', networkConfig, "}}}");

        vm.writeFile("./deployments.json", fullJson);
        console2.log("Saved final addresses to deployments.json");
    }
}
