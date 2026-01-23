// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ILendingPool} from "@bitmor/interfaces/ILendingPool.sol";
import {ILendingPoolAddressesProvider} from "@bitmor/interfaces/ILendingPoolAddressesProvider.sol";
import {IPriceOracleGetter} from "@bitmor/interfaces/IPriceOracleGetter.sol";
import {DataTypes} from "@bitmor/libraries/types/DataTypes.sol";
import {IERC20} from "@openzeppelin/interfaces/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";
import {MockAToken} from "./MockAToken.sol";
import {MockVariableDebtToken} from "./MockVariableDebtToken.sol";

/// @title MockBitmorLendingPool
/// @author Bitmor Protocol
/// @notice Mock Bitmor lending pool for unit testing
/// @dev Implements core ILendingPool functions (deposit, withdraw, borrow, repay)
///      Liquidation and stub methods will be added in Task 6
contract MockBitmorLendingPool is ILendingPool {
    /// @notice The addresses provider for this lending pool
    ILendingPoolAddressesProvider private _addressesProvider;

    /// @notice Reserve data storage for each asset
    mapping(address => DataTypes.ReserveData) private _reserves;

    /// @notice User configuration storage
    mapping(address => DataTypes.UserConfigurationMap) private _userConfigurations;

    /// @notice List of initialized reserves
    address[] private _reservesList;

    /// @notice Whether the pool is paused
    bool private _paused;

    /// @notice Storage for liquidation type testing
    mapping(address => uint256) private _liquidationTypes;

    /// @notice Tracks whether a user's loan is overdue (for micro liquidation)
    mapping(address => bool) private _isOverdue;

    /// @notice Tracks user health factors (for full liquidation)
    mapping(address => uint256) private _healthFactors;

    /// @notice Tracks insurance IDs for loans
    mapping(address => uint256) private _insuranceIds;

    /// @notice Default liquidation bonus in basis points (105% = 5% bonus)
    uint256 private constant LIQUIDATION_BONUS_BPS = 10500;

    /// @notice Default variable borrow rate (5% APY in RAY)
    uint256 private constant VARIABLE_BORROW_RATE = 0.05e27;

    /// @notice Default liquidity index (1.0 in RAY)
    uint256 private constant DEFAULT_LIQUIDITY_INDEX = 1e27;

    /// @notice Default variable borrow index (1.0 in RAY)
    uint256 private constant DEFAULT_VARIABLE_BORROW_INDEX = 1e27;

    /// @notice Creates a new MockBitmorLendingPool
    /// @param addressesProvider Address of the LendingPoolAddressesProvider
    constructor(address addressesProvider) {
        _addressesProvider = ILendingPoolAddressesProvider(addressesProvider);
    }

    // ============ Test Helpers ============

    /// @notice Initialize a reserve with aToken and debt token (test helper)
    /// @dev Sets up a reserve with default configuration values for testing
    /// @param asset The underlying asset address
    /// @param aToken The aToken address for this reserve
    /// @param variableDebtToken The variable debt token address for this reserve
    function initReserve(address asset, address aToken, address variableDebtToken) external {
        _initReserveInternal(asset, aToken, variableDebtToken, address(0));
    }

    /// @notice Initialize a reserve with aToken, debt token, and interest rate strategy
    /// @param asset The underlying asset address
    /// @param aToken The aToken address for this reserve
    /// @param variableDebtToken The variable debt token address for this reserve
    /// @param interestRateStrategy The interest rate strategy address
    function initReserveWithStrategy(
        address asset,
        address aToken,
        address variableDebtToken,
        address interestRateStrategy
    ) external {
        _initReserveInternal(asset, aToken, variableDebtToken, interestRateStrategy);
    }

    /// @dev Internal function to initialize a reserve
    function _initReserveInternal(
        address asset,
        address aToken,
        address variableDebtToken,
        address interestRateStrategy
    ) internal {
        DataTypes.ReserveData storage reserve = _reserves[asset];
        reserve.aTokenAddress = aToken;
        reserve.variableDebtTokenAddress = variableDebtToken;
        reserve.interestRateStrategyAddress = interestRateStrategy;
        reserve.currentVariableBorrowRate = uint128(VARIABLE_BORROW_RATE);
        reserve.liquidityIndex = uint128(DEFAULT_LIQUIDITY_INDEX);
        reserve.variableBorrowIndex = uint128(DEFAULT_VARIABLE_BORROW_INDEX);
        reserve.lastUpdateTimestamp = uint40(block.timestamp);
        // Set configuration with liquidation bonus at bits 32-47
        reserve.configuration.data = LIQUIDATION_BONUS_BPS << 32;
        reserve.id = uint8(_reservesList.length);
        _reservesList.push(asset);
    }

    // ============ Core Functions ============

    /// @inheritdoc ILendingPool
    function deposit(address asset, uint256 amount, address onBehalfOf, uint16) external override {
        DataTypes.ReserveData storage reserve = _reserves[asset];
        require(reserve.aTokenAddress != address(0), "Reserve not initialized");

        IERC20(asset).transferFrom(msg.sender, address(this), amount);
        MockAToken(reserve.aTokenAddress).mint(onBehalfOf, amount);

        emit Deposit(asset, msg.sender, onBehalfOf, amount, 0);
    }

    /// @inheritdoc ILendingPool
    function withdraw(address asset, uint256 amount, address to) external override returns (uint256) {
        DataTypes.ReserveData storage reserve = _reserves[asset];
        require(reserve.aTokenAddress != address(0), "Reserve not initialized");

        MockAToken aToken = MockAToken(reserve.aTokenAddress);
        uint256 userBalance = aToken.balanceOf(msg.sender);
        uint256 amountToWithdraw = amount == type(uint256).max ? userBalance : amount;
        if (amountToWithdraw > userBalance) {
            amountToWithdraw = userBalance;
        }

        aToken.burn(msg.sender, amountToWithdraw);
        IERC20(asset).transfer(to, amountToWithdraw);

        emit Withdraw(asset, msg.sender, to, amountToWithdraw);
        return amountToWithdraw;
    }

    /// @inheritdoc ILendingPool
    function borrow(address asset, uint256 amount, uint256, uint16, address onBehalfOf) external override {
        DataTypes.ReserveData storage reserve = _reserves[asset];
        require(reserve.variableDebtTokenAddress != address(0), "Reserve not initialized");

        MockVariableDebtToken(reserve.variableDebtTokenAddress).mint(onBehalfOf, amount);
        IERC20(asset).transfer(msg.sender, amount);

        emit Borrow(asset, msg.sender, onBehalfOf, amount, 2, reserve.currentVariableBorrowRate, 0);
    }

    /// @inheritdoc ILendingPool
    function repay(address asset, uint256 amount, uint256, address onBehalfOf) external override returns (uint256) {
        DataTypes.ReserveData storage reserve = _reserves[asset];
        require(reserve.variableDebtTokenAddress != address(0), "Reserve not initialized");

        MockVariableDebtToken debtToken = MockVariableDebtToken(reserve.variableDebtTokenAddress);
        uint256 currentDebt = debtToken.balanceOf(onBehalfOf);
        uint256 amountToRepay = amount == type(uint256).max ? currentDebt : amount;
        if (amountToRepay > currentDebt) {
            amountToRepay = currentDebt;
        }

        IERC20(asset).transferFrom(msg.sender, address(this), amountToRepay);
        debtToken.burn(onBehalfOf, amountToRepay);

        emit Repay(asset, onBehalfOf, msg.sender, amountToRepay);
        return amountToRepay;
    }

    // ============ View Functions ============

    /// @inheritdoc ILendingPool
    function getAddressesProvider() external view override returns (ILendingPoolAddressesProvider) {
        return _addressesProvider;
    }

    /// @inheritdoc ILendingPool
    function getReserveData(address asset) external view override returns (DataTypes.ReserveData memory) {
        return _reserves[asset];
    }

    /// @inheritdoc ILendingPool
    function getConfiguration(address asset) external view override returns (DataTypes.ReserveConfigurationMap memory) {
        return _reserves[asset].configuration;
    }

    /// @inheritdoc ILendingPool
    function getUserConfiguration(address user) external view override returns (DataTypes.UserConfigurationMap memory) {
        return _userConfigurations[user];
    }

    /// @inheritdoc ILendingPool
    function getReserveNormalizedIncome(address asset) external view override returns (uint256) {
        return _reserves[asset].liquidityIndex;
    }

    /// @inheritdoc ILendingPool
    function getReserveNormalizedVariableDebt(address asset) external view override returns (uint256) {
        return _reserves[asset].variableBorrowIndex;
    }

    /// @inheritdoc ILendingPool
    function getReservesList() external view override returns (address[] memory) {
        return _reservesList;
    }

    /// @inheritdoc ILendingPool
    function paused() external view override returns (bool) {
        return _paused;
    }

    // ============ Stub Functions (to be completed in Task 6) ============

    /// @inheritdoc ILendingPool
    function swapBorrowRateMode(address, uint256) external override {
        // Stub - not implemented for mock
    }

    /// @inheritdoc ILendingPool
    function rebalanceStableBorrowRate(address, address) external override {
        // Stub - not implemented for mock
    }

    /// @inheritdoc ILendingPool
    function setUserUseReserveAsCollateral(address, bool) external override {
        // Stub - not implemented for mock
    }

    /// @inheritdoc ILendingPool
    function liquidationCall(
        address collateralAsset,
        address debtAsset,
        address user,
        uint256 debtToCover,
        bool receiveAToken
    ) external override {
        DataTypes.ReserveData storage collateralReserve = _reserves[collateralAsset];
        DataTypes.ReserveData storage debtReserve = _reserves[debtAsset];

        MockVariableDebtToken debtToken = MockVariableDebtToken(debtReserve.variableDebtTokenAddress);
        MockAToken aToken = MockAToken(collateralReserve.aTokenAddress);

        uint256 userDebt = debtToken.balanceOf(user);
        uint256 actualDebtToCover = debtToCover > userDebt ? userDebt : debtToCover;

        // Calculate collateral to seize with liquidation bonus
        uint256 collateralToSeize = (actualDebtToCover * LIQUIDATION_BONUS_BPS) / 10000;

        // Transfer debt from liquidator
        IERC20(debtAsset).transferFrom(msg.sender, address(this), actualDebtToCover);
        debtToken.burn(user, actualDebtToCover);

        // Seize collateral
        uint256 userCollateral = aToken.balanceOf(user);
        uint256 actualCollateralSeized = collateralToSeize > userCollateral ? userCollateral : collateralToSeize;

        if (receiveAToken) {
            // Transfer aTokens to liquidator
            aToken.burn(user, actualCollateralSeized);
            aToken.mint(msg.sender, actualCollateralSeized);
        } else {
            // Transfer underlying to liquidator
            aToken.burn(user, actualCollateralSeized);
            IERC20(collateralAsset).transfer(msg.sender, actualCollateralSeized);
        }

        emit LiquidationCall(
            collateralAsset, debtAsset, user, actualDebtToCover, actualCollateralSeized, msg.sender, receiveAToken
        );
    }

    /// @inheritdoc ILendingPool
    function microLiquidationCall(bytes calldata data) external override {
        (address collateralAsset, address debtAsset, address user) = abi.decode(data, (address, address, address));

        DataTypes.ReserveData storage debtReserve = _reserves[debtAsset];
        MockVariableDebtToken debtToken = MockVariableDebtToken(debtReserve.variableDebtTokenAddress);

        uint256 userDebt = debtToken.balanceOf(user);
        // Micro liquidation covers 1/12 of debt (one month's payment)
        uint256 debtToCover = userDebt / 12;
        if (debtToCover == 0) debtToCover = userDebt;

        // Call internal liquidation
        this.liquidationCall(collateralAsset, debtAsset, user, debtToCover, false);
    }

    /// @inheritdoc ILendingPool
    function checkTypeOfLiquidation(address user) external view override returns (uint256) {
        // If manually set via setLiquidationType, use that value
        if (_liquidationTypes[user] != 0) {
            return _liquidationTypes[user];
        }

        // Compute based on state
        uint256 hf = _healthFactors[user];

        // If health factor is set and < 1e18, full liquidation
        if (hf > 0 && hf < 1e18) {
            return 1; // Full liquidation
        }

        // If loan is overdue, micro liquidation
        if (_isOverdue[user]) {
            return 2; // Micro liquidation
        }

        // No liquidation needed
        return 0;
    }

    /// @notice Set the liquidation type for a user (test helper)
    /// @param user The user address
    /// @param liquidationType 0=none, 1=full, 2=micro
    function setLiquidationType(address user, uint256 liquidationType) external {
        _liquidationTypes[user] = liquidationType;
    }

    /// @notice Set whether a user's loan is overdue (test helper)
    /// @param user The user address
    /// @param overdue Whether the loan is overdue
    function setUserOverdue(address user, bool overdue) external {
        _isOverdue[user] = overdue;
    }

    /// @notice Set a user's health factor (test helper)
    /// @param user The user address
    /// @param healthFactor The health factor (1e18 = 1.0)
    function setHealthFactor(address user, uint256 healthFactor) external {
        _healthFactors[user] = healthFactor;
    }

    /// @notice Set insurance ID for a loan (test helper)
    /// @param lsa The loan smart account address
    /// @param insuranceId The insurance ID
    function setInsuranceId(address lsa, uint256 insuranceId) external {
        _insuranceIds[lsa] = insuranceId;
    }

    /// @notice Get insurance ID for a loan
    /// @param lsa The loan smart account address
    /// @return The insurance ID
    function getInsuranceId(address lsa) external view returns (uint256) {
        return _insuranceIds[lsa];
    }

    /// @notice Check if user loan is overdue
    /// @param user The user address
    /// @return Whether the loan is overdue
    function isUserOverdue(address user) external view returns (bool) {
        return _isOverdue[user];
    }

    /// @inheritdoc ILendingPool
    function flashLoan(
        address,
        address[] calldata,
        uint256[] calldata,
        uint256[] calldata,
        address,
        bytes calldata,
        uint16
    ) external override {
        // Stub - not implemented for mock
    }

    /// @inheritdoc ILendingPool
    function getUserAccountData(address user)
        external
        view
        override
        returns (uint256 totalCollateralUSD, uint256 totalDebtUSD, uint256, uint256, uint256, uint256 healthFactor)
    {
        // Get oracle from addresses provider
        address oracle = _addressesProvider.getPriceOracle();

        // Calculate total collateral and debt across all reserves
        for (uint256 i = 0; i < _reservesList.length; i++) {
            address asset = _reservesList[i];
            DataTypes.ReserveData storage reserve = _reserves[asset];

            // Get asset price from oracle (8 decimals)
            uint256 assetPrice = IPriceOracleGetter(oracle).getAssetPrice(asset);

            // Get asset decimals
            uint8 decimals = IERC20Metadata(asset).decimals();

            // Add collateral value (aToken balance * price)
            if (reserve.aTokenAddress != address(0)) {
                uint256 aTokenBalance = IERC20(reserve.aTokenAddress).balanceOf(user);
                if (aTokenBalance > 0) {
                    // Normalize to 8 decimals (USD)
                    totalCollateralUSD += (aTokenBalance * assetPrice) / (10 ** decimals);
                }
            }

            // Add debt value (vdtToken balance * price)
            if (reserve.variableDebtTokenAddress != address(0)) {
                uint256 debtBalance = IERC20(reserve.variableDebtTokenAddress).balanceOf(user);
                if (debtBalance > 0) {
                    // Normalize to 8 decimals (USD)
                    totalDebtUSD += (debtBalance * assetPrice) / (10 ** decimals);
                }
            }
        }

        // Calculate health factor (collateral / debt, scaled by 1e18)
        if (totalDebtUSD == 0) {
            healthFactor = type(uint256).max; // Infinite health factor if no debt
        } else {
            healthFactor = (totalCollateralUSD * 1e18) / totalDebtUSD;
        }

        return (totalCollateralUSD, totalDebtUSD, 0, 0, 0, healthFactor);
    }

    /// @inheritdoc ILendingPool
    function initReserve(address, address, address, address, address) external override {
        // Stub - use the simplified initReserve(asset, aToken, variableDebtToken) for testing
    }

    /// @inheritdoc ILendingPool
    function setReserveInterestRateStrategyAddress(address, address) external override {
        // Stub - not implemented for mock
    }

    /// @inheritdoc ILendingPool
    function setConfiguration(address asset, uint256 configuration) external override {
        _reserves[asset].configuration.data = configuration;
    }

    /// @inheritdoc ILendingPool
    function finalizeTransfer(address, address, address, uint256, uint256, uint256) external override {
        // Stub - not implemented for mock
    }

    /// @inheritdoc ILendingPool
    function setPause(bool val) external override {
        _paused = val;
        if (val) {
            emit Paused();
        } else {
            emit Unpaused();
        }
    }
}
