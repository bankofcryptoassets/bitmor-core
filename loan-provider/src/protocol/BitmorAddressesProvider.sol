// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import {AccessManagedUpgradeable} from "@openzeppelin-upgradeable/access/manager/AccessManagedUpgradeable.sol";

import {IBitmorAddressesProvider} from "../interfaces/IBitmorAddressesProvider.sol";
import {Errors} from "../libraries/helpers/Errors.sol";

contract BitmorAddressesProvider is Initializable, UUPSUpgradeable, IBitmorAddressesProvider, AccessManagedUpgradeable {
    // ============ ERC-7201 Namespaced Storage ============

    bytes32 private constant ADDRESSES_PROVIDER_STORAGE_LOCATION =
        0x8ee1f686d02795c2b874c2b79c204ef2b6969dd63ab11e8118a0fa3cd447b300;

    /// @custom:storage-location erc7201:bitmor.storage.BitmorAddressesProvider
    struct AddressesProviderStorageData {
        /// @dev The Loan contract address
        address loanProvider;
        /// @dev Registry mapping bytes32 keys to contract addresses
        mapping(bytes32 => address) addresses;
    }

    function _getAddressesProviderStorage() internal pure returns (AddressesProviderStorageData storage $) {
        assembly {
            $.slot := ADDRESSES_PROVIDER_STORAGE_LOCATION
        }
    }

    // ============ Constants ============

    bytes32 private constant LOAN_VAULT_FACTORY = keccak256("LOAN_VAULT_FACTORY");
    bytes32 private constant SWAPPER = keccak256("SWAPPER");
    bytes32 private constant PREMIUM_COLLECTOR = keccak256("PREMIUM_COLLECTOR");
    bytes32 private constant LIQUIDATION_FEE_COLLECTOR = keccak256("LIQUIDATION_FEE_COLLECTOR");
    bytes32 private constant AUTO_REPAYER = keccak256("AUTO_REPAYER");

    // ============ Modifiers ============

    modifier checkZeroAddress(address _address) {
        _checkZeroAddress(_address);
        _;
    }

    // ============ Constructor ============

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    // ============ Initialization ============

    /**
     * @notice Initializes the addresses provider
     * @param _manager Access Manager address for role-based access control
     * @param _loanProvider The Loan contract address
     */
    function initialize(address _manager, address _loanProvider)
        public
        initializer
        checkZeroAddress(_manager)
        checkZeroAddress(_loanProvider)
    {
        __AccessManaged_init(_manager);

        _getAddressesProviderStorage().loanProvider = _loanProvider;
    }

    // ============ UUPS ============

    function _authorizeUpgrade(address) internal override restricted {}

    // ============ Setters ============

    function setVaultFactory(address _vaultFactory) external restricted checkZeroAddress(_vaultFactory) {
        _getAddressesProviderStorage().addresses[LOAN_VAULT_FACTORY] = _vaultFactory;
        emit BitmorAddressesProvider__VaultFactoryUpdated(_vaultFactory);
    }

    function setSwapper(address _swapper) external restricted checkZeroAddress(_swapper) {
        _getAddressesProviderStorage().addresses[SWAPPER] = _swapper;
        emit BitmorAddressesProvider__SwapperUpdated(_swapper);
    }

    function setPremiumCollector(address _premiumCollector) external restricted checkZeroAddress(_premiumCollector) {
        _getAddressesProviderStorage().addresses[PREMIUM_COLLECTOR] = _premiumCollector;
        emit BitmorAddressesProvider__PremiumCollectorUpdated(_premiumCollector);
    }

    function setLiquidationFeeCollector(address _liquidationFeeCollector)
        external
        restricted
        checkZeroAddress(_liquidationFeeCollector)
    {
        _getAddressesProviderStorage().addresses[LIQUIDATION_FEE_COLLECTOR] = _liquidationFeeCollector;
        emit BitmorAddressesProvider__LiquidationFeeCollectorUpdated(_liquidationFeeCollector);
    }

    function setAutoRepayer(address _autoRepayer) external restricted checkZeroAddress(_autoRepayer) {
        _getAddressesProviderStorage().addresses[AUTO_REPAYER] = _autoRepayer;
        emit BitmorAddressesProvider__AutoRepayerUpdated(_autoRepayer);
    }

    // ============ Getters ============

    function getLoanVaultFactory() external view returns (address vaultFactory) {
        vaultFactory = _getAddressesProviderStorage().addresses[LOAN_VAULT_FACTORY];
    }

    function getSwapper() external view returns (address swapper) {
        swapper = _getAddressesProviderStorage().addresses[SWAPPER];
    }

    function getPremiumCollector() external view returns (address premiumCollector) {
        premiumCollector = _getAddressesProviderStorage().addresses[PREMIUM_COLLECTOR];
    }

    function getLiquidationFeeCollector() external view returns (address liquidationFeeCollector) {
        liquidationFeeCollector = _getAddressesProviderStorage().addresses[LIQUIDATION_FEE_COLLECTOR];
    }

    function getAutoRepayer() external view returns (address autoRepayer) {
        autoRepayer = _getAddressesProviderStorage().addresses[AUTO_REPAYER];
    }

    // ============ Internal ============

    function _checkZeroAddress(address _address) internal pure {
        if (_address == address(0)) revert Errors.ZeroAddress();
    }
}
