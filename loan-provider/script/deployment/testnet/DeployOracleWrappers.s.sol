// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script, console2} from "forge-std/Script.sol";
import {ChainlinkOracleWrapper} from "../../../test/mock/ChainlinkOracleWrapper.sol";
import {DeploymentConstants} from "../DeploymentConstants.sol";
import {HelperConfig} from "../../HelperConfig.s.sol";

/// @title IAaveOracleSetSources
/// @dev Minimal interface for AaveOracle.setAssetSources (Solidity 0.6.12 contract)
interface IAaveOracleSetSources {
    function setAssetSources(address[] calldata assets, address[] calldata sources) external;
    function getSourceOfAsset(address asset) external view returns (address);
}

/**
 * @title DeployOracleWrappers
 * @author Bitmor Protocol
 * @notice Deploys ChainlinkOracleWrapper contracts and wires them into the existing AaveOracle
 * @dev One-off migration script for Base Sepolia testnet. Replaces static MockChainlinkOracle
 *      sources with wrappers around real Chainlink feeds that support price overrides.
 *
 *      Prerequisites:
 *      - Full testnet deployment already completed (Phases 1-3)
 *      - Caller must be the AaveOracle owner (deployer / bitmor_owner)
 *
 *      Usage:
 *        FOUNDRY_PROFILE=testnet forge script script/deployment/testnet/DeployOracleWrappers.s.sol:DeployOracleWrappers \
 *          --rpc-url $BASE_SEPOLIA_RPC_URL --account bitmor_owner --broadcast --slow -v
 *
 *      After running, update the registry:
 *        bitmor_deploy save --chain 84532 --phase oracle-wrappers --script DeployOracleWrappers --env testnet
 *
 * @custom:security Testnet only. Wrappers have no access control on price overrides.
 */
contract DeployOracleWrappers is Script {
    /// @notice Deployed BTC/USD wrapper address
    address public btcOracleWrapper;

    /// @notice Deployed USDC/USD wrapper address
    address public usdcOracleWrapper;

    function run() external {
        require(block.chainid == DeploymentConstants.BASE_SEPOLIA_CHAIN_ID, "testnet only (chainId 84532)");

        // Load existing deployment addresses
        HelperConfig helperConfig = new HelperConfig();
        address aaveOracle = helperConfig.getOracle();
        address usdc = helperConfig.getUSDC();
        address cbBTC = helperConfig.getCbBTC();
        address bvBTC = helperConfig.getBTCVault();

        require(aaveOracle != address(0), "AaveOracle not deployed");
        require(usdc != address(0), "USDC not deployed");
        require(cbBTC != address(0), "cbBTC not deployed");
        require(bvBTC != address(0), "bvBTC not deployed");

        console2.log("=== Deploy Oracle Wrappers (Base Sepolia) ===");
        console2.log("AaveOracle:", aaveOracle);
        console2.log("USDC:", usdc);
        console2.log("cbBTC:", cbBTC);
        console2.log("bvBTC:", bvBTC);

        vm.startBroadcast();

        // 1. Deploy wrappers around real Chainlink feeds
        btcOracleWrapper = address(new ChainlinkOracleWrapper(DeploymentConstants.BASE_SEPOLIA_BTC_USD_FEED));
        usdcOracleWrapper = address(new ChainlinkOracleWrapper(DeploymentConstants.BASE_SEPOLIA_USDC_USD_FEED));
        console2.log("BTC/USD Wrapper:", btcOracleWrapper);
        console2.log("USDC/USD Wrapper:", usdcOracleWrapper);

        // 2. Wire wrappers into AaveOracle as asset sources
        //    cbBTC must be included — the Loan contract calls oracle.getAssetPrice(cbBTC)
        //    via calculateStrikePrice, and the bvBTC pricing path also depends on it.
        address[] memory assets = new address[](3);
        address[] memory sources = new address[](3);
        assets[0] = usdc;
        assets[1] = cbBTC;
        assets[2] = bvBTC;
        sources[0] = usdcOracleWrapper;
        sources[1] = btcOracleWrapper;
        sources[2] = btcOracleWrapper;

        // Sanity check: verify wrapper descriptions match assets
        require(
            keccak256(bytes(ChainlinkOracleWrapper(sources[0]).description())) != keccak256(bytes("BTC / USD")),
            "USDC asset paired with BTC feed"
        );
        require(
            keccak256(bytes(ChainlinkOracleWrapper(sources[1]).description())) != keccak256(bytes("USDC / USD")),
            "cbBTC asset paired with USDC feed"
        );

        IAaveOracleSetSources(aaveOracle).setAssetSources(assets, sources);
        console2.log("AaveOracle sources updated");

        vm.stopBroadcast();

        // 3. Verify
        address cbBTCSource = IAaveOracleSetSources(aaveOracle).getSourceOfAsset(cbBTC);
        address bvBTCSource = IAaveOracleSetSources(aaveOracle).getSourceOfAsset(bvBTC);
        address usdcSource = IAaveOracleSetSources(aaveOracle).getSourceOfAsset(usdc);
        require(cbBTCSource == btcOracleWrapper, "cbBTC source mismatch after setAssetSources");
        require(bvBTCSource == btcOracleWrapper, "bvBTC source mismatch after setAssetSources");
        require(usdcSource == usdcOracleWrapper, "USDC source mismatch after setAssetSources");
        console2.log("Verification passed: AaveOracle sources match deployed wrappers");

        console2.log("=== Oracle Wrappers Deployed ===");
    }
}
