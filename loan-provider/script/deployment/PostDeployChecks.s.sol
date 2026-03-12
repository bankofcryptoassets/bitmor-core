// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script, console2} from "forge-std/Script.sol";
import {HelperConfig} from "../HelperConfig.s.sol";
import {BitmorAccessManager} from "@bitmor/accessManager/BitmorAccessManager.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {LoanVaultFactory} from "@bitmor/protocol/LoanVaultFactory.sol";
import {IBeaconController} from "@bitmor/interfaces/IBeaconController.sol";

/// @title PostDeployChecks
/// @notice Validates deployment invariants after all phases complete
/// @dev Run after Phase 3c (local) or after TransferToMultisig (mainnet)
/// @custom:security This script is read-only — it does not modify state
contract PostDeployChecks is Script {
    /// @dev EIP-1967 implementation storage slot
    bytes32 constant IMPL_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    uint256 public checks;
    uint256 public passed;

    /// @notice Main entry point — runs all validation checks
    function run() external {
        HelperConfig config = new HelperConfig();
        BitmorAccessManager manager = BitmorAccessManager(config.getAccessManager());

        console2.log("=== Post-Deploy Invariant Checks ===");

        // 1. Proxy → implementation pointers
        _checkProxy("Loan", config.getLoan(), config.getLoanImpl());
        _checkProxy("BTCVault", config.getBTCVault(), config.getBTCVaultImpl());
        _checkProxy("USDCVault", config.getUSDCVault(), config.getUSDCVaultImpl());
        _checkProxy("AutoRepayment", config.getAutoRepayer(), config.getAutoRepaymentImpl());
        _checkProxy(
            "BitmorAddressesProvider", config.getBitmorAddressesProvider(), config.getBitmorAddressesProviderImpl()
        );

        // 2. Beacon ownership == BeaconController
        address beacon = config.getBeacon();
        address beaconController = config.getBeaconController();
        _check("Beacon owner == BeaconController", UpgradeableBeacon(beacon).owner() == beaconController);

        // 3. Beacon implementation == LoanVault impl
        address loanVaultImpl = config.getLoanVaultImplementation();
        _check("Beacon impl == LoanVault impl", UpgradeableBeacon(beacon).implementation() == loanVaultImpl);

        // 4. Factory beacon pointer
        address factory = config.getLoanVaultFactory();
        _check("Factory.i_BEACON == beacon", LoanVaultFactory(factory).i_BEACON() == beacon);

        // 5. UPGRADER can call upgradeToAndCall on Loan proxy
        bytes4 uupsSelector = bytes4(keccak256("upgradeToAndCall(address,bytes)"));
        _checkCanCall(manager, "UPGRADER -> Loan.upgradeToAndCall", config.getLoan(), uupsSelector);
        _checkCanCall(manager, "UPGRADER -> BTCVault.upgradeToAndCall", config.getBTCVault(), uupsSelector);
        _checkCanCall(manager, "UPGRADER -> USDCVault.upgradeToAndCall", config.getUSDCVault(), uupsSelector);
        _checkCanCall(manager, "UPGRADER -> AutoRepayment.upgradeToAndCall", config.getAutoRepayer(), uupsSelector);
        _checkCanCall(
            manager, "UPGRADER -> AddressesProvider.upgradeToAndCall", config.getBitmorAddressesProvider(), uupsSelector
        );
        _checkCanCall(
            manager,
            "UPGRADER -> BeaconController.upgradeBeacon",
            beaconController,
            IBeaconController.upgradeBeacon.selector
        );

        // 6. Summary
        console2.log("");
        console2.log(string.concat("=== Results: ", vm.toString(passed), " / ", vm.toString(checks), " passed ==="));
        require(passed == checks, "PostDeployChecks: FAILED");
    }

    /// @notice Validates proxy points to expected implementation
    /// @param name Human-readable contract name for logging
    /// @param proxy The proxy address
    /// @param expectedImpl The expected implementation address
    function _checkProxy(string memory name, address proxy, address expectedImpl) internal {
        address actualImpl = address(uint160(uint256(vm.load(proxy, IMPL_SLOT))));
        _check(string.concat(name, " proxy -> impl"), actualImpl == expectedImpl);
        _check(string.concat(name, " impl has bytecode"), actualImpl.code.length > 0);
    }

    /// @notice Validates an address can call a function on a target via AccessManager
    /// @param manager The AccessManager instance
    /// @param label Human-readable label for logging
    /// @param target The target contract
    /// @param selector The function selector to check
    function _checkCanCall(BitmorAccessManager manager, string memory label, address target, bytes4 selector) internal {
        (bool immediate, uint32 delay) = manager.canCall(msg.sender, target, selector);
        _check(label, immediate || delay > 0);
    }

    /// @notice Records and logs a check result
    /// @param label Human-readable check description
    /// @param condition Whether the check passed
    function _check(string memory label, bool condition) internal {
        checks++;
        if (condition) {
            passed++;
            console2.log("  [PASS]", label);
        } else {
            console2.log("  [FAIL]", label);
        }
    }
}
