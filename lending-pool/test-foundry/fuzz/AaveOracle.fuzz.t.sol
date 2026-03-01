// SPDX-License-Identifier: agpl-3.0
pragma solidity >=0.8.13 <0.9.0;

import "forge-std/Test.sol";

interface IAaveOracle {
    function getAssetPrice(address asset) external view returns (uint256);
}

interface IMockChainlinkForOracle {
    function setAnswer(int256 answer_) external;
}

interface IMockVaultForOracle {
    function setPreviewRedeem(uint256 result) external;
    function setDecimals(uint8 dec) external;
}

interface IMockBTCForOracle {
    function setDecimals(uint8 dec) external;
}

interface IMockFallbackOracle {
    function setAssetPrice(address asset, uint256 price) external;
}

contract AaveOracleFuzzTest is Test {
    IAaveOracle oracle;
    IMockChainlinkForOracle chainlink;
    IMockVaultForOracle bvBTC;
    IMockBTCForOracle btc;
    IMockFallbackOracle fallbackOracle;

    // Standard cbBTC decimals
    uint8 constant BTC_DECIMALS = 8;
    uint8 constant BVBTC_DECIMALS = 8;

    function setUp() public {
        // Warp to a realistic timestamp so that `block.timestamp - MAX_STALENESS` (3600)
        // does not underflow in the 0.6.12 AaveOracle staleness check.
        vm.warp(100_000);

        // Deploy mocks
        chainlink = IMockChainlinkForOracle(deployCode("AaveOracleHarness.sol:MockChainlinkForOracle"));
        bvBTC = IMockVaultForOracle(deployCode("AaveOracleHarness.sol:MockVaultForOracle"));
        btc = IMockBTCForOracle(deployCode("AaveOracleHarness.sol:MockBTCForOracle"));
        fallbackOracle = IMockFallbackOracle(deployCode("AaveOracleHarness.sol:MockFallbackOracle"));

        // Configure mock defaults
        btc.setDecimals(BTC_DECIMALS);
        bvBTC.setDecimals(BVBTC_DECIMALS);

        // Deploy AaveOracleHarness (inherits real AaveOracle) with btc → chainlink source
        address[] memory assets = new address[](1);
        assets[0] = address(btc);
        address[] memory sources = new address[](1);
        sources[0] = address(chainlink);

        oracle = IAaveOracle(
            deployCode(
                "AaveOracleHarness.sol:AaveOracleHarness",
                abi.encode(
                    assets,
                    sources,
                    address(btc),
                    address(bvBTC),
                    address(fallbackOracle),
                    address(0),
                    1e8
                )
            )
        );
    }

    /// @dev Configure mock state for a fuzz run (uses default BTC_DECIMALS from setUp)
    function _setOracleState(uint256 btcPrice, uint256 assetPerShare) internal {
        chainlink.setAnswer(int256(btcPrice));
        bvBTC.setPreviewRedeem(assetPerShare);
    }

    /// @dev Configure mock state with custom btcDecimals
    function _setOracleState(uint256 btcPrice, uint256 assetPerShare, uint8 btcDecimals) internal {
        chainlink.setAnswer(int256(btcPrice));
        bvBTC.setPreviewRedeem(assetPerShare);
        btc.setDecimals(btcDecimals);
    }

    // ============================================================
    //                   getAssetPrice (bvBTC)
    // ============================================================

    function testFuzz_bvBTCPrice_ZeroBtcPriceReturnsZero(
        uint256 assetPerShare,
        uint8 btcDecimals
    ) public {
        assetPerShare = bound(assetPerShare, 0, 1e18);
        btcDecimals = uint8(bound(uint256(btcDecimals), 1, 18));

        // Chainlink returns 0 → oracle falls back; set fallback to 0 as well
        chainlink.setAnswer(0);
        fallbackOracle.setAssetPrice(address(btc), 0);
        bvBTC.setPreviewRedeem(assetPerShare);
        btc.setDecimals(btcDecimals);

        uint256 result = oracle.getAssetPrice(address(bvBTC));

        assertEq(result, 0, "zero BTC price should return zero bvBTC price");
    }

    function testFuzz_bvBTCPrice_ZeroAssetsPerShareReturnsZero(
        uint256 btcPrice,
        uint8 btcDecimals
    ) public {
        btcPrice = bound(btcPrice, 1, 1e18);
        btcDecimals = uint8(bound(uint256(btcDecimals), 1, 18));

        _setOracleState(btcPrice, 0, btcDecimals);

        uint256 result = oracle.getAssetPrice(address(bvBTC));

        assertEq(result, 0, "zero assets per share should return zero bvBTC price");
    }

    function testFuzz_bvBTCPrice_StandardDecimals(
        uint256 btcPrice,
        uint256 assetPerShare
    ) public {
        // Standard case: 8 decimal BTC
        // bvBTCPrice = btcPrice * assetPerShare / 1e8
        btcPrice = bound(btcPrice, 1, 1e18);
        assetPerShare = bound(assetPerShare, 1, 1e18);

        _setOracleState(btcPrice, assetPerShare);

        uint256 result = oracle.getAssetPrice(address(bvBTC));
        uint256 expected = (btcPrice * assetPerShare) / (10 ** uint256(BTC_DECIMALS));

        assertEq(result, expected, "should match manual calculation for 8 decimals");
    }

    function testFuzz_bvBTCPrice_MonotonicInBtcPrice(
        uint256 price1,
        uint256 price2,
        uint256 assetPerShare
    ) public {
        price1 = bound(price1, 0, 1e18);
        price2 = bound(price2, price1, 1e18);
        assetPerShare = bound(assetPerShare, 1, 1e18);

        _setOracleState(price1, assetPerShare);
        uint256 result1 = oracle.getAssetPrice(address(bvBTC));

        _setOracleState(price2, assetPerShare);
        uint256 result2 = oracle.getAssetPrice(address(bvBTC));

        assertLe(result1, result2, "higher BTC price should give higher or equal bvBTC price");
    }

    function testFuzz_bvBTCPrice_MonotonicInAssetsPerShare(
        uint256 btcPrice,
        uint256 aps1,
        uint256 aps2
    ) public {
        btcPrice = bound(btcPrice, 1, 1e18);
        aps1 = bound(aps1, 0, 1e18);
        aps2 = bound(aps2, aps1, 1e18);

        _setOracleState(btcPrice, aps1);
        uint256 result1 = oracle.getAssetPrice(address(bvBTC));

        _setOracleState(btcPrice, aps2);
        uint256 result2 = oracle.getAssetPrice(address(bvBTC));

        assertLe(result1, result2, "higher assets per share should give higher or equal bvBTC price");
    }

    function testFuzz_bvBTCPrice_HigherDecimalsLowerPrice(
        uint256 btcPrice,
        uint256 assetPerShare,
        uint8 dec1,
        uint8 dec2
    ) public {
        // More decimals → larger denominator → smaller result
        btcPrice = bound(btcPrice, 1, 1e12);
        assetPerShare = bound(assetPerShare, 1, 1e12);
        dec1 = uint8(bound(uint256(dec1), 1, 16));
        dec2 = uint8(bound(uint256(dec2), uint256(dec1), 16));

        _setOracleState(btcPrice, assetPerShare, dec1);
        uint256 result1 = oracle.getAssetPrice(address(bvBTC));

        _setOracleState(btcPrice, assetPerShare, dec2);
        uint256 result2 = oracle.getAssetPrice(address(bvBTC));

        assertGe(result1, result2, "higher decimals should give smaller or equal price");
    }

    function testFuzz_bvBTCPrice_IdentityAtOneShare(
        uint256 btcPrice,
        uint8 btcDecimals
    ) public {
        // When assetPerShare == 10^btcDecimals (1:1 share), result should equal btcPrice
        btcDecimals = uint8(bound(uint256(btcDecimals), 1, 18));
        btcPrice = bound(btcPrice, 1, type(uint256).max / (10 ** uint256(btcDecimals)));

        uint256 oneShare = 10 ** uint256(btcDecimals);
        _setOracleState(btcPrice, oneShare, btcDecimals);

        uint256 result = oracle.getAssetPrice(address(bvBTC));

        assertEq(result, btcPrice, "1:1 share ratio should return btcPrice");
    }

    function testFuzz_bvBTCPrice_Commutativity(
        uint256 a,
        uint256 b,
        uint8 btcDecimals
    ) public {
        // btcPrice * assetsPerShare is commutative
        btcDecimals = uint8(bound(uint256(btcDecimals), 1, 18));
        a = bound(a, 1, 1e18);
        b = bound(b, 1, 1e18);

        _setOracleState(a, b, btcDecimals);
        uint256 result1 = oracle.getAssetPrice(address(bvBTC));

        _setOracleState(b, a, btcDecimals);
        uint256 result2 = oracle.getAssetPrice(address(bvBTC));

        assertEq(result1, result2, "calculation should be commutative in price and share");
    }

    function testFuzz_bvBTCPrice_OverflowReverts(
        uint256 btcPrice,
        uint256 assetPerShare
    ) public {
        // Large multiplication should revert (SafeMath overflow in 0.6.12 AaveOracle)
        // Both values >= 2^128 guarantees product >= 2^256 which overflows uint256
        btcPrice = bound(btcPrice, uint256(type(uint128).max) + 1, uint256(type(int256).max));
        assetPerShare = bound(assetPerShare, uint256(type(uint128).max) + 1, type(uint256).max);

        _setOracleState(btcPrice, assetPerShare);

        vm.expectRevert();
        oracle.getAssetPrice(address(bvBTC));
    }
}
