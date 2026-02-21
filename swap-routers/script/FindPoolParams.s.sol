// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script, console} from "forge-std/Script.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";

/**
 * @title FindPoolParams
 * @notice Script to find the correct pool parameters for USDC/CBBTC on Base
 * @dev Run with: forge script script/FindPoolParams.s.sol --fork-url $BASE_RPC_URL -vvv
 */
contract FindPoolParams is Script {
    using PoolIdLibrary for PoolKey;

    // Known pool ID from GeckoTerminal
    bytes32 constant KNOWN_POOL_ID = 0xdfb2536ba09a004b32db0a1a15f73676b5e356d831c4ea1e843cd9433b080ab6;

    // Base Mainnet tokens (sorted by address)
    address constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address constant CBBTC = 0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf;

    // Dynamic fee flag
    uint24 constant DYNAMIC_FEE_FLAG = 0x800000;

    function run() public view {
        console.log("=== Finding USDC/CBBTC Pool Parameters ===");
        console.log("");
        console.log("Known Pool ID:", vm.toString(KNOWN_POOL_ID));
        console.log("");

        // Verify token ordering
        console.log("Token ordering check:");
        console.log("USDC:", USDC);
        console.log("CBBTC:", CBBTC);
        console.log("USDC < CBBTC:", USDC < CBBTC);
        console.log("");

        // Exhaustive search of all reasonable fee/tickSpacing combinations
        uint24[10] memory fees = [
            uint24(100),
            uint24(500),
            uint24(450),
            uint24(3000),
            uint24(10000),
            DYNAMIC_FEE_FLAG,
            uint24(400),
            uint24(2000),
            uint24(5000),
            uint24(1000)
        ];

        int24[10] memory tickSpacings = [
            int24(1), int24(2), int24(5), int24(10), int24(15), int24(20), int24(50), int24(60), int24(100), int24(200)
        ];

        console.log("Exhaustive search (100 combinations):");
        console.log("");

        bool found = false;
        for (uint256 i = 0; i < fees.length; i++) {
            for (uint256 j = 0; j < tickSpacings.length; j++) {
                bytes32 poolId = _computePoolId(fees[i], tickSpacings[j], address(0));
                if (poolId == KNOWN_POOL_ID) {
                    console.log("!!! MATCH FOUND !!!");
                    console.log("Fee:", fees[i]);
                    console.log("TickSpacing:", uint24(int24(tickSpacings[j])));
                    console.log("Hooks: address(0)");
                    console.log("Pool ID:", vm.toString(poolId));
                    found = true;
                }
            }
        }

        if (!found) {
            console.log("No match found with address(0) hooks.");
            console.log("");
            console.log("The pool likely uses a custom hooks address.");
            console.log("Printing computed pool IDs for reference:");
            console.log("");

            // Print what pool IDs we get with common params
            bytes32 id1 = _computePoolId(DYNAMIC_FEE_FLAG, 200, address(0));
            console.log("Dynamic fee + tickSpacing=200:");
            console.log(vm.toString(id1));

            bytes32 id2 = _computePoolId(3000, 60, address(0));
            console.log("Fee=3000 + tickSpacing=60:");
            console.log(vm.toString(id2));

            bytes32 id3 = _computePoolId(500, 10, address(0));
            console.log("Fee=500 + tickSpacing=10:");
            console.log(vm.toString(id3));

            // This is what the quote function used and worked!
            bytes32 id4 = _computePoolId(3000, 60, address(0));
            console.log("");
            console.log("Quote test used fee=3000, tickSpacing=60. Pool ID:");
            console.log(vm.toString(id4));
            console.log("");
            console.log("Try querying StateView with this pool ID to verify it has liquidity.");
        }
    }

    function _computePoolId(uint24 fee, int24 tickSpacing, address hooks) internal pure returns (bytes32) {
        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(USDC),
            currency1: Currency.wrap(CBBTC),
            fee: fee,
            tickSpacing: tickSpacing,
            hooks: IHooks(hooks)
        });
        return PoolId.unwrap(key.toId());
    }

    function _testAndLog(uint24 fee, int24 tickSpacing, address hooks) internal view {
        bytes32 poolId = _computePoolId(fee, tickSpacing, hooks);
        bool isMatch = poolId == KNOWN_POOL_ID;

        if (isMatch) {
            console.log("!!! MATCH FOUND !!!");
            console.log("Fee:", fee);
            console.log("TickSpacing:", uint24(int24(tickSpacing)));
            console.log("Pool ID:", vm.toString(poolId));
        } else {
            console.log("Fee:", fee);
            console.log("TickSpacing:", uint24(int24(tickSpacing)));
            console.log("No match");
        }
        console.log("");
    }
}
