// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import {LendingPoolConfigurator} from "../protocol/lendingpool/LendingPoolConfigurator.sol";
import {DataTypes} from "../protocol/libraries/types/DataTypes.sol";

/// @dev Mock LendingPool for LendingPoolConfigurator harness tests.
/// Implements getConfiguration, setConfiguration, and getReserveData.
contract MockPoolForLPC {
    mapping(address => uint256) internal _configurations;

    function getConfiguration(address asset)
        external
        view
        returns (DataTypes.ReserveConfigurationMap memory)
    {
        return DataTypes.ReserveConfigurationMap(_configurations[asset]);
    }

    function setConfiguration(address asset, uint256 data) external {
        _configurations[asset] = data;
    }

    /// @dev Returns default (all-zero) reserve data.
    /// currentLiquidityRate == 0 satisfies _checkNoLiquidity.
    function getReserveData(address) external pure returns (DataTypes.ReserveData memory) {
        DataTypes.ReserveData memory data;
        return data;
    }
}

/// @dev Mock addresses provider for LendingPoolConfigurator harness tests.
contract MockAddressesProviderForLPC {
    address internal _poolAdmin;
    address internal _pool;

    function setPoolAdmin(address admin) external {
        _poolAdmin = admin;
    }

    function setLendingPool(address pool_) external {
        _pool = pool_;
    }

    function getPoolAdmin() external view returns (address) {
        return _poolAdmin;
    }

    function getLendingPool() external view returns (address) {
        return _pool;
    }
}

/// @dev Mock ERC20 asset that returns 0 balance for any address.
/// Used by _checkNoLiquidity when threshold is set to 0.
contract MockAssetForLPC {
    function balanceOf(address) external pure returns (uint256) {
        return 0;
    }
}

/// @dev Harness that inherits from the real LendingPoolConfigurator.
/// Tests exercise the actual configureReserveAsCollateral code path.
contract LendingPoolConfiguratorHarness is LendingPoolConfigurator {}
