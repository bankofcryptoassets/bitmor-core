// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script, console2} from "forge-std/Script.sol";

/**
 * @title DeployLibraries
 * @author Bitmor Protocol
 * @notice Deploys all public linked libraries required by Loan.sol
 * @dev Run before DeployPhase3 scripts. Address persistence is handled externally
 *      by the bitmor-deploy CLI tool, which reads Forge broadcast files.
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
    }

    function _deployLibrary(string memory name) internal returns (address deployed) {
        bytes memory bytecode = vm.getCode(string.concat(name, ".sol:", name));
        assembly {
            deployed := create(0, add(bytecode, 0x20), mload(bytecode))
        }
        require(deployed != address(0), string.concat("Failed to deploy ", name));
    }
}
