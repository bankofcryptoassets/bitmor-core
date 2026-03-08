// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {IFlashLoanSimpleReceiver} from "@bitmor/interfaces/IFlashLoanSimpleReceiver.sol";
import {MockAToken} from "./MockAToken.sol";

/// @title MockAaveV3Pool
/// @author Bitmor Protocol
/// @notice Mock Aave V3 Pool for local testing with flash loan and lending support
/// @dev Implements flashLoanSimple(), supply(), withdraw() as required by protocol
contract MockAaveV3Pool {
    // ============ State Variables ============

    /// @dev Flash loan premium in basis points (default: 5 = 0.05%)
    uint128 private _flashLoanPremium = 5;

    /// @dev Mapping from asset to aToken
    mapping(address => address) private _reserveATokens;

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

    // ============ Aave Lending Functions ============

    /// @notice Initialize a reserve with an aToken (test helper)
    /// @param asset The underlying asset address
    /// @param aToken The aToken address for this reserve
    function initReserve(address asset, address aToken) external {
        _reserveATokens[asset] = aToken;
    }

    /// @notice Get the aToken address for a reserve
    /// @param asset The underlying asset address
    /// @return The aToken address
    function getReserveAToken(address asset) external view returns (address) {
        return _reserveATokens[asset];
    }

    /// @notice Supply assets to the pool
    /// @param asset The asset to supply
    /// @param amount The amount to supply
    /// @param onBehalfOf The address receiving the aTokens
    /// @param referralCode Referral code (unused)
    function supply(address asset, uint256 amount, address onBehalfOf, uint16 referralCode) external {
        referralCode; // Silence unused warning
        _supplyInternal(asset, amount, onBehalfOf);
    }

    /// @notice Deposit assets to the pool (alias for supply, kept for interface compatibility)
    /// @param asset The asset to deposit
    /// @param amount The amount to deposit
    /// @param onBehalfOf The address receiving the aTokens
    /// @param referralCode Referral code (unused)
    function deposit(address asset, uint256 amount, address onBehalfOf, uint16 referralCode) external {
        referralCode; // Silence unused warning
        _supplyInternal(asset, amount, onBehalfOf);
    }

    /// @notice Internal supply logic
    /// @param asset The asset to supply
    /// @param amount The amount to supply
    /// @param onBehalfOf The address receiving the aTokens
    function _supplyInternal(address asset, uint256 amount, address onBehalfOf) internal {
        address aToken = _reserveATokens[asset];
        require(aToken != address(0), "MockAaveV3Pool: reserve not initialized");

        IERC20(asset).transferFrom(msg.sender, address(this), amount);
        MockAToken(aToken).mint(onBehalfOf, amount);
    }

    /// @notice Withdraw assets from the pool
    /// @param asset The asset to withdraw
    /// @param amount The amount to withdraw (use type(uint256).max for all)
    /// @param to The address receiving the underlying
    /// @return The actual amount withdrawn
    function withdraw(address asset, uint256 amount, address to) external returns (uint256) {
        address aToken = _reserveATokens[asset];
        require(aToken != address(0), "MockAaveV3Pool: reserve not initialized");

        MockAToken aTokenContract = MockAToken(aToken);
        uint256 userBalance = aTokenContract.balanceOf(msg.sender);
        uint256 amountToWithdraw = amount == type(uint256).max ? userBalance : amount;
        if (amountToWithdraw > userBalance) {
            amountToWithdraw = userBalance;
        }

        aTokenContract.burn(msg.sender, amountToWithdraw);
        IERC20(asset).transfer(to, amountToWithdraw);

        return amountToWithdraw;
    }
}
