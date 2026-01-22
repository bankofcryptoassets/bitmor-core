// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.30;

import {IERC20} from "@openzeppelin/interfaces/IERC20.sol";
import {IFlashLoanSimpleReceiver} from "@bitmor/interfaces/IFlashLoanSimpleReceiver.sol";

/// @title MockAaveV3Pool
/// @author Bitmor Protocol
/// @notice Mock Aave V3 Pool for local testing with flash loan support
/// @dev Implements flashLoanSimple() and FLASHLOAN_PREMIUM_TOTAL() as required by AavePoolLogic
contract MockAaveV3Pool {
    // ============ State Variables ============

    /// @dev Flash loan premium in basis points (default: 5 = 0.05%)
    uint128 private _flashLoanPremium = 5;

    /// @dev Last call parameters for testing assertions
    address public lastReceiver;
    address public lastAsset;
    uint256 public lastAmount;
    uint256 public lastPremium;
    address public lastInitiator;
    bytes public lastParams;

    // ============ Events ============

    event FlashLoan(
        address indexed target, address indexed initiator, address indexed asset, uint256 amount, uint256 premium
    );

    event PremiumUpdated(uint128 oldPremium, uint128 newPremium);

    // ============ Flash Loan Functions ============

    /// @notice Returns the flash loan premium in basis points
    /// @return The premium (e.g., 5 = 0.05%)
    function FLASHLOAN_PREMIUM_TOTAL() external view returns (uint128) {
        return _flashLoanPremium;
    }

    /// @notice Executes a simple flash loan
    /// @dev Transfers amount to receiver, calls executeOperation, expects repayment
    /// @param receiverAddress The contract receiving the flash loan
    /// @param asset The token being flash loaned
    /// @param amount The amount to flash loan
    /// @param params Encoded parameters for the receiver
    /// @param referralCode Unused, kept for interface compatibility
    function flashLoanSimple(
        address receiverAddress,
        address asset,
        uint256 amount,
        bytes calldata params,
        uint16 referralCode
    ) external {
        // Silence unused variable warning
        referralCode;

        // Store call parameters for testing assertions
        lastReceiver = receiverAddress;
        lastAsset = asset;
        lastAmount = amount;
        lastInitiator = msg.sender;
        lastParams = params;

        // Calculate premium
        uint256 premium = (amount * _flashLoanPremium) / 10000;
        lastPremium = premium;

        // Check pool has sufficient liquidity (funded via deal() in tests)
        uint256 poolBalance = IERC20(asset).balanceOf(address(this));
        require(poolBalance >= amount, "MockAaveV3Pool: insufficient liquidity");

        // Transfer flash loan amount to receiver
        require(IERC20(asset).transfer(receiverAddress, amount), "MockAaveV3Pool: transfer failed");

        // Call receiver's executeOperation
        bool success = IFlashLoanSimpleReceiver(receiverAddress)
            .executeOperation(
                asset,
                amount,
                premium,
                msg.sender, // initiator
                params
            );
        require(success, "MockAaveV3Pool: callback failed");

        // Pull repayment (amount + premium) from receiver
        uint256 amountOwed = amount + premium;
        require(
            IERC20(asset).transferFrom(receiverAddress, address(this), amountOwed), "MockAaveV3Pool: repayment failed"
        );

        emit FlashLoan(receiverAddress, msg.sender, asset, amount, premium);
    }

    // ============ Admin Functions ============

    /// @notice Sets the flash loan premium (for testing edge cases)
    /// @param newPremium New premium in basis points
    function setPremium(uint128 newPremium) external {
        uint128 oldPremium = _flashLoanPremium;
        _flashLoanPremium = newPremium;
        emit PremiumUpdated(oldPremium, newPremium);
    }

    /// @notice Fund the pool with tokens for flash loan liquidity
    /// @dev Caller must have approved this contract to transfer tokens
    /// @param asset The token to fund
    /// @param amount The amount to fund
    function fund(address asset, uint256 amount) external {
        require(IERC20(asset).transferFrom(msg.sender, address(this), amount), "MockAaveV3Pool: fund transfer failed");
    }

    /// @notice Get current balance of an asset in the pool
    /// @param asset The token address
    /// @return The balance
    function getBalance(address asset) external view returns (uint256) {
        return IERC20(asset).balanceOf(address(this));
    }
}
