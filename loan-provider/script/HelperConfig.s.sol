// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.30;

import {stdJson} from "forge-std/StdJson.sol";
import {Script} from "forge-std/Script.sol";
import {DevOpsTools} from "lib/foundry-devops/src/DevOpsTools.sol";
import {IPriceOracleGetter} from "@bitmor/interfaces/IPriceOracleGetter.sol";

contract HelperConfig is Script {
    using stdJson for string;

    struct NetworkConfig {
        address bitmorPool;
        address aaveV3Pool;
        address aaveAddressesProvider;
        address oracle;
        address collateralAsset;
        address debtAsset;
        address getSwapAdapterWrapper;
        address zQuoter;
        address premiumCollector;
        uint256 preClosureFeeBps;
    }

    NetworkConfig public networkConfig;

    uint256 constant CHAIN_ID_BASE_SEPOLIA = 84532;
    uint256 public constant DECIMAL_USDC = 1e6;
    uint256 public constant DECIMAL_CBBTC = 1e8;
    uint256 constant DEPOSIT_AMT = 1e8 * DECIMAL_USDC;
    uint256 constant PREMIUM_AMT = 5_000 * DECIMAL_USDC;
    uint256 constant COLLATERL_AMT = 1e8 * DECIMAL_CBBTC;
    uint256 constant DURATION_IN_MONTHS = 12;
    uint256 constant PRE_CLOSURE_FEE = 10; // in bps = 0.1%
    uint256 constant INSURANCE_ID = 1;
    uint256 constant MAX_LOAN_AMOUNT_BASE_SEPOLIA = 70_000 * DECIMAL_USDC;
    address constant AAVE_V3_POOL_BASE_SEPOLIA = 0xcFc53C27C1b813066F22D2fa70C3D0b4CAa70b7B;
    address constant AAVE_V3_ADDRESSES_PROVIDER = address(0);
    address constant SWAP_ADAPTER_BASE_SEPOLIA = 0x9d1b904192209b9Ab2aB8D79Bd8C46cF4dFA7785;
    address constant ZQUOTER_BASE_SEPOLIA = address(0);
    address public constant BITMOR_OWNER = 0x30fF6c272f2F427CcC81cb7fB14F5AFB94fF9Ad6; // bitmor_owner
    address public constant BITMOR_USER = 0xAe773320F12d18c93acAA4C2054340620b748E3a; // bitmor_user

    constructor() {
        if (block.chainid == CHAIN_ID_BASE_SEPOLIA) {
            networkConfig = getBaseSepoliaNetworkConfig();
        }
    }

    function getBaseSepoliaNetworkConfig() public returns (NetworkConfig memory config) {
        config = NetworkConfig({
            bitmorPool: getBitmorPool(),
            aaveV3Pool: getAaveV3Pool(),
            aaveAddressesProvider: getAaveAddressesProvider(),
            oracle: getOracle(),
            collateralAsset: getCollateralAsset(),
            debtAsset: getDebtAsset(),
            getSwapAdapterWrapper: getSwapAdapterWrapper(),
            zQuoter: getZQuoter(),
            premiumCollector: getPremiumCollector(),
            preClosureFeeBps: getPreClosureFee()
        });
    }

    function getPremiumCollector() public returns (address) {
        return makeAddr("premium");
    }

    function getPreClosureFee() public pure returns (uint256) {
        return PRE_CLOSURE_FEE;
    }

    function getBitmorPool() public view returns (address) {
        string memory contractName = "LendingPool";
        return _readAddress(contractName);
    }

    function getAaveV3Pool() public view returns (address) {
        if (block.chainid == CHAIN_ID_BASE_SEPOLIA) {
            return AAVE_V3_POOL_BASE_SEPOLIA;
        }
    }

    function getAaveAddressesProvider() public view returns (address) {
        if (block.chainid == CHAIN_ID_BASE_SEPOLIA) {
            return AAVE_V3_ADDRESSES_PROVIDER;
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

    function getSwapAdapter() public view returns (address) {
        if (block.chainid == CHAIN_ID_BASE_SEPOLIA) {
            return SWAP_ADAPTER_BASE_SEPOLIA;
        }
    }

    function getSwapAdapterWrapper() public view returns (address) {
        try
            vm.readFile(
                string.concat(
                    vm.projectRoot(),
                    "/broadcast/DeploySwapAdapterWrapper.s.sol/",
                    vm.toString(block.chainid),
                    "/run-latest.json"
                )
            )
        returns (string memory) {
            // If file exists, try to get the deployment
            return
                DevOpsTools.get_most_recent_deployment(
                    "UniswapV4SwapAdapterWrapper",
                    block.chainid
                );
        } catch {
            return address(0); // Not deployed yet
        }
    }

    function getZQuoter() public view returns (address) {
        if (block.chainid == CHAIN_ID_BASE_SEPOLIA) {
            return ZQUOTER_BASE_SEPOLIA;
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
            uint256 insuranceID
        )
    {
        return (DEPOSIT_AMT, PREMIUM_AMT, COLLATERL_AMT, DURATION_IN_MONTHS, INSURANCE_ID);
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
        } else if (block.chainid == 31337 || block.chainid == 1337) {
            network = "hardhat";
        } else {
            revert("HelperConfig: unsupported chainid for deployed-contracts.json");
        }

        // Read the JSON file from repo root
        string memory path = string.concat(
            vm.projectRoot(),
            "/../lending-pool/deployed-contracts.json"
        );
        string memory json = vm.readFile(path);

        // Build jsonpath like: .LendingPool.sepolia.address
        string memory key = string.concat(".", contractName, ".", network, ".address");

        // Parse and return
        addr = json.readAddress(key);
        require(addr != address(0), "HelperConfig: empty address in deployed-contracts.json");
    }
}
