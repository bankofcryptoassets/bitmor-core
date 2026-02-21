// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.6.12;

import {AaveOracle} from "../misc/AaveOracle.sol";

/// @dev Mock Chainlink aggregator for oracle harness tests
contract MockChainlinkForOracle {
    int256 internal _answer;

    function setAnswer(int256 answer_) external {
        _answer = answer_;
    }

    function latestAnswer() external view returns (int256) {
        return _answer;
    }
}

/// @dev Mock ERC4626 vault for bvBTC price conversion
contract MockVaultForOracle {
    uint256 internal _previewRedeemResult;
    uint8 internal _decimals;

    function setPreviewRedeem(uint256 result) external {
        _previewRedeemResult = result;
    }

    function setDecimals(uint8 dec) external {
        _decimals = dec;
    }

    function previewRedeem(uint256) external view returns (uint256) {
        return _previewRedeemResult;
    }

    function decimals() external view returns (uint8) {
        return _decimals;
    }
}

/// @dev Mock BTC token for decimals
contract MockBTCForOracle {
    uint8 internal _decimals;

    function setDecimals(uint8 dec) external {
        _decimals = dec;
    }

    function decimals() external view returns (uint8) {
        return _decimals;
    }
}

/// @dev Mock fallback oracle
contract MockFallbackOracle {
    mapping(address => uint256) internal _prices;

    function setAssetPrice(address asset, uint256 price) external {
        _prices[asset] = price;
    }

    function getAssetPrice(address asset) external view returns (uint256) {
        return _prices[asset];
    }
}

/// @dev Harness that inherits from the real AaveOracle for fuzz testing.
/// Tests exercise the actual getAssetPrice() code path instead of a reimplemented formula.
contract AaveOracleHarness is AaveOracle {
    constructor(
        address[] memory assets,
        address[] memory sources,
        address btc,
        address bvBTC,
        address fallbackOracle,
        address baseCurrency,
        uint256 baseCurrencyUnit
    )
        public
        AaveOracle(assets, sources, btc, bvBTC, fallbackOracle, baseCurrency, baseCurrencyUnit)
    {}
}
