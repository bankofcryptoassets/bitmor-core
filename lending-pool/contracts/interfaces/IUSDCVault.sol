// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.6.12;

import {IERC4626} from "./IERC4626.sol";

interface IUSDCVault is IERC4626 {
    function reallocateAssets(uint256 amountToWithdraw) external;
}
