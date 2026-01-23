// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.6.12;

/**
 * @dev Added for Hardhat 3 / ethers v6 test infrastructure to support bvBTC collateral testing.
 * Simulates production BTCVault (ERC-4626) behavior:
 * - Users deposit cbBTC and receive bvBTC vault shares
 * - Vault deposits to LendingPool and holds aTokens
 * - Enables testing vault-based deposit flow (LP_CALLER_NOT_VAULT check)
 */

import {ERC20} from '../../dependencies/openzeppelin/contracts/ERC20.sol';
import {IERC20} from '../../dependencies/openzeppelin/contracts/IERC20.sol';
import {SafeERC20} from '../../dependencies/openzeppelin/contracts/SafeERC20.sol';
import {ILendingPool} from '../../interfaces/ILendingPool.sol';
import {ILendingPoolAddressesProvider} from '../../interfaces/ILendingPoolAddressesProvider.sol';

/**
 * @title MockBTCVault
 * @notice ERC-4626-like mock vault for testing - wraps cbBTC → bvBTC shares
 * @dev Deposits cbBTC to BLP, vault receives aTokens, user receives bvBTC shares
 *
 * Key behaviors matching production:
 * - Users call deposit(assets, receiver) - matches ERC-4626 signature
 * - Users receive vault SHARES (1:1 with assets for simplicity)
 * - Vault deposits to BLP and receives aTokens
 * - Vault holds the aTokens, not the end user
 * - withdraw() burns shares and returns underlying assets
 *
 * Differences from production:
 * - 1:1 share ratio (no yield accumulation)
 * - No access control, pausability, or strategy management
 */
contract MockBTCVault is ERC20 {
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
     * @param asset The underlying asset (cbBTC)
     */
    constructor(address addressesProvider, address asset) public ERC20('Bitmor BTC Vault', 'bvBTC') {
        require(addressesProvider != address(0), 'MockBTCVault: INVALID_ADDRESSES_PROVIDER');
        require(asset != address(0), 'MockBTCVault: INVALID_ASSET');

        ADDRESSES_PROVIDER = ILendingPoolAddressesProvider(addressesProvider);
        ASSET = asset;

        // Set decimals to match underlying asset (8 for BTC)
        uint8 assetDecimals = ERC20(asset).decimals();
        _setupDecimals(assetDecimals);
    }

    /**
     * @notice Deposits assets into the vault
     * @dev ERC-4626-compatible signature
     *
     * Flow:
     * 1. Transfer assets from caller to vault
     * 2. Vault deposits to BLP (vault receives aTokens)
     * 3. Mint shares to receiver (1:1 ratio)
     *
     * @param assets The amount of underlying asset to deposit
     * @param receiver The address that will receive the vault shares
     * @return shares The amount of shares minted (1:1 with assets)
     */
    function deposit(uint256 assets, address receiver) external returns (uint256 shares) {
        require(assets > 0, 'MockBTCVault: ZERO_ASSETS');
        require(receiver != address(0), 'MockBTCVault: ZERO_RECEIVER');

        // Calculate shares (1:1 for this mock)
        shares = assets;

        ILendingPool pool = ILendingPool(ADDRESSES_PROVIDER.getLendingPool());

        // 1. Transfer assets from caller to vault
        IERC20(ASSET).safeTransferFrom(msg.sender, address(this), assets);

        // 2. Approve BLP to spend vault's assets
        IERC20(ASSET).safeApprove(address(pool), 0);
        IERC20(ASSET).safeApprove(address(pool), assets);

        // 3. Deposit to BLP - vault is registered as BitmorLoan for BTC deposits
        // msg.sender = vault, onBehalfOf = vault (vault receives aTokens)
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
     * @param assets The amount of underlying asset to withdraw
     * @param receiver The address that will receive the assets
     * @param owner The address that owns the shares
     * @return shares The amount of shares burned (1:1 with assets)
     */
    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) external returns (uint256 shares) {
        require(assets > 0, 'MockBTCVault: ZERO_ASSETS');
        require(receiver != address(0), 'MockBTCVault: ZERO_RECEIVER');
        require(owner != address(0), 'MockBTCVault: ZERO_OWNER');

        shares = assets;

        if (msg.sender != owner) {
            uint256 allowed = allowance(owner, msg.sender);
            if (allowed != uint256(-1)) {
                require(allowed >= shares, 'MockBTCVault: INSUFFICIENT_ALLOWANCE');
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
     */
    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) external returns (uint256 assets) {
        require(shares > 0, 'MockBTCVault: ZERO_SHARES');
        require(receiver != address(0), 'MockBTCVault: ZERO_RECEIVER');
        require(owner != address(0), 'MockBTCVault: ZERO_OWNER');

        assets = shares;

        if (msg.sender != owner) {
            uint256 allowed = allowance(owner, msg.sender);
            if (allowed != uint256(-1)) {
                require(allowed >= shares, 'MockBTCVault: INSUFFICIENT_ALLOWANCE');
                _approve(owner, msg.sender, allowed - shares);
            }
        }

        ILendingPool pool = ILendingPool(ADDRESSES_PROVIDER.getLendingPool());

        _burn(owner, shares);
        uint256 withdrawn = pool.withdraw(ASSET, assets, address(this));
        IERC20(ASSET).safeTransfer(receiver, withdrawn);

        emit Withdraw(msg.sender, receiver, owner, withdrawn, shares);

        return assets;
    }

    // ========== ERC-4626 VIEW FUNCTIONS ==========

    /**
     * @notice Returns the underlying asset address
     */
    function asset() external view returns (address) {
        return ASSET;
    }

    /**
     * @notice Returns the total assets under management
     */
    function totalAssets() external view returns (uint256) {
        return totalSupply();
    }

    /**
     * @notice Convert shares to assets (1:1 for mock)
     */
    function convertToAssets(uint256 shares) external pure returns (uint256) {
        return shares;
    }

    /**
     * @notice Convert assets to shares (1:1 for mock)
     */
    function convertToShares(uint256 assets) external pure returns (uint256) {
        return assets;
    }

    /**
     * @notice Preview deposit (1:1 for mock)
     */
    function previewDeposit(uint256 assets) external pure returns (uint256) {
        return assets;
    }

    /**
     * @notice Preview redeem (1:1 for mock)
     */
    function previewRedeem(uint256 shares) external pure returns (uint256) {
        return shares;
    }

    /**
     * @notice Preview withdraw (1:1 for mock)
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

    // ========== TEST HELPERS ==========

    /**
     * @notice Mint shares directly without deposit (test helper)
     */
    function mint(address to, uint256 shares) external {
        _mint(to, shares);
    }

    /**
     * @notice Burn shares directly (test helper)
     */
    function burn(address from, uint256 shares) external {
        _burn(from, shares);
    }
}
