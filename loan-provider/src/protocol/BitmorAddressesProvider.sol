// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {AccessManaged} from "@openzeppelin/contracts/access/manager/AccessManaged.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

import {IBitmorAddressesProvider} from "../interfaces/IBitmorAddressesProvider.sol";
import {Errors} from "../libraries/helpers/Errors.sol";

contract BitmorAddressesProvider is IBitmorAddressesProvider, AccessManaged {
    address public immutable i_LOAN_PROVIDER;

    mapping(bytes32 => address) private _addresses;

    bytes32 private constant LOAN_VAULT_FACTORY = keccak256("LOAN_VAULT_FACTORY");
    bytes32 private constant SWAPPER = keccak256("SWAPPER");
    bytes32 private constant PREMIUM_COLLECTOR = keccak256("PREMIUM_COLLECTOR");
    bytes32 private constant LIQUIDATION_FEE_COLLECTOR = keccak256("LIQUIDATION_FEE_COLLECTOR");
    bytes32 private constant AUTO_REPAYER = keccak256("AUTO_REPAYER");

    modifier checkZeroAddress(address _address) {
        _checkZeroAddress(_address);
        _;
    }

    constructor(address _manager, address _loanProvider)
        checkZeroAddress(_loanProvider)
        checkZeroAddress(_manager)
        AccessManaged(_manager)
    {
        i_LOAN_PROVIDER = _loanProvider;
    }

    function setVaultFactory(address _vaultFactory) external restricted checkZeroAddress(_vaultFactory) {
        _addresses[LOAN_VAULT_FACTORY] = _vaultFactory;
        emit BitmorAddressesProvider__VaultFactoryUpdated(_vaultFactory);
    }

    function setSwapper(address _swapper) external restricted checkZeroAddress(_swapper) {
        _addresses[SWAPPER] = _swapper;
        emit BitmorAddressesProvider__SwapperUpdated(_swapper);
    }

    function setPremiumCollector(address _premiumCollector) external restricted checkZeroAddress(_premiumCollector) {
        _addresses[PREMIUM_COLLECTOR] = _premiumCollector;
        emit BitmorAddressesProvider__PremiumCollectorUpdated(_premiumCollector);
    }

    function setLiquidationFeeCollector(address _liquidationFeeCollector)
        external
        restricted
        checkZeroAddress(_liquidationFeeCollector)
    {
        _addresses[LIQUIDATION_FEE_COLLECTOR] = _liquidationFeeCollector;
        emit BitmorAddressesProvider__LiquidationFeeCollectorUpdated(_liquidationFeeCollector);
    }

    function setAutoRepayer(address _autoRepayer) external restricted checkZeroAddress(_autoRepayer) {
        _addresses[AUTO_REPAYER] = _autoRepayer;
        emit BitmorAddressesProvider__AutoRepayerUpdated(_autoRepayer);
    }

    function getLoanVaultFactory() external view returns (address vaultFactory) {
        vaultFactory = _addresses[LOAN_VAULT_FACTORY];
    }

    function getSwapper() external view returns (address swapper) {
        swapper = _addresses[SWAPPER];
    }

    function getPremiumCollector() external view returns (address premiumCollector) {
        premiumCollector = _addresses[PREMIUM_COLLECTOR];
    }

    function getLiquidationFeeCollector() external view returns (address liquidationFeeCollector) {
        liquidationFeeCollector = _addresses[LIQUIDATION_FEE_COLLECTOR];
    }

    function getAutoRepayer() external view returns (address autoRepayer) {
        autoRepayer = _addresses[AUTO_REPAYER];
    }

    function _checkZeroAddress(address _address) internal pure {
        if (_address == address(0)) revert Errors.ZeroAddress();
    }
}
