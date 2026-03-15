// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script, console2} from "forge-std/Script.sol";

/**
 * @title DeployLibraries
 * @author Bitmor Protocol
 * @notice Deploys all public linked libraries required by Loan.sol
 * @dev Run before DeployPhase3 scripts. Writes addresses to deployments.json.
 *      Uses raw CREATE opcode since Solidity does not support `new` for libraries.
 *
 * Usage (local):
 *   FOUNDRY_PROFILE=local forge script script/deployment/DeployLibraries.s.sol:DeployLibraries \
 *     --rpc-url $RPC_URL --private-key $PRIVATE_KEY --broadcast -v
 *
 * Usage (mainnet):
 *   forge script script/deployment/DeployLibraries.s.sol:DeployLibraries \
 *     --rpc-url $RPC_URL --account bitmor_owner --broadcast --verify -v
 */
contract DeployLibraries is Script {
    function run() external {
        vm.startBroadcast();

        address loanLogic = _deployLibrary("LoanLogic");
        address repayLogic = _deployLibrary("RepayLogic");
        address closeLoanLogic = _deployLibrary("CloseLoanLogic");
        address flashLoanLogic = _deployLibrary("FlashLoanLogic");

        vm.stopBroadcast();

        console2.log("LoanLogic:", loanLogic);
        console2.log("RepayLogic:", repayLogic);
        console2.log("CloseLoanLogic:", closeLoanLogic);
        console2.log("FlashLoanLogic:", flashLoanLogic);

        _saveToDeployments(loanLogic, repayLogic, closeLoanLogic, flashLoanLogic);

        console2.log("Library addresses saved to deployments.json");
    }

    function _deployLibrary(string memory name) internal returns (address deployed) {
        bytes memory bytecode = vm.getCode(string.concat(name, ".sol:", name));
        assembly {
            deployed := create(0, add(bytecode, 0x20), mload(bytecode))
        }
        require(deployed != address(0), string.concat("Failed to deploy ", name));
    }

    function _saveToDeployments(address loanLogic, address repayLogic, address closeLoanLogic, address flashLoanLogic)
        internal
    {
        string memory json = vm.readFile("deployments.json");
        string memory chainId = vm.toString(block.chainid);
        string memory base = string.concat(".deployments.", chainId, ".networkConfig");

        // Chunk 1: Core Phase 1 addresses
        string memory keys = _readChunk1(json, base);
        // Chunk 2: Protocol addresses + oracles
        keys = string.concat(keys, _readChunk2(json, base));
        // Chunk 3: Library addresses
        keys = string.concat(
            keys,
            ',"loanLogicLib":"',
            vm.toString(loanLogic),
            '","repayLogicLib":"',
            vm.toString(repayLogic),
            '","closeLoanLogicLib":"',
            vm.toString(closeLoanLogic),
            '","flashLoanLogicLib":"',
            vm.toString(flashLoanLogic),
            '"'
        );

        string memory networkName = block.chainid == 31337 ? "localhost" : "base";

        vm.writeFile(
            "deployments.json",
            string.concat(
                '{"deployments":{"', chainId, '":{"network":"', networkName, '","networkConfig":{', keys, "}}}}"
            )
        );
    }

    function _readChunk1(string memory json, string memory base) internal returns (string memory) {
        return string.concat(
            '"accessManager":"',
            vm.toString(vm.parseJsonAddress(json, string.concat(base, ".accessManager"))),
            '","collateralAsset":"',
            vm.toString(vm.parseJsonAddress(json, string.concat(base, ".collateralAsset"))),
            '","btcVaultImpl":"',
            vm.toString(vm.parseJsonAddress(json, string.concat(base, ".btcVaultImpl"))),
            '","debtAsset":"',
            vm.toString(vm.parseJsonAddress(json, string.concat(base, ".debtAsset"))),
            '"'
        );
    }

    function _readChunk2(string memory json, string memory base) internal returns (string memory) {
        string memory keys = string.concat(
            ',"cbBTC":"',
            vm.toString(vm.parseJsonAddress(json, string.concat(base, ".cbBTC"))),
            '","btc":"',
            vm.toString(vm.parseJsonAddress(json, string.concat(base, ".btc"))),
            '","aaveV3Pool":"',
            vm.toString(vm.parseJsonAddress(json, string.concat(base, ".aaveV3Pool"))),
            '","aaveAddressesProvider":"',
            vm.toString(vm.parseJsonAddress(json, string.concat(base, ".aaveAddressesProvider"))),
            '"'
        );

        // Optional oracle fields (local only)
        try vm.parseJsonAddress(json, string.concat(base, ".btcOracle")) returns (address parsed) {
            keys = string.concat(keys, ',"btcOracle":"', vm.toString(parsed), '"');
        } catch {}
        try vm.parseJsonAddress(json, string.concat(base, ".usdcOracle")) returns (address parsed) {
            keys = string.concat(keys, ',"usdcOracle":"', vm.toString(parsed), '"');
        } catch {}

        return keys;
    }
}
