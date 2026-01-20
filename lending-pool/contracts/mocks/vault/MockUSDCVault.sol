// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.6.12;

import {ERC20} from '../../dependencies/openzeppelin/contracts/ERC20.sol';
import {IERC20} from '../../dependencies/openzeppelin/contracts/IERC20.sol';
import {SafeERC20} from '../../dependencies/openzeppelin/contracts/SafeERC20.sol';
import {ILendingPool} from '../../interfaces/ILendingPool.sol';
import {ILendingPoolAddressesProvider} from '../../interfaces/ILendingPoolAddressesProvider.sol';
import {DataTypes} from '../../protocol/libraries/types/DataTypes.sol';

/**
 * @title MockUSDCVault
 * @notice Simplified ERC-4626-like mock vault for testing lending pool integration
 * @dev This is a TESTING-ONLY contract that mimics the real USDCVault behavior
 *
 * Key behaviors matching production:
 * - Users call deposit(assets, receiver) - matches ERC-4626 signature
 * - Users receive vault SHARES (1:1 with assets for simplicity)
 * - Vault deposits to BLP and receives aTokens (just like real Strategy)
 * - Vault holds the aTokens, not the end user
 * - withdraw() burns shares and returns underlying assets
 *
 * Differences from production:
 * - Real vault is full ERC-4626 with complex share pricing
 * - Real vault has a Strategy that splits between Aave V3 (80%) and BLP (20%)
 * - This mock deposits 100% to BLP for simplicity
 * - 1:1 share ratio (no yield accumulation in share price)
 * - No access control, pausability, or strategy management
 */
contract MockUSDCVault is ERC20 {
    using SafeERC20 for IERC20;

    ILendingPoolAddressesProvider public immutable ADDRESSES_PROVIDER;
    address public immutable ASSET;

    event Deposit(address indexed caller, address indexed owner, uint256 assets, uint256 shares);
    event Withdraw(
        address indexed caller,
        address indexed receiver,
        address indexed owner,
        uint256 assets,
        uint256 shares
    );

    /**
     * @dev Constructor
     * @param addressesProvider The address of the LendingPoolAddressesProvider
     * @param asset The underlying asset (e.g., DAI, USDC, WETH)
     */
    constructor(address addressesProvider, address asset) public ERC20('Mock Vault Shares', 'mvShares') {
        require(addressesProvider != address(0), 'MockUSDCVault: INVALID_ADDRESSES_PROVIDER');
        require(asset != address(0), 'MockUSDCVault: INVALID_ASSET');

        ADDRESSES_PROVIDER = ILendingPoolAddressesProvider(addressesProvider);
        ASSET = asset;

        // Set decimals to match underlying asset
        uint8 assetDecimals = ERC20(asset).decimals();
        _setupDecimals(assetDecimals);
    }

    /**
     * @notice Deposits assets into the vault
     * @dev ERC-4626-compatible signature matching real USDCVault
     *
     * Flow:
     * 1. Transfer assets from caller to vault
     * 2. Vault deposits to BLP (vault receives aTokens as onBehalfOf)
     * 3. Mint shares to receiver (1:1 ratio for simplicity)
     *
     * @param assets The amount of underlying asset to deposit
     * @param receiver The address that will receive the vault shares
     * @return shares The amount of shares minted (1:1 with assets)
     */
    function deposit(uint256 assets, address receiver) external returns (uint256 shares) {
        require(assets > 0, 'MockUSDCVault: ZERO_ASSETS');
        require(receiver != address(0), 'MockUSDCVault: ZERO_RECEIVER');

        // Calculate shares (1:1 for this mock)
        shares = assets;

        ILendingPool pool = ILendingPool(ADDRESSES_PROVIDER.getLendingPool());

        // 1. Transfer assets from caller to vault
        IERC20(ASSET).safeTransferFrom(msg.sender, address(this), assets);

        // 2. Approve BLP to spend vault's assets
        IERC20(ASSET).safeApprove(address(pool), 0);
        IERC20(ASSET).safeApprove(address(pool), assets);

        // 3. Deposit to BLP
        // msg.sender = vault (passes LP_CALLER_NOT_VAULT check)
        // onBehalfOf = vault (vault receives the aTokens, just like real Strategy)
        pool.deposit(ASSET, assets, address(this), 0);

        // 4. Mint shares to receiver
        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, assets, shares);

        return shares;
    }

    /**
     * @notice Withdraws assets from the vault
     * @dev ERC-4626-compatible signature
     *
     * Flow:
     * 1. Burn shares from owner
     * 2. Vault withdraws from BLP (burns aTokens, receives underlying)
     * 3. Transfer underlying to receiver
     *
     * @param assets The amount of underlying asset to withdraw
     * @param receiver The address that will receive the assets
     * @param owner The address that owns the shares (must approve if caller != owner)
     * @return shares The amount of shares burned (1:1 with assets)
     */
    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) external returns (uint256 shares) {
        require(assets > 0, 'MockUSDCVault: ZERO_ASSETS');
        require(receiver != address(0), 'MockUSDCVault: ZERO_RECEIVER');
        require(owner != address(0), 'MockUSDCVault: ZERO_OWNER');

        // Calculate shares (1:1 for this mock)
        shares = assets;

        // If caller is not owner, check allowance
        if (msg.sender != owner) {
            uint256 allowed = allowance(owner, msg.sender);
            if (allowed != uint256(-1)) {
                require(allowed >= shares, 'MockUSDCVault: INSUFFICIENT_ALLOWANCE');
                _approve(owner, msg.sender, allowed - shares);
            }
        }

        ILendingPool pool = ILendingPool(ADDRESSES_PROVIDER.getLendingPool());

        // 1. Burn shares from owner
        _burn(owner, shares);

        // 2. Withdraw from BLP (vault owns the aTokens)
        uint256 withdrawn = pool.withdraw(ASSET, assets, address(this));

        // 3. Transfer underlying to receiver
        IERC20(ASSET).safeTransfer(receiver, withdrawn);

        emit Withdraw(msg.sender, receiver, owner, withdrawn, shares);

        return shares;
    }

    /**
     * @notice Redeems shares for assets
     * @dev ERC-4626-compatible signature
     * @param shares The amount of shares to burn
     * @param receiver The address that will receive the assets
     * @param owner The address that owns the shares
     * @return assets The amount of assets withdrawn (1:1 with shares)
     */
    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) external returns (uint256 assets) {
        require(shares > 0, 'MockUSDCVault: ZERO_SHARES');
        require(receiver != address(0), 'MockUSDCVault: ZERO_RECEIVER');
        require(owner != address(0), 'MockUSDCVault: ZERO_OWNER');

        // Calculate assets (1:1 for this mock)
        assets = shares;

        // If caller is not owner, check allowance
        if (msg.sender != owner) {
            uint256 allowed = allowance(owner, msg.sender);
            if (allowed != uint256(-1)) {
                require(allowed >= shares, 'MockUSDCVault: INSUFFICIENT_ALLOWANCE');
                _approve(owner, msg.sender, allowed - shares);
            }
        }

        ILendingPool pool = ILendingPool(ADDRESSES_PROVIDER.getLendingPool());

        // 1. Burn shares from owner
        _burn(owner, shares);

        // 2. Withdraw from BLP
        uint256 withdrawn = pool.withdraw(ASSET, assets, address(this));

        // 3. Transfer underlying to receiver
        IERC20(ASSET).safeTransfer(receiver, withdrawn);

        emit Withdraw(msg.sender, receiver, owner, withdrawn, shares);

        return assets;
    }

    // ========== VIEW FUNCTIONS ==========

    /**
     * @notice Returns the underlying asset address
     */
    function asset() external view returns (address) {
        return ASSET;
    }

    /**
     * @notice Returns the total assets under management
     * @dev For this mock: total supply of shares (1:1 ratio)
     */
    function totalAssets() external view returns (uint256) {
        return totalSupply();
    }

    /**
     * @notice Preview how many shares will be minted for assets
     * @dev 1:1 ratio for this mock
     */
    function previewDeposit(uint256 assets) external pure returns (uint256) {
        return assets;
    }

    /**
     * @notice Preview how many assets will be received for shares
     * @dev 1:1 ratio for this mock
     */
    function previewRedeem(uint256 shares) external pure returns (uint256) {
        return shares;
    }

    /**
     * @notice Preview how many shares will be burned for assets withdrawal
     * @dev 1:1 ratio for this mock
     */
    function previewWithdraw(uint256 assets) external pure returns (uint256) {
        return assets;
    }

    /**
     * @notice Returns the lending pool address
     */
    function getLendingPool() external view returns (address) {
        return ADDRESSES_PROVIDER.getLendingPool();
    }
}
