// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.30;

import {IntegrationTestBase} from "../base/IntegrationTestBase.sol";
import {TestConstants as TC} from "../helpers/TestConstants.sol";
import {DataTypes} from "@bitmor/libraries/types/DataTypes.sol";
import {IERC20} from "@openzeppelin/interfaces/IERC20.sol";

/// @title LendingPoolInvariantsTest
/// @notice Integration tests for lending pool index and rate invariants
contract LendingPoolInvariantsTest is IntegrationTestBase {
    uint256 internal constant INDEX_POKE_AMOUNT = 1e6; // 1 USDC

    function setUp() public override {
        super.setUp();
        _setupTestUser();
    }

    /// @notice Force BLP reserve indices to update by doing a tiny deposit
    /// @dev Aave V2 only updates indices on interactions, not on time advance.
    function _pokeReserveIndex() internal {
        address poker = makeAddr("indexPoker");
        _fundUSDC(poker, INDEX_POKE_AMOUNT);
        vm.prank(poker);
        IERC20(address(usdc)).approve(address(usdcVault), INDEX_POKE_AMOUNT);
        vm.prank(poker);
        usdcVault.deposit(INDEX_POKE_AMOUNT, poker);
    }

    /// @notice 22.2: USDC liquidity and borrow indices never decrease after any action
    /// @dev bvBTC indices only checked at real interaction checkpoints (init, close).
    ///      Time-based bvBTC index growth requires a bvBTC-specific poke — out of scope.
    function test_USDCIndices_MonotonicallyIncrease() public {
        address usdcAddr = address(usdc);
        address bvBTCAddr = address(btcVault);

        // --- Checkpoint 0: Initial state ---
        uint256 usdcLiqIdx0 = _getLiquidityIndex(usdcAddr);
        uint256 bvBTCLiqIdx0 = _getLiquidityIndex(bvBTCAddr);
        uint256 usdcBorrowIdx0 = _getVariableBorrowIndex();
        assertGt(usdcLiqIdx0, 0, "USDC liquidity index must be positive at start");
        assertGt(bvBTCLiqIdx0, 0, "bvBTC liquidity index must be positive at start");

        // --- Checkpoint 1: After loan init ---
        (address lsa, DataTypes.LoanData memory loanData) = _createStandardLoanWithData();

        uint256 usdcLiqIdx1 = _getLiquidityIndex(usdcAddr);
        uint256 bvBTCLiqIdx1 = _getLiquidityIndex(bvBTCAddr);
        uint256 usdcBorrowIdx1 = _getVariableBorrowIndex();
        assertGe(usdcLiqIdx1, usdcLiqIdx0, "USDC liq index must not decrease after loan init");
        assertGe(bvBTCLiqIdx1, bvBTCLiqIdx0, "bvBTC liq index must not decrease after deposit");
        assertGe(usdcBorrowIdx1, usdcBorrowIdx0, "USDC borrow index must not decrease after loan init");

        // --- Checkpoint 2: After 7 days + forced index update ---
        _advanceDays(7);
        _pokeReserveIndex();

        uint256 usdcLiqIdx2 = _getLiquidityIndex(usdcAddr);
        uint256 usdcBorrowIdx2 = _getVariableBorrowIndex();
        assertGt(usdcLiqIdx2, usdcLiqIdx1, "USDC liq index should increase with outstanding debt + time");
        assertGt(usdcBorrowIdx2, usdcBorrowIdx1, "USDC borrow index should increase with outstanding debt + time");

        // --- Checkpoint 3: After ~30 days + forced index update ---
        _advanceDays(23);
        _pokeReserveIndex();

        uint256 usdcLiqIdx3 = _getLiquidityIndex(usdcAddr);
        uint256 usdcBorrowIdx3 = _getVariableBorrowIndex();
        assertGt(usdcLiqIdx3, usdcLiqIdx2, "USDC liq index must increase after 30d + poke");
        assertGt(usdcBorrowIdx3, usdcBorrowIdx2, "USDC borrow index must increase after 30d + poke");

        // --- Checkpoint 4: After repayment ---
        _repayLoan(lsa, testUser, loanData.estimatedMonthlyPayment);

        uint256 usdcLiqIdx4 = _getLiquidityIndex(usdcAddr);
        uint256 usdcBorrowIdx4 = _getVariableBorrowIndex();
        assertGe(usdcLiqIdx4, usdcLiqIdx3, "USDC liq index must not decrease after repay");
        assertGe(usdcBorrowIdx4, usdcBorrowIdx3, "USDC borrow index must not decrease after repay");

        // --- Checkpoint 5: After second month + forced update ---
        _advanceDays(30);
        _pokeReserveIndex();

        uint256 usdcLiqIdx5 = _getLiquidityIndex(usdcAddr);
        uint256 usdcBorrowIdx5 = _getVariableBorrowIndex();
        assertGt(usdcLiqIdx5, usdcLiqIdx4, "USDC liq index must increase after 2nd month + poke");
        assertGt(usdcBorrowIdx5, usdcBorrowIdx4, "USDC borrow index must increase after 2nd month + poke");

        // --- Checkpoint 6: After second repayment ---
        _repayLoan(lsa, testUser, loanData.estimatedMonthlyPayment);

        uint256 usdcLiqIdx6 = _getLiquidityIndex(usdcAddr);
        uint256 usdcBorrowIdx6 = _getVariableBorrowIndex();
        assertGe(usdcLiqIdx6, usdcLiqIdx5, "USDC liq index must not decrease after 2nd repay");
        assertGe(usdcBorrowIdx6, usdcBorrowIdx5, "USDC borrow index must not decrease after 2nd repay");

        // --- Checkpoint 7: After close ---
        {
            DataTypes.LoanData memory closeData = loanContract.getLoanByLSA(lsa);
            uint256 closeBuffer = closeData.loanAmount * 2;
            uint256 currentBalance = usdc.balanceOf(testUser);
            if (currentBalance < closeBuffer) {
                _fundUSDC(testUser, closeBuffer - currentBalance);
            }
            vm.prank(testUser);
            usdc.approve(address(loanContract), type(uint256).max);
            vm.prank(testUser);
            loanContract.closeLoan(lsa, false);
        }

        uint256 usdcLiqIdx7 = _getLiquidityIndex(usdcAddr);
        uint256 usdcBorrowIdx7 = _getVariableBorrowIndex();
        assertGe(usdcLiqIdx7, usdcLiqIdx6, "USDC liq index must not decrease after close");
        assertGe(usdcBorrowIdx7, usdcBorrowIdx6, "USDC borrow index must not decrease after close");

        // --- Final: verify net increase over entire lifecycle ---
        assertGt(usdcLiqIdx7, usdcLiqIdx0, "USDC liq index must be higher at end than start");
        assertGt(usdcBorrowIdx7, usdcBorrowIdx0, "USDC borrow index must be higher at end than start");
    }
}
