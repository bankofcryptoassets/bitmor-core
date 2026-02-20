// SPDX-License-Identifier: agpl-3.0
pragma solidity >=0.8.13 <0.9.0;

import "forge-std/Test.sol";

interface IVariableDebtTokenHarness {
    function initialize(
        address pool,
        address underlyingAsset,
        address incentivesController,
        uint8 debtTokenDecimals,
        string memory debtTokenName,
        string memory debtTokenSymbol,
        bytes calldata params
    ) external;

    function mint(
        address user,
        address onBehalfOf,
        uint256 amount,
        uint256 index
    ) external returns (bool);

    function balanceOf(address user) external view returns (uint256);
    function scaledBalanceOf(address user) external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function scaledTotalSupply() external view returns (uint256);
}

interface IMockPoolForVariableDebt {
    function setNormalizedVariableDebt(uint256 debt) external;
}

contract VariableDebtTokenFuzzTest is Test {
    IVariableDebtTokenHarness varDebt;
    IMockPoolForVariableDebt mockPool;

    uint256 constant RAY = 1e27;

    function setUp() public {
        // Deploy mock pool and VariableDebtToken harness (inherits real VariableDebtToken)
        mockPool = IMockPoolForVariableDebt(
            deployCode("VariableDebtTokenHarness.sol:MockPoolForVariableDebt")
        );
        varDebt = IVariableDebtTokenHarness(
            deployCode("VariableDebtTokenHarness.sol:VariableDebtTokenHarness")
        );

        // Set default normalized variable debt to RAY (1.0)
        mockPool.setNormalizedVariableDebt(RAY);

        // Initialize VariableDebtToken with mock pool
        varDebt.initialize(
            address(mockPool),
            address(0xbeef),    // underlyingAsset
            address(0),         // incentivesController
            8,                  // decimals
            "Test Variable Debt",
            "vTEST",
            ""
        );
    }

    // ============================================================
    //            scaledAmount (via mint + scaledBalanceOf)
    // ============================================================
    // mint stores: scaledBal = amount.rayDiv(index)
    // Verified via scaledBalanceOf

    function testFuzz_scaledAmount_Identity(uint256 amount) public {
        // rayDiv(amount, RAY) == amount
        amount = bound(amount, 1, type(uint256).max / RAY);

        address user = makeAddr("user_identity");
        vm.prank(address(mockPool));
        varDebt.mint(user, user, amount, RAY);

        uint256 scaledBal = varDebt.scaledBalanceOf(user);
        assertEq(scaledBal, amount, "scaledAmount at RAY index should return amount");
    }

    function testFuzz_scaledAmount_MonotonicInIndex(
        uint256 amount,
        uint256 index1,
        uint256 index2
    ) public {
        // Higher index → smaller scaled amount (more debt growth already happened)
        index1 = bound(index1, RAY, 10 * RAY);
        index2 = bound(index2, index1, 10 * RAY);
        // Ensure amount is large enough so rayDiv(amount, index) >= 1 for both indices
        uint256 minAmount = index2 / (2 * RAY) + 1;
        amount = bound(amount, minAmount, 1e36);

        address user1 = makeAddr("user_mono1");
        address user2 = makeAddr("user_mono2");

        vm.prank(address(mockPool));
        varDebt.mint(user1, user1, amount, index1);

        vm.prank(address(mockPool));
        varDebt.mint(user2, user2, amount, index2);

        uint256 scaled1 = varDebt.scaledBalanceOf(user1);
        uint256 scaled2 = varDebt.scaledBalanceOf(user2);

        assertGe(scaled1, scaled2, "higher index should give smaller or equal scaled amount");
    }

    function testFuzz_scaledAmount_ZeroAmountReverts(uint256 index) public {
        // Real VariableDebtToken requires amountScaled != 0 (error "56": CT_INVALID_MINT_AMOUNT)
        index = bound(index, RAY, 10 * RAY);

        address user = makeAddr("user_zero");
        vm.prank(address(mockPool));
        vm.expectRevert(bytes("56"));
        varDebt.mint(user, user, 0, index);
    }

    // ============================================================
    //         scaledBalance (via balanceOf + normalizedVariableDebt)
    // ============================================================
    // balanceOf returns: scaledBal.rayMul(normalizedVariableDebt)
    // We mint at RAY index (so stored == amount), then vary normalized debt

    function testFuzz_scaledBalance_Identity(uint256 scaledBal) public {
        // rayMul(scaledBal, RAY) == scaledBal
        scaledBal = bound(scaledBal, 1, type(uint256).max / RAY);

        address user = makeAddr("user_bal_identity");
        // Mint at RAY so stored == scaledBal
        vm.prank(address(mockPool));
        varDebt.mint(user, user, scaledBal, RAY);

        mockPool.setNormalizedVariableDebt(RAY);
        uint256 result = varDebt.balanceOf(user);
        assertEq(result, scaledBal, "scaledBalance at RAY normalizedDebt should return scaledBal");
    }

    function testFuzz_scaledBalance_MonotonicInNormalizedDebt(
        uint256 scaledBal,
        uint256 nd1,
        uint256 nd2
    ) public {
        // Higher normalized debt → larger balance (more interest accrued)
        scaledBal = bound(scaledBal, 1, 1e36);
        nd1 = bound(nd1, RAY, 10 * RAY);
        nd2 = bound(nd2, nd1, 10 * RAY);

        address user = makeAddr("user_bal_mono");
        // Mint at RAY so stored == scaledBal
        vm.prank(address(mockPool));
        varDebt.mint(user, user, scaledBal, RAY);

        mockPool.setNormalizedVariableDebt(nd1);
        uint256 bal1 = varDebt.balanceOf(user);

        mockPool.setNormalizedVariableDebt(nd2);
        uint256 bal2 = varDebt.balanceOf(user);

        assertLe(bal1, bal2, "higher normalized debt should give larger or equal balance");
    }

    function testFuzz_scaledBalance_ZeroScaledBal(uint256 nd) public {
        nd = bound(nd, RAY, 10 * RAY);

        address user = makeAddr("user_zero_bal");
        // Don't mint anything - scaledBal is 0

        mockPool.setNormalizedVariableDebt(nd);
        uint256 result = varDebt.balanceOf(user);
        assertEq(result, 0, "zero scaled balance should return zero");
    }

    // ============================================================
    //                       mintThenBalance
    // ============================================================
    // Mint at mintIndex (stores amount.rayDiv(mintIndex))
    // Query balanceOf at queryIndex (returns stored.rayMul(queryIndex))

    function testFuzz_mintThenBalance_SameIndex(uint256 amount, uint256 index) public {
        // Mint at index, query at same index → should recover amount (± rounding)
        index = bound(index, RAY, 10 * RAY);
        // Ensure amount is large enough so rayDiv(amount, index) >= 1
        uint256 minAmount = index / (2 * RAY) + 1;
        amount = bound(amount, minAmount, 1e36);

        address user = makeAddr("user_same_idx");
        vm.prank(address(mockPool));
        varDebt.mint(user, user, amount, index);

        mockPool.setNormalizedVariableDebt(index);
        uint256 recovered = varDebt.balanceOf(user);

        uint256 diff = amount > recovered ? amount - recovered : recovered - amount;
        uint256 maxError = index / RAY + 1;

        assertLe(diff, maxError, "mint+query at same index should recover amount within rounding tolerance");
    }

    function testFuzz_mintThenBalance_GrowingIndex(
        uint256 amount,
        uint256 mintIndex,
        uint256 queryIndex
    ) public {
        // Growing normalized debt index → debt balance increases
        amount = bound(amount, 1e18, 1e36);
        mintIndex = bound(mintIndex, RAY, 5 * RAY);
        queryIndex = bound(queryIndex, mintIndex, 10 * RAY);

        address user = makeAddr("user_growing_idx");
        vm.prank(address(mockPool));
        varDebt.mint(user, user, amount, mintIndex);

        mockPool.setNormalizedVariableDebt(queryIndex);
        uint256 balance = varDebt.balanceOf(user);

        uint256 maxError = queryIndex / RAY + 1;
        assertGe(balance + maxError, amount, "balance at higher index should be >= original amount minus rounding");
    }

    // ============================================================
    //                    mintRoundTrip
    // ============================================================

    function testFuzz_mintRoundTrip_BoundedError(uint256 amount, uint256 index) public {
        // Precision loss from rayDiv then rayMul is bounded
        index = bound(index, RAY, 10 * RAY);
        // Ensure amount is large enough so rayDiv(amount, index) >= 1
        uint256 minAmount = index / (2 * RAY) + 1;
        amount = bound(amount, minAmount, 1e36);

        address user = makeAddr("user_roundtrip");
        vm.prank(address(mockPool));
        varDebt.mint(user, user, amount, index);

        mockPool.setNormalizedVariableDebt(index);
        uint256 recovered = varDebt.balanceOf(user);

        uint256 diff = amount > recovered ? amount - recovered : recovered - amount;
        uint256 maxError = index / RAY + 1;

        assertLe(diff, maxError, "mint round trip precision loss should be within rounding tolerance");
    }

    // ============================================================
    //                      overflow
    // ============================================================

    function testFuzz_scaledAmount_OverflowReverts(uint256 amount, uint256 index) public {
        // Large amount with small index should overflow in rayDiv
        amount = bound(amount, type(uint256).max / RAY + 1, type(uint256).max);
        index = bound(index, 1, RAY / 2);

        address user = makeAddr("user_overflow");
        vm.prank(address(mockPool));
        vm.expectRevert();
        varDebt.mint(user, user, amount, index);
    }
}
