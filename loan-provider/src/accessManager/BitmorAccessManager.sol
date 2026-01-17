// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.30;

import {AccessManager} from "@openzeppelin/access/manager/AccessManager.sol";

contract BitmorAccessManager is AccessManager {
    constructor(address _initialAdmin) AccessManager(_initialAdmin) {}
}
