// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Address} from "@openzeppelin/utils/Address.sol";
import {FixedPointMathLib} from "@solady/utils/FixedPointMathLib.sol";
import {SafeTransferLib} from "@solady/utils/SafeTransferLib.sol";
import {ERC20} from "@solady/tokens/ERC20.sol";

import {Errors} from "../../libraries/helpers/Errors.sol";
import {DataTypes} from "../../libraries/types/DataTypes.sol";

import {ILendingPool as IBLP} from "../../interfaces/ILendingPool.sol";
import {ISimpleStrategy} from "../../interfaces/ISimpleStrategy.sol";
import {IPool as IAave} from "../../interfaces/IPool.sol";

/**
 * @title USDCStrategy
 * @author Bitmor Protocol
 * @notice A yield strategy that splits deposited USDC between Aave and Bitmor Lending Pool
 * @dev Implements ISimpleStrategy interface. The allocation ratio is configurable via
 * `s_externalAllocation` (in basis points). The remainder goes to BLP.
 * @custom:security Only callable by the owning vault via the `onlyVault` modifier
 */
contract USDCStrategy is ISimpleStrategy {
    using Address for address;
    using FixedPointMathLib for uint256;
    using SafeTransferLib for address;

    /// @notice Thrown when a function restricted to the vault is called by another address
    error USDCStrategy__NotVault();

    /**
     * @notice The Aave lending pool contract
     */
    IAave public immutable i_aave;

    /**
     * @notice The Bitmor Lending Pool contract
     */
    IBLP public immutable i_blp;

    /**
     * @notice The vault contract that owns this strategy
     */
    address public immutable i_vault;

    /**
     * @notice Address of the base `asset` from the vault.
     */
    address public immutable i_asset;

    /**
     * @notice Referral code for Aave deposits (0 = no referral)
     */
    uint16 internal constant REFERRAL_CODE = 0;

    /**
     * @notice Scale factor for percentage calculations (100%)
     */
    uint256 internal constant BASIS_POINT_SCALE = 100_00;

    /**
     * @notice Minimum Delta required for reallocation of assets, expressed in basis points.
     */
    uint256 private s_minimumDeltaRequired;

    /**
     * @notice Percentage to allocate to External Protocol in this case its AAVE.
     */
    uint256 private s_externalAllocation;

    /**
     * @notice Initializes the strategy with required protocol addresses
     * @param _vault The address of the vault that will use this strategy
     * @param _aave The address of the Aave lending pool
     * @param _blp The address of the Bitmor Lending Pool
     */
    constructor(address _vault, address _aave, address _blp) {
        if (_vault == address(0) || _aave == address(0) || _blp == address(0)) {
            revert Errors.ZeroAddress();
        }

        i_aave = IAave(_aave);
        i_blp = IBLP(_blp);
        i_vault = _vault;

        bytes memory data = i_vault.functionStaticCall(abi.encodeWithSignature("asset()"));
        i_asset = abi.decode(data, (address));

        // Approving Aave and BLP to transfer funds from this address.
        i_asset.safeApprove(address(i_aave), type(uint256).max);
        i_asset.safeApprove(address(i_blp), type(uint256).max);
    }

    /// @notice Restricts function access to the owning vault contract
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

    /**
     * @notice Returns the underlying asset address.
     * @return assetAddress The address of the underlying ERC20 asset
     */
    function asset() public view returns (address assetAddress) {
        return i_asset;
    }

    /**
     * @notice Returns the total assets under management across all positions
     * @dev Sums vault balance and deployed assets in external protocols
     * @return totalBalance The total amount of assets managed by this strategy
     */
    function totalAssets() public view returns (uint256 totalBalance) {
        totalBalance = _getTotalBalanceInMarkets();
    }

    /**
     * @notice Returns the total balance deployed across external protocols
     * @dev Sums balances in Aave and BLP
     * @return balance The total amount deployed in external protocols
     */
    function getTotalBalanceInMarkets() public view returns (uint256 balance) {
        balance = _getTotalBalanceInMarkets();
    }

    /**
     * @notice Returns the total amount of assets that can actually be withdrawn right now
     * @dev Sums Aave balance (fully liquid) and BLP available liquidity (excludes lent-out funds)
     * @return withdrawable The total withdrawable amount across all positions
     */
    function withdrawableAssets() public view returns (uint256 withdrawable) {
        withdrawable = _getBalanceInAave() + _getWithdrawableBalanceInBLP();
    }

    /*
       _______  _______ _____ ____  _   _    _    _       _____ _   _ _   _  ____ _____ ___ ___  _   _ ____
      | ____\ \/ /_   _| ____|  _ \| \ | |  / \  | |     |  ___| | | | \ | |/ ___|_   _|_ _/ _ \| \ | / ___|
      |  _|  \  /  | | |  _| | |_) |  \| | / _ \ | |     | |_  | | | |  \| | |     | |  | | | | |  \| \___ \
      | |___ /  \  | | | |___|  _ <| |\  |/ ___ \| |___  |  _| | |_| | |\  | |___  | |  | | |_| | |\  |___) |
      |_____/_/\_\ |_| |_____|_| \_\_| \_/_/   \_\_____| |_|    \___/|_| \_|\____| |_| |___\___/|_| \_|____/
    */

    function getExternalAllocation() external view returns (uint256) {
        return s_externalAllocation;
    }

    /**
     * @notice Updates the percentage of deposited assets allocated to Aave
     * @param newExternalAllocation New allocation in basis points (e.g., 8000 = 80% to Aave)
     * @custom:access Only callable by the vault
     */
    function updateExternalAllocation(uint256 newExternalAllocation) external onlyVault {
        if (newExternalAllocation > BASIS_POINT_SCALE) revert Errors.InvalidInputs();

        s_externalAllocation = newExternalAllocation;
        emit SimpleStrategy__ExternalAllocationUpdated(newExternalAllocation);
    }

    /**
     * @notice Transfers `amount` from the vault and splits it between Aave and BLP per `s_externalAllocation`
     * @param amount Amount of assets to supply
     * @custom:access Only callable by the vault
     */
    function supply(uint256 amount) external onlyVault {
        // Transfer assets from vault to strategy
        i_asset.safeTransferFrom(i_vault, address(this), amount);

        // Split 80% Aave and 20% Bitmor Lending Pool
        uint256 amountToDepositInAave = amount.mulDiv(s_externalAllocation, BASIS_POINT_SCALE);
        uint256 amountToDepositInBLP = amount.rawSub(amountToDepositInAave);

        // Supply to Aave
        if (amountToDepositInAave != 0) {
            i_aave.supply(i_asset, amountToDepositInAave, address(this), REFERRAL_CODE);
        }

        // Supply to BLP
        if (amountToDepositInBLP != 0) {
            i_blp.deposit(i_asset, amountToDepositInBLP, address(this), REFERRAL_CODE);
        }
    }

    /**
     * @notice Withdraws `amount` from Aave and BLP while maintaining the allocation ratio, then transfers to the vault
     * @param amount The amount of assets to withdraw and send to the vault
     * @custom:access Only callable by the vault
     */
    function withdraw(uint256 amount) external onlyVault {
        _withdrawFunds(amount);
        // Transfer withdrawn assets to vault (msg.sender)
        i_asset.safeTransfer(msg.sender, amount);
    }

    /// @notice Rebalances assets between Aave and BLP to match the configured `s_externalAllocation` ratio.
    /// @custom:access Only callable by the vault
    function reallocateAssets() external onlyVault {
        _reallocateAssets();
    }

    /**
     * @notice Withdraws assets from Aave and deposits them into BLP to prepare for a user withdrawal
     * @param amountToWithdraw The amount the user intends to withdraw from BLP
     * @custom:access Only callable by the vault
     */
    function reallocateAssets(uint256 amountToWithdraw) external onlyVault {
        _withdrawFundsToBLP(amountToWithdraw);
    }

    /**
     * @notice Withdraws all funds from AAVE back to the BLP
     * @dev Called when strategy is being replaced or vault needs to liquidate all positions
     */
    function withdrawAllFunds() external onlyVault {
        _withdrawAllFunds();
    }

    /**
     * @notice Updates the minimum delta threshold required before triggering a reallocation
     * @param newMinimumDeltaRequired The new minimum delta in basis points
     * @custom:access Only callable by the vault
     */
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

    /**
     * @dev Returns the total balance deployed across Aave and BLP
     * @return balance The total amount deployed in external protocols
     */
    function _getTotalBalanceInMarkets() internal view returns (uint256 balance) {
        return _getBalanceInAave() + _getBalanceInBLP();
    }

    /**
     * @dev Returns the balance of assets deposited in Aave by querying the aToken balance
     * @return balance The amount of assets deposited in Aave
     */
    function _getBalanceInAave() internal view returns (uint256 balance) {
        address aToken = IAave(i_aave).getReserveAToken(i_asset);
        balance = ERC20(aToken).balanceOf(address(this));
    }

    /**
     * @dev Returns the total assets deposited into BLP by querying the aToken balance
     * @return balance The total amount of assets attributable to this strategy in BLP
     */
    function _getBalanceInBLP() internal view returns (uint256 balance) {
        DataTypes.ReserveData memory reserveData = i_blp.getReserveData(i_asset);

        balance = ERC20(reserveData.aTokenAddress).balanceOf(address(this));
    }

    /**
     * @dev Returns only the available (withdrawable) liquidity in BLP, excluding lent-out funds
     * @return withdrawable The amount of assets that can actually be withdrawn from BLP
     */
    function _getWithdrawableBalanceInBLP() internal view returns (uint256 withdrawable) {
        DataTypes.ReserveData memory reserveData = i_blp.getReserveData(i_asset);
        withdrawable = ERC20(i_asset).balanceOf(reserveData.aTokenAddress);
    }

    /**
     * @dev Rebalances assets between Aave and BLP to match `s_externalAllocation`.
     * Only rebalances when the delta exceeds `s_minimumDeltaRequired` to avoid unnecessary gas costs.
     */
    function _reallocateAssets() internal {
        uint256 currentBalanceInAave = _getBalanceInAave();

        uint256 targetBalanceInAave = _getTotalBalanceInMarkets().mulDiv(s_externalAllocation, BASIS_POINT_SCALE);

        if (targetBalanceInAave == 0) {
            // When target is 0% Aave, move all Aave funds to BLP
            if (currentBalanceInAave > 0) {
                _withdrawFomAaveAndDepositInBLP(currentBalanceInAave);
            }
            return;
        }

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

    /**
     * @dev Withdraws all funds from both Aave and BLP back to the strategy contract.
     */
    function _withdrawAllFunds() internal {
        uint256 aaveBal = _getBalanceInAave();
        if (aaveBal > 0) i_aave.withdraw(i_asset, aaveBal, i_vault);
        uint256 blpBal = _getBalanceInBLP();
        if (blpBal > 0) i_blp.withdraw(i_asset, blpBal, i_vault);
    }

    /**
     * @dev Calculates and withdraws the required amount from Aave into BLP so that the
     * BLP has enough liquidity to cover `amountToTransfer` while maintaining the allocation ratio.
     * @param amountToTransfer Amount to be withdrawn from BLP by the user
     */
    function _withdrawFundsToBLP(uint256 amountToTransfer) internal {
        uint256 aaveBalance = _getBalanceInAave();
        uint256 blpBalance = _getWithdrawableBalanceInBLP();
        uint256 totalBalance = aaveBalance + blpBalance;

        if (totalBalance < amountToTransfer) revert Errors.InsufficientBalance();

        uint256 totalBalanceAfter = totalBalance.zeroFloorSub(amountToTransfer);
        uint256 targetBLPAssetsAfter =
            totalBalanceAfter.mulDiv(BASIS_POINT_SCALE.rawSub(s_externalAllocation), BASIS_POINT_SCALE);

        uint256 amountToWithdrawFromAave =
            (targetBLPAssetsAfter.rawAdd(amountToTransfer).zeroFloorSub(_getWithdrawableBalanceInBLP()));

        if (amountToWithdrawFromAave == 0) return;

        _withdrawFomAaveAndDepositInBLP(amountToWithdrawFromAave.min(aaveBalance));
    }

    /**
     * @dev Withdraws `amountToTransfer` from Aave and BLP while maintaining the allocation ratio.
     * Uses only withdrawable (liquid) BLP balance for ratio targeting so that `fromBLP` is
     * naturally bounded by available liquidity — no explicit cap needed.
     * @param amountToTransfer Amount of assets to withdraw to this contract
     */
    function _withdrawFunds(uint256 amountToTransfer) internal {
        uint256 currentAaveBalance = _getBalanceInAave();
        uint256 withdrawableBLPBalance = _getWithdrawableBalanceInBLP();

        uint256 liquidTotal = currentAaveBalance.rawAdd(withdrawableBLPBalance);

        if (amountToTransfer > liquidTotal) revert Errors.InsufficientBalance();

        uint256 targetAaveBalance = liquidTotal.rawSub(amountToTransfer).mulDiv(s_externalAllocation, BASIS_POINT_SCALE);

        // Ratio-based split — fromBLP is naturally bounded by withdrawableBLPBalance
        uint256 fromAave = currentAaveBalance.zeroFloorSub(targetAaveBalance);
        uint256 fromBLP = amountToTransfer.zeroFloorSub(fromAave);

        // Execute withdrawals
        uint256 totalWithdrawn;
        if (fromAave > 0) totalWithdrawn = i_aave.withdraw(i_asset, fromAave, address(this));
        if (fromBLP > 0) totalWithdrawn += i_blp.withdraw(i_asset, fromBLP, address(this));

        if (totalWithdrawn < amountToTransfer) revert Errors.InsufficientBalance();

        // Redeposit any rounding excess to BLP
        uint256 excess = totalWithdrawn.rawSub(amountToTransfer);
        if (excess > 0) i_blp.deposit(i_asset, excess, address(this), REFERRAL_CODE);
    }

    /**
     * @dev Withdraws `amountToWithdrawFromAave` assets from Aave and deposits them into BLP.
     * @param amountToWithdrawFromAave Amount of assets to withdraw from Aave
     */
    function _withdrawFomAaveAndDepositInBLP(uint256 amountToWithdrawFromAave) internal {
        uint256 finalAmountWithdrawn = i_aave.withdraw(i_asset, amountToWithdrawFromAave, address(this));

        i_blp.deposit(i_asset, finalAmountWithdrawn, address(this), REFERRAL_CODE);
    }

    /**
     * @dev Withdraws `amountToWithdrawFromBLP` assets from BLP and deposits them into Aave.
     * @param amountToWithdrawFromBLP Amount of assets to withdraw from BLP
     */
    function _withdrawFomBLPAndDepositInAAVE(uint256 amountToWithdrawFromBLP) internal {
        uint256 finalAmountWithdrawn = i_blp.withdraw(i_asset, amountToWithdrawFromBLP, address(this));

        i_aave.deposit(i_asset, finalAmountWithdrawn, address(this), REFERRAL_CODE);
    }
}
