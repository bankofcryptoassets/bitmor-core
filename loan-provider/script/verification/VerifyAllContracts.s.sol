// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "forge-std/Script.sol";
import "forge-std/StdJson.sol";

contract VerifyAllContracts is Script {
    using stdJson for string;

    struct ContractInfo {
        string name;
        string contractPath;
        address deployedAddress;
    }

    function run() external {
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/deployments.json");
        string memory json = vm.readFile(path);

        // Get chain ID from environment
        uint256 chainId = block.chainid;
        string memory chainIdStr = vm.toString(chainId);

        console.log("Verifying contracts for chain ID:", chainId);

        // Parse deployed contracts for the current chain
        string memory deploymentsPath = string.concat(".deployments.", chainIdStr, ".deployedContracts");

        // Get all contract addresses
        string memory swapAdapterWrapper = json.readString(string.concat(deploymentsPath, ".swapAdapterWrapper"));
        string memory loanVault = json.readString(string.concat(deploymentsPath, ".loanVault"));
        string memory loan = json.readString(string.concat(deploymentsPath, ".loan"));
        string memory loanVaultFactory = json.readString(string.concat(deploymentsPath, ".loanVaultFactory"));

        // Create contract info array
        ContractInfo[] memory contracts = new ContractInfo[](4);

        contracts[0] = ContractInfo({
            name: "SwapAdapterWrapper",
            contractPath: "src/dependencies/swap-adapter/SwapAdapterWrapper.sol:SwapAdapterWrapper",
            deployedAddress: vm.parseAddress(swapAdapterWrapper)
        });

        contracts[1] = ContractInfo({
            name: "LoanVault",
            contractPath: "src/loan/LoanVault.sol:LoanVault",
            deployedAddress: vm.parseAddress(loanVault)
        });

        contracts[2] = ContractInfo({
            name: "Loan", contractPath: "src/loan/Loan.sol:Loan", deployedAddress: vm.parseAddress(loan)
        });

        contracts[3] = ContractInfo({
            name: "LoanVaultFactory",
            contractPath: "src/loan/LoanVaultFactory.sol:LoanVaultFactory",
            deployedAddress: vm.parseAddress(loanVaultFactory)
        });

        // Verify each contract
        for (uint256 i = 0; i < contracts.length; i++) {
            ContractInfo memory contractInfo = contracts[i];

            console.log("=================================");
            console.log("Verifying contract:", contractInfo.name);
            console.log("Address:", contractInfo.deployedAddress);
            console.log("Contract path:", contractInfo.contractPath);

            // Build verification command
            string[] memory verifyCommand = new string[](8);
            verifyCommand[0] = "forge";
            verifyCommand[1] = "verify-contract";
            verifyCommand[2] = vm.toString(contractInfo.deployedAddress);
            verifyCommand[3] = contractInfo.contractPath;
            verifyCommand[4] = "--chain-id";
            verifyCommand[5] = chainIdStr;
            verifyCommand[6] = "--etherscan-api-key";

            if (chainId == 84532) {
                verifyCommand[7] = "base_sepolia";
            } else if (chainId == 8453) {
                verifyCommand[7] = "base";
            } else {
                // Fallback to environment variable
                verifyCommand[7] = vm.envString("ETHERSCAN_KEY");
            }

            // Execute verification command
            try vm.ffi(verifyCommand) returns (bytes memory result) {
                console.log("Verification result:", string(result));
                console.log("[SUCCESS] Successfully verified:", contractInfo.name);
            } catch Error(string memory reason) {
                console.log("[FAILED] Verification failed for", contractInfo.name);
                console.log("Reason:", reason);
            } catch {
                console.log("[FAILED] Verification failed for", contractInfo.name, "- Unknown error");
            }

            console.log("=================================");
            console.log("");
        }

        console.log("Verification process completed!");
        console.log("Check BaseScan for verification status:");

        if (chainId == 84532) {
            console.log("https://sepolia.basescan.org/");
        } else if (chainId == 8453) {
            console.log("https://basescan.org/");
        }
    }
}
