// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.30;

/**
 * @title ILendingPoolAddressesProvider
 * @author Aave / Bitmor Protocol
 * @notice Interface for the Bitmor Lending Pool Addresses Provider registry
 * @dev Main registry of addresses connected to the protocol, including permissioned roles.
 * Extended with Bitmor-specific functions for the Loan contract address.
 */
interface ILendingPoolAddressesProvider {
    /// @notice Emitted when the market identifier is updated
    event MarketIdSet(string newMarketId);
    /// @notice Emitted when the LendingPool address is updated
    event LendingPoolUpdated(address indexed newAddress);
    /// @notice Emitted when the configuration admin is updated
    event ConfigurationAdminUpdated(address indexed newAddress);
    /// @notice Emitted when the emergency admin is updated
    event EmergencyAdminUpdated(address indexed newAddress);
    /// @notice Emitted when the LendingPoolConfigurator is updated
    event LendingPoolConfiguratorUpdated(address indexed newAddress);
    /// @notice Emitted when the LendingPoolCollateralManager is updated
    event LendingPoolCollateralManagerUpdated(address indexed newAddress);
    /// @notice Emitted when the price oracle is updated
    event PriceOracleUpdated(address indexed newAddress);
    /// @notice Emitted when the Bitmor Loan contract address is updated
    event BitmorLoanUpdated(address indexed bitmorLoan);
    /// @notice Emitted when the lending rate oracle is updated
    event LendingRateOracleUpdated(address indexed newAddress);
    /// @notice Emitted when a new proxy is created
    event ProxyCreated(bytes32 id, address indexed newAddress);
    /// @notice Emitted when an address is set in the registry
    event AddressSet(bytes32 id, address indexed newAddress, bool hasProxy);

    /// @notice Returns the market identifier string.
    function getMarketId() external view returns (string memory);

    /// @notice Sets the `marketId` for this addresses provider.
    function setMarketId(string calldata marketId) external;

    /// @notice Sets a raw address for the given `id`.
    function setAddress(bytes32 id, address newAddress) external;

    /// @notice Sets a proxy implementation address for the given `id`.
    function setAddressAsProxy(bytes32 id, address impl) external;

    /// @notice Returns the address registered for the given `id`.
    function getAddress(bytes32 id) external view returns (address);

    /// @notice Returns the LendingPool proxy address.
    function getLendingPool() external view returns (address);

    /// @notice Sets the LendingPool implementation address.
    function setLendingPoolImpl(address pool) external;

    /// @notice Returns the LendingPoolConfigurator proxy address.
    function getLendingPoolConfigurator() external view returns (address);

    /// @notice Sets the LendingPoolConfigurator implementation address.
    function setLendingPoolConfiguratorImpl(address configurator) external;

    /// @notice Returns the LendingPoolCollateralManager address.
    function getLendingPoolCollateralManager() external view returns (address);

    /// @notice Sets the LendingPoolCollateralManager address.
    function setLendingPoolCollateralManager(address manager) external;

    /// @notice Returns the pool admin address.
    function getPoolAdmin() external view returns (address);

    /// @notice Sets the pool admin address.
    function setPoolAdmin(address admin) external;

    /// @notice Returns the emergency admin address.
    function getEmergencyAdmin() external view returns (address);

    /// @notice Sets the emergency admin address.
    function setEmergencyAdmin(address admin) external;

    /// @notice Returns the price oracle address.
    function getPriceOracle() external view returns (address);

    /// @notice Sets the price oracle address.
    function setPriceOracle(address priceOracle) external;

    /// @notice Returns the lending rate oracle address.
    function getLendingRateOracle() external view returns (address);

    /// @notice Sets the lending rate oracle address.
    function setLendingRateOracle(address lendingRateOracle) external;

    /// @notice Returns the Bitmor Loan contract address.
    function getBitmorLoan() external view returns (address);

    /// @notice Sets the Bitmor Loan contract address.
    function setBitmorLoan(address bitmorLoan) external;
}
