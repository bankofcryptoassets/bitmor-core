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

    /// @notice Uniswap V4 swap configuration for deployment
    struct SwapConfig {
        address universalRouter;
        address quoter;
        uint24 fee;
        int24 tickSpacing;
        address hooks;
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
    uint256 constant DEPOSIT_AMT = 3e4 * DECIMAL_USDC; // 30000 USDC
    uint256 constant PREMIUM_AMT = 4_000 * DECIMAL_USDC;
    uint256 constant CBBTC_AMT = 1 * DECIMAL_CBBTC; // 1 CBBTC
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
    address constant CBBTC_BASE_MAINNET = 0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf;
    address constant USDC_BASE_MAINNET = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address constant SWAP_ADAPTER_BASE_MAINNET = address(0);
    // BTC/USD Chainlink aggregator on Base mainnet
    // TODO: Replace with actual address before fork/mainnet deployment
    address constant BTC_USD_CHAINLINK_BASE_MAINNET = 0x07DA0E54543a844a80ABE69c8A12F22B3aA59f9D;
    // Uniswap V4 Base Mainnet Constants
    // TODO: Replace with actual Base mainnet addresses before fork deployment
    address constant UNIVERSAL_ROUTER_BASE_MAINNET = 0x6fF5693b99212Da76ad316178A184AB56D299b43;
    address constant V4_QUOTER_BASE_MAINNET = 0x0d5e0F971ED27FBfF6c2837bf31316121532048D;
    uint24 constant SWAP_FEE_BASE_MAINNET = 3000;
    int24 constant SWAP_TICK_SPACING_BASE_MAINNET = 60;
    address constant SWAP_HOOKS_BASE_MAINNET = address(0);
    address public constant BITMOR_OWNER = 0xc617C587122256e940e10FA46d30f610139A818E; // bitmor_owner
    address public constant BITMOR_USER = 0xAe773320F12d18c93acAA4C2054340620b748E3a; // bitmor_user
    address public constant PREMIUM_COLLECTOR = 0xc617C587122256e940e10FA46d30f610139A818E; // bitmor_owner
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

    // INSURANCE DATA CONSTANTS
    string public constant INSTRUMENT_NAME = "BTC-10APR26-60000-C";
    string public constant CONTRACTS_AMOUNT = "0.01";
    string public constant PRICE_PER_CONTRACT = "50000";
    uint256 public constant SIGNED_BTC_PRICE = 60_000; // $60k
    uint256 public constant DERIBIT_BTC_PRICE = 60_000; // $60k

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

    /// @notice Returns the network key used by the lending-pool Hardhat deployment
    /// @dev Maps chain ID to the key the lending-pool Hardhat deployment uses
    /// @return key The network key (e.g., "localhost", "sepolia", "base")
    function getLendingPoolNetworkKey() public view returns (string memory key) {
        string memory fork = vm.envOr("FORK", string(""));
        if (bytes(fork).length > 0) {
            return "localhost";
        }
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
    /// @dev For full-mock testnet deployment, reads from unified registry like local
    function _initBaseSepoliaConfig() internal {
        address mockUsdc = _readDeployment("tokens.usdc");
        address mockCbBTC = _readDeployment("tokens.cbBTC");

        s_networkConfig.accessManager = _readDeployment("loanProvider.accessManager");
        s_networkConfig.bitmorPool = getBitmorPool();
        s_networkConfig.aaveV3Pool = _readDeployment("external.aaveV3Pool");
        s_networkConfig.aaveAddressesProvider = _readDeployment("external.aaveAddressesProvider");
        s_networkConfig.oracle = getOracle();
        s_networkConfig.collateralAsset = _readDeployment("loanProvider.btcVault");
        s_networkConfig.debtAsset = mockUsdc;
        s_networkConfig.btc = mockCbBTC;
        s_networkConfig.swapper = getSwapper();
        s_networkConfig.premiumCollector = BITMOR_OWNER;
        s_networkConfig.usdc = mockUsdc;
        s_networkConfig.usdc_holder = BITMOR_OWNER;
    }

    /// @dev Internal helper to initialize local config incrementally
    function _initLocalConfig() internal {
        address mockUsdc = _readDeployment("tokens.usdc");
        address mockCbBTC = _readDeployment("tokens.cbBTC");

        s_networkConfig.accessManager = _readDeployment("loanProvider.accessManager");
        s_networkConfig.bitmorPool = getBitmorPool();
        s_networkConfig.aaveV3Pool = _readDeployment("external.aaveV3Pool");
        s_networkConfig.aaveAddressesProvider = _readDeployment("external.aaveAddressesProvider");
        s_networkConfig.oracle = getOracle();
        s_networkConfig.collateralAsset = _readDeployment("loanProvider.btcVault"); // bvBTC
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
        return _readDeployment("loanProvider.accessManager");
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
        if (block.chainid == CHAIN_ID_BASE_MAINNET || _isFork()) {
            aavePool = AAVE_V3_POOL_BASE_MAINNET;
        } else {
            // Local & testnet: read from unified registry (mocks)
            aavePool = _readDeployment("external.aaveV3Pool");
        }
    }

    function getAaveAddressesProvider() public view returns (address addressesProvider) {
        if (block.chainid == CHAIN_ID_BASE_MAINNET || _isFork()) {
            addressesProvider = AAVE_ADDRESSES_PROVIDER_BASE_MAINNET;
        } else {
            // Local & testnet: read from unified registry (mocks)
            addressesProvider = _readDeployment("external.aaveAddressesProvider");
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
        return _readDeployment("loanProvider.loanVaultImpl");
    }

    function getLoanVaultFactory() public view returns (address) {
        return _readDeployment("loanProvider.loanVaultFactory");
    }

    function getCollateralAsset() public view returns (address) {
        return getBTCVault();
    }

    function getDebtAsset() public view returns (address) {
        return _readAddress("USDC");
    }

    function getSwapper() public view returns (address) {
        return _readDeployment("loanProvider.swapper");
    }

    function getLoan() public view returns (address) {
        return _readDeployment("loanProvider.loan");
    }

    /// @notice Returns the deployed BitmorAddressesProvider address
    /// @return The BitmorAddressesProvider address from most recent deployment
    function getBitmorAddressesProvider() public view returns (address) {
        return _readDeployment("loanProvider.addressesProvider");
    }

    /// @notice Returns the deployed AutoRepayment contract address
    /// @dev This is the address to configure as autoRepayer in BitmorAddressesProvider
    /// @return The AutoRepayment contract address from the unified registry
    function getAutoRepayer() public view returns (address) {
        return _readDeployment("loanProvider.autoRepayment");
    }

    /// @notice Returns the BTCVault implementation address
    /// @return The BTCVault implementation address from most recent deployment
    function getBTCVaultImpl() public view returns (address) {
        return _readDeployment("loanProvider.btcVaultImpl");
    }

    /// @notice Returns the Loan implementation address
    /// @return The Loan implementation address from most recent deployment
    function getLoanImpl() public view returns (address) {
        return _readDeployment("loanProvider.loanImpl");
    }

    /// @notice Returns the USDCVault implementation address
    /// @return The USDCVault implementation address from most recent deployment
    function getUSDCVaultImpl() public view returns (address) {
        return _readDeployment("loanProvider.usdcVaultImpl");
    }

    /// @notice Returns the AutoRepayment implementation address
    /// @return The AutoRepayment implementation address from most recent deployment
    function getAutoRepaymentImpl() public view returns (address) {
        return _readDeployment("loanProvider.autoRepaymentImpl");
    }

    /// @notice Returns the BitmorAddressesProvider implementation address
    /// @return The BitmorAddressesProvider implementation address from most recent deployment
    function getBitmorAddressesProviderImpl() public view returns (address) {
        return _readDeployment("loanProvider.addressesProviderImpl");
    }

    /// @notice Returns the UpgradeableBeacon address for LoanVault proxies
    /// @return The UpgradeableBeacon address from most recent deployment
    function getBeacon() public view returns (address) {
        return _readDeployment("loanProvider.beacon");
    }

    /// @notice Returns the BeaconController address
    /// @return The BeaconController address from most recent deployment
    function getBeaconController() public view returns (address) {
        return _readDeployment("loanProvider.beaconController");
    }

    /// @notice Returns the deployed BTCVault address
    /// @return The BTCVault proxy address from most recent deployment
    function getBTCVault() public view returns (address) {
        return _readDeployment("loanProvider.btcVault");
    }

    /// @notice Returns the deployed USDCVault address
    /// @return The USDCVault proxy address from most recent deployment
    function getUSDCVault() public view returns (address) {
        return _readDeployment("loanProvider.usdcVault");
    }

    /// @notice Returns the deployed AaveTokenizedStrategy address for BTCVault
    /// @return The AaveTokenizedStrategy address from most recent deployment
    function getAaveTokenizedStrategy() public view returns (address) {
        return _readDeployment("loanProvider.aaveStrategy");
    }

    /// @notice Returns the deployed USDCStrategy address
    /// @return The USDCStrategy address from most recent deployment
    function getUSDCStrategy() public view returns (address) {
        return _readDeployment("loanProvider.usdcStrategy");
    }

    /// @notice Returns the cbBTC/BTC token address
    /// @dev Mainnet uses a hardcoded constant; local/testnet reads from unified registry
    /// @return The cbBTC token address
    function getCbBTC() public view returns (address) {
        if (block.chainid == CHAIN_ID_BASE_MAINNET || _isFork()) {
            return CBBTC_BASE_MAINNET;
        }
        return _readDeployment("tokens.cbBTC");
    }

    /// @notice Returns the USDC token address
    /// @dev Mainnet uses a hardcoded constant; local/testnet reads from unified registry
    /// @return The USDC token address
    function getUSDC() public view returns (address) {
        if (block.chainid == CHAIN_ID_BASE_MAINNET || _isFork()) {
            return USDC_BASE_MAINNET;
        }
        return _readDeployment("tokens.usdc");
    }

    /// @notice Returns the swap adapter address
    /// @dev Mainnet uses a hardcoded constant; local/testnet reads from unified registry
    function getSwapAdapterAddress() public view returns (address) {
        if (block.chainid == CHAIN_ID_BASE_MAINNET || _isFork()) {
            return SWAP_ADAPTER_BASE_MAINNET;
        }
        return _readDeployment("loanProvider.swapper");
    }

    /// @notice Returns the Uniswap V4 swap configuration for Base mainnet
    function getSwapConfig() public pure returns (SwapConfig memory config) {
        config = SwapConfig({
            universalRouter: UNIVERSAL_ROUTER_BASE_MAINNET,
            quoter: V4_QUOTER_BASE_MAINNET,
            fee: SWAP_FEE_BASE_MAINNET,
            tickSpacing: SWAP_TICK_SPACING_BASE_MAINNET,
            hooks: SWAP_HOOKS_BASE_MAINNET
        });
    }

    /// @notice Returns the BTC/USD Chainlink aggregator address on Base mainnet
    function getBtcUsdChainlink() public pure returns (address) {
        return BTC_USD_CHAINLINK_BASE_MAINNET;
    }

    /// @notice Returns the USDC holder address (for testing)
    /// @dev Reads from unified registry for all chains
    /// @return The USDC holder address
    function getUSDCHolder() public view returns (address) {
        return _readDeployment("loanProvider.usdcHolder");
    }

    /// @notice Returns the deployed mock cbBTC contract address (local only)
    /// @return The MockCbBTC address from most recent deployment, or address(0) if not local
    function getMockCbBTC() public view returns (address) {
        if (block.chainid == CHAIN_ID_LOCAL || block.chainid == CHAIN_ID_BASE_SEPOLIA) {
            return _readDeployment("tokens.cbBTC");
        }
        return address(0);
    }

    /// @notice Returns the deployed mock USDC contract address (local only)
    /// @return The MockUSDC address from most recent deployment, or address(0) if not local
    function getMockUSDC() public view returns (address) {
        if (block.chainid == CHAIN_ID_LOCAL || block.chainid == CHAIN_ID_BASE_SEPOLIA) {
            return _readDeployment("tokens.usdc");
        }
        return address(0);
    }

    /// @notice Returns the deployed BTC/USD Chainlink oracle address (local only)
    /// @return The BTC/USD mock oracle address from most recent deployment
    function getBtcUsdOracle() public view returns (address) {
        return _readDeployment("external.btcOracle");
    }

    /// @notice Returns the deployed USDC/USD Chainlink oracle address (local only)
    /// @return The USDC/USD mock oracle address from most recent deployment
    function getUsdcUsdOracle() public view returns (address) {
        return _readDeployment("external.usdcOracle");
    }

    /// @notice Returns the path to the unified deployment registry for the current chain
    /// @return The absolute path to `../deployments/<chainKey>/latest.json`
    function getDeploymentsJsonPath() public view returns (string memory) {
        return string.concat(vm.projectRoot(), "/../deployments/", _getChainKey(), "/latest.json");
    }

    /// @notice Returns the path to the unified deployment registry (same as getDeploymentsJsonPath)
    /// @dev Kept for backward compatibility; lending-pool addresses are now in the unified registry
    /// @return The absolute path to `../deployments/<chainKey>/latest.json`
    function getLendingPoolDeploymentsPath() public view returns (string memory) {
        return string.concat(vm.projectRoot(), "/../deployments/", _getChainKey(), "/latest.json");
    }

    /// @notice Returns the chain key used in the unified deployment registry
    /// @dev When FORK env var is set, appends "-fork" to avoid collisions (e.g., "31337-fork")
    /// @return key The chain key string
    function _getChainKey() internal view returns (string memory) {
        string memory fork = vm.envOr("FORK", string(""));
        if (bytes(fork).length > 0) {
            return string.concat(vm.toString(block.chainid), "-fork");
        }
        return vm.toString(block.chainid);
    }

    /// @notice Public wrapper for _getChainKey()
    function getChainKey() public view returns (string memory) {
        return _getChainKey();
    }

    /// @notice Returns true if running in fork mode
    function _isFork() internal view returns (bool) {
        string memory fork = vm.envOr("FORK", string(""));
        return bytes(fork).length > 0;
    }

    /// @notice Public wrapper for _isFork()
    function isForkMode() public view returns (bool) {
        return _isFork();
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

    function encodeInsuranceData(
        string memory instrumentName,
        string memory contractsAmount,
        string memory pricePerContract,
        uint256 signedBtcPrice,
        uint256 deribitBtcPrice
    ) public pure returns (bytes memory) {
        return abi.encode(instrumentName, contractsAmount, pricePerContract, signedBtcPrice, deribitBtcPrice);
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
        data = encodeInsuranceData(
            INSTRUMENT_NAME, CONTRACTS_AMOUNT, PRICE_PER_CONTRACT, SIGNED_BTC_PRICE, DERIBIT_BTC_PRICE
        );
        return (DEPOSIT_AMT, PREMIUM_AMT, CBBTC_AMT, DURATION_IN_MONTHS, data);
    }

    function _readAddress(string memory contractName) internal view returns (address addr) {
        // Map old lending-pool contract names to new registry paths
        string memory dotPath;
        if (_strEq(contractName, "LendingPool")) {
            dotPath = "lendingPool.pool";
        } else if (_strEq(contractName, "LendingPoolAddressesProvider")) {
            dotPath = "lendingPool.addressesProvider";
        } else if (_strEq(contractName, "AaveOracle")) {
            dotPath = "lendingPool.oracle";
        } else if (_strEq(contractName, "USDC")) {
            dotPath = "tokens.usdc";
        } else {
            revert(string.concat("HelperConfig: unknown LP contract: ", contractName));
        }

        addr = _readDeployment(dotPath);
        require(addr != address(0), string.concat("HelperConfig: empty address for ", dotPath));
    }

    /// @notice Compares two strings for equality
    /// @param a First string
    /// @param b Second string
    /// @return True if the strings are equal
    function _strEq(string memory a, string memory b) internal pure returns (bool) {
        return keccak256(bytes(a)) == keccak256(bytes(b));
    }

    /// @notice Reads address from unified registry at `../deployments/<chainKey>/latest.json`
    /// @param dotPath The dot-path key to read (e.g., "loanProvider.loan", "tokens.usdc")
    /// @return addr The address, or address(0) if not found
    function _readDeployment(string memory dotPath) internal view returns (address addr) {
        string memory path = string.concat(vm.projectRoot(), "/../deployments/", _getChainKey(), "/latest.json");

        try vm.readFile(path) returns (string memory json) {
            string memory jsonKey = string.concat(".", dotPath);
            try vm.parseJsonAddress(json, jsonKey) returns (address parsed) {
                addr = parsed;
            } catch {
                addr = address(0);
            }
        } catch {
            addr = address(0);
        }
    }

    /// @notice Public wrapper to read a lending-pool contract address from the unified registry
    /// @param contractName The contract name key (e.g., "LendingPoolCollateralManager")
    /// @return addr The address from the JSON file
    function readLendingPoolAddress(string memory contractName) public view returns (address addr) {
        return _readAddress(contractName);
    }
}
