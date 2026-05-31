// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {console2} from "forge-std/Script.sol";
import {ForkRolesConfig} from "@bitmor-config/ForkRolesConfig.sol";
import {DeploymentConstants} from "../DeploymentConstants.sol";
import {BitmorAccessManager} from "@bitmor/accessManager/BitmorAccessManager.sol";
import {USDCVault} from "@usdcVault/USDCVault.sol";
import {Loan} from "@bitmor/protocol/Loan.sol";
import {BitmorAddressesProvider} from "@bitmor/protocol/BitmorAddressesProvider.sol";
import {AutoRepayment} from "@bitmor/protocol/AutoRepayment.sol";
import {AaveTokenizedStrategy} from "@btcVault/TokenizedStrategy/AaveTokenizedStrategy.sol";
import {USDCStrategy} from "@usdcVault/USDCStrategy.sol";
import {BTCVault} from "@btcVault/BTCVault.sol";
import {DataTypes} from "@bitmor/libraries/types/DataTypes.sol";
import {Options} from "@openzeppelin-foundry-upgrades/Options.sol";
import {HelperConfig} from "../../HelperConfig.s.sol";
import {StdStorage, stdStorage} from "forge-std/StdStorage.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title DeployPhase3Fork
/// @notice Phase 3 fork deployment: all UUPS proxies, beacon, strategies, and roles
/// @dev Uses real external contracts from fork state. Swap adapter must be pre-deployed
/// from swap-routers/ and its address set in HelperConfig (SWAP_ADAPTER_BASE_MAINNET).
/// @custom:security For local fork deployments only.
contract DeployPhase3Fork is ForkRolesConfig {
    uint256 constant STRATEGY_CAP = type(uint96).max;

    using stdStorage for StdStorage;

    StdStorage private _stdstore;

    // ============ Phase 1 Addresses ============
    address public accessManager;
    address public usdc;
    address public cbBTC;
    address public btcVault;
    address public btcVaultImpl;

    // ============ Lending Pool Addresses ============
    address public bitmorPool;
    address public aaveOracle;
    address public lendingPoolAddressesProvider;

    // ============ External Protocol Addresses ============
    address public aaveV3Pool;
    address public aaveAddressesProvider;

    // ============ Phase 3 Deployed Addresses ============
    address public usdcVault;
    address public usdcVaultImpl;
    address public swapper;
    address public loan;
    address public loanImpl;
    address public loanVaultImpl;
    address public beacon;
    address public beaconController;
    address public loanVaultFactory;
    address public bitmorAddressesProvider;
    address public bitmorAddressesProviderImpl;
    address public autoRepayment;
    address public autoRepaymentImpl;
    address public aaveStrategy;
    address public usdcStrategy;

    function run() external {
        _preflightPhase3(DeploymentConstants.LOCAL_CHAIN_ID);
        _preflightLendingPool();

        HelperConfig helperConfig = new HelperConfig();
        HelperConfig.ProtocolConfig memory pc = helperConfig.getProtocolConfig();

        // Validate swap adapter (deployed by orchestrator in Phase 0 from swap-routers/)
        // Read from SWAP_ADAPTER_OVERRIDE env var (set by deploy-fork.sh), fall back to HelperConfig
        address swapAdapterAddr = vm.envOr("SWAP_ADAPTER_OVERRIDE", address(0));
        if (swapAdapterAddr == address(0)) {
            swapAdapterAddr = helperConfig.getSwapAdapterAddress();
        }
        require(swapAdapterAddr != address(0), "DeployPhase3Fork: swap adapter not deployed - run Phase 0 first");
        require(swapAdapterAddr.code.length > 0, "DeployPhase3Fork: swap adapter has no bytecode on fork");

        // Validate USDC
        address usdcAddr = helperConfig.getUSDC();
        require(usdcAddr != address(0), "DeployPhase3Fork: set USDC_BASE_MAINNET in HelperConfig");
        require(usdcAddr.code.length > 0, "DeployPhase3Fork: USDC has no bytecode on fork");

        console2.log("=== Phase 3: Fork Deployment ===");

        // Load Phase 1 + lending pool addresses from unified registry via HelperConfig
        accessManager = helperConfig.getAccessManager();
        cbBTC = helperConfig.getCbBTC();
        btcVault = helperConfig.getBTCVault();
        btcVaultImpl = helperConfig.getBTCVaultImpl();
        aaveV3Pool = helperConfig.getAaveV3Pool();
        aaveAddressesProvider = helperConfig.getAaveAddressesProvider();
        bitmorPool = helperConfig.getBitmorPool();
        aaveOracle = helperConfig.getOracle();
        lendingPoolAddressesProvider = helperConfig.getAddressesProvider();
        usdc = usdcAddr;
        swapper = swapAdapterAddr;

        vm.startBroadcast();

        // 1. USDCVault (UUPS proxy)
        usdcVault =
            _deployUUPSProxy("USDCVault.sol", abi.encodeCall(USDCVault.initialize, (accessManager, usdc, bitmorPool)));
        usdcVaultImpl = _getProxyImplementation(usdcVault);
        console2.log("USDCVault proxy:", usdcVault);

        // 2. AaveOracle — register cbBTC oracle source for bvBTC pricing path
        //
        // Phase 2 (lending-pool) configured:
        //   - assetsSources[USDC_addr] = USDC/USD Chainlink
        //   - s_bvBTC = btcVault, s_btc = cbBTC
        //
        // bvBTC pricing uses the special path: btcPrice * previewRedeem(oneShare) / decimals
        // That path calls _getAssetPrice(s_btc) which needs assetsSources[cbBTC].
        // cbBTC is NOT in ReserveAssets, so Phase 2 never sets it.
        // Fix: set cbBTC source to the BTC/USD Chainlink feed from HelperConfig.
        {
            address btcChainlinkFeed = helperConfig.getBtcUsdChainlink();
            require(
                btcChainlinkFeed != address(0), "DeployPhase3Fork: set BTC_USD_CHAINLINK_BASE_MAINNET in HelperConfig"
            );
            require(btcChainlinkFeed.code.length > 0, "DeployPhase3Fork: BTC/USD Chainlink has no bytecode on fork");

            address[] memory assets = new address[](1);
            address[] memory sources = new address[](1);
            assets[0] = cbBTC;
            sources[0] = btcChainlinkFeed;
            (bool okSet,) =
                aaveOracle.call(abi.encodeWithSignature("setAssetSources(address[],address[])", assets, sources));
            require(okSet, "Failed to set cbBTC oracle source");
            console2.log("AaveOracle: cbBTC source set to BTC/USD Chainlink:", btcChainlinkFeed);
        }
        console2.log("AaveOracle: bvBTC pricing path active (s_bvBTC=btcVault, s_btc=cbBTC, cbBTC source set)");

        // 3. BitmorAddressesProvider (UUPS proxy)
        bitmorAddressesProvider = _deployUUPSProxy(
            "BitmorAddressesProvider.sol",
            abi.encodeCall(BitmorAddressesProvider.initialize, (accessManager, swapper, msg.sender, msg.sender))
        );
        bitmorAddressesProviderImpl = _getProxyImplementation(bitmorAddressesProvider);
        console2.log("BitmorAddressesProvider proxy:", bitmorAddressesProvider);

        // 4. Loan (UUPS proxy)
        Options memory loanOpts;
        loanOpts.unsafeAllow = "external-library-linking";
        DataTypes.InitParams memory loanInitParams = DataTypes.InitParams({
            manager: accessManager,
            aaveV3Pool: aaveV3Pool,
            aaveAddressesProvider: aaveAddressesProvider,
            bitmorPool: bitmorPool,
            oracle: aaveOracle,
            collateralAsset: btcVault,
            debtAsset: usdc,
            btc: cbBTC,
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

        // 5. LoanVault beacon proxy
        (loanVaultImpl, beacon, beaconController, loanVaultFactory) = _deployBeaconProxy(accessManager, loan);
        console2.log("LoanVault beacon system deployed");

        // 6. AutoRepayment (UUPS proxy)
        autoRepayment = _deployUUPSProxy(
            "AutoRepayment.sol", abi.encodeCall(AutoRepayment.initialize, (accessManager, loan, usdc))
        );
        autoRepaymentImpl = _getProxyImplementation(autoRepayment);
        console2.log("AutoRepayment proxy:", autoRepayment);

        // 7. BAP post-init setters
        BitmorAddressesProvider(bitmorAddressesProvider).setVaultFactory(loanVaultFactory);
        BitmorAddressesProvider(bitmorAddressesProvider).setAutoRepayer(autoRepayment);

        // 8. Register with LendingPoolAddressesProvider
        (bool okSetLoan,) = lendingPoolAddressesProvider.call(abi.encodeWithSignature("setBitmorLoan(address)", loan));
        require(okSetLoan, "Failed to setBitmorLoan");
        (bool okSetUSDCVault,) =
            lendingPoolAddressesProvider.call(abi.encodeWithSignature("setUSDCVault(address)", usdcVault));
        require(okSetUSDCVault, "Failed to setUSDCVault");

        // 9. Strategies (non-proxied) — uses real Aave V3 pool from fork
        aaveStrategy = address(new AaveTokenizedStrategy(aaveV3Pool, btcVault));
        usdcStrategy = address(new USDCStrategy(usdcVault, aaveV3Pool, bitmorPool));
        console2.log("Strategies deployed");

        // 10. Wire strategies — called before _setupAccessManagerRoles() maps
        // these functions to BVC/UVC roles. Until role wiring, restricted functions
        // default to ADMIN_ROLE (0) which the deployer holds with 0 delay.
        BTCVault(btcVault).addStrategy(aaveStrategy, STRATEGY_CAP);
        console2.log("BTCVault strategy added (as ADMIN, pre-role-wiring)");
        USDCVault(usdcVault).setStrategy(usdcStrategy);
        console2.log("USDCVault strategy set (as ADMIN, pre-role-wiring)");

        // 10b. Seed BLP with USDC liquidity for loan borrows
        // Write USDC balance directly — fork has real USDC (no mint())
        _stdstore.target(usdc).sig(IERC20.balanceOf.selector).with_key(msg.sender)
            .checked_write(DeploymentConstants.USDC_SEED_AMOUNT);
        _seedUSDCVault(usdcVault, usdc, DeploymentConstants.USDC_SEED_AMOUNT);

        // 11. AccessManager role wiring
        _setupAccessManagerRoles();

        vm.stopBroadcast();

        console2.log("=== Phase 3 Complete ===");
    }

    function _setupAccessManagerRoles() internal {
        BitmorAccessManager manager = BitmorAccessManager(accessManager);
        RoleGrantees memory g = _getRoleGrantees();
        _grantOperationalRoles(
            manager, g, loan, btcVault, usdcVault, autoRepayment, bitmorAddressesProvider, bitmorPool
        );
        _wireUpgraderRole(
            manager, loan, btcVault, usdcVault, autoRepayment, bitmorAddressesProvider, beaconController, g.upgrader
        );
        _setupGuardians(manager, g.admin);
    }
}
