// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.30;

import {stdJson} from "forge-std/StdJson.sol";
import {Script} from "forge-std/Script.sol";
import {DevOpsTools} from "lib/foundry-devops/src/DevOpsTools.sol";
import {IPriceOracleGetter} from "@bitmor/interfaces/IPriceOracleGetter.sol";
import {RolesData} from "@bitmor/accessManager/RolesData.sol";

contract HelperConfig is Script, RolesData {
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
        address getSwapAdapterWrapper;
        address zQuoter;
        address premiumCollector;
        uint256 preClosureFeeBps;
        uint256 gracePeriod;
        uint256 liquidationBuffer;
        // Vault test config
        address usdc;
        address usdc_holder;
        uint256 entryFee;
        uint256 exitFee;
    }

    NetworkConfig public networkConfig;

    uint256 public constant CHAIN_ID_LOCAL = 31337;
    uint256 public constant CHAIN_ID_BASE_SEPOLIA = 84532;
    uint256 public constant CHAIN_ID_BASE_MAINNET = 8453;
    uint256 public constant DECIMAL_USDC = 1e6;
    uint256 public constant DECIMAL_CBBTC = 1e8;
    uint256 constant DEPOSIT_AMT = 1e8 * DECIMAL_USDC;
    uint256 constant PREMIUM_AMT = 5_000 * DECIMAL_USDC;
    uint256 constant COLLATERL_AMT = 1e8 * DECIMAL_CBBTC;
    uint256 constant DURATION_IN_MONTHS = 12;
    uint256 constant PRE_CLOSURE_FEE = 10; // in bps = 0.1%
    uint256 constant INSURANCE_ID = 1;
    uint256 constant INITIAL_INSURANCE_ID = 0;
    uint256 constant MAX_LOAN_AMOUNT_BASE_SEPOLIA = 70_000 * DECIMAL_USDC;
    uint256 constant GRACE_PERIOD = 7 days;
    uint256 constant LIQUIDATION_BUFFER = 50; // in bps = 0.5%
    address constant AAVE_V3_POOL_BASE_SEPOLIA = 0xcFc53C27C1b813066F22D2fa70C3D0b4CAa70b7B;
    address constant AAVE_V3_ADDRESSES_PROVIDER = 0x39Eb7Ca3b8f0F29C21a008b1F281b30c4539736a;
    address constant SWAP_ADAPTER_BASE_SEPOLIA = 0x9d1b904192209b9Ab2aB8D79Bd8C46cF4dFA7785;
    address constant ZQUOTER_BASE_SEPOLIA = address(0);
    address public constant BITMOR_OWNER = 0x30fF6c272f2F427CcC81cb7fB14F5AFB94fF9Ad6; // bitmor_owner
    address public constant BITMOR_USER = 0xAe773320F12d18c93acAA4C2054340620b748E3a; // bitmor_user
    address public constant PREMIUM_COLLECTOR = 0x30fF6c272f2F427CcC81cb7fB14F5AFB94fF9Ad6; // bitmor_owner
    bytes public constant DATA = "0xLOAN";
    // USDC on Base Sepolia (Circle's USDC)
    address public constant USDC_BASE_SEPOLIA = 0x036CbD53842c5426634e7929541eC2318f3dCF7e;
    // USDC holder on Base Sepolia (whale address with large USDC balance for fork testing)
    address public constant USDC_HOLDER_BASE_SEPOLIA = 0x4200000000000000000000000000000000000006;
    address public constant BTC_BASE_SEPOLIA = 0x4200000000000000000000000000000000000006;
    // Default vault fees in basis points
    uint256 public constant DEFAULT_ENTRY_FEE = 10; // 0.1%
    uint256 public constant DEFAULT_EXIT_FEE = 10; // 0.1%
    // USDC Strategy allocation config (in basis points)
    uint256 public constant DEFAULT_AAVE_ALLOCATION = 8000; // 80% to Aave
    uint256 public constant DEFAULT_MINIMUM_DELTA_REQUIRED = 100; // 1% minimum delta for reallocation

    /// @notice Returns human-readable network name for a given chain ID
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
    /// @return name The network name for block.chainid
    function getCurrentNetworkName() public view returns (string memory) {
        return getNetworkName(block.chainid);
    }

    constructor() {
        if (block.chainid == CHAIN_ID_LOCAL) {
            networkConfig = getLocalNetworkConfig();
        } else if (block.chainid == CHAIN_ID_BASE_SEPOLIA) {
            networkConfig = getBaseSepoliaNetworkConfig();
        }
    }

    function getBaseSepoliaNetworkConfig() public view returns (NetworkConfig memory config) {
        config = NetworkConfig({
            accessManager: getAccessManager(),
            bitmorPool: getBitmorPool(),
            aaveV3Pool: getAaveV3Pool(),
            aaveAddressesProvider: getAaveAddressesProvider(),
            oracle: getOracle(),
            collateralAsset: getCollateralAsset(),
            debtAsset: getDebtAsset(),
            btc: BTC_BASE_SEPOLIA,
            getSwapAdapterWrapper: getSwapAdapterWrapper(),
            zQuoter: getZQuoter(),
            premiumCollector: getPremiumCollector(),
            preClosureFeeBps: getPreClosureFee(),
            gracePeriod: getGracePeriod(),
            liquidationBuffer: getLiquidationBuffer(),
            usdc: USDC_BASE_SEPOLIA,
            usdc_holder: USDC_HOLDER_BASE_SEPOLIA,
            entryFee: DEFAULT_ENTRY_FEE,
            exitFee: DEFAULT_EXIT_FEE
        });
    }

    /// @notice Returns network config for local Anvil (chainId 31337)
    /// @dev Reads from loan-provider/deployments.json and lending-pool/deployed-contracts.json
    function getLocalNetworkConfig() public view returns (NetworkConfig memory config) {
        // Read from deployments.json (Phase 1 addresses from loan-provider)
        address mockUsdc = _readLocalDeployment("debtAsset");
        address mockCbBTC = _readLocalDeployment("cbBTC");
        address localAccessManager = _readLocalDeployment("accessManager");

        config = NetworkConfig({
            accessManager: localAccessManager,
            bitmorPool: getBitmorPool(),
            aaveV3Pool: _readLocalDeployment("aaveV3Pool"),
            aaveAddressesProvider: address(0), // Not used for local
            oracle: getOracle(),
            collateralAsset: _readLocalDeployment("collateralAsset"), // bvBTC
            debtAsset: mockUsdc,
            btc: mockCbBTC,
            getSwapAdapterWrapper: getSwapAdapterWrapper(),
            zQuoter: address(0), // Not used for local
            premiumCollector: BITMOR_OWNER,
            preClosureFeeBps: getPreClosureFee(),
            gracePeriod: getGracePeriod(),
            liquidationBuffer: getLiquidationBuffer(),
            usdc: mockUsdc,
            usdc_holder: BITMOR_OWNER, // Use owner as USDC holder for local testing
            entryFee: DEFAULT_ENTRY_FEE,
            exitFee: DEFAULT_EXIT_FEE
        });
    }

    function getInitialAdmin() public pure returns (address) {
        return BITMOR_OWNER;
    }

    function getNetworkConfig() public view returns (NetworkConfig memory) {
        return networkConfig;
    }

    function getAccessManager() public view returns (address) {
        string memory contractName = "BitmorAccessManager";
        return _getAddress(contractName);
    }

    function getGracePeriod() public pure returns (uint256) {
        return GRACE_PERIOD;
    }

    function getLiquidationBuffer() public pure returns (uint256) {
        return LIQUIDATION_BUFFER;
    }

    function getPremiumCollector() public pure returns (address) {
        return PREMIUM_COLLECTOR;
    }

    function getPreClosureFee() public pure returns (uint256) {
        return PRE_CLOSURE_FEE;
    }

    function getAaveAllocation() public pure returns (uint256) {
        return DEFAULT_AAVE_ALLOCATION;
    }

    function getMinimumDeltaRequired() public pure returns (uint256) {
        return DEFAULT_MINIMUM_DELTA_REQUIRED;
    }

    function getBitmorPool() public view returns (address) {
        string memory contractName = "LendingPool";
        return _readAddress(contractName);
    }

    function getAaveV3Pool() public view returns (address aavePool) {
        if (block.chainid == CHAIN_ID_LOCAL) {
            // For local: read from deployments.json or return address(0) if using mocks
            aavePool = _readLocalDeployment("aaveV3Pool");
        } else if (block.chainid == CHAIN_ID_BASE_SEPOLIA) {
            aavePool = AAVE_V3_POOL_BASE_SEPOLIA;
        }
    }

    function getAaveAddressesProvider() public view returns (address addressesProvider) {
        if (block.chainid == CHAIN_ID_LOCAL) {
            addressesProvider = address(0); // Not needed for local mock setup
        } else if (block.chainid == CHAIN_ID_BASE_SEPOLIA) {
            addressesProvider = AAVE_V3_ADDRESSES_PROVIDER;
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
        return _getAddress("LoanVault");
    }

    function getLoanVaultFactory() public view returns (address) {
        return _getAddress("LoanVaultFactory");
    }

    function getCollateralAsset() public view returns (address) {
        return _readAddress("bcbBTC");
    }

    function getDebtAsset() public view returns (address) {
        return _readAddress("bUSDC");
    }

    function getSwapAdapter() public view returns (address swapAdapter) {
        if (block.chainid == CHAIN_ID_BASE_SEPOLIA) {
            swapAdapter = SWAP_ADAPTER_BASE_SEPOLIA;
        }
    }

    function getSwapAdapterWrapper() public view returns (address) {
        try vm.readFile(
            string.concat(
                vm.projectRoot(),
                "/broadcast/DeploySwapAdapterWrapper.s.sol/",
                vm.toString(block.chainid),
                "/run-latest.json"
            )
        ) returns (
            string memory
        ) {
            // If file exists, try to get the deployment
            return DevOpsTools.get_most_recent_deployment("UniswapV4SwapAdapterWrapper", block.chainid);
        } catch {
            return address(0); // Not deployed yet
        }
    }

    function getZQuoter() public view returns (address zQuoter) {
        if (block.chainid == CHAIN_ID_BASE_SEPOLIA) {
            zQuoter = ZQUOTER_BASE_SEPOLIA;
        }
    }

    function getLoan() public view returns (address) {
        return _getAddress("Loan");
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
        return (DEPOSIT_AMT, PREMIUM_AMT, COLLATERL_AMT, DURATION_IN_MONTHS, DATA);
    }

    function _getAddress(string memory contractName) internal view returns (address) {
        return DevOpsTools.get_most_recent_deployment(contractName, block.chainid);
    }

    function _readAddress(string memory contractName) internal view returns (address addr) {
        // Map current chain to the key used in deployed-contracts.json
        string memory network;
        if (block.chainid == CHAIN_ID_BASE_SEPOLIA) {
            // Your JSON uses "sepolia" for Base Sepolia deployments
            network = "sepolia";
        } else if (block.chainid == CHAIN_ID_LOCAL || block.chainid == 1337) {
            network = "hardhat";
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

    /// @notice Reads address from loan-provider/deployments.json for local chain
    /// @param key The key to read from networkConfig (e.g., "collateralAsset", "debtAsset")
    function _readLocalDeployment(string memory key) internal view returns (address addr) {
        string memory path = string.concat(vm.projectRoot(), "/deployments.json");

        try vm.readFile(path) returns (string memory json) {
            // Build jsonpath: .deployments.31337.networkConfig.<key>
            string memory jsonKey = string.concat(".deployments.", vm.toString(CHAIN_ID_LOCAL), ".networkConfig.", key);

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
