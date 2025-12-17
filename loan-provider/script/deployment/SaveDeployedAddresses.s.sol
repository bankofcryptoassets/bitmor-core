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

        // Write deployment data for current chain
        // Use vm.writeFile to create proper JSON structure
        string memory fullJson = string.concat('{"deployments":{"', chainId, '":', networkDeployment, "}}");

        // Check if file exists and merge with existing data
        try vm.readFile(JSON_PATH) returns (string memory existingContent) {
            // Parse existing JSON to preserve other chain deployments
            fullJson = _mergeChainData(existingContent, chainId, networkDeployment);
        } catch {
            // File doesn't exist, use new structure
        }

        vm.writeFile(JSON_PATH, fullJson);

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
        json = string.concat(json, ',"timestamp":"', vm.toString(block.timestamp), '"');
        json = string.concat(json, ',"blockNumber":"', vm.toString(block.number), '"}');

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

    function _buildMockTokens(address mockUSDC, address mockCbBTC) internal pure returns (string memory) {
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
            uint256 gracePeriod,
            uint256 liquidationBuffer
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
            '"preClosureFeeBps":"',
            vm.toString(preClosureFeeBps),
            '",',
            '"gracePeriod":"',
            vm.toString(gracePeriod),
            '",',
            '"liquidationBuffer":"',
            vm.toString(liquidationBuffer),
            '"}'
        );
    }

    function _buildConstants() internal view returns (string memory) {
        (uint256 depositAmt, uint256 premiumAmt, uint256 collateralAmt, uint256 durationInMonths, bytes memory data) =
            helperConfig.getLoanConfig();

        string memory json = string.concat(
            ',"constants":{',
            '"decimalUSDC":"',
            vm.toString(helperConfig.DECIMAL_USDC()),
            '",',
            '"decimalCbBTC":"',
            vm.toString(helperConfig.DECIMAL_CBBTC()),
            '",',
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
            '"durationInMonths":"',
            vm.toString(durationInMonths),
            '",',
            '"preClosureFee":"',
            vm.toString(helperConfig.getPreClosureFee()),
            '",',
            '"data":"',
            vm.toString(data),
            '",'
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

    function _mergeChainData(string memory existingContent, string memory chainId, string memory newDeployment)
        internal
        pure
        returns (string memory)
    {
        // Check if existing content has proper deployments structure
        if (bytes(existingContent).length == 0) {
            return string.concat('{"deployments":{"', chainId, '":', newDeployment, "}}");
        }

        // For simplicity in this case, we'll replace entire file content with new deployment
        // In a production system, you might want more sophisticated JSON parsing
        return string.concat('{"deployments":{"', chainId, '":', newDeployment, "}}");
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
