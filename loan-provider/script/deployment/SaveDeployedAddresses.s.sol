// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.30;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {DevOpsTools} from "lib/foundry-devops/src/DevOpsTools.sol";
import {HelperConfig} from "../HelperConfig.s.sol";
import {stdJson} from "forge-std/StdJson.sol";

contract SaveDeployedAddresses is Script {
    using stdJson for string;

    string constant JSON_PATH = "./deployments.json";
    HelperConfig helperConfig;

    function run() public {
        // Initialize helper config
        helperConfig = new HelperConfig();

        // Fetch deployed addresses from broadcast files
        address swapAdapterWrapper = _getAddress("UniswapV4SwapAdapterWrapper");
        address loanVault = _getAddress("LoanVault");
        address loan = _getAddress("Loan");
        address loanVaultFactory = _getAddress("LoanVaultFactory");

        // Optional: Mock tokens (may not always be deployed via loan-provider)
        address mockUSDC = _getAddressOptional("MockUSDC");
        address mockCbBTC = _getAddressOptional("MockCbBTC");

        console2.log("=== Deployed Addresses ===");
        console2.log("SwapAdapterWrapper:", swapAdapterWrapper);
        console2.log("LoanVault:", loanVault);
        console2.log("Loan:", loan);
        console2.log("LoanVaultFactory:", loanVaultFactory);
        if (mockUSDC != address(0)) console2.log("MockUSDC:", mockUSDC);
        if (mockCbBTC != address(0)) console2.log("MockCbBTC:", mockCbBTC);

        // Get current network chain ID
        string memory chainId = vm.toString(block.chainid);

        // Build deployment data for current network
        string memory networkDeployment =
            _buildNetworkDeployment(swapAdapterWrapper, loanVault, loan, loanVaultFactory, mockUSDC, mockCbBTC);

        // Read existing JSON file if it exists and build complete structure
        string memory completeJson;
        try vm.readFile(JSON_PATH) returns (string memory existingContent) {
            // File exists, parse and reconstruct with overwritten chain data
            completeJson = _overwriteChainData(existingContent, chainId, networkDeployment);
        } catch {
            // File doesn't exist, create new structure
            completeJson = string.concat('{"deployments":{"', chainId, '":', networkDeployment, "}}");
        }

        // Write the complete JSON structure, overwriting the entire file
        vm.writeJson(completeJson, JSON_PATH);

        console2.log("\nAddresses saved to:", JSON_PATH);
        console2.log("Network:", _getNetworkName(block.chainid));
        console2.log("Chain ID:", chainId);
    }

    function _buildNetworkDeployment(
        address swapAdapterWrapper,
        address loanVault,
        address loan,
        address loanVaultFactory,
        address mockUSDC,
        address mockCbBTC
    ) internal view returns (string memory) {
        // Build JSON for current network deployment
        string memory json = _buildNetworkInfo();
        json = string.concat(json, _buildDeployedContracts(swapAdapterWrapper, loanVault, loan, loanVaultFactory));
        json = string.concat(json, _buildMockTokens(mockUSDC, mockCbBTC));
        json = string.concat(json, _buildNetworkConfig());
        json = string.concat(json, _buildConstants());
        json = string.concat(json, ',"timestamp":"', vm.toString(block.timestamp), '"}');

        return json;
    }

    function _buildNetworkInfo() internal view returns (string memory) {
        return string.concat('{"network":"', _getNetworkName(block.chainid), '"');
    }

    function _buildDeployedContracts(
        address swapAdapterWrapper,
        address loanVault,
        address loan,
        address loanVaultFactory
    ) internal pure returns (string memory) {
        return string.concat(
            ',"deployedContracts":{',
            '"swapAdapterWrapper":"',
            vm.toString(swapAdapterWrapper),
            '",',
            '"loanVault":"',
            vm.toString(loanVault),
            '",',
            '"loan":"',
            vm.toString(loan),
            '",',
            '"loanVaultFactory":"',
            vm.toString(loanVaultFactory),
            '"',
            "}"
        );
    }

    function _buildMockTokens(address mockUSDC, address mockCbBTC) internal view returns (string memory) {
        if (mockUSDC == address(0) && mockCbBTC == address(0)) {
            return "";
        }

        string memory json = ',"mockTokens":{';

        if (mockUSDC != address(0)) {
            json = string.concat(json, '"USDC":"', vm.toString(mockUSDC), '"');
            if (mockCbBTC != address(0)) {
                json = string.concat(json, ",");
            }
        }

        if (mockCbBTC != address(0)) {
            json = string.concat(json, '"cbBTC":"', vm.toString(mockCbBTC), '"');
        }

        return string.concat(json, "}");
    }

    function _buildNetworkConfig() internal view returns (string memory) {
        (
            address bitmorPool,
            address aaveV3Pool,
            address aaveAddressesProvider,
            address oracle,
            address collateralAsset,
            address debtAsset,
            address getSwapAdapterWrapper,
            address zQuoter,
            address premiumCollector,
            uint256 preClosureFeeBps,
            uint256 gracePeriod
        ) = helperConfig.networkConfig();

        string memory json = string.concat(
            ',"networkConfig":{',
            '"bitmorPool":"',
            vm.toString(bitmorPool),
            '",',
            '"aaveV3Pool":"',
            vm.toString(aaveV3Pool),
            '",',
            '"aaveAddressesProvider":"',
            vm.toString(aaveAddressesProvider),
            '",',
            '"oracle":"',
            vm.toString(oracle),
            '",'
        );

        json = string.concat(
            json,
            '"collateralAsset":"',
            vm.toString(collateralAsset),
            '",',
            '"debtAsset":"',
            vm.toString(debtAsset),
            '",',
            '"swapAdapterWrapper":"',
            vm.toString(getSwapAdapterWrapper),
            '",',
            '"zQuoter":"',
            vm.toString(zQuoter),
            '",'
        );

        return string.concat(
            json,
            '"premiumCollector":"',
            vm.toString(premiumCollector),
            '",',
            '"preClosureFeeBps":',
            vm.toString(preClosureFeeBps),
            '",',
            '"gracePeriod":',
            vm.toString(gracePeriod),
            "}"
        );
    }

    function _buildConstants() internal view returns (string memory) {
        (uint256 depositAmt, uint256 premiumAmt, uint256 collateralAmt, uint256 durationInMonths, uint256 insuranceId) =
            helperConfig.getLoanConfig();

        string memory json = string.concat(
            ',"constants":{',
            '"decimalUSDC":',
            vm.toString(helperConfig.DECIMAL_USDC()),
            ",",
            '"decimalCbBTC":',
            vm.toString(helperConfig.DECIMAL_CBBTC()),
            ",",
            '"depositAmt":"',
            vm.toString(depositAmt),
            '",',
            '"premiumAmt":"',
            vm.toString(premiumAmt),
            '",'
        );

        json = string.concat(
            json,
            '"collateralAmt":"',
            vm.toString(collateralAmt),
            '",',
            '"durationInMonths":',
            vm.toString(durationInMonths),
            ",",
            '"preClosureFee":',
            vm.toString(helperConfig.getPreClosureFee()),
            ",",
            '"insuranceId":',
            vm.toString(insuranceId),
            ","
        );

        return string.concat(
            json,
            '"bitmorOwner":"',
            vm.toString(helperConfig.BITMOR_OWNER()),
            '",',
            '"bitmorUser":"',
            vm.toString(helperConfig.BITMOR_USER()),
            '"',
            "}"
        );
    }

    function _getAddress(string memory contractName) internal view returns (address) {
        return DevOpsTools.get_most_recent_deployment(contractName, block.chainid);
    }

    function _getAddressOptional(string memory contractName) internal view returns (address) {
        // Check if broadcast file exists before attempting to get deployment
        try vm.readFile(
            string.concat(
                vm.projectRoot(), "/broadcast/DeployMockTokens.s.sol/", vm.toString(block.chainid), "/run-latest.json"
            )
        ) returns (
            string memory
        ) {
            // File exists, try to get the deployment
            return DevOpsTools.get_most_recent_deployment(contractName, block.chainid);
        } catch {
            // File doesn't exist, contract not deployed
            return address(0);
        }
    }

    function _overwriteChainData(string memory existingContent, string memory chainId, string memory newDeployment)
        internal
        pure
        returns (string memory)
    {
        // Check if the file uses the proper "deployments" wrapper structure
        int256 deploymentsPos = _indexOf(existingContent, '"deployments":{');

        if (deploymentsPos >= 0) {
            // Proper structure exists, look for chain within deployments
            int256 chainIdPosition = _indexOf(existingContent, string.concat('"', chainId, '":'));

            if (chainIdPosition >= 0) {
                // Chain exists, replace its data completely
                bytes memory searchPattern = bytes(string.concat('"', chainId, '":'));
                uint256 startPos = uint256(chainIdPosition) + searchPattern.length;
                uint256 endPos = _findObjectEnd(existingContent, startPos);

                string memory beforePart =
                    _substring(existingContent, 0, uint256(chainIdPosition) + searchPattern.length);
                string memory afterPart = _substring(existingContent, endPos, bytes(existingContent).length);

                return string.concat(beforePart, newDeployment, afterPart);
            } else {
                // Chain doesn't exist in deployments, add it
                uint256 insertPos = uint256(deploymentsPos) + bytes('"deployments":{').length;
                string memory beforePart = _substring(existingContent, 0, insertPos);
                string memory afterPart = _substring(existingContent, insertPos, bytes(existingContent).length);

                bytes memory afterBytes = bytes(afterPart);
                bool isEmpty = afterBytes.length > 0 && afterBytes[0] == "}";

                if (isEmpty) {
                    return string.concat(beforePart, '"', chainId, '":', newDeployment, afterPart);
                } else {
                    return string.concat(beforePart, '"', chainId, '":', newDeployment, ",", afterPart);
                }
            }
        } else {
            // No "deployments" wrapper, create new structure with proper format
            // This handles legacy format or first-time setup
            return string.concat('{"deployments":{"', chainId, '":', newDeployment, "}}");
        }
    }

    function _indexOf(string memory haystack, string memory needle) internal pure returns (int256) {
        bytes memory haystackBytes = bytes(haystack);
        bytes memory needleBytes = bytes(needle);

        if (needleBytes.length > haystackBytes.length) {
            return -1;
        }

        for (uint256 i = 0; i <= haystackBytes.length - needleBytes.length; i++) {
            bool found = true;
            for (uint256 j = 0; j < needleBytes.length; j++) {
                if (haystackBytes[i + j] != needleBytes[j]) {
                    found = false;
                    break;
                }
            }
            if (found) {
                return int256(i);
            }
        }

        return -1;
    }

    function _substring(string memory str, uint256 start, uint256 end) internal pure returns (string memory) {
        bytes memory strBytes = bytes(str);
        bytes memory result = new bytes(end - start);

        for (uint256 i = start; i < end; i++) {
            result[i - start] = strBytes[i];
        }

        return string(result);
    }

    function _findObjectEnd(string memory json, uint256 startPos) internal pure returns (uint256) {
        bytes memory jsonBytes = bytes(json);
        uint256 braceCount = 0;
        bool inString = false;
        bool escaped = false;

        for (uint256 i = startPos; i < jsonBytes.length; i++) {
            bytes1 char = jsonBytes[i];

            if (escaped) {
                escaped = false;
                continue;
            }

            if (char == "\\") {
                escaped = true;
                continue;
            }

            if (char == '"' && !escaped) {
                inString = !inString;
                continue;
            }

            if (!inString) {
                if (char == "{") {
                    braceCount++;
                } else if (char == "}") {
                    if (braceCount == 0) {
                        return i;
                    }
                    braceCount--;
                }
            }
        }

        return jsonBytes.length;
    }

    function _getNetworkName(uint256 chainId) internal pure returns (string memory) {
        if (chainId == 84532) {
            return "base-sepolia";
        } else if (chainId == 8453) {
            return "base";
        } else if (chainId == 11155111) {
            return "sepolia";
        } else if (chainId == 1) {
            return "mainnet";
        } else if (chainId == 31337 || chainId == 1337) {
            return "localhost";
        } else {
            return "unknown";
        }
    }
}
