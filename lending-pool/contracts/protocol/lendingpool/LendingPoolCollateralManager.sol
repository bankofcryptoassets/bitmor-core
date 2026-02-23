// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import {SafeMath} from "../../dependencies/openzeppelin/contracts//SafeMath.sol";
import {IERC20} from "../../dependencies/openzeppelin/contracts//IERC20.sol";
import {IAToken} from "../../interfaces/IAToken.sol";
import {IStableDebtToken} from "../../interfaces/IStableDebtToken.sol";
import {IVariableDebtToken} from "../../interfaces/IVariableDebtToken.sol";
import {IPriceOracleGetter} from "../../interfaces/IPriceOracleGetter.sol";
import {ILendingPoolCollateralManager} from "../../interfaces/ILendingPoolCollateralManager.sol";
import {VersionedInitializable} from "../libraries/aave-upgradeability/VersionedInitializable.sol";
import {GenericLogic} from "../libraries/logic/GenericLogic.sol";
import {Helpers} from "../libraries/helpers/Helpers.sol";
import {WadRayMath} from "../libraries/math/WadRayMath.sol";
import {PercentageMath} from "../libraries/math/PercentageMath.sol";
import {SafeERC20} from "../../dependencies/openzeppelin/contracts/SafeERC20.sol";
import {Errors} from "../libraries/helpers/Errors.sol";
import {ValidationLogic} from "../libraries/logic/ValidationLogic.sol";
import {DataTypes} from "../libraries/types/DataTypes.sol";
import {LendingPoolStorage} from "./LendingPoolStorage.sol";
import {LoanLiquidationLogic} from "../libraries/logic/LoanLiquidationLogic.sol";
import {ILoan} from "../../interfaces/ILoan.sol";
import {IERC4626} from "../../interfaces/IERC4626.sol";

/**
 * @title LendingPoolCollateralManager contract
 * @author Aave
 * @dev Implements actions involving management of collateral in the protocol, the main one being the liquidations
 * IMPORTANT This contract will run always via DELEGATECALL, through the LendingPool, so the chain of inheritance
 * is the same as the LendingPool, to have compatible storage layouts
 *
 */
contract LendingPoolCollateralManager is ILendingPoolCollateralManager, VersionedInitializable, LendingPoolStorage {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;
    using WadRayMath for uint256;
    using PercentageMath for uint256;
    /// @notice NOT REQUIRED because when checkTypeOfLiquidation returns for Full Liquidation, user have to be liquidated.
    // uint256 internal constant LIQUIDATION_CLOSE_FACTOR_PERCENT = 5000;

    struct LiquidationCallLocalVars {
        uint256 userCollateralBalance;
        uint256 userStableDebt;
        uint256 userVariableDebt;
        uint256 maxLiquidatableDebt;
        uint256 actualDebtToLiquidate;
        uint256 liquidationRatio;
        uint256 maxAmountCollateralToLiquidate;
        uint256 userStableRate;
        uint256 maxCollateralToLiquidate;
        uint256 debtAmountNeeded;
        uint256 healthFactor;
        uint256 liquidatorPreviousATokenBalance;
        uint256 protocolFee;
        uint256 liquidatorCollateral;
        uint256 liquidationBonus;
        address oracle;
        IAToken collateralAtoken;
        bool isCollateralEnabled;
        DataTypes.InterestRateMode borrowRateMode;
        uint256 errorCode;
        string errorMsg;
    }

    struct AvailableCollateralToLiquidateLocalVars {
        uint256 userCompoundedBorrowBalance;
        uint256 liquidationBonus;
        uint256 collateralPrice;
        uint256 debtAssetPrice;
        uint256 maxAmountCollateralToLiquidate;
        uint256 debtAssetDecimals;
        uint256 collateralDecimals;
    }

    /**
     * @dev As thiS contract extends the VersionedInitializable contract to match the state
     * of the LendingPool contract, the getRevision() function is needed, but the value is not
     * important, as the initialize() function will never be called here
     */
    function getRevision() internal pure override returns (uint256) {
        return 0;
    }

    /**
     * @dev Function to liquidate a position if its Health Factor drops below 1
     * - The caller (liquidator) covers `debtToCover` amount of debt of the user getting liquidated, and receives
     *   a proportionally amount of the `collateralAsset` plus a bonus to cover market risk
     *
     * Bitmor full-liquidation invariants:
     * - MUST revert if collateral is sufficient AND payment is current — i.e., the position
     *   is healthy and not past due (Invariant 4.10).
     * - If full liquidation succeeds, `loanData.status` MUST be set to `Liquidated` (Invariant 4.10).
     * - Fund distribution MUST follow this order (Invariant 4.11):
     *   Step 1: pool receives min(VDT balance, total liquidation proceeds).
     *   Step 2: liquidator receives min(bonus - `s_liquidationFee`, proceeds - pool_payment).
     *   Step 3: protocol receives `s_liquidationFee` portion + any remaining insurance amount.
     * - Liquidator bonus MUST NOT exceed `(LIQUIDATION_BONUS_BPS - 10000) / 10000 * debtToCover`
     *   minus the protocol fee portion (Invariant 4.12).
     * - USDC returned to pool MUST be >= min(VDT balance, collateral sale proceeds + insurance proceeds)
     *   to protect lender capital (Invariant 4.13).
     * - If BTC collateral is insufficient to cover the liquidator, insurance MUST be sold
     *   and proceeds sent to cover the shortfall (Invariant 4.9).
     *
     * @param collateralAsset The address of the underlying asset used as collateral, to receive as result of the liquidation
     * @param debtAsset The address of the underlying borrowed asset to be repaid with the liquidation
     * @param user The address of the borrower getting liquidated
     * @param debtToCover The debt amount of borrowed `debtAsset` the liquidator wants to cover.
     *                    Must be >= the user's full variable debt. Use `type(uint256).max` to guarantee
     *                    coverage regardless of interest accrual between off-chain read and on-chain execution.
     *                    The contract caps the actual amount to `userVariableDebt`.
     * @param receiveAToken `true` if the liquidator wants to receive the collateral aTokens, `false` if he wants
     * to receive the underlying collateral asset directly. Must be `false` in Bitmor (aToken receipt is rejected).
     *
     */
    function liquidationCall(
        address collateralAsset,
        address debtAsset,
        address user,
        uint256 debtToCover,
        bool receiveAToken
    ) external override returns (uint256, string memory) {
        DataTypes.ReserveData storage collateralReserve = _reserves[collateralAsset];

        DataTypes.ReserveData storage debtReserve = _reserves[debtAsset];

        DataTypes.UserConfigurationMap storage userConfig = _usersConfig[user];

        LiquidationCallLocalVars memory vars;

        vars.oracle = _addressesProvider.getPriceOracle();

        (,,,, vars.healthFactor) = GenericLogic.calculateUserAccountData(
            user, _reserves, userConfig, _reservesList, _reservesCount, vars.oracle
        );

        (vars.userStableDebt, vars.userVariableDebt) = Helpers.getUserCurrentDebt(user, debtReserve);

        uint256 typeOfLiquidation = LoanLiquidationLogic.checkTypeOfLiquidation(
            user, _reserves, vars.healthFactor, vars.oracle, ILoan(_addressesProvider.getBitmorLoan())
        );

        (vars.errorCode, vars.errorMsg) = ValidationLogic.validateLiquidationCall(
            collateralReserve,
            debtReserve,
            userConfig,
            typeOfLiquidation,
            vars.healthFactor,
            vars.userStableDebt,
            vars.userVariableDebt
        );

        if (Errors.CollateralManagerErrors(vars.errorCode) != Errors.CollateralManagerErrors.NO_ERROR) {
            return (vars.errorCode, vars.errorMsg);
        }

        vars.collateralAtoken = IAToken(collateralReserve.aTokenAddress);

        vars.userCollateralBalance = vars.collateralAtoken.balanceOf(user);

        // vars.maxLiquidatableDebt =
        //     vars.userStableDebt.add(vars.userVariableDebt).percentMul(LIQUIDATION_CLOSE_FACTOR_PERCENT);
        /// @dev Full Liquidation will ALWAYS fully liquidate the user.
        /// @dev vars.userStableDebt will always be 0 as both collaterals in Bitmor not offers stable borrow rate.
        vars.maxLiquidatableDebt = vars.userVariableDebt;

        // Enforce full debt coverage — prevents griefing via partial debtToCover.
        if (debtToCover < vars.maxLiquidatableDebt) {
            return (
                uint256(Errors.CollateralManagerErrors.INSUFFICIENT_DEBT_COVERAGE),
                Errors.LPCM_INSUFFICIENT_DEBT_COVERAGE
            );
        }

        vars.actualDebtToLiquidate = debtToCover > vars.maxLiquidatableDebt ? vars.maxLiquidatableDebt : debtToCover;

        (vars.maxCollateralToLiquidate, vars.debtAmountNeeded, vars.liquidationBonus) =
            _calculateAvailableCollateralToLiquidate(
                collateralReserve,
                debtReserve,
                collateralAsset,
                debtAsset,
                vars.actualDebtToLiquidate,
                vars.userCollateralBalance
            );

        // If debtAmountNeeded < actualDebtToLiquidate, there isn't enough
        // collateral to cover the actual amount that is being liquidated, hence we liquidate
        // a smaller amount

        if (vars.debtAmountNeeded < vars.actualDebtToLiquidate) {
            vars.actualDebtToLiquidate = vars.debtAmountNeeded;
        }

        // If the liquidator reclaims the underlying asset, we make sure there is enough available liquidity in the
        // collateral reserve
        if (!receiveAToken) {
            uint256 currentAvailableCollateral = IERC20(collateralAsset).balanceOf(address(vars.collateralAtoken));
            if (currentAvailableCollateral < vars.maxCollateralToLiquidate) {
                return (
                    uint256(Errors.CollateralManagerErrors.NOT_ENOUGH_LIQUIDITY),
                    Errors.LPCM_NOT_ENOUGH_LIQUIDITY_TO_LIQUIDATE
                );
            }
        }

        debtReserve.updateState();

        if (vars.userVariableDebt >= vars.actualDebtToLiquidate) {
            IVariableDebtToken(debtReserve.variableDebtTokenAddress)
                .burn(user, vars.actualDebtToLiquidate, debtReserve.variableBorrowIndex);
        } else {
            // TODO: Check if this condition will meet.
            // If the user doesn't have variable debt, no need to try to burn variable debt tokens
            if (vars.userVariableDebt > 0) {
                IVariableDebtToken(debtReserve.variableDebtTokenAddress)
                    .burn(user, vars.userVariableDebt, debtReserve.variableBorrowIndex);
            }
            /// @dev Since there's no stable borrow debt, so no need to burn.
            // IStableDebtToken(debtReserve.stableDebtTokenAddress).burn(
            //     user,
            //     vars.actualDebtToLiquidate.sub(vars.userVariableDebt)
            // );
        }

        debtReserve.updateInterestRates(debtAsset, debtReserve.aTokenAddress, vars.actualDebtToLiquidate, 0);

        // Calculate fee split
        (vars.protocolFee, vars.liquidatorCollateral) = _calculateProtocolFee(
            vars.maxCollateralToLiquidate,
            vars.liquidationBonus,
            ILoan(_addressesProvider.getBitmorLoan()).getLiquidationFeeBps()
        );
        if (receiveAToken) {
            /// @dev Liquidator SHOULD NOT be able to create a collateral position in the protocol.
            return (uint256(Errors.CollateralManagerErrors.CANNOT_RECEIVE_ATOKEN), Errors.LPCM_CANNOT_RECEIVE_ATOKEN);
        } else {
            collateralReserve.updateState();
            collateralReserve.updateInterestRates(
                collateralAsset, address(vars.collateralAtoken), 0, vars.maxCollateralToLiquidate
            );

            // Burn aTokens, receive bvBTC to LendingPool
            vars.collateralAtoken
                .burn(user, address(this), vars.maxCollateralToLiquidate, collateralReserve.liquidityIndex);

            // Get slippage tolerance from Loan contract
            uint256 slippageBps = ILoan(_addressesProvider.getBitmorLoan()).getSlippageForSharesToAsset();

            // Redeem bvBTC → cbBTC for liquidator
            uint256 assetsSent =
                _redeemCollateralWithSlippage(collateralAsset, vars.liquidatorCollateral, msg.sender, slippageBps);

            if (assetsSent == 0) {
                return (uint256(Errors.CollateralManagerErrors.SLIPPAGE_EXCEEDED), Errors.LPCM_SLIPPAGE_EXCEEDED);
            }

            // Redeem bvBTC → cbBTC for protocol fee collector
            if (vars.protocolFee > 0) {
                assetsSent = _redeemCollateralWithSlippage(
                    collateralAsset,
                    vars.protocolFee,
                    ILoan(_addressesProvider.getBitmorLoan()).getLiquidationFeeCollector(),
                    slippageBps
                );

                if (assetsSent == 0) {
                    return (uint256(Errors.CollateralManagerErrors.SLIPPAGE_EXCEEDED), Errors.LPCM_SLIPPAGE_EXCEEDED);
                }

                emit ProtocolLiquidationFee(collateralAsset, user, msg.sender, vars.protocolFee);
            }
        }

        // If the collateral being liquidated is equal to the user balance,
        // we set the currency as not being used as collateral anymore
        if (vars.maxCollateralToLiquidate == vars.userCollateralBalance) {
            userConfig.setUsingAsCollateral(collateralReserve.id, false);
            emit ReserveUsedAsCollateralDisabled(collateralAsset, user);
        }
        _updateLoanForFullLiquidation(user);
        // Transfers the debt asset being repaid to the aToken, where the liquidity is kept
        IERC20(debtAsset).safeTransferFrom(msg.sender, debtReserve.aTokenAddress, vars.actualDebtToLiquidate);

        emit LiquidationCall(
            collateralAsset,
            debtAsset,
            user,
            vars.actualDebtToLiquidate,
            vars.maxCollateralToLiquidate,
            msg.sender,
            receiveAToken
        );

        return (uint256(Errors.CollateralManagerErrors.NO_ERROR), Errors.LPCM_NO_ERRORS);
    }

    /**
     * @dev Function to micro-liquidate a user who didn't pay its monthly installment for their loan.
     * - The caller (liquidator) pays the monthly installment amount, receives equivalent value of underlying asset used as collateral and increase loan's nextDueDate by 30 days.
     *
     * Bitmor micro-liquidation invariants:
     * - `debtToCover` MUST equal `estimatedMonthlyPayment`, capped at VDT balance (Invariant 4.6).
     * - Actual BTC sold MUST equal cash_needed / price (+/- 1 wei rounding) (Invariant 4.6).
     * - After execution, USDC debt MUST decrease by `debtToCover`, `loanData.duration` MUST
     *   decrease by 1, `loanData.status` MUST remain Active, and `lastPaymentTimestamp`
     *   MUST be updated to `block.timestamp` (Invariant 4.8).
     * - If BTC collateral is insufficient to cover the liquidator, insurance MUST be sold
     *   and proceeds sent to cover the shortfall (Invariant 4.9).
     * - Liquidator bonus MUST NOT exceed `liquidation_bonus * estimatedMonthlyPayment - protocol_fee` (Invariant 4.12).
     *
     * @param data Microliquidation call data
     */
    function microLiquidationCall(bytes calldata data) external override returns (uint256, string memory) {
        /// @dev Here `user` is the `lsa`.
        (address collateralAsset, address debtAsset, address user) = abi.decode(data, (address, address, address));

        /// @dev No one can deposit in the Lending Pool without going through loan creation process.
        bool receiveAToken = false;

        DataTypes.ReserveData storage collateralReserve = _reserves[collateralAsset];
        DataTypes.ReserveData storage debtReserve = _reserves[debtAsset];
        DataTypes.UserConfigurationMap storage userConfig = _usersConfig[user];

        LiquidationCallLocalVars memory vars;

        (,,,, vars.healthFactor) = GenericLogic.calculateUserAccountData(
            user, _reserves, userConfig, _reservesList, _reservesCount, _addressesProvider.getPriceOracle()
        );

        (vars.userStableDebt, vars.userVariableDebt) = Helpers.getUserCurrentDebt(user, debtReserve);

        uint256 typeOfLiquidation = LoanLiquidationLogic.checkTypeOfLiquidation(
            user,
            _reserves,
            vars.healthFactor,
            _addressesProvider.getPriceOracle(),
            ILoan(_addressesProvider.getBitmorLoan())
        );

        (vars.errorCode, vars.errorMsg) = ValidationLogic.validateMicroLiquidationCall(
            collateralReserve, debtReserve, userConfig, typeOfLiquidation, vars.userStableDebt, vars.userVariableDebt
        );

        if (Errors.CollateralManagerErrors(vars.errorCode) != Errors.CollateralManagerErrors.NO_ERROR) {
            return (vars.errorCode, vars.errorMsg);
        }

        vars.collateralAtoken = IAToken(collateralReserve.aTokenAddress);

        vars.userCollateralBalance = vars.collateralAtoken.balanceOf(user);

        address bitmorLoan = _addressesProvider.getBitmorLoan();

        DataTypes.LoanData memory loanData = ILoan(bitmorLoan).getLoanByLSA(user);

        if (loanData.duration == 1) {
            vars.actualDebtToLiquidate = vars.userVariableDebt;
        } else {
            vars.actualDebtToLiquidate = loanData.estimatedMonthlyPayment > vars.userVariableDebt
                ? vars.userVariableDebt
                : loanData.estimatedMonthlyPayment;
        }

        (vars.maxCollateralToLiquidate, vars.debtAmountNeeded, vars.liquidationBonus) =
            _calculateAvailableCollateralToLiquidate(
                collateralReserve,
                debtReserve,
                collateralAsset,
                debtAsset,
                vars.actualDebtToLiquidate,
                vars.userCollateralBalance
            );

        // If debtAmountNeeded < actualDebtToLiquidate, there isn't enough
        // collateral to cover the actual amount that is being liquidated, hence we liquidate
        // a smaller amount

        if (vars.debtAmountNeeded < vars.actualDebtToLiquidate) {
            vars.actualDebtToLiquidate = vars.debtAmountNeeded;
        }

        // If the liquidator reclaims the underlying asset, we make sure there is enough available liquidity in the
        // collateral reserve
        if (!receiveAToken) {
            uint256 currentAvailableCollateral = IERC20(collateralAsset).balanceOf(address(vars.collateralAtoken));
            if (currentAvailableCollateral < vars.maxCollateralToLiquidate) {
                return (
                    uint256(Errors.CollateralManagerErrors.NOT_ENOUGH_LIQUIDITY),
                    Errors.LPCM_NOT_ENOUGH_LIQUIDITY_TO_LIQUIDATE
                );
            }
        }

        debtReserve.updateState();

        if (vars.userVariableDebt >= vars.actualDebtToLiquidate) {
            IVariableDebtToken(debtReserve.variableDebtTokenAddress)
                .burn(user, vars.actualDebtToLiquidate, debtReserve.variableBorrowIndex);
        } else {
            // TODO: Check if this condition will meet.
            // If the user doesn't have variable debt, no need to try to burn variable debt tokens
            if (vars.userVariableDebt > 0) {
                IVariableDebtToken(debtReserve.variableDebtTokenAddress)
                    .burn(user, vars.userVariableDebt, debtReserve.variableBorrowIndex);
            }
            /// @dev Since there's no stable borrow debt, so no need to burn.
            // IStableDebtToken(debtReserve.stableDebtTokenAddress).burn(
            //     user,
            //     vars.actualDebtToLiquidate.sub(vars.userVariableDebt)
            // );
        }

        debtReserve.updateInterestRates(debtAsset, debtReserve.aTokenAddress, vars.actualDebtToLiquidate, 0);

        // Calculate fee split
        (vars.protocolFee, vars.liquidatorCollateral) = _calculateProtocolFee(
            vars.maxCollateralToLiquidate,
            vars.liquidationBonus,
            ILoan(_addressesProvider.getBitmorLoan()).getLiquidationFeeBps()
        );

        if (receiveAToken) {
            /// @dev Liquidator SHOULD NOT be able to create a collateral position in the protocol.
            return (uint256(Errors.CollateralManagerErrors.CANNOT_RECEIVE_ATOKEN), Errors.LPCM_CANNOT_RECEIVE_ATOKEN);
        } else {
            collateralReserve.updateState();
            collateralReserve.updateInterestRates(
                collateralAsset, address(vars.collateralAtoken), 0, vars.maxCollateralToLiquidate
            );

            // Burn aTokens, receive bvBTC to LendingPool
            vars.collateralAtoken
                .burn(user, address(this), vars.maxCollateralToLiquidate, collateralReserve.liquidityIndex);

            // Get slippage tolerance from Loan contract
            uint256 slippageBps = ILoan(_addressesProvider.getBitmorLoan()).getSlippageForSharesToAsset();

            // Redeem bvBTC → cbBTC for liquidator
            uint256 assetsSent =
                _redeemCollateralWithSlippage(collateralAsset, vars.liquidatorCollateral, msg.sender, slippageBps);

            if (assetsSent == 0) {
                return (uint256(Errors.CollateralManagerErrors.SLIPPAGE_EXCEEDED), Errors.LPCM_SLIPPAGE_EXCEEDED);
            }

            // Redeem bvBTC → cbBTC for protocol fee collector
            if (vars.protocolFee > 0) {
                assetsSent = _redeemCollateralWithSlippage(
                    collateralAsset,
                    vars.protocolFee,
                    ILoan(_addressesProvider.getBitmorLoan()).getLiquidationFeeCollector(),
                    slippageBps
                );

                if (assetsSent == 0) {
                    return (uint256(Errors.CollateralManagerErrors.SLIPPAGE_EXCEEDED), Errors.LPCM_SLIPPAGE_EXCEEDED);
                }
                emit ProtocolLiquidationFee(collateralAsset, user, msg.sender, vars.protocolFee);
            }
        }

        // If the collateral being liquidated is equal to the user balance,
        // we set the currency as not being used as collateral anymore
        if (vars.maxCollateralToLiquidate == vars.userCollateralBalance) {
            userConfig.setUsingAsCollateral(collateralReserve.id, false);
            emit ReserveUsedAsCollateralDisabled(collateralAsset, user);
        }

        if (loanData.duration.sub(1) == 0) {
            _updateLoanForMicroLiquidationCompletion(user);
        } else {
            _updateLoanForMicroLiquidation(user);
        }

        // Transfers the debt asset being repaid to the aToken, where the liquidity is kept
        IERC20(debtAsset).safeTransferFrom(msg.sender, debtReserve.aTokenAddress, vars.actualDebtToLiquidate);

        emit MicroLiquidationCall(
            collateralAsset,
            debtAsset,
            user,
            vars.actualDebtToLiquidate,
            vars.maxCollateralToLiquidate,
            msg.sender,
            receiveAToken
        );

        return (uint256(Errors.CollateralManagerErrors.NO_ERROR), Errors.LPCM_NO_ERRORS);
    }

    /**
     * @notice Routes a standard micro-liquidation update to the external Loan contract
     * @dev Called when `duration > 1`. Reduces loan duration by 1 and updates payment timestamp.
     * @param lsa The Loan Specific Address
     */
    function _updateLoanForMicroLiquidation(address lsa) internal {
        address bitmorLoan = _addressesProvider.getBitmorLoan();
        ILoan(bitmorLoan).updateLoanDataForMicroLiquidation(lsa);
    }

    /**
     * @notice Routes a final micro-liquidation completion to the external Loan contract
     * @dev Called when `duration == 1`. Sets loan to Completed, returns remaining collateral to borrower.
     * @param lsa The Loan Specific Address
     */
    function _updateLoanForMicroLiquidationCompletion(address lsa) internal {
        address bitmorLoan = _addressesProvider.getBitmorLoan();
        ILoan(bitmorLoan).updateLoanForMicroLiquidationCompletion(lsa);
    }

    /**
     * @notice Routes a full liquidation update to the external Loan contract
     * @dev Sets duration to 0, status to Liquidated, updates payment timestamp.
     * @param lsa The Loan Specific Address
     */
    function _updateLoanForFullLiquidation(address lsa) internal {
        address bitmorLoan = _addressesProvider.getBitmorLoan();
        ILoan(bitmorLoan).updateLoanDataForFullLiquidation(lsa);
    }

    /**
     * @dev Calculates how much of a specific collateral can be liquidated, given
     * a certain amount of debt asset.
     * - This function needs to be called after all the checks to validate the liquidation have been performed,
     *   otherwise it might fail.
     * @param collateralReserve The data of the collateral reserve
     * @param debtReserve The data of the debt reserve
     * @param collateralAsset The address of the underlying asset used as collateral, to receive as result of the liquidation
     * @param debtAsset The address of the underlying borrowed asset to be repaid with the liquidation
     * @param debtToCover The debt amount of borrowed `asset` the liquidator wants to cover
     * @param userCollateralBalance The collateral balance for the specific `collateralAsset` of the user being liquidated
     * @return collateralAmount: The maximum amount that is possible to liquidate given all the liquidation constraints
     *                           (user balance, close factor)
     *         debtAmountNeeded: The amount to repay with the liquidation
     *
     */
    function _calculateAvailableCollateralToLiquidate(
        DataTypes.ReserveData storage collateralReserve,
        DataTypes.ReserveData storage debtReserve,
        address collateralAsset,
        address debtAsset,
        uint256 debtToCover,
        uint256 userCollateralBalance
    ) internal view returns (uint256, uint256, uint256) {
        uint256 collateralAmount = 0;
        uint256 debtAmountNeeded = 0;
        IPriceOracleGetter oracle = IPriceOracleGetter(_addressesProvider.getPriceOracle());

        AvailableCollateralToLiquidateLocalVars memory vars;

        vars.collateralPrice = oracle.getAssetPrice(collateralAsset);
        vars.debtAssetPrice = oracle.getAssetPrice(debtAsset);

        (,, vars.liquidationBonus, vars.collateralDecimals,) = collateralReserve.configuration.getParams();
        vars.debtAssetDecimals = debtReserve.configuration.getDecimals();

        // This is the maximum possible amount of the selected collateral that can be liquidated, given the
        // max amount of liquidatable debt
        vars.maxAmountCollateralToLiquidate = vars.debtAssetPrice.mul(debtToCover).mul(10 ** vars.collateralDecimals)
            .percentMul(vars.liquidationBonus).div(vars.collateralPrice.mul(10 ** vars.debtAssetDecimals));

        if (vars.maxAmountCollateralToLiquidate > userCollateralBalance) {
            collateralAmount = userCollateralBalance;
            debtAmountNeeded = vars.collateralPrice.mul(collateralAmount).mul(10 ** vars.debtAssetDecimals)
                .div(vars.debtAssetPrice.mul(10 ** vars.collateralDecimals)).percentDiv(vars.liquidationBonus);
        } else {
            collateralAmount = vars.maxAmountCollateralToLiquidate;
            debtAmountNeeded = debtToCover;
        }
        return (collateralAmount, debtAmountNeeded, vars.liquidationBonus);
    }

    /**
     * @notice Calculates the protocol fee and liquidator's share of collateral
     * @dev The protocol fee is taken as a percentage of the liquidation bonus only, not the base collateral
     *
     * Math breakdown:
     * - maxCollateralToLiquidate = baseCollateral * (liquidationBonus / 10000)
     * - baseCollateral = maxCollateral / (liquidationBonus / 10000) = maxCollateral * 10000 / liquidationBonus
     * - bonusCollateral = maxCollateral - baseCollateral
     * - protocolFee = bonusCollateral * (liquidationFee / 10000)
     * - liquidatorCollateral = maxCollateral - protocolFee
     *
     * Example: If liquidationBonus = 10500 (105%) and liquidationFee = 2000 (20%):
     * - maxCollateral = 105 tokens
     * - baseCollateral = 105 * 10000 / 10500 = 100 tokens
     * - bonusCollateral = 105 - 100 = 5 tokens
     * - protocolFee = 5 * 2000 / 10000 = 1 token
     * - liquidatorCollateral = 105 - 1 = 104 tokens
     *
     * @param maxCollateralToLiquidate Total collateral to liquidate (includes bonus)
     * @param liquidationBonusPercent Liquidation bonus in basis points (e.g., 10500 = 105%)
     * @param liquidationFee Protocol fee as percentage of bonus in basis points (e.g., 2000 = 20%)
     * @return protocolFee Amount of collateral going to protocol
     * @return liquidatorCollateral Amount of collateral going to liquidator
     */
    function _calculateProtocolFee(
        uint256 maxCollateralToLiquidate,
        uint256 liquidationBonusPercent,
        uint256 liquidationFee
    ) internal pure returns (uint256 protocolFee, uint256 liquidatorCollateral) {
        if (liquidationFee == 0) return (0, maxCollateralToLiquidate);

        // Calculate base collateral (what liquidator would get without bonus)
        // baseCollateral = maxCollateral / (liquidationBonus / PERCENTAGE_FACTOR)
        uint256 baseCollateral = maxCollateralToLiquidate.percentDiv(liquidationBonusPercent);

        // Bonus is the difference
        uint256 bonusCollateral = maxCollateralToLiquidate.sub(baseCollateral);

        // Protocol fee is percentage of bonus
        protocolFee = bonusCollateral.percentMul(liquidationFee);

        // Liquidator gets total minus protocol fee
        liquidatorCollateral = maxCollateralToLiquidate.sub(protocolFee);
    }

    /**
     * @notice Redeems vault shares (bvBTC) for underlying asset (cbBTC) with slippage protection
     * @param vault The ERC4626 vault address (collateralAsset / bvBTC)
     * @param shares Amount of vault shares to redeem
     * @param receiver Address to receive the underlying cbBTC
     * @param slippageBps Maximum acceptable slippage in basis points
     * @return assets Amount of underlying assets (cbBTC) received
     */
    function _redeemCollateralWithSlippage(address vault, uint256 shares, address receiver, uint256 slippageBps)
        internal
        returns (uint256 assets)
    {
        // Calculate expected assets from shares
        uint256 expectedAssets = IERC4626(vault).previewRedeem(shares);

        // Calculate minimum acceptable assets (accounting for slippage)
        uint256 minAssets =
            expectedAssets.mul(PercentageMath.PERCENTAGE_FACTOR.sub(slippageBps)).div(PercentageMath.PERCENTAGE_FACTOR);

        // Execute redemption
        assets = IERC4626(vault).redeem(shares, receiver, address(this));

        // Verify slippage protection
        if (assets < minAssets) return 0;

        return assets;
    }
}
