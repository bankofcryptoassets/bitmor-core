// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.30;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {HelperConfig} from "../HelperConfig.s.sol";
import {ILoan} from "@bitmor/interfaces/ILoan.sol";

contract Loan_InitializeLoan is Script {
    HelperConfig config = new HelperConfig();

    function _initializeLoanWithConfigs(
        address loanAddress,
        uint256 depositAmt,
        uint256 premiumAmt,
        uint256 collateralAmt,
        uint256 durationInMonths,
        bytes memory data
    ) internal returns (address lsa) {
        ILoan loan = ILoan(loanAddress);

        vm.broadcast();
        lsa = loan.initializeLoan(depositAmt, premiumAmt, collateralAmt, durationInMonths, data);

        console2.log("LSA address:", lsa);
    }

    function _initializeLoan() internal returns (address lsa) {
        (uint256 depositAmt, uint256 premiumAmt, uint256 collateralAmt, uint256 durationInMonths, bytes memory data) =
            config.getLoanConfig();

        address loanAddress = config.getLoan();

        lsa = _initializeLoanWithConfigs(loanAddress, depositAmt, premiumAmt, collateralAmt, durationInMonths, data);
    }

    function run() public returns (address) {
        _initializeLoan();
    }
}

contract Loan_SetLoanVaultFactory is Script {
    HelperConfig config = new HelperConfig();

    function _setLoanVaultFactoryWithConfigs(address loanAddress, address loanVaultFactory) internal {
        ILoan loan = ILoan(loanAddress);

        vm.broadcast();
        loan.setLoanVaultFactory(loanVaultFactory);
    }

    function _setLoanVaultFactory() internal {
        address loanVaultFactory = config.getLoanVaultFactory();
        address loanAddress = config.getLoan();

        _setLoanVaultFactoryWithConfigs(loanAddress, loanVaultFactory);
    }

    function run() public {
        _setLoanVaultFactory();
    }
}

contract Loan_SetGracePeriod is Script {
    HelperConfig config = new HelperConfig();

    function _setGracePeriodWithConfigs(address loanAddress, uint256 gracePeriod) internal {
        ILoan loan = ILoan(loanAddress);

        vm.broadcast();
        loan.setGracePeriod(gracePeriod);
    }

    function _setGracePeriod() internal {
        address loanAddress = config.getLoan();
        uint256 gracePeriod = config.getGracePeriod();

        _setGracePeriodWithConfigs(loanAddress, gracePeriod);
    }

    function run() public {
        _setGracePeriod();
    }
}
