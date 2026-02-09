// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script} from "forge-std/Script.sol";

contract HelperConfig is Script {
    // ============ Chain ID Constants ============

    uint256 public constant CHAIN_ID_LOCAL = 31337;
    uint256 public constant CHAIN_ID_BASE_SEPOLIA = 84532;
    uint256 public constant CHAIN_ID_BASE_MAINNET = 8453;

    // ============ Base Mainnet Addresses ============
    // Source: https://github.com/Uniswap/universal-router/tree/main/deploy-addresses
    // https://basescan.org/address/0x0d5e0f971ed27fbff6c2837bf31316121532048d
    // https://docs.uniswap.org/contracts/v4/deployments

    address constant UNIVERSAL_ROUTER_BASE_MAINNET = 0x6fF5693b99212Da76ad316178A184AB56D299b43;
    address constant V4_QUOTER_BASE_MAINNET = 0x0d5e0F971ED27FBfF6c2837bf31316121532048D;

    // ============ Base Sepolia Addresses ============

    address constant UNIVERSAL_ROUTER_BASE_SEPOLIA = 0x95273d871c8156636e114b63797d78D7E1720d81;
    address constant V4_QUOTER_BASE_SEPOLIA = 0x4A6513c898fe1B2d0E78d3b0e0A4a151589B1cBa;

    // ============ Public Getters ============

    /// @notice Returns network name for current chain
    function getCurrentNetworkName() public view returns (string memory) {
        if (block.chainid == CHAIN_ID_LOCAL) return "local";
        if (block.chainid == CHAIN_ID_BASE_SEPOLIA) return "base-sepolia";
        if (block.chainid == CHAIN_ID_BASE_MAINNET) return "base-mainnet";
        return "unknown";
    }

    /// @notice Returns Universal Router address for current chain
    function getUniversalRouter() public view returns (address) {
        if (block.chainid == CHAIN_ID_BASE_MAINNET) return UNIVERSAL_ROUTER_BASE_MAINNET;
        if (block.chainid == CHAIN_ID_BASE_SEPOLIA) return UNIVERSAL_ROUTER_BASE_SEPOLIA;
        return _readDeployment("universalRouter");
    }

    /// @notice Returns V4 Quoter address for current chain
    function getV4Quoter() public view returns (address) {
        if (block.chainid == CHAIN_ID_BASE_MAINNET) return V4_QUOTER_BASE_MAINNET;
        if (block.chainid == CHAIN_ID_BASE_SEPOLIA) return V4_QUOTER_BASE_SEPOLIA;
        return _readDeployment("v4Quoter");
    }

    // ============ Internal ============

    /// @notice Reads address from deployments.json for local chain
    function _readDeployment(string memory key) internal view returns (address addr) {
        string memory path = string.concat(vm.projectRoot(), "/deployments.json");

        try vm.readFile(path) returns (string memory json) {
            string memory jsonKey = string.concat(
                ".deployments.",
                vm.toString(block.chainid),
                ".contracts.",
                key
            );

            try vm.parseJsonAddress(json, jsonKey) returns (address parsed) {
                addr = parsed;
            } catch {
                addr = address(0);
            }
        } catch {
            addr = address(0);
        }
    }
}
