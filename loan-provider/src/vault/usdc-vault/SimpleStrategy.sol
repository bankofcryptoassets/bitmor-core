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

    /// @notice Address of the base `asset` from the vault.
    address public immutable i_asset;

    /// @notice Referral code for Aave deposits (0 = no referral)
    uint16 internal constant REFERRAL_CODE = 0;

    /// @notice Percentage to allocate to Aave (80% of total) for 4:1 ratio
    uint256 internal constant AAVE_ALLOCATION = 80_00;

    /// @notice Scale factor for percentage calculations (100%)
    uint256 internal constant BASIS_POINT_SCALE = 100_00;

    /// @notice Minimum Delta required for reallocation of assets, expressed in basis points.
    uint256 private s_minimumDeltaRequired;

    /// @notice Initializes the strategy with required protocol addresses
    /// @param vault_ The address of the vault that will use this strategy
    /// @param aave_ The address of the Aave lending pool
    /// @param blp_ The address of the Bitmor Lending Pool
    constructor(address vault_, address aave_, address blp_) {
        i_aave = IAave(aave_);
        i_blp = IBLP(blp_);
        i_vault = vault_;

        bytes memory data = i_vault.functionStaticCall(abi.encodeWithSignature("i_asset"));

        i_asset = abi.decode(data, (address));
    }

    function updateMinimumDeltarRequired(uint256 newMinimumDeltaRequired) external {
        s_minimumDeltaRequired = newMinimumDeltaRequired;

        emit SimpleStrategy__MinimumDeltaUpdated(newMinimumDeltaRequired);
    }

    /// @notice Returns the underlying asset address.
    /// @return assetAddress The address of the underlying ERC20 asset
    function asset() public view returns (address assetAddress) {
        return i_asset;
    }

    /// @notice Returns the total assets under management across all positions
    /// @dev Sums vault balance and deployed assets in external protocols
    /// @return totalBalance The total amount of assets managed by this strategy
    function totalAssets() public view returns (uint256 totalBalance) {
        totalBalance = getTotalBalanceInMarkets();
    }

    /// @notice Supplies assets to external protocols according to strategy allocation
    /// @dev Deploys 100% of amount in 4:1 ratio between Aave and BLP respectively
    /// @param amount The total amount of assets to be deployed
    function supply(uint256 amount) external {
        // Transfer assets from vault to strategy
        i_asset.safeTransferFrom(i_vault, address(this), amount);

        // Split 80% Aave and 20% Bitmor Lending Pool
        uint256 amountToDepositInAave = amount.mulDiv(AAVE_ALLOCATION, BASIS_POINT_SCALE);
        uint256 amountToDepositInBLP = amount.rawSub(amountToDepositInAave);

        // Supply to Aave
        i_asset.safeApprove(address(i_aave), amountToDepositInAave);
        i_aave.supply(i_asset, amountToDepositInAave, address(this), REFERRAL_CODE);

        // Supply to BLP
        i_asset.safeApprove(address(i_blp), amountToDepositInBLP);
        i_blp.deposit(i_asset, amountToDepositInBLP, address(this), REFERRAL_CODE);
    }

    /// @notice Withdraws the requested amount from AAVE and deposit in BLP.
    /// @param amount The amount of assets to make available for withdrawal in BLP.
    function withdraw(uint256 amount) external {
        _withdrawFunds(amount);
    }

    function reallocateAssets() external {
        _reallocateAssets();
    }

    /// @notice Withdraws all funds from AAVE back to the BLP
    /// @dev Called when strategy is being replaced or vault needs to liquidate all positions
    function withdrawFunds() external {
        _withdrawAllFunds();
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
        address aToken = IAave(i_aave).getReserveAToken(i_asset);
        balance = ERC20(aToken).balanceOf(address(this));
    }

    /// @notice Gets the balance of assets deposited in BLP
    /// @dev Queries the aToken balance from BLP reserve data
    /// @return balance The amount of assets deposited in BLP
    function _getBalanceInBLP() internal view returns (uint256 balance) {
        DataTypes.ReserveData memory reserveData = i_blp.getReserveData(i_asset);
        address aToken = reserveData.aTokenAddress;
        balance = ERC20(aToken).balanceOf(address(this));
    }

    /// @notice Reallocates assets between Aave and BLP.
    function _reallocateAssets() internal {
        uint256 currentBalanceInAave = _getBalanceInAave();
        uint256 targetBalanceInAave = totalAssets().mulDiv(AAVE_ALLOCATION, BASIS_POINT_SCALE);

        if (targetBalanceInAave >= currentBalanceInAave) {
            uint256 delta = targetBalanceInAave.rawSub(currentBalanceInAave);

            uint256 deltaPercentage = delta.mulDiv(BASIS_POINT_SCALE, targetBalanceInAave);

            if (deltaPercentage >= s_minimumDeltaRequired) {
                _withdrawFomBLPAndDepositInAAVE(delta);
            }
        } else if (targetBalanceInAave < currentBalanceInAave) {
            uint256 delta = currentBalanceInAave.rawSub(targetBalanceInAave);

            uint256 deltaPercentage = delta.mulDiv(BASIS_POINT_SCALE, targetBalanceInAave);

            if (deltaPercentage >= s_minimumDeltaRequired) {
                _withdrawFomAaveAndDepositInBLP(delta);
            }
        }
    }

    /// @notice Internal function to withdraw all funds from Aave to BLP
    function _withdrawAllFunds() internal {
        // Withdraw all from Aave directly to vault
        _withdrawFomAaveAndDepositInBLP(_getBalanceInAave());
    }

    /**
     * @notice Calculates, withdraws and deposit the amount required to be present in BLP from AAVE to meet the standard ratio.
     * @param amountToTransfer Amount to transfer to the user from the BLP.
     */
    function _withdrawFunds(uint256 amountToTransfer) internal {
        uint256 totalBalance = getTotalBalanceInMarkets();
        uint256 totalBalanceAfter = totalBalance.rawSub(amountToTransfer);
        uint256 targetBLPAssetsAfter =
            totalBalanceAfter.mulDiv(BASIS_POINT_SCALE.rawSub(AAVE_ALLOCATION), BASIS_POINT_SCALE);
        uint256 amountToWithdrawFromAave = targetBLPAssetsAfter + amountToTransfer - _getBalanceInBLP();

        _withdrawFomAaveAndDepositInBLP(amountToWithdrawFromAave);
    }

    function _withdrawFomAaveAndDepositInBLP(uint256 amountToWithdrawFromAave) internal {
        uint256 finalAmountWithdrawn = i_aave.withdraw(i_asset, amountToWithdrawFromAave, address(this));

        i_asset.safeApprove(address(i_blp), finalAmountWithdrawn);
        i_blp.deposit(i_asset, finalAmountWithdrawn, address(this), REFERRAL_CODE);
    }

    function _withdrawFomBLPAndDepositInAAVE(uint256 amountToWithdrawFromBLP) internal {
        uint256 finalAmountWithdrawn = i_blp.withdraw(i_asset, amountToWithdrawFromBLP, address(this));

        i_asset.safeApprove(address(i_aave), finalAmountWithdrawn);
        i_aave.deposit(i_asset, finalAmountWithdrawn, address(this), REFERRAL_CODE);
    }

    /// @notice Returns one unit of the underlying asset (1.0 in asset's decimal precision)
    /// @dev Used as a threshold for determining when to withdraw all funds
    /// @return One unit of the asset (e.g., 1e6 for USDC)
    function _singleUnitAsset() internal view returns (uint256) {
        return 1 * 10 ** ERC20(i_asset).decimals();
    }
}
