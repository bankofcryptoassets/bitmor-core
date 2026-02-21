// SPDX-License-Identifier: agpl-3.0
pragma solidity >=0.8.13 <0.9.0;

import "forge-std/Test.sol";

interface IATokenHarness {
    function initialize(
        address pool,
        address treasury,
        address underlyingAsset,
        address incentivesController,
        uint8 aTokenDecimals,
        string calldata aTokenName,
        string calldata aTokenSymbol,
        bytes calldata params
    ) external;

    function mint(address user, uint256 amount, uint256 index) external returns (bool);
    function balanceOf(address user) external view returns (uint256);
    function scaledBalanceOf(address user) external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function scaledTotalSupply() external view returns (uint256);
}

interface IMockPoolForAToken {
    function setNormalizedIncome(uint256 income) external;
}

contract ATokenFuzzTest is Test {
    IATokenHarness aToken;
    IMockPoolForAToken mockPool;

    uint256 constant RAY = 1e27;
    uint256 constant MAX_BOUND = 1e36;

    function setUp() public {
        // Deploy mock pool and AToken harness (inherits real AToken)
        mockPool = IMockPoolForAToken(deployCode("ATokenHarness.sol:MockPoolForAToken"));
        aToken = IATokenHarness(deployCode("ATokenHarness.sol:ATokenHarness"));

        // Set default normalized income to RAY (1.0)
        mockPool.setNormalizedIncome(RAY);

        // Initialize AToken with mock pool
        aToken.initialize(
            address(mockPool),
            address(0xdead),    // treasury
            address(0xbeef),    // underlyingAsset
            address(0),         // incentivesController
            8,                  // decimals
            "Test AToken",
            "aTEST",
            ""
        );
    }

    // ============================================================
    //               scaledAmount (via mint + scaledBalanceOf)
    // ============================================================
    // mint stores: scaledBal = amount.rayDiv(index)
    // Verified via scaledBalanceOf

    function testFuzz_scaledAmount_Identity(uint256 amount) public {
        // rayDiv(amount, RAY) == amount
        amount = bound(amount, 1, type(uint256).max / RAY);

        address user = makeAddr("user_identity");
        vm.prank(address(mockPool));
        aToken.mint(user, amount, RAY);

        uint256 scaledBal = aToken.scaledBalanceOf(user);
        assertEq(scaledBal, amount, "scaledAmount at RAY index should return amount");
    }

    function testFuzz_scaledAmount_MonotonicInIndex(
        uint256 amount,
        uint256 index1,
        uint256 index2
    ) public {
        // Higher index → smaller scaled amount (more growth already happened)
        index1 = bound(index1, RAY, 10 * RAY);
        index2 = bound(index2, index1, 10 * RAY);
        // Ensure amount is large enough so rayDiv(amount, index) >= 1 for both indices
        uint256 minAmount = index2 / (2 * RAY) + 1;
        amount = bound(amount, minAmount, MAX_BOUND);

        address user1 = makeAddr("user_mono1");
        address user2 = makeAddr("user_mono2");

        vm.prank(address(mockPool));
        aToken.mint(user1, amount, index1);

        vm.prank(address(mockPool));
        aToken.mint(user2, amount, index2);

        uint256 scaled1 = aToken.scaledBalanceOf(user1);
        uint256 scaled2 = aToken.scaledBalanceOf(user2);

        assertGe(scaled1, scaled2, "higher index should give smaller or equal scaled amount");
    }

    function testFuzz_scaledAmount_ZeroAmountReverts(uint256 index) public {
        // Real AToken requires amountScaled != 0 (error "56": CT_INVALID_MINT_AMOUNT)
        index = bound(index, RAY, 10 * RAY);

        address user = makeAddr("user_zero");
        vm.prank(address(mockPool));
        vm.expectRevert(bytes("56"));
        aToken.mint(user, 0, index);
    }

    // ============================================================
    //              scaledBalance (via balanceOf + normalizedIncome)
    // ============================================================
    // balanceOf returns: scaledBal.rayMul(normalizedIncome)
    // We mint at RAY index (so stored == amount), then vary income

    function testFuzz_scaledBalance_Identity(uint256 scaledBal) public {
        // rayMul(scaledBal, RAY) == scaledBal
        scaledBal = bound(scaledBal, 1, type(uint256).max / RAY);

        address user = makeAddr("user_bal_identity");
        // Mint at RAY so stored == scaledBal
        vm.prank(address(mockPool));
        aToken.mint(user, scaledBal, RAY);

        mockPool.setNormalizedIncome(RAY);
        uint256 result = aToken.balanceOf(user);
        assertEq(result, scaledBal, "scaledBalance at RAY income should return scaledBal");
    }

    function testFuzz_scaledBalance_MonotonicInIndex(
        uint256 scaledBal,
        uint256 index1,
        uint256 index2
    ) public {
        // Higher income → larger balance (more interest accrued)
        scaledBal = bound(scaledBal, 1, MAX_BOUND);
        index1 = bound(index1, RAY, 10 * RAY);
        index2 = bound(index2, index1, 10 * RAY);

        address user = makeAddr("user_bal_mono");
        // Mint at RAY so stored == scaledBal
        vm.prank(address(mockPool));
        aToken.mint(user, scaledBal, RAY);

        mockPool.setNormalizedIncome(index1);
        uint256 bal1 = aToken.balanceOf(user);

        mockPool.setNormalizedIncome(index2);
        uint256 bal2 = aToken.balanceOf(user);

        assertLe(bal1, bal2, "higher income should give larger or equal balance");
    }

    function testFuzz_scaledBalance_ZeroScaledBal(uint256 index) public {
        index = bound(index, RAY, 10 * RAY);

        address user = makeAddr("user_zero_bal");
        // Don't mint anything - scaledBal is 0

        mockPool.setNormalizedIncome(index);
        uint256 result = aToken.balanceOf(user);
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
        amount = bound(amount, minAmount, MAX_BOUND);

        address user = makeAddr("user_same_idx");
        vm.prank(address(mockPool));
        aToken.mint(user, amount, index);

        mockPool.setNormalizedIncome(index);
        uint256 recovered = aToken.balanceOf(user);

        uint256 diff = amount > recovered ? amount - recovered : recovered - amount;
        uint256 maxError = index / RAY + 1;

        assertLe(diff, maxError, "mint+query at same index should recover amount within rounding tolerance");
    }

    function testFuzz_mintThenBalance_GrowingIndex(
        uint256 amount,
        uint256 mintIndex,
        uint256 queryIndex
    ) public {
        // Query at higher index → balance >= original amount (interest accrued)
        amount = bound(amount, 1e18, MAX_BOUND);
        mintIndex = bound(mintIndex, RAY, 5 * RAY);
        queryIndex = bound(queryIndex, mintIndex, 10 * RAY);

        address user = makeAddr("user_growing_idx");
        vm.prank(address(mockPool));
        aToken.mint(user, amount, mintIndex);

        mockPool.setNormalizedIncome(queryIndex);
        uint256 balance = aToken.balanceOf(user);

        uint256 maxError = queryIndex / RAY + 1;
        assertGe(balance + maxError, amount, "balance at higher index should be >= original amount minus rounding");
    }

    function testFuzz_mintThenBalance_DecreasingIndex(
        uint256 amount,
        uint256 mintIndex,
        uint256 queryIndex
    ) public {
        // Query at lower index → balance <= original amount (+ rounding tolerance)
        amount = bound(amount, 1e18, MAX_BOUND);
        queryIndex = bound(queryIndex, RAY, 5 * RAY);
        mintIndex = bound(mintIndex, queryIndex, 10 * RAY);

        address user = makeAddr("user_dec_idx");
        vm.prank(address(mockPool));
        aToken.mint(user, amount, mintIndex);

        mockPool.setNormalizedIncome(queryIndex);
        uint256 balance = aToken.balanceOf(user);

        uint256 maxError = mintIndex / RAY + 1;
        assertLe(balance, amount + maxError, "balance at lower index should be <= original amount + rounding tolerance");
    }

    // ============================================================
    //                    mintRoundTrip
    // ============================================================

    function testFuzz_mintRoundTrip_BoundedError(uint256 amount, uint256 index) public {
        // Precision loss from rayDiv then rayMul is bounded
        index = bound(index, RAY, 10 * RAY);
        // Ensure amount is large enough so rayDiv(amount, index) >= 1
        uint256 minAmount = index / (2 * RAY) + 1;
        amount = bound(amount, minAmount, MAX_BOUND);

        address user = makeAddr("user_roundtrip");
        vm.prank(address(mockPool));
        aToken.mint(user, amount, index);

        mockPool.setNormalizedIncome(index);
        uint256 recovered = aToken.balanceOf(user);

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
        aToken.mint(user, amount, index);
    }
}
