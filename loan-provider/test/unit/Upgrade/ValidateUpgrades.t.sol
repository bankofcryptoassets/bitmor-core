// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {Upgrades, Options} from "@openzeppelin-foundry-upgrades/Upgrades.sol";

/// @title ValidateUpgradesTest
/// @notice Validates all UUPS implementations pass OZ upgrade safety checks
/// @dev Uses FFI to run OZ upgrade validation (storage layout, initializers, unsafe opcodes)
contract ValidateUpgradesTest is Test {
    Options internal opts;

    function setUp() public {
        // OZ Foundry Upgrades uses vm.envOr("FOUNDRY_OUT", "out") to find build artifacts.
        // Our profile sets out = "forge-out", so we must set this env var to match.
        vm.setEnv("FOUNDRY_OUT", "forge-out");
    }

    /// @notice Validates Loan implementation passes upgrade safety checks
    function test_ValidateLoan() public {
        Upgrades.validateImplementation("Loan.sol", opts);
    }

    /// @notice Validates BTCVault implementation passes upgrade safety checks
    function test_ValidateBTCVault() public {
        Upgrades.validateImplementation("BTCVault.sol", opts);
    }

    /// @notice Validates USDCVault implementation passes upgrade safety checks
    function test_ValidateUSDCVault() public {
        Upgrades.validateImplementation("USDCVault.sol", opts);
    }

    /// @notice Validates AutoRepayment implementation passes upgrade safety checks
    function test_ValidateAutoRepayment() public {
        Upgrades.validateImplementation("AutoRepayment.sol", opts);
    }

    /// @notice Validates BitmorAddressesProvider implementation passes upgrade safety checks
    function test_ValidateBitmorAddressesProvider() public {
        Upgrades.validateImplementation("BitmorAddressesProvider.sol", opts);
    }
}
