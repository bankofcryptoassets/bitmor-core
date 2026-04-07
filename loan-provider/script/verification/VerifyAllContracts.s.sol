// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "forge-std/Script.sol";
import {HelperConfig} from "../HelperConfig.s.sol";

contract VerifyAllContracts is Script {
    struct ContractInfo {
        string name;
        string contractPath;
        address deployedAddress;
    }

    function run() external {
        HelperConfig helperConfig = new HelperConfig();

        uint256 chainId = block.chainid;
        console.log("Verifying contracts for chain ID:", chainId);

        // Build contract list from HelperConfig (reads from unified registry)
        ContractInfo[] memory contracts = _buildContractList(helperConfig);

        // Verify each contract
        _verifyContracts(contracts, chainId);

        console.log("Verification process completed!");
        _logExplorerUrl(chainId);
    }

    function _buildContractList(HelperConfig helperConfig) internal view returns (ContractInfo[] memory contracts) {
        contracts = new ContractInfo[](3);

        // Get addresses from unified registry via HelperConfig
        address loanVaultImpl = helperConfig.getLoanVaultImplementation();
        address loan = helperConfig.getLoan();
        address loanVaultFactory = helperConfig.getLoanVaultFactory();

        // Build contract list - Sourcify auto-detects constructor args
        contracts[0] = ContractInfo({
            name: "LoanVault", contractPath: "src/protocol/LoanVault.sol:LoanVault", deployedAddress: loanVaultImpl
        });

        contracts[1] = ContractInfo({name: "Loan", contractPath: "src/protocol/Loan.sol:Loan", deployedAddress: loan});

        contracts[2] = ContractInfo({
            name: "LoanVaultFactory",
            contractPath: "src/protocol/LoanVaultFactory.sol:LoanVaultFactory",
            deployedAddress: loanVaultFactory
        });
    }

    function _verifyContracts(ContractInfo[] memory contracts, uint256 chainId) internal {
        for (uint256 i = 0; i < contracts.length; i++) {
            _verifyContract(contracts[i], chainId);
        }
    }

    function _verifyContract(ContractInfo memory contractInfo, uint256 chainId) internal {
        console.log("=================================");
        console.log("Verifying contract:", contractInfo.name);
        console.log("Address:", contractInfo.deployedAddress);
        console.log("Contract path:", contractInfo.contractPath);

        string[] memory verifyCommand = _buildVerifyCommand(contractInfo, chainId);

        // Print the full command for debugging
        console.log("Command:");
        for (uint256 i = 0; i < verifyCommand.length; i++) {
            console.log(" ", verifyCommand[i]);
        }

        try vm.ffi(verifyCommand) returns (bytes memory result) {
            string memory output = string(result);
            console.log("Verification result:", output);
            console.log("[SUCCESS] Successfully verified:", contractInfo.name);
        } catch Error(string memory reason) {
            console.log("[FAILED] Verification failed for", contractInfo.name);
            console.log("Reason:", reason);
        } catch (bytes memory lowLevelData) {
            console.log("[FAILED] Verification failed for", contractInfo.name);
            console.log("Low-level error:", string(lowLevelData));
        }

        console.log("=================================");
        console.log("");
    }

    function _buildVerifyCommand(ContractInfo memory contractInfo, uint256 chainId)
        internal
        pure
        returns (string[] memory)
    {
        // For Sourcify: use --chain-id and --verifier sourcify
        // Constructor args are NOT passed for Sourcify - it auto-detects them
        string[] memory cmd = new string[](8);

        cmd[0] = "forge";
        cmd[1] = "verify-contract";
        cmd[2] = vm.toString(contractInfo.deployedAddress);
        cmd[3] = contractInfo.contractPath;
        cmd[4] = "--chain-id";
        cmd[5] = vm.toString(chainId);
        cmd[6] = "--verifier";
        cmd[7] = "sourcify";

        return cmd;
    }

    function _logExplorerUrl(uint256 chainId) internal pure {
        console.log("Verification submitted to Sourcify!");
        console.log("Check verification status on Sourcify:");
        console.log("https://repo.sourcify.dev/");
        console.log("");
        console.log("Also check block explorer:");
        if (chainId == 84532) {
            console.log("https://sepolia.basescan.org/");
        } else if (chainId == 8453) {
            console.log("https://basescan.org/");
        }
    }
}
