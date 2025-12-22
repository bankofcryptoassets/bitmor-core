// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {console2} from "forge-std/console2.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {FixedPointMathLib} from "@solady/utils/FixedPointMathLib.sol";
import {SafeTransferLib} from "@solady/utils/SafeTransferLib.sol";
import {ILendingPool as IBLP} from "../../interfaces/ILendingPool.sol";
import {DataTypes} from "../../libraries/types/DataTypes.sol";
import {ERC20} from "@solady/tokens/ERC20.sol";

import {ISimpleStrategy} from "../../interfaces/ISimpleStrategy.sol";
import {IPool as IAave} from "../../interfaces/IPool.sol";

/// @title SimpleStrategy
/// @notice A yield strategy that splits 100% of deposited assets in 4:1 ratio between Aave and BLP protocols
/// @dev Implements ISimpleStrategy interface and manages asset allocation across DeFi protocols
/// @author megabyte0x.eth

contract SimpleStrategy is ISimpleStrategy {
    using Address for address;
    using FixedPointMathLib for uint256;
    using SafeTransferLib for address;

    /// @notice The Aave lending pool contract
    IAave public immutable i_aave;

    /// @notice The Bitmor Lending Pool contract
    IBLP public immutable i_blp;

    /// @notice The vault contract that owns this strategy
    address public immutable i_vault;

    /// @notice Referral code for Aave deposits (0 = no referral)
    uint16 internal constant REFERRAL_CODE = 0;

    /// @notice Percentage to allocate to Aave (80% of total) for 4:1 ratio
    uint256 internal constant AAVE_ALLOCATION = 80_00;

    /// @notice Scale factor for percentage calculations (100%)
    uint256 internal constant BASIS_POINT_SCALE = 100_00;

    /// @notice Initializes the strategy with required protocol addresses
    /// @param vault_ The address of the vault that will use this strategy
    /// @param aave_ The address of the Aave lending pool
    /// @param blp_ The address of the Bitmor Lending Pool
    constructor(address vault_, address aave_, address blp_) {
        i_aave = IAave(aave_);
        i_blp = IBLP(blp_);
        i_vault = vault_;
    }

    /// @notice Returns the underlying asset address by querying the vault
    /// @dev Uses OpenZeppelin's Address library for safe static calls
    /// @return assetAddress The address of the underlying ERC20 asset
    function asset() public view returns (address assetAddress) {
        bytes memory data = i_vault.functionStaticCall(abi.encodeWithSignature("asset()"));

        assetAddress = abi.decode(data, (address));
    }

    /// @notice Returns the total assets under management across all positions
    /// @dev Sums vault balance and deployed assets in external protocols
    /// @return totalBalance The total amount of assets managed by this strategy
    function totalAssets() public view returns (uint256 totalBalance) {
        uint256 balanceInVault = ERC20(asset()).balanceOf(i_vault);

        uint256 totalBalanceInDifferentMarkets = getTotalBalanceInMarkets();

        totalBalance = balanceInVault + totalBalanceInDifferentMarkets;
    }

    /// @notice Supplies assets to external protocols according to strategy allocation
    /// @dev Deploys 100% of amount in 4:1 ratio between Aave and BLP respectively
    /// @param amount The total amount of assets to be deployed
    function supply(uint256 amount) external {
        address token = asset();

        // Transfer assets from vault to strategy
        token.safeTransferFrom(i_vault, address(this), amount);

        // Split 80% Aave and 20% Bitmor Lending Pool
        uint256 amountToDepositInAave = amount.mulDiv(AAVE_ALLOCATION, BASIS_POINT_SCALE);
        uint256 amountToDepositInBLP = amount.rawSub(amountToDepositInAave);

        // Supply to Aave
        token.safeApprove(address(i_aave), amountToDepositInAave);
        i_aave.supply(asset(), amountToDepositInAave, address(this), REFERRAL_CODE);

        // Supply to BLP
        token.safeApprove(address(i_blp), amountToDepositInBLP);
        i_blp.deposit(asset(), amountToDepositInBLP, address(this), REFERRAL_CODE);
    }

    /// @notice Withdraws the requested amount by reallocating assets if necessary
    /// @dev If vault doesn't have enough balance, triggers reallocation from external protocols
    /// @param amount The amount of assets to make available for withdrawal
    function withdraw(uint256 amount) external {
        //! TODO: Remove debug console logs before production
        console2.log("amount to withdraw: ", amount);

        uint256 currentBalanceInVault = ERC20(asset()).balanceOf(i_vault);
        console2.log("Current balance in vault: ", currentBalanceInVault);

        // Reallocate assets if vault doesn't have sufficient balance
        if (amount > currentBalanceInVault) {
            _reallocateAssets(amount, currentBalanceInVault);
        }
    }

    /// @notice Withdraws all funds from external protocols back to the vault
    /// @dev Called when strategy is being replaced or vault needs to liquidate all positions
    function withdrawFunds() external {
        _withdrawFunds();
    }

    /// @notice Returns the total balance deployed across external protocols
    /// @dev Sums balances in Aave and BLP
    /// @return balance The total amount deployed in external protocols
    function getTotalBalanceInMarkets() public view returns (uint256 balance) {
        return _getBalanceInAave() + _getBalanceInBLP();
    }

    /// @notice Gets the balance of assets deposited in Aave
    /// @dev Queries the aToken balance which represents deposits in Aave
    /// @return balance The amount of assets deposited in Aave
    function _getBalanceInAave() internal view returns (uint256 balance) {
        address aToken = IAave(i_aave).getReserveAToken(asset());
        balance = ERC20(aToken).balanceOf(address(this));
    }

    /// @notice Gets the balance of assets deposited in BLP
    /// @dev Queries the aToken balance from BLP reserve data
    /// @return balance The amount of assets deposited in BLP
    function _getBalanceInBLP() internal view returns (uint256 balance) {
        DataTypes.ReserveData memory reserveData = i_blp.getReserveData(asset());
        address aToken = reserveData.aTokenAddress;
        balance = ERC20(aToken).balanceOf(address(this));
    }

    /// @notice Reallocates assets from external protocols to meet withdrawal requirements
    /// @dev Withdraws from protocols to meet withdrawal requirements
    /// @param amountToWithdraw The amount that needs to be withdrawn
    /// @param currentBalanceInVault The current balance available in the vault
    function _reallocateAssets(uint256 amountToWithdraw, uint256 currentBalanceInVault) internal {
        uint256 totalBalance = totalAssets();

        //! TODO: Remove debug console logs before production
        console2.log("total balance: ", totalBalance);

        uint256 totalBalanceAfter = totalBalance.rawSub(amountToWithdraw);
        console2.log("total balance after: ", totalBalanceAfter);

        // If remaining balance is too small, withdraw everything
        if (totalBalanceAfter < _singleUnitAsset()) {
            _withdrawFunds();
        } else {
            uint256 amountNeededFromProtocols = amountToWithdraw.rawSub(currentBalanceInVault);
            _reallocate(amountNeededFromProtocols);
        }
    }

    /// @notice Withdraws specified amount from external protocols proportionally
    /// @dev Withdraws from Aave and BLP to maintain balance
    /// @param totalBalanceToWithdraw The total amount to withdraw from external protocols
    function _reallocate(uint256 totalBalanceToWithdraw) internal {
        uint256 balanceToWithdrawFromAave = totalBalanceToWithdraw.mulDiv(AAVE_ALLOCATION, BASIS_POINT_SCALE);

        // Withdraw proportional amount from Aave directly to vault
        i_aave.withdraw(asset(), balanceToWithdrawFromAave, i_vault);

        // Withdraw remaining from BLP directly to vault
        i_blp.withdraw(asset(), totalBalanceToWithdraw - balanceToWithdrawFromAave, i_vault);
    }

    /// @notice Internal function to withdraw all funds from external protocols
    /// @dev Withdraws entire balance from both Aave and BLP back to vault
    function _withdrawFunds() internal {
        // Withdraw all from Aave directly to vault
        i_aave.withdraw(asset(), _getBalanceInAave(), i_vault);

        // Withdraw all from BLP directly to vault
        i_blp.withdraw(asset(), _getBalanceInBLP(), i_vault);
    }

    /// @notice Returns one unit of the underlying asset (1.0 in asset's decimal precision)
    /// @dev Used as a threshold for determining when to withdraw all funds
    /// @return One unit of the asset (e.g., 1e6 for USDC)
    function _singleUnitAsset() internal view returns (uint256) {
        return 1 * 10 ** ERC20(asset()).decimals();
    }
}
