// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.30;

import {IntegrationTestBase} from "../base/IntegrationTestBase.sol";
import {TestConstants as TC} from "../helpers/TestConstants.sol";
import {DataTypes} from "@bitmor/libraries/types/DataTypes.sol";
import {IERC20} from "@openzeppelin/interfaces/IERC20.sol";
import {AaveTokenizedStrategy} from "@btcVault/TokenizedStrategy/AaveTokenizedStrategy.sol";

/// @title CollateralValuationTest
/// @notice Loan initialization should not leave residual USDC in the Loan contract.
///         LoanLogic should use the cbBTC price (underlying) when computing the loan amount
///         for a cbBTC collateral amount, not the bvBTC share price.
contract CollateralValuationTest is IntegrationTestBase {
    uint256 internal constant SIMULATED_YIELD_BPS = 500; // 5%

    function setUp() public override {
        super.setUp();
        _setupTestUser();
    }

    /// @notice Loan contract should hold zero USDC after loan initialization
    function test_InitializeLoan_NoResidualUSDC_WhenVaultHasYield() public {
        // Seed the vault with a first loan so the strategy has aTokens
        _createStandardLoan();

        // Simulate 5% yield accrual in the BTCVault strategy
        _simulateVaultYield(SIMULATED_YIELD_BPS);

        // Create a second loan with the now-inflated vault share price
        vm.warp(block.timestamp + 1);
        _createStandardLoan();

        // The Loan contract should not hold any USDC after initialization completes
        uint256 residual = usdc.balanceOf(address(loanContract));
        assertEq(residual, 0, "Loan contract should have zero USDC after initialization");
    }

    // ============ Helpers ============

    function _simulateVaultYield(uint256 yieldBps) internal override {
        address strategy = config.getAaveTokenizedStrategy();
        AaveTokenizedStrategy ats = AaveTokenizedStrategy(strategy);

        address yieldSource = ats.i_yieldSource();
        (bool ok, bytes memory data) =
            yieldSource.staticcall(abi.encodeWithSignature("getReserveAToken(address)", address(cbBTC)));
        require(ok, "getReserveAToken failed");
        address aToken = abi.decode(data, (address));

        uint256 currentBalance = IERC20(aToken).balanceOf(strategy);
        require(currentBalance > 0, "strategy must have deposits before simulating yield");

        uint256 yieldAmount = currentBalance * yieldBps / 10_000;
        deal(aToken, strategy, currentBalance + yieldAmount);
    }
}
