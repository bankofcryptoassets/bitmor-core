// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.6.12;

import {SafeMath} from "../dependencies/openzeppelin/contracts/SafeMath.sol";

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
    uint256 internal _convertToAssetsResult;
    uint8 internal _decimals;

    function setConvertToAssets(uint256 result) external {
        _convertToAssetsResult = result;
    }

    function setDecimals(uint8 dec) external {
        _decimals = dec;
    }

    function convertToAssets(uint256) external view returns (uint256) {
        return _convertToAssetsResult;
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

/// @dev Harness that replicates the AaveOracle bvBTC price conversion logic as a pure-ish function.
/// This avoids needing the full AaveOracle constructor with Ownable and Chainlink dependencies.
contract AaveOracleHarness {
    using SafeMath for uint256;

    /// @dev Replicates the bvBTC price conversion from AaveOracle.getAssetPrice():
    /// bvBTCPrice = btcPrice * assetPerShare / (10 ** btcDecimals)
    function calculateBvBTCPrice(
        uint256 btcPrice,
        uint256 assetPerShare,
        uint8 btcDecimals
    ) external pure returns (uint256) {
        return btcPrice.mul(assetPerShare).div(10 ** uint256(btcDecimals));
    }
}
