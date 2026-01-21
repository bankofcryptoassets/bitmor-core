// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.30;

import {IERC20} from "@openzeppelin/interfaces/IERC20.sol";
import {IFlashLoanSimpleReceiver} from "@bitmor/interfaces/IFlashLoanSimpleReceiver.sol";

/// @dev Minimal mock of Aave V3 pool for flash loans.
/// Records last call parameters and performs the callback/repayment flow.
contract MockAaveV3Pool {
    address public lastReceiver;
    address public lastAsset;
    uint256 public lastAmount;
    uint256 public lastPremium;
    address public lastInitiator;
    bytes public lastParams;

    function flashLoanSimple(
        address receiverAddress,
        address asset,
        uint256 amount,
        bytes calldata params,
        uint16 /*referralCode*/
    )
        external
    {
        lastReceiver = receiverAddress;
        lastAsset = asset;
        lastAmount = amount;
        lastPremium = 0;
        lastInitiator = msg.sender;
        lastParams = params;

        // Fund the pool with the flash-loaned asset and send to receiver.
        (bool mintSuccess,) = asset.call(abi.encodeWithSignature("mint(uint256)", amount));
        require(mintSuccess, "MOCK_MINT_ERROR");
        require(IERC20(asset).transfer(receiverAddress, amount), "MOCK_TRANSFER_ERROR");

        // Callback into the receiver.
        bool ok = IFlashLoanSimpleReceiver(receiverAddress).executeOperation(asset, amount, 0, msg.sender, params);
        require(ok, "MOCK_CALLBACK_FAILED");

        // Pull repayment (amount + premium) from receiver.
        require(IERC20(asset).transferFrom(receiverAddress, address(this), amount), "MOCK_REPAY_TRANSFERFROM_FAILED");
    }
}
