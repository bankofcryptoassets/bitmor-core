// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {console2} from "forge-std/console2.sol";

import {DeploymentHelper} from "../helpers/DeploymentHelper.s.sol";
import {HelperConfig} from "../HelperConfig.s.sol";
import {DeploymentConstants} from "../deployment/DeploymentConstants.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {MintableERC20} from "../../test/mock/MintableERC20.sol";

/// @title InteractionBase
/// @author Bitmor Protocol
/// @notice Base contract for all interaction scripts with environment-aware token funding
/// @dev Three environments with different funding strategies:
///      - Local Anvil (chainId 31337, no FORK): broadcast mint() on mock tokens,
///        pool seeding via broadcast mint + approve + USDCVault.deposit
///      - Fork Anvil (chainId 31337, FORK=base): vm.broadcast(whale) for real token transfers,
///        pool seeding via whale broadcast + USDCVault.deposit
///      - Live Base mainnet (chainId 8453): skip funding, user must hold tokens
///
///      Lending pool seeding always goes through USDCVault because the real LendingPool
///      (used on both local and fork) rejects direct deposits from non-vault callers (Error 85).
///      Note: USDCVault's strategy splits deposits ~80% Aave / ~20% BLP, so seed ~5x
///      the amount you need as BLP flash loan liquidity.
///
///      IMPORTANT: All addresses are cached in _preflight() because Foundry forbids
///      staticcalls (e.g., config.getUSDC()) after any broadcast block ends when
///      running with --unlocked. Cache everything before any broadcast.
abstract contract InteractionBase is DeploymentHelper {
    /// @dev HelperConfig instance — initialized by _preflight()
    HelperConfig public config;

    // ============ Cached Addresses ============
    // Populated by _preflight(). Must be read BEFORE any vm.broadcast() call because
    // Foundry forbids staticcalls after broadcast when using --unlocked.

    address internal _usdc;
    address internal _cbBTC;
    address internal _loan;
    address internal _bitmorPool;
    address internal _btcVault;
    address internal _usdcVault;
    bool internal _forkMode;
    bool internal _liveMode;
    address internal _broadcaster;

    // ============ Whale Addresses (Base Mainnet) ============
    // Used on fork to impersonate token transfers. Anvil unlocks all accounts by default.
    // Requires `anvil_impersonateAccount` RPC call or `--unlocked` flag.

    /// @dev Large USDC holder on Base mainnet (~$779K USDC at fork block)
    address internal constant USDC_WHALE = 0x20FE51A9229EEf2cF8Ad9E89d91CAb9312cF3b7A;

    /// @dev Large cbBTC holder on Base mainnet (~26K BTC at fork block)
    address internal constant CBBTC_WHALE = 0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb;

    // ============ Token Funding ============

    /// @notice Funds `to` with `amount` of USDC
    /// @dev Local/Testnet: broadcast mint() on mock token. Fork: broadcast transfer from whale. Live: skip.
    /// @param to Address to fund
    /// @param amount USDC amount (6 decimals)
    function _fundWithUSDC(address to, uint256 amount) internal {
        if (_liveMode) return;

        if (_forkMode) {
            vm.broadcast(USDC_WHALE);
            IERC20(_usdc).transfer(to, amount);
        } else {
            vm.broadcast();
            MintableERC20(_usdc).mint(to, amount);
        }
        console2.log("Funded USDC:", amount, "to:", to);
    }

    /// @notice Funds `to` with `amount` of cbBTC
    /// @dev Local/Testnet: broadcast mint() on mock token. Fork: broadcast transfer from whale. Live: skip.
    /// @param to Address to fund
    /// @param amount cbBTC amount (8 decimals)
    function _fundWithCbBTC(address to, uint256 amount) internal {
        if (_liveMode) return;

        if (_forkMode) {
            vm.broadcast(CBBTC_WHALE);
            IERC20(_cbBTC).transfer(to, amount);
        } else {
            vm.broadcast();
            MintableERC20(_cbBTC).mint(to, amount);
        }
        console2.log("Funded cbBTC:", amount, "to:", to);
    }

    // ============ Lending Pool Seeding ============

    /// @notice Seeds the Bitmor lending pool with USDC liquidity via USDCVault
    /// @dev Both local and fork route through USDCVault because the real LendingPool
    ///      gates deposit() to vault/loan callers only (Error 85: LP_CALLER_NOT_VAULT).
    ///      USDCVault's strategy splits deposits ~80% Aave / ~20% BLP (configurable).
    ///      To get X USDC of BLP liquidity, seed ~5X through USDCVault.
    ///      Local/Testnet: broadcast mint + approve + USDCVault.deposit.
    ///      Fork: broadcast as whale + USDCVault.deposit (persists on Anvil).
    ///      Live: skip (pool already has liquidity).
    /// @param amount USDC amount to deposit into USDCVault (6 decimals)
    function _seedLendingPoolUSDC(uint256 amount) internal {
        if (_liveMode) return;

        if (_forkMode) {
            // Check if whale has enough — skip if already depleted (pool may already be seeded)
            uint256 whaleBalance = IERC20(_usdc).balanceOf(USDC_WHALE);
            if (whaleBalance < amount) {
                console2.log("Whale USDC balance insufficient for seeding, skipping. Balance:", whaleBalance);
                return;
            }
            vm.startBroadcast(USDC_WHALE);
            IERC20(_usdc).approve(_usdcVault, amount);
            IERC4626(_usdcVault).deposit(amount, USDC_WHALE);
            vm.stopBroadcast();
        } else {
            // Mint and deposit for the configured broadcaster even before the main broadcast block.
            vm.startBroadcast();
            MintableERC20(_usdc).mint(_broadcaster, amount);
            IERC20(_usdc).approve(_usdcVault, amount);
            IERC4626(_usdcVault).deposit(amount, _broadcaster);
            vm.stopBroadcast();
        }

        console2.log("Seeded lending pool via USDCVault with USDC:", amount);
    }

    /// @dev Resolves the broadcaster address used for pre-broadcast routing.
    ///      Explicit `SENDER` still wins, otherwise prefer a single configured Foundry signer
    ///      (private key or keystore/account) before falling back to the current caller context.
    function _resolveBroadcaster() internal view returns (address) {
        address explicitSender = vm.envOr("SENDER", address(0));
        if (explicitSender != address(0)) return explicitSender;

        address[] memory wallets = vm.getWallets();
        if (wallets.length == 1) return wallets[0];

        return msg.sender;
    }

    /// @dev Resolves an optional funding target, defaulting to the cached broadcaster.
    function _resolveFundingTarget() internal view returns (address) {
        return vm.envOr("TARGET", _broadcaster);
    }

    // ============ Preflight ============

    /// @notice Validates deployed contracts and caches all addresses
    /// @dev Must be called at the start of every run() function, BEFORE any broadcast.
    ///      Caches addresses because Foundry forbids staticcalls after broadcast
    ///      when running with --unlocked (needed for whale impersonation on fork).
    function _preflight() internal {
        config = new HelperConfig();

        // Cache all addresses before any broadcast
        _usdc = config.getUSDC();
        _cbBTC = config.getCbBTC();
        _loan = config.getLoan();
        _bitmorPool = config.getBitmorPool();
        _btcVault = config.getBTCVault();
        _usdcVault = config.getUSDCVault();
        _forkMode = config.isForkMode();
        _liveMode = block.chainid == DeploymentConstants.BASE_MAINNET_CHAIN_ID;
        _broadcaster = _resolveBroadcaster();

        // Validate
        requireNonZero(_loan, "Loan");
        requireNonZero(_usdc, "USDC");
        requireNonZero(_bitmorPool, "BitmorPool");
        requireNonZero(_btcVault, "BTCVault");

        console2.log("Preflight passed. Environment:", _liveMode ? "LIVE" : (_forkMode ? "FORK" : "LOCAL"));
        console2.log("Broadcaster:", _broadcaster);
    }
}
