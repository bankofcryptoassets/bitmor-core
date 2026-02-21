// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.6.12;

import {DefaultReserveInterestRateStrategy} from "../protocol/lendingpool/DefaultReserveInterestRateStrategy.sol";
import {ILendingPoolAddressesProvider} from "../interfaces/ILendingPoolAddressesProvider.sol";

/// @dev Minimal mock: only implements getLendingRateOracle()
contract MockRateOracleForStrategy {
    uint256 internal _rate;

    function setRate(uint256 rate) external {
        _rate = rate;
    }

    function getMarketBorrowRate(address) external view returns (uint256) {
        return _rate;
    }
}

/// @dev Minimal mock addresses provider returning a lending rate oracle
contract MockProviderForStrategy {
    address internal _lendingRateOracle;

    constructor(address lendingRateOracle_) public {
        _lendingRateOracle = lendingRateOracle_;
    }

    function getLendingRateOracle() external view returns (address) {
        return _lendingRateOracle;
    }
}

/// @dev Harness exposing internal _getOverallBorrowRate
contract InterestRateStrategyHarness is DefaultReserveInterestRateStrategy {
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
        DefaultReserveInterestRateStrategy(
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
