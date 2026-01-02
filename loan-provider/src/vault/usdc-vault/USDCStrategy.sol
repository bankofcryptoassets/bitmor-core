// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {FixedPointMathLib} from "@solady/utils/FixedPointMathLib.sol";
import {SafeTransferLib} from "@solady/utils/SafeTransferLib.sol";
import {ERC20} from "@solady/tokens/ERC20.sol";

import {Errors} from "../../libraries/helpers/Errors.sol";
import {DataTypes} from "../../libraries/types/DataTypes.sol";

import {ILendingPool as IBLP} from "../../interfaces/ILendingPool.sol";
import {ISimpleStrategy} from "../../interfaces/ISimpleStrategy.sol";
import {IPool as IAave} from "../../interfaces/IPool.sol";

/// @title USDCStrategy
/// @notice A yield strategy that splits 100% of deposited assets in 4:1 ratio between Aave and BLP protocols
/// @dev Implements ISimpleStrategy interface and manages asset allocation across DeFi protocols
/// @author megabyte0x.eth

contract USDCStrategy is ISimpleStrategy {
    using Address for address;
    using FixedPointMathLib for uint256;
    using SafeTransferLib for address;

    error USDCStrategy__NotVault();

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
        if (vault_ == address(0) || aave_ == address(0) || blp_ == address(0) || aave_ == address(0)) {
            revert Errors.ZeroAddress();
        }

        i_aave = IAave(i_aave);
        i_blp = IBLP(blp_);
        i_vault = vault_;

        bytes memory data = i_vault.functionStaticCall(abi.encodeWithSignature("asset()"));
        i_asset = abi.decode(data, (address));

        // Approving Aave and BLP to transfer funds from this address.
        i_asset.safeApprove(address(i_aave), type(uint256).max);
        i_asset.safeApprove(address(i_blp), type(uint256).max);
    }

    modifier onlyVault() {
        if (msg.sender != i_vault) revert USDCStrategy__NotVault();
        _;
    }

    /*
       ____  _   _ ____  _     ___ ____   _____ _   _ _   _  ____ _____ ___ ___  _   _ ____
      |  _ \| | | | __ )| |   |_ _/ ___| |  ___| | | | \ | |/ ___|_   _|_ _/ _ \| \ | / ___|
      | |_) | | | |  _ \| |    | | |     | |_  | | | |  \| | |     | |  | | | | |  \| \___ \
      |  __/| |_| | |_) | |___ | | |___  |  _| | |_| | |\  | |___  | |  | | |_| | |\  |___) |
      |_|    \___/|____/|_____|___\____| |_|    \___/|_| \_|\____| |_| |___\___/|_| \_|____/
    */

    /// @notice Returns the underlying asset address.
    /// @return assetAddress The address of the underlying ERC20 asset
    function asset() public view returns (address assetAddress) {
        return i_asset;
    }

    /// @notice Returns the total assets under management across all positions
    /// @dev Sums vault balance and deployed assets in external protocols
    /// @return totalBalance The total amount of assets managed by this strategy
    function totalAssets() public view returns (uint256 totalBalance) {
        totalBalance = _getTotalBalanceInMarkets();
    }

    /// @notice Returns the total balance deployed across external protocols
    /// @dev Sums balances in Aave and BLP
    /// @return balance The total amount deployed in external protocols
    function getTotalBalanceInMarkets() public view returns (uint256 balance) {
        balance = _getTotalBalanceInMarkets();
    }

    /*
       _______  _______ _____ ____  _   _    _    _       _____ _   _ _   _  ____ _____ ___ ___  _   _ ____
      | ____\ \/ /_   _| ____|  _ \| \ | |  / \  | |     |  ___| | | | \ | |/ ___|_   _|_ _/ _ \| \ | / ___|
      |  _|  \  /  | | |  _| | |_) |  \| | / _ \ | |     | |_  | | | |  \| | |     | |  | | | | |  \| \___ \
      | |___ /  \  | | | |___|  _ <| |\  |/ ___ \| |___  |  _| | |_| | |\  | |___  | |  | | |_| | |\  |___) |
      |_____/_/\_\ |_| |_____|_| \_\_| \_/_/   \_\_____| |_|    \___/|_| \_|\____| |_| |___\___/|_| \_|____/
    */

    /**
     * @notice Supply the amount between AAVE and BLP.
     * @param amount Amount of assets supplied.
     */
    function supply(uint256 amount) external onlyVault {
        // Transfer assets from vault to strategy
        i_asset.safeTransferFrom(i_vault, address(this), amount);

        // Split 80% Aave and 20% Bitmor Lending Pool
        uint256 amountToDepositInAave = amount.mulDiv(AAVE_ALLOCATION, BASIS_POINT_SCALE);
        uint256 amountToDepositInBLP = amount.rawSub(amountToDepositInAave);

        // Supply to Aave
        i_aave.supply(i_asset, amountToDepositInAave, address(this), REFERRAL_CODE);

        // Supply to BLP
        i_blp.deposit(i_asset, amountToDepositInBLP, address(this), REFERRAL_CODE);
    }

    /// @notice Withdraws the requested amount from AAVE and deposit in BLP.
    /// @param amount The amount of assets to make available for withdrawal in BLP.
    function withdraw(uint256 amount) external onlyVault {
        _withdrawFunds(amount);
    }

    function reallocateAssets() external onlyVault {
        _reallocateAssets();
    }

    function reallocateAssets(uint256 amountToWithdraw) external onlyVault {
        _withdrawFundsToBLP(amountToWithdraw);
    }

    /// @notice Withdraws all funds from AAVE back to the BLP
    /// @dev Called when strategy is being replaced or vault needs to liquidate all positions
    function withdrawAllFunds() external onlyVault {
        _withdrawAllFunds();
    }

    function updateMinimumDeltaRequired(uint256 newMinimumDeltaRequired) external onlyVault {
        s_minimumDeltaRequired = newMinimumDeltaRequired;

        emit SimpleStrategy__MinimumDeltaUpdated(newMinimumDeltaRequired);
    }

    /*
       ___ _   _ _____ _____ ____  _   _    _    _       _____ _   _ _   _  ____ _____ ___ ___  _   _ ____
      |_ _| \ | |_   _| ____|  _ \| \ | |  / \  | |     |  ___| | | | \ | |/ ___|_   _|_ _/ _ \| \ | / ___|
       | ||  \| | | | |  _| | |_) |  \| | / _ \ | |     | |_  | | | |  \| | |     | |  | | | | |  \| \___ \
       | || |\  | | | | |___|  _ <| |\  |/ ___ \| |___  |  _| | |_| | |\  | |___  | |  | | |_| | |\  |___) |
      |___|_| \_| |_| |_____|_| \_\_| \_/_/   \_\_____| |_|    \___/|_| \_|\____| |_| |___\___/|_| \_|____/
    */

    /// @notice Returns the total balance deployed across external protocols
    /// @dev Sums balances in Aave and BLP
    /// @return balance The total amount deployed in external protocols
    function _getTotalBalanceInMarkets() internal view returns (uint256 balance) {
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

        uint256 targetBalanceInAave = _getTotalBalanceInMarkets().mulDiv(AAVE_ALLOCATION, BASIS_POINT_SCALE);

        if (targetBalanceInAave == 0) return;

        if (targetBalanceInAave >= currentBalanceInAave) {
            uint256 delta = targetBalanceInAave.zeroFloorSub(currentBalanceInAave);

            uint256 deltaPercentage = delta.mulDivUp(BASIS_POINT_SCALE, targetBalanceInAave);

            if (deltaPercentage >= s_minimumDeltaRequired) {
                _withdrawFomBLPAndDepositInAAVE(delta);
            }
        } else if (targetBalanceInAave < currentBalanceInAave) {
            uint256 delta = currentBalanceInAave.zeroFloorSub(targetBalanceInAave);

            uint256 deltaPercentage = delta.mulDivUp(BASIS_POINT_SCALE, targetBalanceInAave);

            if (deltaPercentage >= s_minimumDeltaRequired) {
                _withdrawFomAaveAndDepositInBLP(delta);
            }
        }
    }

    /// @notice Withdraw all funds in the vault.
    function _withdrawAllFunds() internal {
        i_aave.withdraw(i_asset, _getBalanceInAave(), address(this));
        i_blp.withdraw(i_asset, _getBalanceInBLP(), address(this));
    }

    /**
     * @notice Calculates, withdraws and deposit the amount required to be present in BLP from AAVE to meet the standard ratio.
     * @param amountToTransfer Amount to transfer to the user from the BLP.
     */
    function _withdrawFundsToBLP(uint256 amountToTransfer) internal {
        uint256 totalBalance = _getTotalBalanceInMarkets();
        uint256 totalBalanceAfter = totalBalance.zeroFloorSub(amountToTransfer);
        uint256 targetBLPAssetsAfter =
            totalBalanceAfter.mulDiv(BASIS_POINT_SCALE.rawSub(AAVE_ALLOCATION), BASIS_POINT_SCALE);

        uint256 amountToWithdrawFromAave =
            targetBLPAssetsAfter.rawAdd(amountToTransfer).zeroFloorSub(_getBalanceInBLP());

        if (amountToWithdrawFromAave == 0) return;

        _withdrawFomAaveAndDepositInBLP(amountToWithdrawFromAave);
    }

    /**
     * @notice When Liquidity Provider (LP) wants to withdraw their assets(burn their shares), the `i_vault` calls the withdraw function to send `assets` to the LP.
     * @dev This calculates and withdraw the funds from both BLP and AAVE such that the remaining funds in both the protocols maintains the allocation ratio.
     * @param amountToTransfer Amount of assets to transfer to LP.
     */
    function _withdrawFunds(uint256 amountToTransfer) internal {
        uint256 currentAaveBalance = _getBalanceInAave();
        uint256 currentBLPBalance = _getBalanceInBLP();

        uint256 totalBalance = currentAaveBalance.rawAdd(currentBLPBalance);

        uint256 totalBalanceAfter = totalBalance.rawSub(amountToTransfer);

        uint256 targetAaveBalance = totalBalanceAfter.mulDivUp(AAVE_ALLOCATION, BASIS_POINT_SCALE);
        uint256 targetBLPBalance = totalBalanceAfter.rawSub(targetAaveBalance);

        uint256 remaining = amountToTransfer;
        if (currentAaveBalance > targetAaveBalance) {
            uint256 amountToWithdrawFromAave = currentAaveBalance.rawSub(targetAaveBalance);

            uint256 finalAmountWithdrawn = i_aave.withdraw(i_asset, amountToWithdrawFromAave, address(this));

            if (finalAmountWithdrawn > amountToTransfer) {
                uint256 excess = finalAmountWithdrawn.rawSub(amountToTransfer);

                i_blp.deposit(i_asset, excess, address(this), REFERRAL_CODE);

                return;
            }

            remaining = remaining.rawSub(finalAmountWithdrawn);
        }

        if (currentBLPBalance > targetBLPBalance) {
            uint256 amountToWithdrawFromBLP = currentBLPBalance.rawSub(targetBLPBalance);

            uint256 finalAmountWithdrawn = i_blp.withdraw(i_asset, amountToWithdrawFromBLP, address(this));

            if (finalAmountWithdrawn > remaining) {
                uint256 excess = finalAmountWithdrawn.rawSub(remaining);

                i_aave.deposit(i_asset, excess, address(this), REFERRAL_CODE);

                return;
            }

            remaining = remaining.rawSub(finalAmountWithdrawn);
        }

        if (remaining != 0) revert Errors.InsufficientBalance();
    }

    /**
     * Withdraws `amountToWithdrawFromAave` assets from Aave and deposit them in BLP.
     * @param amountToWithdrawFromAave Amount of assets to withdraw from Aave
     */
    function _withdrawFomAaveAndDepositInBLP(uint256 amountToWithdrawFromAave) internal {
        uint256 finalAmountWithdrawn = i_aave.withdraw(i_asset, amountToWithdrawFromAave, address(this));

        i_blp.deposit(i_asset, finalAmountWithdrawn, address(this), REFERRAL_CODE);
    }

    /**
     * Withdraws `amountToWithdrawFromBLP` assets from BLP and deposit them in Aave.
     * @param amountToWithdrawFromBLP Amount of assets to withdraw from BLP
     */
    function _withdrawFomBLPAndDepositInAAVE(uint256 amountToWithdrawFromBLP) internal {
        uint256 finalAmountWithdrawn = i_blp.withdraw(i_asset, amountToWithdrawFromBLP, address(this));

        i_aave.deposit(i_asset, finalAmountWithdrawn, address(this), REFERRAL_CODE);
    }
}
