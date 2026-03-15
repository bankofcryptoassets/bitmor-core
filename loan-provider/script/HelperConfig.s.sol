// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {stdJson} from "forge-std/StdJson.sol";
import {Script} from "forge-std/Script.sol";
import {IPriceOracleGetter} from "@bitmor/interfaces/IPriceOracleGetter.sol";

contract HelperConfig is Script {
    using stdJson for string;

    struct NetworkConfig {
        address accessManager;
        address bitmorPool;
        address aaveV3Pool;
        address aaveAddressesProvider;
        address oracle;
        address collateralAsset;
        address debtAsset;
        address btc;
        address swapper;
        address premiumCollector;
        address usdc;
        address usdc_holder;
    }

    /// @notice Protocol-wide configuration parameters for deployment scripts
    /// @dev All protocol constants centralized here — deployers only edit this struct's values
    struct ProtocolConfig {
        /// @notice Loan pre-closure fee in basis points (0.1%)
        uint256 preClosureFeeBps;
        /// @notice Grace period for monthly payments
        uint256 gracePeriod;
        /// @notice Maximum loan duration in months
        uint256 maxDuration;
        /// @notice Swap slippage tolerance in basis points
        uint256 slippageSwap;
        /// @notice Shares-to-asset conversion slippage tolerance in basis points
        uint256 slippageSharesToAsset;
        /// @notice Maximum cbBTC collateral amount (8 decimals)
        uint256 maxBTCAmt;
        /// @notice Minimum cbBTC collateral amount (8 decimals)
        uint256 minBTCAmt;
        /// @notice Minimum deposit percentage in basis points
        uint256 minDepositBps;
        /// @notice Liquidation fee in basis points
        uint256 liquidationFee;
        /// @notice Liquidation buffer in basis points
        uint256 liquidationBuffer;
        /// @notice Maximum strategy cap
        uint256 strategyCap;
        /// @notice Maximum number of strategies per vault
        uint256 maxStrategies;
        /// @notice Vault entry fee in basis points
        uint256 entryFee;
        /// @notice Vault exit fee in basis points
        uint256 exitFee;
    }

    NetworkConfig internal s_networkConfig;

    uint256 public constant CHAIN_ID_LOCAL = 31337;
    uint256 public constant CHAIN_ID_BASE_SEPOLIA = 84532;
    uint256 public constant CHAIN_ID_BASE_MAINNET = 8453;
    uint256 public constant DECIMAL_USDC = 1e6;
    uint256 public constant DECIMAL_CBBTC = 1e8;
    uint256 constant DEPOSIT_AMT = 1e8 * DECIMAL_USDC;
    uint256 constant PREMIUM_AMT = 5_000 * DECIMAL_USDC;
    uint256 constant CBBTC_AMT = 1e8 * DECIMAL_CBBTC;
    uint256 constant DURATION_IN_MONTHS = 12;
    uint256 constant PRE_CLOSURE_FEE = 10; // in bps = 0.1%
    uint256 constant INSURANCE_ID = 1;
    uint256 constant INITIAL_INSURANCE_ID = 0;
    uint256 constant MAX_LOAN_AMOUNT_BASE_SEPOLIA = 70_000 * DECIMAL_USDC;
    uint256 constant GRACE_PERIOD = 7 days;
    uint256 constant MAX_DURATION = 60; // 5 years in months
    // Base Mainnet External Protocol Constants (only mainnet uses hardcoded addresses)
    address constant AAVE_V3_POOL_BASE_MAINNET = 0xA238Dd80C259a72e81d7e4664a9801593F98d1c5;
    address constant AAVE_ADDRESSES_PROVIDER_BASE_MAINNET = 0xe20fCBdBfFC4Dd138cE8b2E6FBb6CB49777ad64D;
    // TODO: Replace with actual Base mainnet addresses before deployment
    address constant CBBTC_BASE_MAINNET = address(0);
    address constant USDC_BASE_MAINNET = address(0);
    address constant SWAP_ADAPTER_BASE_MAINNET = address(0);
    address public constant BITMOR_OWNER = 0x30fF6c272f2F427CcC81cb7fB14F5AFB94fF9Ad6; // bitmor_owner
    address public constant BITMOR_USER = 0xAe773320F12d18c93acAA4C2054340620b748E3a; // bitmor_user
    address public constant PREMIUM_COLLECTOR = 0x30fF6c272f2F427CcC81cb7fB14F5AFB94fF9Ad6; // bitmor_owner
    bytes public constant DATA = "0xLOAN";
    // Default vault fees in basis points
    uint256 public constant DEFAULT_ENTRY_FEE = 10; // 0.1%
    uint256 public constant DEFAULT_EXIT_FEE = 10; // 0.1%
    // Liquidation fee configuration
    uint256 public constant LIQUIDATION_FEE = 0; // 0 basis points initially
    address public constant LIQUIDATION_FEE_COLLECTOR = BITMOR_OWNER;
    // USDC Strategy allocation config (in basis points)
    uint256 public constant DEFAULT_AAVE_ALLOCATION = 8000; // 80% to Aave
    uint256 public constant DEFAULT_MINIMUM_DELTA_REQUIRED = 100; // 1% minimum delta for reallocation

    // Protocol configuration constants
    uint256 public constant SLIPPAGE_SWAP = 50; // 0.5%
    uint256 public constant SLIPPAGE_SHARES_TO_ASSET = 100; // 1%
    uint256 public constant MAX_BTC_AMOUNT = 10e8; // 10 BTC
    uint256 public constant MIN_BTC_AMOUNT = 0.01e8; // 0.01 BTC
    uint256 public constant MIN_DEPOSIT_BPS = 30_00; // 30%
    uint256 public constant LIQUIDATION_BUFFER = 50; // 0.5%
    uint256 public constant STRATEGY_CAP = type(uint96).max;
    uint256 public constant MAX_STRATEGIES = 5;

    // Oracle price constants (8 decimals)
    uint256 public constant BTC_USD_PRICE = 100_000e8; // $100,000
    uint256 public constant USDC_USD_PRICE = 1e8; // $1

    /// @notice Returns human-readable network name for a given `chainId`
    /// @param chainId The chain ID to look up
    /// @return name The network name (e.g., "base-sepolia", "local")
    function getNetworkName(uint256 chainId) public pure returns (string memory name) {
        if (chainId == CHAIN_ID_LOCAL) {
            name = "local";
        } else if (chainId == CHAIN_ID_BASE_SEPOLIA) {
            name = "base-sepolia";
        } else if (chainId == CHAIN_ID_BASE_MAINNET) {
            name = "base";
        } else {
            name = "unknown";
        }
    }

    /// @notice Returns network name for current chain
    /// @return name The network name for `block.chainid`
    function getCurrentNetworkName() public view returns (string memory) {
        return getNetworkName(block.chainid);
    }

    /// @notice Returns the network key used in lending-pool/deployed-contracts.json
    /// @dev Maps chain ID to the key the lending-pool Hardhat deployment uses
    /// @return key The network key (e.g., "localhost", "sepolia", "base")
    function getLendingPoolNetworkKey() public view returns (string memory key) {
        if (block.chainid == CHAIN_ID_LOCAL || block.chainid == 1337) {
            key = "localhost";
        } else if (block.chainid == CHAIN_ID_BASE_SEPOLIA) {
            key = "sepolia";
        } else if (block.chainid == CHAIN_ID_BASE_MAINNET) {
            key = "base";
        } else {
            revert("HelperConfig: unsupported chain for lending pool network key");
        }
    }

    /// @notice Lazy initialization - call this to populate s_networkConfig if needed
    /// @dev Avoids stack depth issues by not auto-initializing in constructor
    function initNetworkConfig() public {
        if (block.chainid == CHAIN_ID_LOCAL) {
            _initLocalConfig();
        } else if (block.chainid == CHAIN_ID_BASE_SEPOLIA) {
            _initBaseSepoliaConfig();
        }
    }

    /// @dev Internal helper to initialize Base Sepolia config incrementally
    function _initBaseSepoliaConfig() internal {
        s_networkConfig.accessManager = getAccessManager();
        s_networkConfig.bitmorPool = getBitmorPool();
        s_networkConfig.aaveV3Pool = getAaveV3Pool();
        s_networkConfig.aaveAddressesProvider = getAaveAddressesProvider();
        s_networkConfig.oracle = getOracle();
        s_networkConfig.collateralAsset = getCollateralAsset();
        s_networkConfig.debtAsset = getDebtAsset();
        s_networkConfig.btc = getCbBTC();
        s_networkConfig.swapper = getSwapper();
        s_networkConfig.premiumCollector = getPremiumCollector();
        s_networkConfig.usdc = getUSDC();
        s_networkConfig.usdc_holder = getUSDCHolder();
    }

    /// @dev Internal helper to initialize local config incrementally
    function _initLocalConfig() internal {
        address mockUsdc = _readDeployment("debtAsset");
        address mockCbBTC = _readDeployment("cbBTC");

        s_networkConfig.accessManager = _readDeployment("accessManager");
        s_networkConfig.bitmorPool = getBitmorPool();
        s_networkConfig.aaveV3Pool = _readDeployment("aaveV3Pool");
        s_networkConfig.aaveAddressesProvider = _readDeployment("aaveAddressesProvider");
        s_networkConfig.oracle = getOracle();
        s_networkConfig.collateralAsset = _readDeployment("collateralAsset"); // bvBTC
        s_networkConfig.debtAsset = mockUsdc;
        s_networkConfig.btc = mockCbBTC;
        s_networkConfig.swapper = getSwapper();
        s_networkConfig.premiumCollector = BITMOR_OWNER;
        s_networkConfig.usdc = mockUsdc;
        s_networkConfig.usdc_holder = BITMOR_OWNER;
    }

    function getInitialAdmin() public pure returns (address) {
        return BITMOR_OWNER;
    }

    function getAccessManager() public view returns (address) {
        return _readDeployment("accessManager");
    }

    function getGracePeriod() public pure returns (uint256) {
        return GRACE_PERIOD;
    }

    function getMaxDuration() public pure returns (uint256) {
        return MAX_DURATION;
    }

    function getPremiumCollector() public pure returns (address) {
        return PREMIUM_COLLECTOR;
    }

    function getPreClosureFee() public pure returns (uint256) {
        return PRE_CLOSURE_FEE;
    }

    function getLiquidationFee() public pure returns (uint256) {
        return LIQUIDATION_FEE;
    }

    function getLiquidationFeeCollector() public pure returns (address) {
        return LIQUIDATION_FEE_COLLECTOR;
    }

    function getAaveAllocation() public pure returns (uint256) {
        return DEFAULT_AAVE_ALLOCATION;
    }

    function getMinimumDeltaRequired() public pure returns (uint256) {
        return DEFAULT_MINIMUM_DELTA_REQUIRED;
    }

    /// @notice Returns the full protocol configuration for deployment scripts
    /// @dev All chains currently share the same values. Branch on `block.chainid` if they diverge.
    /// @return config The populated ProtocolConfig struct
    function getProtocolConfig() public pure returns (ProtocolConfig memory config) {
        config = ProtocolConfig({
            preClosureFeeBps: PRE_CLOSURE_FEE,
            gracePeriod: GRACE_PERIOD,
            maxDuration: MAX_DURATION,
            slippageSwap: SLIPPAGE_SWAP,
            slippageSharesToAsset: SLIPPAGE_SHARES_TO_ASSET,
            maxBTCAmt: MAX_BTC_AMOUNT,
            minBTCAmt: MIN_BTC_AMOUNT,
            minDepositBps: MIN_DEPOSIT_BPS,
            liquidationFee: LIQUIDATION_FEE,
            liquidationBuffer: LIQUIDATION_BUFFER,
            strategyCap: STRATEGY_CAP,
            maxStrategies: MAX_STRATEGIES,
            entryFee: DEFAULT_ENTRY_FEE,
            exitFee: DEFAULT_EXIT_FEE
        });
    }

    function getBitmorPool() public view returns (address) {
        string memory contractName = "LendingPool";
        return _readAddress(contractName);
    }

    function getAaveV3Pool() public view returns (address aavePool) {
        if (block.chainid == CHAIN_ID_BASE_MAINNET) {
            aavePool = AAVE_V3_POOL_BASE_MAINNET;
        } else {
            // Local & testnet: read from deployments.json (mocks)
            aavePool = _readDeployment("aaveV3Pool");
        }
    }

    function getAaveAddressesProvider() public view returns (address addressesProvider) {
        if (block.chainid == CHAIN_ID_BASE_MAINNET) {
            addressesProvider = AAVE_ADDRESSES_PROVIDER_BASE_MAINNET;
        } else {
            // Local & testnet: read from deployments.json (mocks)
            addressesProvider = _readDeployment("aaveAddressesProvider");
        }
    }

    function getOracle() public view returns (address) {
        string memory contractName = "AaveOracle";
        return _readAddress(contractName);
    }

    function getAddressesProvider() public view returns (address) {
        string memory contractName = "LendingPoolAddressesProvider";
        return _readAddress(contractName);
    }

    function getLoanVaultImplementation() public view returns (address) {
        return _readDeployment("loanVaultImpl");
    }

    function getLoanVaultFactory() public view returns (address) {
        return _readDeployment("loanVaultFactory");
    }

    function getCollateralAsset() public view returns (address) {
        return getBTCVault();
    }

    function getDebtAsset() public view returns (address) {
        return _readAddress("bUSDC");
    }

    function getSwapAdapter() public view returns (address swapAdapter) {
        swapAdapter = _readDeployment("swapAdapter");
    }

    function getSwapper() public view returns (address) {
        return _readDeployment("swapper");
    }

    /// @dev Deprecated: kept for backward compatibility in tests that still reference the old name
    function getSwapAdapterWrapper() public view returns (address) {
        return getSwapper();
    }

    function getLoan() public view returns (address) {
        return _readDeployment("loan");
    }

    /// @notice Returns the deployed BitmorAddressesProvider address
    /// @return The BitmorAddressesProvider address from most recent deployment
    function getBitmorAddressesProvider() public view returns (address) {
        return _readDeployment("bitmorAddressesProvider");
    }

    /// @notice Returns the deployed AutoRepayment contract address
    /// @dev This is the address to configure as autoRepayer in BitmorAddressesProvider
    /// @return The AutoRepayment contract address from deployments.json
    function getAutoRepayer() public view returns (address) {
        return _readDeployment("autoRepayment");
    }

    /// @notice Returns the BTCVault implementation address
    /// @return The BTCVault implementation address from most recent deployment
    function getBTCVaultImpl() public view returns (address) {
        return _readDeployment("btcVaultImpl");
    }

    /// @notice Returns the Loan implementation address
    /// @return The Loan implementation address from most recent deployment
    function getLoanImpl() public view returns (address) {
        return _readDeployment("loanImpl");
    }

    /// @notice Returns the USDCVault implementation address
    /// @return The USDCVault implementation address from most recent deployment
    function getUSDCVaultImpl() public view returns (address) {
        return _readDeployment("usdcVaultImpl");
    }

    /// @notice Returns the AutoRepayment implementation address
    /// @return The AutoRepayment implementation address from most recent deployment
    function getAutoRepaymentImpl() public view returns (address) {
        return _readDeployment("autoRepaymentImpl");
    }

    /// @notice Returns the BitmorAddressesProvider implementation address
    /// @return The BitmorAddressesProvider implementation address from most recent deployment
    function getBitmorAddressesProviderImpl() public view returns (address) {
        return _readDeployment("bitmorAddressesProviderImpl");
    }

    /// @notice Returns the UpgradeableBeacon address for LoanVault proxies
    /// @return The UpgradeableBeacon address from most recent deployment
    function getBeacon() public view returns (address) {
        return _readDeployment("beacon");
    }

    /// @notice Returns the BeaconController address
    /// @return The BeaconController address from most recent deployment
    function getBeaconController() public view returns (address) {
        return _readDeployment("beaconController");
    }

    /// @notice Returns the deployed BTCVault address
    /// @return The BTCVault proxy address from most recent deployment
    function getBTCVault() public view returns (address) {
        return _readDeployment("collateralAsset");
    }

    /// @notice Returns the deployed USDCVault address
    /// @return The USDCVault proxy address from most recent deployment
    function getUSDCVault() public view returns (address) {
        return _readDeployment("usdcVault");
    }

    /// @notice Returns the deployed AaveTokenizedStrategy address for BTCVault
    /// @return The AaveTokenizedStrategy address from most recent deployment
    function getAaveTokenizedStrategy() public view returns (address) {
        return _readDeployment("aaveStrategy");
    }

    /// @notice Returns the deployed USDCStrategy address
    /// @return The USDCStrategy address from most recent deployment
    function getUSDCStrategy() public view returns (address) {
        return _readDeployment("usdcStrategy");
    }

    /// @notice Returns the cbBTC/BTC token address
    /// @dev Mainnet uses a hardcoded constant; local/testnet reads from deployments.json
    /// @return The cbBTC token address
    function getCbBTC() public view returns (address) {
        if (block.chainid == CHAIN_ID_BASE_MAINNET) {
            return CBBTC_BASE_MAINNET;
        }
        return _readDeployment("cbBTC");
    }

    /// @notice Returns the USDC token address
    /// @dev Mainnet uses a hardcoded constant; local/testnet reads from deployments.json
    /// @return The USDC token address
    function getUSDC() public view returns (address) {
        if (block.chainid == CHAIN_ID_BASE_MAINNET) {
            return USDC_BASE_MAINNET;
        }
        return _readDeployment("debtAsset");
    }

    /// @notice Returns the swap adapter address
    /// @dev Mainnet uses a hardcoded constant; local/testnet reads from deployments.json
    function getSwapAdapterAddress() public view returns (address) {
        if (block.chainid == CHAIN_ID_BASE_MAINNET) {
            return SWAP_ADAPTER_BASE_MAINNET;
        }
        return _readDeployment("swapper");
    }

    /// @notice Returns the USDC holder address (for testing)
    /// @dev Reads from deployments.json for all chains
    /// @return The USDC holder address
    function getUSDCHolder() public view returns (address) {
        return _readDeployment("usdcHolder");
    }

    /// @notice Returns the deployed mock cbBTC contract address (local only)
    /// @return The MockCbBTC address from most recent deployment, or address(0) if not local
    function getMockCbBTC() public view returns (address) {
        if (block.chainid == CHAIN_ID_LOCAL) {
            return _readDeployment("cbBTC");
        }
        return address(0);
    }

    /// @notice Returns the deployed mock USDC contract address (local only)
    /// @return The MockUSDC address from most recent deployment, or address(0) if not local
    function getMockUSDC() public view returns (address) {
        if (block.chainid == CHAIN_ID_LOCAL) {
            return _readDeployment("debtAsset");
        }
        return address(0);
    }

    /// @notice Returns the deployed BTC/USD Chainlink oracle address (local only)
    /// @return The BTC/USD mock oracle address from most recent deployment
    function getBtcUsdOracle() public view returns (address) {
        return _readDeployment("btcOracle");
    }

    /// @notice Returns the deployed USDC/USD Chainlink oracle address (local only)
    /// @return The USDC/USD mock oracle address from most recent deployment
    function getUsdcUsdOracle() public view returns (address) {
        return _readDeployment("usdcOracle");
    }

    /// @notice Returns the path to loan-provider's deployments.json
    /// @return The absolute path to deployments.json
    function getDeploymentsJsonPath() public view returns (string memory) {
        return string.concat(vm.projectRoot(), "/deployments.json");
    }

    /// @notice Returns the path to lending-pool's deployed-contracts.json
    /// @return The absolute path to deployed-contracts.json
    function getLendingPoolDeploymentsPath() public view returns (string memory) {
        return string.concat(vm.projectRoot(), "/../lending-pool/deployed-contracts.json");
    }

    /// @notice Returns the broadcast directory for a given script
    /// @param scriptName The script file name (e.g., "DeployLoan.s.sol")
    /// @return The absolute path to the broadcast directory
    function getBroadcastPath(string memory scriptName) public view returns (string memory) {
        return
            string.concat(
                vm.projectRoot(), "/broadcast/", scriptName, "/", vm.toString(block.chainid), "/run-latest.json"
            );
    }

    function getLoanConfig()
        public
        pure
        returns (
            uint256 depositAmt,
            uint256 premiumAmt,
            uint256 collateralAmt,
            uint256 durationInMonths,
            bytes memory data
        )
    {
        return (DEPOSIT_AMT, PREMIUM_AMT, CBBTC_AMT, DURATION_IN_MONTHS, DATA);
    }

    function _readAddress(string memory contractName) internal view returns (address addr) {
        // Map current chain to the key used in deployed-contracts.json
        string memory network;
        if (block.chainid == CHAIN_ID_BASE_SEPOLIA) {
            // Your JSON uses "sepolia" for Base Sepolia deployments
            network = "sepolia";
        } else if (block.chainid == CHAIN_ID_LOCAL || block.chainid == 1337) {
            // lending-pool deployment saves under "localhost" key
            network = "localhost";
        } else {
            revert("HelperConfig: unsupported chainid for deployed-contracts.json");
        }

        // Read the JSON file from repo root
        string memory path = string.concat(vm.projectRoot(), "/../lending-pool/deployed-contracts.json");
        string memory json = vm.readFile(path);

        // Build jsonpath like: .LendingPool.sepolia.address
        string memory key = string.concat(".", contractName, ".", network, ".address");

        // Parse and return
        addr = json.readAddress(key);
        require(addr != address(0), "HelperConfig: empty address in deployed-contracts.json");
    }

    /// @notice Reads address from deployments.json for any supported chain
    /// @param key The key to read (e.g., "accessManager", "loan")
    /// @return addr The address, or address(0) if not found
    function _readDeployment(string memory key) internal view returns (address addr) {
        string memory path = string.concat(vm.projectRoot(), "/deployments.json");

        try vm.readFile(path) returns (string memory json) {
            // Build jsonpath: .deployments.<chainId>.networkConfig.<key>
            string memory jsonKey = string.concat(".deployments.", vm.toString(block.chainid), ".networkConfig.", key);

            try vm.parseJsonAddress(json, jsonKey) returns (address parsed) {
                addr = parsed;
            } catch {
                addr = address(0);
            }
        } catch {
            addr = address(0);
        }
    }

    /// @notice Public wrapper to read address from lending-pool/deployed-contracts.json
    /// @param contractName The contract name key (e.g., "LendingPoolCollateralManager")
    /// @return addr The address from the JSON file
    function readLendingPoolAddress(string memory contractName) public view returns (address addr) {
        return _readAddress(contractName);
    }
}
