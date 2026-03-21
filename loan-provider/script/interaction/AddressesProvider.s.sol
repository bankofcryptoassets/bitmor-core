// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {console2} from "forge-std/console2.sol";
import {InteractionBase} from "./InteractionBase.s.sol";

/// @title AddressesProvider_SetBitmorLoan
/// @notice Sets the Bitmor Loan address on the LendingPoolAddressesProvider
contract AddressesProvider_SetBitmorLoan is InteractionBase {
    function run() public {
        _preflight();

        address addressesProvider = config.getAddressesProvider();
        address loanAddr = config.getLoan();

        vm.broadcast();
        (bool success,) = addressesProvider.call(abi.encodeWithSignature("setBitmorLoan(address)", loanAddr));
        require(success, "ERR: SET BITMOR LOAN FAILED");

        console2.log("BitmorLoan set to:", loanAddr, "on:", addressesProvider);
    }
}
