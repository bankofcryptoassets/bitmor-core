// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {Loan} from "@bitmor/protocol/Loan.sol";
import {LoanVault} from "@bitmor/protocol/LoanVault.sol";
import {LoanVaultFactory} from "@bitmor/protocol/LoanVaultFactory.sol";
import {BeaconController} from "@bitmor/protocol/BeaconController.sol";
import {BTCVault} from "@btcVault/BTCVault.sol";
import {USDCVault} from "@usdcVault/USDCVault.sol";
import {AutoRepayment} from "@bitmor/protocol/AutoRepayment.sol";
import {BitmorAddressesProvider} from "@bitmor/protocol/BitmorAddressesProvider.sol";
import {ILoan} from "@bitmor/interfaces/ILoan.sol";

/// @title ProxyTestHelper
/// @notice Shared proxy deployment functions for test infrastructure
/// @dev Uses ERC1967Proxy directly (no FFI) for fast test execution.
///      All functions deploy implementation + proxy in one call and return typed contracts.
abstract contract ProxyTestHelper is Test {
    /// @dev EIP-1967 implementation storage slot
    bytes32 constant IMPL_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    // ===== UUPS Proxy Helpers =====

    /// @notice Deploys Loan behind ERC1967Proxy
    /// @param params InitParams struct with all initialization parameters
    /// @return The Loan contract instance (cast from proxy address)
    function _deployLoanProxy(ILoan.InitParams memory params) internal returns (Loan) {
        Loan impl = new Loan();
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), abi.encodeCall(Loan.initialize, (params)));
        return Loan(address(proxy));
    }

    /// @notice Deploys BTCVault behind ERC1967Proxy
    /// @param _asset The underlying asset (cbBTC) address
    /// @param _manager AccessManager address
    /// @param _maxStrategies Maximum number of strategies
    /// @return The BTCVault contract instance
    function _deployBTCVaultProxy(address _asset, address _manager, uint256 _maxStrategies)
        internal
        returns (BTCVault)
    {
        BTCVault impl = new BTCVault();
        ERC1967Proxy proxy =
            new ERC1967Proxy(address(impl), abi.encodeCall(BTCVault.initialize, (_asset, _manager, _maxStrategies)));
        return BTCVault(address(proxy));
    }

    /// @notice Deploys USDCVault behind ERC1967Proxy
    /// @param _manager AccessManager address
    /// @param _asset The underlying asset (USDC) address
    /// @param _blp Bitmor lending pool address
    /// @return The USDCVault contract instance
    function _deployUSDCVaultProxy(address _manager, address _asset, address _blp) internal returns (USDCVault) {
        USDCVault impl = new USDCVault();
        ERC1967Proxy proxy =
            new ERC1967Proxy(address(impl), abi.encodeCall(USDCVault.initialize, (_manager, _asset, _blp)));
        return USDCVault(address(proxy));
    }

    /// @notice Deploys AutoRepayment behind ERC1967Proxy
    /// @param _manager AccessManager address
    /// @param _loan Loan contract address
    /// @param _debtAsset Debt asset (USDC) address
    /// @return The AutoRepayment contract instance
    function _deployAutoRepaymentProxy(address _manager, address _loan, address _debtAsset)
        internal
        returns (AutoRepayment)
    {
        AutoRepayment impl = new AutoRepayment();
        ERC1967Proxy proxy =
            new ERC1967Proxy(address(impl), abi.encodeCall(AutoRepayment.initialize, (_manager, _loan, _debtAsset)));
        return AutoRepayment(address(proxy));
    }

    /// @notice Deploys BitmorAddressesProvider behind ERC1967Proxy
    /// @param _manager AccessManager address
    /// @param _swapper Swap adapter address
    /// @param _premiumCollector Premium collector address
    /// @param _liquidationFeeCollector Liquidation fee collector address
    /// @return The BitmorAddressesProvider contract instance
    function _deployAddressesProviderProxy(
        address _manager,
        address _swapper,
        address _premiumCollector,
        address _liquidationFeeCollector
    ) internal returns (BitmorAddressesProvider) {
        BitmorAddressesProvider impl = new BitmorAddressesProvider();
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(impl),
            abi.encodeCall(
                BitmorAddressesProvider.initialize, (_manager, _swapper, _premiumCollector, _liquidationFeeCollector)
            )
        );
        return BitmorAddressesProvider(address(proxy));
    }

    /// @notice Deploys LoanVault behind ERC1967Proxy
    /// @dev For tests that need initialized LoanVault instances directly (not via factory)
    /// @param _owner The vault owner (typically the Loan contract)
    /// @param _borrower The borrower address
    /// @return The LoanVault contract instance
    function _deployLoanVaultViaProxy(address _owner, address _borrower) internal returns (LoanVault) {
        LoanVault impl = new LoanVault();
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), abi.encodeCall(LoanVault.initialize, (_owner, _borrower)));
        return LoanVault(payable(address(proxy)));
    }

    // ===== Beacon Proxy Helpers =====

    /// @notice Deploys simplified beacon proxy for unit/fuzz tests
    /// @dev No BeaconController -- test contract owns beacon directly
    /// @param _loanProxy Loan proxy address (passed to LoanVaultFactory)
    /// @return loanVaultImpl LoanVault implementation address
    /// @return beacon UpgradeableBeacon address (owned by test contract)
    /// @return factory LoanVaultFactory address
    function _deploySimpleBeaconProxy(address _loanProxy)
        internal
        returns (address loanVaultImpl, address beacon, address factory)
    {
        loanVaultImpl = address(new LoanVault());
        beacon = address(new UpgradeableBeacon(loanVaultImpl, address(this)));
        factory = address(new LoanVaultFactory(beacon, _loanProxy));
    }

    /// @notice Deploys full beacon proxy infrastructure for integration/upgrade tests
    /// @dev Includes BeaconController with ownership transfer
    /// @param _accessManager AccessManager address for BeaconController
    /// @param _loanProxy Loan proxy address for LoanVaultFactory
    /// @return loanVaultImpl LoanVault implementation address
    /// @return beacon UpgradeableBeacon address
    /// @return beaconController BeaconController address (owns beacon)
    /// @return factory LoanVaultFactory address
    function _deployFullBeaconProxy(address _accessManager, address _loanProxy)
        internal
        returns (address loanVaultImpl, address beacon, address beaconController, address factory)
    {
        loanVaultImpl = address(new LoanVault());
        beacon = address(new UpgradeableBeacon(loanVaultImpl, address(this)));
        beaconController = address(new BeaconController(_accessManager, beacon));
        UpgradeableBeacon(beacon).transferOwnership(beaconController);
        factory = address(new LoanVaultFactory(beacon, _loanProxy));
    }

    // ===== Utility =====

    /// @notice Reads implementation address from EIP-1967 storage slot
    /// @param proxy The proxy contract address
    /// @return The implementation address stored in the EIP-1967 slot
    function _getImplAddress(address proxy) internal view returns (address) {
        return address(uint160(uint256(vm.load(proxy, IMPL_SLOT))));
    }
}
