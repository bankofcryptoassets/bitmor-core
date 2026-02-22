// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import {LoanLiquidationLogic} from "../protocol/libraries/logic/LoanLiquidationLogic.sol";
import {DataTypes} from "../protocol/libraries/types/DataTypes.sol";
import {ReserveConfiguration} from "../protocol/libraries/configuration/ReserveConfiguration.sol";
import {ILoan} from "../interfaces/ILoan.sol";

/// @dev Mock token returning configurable balanceOf
contract MockBalanceToken {
    mapping(address => uint256) internal _balances;

    function setBalance(address user, uint256 amount) external {
        _balances[user] = amount;
    }

    function balanceOf(address user) external view returns (uint256) {
        return _balances[user];
    }
}

/// @dev Mock price oracle
contract MockOracleForLiquidation {
    mapping(address => uint256) internal _prices;

    function setAssetPrice(address asset, uint256 price) external {
        _prices[asset] = price;
    }

    function getAssetPrice(address asset) external view returns (uint256) {
        return _prices[asset];
    }
}

/// @dev Mock ILoan returning configurable loan data
contract MockLoanForLiquidation {
    DataTypes.LoanData internal _loanData;
    address internal _collateralAsset;
    address internal _debtAsset;
    uint256 internal _gracePeriod;
    uint256 internal _repaymentInterval;

    function setLoanData(
        address borrower,
        uint256 depositAmount,
        uint256 loanAmount,
        uint256 btcAmount,
        uint256 estimatedMonthlyPayment,
        uint256 duration,
        uint256 createdAt,
        uint256 insuranceID,
        uint256 lastPaymentTimestamp,
        uint256 amountRepaidInCurrentPeriod,
        DataTypes.LoanStatus status
    ) external {
        _loanData = DataTypes.LoanData({
            borrower: borrower,
            depositAmount: depositAmount,
            loanAmount: loanAmount,
            btcAmount: btcAmount,
            estimatedMonthlyPayment: estimatedMonthlyPayment,
            duration: duration,
            createdAt: createdAt,
            insuranceID: insuranceID,
            lastPaymentTimestamp: lastPaymentTimestamp,
            amountRepaidInCurrentPeriod: amountRepaidInCurrentPeriod,
            status: status
        });
    }

    function setCollateralAsset(address asset) external {
        _collateralAsset = asset;
    }

    function setDebtAsset(address asset) external {
        _debtAsset = asset;
    }

    function setGracePeriod(uint256 period) external {
        _gracePeriod = period;
    }

    function setRepaymentInterval(uint256 interval) external {
        _repaymentInterval = interval;
    }

    function getLoanByLSA(address) external view returns (DataTypes.LoanData memory) {
        return _loanData;
    }

    function getCollateralAsset() external view returns (address) {
        return _collateralAsset;
    }

    function getDebtAsset() external view returns (address) {
        return _debtAsset;
    }

    function getGracePeriod() external view returns (uint256) {
        return _gracePeriod;
    }

    function getRepaymentInterval() external view returns (uint256) {
        return _repaymentInterval;
    }
}

/// @dev Harness wrapping LoanLiquidationLogic with controllable storage
contract LoanLiquidationLogicHarness {
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;

    mapping(address => DataTypes.ReserveData) internal _reservesData;

    /// @dev Set the raw configuration bitmap for a reserve
    function setReserveConfigData(address asset, uint256 configData) external {
        _reservesData[asset].configuration.data = configData;
    }

    /// @dev Set the variable debt token address for a reserve
    function setReserveVariableDebtToken(address asset, address token) external {
        _reservesData[asset].variableDebtTokenAddress = token;
    }

    /// @dev Set the stable debt token address for a reserve
    function setReserveStableDebtToken(address asset, address token) external {
        _reservesData[asset].stableDebtTokenAddress = token;
    }

    /// @dev Set the aToken address for a reserve
    function setReserveAToken(address asset, address token) external {
        _reservesData[asset].aTokenAddress = token;
    }

    function checkTypeOfLiquidation(
        address user,
        uint256 hf,
        address oracle,
        address bitmorLoan
    ) external view returns (uint256) {
        return LoanLiquidationLogic.checkTypeOfLiquidation(
            user,
            _reservesData,
            hf,
            oracle,
            ILoan(bitmorLoan)
        );
    }
}
