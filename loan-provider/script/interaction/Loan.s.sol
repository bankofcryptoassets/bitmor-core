// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {console2} from "forge-std/console2.sol";
import {InteractionBase} from "./InteractionBase.s.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {ILoan} from "@bitmor/interfaces/ILoan.sol";
import {IBitmorAddressesProvider} from "@bitmor/interfaces/IBitmorAddressesProvider.sol";

/// @title Loan_InitializeLoan
/// @notice Initializes a loan on any environment (local, fork, live)
/// @dev Flow: preflight → seed pool → fund user → broadcast approve + initializeLoan.
///      Seed pool first so whale's balance is used for seeding before user funding.
///      Pool seeding deposits into USDCVault which splits ~80% Aave / ~20% BLP.
///      For the default loan config (10K deposit + 5K premium = 15K USDC total),
///      100K USDC seeded → ~20K BLP liquidity (sufficient for flash loan repayment).
contract Loan_InitializeLoan is InteractionBase {
    function run() public {
        _preflight();

        // Cache loan config (pure function, safe to call anytime)
        (uint256 deposit, uint256 premium, uint256 collateral, uint256 duration, bytes memory data) =
            config.getLoanConfig();
        uint256 totalUSDC = deposit + premium;

        // 1. Seed pool with flash loan liquidity (whale→USDCVault on fork, mint→USDCVault on local)
        _seedLendingPoolUSDC(100_000e6);

        // 2. Fund user with USDC for deposit + premium (whale transfer on fork, mint on local)
        _fundWithUSDC(msg.sender, totalUSDC);

        // 3. Broadcast as user: approve + initializeLoan (uses cached _usdc, _loan from _preflight)
        vm.startBroadcast();
        IERC20(_usdc).approve(_loan, totalUSDC);
        address lsa = ILoan(_loan).initializeLoan(deposit, premium, collateral, duration, data);
        vm.stopBroadcast();

        console2.log("Loan initialized. LSA:", lsa);
    }
}

/// @title Loan_SetLoanVaultFactory
/// @notice Sets the LoanVaultFactory on BitmorAddressesProvider
contract Loan_SetLoanVaultFactory is InteractionBase {
    function run() public {
        _preflight();

        // Cache before broadcast (config calls are staticcalls)
        address loanVaultFactory = config.getLoanVaultFactory();
        address bap = config.getBitmorAddressesProvider();

        vm.broadcast();
        IBitmorAddressesProvider(bap).setVaultFactory(loanVaultFactory);

        console2.log("VaultFactory set to:", loanVaultFactory);
    }
}

/// @title Loan_SetGracePeriod
/// @notice Sets the grace period on the Loan contract
contract Loan_SetGracePeriod is InteractionBase {
    function run() public {
        _preflight();

        // Cache before broadcast
        uint256 gracePeriod = config.getGracePeriod();

        vm.broadcast();
        ILoan(_loan).setGracePeriod(uint32(gracePeriod));

        console2.log("Grace period set to:", gracePeriod);
    }
}
