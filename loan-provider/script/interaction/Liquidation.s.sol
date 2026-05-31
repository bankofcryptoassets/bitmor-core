// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {console2} from "forge-std/console2.sol";
import {InteractionBase} from "./InteractionBase.s.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {ILendingPool} from "@bitmor/interfaces/ILendingPool.sol";
import {DataTypes} from "@bitmor/libraries/types/DataTypes.sol";

/// @title Liquidation_LiquidateLSA
/// @notice Liquidates an LSA on the Bitmor Lending Pool (live testnet)
/// @dev Flow: preflight → check liquidation type → read VDT balance → approve → liquidationCall.
///      Set the LSA address via env var: LSA=0x...
///      The broadcaster wallet must already hold enough USDC to cover the debt.
///      Usage: LSA=0x... forge script script/interaction/Liquidation.s.sol:Liquidation_LiquidateLSA --rpc-url base_sepolia --account bitmor_owner --broadcast -vvvv
contract Liquidation_LiquidateLSA is InteractionBase {
    function run() public {
        _preflight();

        address lsa = vm.envAddress("LSA");
        require(lsa != address(0), "LSA env var required");

        ILendingPool pool = ILendingPool(_bitmorPool);

        // 1. Check if LSA is liquidatable (0 = none, 1 = full, 2 = micro)
        uint256 liquidationType = pool.checkTypeOfLiquidation(lsa);
        console2.log("Liquidation type for LSA:", liquidationType);
        require(liquidationType == 1, "LSA is not eligible for full liquidation");

        // 2. Get the variable debt token balance of the LSA
        DataTypes.ReserveData memory reserveData = pool.getReserveData(_usdc);
        address vdt = reserveData.variableDebtTokenAddress;
        require(vdt != address(0), "Variable debt token not found for USDC");

        uint256 debtToCover = IERC20(vdt).balanceOf(lsa);
        console2.log("VDT balance (debtToCover):", debtToCover);
        require(debtToCover > 0, "LSA has no variable debt");

        // 3. Verify liquidator has enough USDC
        uint256 liquidatorBalance = IERC20(_usdc).balanceOf(_broadcaster);
        console2.log("Liquidator USDC balance:", liquidatorBalance);
        require(liquidatorBalance >= debtToCover, "Liquidator has insufficient USDC to cover debt");

        // 4. Approve lending pool and execute liquidation
        vm.startBroadcast();
        IERC20(_usdc).approve(_bitmorPool, debtToCover);
        pool.liquidationCall(_btcVault, _usdc, lsa, debtToCover, false);
        vm.stopBroadcast();

        console2.log("Liquidation executed for LSA:", lsa);
        console2.log("Debt covered:", debtToCover);
    }
}
