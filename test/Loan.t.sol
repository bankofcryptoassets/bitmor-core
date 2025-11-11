// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.30;

import {Test} from 'forge-std/Test.sol';
import {Loan} from '@bitmor/loan/Loan.sol';

contract LoanTest is Test {
  Loan loan;

  function setUp() public {
    loan = new Loan();
  }
}
