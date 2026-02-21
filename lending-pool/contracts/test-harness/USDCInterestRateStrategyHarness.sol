// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.6.12;

import {USDCReserveInterestRateStrategy} from "../protocol/lendingpool/USDCReserveInterestRateStrategy.sol";
import {ILendingPoolAddressesProvider} from "../interfaces/ILendingPoolAddressesProvider.sol";

/// @dev Minimal mock: only implements getLendingRateOracle()
contract MockRateOracleForUSDCStrategy {
    uint256 internal _rate;

    function setRate(uint256 rate) external {
        _rate = rate;
    }

    function getMarketBorrowRate(address) external view returns (uint256) {
        return _rate;
    }
}

/// @dev Minimal mock USDC vault: returns configurable totalAssets and asset address
contract MockUSDCVaultForStrategy {
    uint256 internal _totalAssets;
    address internal _asset;

    function setTotalAssets(uint256 totalAssets_) external {
        _totalAssets = totalAssets_;
    }

    function setAsset(address asset_) external {
        _asset = asset_;
    }

    function totalAssets() external view returns (uint256) {
        return _totalAssets;
    }

    function asset() external view returns (address) {
        return _asset;
    }
}

/// @dev Minimal mock addresses provider for USDC strategy
contract MockProviderForUSDCStrategy {
    address internal _lendingRateOracle;
    address internal _usdcVault;

    constructor(address lendingRateOracle_, address usdcVault_) public {
        _lendingRateOracle = lendingRateOracle_;
        _usdcVault = usdcVault_;
    }

    function getLendingRateOracle() external view returns (address) {
        return _lendingRateOracle;
    }

    function getUSDCVault() external view returns (address) {
        return _usdcVault;
    }
}

/// @dev Harness exposing internal _getOverallBorrowRate for USDC strategy
contract USDCInterestRateStrategyHarness is USDCReserveInterestRateStrategy {
    constructor(
        ILendingPoolAddressesProvider provider,
        uint256 optimalUtilizationRate,
        uint256 baseVariableBorrowRate,
        uint256 variableRateSlope1,
        uint256 variableRateSlope2,
        uint256 stableRateSlope1,
        uint256 stableRateSlope2
    )
        public
        USDCReserveInterestRateStrategy(
            provider,
            optimalUtilizationRate,
            baseVariableBorrowRate,
            variableRateSlope1,
            variableRateSlope2,
            stableRateSlope1,
            stableRateSlope2
        )
    {}

    function exposed_getOverallBorrowRate(
        uint256 totalStableDebt,
        uint256 totalVariableDebt,
        uint256 currentVariableBorrowRate,
        uint256 currentAverageStableBorrowRate
    ) external pure returns (uint256) {
        return _getOverallBorrowRate(
            totalStableDebt,
            totalVariableDebt,
            currentVariableBorrowRate,
            currentAverageStableBorrowRate
        );
    }
}
