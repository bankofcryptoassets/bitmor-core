// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ILendingPoolAddressesProvider} from "@bitmor/interfaces/ILendingPoolAddressesProvider.sol";

/// @title MockAddressesProvider
/// @author Bitmor Protocol
/// @notice Mock addresses provider for unit testing
/// @dev Implements ILendingPoolAddressesProvider with configurable addresses and stubbed methods
contract MockAddressesProvider is ILendingPoolAddressesProvider {
    // ============ State Variables ============

    string private _marketId;
    address private _lendingPool;
    address private _lendingPoolConfigurator;
    address private _lendingPoolCollateralManager;
    address private _poolAdmin;
    address private _emergencyAdmin;
    address private _priceOracle;
    address private _lendingRateOracle;
    address private _bitmorLoan;

    /// @dev Generic address storage for arbitrary IDs
    mapping(bytes32 => address) private _addresses;

    // ============ Constructor ============

    /// @notice Initializes the mock with key addresses
    /// @param lendingPool Address of the lending pool
    /// @param priceOracle Address of the price oracle
    /// @param poolAdmin Address of the pool admin
    constructor(address lendingPool, address priceOracle, address poolAdmin) {
        _lendingPool = lendingPool;
        _priceOracle = priceOracle;
        _poolAdmin = poolAdmin;
        _marketId = "Bitmor";
    }

    // ============ Market ID ============

    /// @inheritdoc ILendingPoolAddressesProvider
    function getMarketId() external view override returns (string memory) {
        return _marketId;
    }

    /// @inheritdoc ILendingPoolAddressesProvider
    function setMarketId(string calldata marketId) external override {
        _marketId = marketId;
        emit MarketIdSet(marketId);
    }

    // ============ Generic Address Management ============

    /// @inheritdoc ILendingPoolAddressesProvider
    function setAddress(bytes32 id, address newAddress) external override {
        _addresses[id] = newAddress;
        emit AddressSet(id, newAddress, false);
    }

    /// @inheritdoc ILendingPoolAddressesProvider
    function setAddressAsProxy(bytes32 id, address impl) external override {
        // In mock, we just store the address directly (no proxy deployment)
        _addresses[id] = impl;
        emit ProxyCreated(id, impl);
    }

    /// @inheritdoc ILendingPoolAddressesProvider
    function getAddress(bytes32 id) external view override returns (address) {
        return _addresses[id];
    }

    // ============ Lending Pool ============

    /// @inheritdoc ILendingPoolAddressesProvider
    function getLendingPool() external view override returns (address) {
        return _lendingPool;
    }

    /// @inheritdoc ILendingPoolAddressesProvider
    function setLendingPoolImpl(address pool) external override {
        _lendingPool = pool;
        emit LendingPoolUpdated(pool);
    }

    /// @notice Sets the lending pool address directly (test helper)
    /// @param pool Address of the lending pool
    function setLendingPool(address pool) external {
        _lendingPool = pool;
        emit LendingPoolUpdated(pool);
    }

    // ============ Lending Pool Configurator ============

    /// @inheritdoc ILendingPoolAddressesProvider
    function getLendingPoolConfigurator() external view override returns (address) {
        return _lendingPoolConfigurator;
    }

    /// @inheritdoc ILendingPoolAddressesProvider
    function setLendingPoolConfiguratorImpl(address configurator) external override {
        _lendingPoolConfigurator = configurator;
        emit LendingPoolConfiguratorUpdated(configurator);
    }

    /// @notice Sets the lending pool configurator address directly (test helper)
    /// @param configurator Address of the configurator
    function setLendingPoolConfigurator(address configurator) external {
        _lendingPoolConfigurator = configurator;
        emit LendingPoolConfiguratorUpdated(configurator);
    }

    // ============ Lending Pool Collateral Manager ============

    /// @inheritdoc ILendingPoolAddressesProvider
    function getLendingPoolCollateralManager() external view override returns (address) {
        return _lendingPoolCollateralManager;
    }

    /// @inheritdoc ILendingPoolAddressesProvider
    function setLendingPoolCollateralManager(address manager) external override {
        _lendingPoolCollateralManager = manager;
        emit LendingPoolCollateralManagerUpdated(manager);
    }

    // ============ Pool Admin ============

    /// @inheritdoc ILendingPoolAddressesProvider
    function getPoolAdmin() external view override returns (address) {
        return _poolAdmin;
    }

    /// @inheritdoc ILendingPoolAddressesProvider
    function setPoolAdmin(address admin) external override {
        _poolAdmin = admin;
        emit ConfigurationAdminUpdated(admin);
    }

    // ============ Emergency Admin ============

    /// @inheritdoc ILendingPoolAddressesProvider
    function getEmergencyAdmin() external view override returns (address) {
        return _emergencyAdmin;
    }

    /// @inheritdoc ILendingPoolAddressesProvider
    function setEmergencyAdmin(address admin) external override {
        _emergencyAdmin = admin;
        emit EmergencyAdminUpdated(admin);
    }

    // ============ Price Oracle ============

    /// @inheritdoc ILendingPoolAddressesProvider
    function getPriceOracle() external view override returns (address) {
        return _priceOracle;
    }

    /// @inheritdoc ILendingPoolAddressesProvider
    function setPriceOracle(address priceOracle) external override {
        _priceOracle = priceOracle;
        emit PriceOracleUpdated(priceOracle);
    }

    // ============ Lending Rate Oracle ============

    /// @inheritdoc ILendingPoolAddressesProvider
    function getLendingRateOracle() external view override returns (address) {
        return _lendingRateOracle;
    }

    /// @inheritdoc ILendingPoolAddressesProvider
    function setLendingRateOracle(address lendingRateOracle) external override {
        _lendingRateOracle = lendingRateOracle;
        emit LendingRateOracleUpdated(lendingRateOracle);
    }

    // ============ Bitmor Loan ============

    /// @inheritdoc ILendingPoolAddressesProvider
    function getBitmorLoan() external view override returns (address) {
        return _bitmorLoan;
    }

    /// @inheritdoc ILendingPoolAddressesProvider
    function setBitmorLoan(address bitmorLoan) external override {
        _bitmorLoan = bitmorLoan;
        emit BitmorLoanUpdated(bitmorLoan);
    }
}
