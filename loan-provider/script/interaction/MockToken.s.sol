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

contract MockToken_MintTokens is Script {
    HelperConfig config;

    function _mintTokensUsingConfig(
        address collateralAsset,
        address debtAsset,
        uint256 debtAssetAmt,
        uint256 collateralAssetAmt
    ) internal {
        vm.startBroadcast();
        (bool success,) = debtAsset.call(abi.encodeWithSignature("mint(uint256)", debtAssetAmt));
        if (!success) revert();

        (success,) = collateralAsset.call(abi.encodeWithSignature("mint(uint256)", collateralAssetAmt));
        if (!success) revert();

        vm.stopBroadcast();
    }

    function _mintTokens() internal {
        config = new HelperConfig();
        address collateralAsset = config.getCollateralAsset();
        address debtAsset = config.getDebtAsset();

        (uint256 depositAmt, uint256 premiumAmt, uint256 collateralAmt,,) = config.getLoanConfig();

        _mintTokensUsingConfig(collateralAsset, debtAsset, depositAmt + premiumAmt, collateralAmt);
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
