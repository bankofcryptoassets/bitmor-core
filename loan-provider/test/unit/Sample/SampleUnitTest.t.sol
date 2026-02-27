// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {UnitTestBase} from "../../base/UnitTestBase.sol";

/// @title SampleUnitTest
/// @author Bitmor Protocol
/// @notice Template demonstrating how to write unit tests using the `UnitTestBase` infrastructure
contract SampleUnitTest is UnitTestBase {
    function test_mockTokensHaveCorrectDecimals() public view {
        assertEq(mockCbBTC.decimals(), 8, "cbBTC should have 8 decimals");
        assertEq(mockUSDC.decimals(), 6, "USDC should have 6 decimals");
    }

    function test_canMintMockTokens() public {
        uint256 amount = 1e8; // 1 cbBTC
        _fundCbBTC(testUser, amount);
        assertEq(mockCbBTC.balanceOf(testUser), amount);
    }

    function test_mockAavePoolHasLiquidity() public view {
        uint256 balance = mockUSDC.balanceOf(address(mockAavePool));
        assertGt(balance, 0, "Mock Aave pool should have USDC liquidity");
    }

    function test_accessManagerIsDeployed() public view {
        assertTrue(address(manager) != address(0), "AccessManager should be deployed");
    }

    function test_roleActorsAreCreated() public view {
        assertTrue(executor != address(0), "Executor should be created");
        assertTrue(lpcm != address(0), "LPCM should be created");
    }
}
