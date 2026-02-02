// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {BaseStrategyTest} from "./BaseStrategyTest.t.sol";
import {SimpleTokenizedStrategyHarness} from "../../harness/SimpleTokenizedStrategyHarness.sol";
import {MockVault} from "../../mock/MockVault.sol";

/// @title SimpleTokenizedStrategyTest
/// @notice Unit tests for SimpleTokenizedStrategy abstract contract
/// @dev Tests via harness since contract is abstract
contract SimpleTokenizedStrategyTest is BaseStrategyTest {
    /// @notice Test that constructor sets i_yieldSource correctly
    function test_Constructor_SetsYieldSource() public view {
        address yieldSource = strategyHarness.i_yieldSource();
        assertEq(yieldSource, address(mockAavePool), "yieldSource should match constructor arg");
    }

    /// @notice Test that constructor sets i_vault correctly
    function test_Constructor_SetsVault() public view {
        address vault = strategyHarness.i_vault();
        assertEq(vault, address(mockVault), "vault should match constructor arg");
    }

    /// @notice Test that constructor queries vault for asset
    function test_Constructor_QueriesVaultAsset() public view {
        address asset = strategyHarness.asset();
        address expectedAsset = mockVault.asset();
        assertEq(asset, expectedAsset, "asset should be queried from vault");
    }

    /// @notice Test that asset() returns correct address
    function test_Asset_ReturnsCorrectAddress() public view {
        address asset = strategyHarness.asset();
        assertEq(asset, address(mockAsset), "asset should return mockAsset address");
    }

    /// @notice Test that _underlyingDecimals matches asset decimals
    function test_UnderlyingDecimals_MatchesAsset() public view {
        uint8 decimals = strategyHarness.exposed_underlyingDecimals();
        uint8 expectedDecimals = mockAsset.decimals();
        assertEq(decimals, expectedDecimals, "underlyingDecimals should match asset decimals");
        assertEq(decimals, 8, "cbBTC should have 8 decimals");
    }

    /// @notice Test that base totalAssets returns zero
    function test_TotalAssets_ReturnsZeroByDefault() public view {
        uint256 totalAssets = strategyHarness.totalAssets();
        assertEq(totalAssets, 0, "base totalAssets should return 0");
    }

    /// @notice Test that constructor reverts when vault has no asset function
    function test_RevertWhen_VaultHasNoAssetFunction() public {
        // Deploy a contract with no asset() function
        address invalidVault = address(new NoAssetContract());

        vm.expectRevert();
        new SimpleTokenizedStrategyHarness(address(mockAavePool), invalidVault);
    }
}

/// @notice Contract without asset() function for revert testing
contract NoAssetContract {}
