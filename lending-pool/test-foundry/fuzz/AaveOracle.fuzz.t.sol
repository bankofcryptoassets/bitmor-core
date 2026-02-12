// SPDX-License-Identifier: agpl-3.0
pragma solidity >=0.8.13 <0.9.0;

import "forge-std/Test.sol";

interface IAaveOracleHarness {
    function calculateBvBTCPrice(
        uint256 btcPrice,
        uint256 assetPerShare,
        uint8 btcDecimals
    ) external pure returns (uint256);
}

contract AaveOracleFuzzTest is Test {
    IAaveOracleHarness h;

    // Standard cbBTC decimals
    uint8 constant BTC_DECIMALS = 8;

    function setUp() public {
        h = IAaveOracleHarness(deployCode("AaveOracleHarness.sol:AaveOracleHarness"));
    }

    // ============================================================
    //                   calculateBvBTCPrice
    // ============================================================

    function testFuzz_bvBTCPrice_ZeroBtcPriceReturnsZero(
        uint256 assetPerShare,
        uint8 btcDecimals
    ) public view {
        assetPerShare = bound(assetPerShare, 0, 1e18);
        btcDecimals = uint8(bound(uint256(btcDecimals), 1, 18));

        uint256 result = h.calculateBvBTCPrice(0, assetPerShare, btcDecimals);

        assertEq(result, 0, "zero BTC price should return zero bvBTC price");
    }

    function testFuzz_bvBTCPrice_ZeroAssetsPerShareReturnsZero(
        uint256 btcPrice,
        uint8 btcDecimals
    ) public view {
        btcPrice = bound(btcPrice, 0, 1e18);
        btcDecimals = uint8(bound(uint256(btcDecimals), 1, 18));

        uint256 result = h.calculateBvBTCPrice(btcPrice, 0, btcDecimals);

        assertEq(result, 0, "zero assets per share should return zero bvBTC price");
    }

    function testFuzz_bvBTCPrice_StandardDecimals(
        uint256 btcPrice,
        uint256 assetPerShare
    ) public view {
        // Standard case: 8 decimal BTC
        // bvBTCPrice = btcPrice * assetPerShare / 1e8
        btcPrice = bound(btcPrice, 1, 1e18);
        assetPerShare = bound(assetPerShare, 1, 1e18);

        uint256 result = h.calculateBvBTCPrice(btcPrice, assetPerShare, BTC_DECIMALS);
        uint256 expected = (btcPrice * assetPerShare) / (10 ** uint256(BTC_DECIMALS));

        assertEq(result, expected, "should match manual calculation for 8 decimals");
    }

    function testFuzz_bvBTCPrice_MonotonicInBtcPrice(
        uint256 price1,
        uint256 price2,
        uint256 assetPerShare
    ) public view {
        price1 = bound(price1, 0, 1e18);
        price2 = bound(price2, price1, 1e18);
        assetPerShare = bound(assetPerShare, 1, 1e18);

        uint256 result1 = h.calculateBvBTCPrice(price1, assetPerShare, BTC_DECIMALS);
        uint256 result2 = h.calculateBvBTCPrice(price2, assetPerShare, BTC_DECIMALS);

        assertLe(result1, result2, "higher BTC price should give higher or equal bvBTC price");
    }

    function testFuzz_bvBTCPrice_MonotonicInAssetsPerShare(
        uint256 btcPrice,
        uint256 aps1,
        uint256 aps2
    ) public view {
        btcPrice = bound(btcPrice, 1, 1e18);
        aps1 = bound(aps1, 0, 1e18);
        aps2 = bound(aps2, aps1, 1e18);

        uint256 result1 = h.calculateBvBTCPrice(btcPrice, aps1, BTC_DECIMALS);
        uint256 result2 = h.calculateBvBTCPrice(btcPrice, aps2, BTC_DECIMALS);

        assertLe(result1, result2, "higher assets per share should give higher or equal bvBTC price");
    }

    function testFuzz_bvBTCPrice_HigherDecimalsLowerPrice(
        uint256 btcPrice,
        uint256 assetPerShare,
        uint8 dec1,
        uint8 dec2
    ) public view {
        // More decimals → larger denominator → smaller result
        btcPrice = bound(btcPrice, 1, 1e12);
        assetPerShare = bound(assetPerShare, 1, 1e12);
        dec1 = uint8(bound(uint256(dec1), 1, 16));
        dec2 = uint8(bound(uint256(dec2), uint256(dec1), 16));

        uint256 result1 = h.calculateBvBTCPrice(btcPrice, assetPerShare, dec1);
        uint256 result2 = h.calculateBvBTCPrice(btcPrice, assetPerShare, dec2);

        assertGe(result1, result2, "higher decimals should give smaller or equal price");
    }

    function testFuzz_bvBTCPrice_IdentityAtOneShare(
        uint256 btcPrice,
        uint8 btcDecimals
    ) public view {
        // When assetPerShare == 10^btcDecimals (1:1 share), result should equal btcPrice
        btcDecimals = uint8(bound(uint256(btcDecimals), 1, 18));
        btcPrice = bound(btcPrice, 0, type(uint256).max / (10 ** uint256(btcDecimals)));

        uint256 oneShare = 10 ** uint256(btcDecimals);
        uint256 result = h.calculateBvBTCPrice(btcPrice, oneShare, btcDecimals);

        assertEq(result, btcPrice, "1:1 share ratio should return btcPrice");
    }

    function testFuzz_bvBTCPrice_Commutativity(
        uint256 a,
        uint256 b,
        uint8 btcDecimals
    ) public view {
        // btcPrice * assetsPerShare is commutative
        btcDecimals = uint8(bound(uint256(btcDecimals), 1, 18));
        a = bound(a, 0, 1e18);
        b = bound(b, 0, 1e18);

        uint256 result1 = h.calculateBvBTCPrice(a, b, btcDecimals);
        uint256 result2 = h.calculateBvBTCPrice(b, a, btcDecimals);

        assertEq(result1, result2, "calculation should be commutative in price and share");
    }

    function testFuzz_bvBTCPrice_OverflowReverts(
        uint256 btcPrice,
        uint256 assetPerShare
    ) public {
        // Large multiplication should revert (SafeMath overflow)
        btcPrice = bound(btcPrice, type(uint128).max, type(uint256).max);
        assetPerShare = bound(assetPerShare, type(uint128).max, type(uint256).max);

        vm.expectRevert();
        h.calculateBvBTCPrice(btcPrice, assetPerShare, BTC_DECIMALS);
    }
}
