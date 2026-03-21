// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {console2} from "forge-std/console2.sol";
import {InteractionBase} from "./InteractionBase.s.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

/// @title FundUser_USDC
/// @notice Funds the broadcaster with USDC (deal on Anvil, skip on live)
/// @dev Override amount with AMOUNT env var, target with TARGET env var
contract FundUser_USDC is InteractionBase {
    function run() public {
        _preflight();

        uint256 amount = vm.envOr("AMOUNT", uint256(100_000e6));
        address target = vm.envOr("TARGET", msg.sender);

        _fundWithUSDC(target, amount);
        console2.log("USDC balance:", IERC20(_usdc).balanceOf(target));
    }
}

/// @title FundUser_CbBTC
/// @notice Funds the broadcaster with cbBTC (deal on Anvil, skip on live)
contract FundUser_CbBTC is InteractionBase {
    function run() public {
        _preflight();

        uint256 amount = vm.envOr("AMOUNT", uint256(10e8));
        address target = vm.envOr("TARGET", msg.sender);

        _fundWithCbBTC(target, amount);
        console2.log("cbBTC balance:", IERC20(_cbBTC).balanceOf(target));
    }
}

/// @title SeedLendingPool
/// @notice Seeds the Bitmor lending pool with USDC for flash loan liquidity
/// @dev Uses whale broadcast + USDCVault.deposit on fork, deal + prank + USDCVault.deposit on local.
///      Default: 500K USDC (whale has ~$779K). USDCVault splits ~80% Aave / ~20% BLP.
contract SeedLendingPool is InteractionBase {
    function run() public {
        _preflight();

        uint256 amount = vm.envOr("AMOUNT", uint256(100_000e6));
        _seedLendingPoolUSDC(amount);
    }
}
