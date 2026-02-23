// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ERC20} from "@solady/tokens/ERC20.sol";
import {FixedPointMathLib} from "@solady/utils/FixedPointMathLib.sol";

import {BTCVault} from "@btcVault/BTCVault.sol";
import {Errors} from "@bitmor/libraries/helpers/Errors.sol";
import {BaseTestForBTCVault, BTCVaultHarness} from "../BaseTestForBTCVault.t.sol";

/// @title BTCVaultTest
/// @author Bitmor Protocol
/// @notice Tests for BTCVault constructor, external setters, public view functions, and internal metadata
contract BTCVaultTest is BaseTestForBTCVault {
    using FixedPointMathLib for uint256;

    function test_constructor() public {
        BTCVaultHarness newVault = new BTCVaultHarness(networkConfig.usdc, address(this));

        assertEq(newVault.asset(), networkConfig.usdc);
    }

    /*
       _______  _______ _____ ____  _   _    _    _       _____ _   _ _   _  ____ _____ ___ ___  _   _ ____
      | ____\ \/ /_   _| ____|  _ \| \ | |  / \  | |     |  ___| | | | \ | |/ ___|_   _|_ _/ _ \| \ | / ___|
      |  _|  \  /  | | |  _| | |_) |  \| | / _ \ | |     | |_  | | | |  \| | |     | |  | | | | |  \| \___ \
      | |___ /  \  | | | |___|  _ <| |\  |/ ___ \| |___  |  _| | |_| | |\  | |___  | |  | | |_| | |\  |___) |
      |_____/_/\_\ |_| |_____|_| \_\_| \_/_/   \_\_____| |_|    \___/|_| \_|\____| |_| |___\___/|_| \_|____/
    */

    function test_setEntryFee() public {
        uint256 entryFeeInBPS = 100;

        _scheduleAndExecute(bvm_slow, bvm_slow_id(), abi.encodeCall(BTCVault.setEntryFee, (entryFeeInBPS)));

        assertEq(vault.getEntryFee(), entryFeeInBPS);
    }

    function test_setExitFee() public {
        uint256 exitFeeInBps = 100;

        _scheduleAndExecute(bvm_slow, bvm_slow_id(), abi.encodeCall(BTCVault.setExitFee, (exitFeeInBps)));

        assertEq(vault.getExitFee(), exitFeeInBps);
    }

    function test_setFeeRecipient() public {
        address newFeeRecipient = makeAddr("newRecipient");

        _scheduleAndExecute(bvm_slow, bvm_slow_id(), abi.encodeCall(BTCVault.setFeeRecipient, (newFeeRecipient)));

        assertEq(vault.getFeeRecipient(), newFeeRecipient);
    }

    function test_setFeeRecipient_withZeroAddress() public {
        bytes memory data = abi.encodeCall(BTCVault.setFeeRecipient, (address(0)));

        _scheduleAndExpectRevert(bvm_slow, bvm_slow_id(), data, abi.encodeWithSelector(Errors.ZeroAddress.selector));
    }

    function test_setEntryFee_RevertWhen_FeeRecipientNotSet() public {
        // Arrange: fresh vault with no fee recipient
        BTCVaultHarness freshVault = new BTCVaultHarness(address(mockUSDC), address(manager));

        // Act + Assert
        vm.expectRevert(abi.encodeWithSelector(Errors.Vault__FeeRecipientNotSet.selector));
        freshVault.setEntryFee(100);
    }

    function test_setExitFee_RevertWhen_FeeRecipientNotSet() public {
        // Arrange: fresh vault with no fee recipient
        BTCVaultHarness freshVault = new BTCVaultHarness(address(mockUSDC), address(manager));

        // Act + Assert
        vm.expectRevert(abi.encodeWithSelector(Errors.Vault__FeeRecipientNotSet.selector));
        freshVault.setExitFee(100);
    }

    function test_setEntryFee_AllowsZeroFee_WithoutRecipient() public {
        // Arrange: fresh vault with no fee recipient
        BTCVaultHarness freshVault = new BTCVaultHarness(address(mockUSDC), address(manager));

        // Act: setting zero fee should succeed even without recipient
        freshVault.setEntryFee(0);

        // Assert
        assertEq(freshVault.getEntryFee(), 0, "entry fee should be 0");
    }

    function test_setExitFee_AllowsZeroFee_WithoutRecipient() public {
        // Arrange: fresh vault with no fee recipient
        BTCVaultHarness freshVault = new BTCVaultHarness(address(mockUSDC), address(manager));

        // Act: setting zero fee should succeed even without recipient
        freshVault.setExitFee(0);

        // Assert
        assertEq(freshVault.getExitFee(), 0, "exit fee should be 0");
    }

    /*
       ____  _   _ ____  _     ___ ____   _____ _   _ _   _  ____ _____ ___ ___  _   _ ____
      |  _ \| | | | __ )| |   |_ _/ ___| |  ___| | | | \ | |/ ___|_   _|_ _/ _ \| \ | / ___|
      | |_) | | | |  _ \| |    | | |     | |_  | | | |  \| | |     | |  | | | | |  \| \___ \
      |  __/| |_| | |_) | |___ | | |___  |  _| | |_| | |\  | |___  | |  | | |_| | |\  |___) |
      |_|    \___/|____/|_____|___\____| |_|    \___/|_| \_|\____| |_| |___\___/|_| \_|____/
    */

    function test_name() public view {
        string memory currentName = vault.name();
        string memory expectedName = "BitmorBTCVault";

        assertEq(currentName, expectedName);
    }

    function test_symbol() public view {
        string memory currentSymbol = vault.symbol();
        string memory expectedSymbol = "bvBTC";

        assertEq(currentSymbol, expectedSymbol);
    }

    function test_asset() public view {
        assertEq(vault.asset(), networkConfig.usdc);
    }

    /*
       ___ _   _ _____ _____ ____  _   _    _    _       _____ _   _ _   _  ____ _____ ___ ___  _   _ ____
      |_ _| \ | |_   _| ____|  _ \| \ | |  / \  | |     |  ___| | | | \ | |/ ___|_   _|_ _/ _ \| \ | / ___|
       | ||  \| | | | |  _| | |_) |  \| | / _ \ | |     | |_  | | | |  \| | |     | |  | | | | |  \| \___ \
       | || |\  | | | | |___|  _ <| |\  |/ ___ \| |___  |  _| | |_| | |\  | |___  | |  | | |_| | |\  |___) |
      |___|_| \_| |_| |_____|_| \_\_| \_/_/   \_\_____| |_|    \___/|_| \_|\____| |_| |___\___/|_| \_|____/
    */

    function test_underlyingDecimals() public view {
        uint8 currentDecimals = vault.underlyingDecimals();

        uint8 epxectedDecimals = ERC20(networkConfig.usdc).decimals();

        assertEq(currentDecimals, epxectedDecimals);
    }
}
