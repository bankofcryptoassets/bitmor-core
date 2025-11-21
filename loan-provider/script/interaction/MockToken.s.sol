// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.30;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {HelperConfig} from "../HelperConfig.s.sol";
import {IERC20} from "@bitmor/dependencies/openzeppelin/IERC20.sol";
import {MintableERC20} from "@bitmor/mocks/MintableERC20.sol";
import {ILendingPool} from "@bitmor/interfaces/ILendingPool.sol";
import {ILendingPoolAddressesProvider} from "@bitmor/interfaces/ILendingPoolAddressesProvider.sol";

struct ConfiguratorInitInput {
    address aTokenImpl;
    address stableDebtTokenImpl;
    address variableDebtTokenImpl;
    uint8 underlyingAssetDecimals;
    address interestRateStrategyAddress;
    address underlyingAsset;
    address treasury;
    address incentivesController;
    string underlyingAssetName;
    string aTokenName;
    string aTokenSymbol;
    string variableDebtTokenName;
    string variableDebtTokenSymbol;
    string stableDebtTokenName;
    string stableDebtTokenSymbol;
    bytes params;
}

interface ILendingPoolConfiguratorLike {
    function batchInitReserve(ConfiguratorInitInput[] calldata input) external;
}

contract MockToken_MintTokens is Script {
    HelperConfig config;

    function _mintTokensUsingConfig(
        address bitmor_owner,
        address bitmor_user,
        address collateralAsset,
        address debtAsset,
        uint256 totalDebtAssetAmount,
        uint256 collateralAmt
    ) internal {
        vm.startBroadcast();

        MintableERC20(collateralAsset).mint(bitmor_owner, collateralAmt * 1e6);
        MintableERC20(collateralAsset).mint(bitmor_user, collateralAmt * 1e6);

        MintableERC20(debtAsset).mint(bitmor_owner, totalDebtAssetAmount * 1e12);
        MintableERC20(debtAsset).mint(bitmor_user, totalDebtAssetAmount * 1e12);

        vm.stopBroadcast();
    }

    function _mintTokens() internal {
        config = new HelperConfig();
        address collateralAsset = config.getCollateralAsset();
        address debtAsset = config.getDebtAsset();
        address bitmor_owner = config.BITMOR_OWNER();
        address bitmor_user = config.BITMOR_USER();

        (uint256 depositAmt, uint256 premiumAmt, uint256 collateralAmt,,) = config.getLoanConfig();

        _mintTokensUsingConfig(
            bitmor_owner, bitmor_user, collateralAsset, debtAsset, depositAmt + premiumAmt, collateralAmt
        );
    }

    function run() public {
        _mintTokens();
    }
}

contract MockToken_AddToLendingPool is Script {
    HelperConfig config;

    function _addToLendingPoolUsingConfig(address debtAsset, address lendingPool, uint256 amount) internal {
        vm.startBroadcast();

        IERC20(debtAsset).approve(lendingPool, amount);

        ILendingPool(lendingPool).deposit(debtAsset, amount, msg.sender, uint16(0));

        vm.stopBroadcast();
    }

    function _addToLendingPool() internal {
        config = new HelperConfig();
        address debtAsset = config.getDebtAsset();
        address lendingPool = config.getBitmorPool();
        uint256 amountToAddInLendingPool = 100_000_000 * config.DECIMAL_USDC();

        _addToLendingPoolUsingConfig(debtAsset, lendingPool, amountToAddInLendingPool);
    }

    function run() public {
        _addToLendingPool();
    }
}

// TODO! : Check the AI implementation
contract MockToken_InitReserves is Script {
    using stdJson for string;

    HelperConfig config;

    address constant TREASURY = 0x464C71f6c2F760DdA6093dCB91C24c39e5d6e18c;
    uint256 constant CHAIN_ID_BASE_SEPOLIA = 84532;

    function _initReserves() internal {
        config = new HelperConfig();

        address provider = config.getAddressesProvider();
        address configurator = ILendingPoolAddressesProvider(provider).getLendingPoolConfigurator();

        address aTokenImpl = _readDeploymentAddress("AToken");
        address stableDebtTokenImpl = _readDeploymentAddress("StableDebtToken");
        address variableDebtTokenImpl = _readDeploymentAddress("VariableDebtToken");
        address rateStrategyUSDC = _readDeploymentAddress("rateStrategyUSDC");
        address rateStrategyCBBTC = _readDeploymentAddress("rateStrategyCBBTC");

        ConfiguratorInitInput[] memory inputs = new ConfiguratorInitInput[](2);
        inputs[0] = _buildInitInput(
            config.getDebtAsset(), "USDC", rateStrategyUSDC, aTokenImpl, stableDebtTokenImpl, variableDebtTokenImpl
        );
        inputs[1] = _buildInitInput(
            config.getCollateralAsset(),
            "cbBTC",
            rateStrategyCBBTC,
            aTokenImpl,
            stableDebtTokenImpl,
            variableDebtTokenImpl
        );

        _initReservesUsingConfig(configurator, inputs);
    }

    function _buildInitInput(
        address underlyingAsset,
        string memory symbol,
        address rateStrategy,
        address aTokenImpl,
        address stableDebtTokenImpl,
        address variableDebtTokenImpl
    ) internal view returns (ConfiguratorInitInput memory) {
        MintableERC20 token = MintableERC20(underlyingAsset);
        string memory stableName = string.concat("Bitmor stable debt bearing ", symbol);
        string memory variableName = string.concat("Bitmor variable debt bearing ", symbol);
        return ConfiguratorInitInput({
            aTokenImpl: aTokenImpl,
            stableDebtTokenImpl: stableDebtTokenImpl,
            variableDebtTokenImpl: variableDebtTokenImpl,
            underlyingAssetDecimals: token.decimals(),
            interestRateStrategyAddress: rateStrategy,
            underlyingAsset: underlyingAsset,
            treasury: TREASURY,
            incentivesController: address(0),
            underlyingAssetName: token.name(),
            aTokenName: string.concat("Bitmor interest bearing ", symbol),
            aTokenSymbol: string.concat("a", symbol),
            variableDebtTokenName: variableName,
            variableDebtTokenSymbol: string.concat("variableDebt", symbol),
            stableDebtTokenName: stableName,
            stableDebtTokenSymbol: string.concat("stableDebt", symbol),
            params: hex"10"
        });
    }

    function _initReservesUsingConfig(address configurator, ConfiguratorInitInput[] memory inputs) internal {
        vm.startBroadcast();
        ILendingPoolConfiguratorLike(configurator).batchInitReserve(inputs);
        vm.stopBroadcast();
    }

    function _readDeploymentAddress(string memory contractName) internal view returns (address addr) {
        string memory network;
        if (block.chainid == CHAIN_ID_BASE_SEPOLIA) {
            network = "sepolia";
        } else if (block.chainid == 31337 || block.chainid == 1337) {
            network = "hardhat";
        } else {
            revert("MockToken_InitReserves: unsupported chain id");
        }

        string memory path = string.concat(vm.projectRoot(), "/deployed-contracts.json");
        string memory json = vm.readFile(path);
        string memory key = string.concat(".", contractName, ".", network, ".address");

        addr = json.readAddress(key);
        require(addr != address(0), "MockToken_InitReserves: deployment not found");
    }

    function run() public {
        _initReserves();
    }
}
