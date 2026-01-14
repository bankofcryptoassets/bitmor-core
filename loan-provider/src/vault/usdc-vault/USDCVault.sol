// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ERC4626, ERC20} from "@solady/tokens/ERC4626.sol";
import {FixedPointMathLib} from "@solady/utils/FixedPointMathLib.sol";
import {SafeTransferLib} from "@solady/utils/SafeTransferLib.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

import {Errors} from "../../libraries/helpers/Errors.sol";
import {ISimpleStrategy} from "../../interfaces/ISimpleStrategy.sol";

/// @title USDCVault
contract USDCVault is ERC4626, AccessControl {
    using FixedPointMathLib for uint256;
    using SafeTransferLib for address;

    /// @notice Emitted when the strategy contract is updated
    /// @param newStrategy The new strategy contract address
    event SimpleVault__StrategyUpdated(address newStrategy);

    /// @notice The underlying asset that the vault accepts (immutable)
    address internal immutable i_asset;

    address internal immutable i_blp;

    bytes32 private constant ALLOCATOR_ROLE = keccak256("ALLOCATOR");
    bytes32 private constant MANAGER_ROLE = keccak256("MANAGER");

    /// @notice The strategy contract that manages yield generation
    ISimpleStrategy private s_strategy;

    /// @notice Initializes the vault with the specified underlying asset
    /// @param asset_ The address of the ERC20 token to be used as the underlying asset
    constructor(address asset_, address blp_) {
        if (asset_ == address(0) || blp_ == address(0)) revert Errors.ZeroAddress();
        i_asset = asset_;
        i_blp = blp_;

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    /*
       _____      _                        _   _____                 _   _
      | ____|_  _| |_ ___ _ __ _ __   __ _| | |  ___|   _ _ __   ___| |_(_) ___  _ __  ___
      |  _| \ \/ / __/ _ \ '__| '_ \ / _` | | | |_ | | | | '_ \ / __| __| |/ _ \| '_ \/ __|
      | |___ >  <| ||  __/ |  | | | | (_| | | |  _|| |_| | | | | (__| |_| | (_) | | | \__ \
      |_____/_/\_\\__\___|_|  |_| |_|\__,_|_| |_|   \__,_|_| |_|\___|\__|_|\___/|_| |_|___/
    */

    /// @notice Updates the strategy contract used for yield generation
    /// @dev Withdraws funds from current strategy before switching to new one
    /// @param newStrategy The address of the new strategy contract (cannot be zero address)
    function setStrategy(address newStrategy) external onlyRole(MANAGER_ROLE) {
        if (newStrategy == address(0)) revert Errors.ZeroAddress();

        // Withdraw all funds from current strategy if one exists
        if (address(s_strategy) != address(0) && s_strategy.getTotalBalanceInMarkets() > 0) {
            s_strategy.withdrawAllFunds();
            i_asset.safeApprove(address(s_strategy), 0);
        }

        // Approve new strategy to spend vault's assets
        i_asset.safeApprove(newStrategy, type(uint256).max);

        s_strategy = ISimpleStrategy(newStrategy);

        emit SimpleVault__StrategyUpdated(newStrategy);
    }

    function reallocateAssets() external onlyRole(ALLOCATOR_ROLE) {
        s_strategy.reallocateAssets();
    }

    function reallocateAssets(uint256 amountToWithdraw) external {
        if (msg.sender != i_blp) revert Errors.UnauthorizedCaller();
        s_strategy.reallocateAssets(amountToWithdraw);
    }

    function updateMinimumDeltaRequired(uint256 newMinimumDeltaRequired) external onlyRole(MANAGER_ROLE) {
        s_strategy.updateMinimumDeltaRequired(newMinimumDeltaRequired);
    }

    function getStrategy() external view returns (address) {
        return address(s_strategy);
    }

    /*
       ____        _     _ _        _____                 _   _
      |  _ \ _   _| |__ | (_) ___  |  ___|   _ _ __   ___| |_(_) ___  _ __  ___
      | |_) | | | | '_ \| | |/ __| | |_ | | | | '_ \ / __| __| |/ _ \| '_ \/ __|
      |  __/| |_| | |_) | | | (__  |  _|| |_| | | | | (__| |_| | (_) | | | \__ \
      |_|    \__,_|_.__/|_|_|\___| |_|   \__,_|_| |_|\___|\__|_|\___/|_| |_|___/
    */

    /// @notice Returns the name of the vault token
    /// @inheritdoc ERC20
    /// @return The vault token name
    function name() public pure override returns (string memory) {
        return "Simple Vault";
    }

    /// @notice Returns the symbol of the vault token
    /// @inheritdoc ERC20
    /// @return The vault token symbol
    function symbol() public pure override returns (string memory) {
        return "SV";
    }

    /// @notice Returns the address of the underlying asset
    /// @inheritdoc ERC4626
    /// @return The address of the underlying ERC20 token
    function asset() public view override returns (address) {
        return i_asset;
    }

    /// @notice Returns the total amount of assets under management
    /// @inheritdoc ERC4626
    /// @dev Delegates to the strategy contract to calculate total assets across all positions
    /// @return assets The total amount of underlying assets managed by the vault
    function totalAssets() public view override returns (uint256 assets) {
        assets = s_strategy.totalAssets();
    }

    /*
       ___       _                        _   _____                 _   _
      |_ _|_ __ | |_ ___ _ __ _ __   __ _| | |  ___|   _ _ __   ___| |_(_) ___  _ __  ___
       | || '_ \| __/ _ \ '__| '_ \ / _` | | | |_ | | | | '_ \ / __| __| |/ _ \| '_ \/ __|
       | || | | | ||  __/ |  | | | | (_| | | |  _|| |_| | | | | (__| |_| | (_) | | | \__ \
      |___|_| |_|\__\___|_|  |_| |_|\__,_|_| |_|   \__,_|_| |_|\___|\__|_|\___/|_| |_|___/
    */

    /// @notice Returns the number of decimals used by the underlying asset
    /// @inheritdoc ERC4626
    /// @dev Used internally for precise share calculations
    /// @return The number of decimals of the underlying asset
    function _underlyingDecimals() internal view override returns (uint8) {
        return ERC20(i_asset).decimals();
    }

    function _afterDeposit(uint256 assets, uint256 shares) internal override {
        s_strategy.supply(assets);
    }

    function _beforeWithdraw(uint256 assets, uint256 shares) internal override {
        // Withdraw assets from strategy
        s_strategy.withdraw(assets);
    }
}
