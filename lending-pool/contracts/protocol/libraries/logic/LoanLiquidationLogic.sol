// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import {SafeMath} from "../../../dependencies/openzeppelin/contracts/SafeMath.sol";
import {PercentageMath} from "../math/PercentageMath.sol";
import {DataTypes} from "../types/DataTypes.sol";
import {IPriceOracleGetter} from "../../../interfaces/IPriceOracleGetter.sol";
import {ReserveConfiguration} from "../configuration/ReserveConfiguration.sol";
import {GenericLogic} from "./GenericLogic.sol";
import {ILoan} from "../../../interfaces/ILoan.sol";
import {Helpers} from "../helpers/Helpers.sol";

library LoanLiquidationLogic {
    using SafeMath for uint256;
    using PercentageMath for uint256;
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;

    struct LiquidationVars {
        address collateralAsset;
        address debtAsset;
        uint256 collateralDecimals;
        uint256 debtDecimals;
        uint256 collateralUnitPrice;
        uint256 debtUnitPrice;
        uint256 collateralValueInUSD;
        uint256 currentDebtBalance;
        uint256 amountToBeDeducted;
        uint256 totalAmtToBeDeducted;
        uint256 amountToBeDeductedInUSD;
        uint256 remainingCollateralInUSD;
        uint256 debtBalanceAfter;
        uint256 guardAmount;
        uint256 guardAmountInUSD;
    }

    /**
     * @dev Calculates which type of Liquidation can be done for a user
     * It can return 0,1 and 2
     * 0 => No Liquidation
     * 1 => Full Liquidation in which case Liquidator can call `liquidationCall` function to liquidate complete position of the user
     * 2 => MicroLiquidate in which case Liquidator can `microLiquidationCall` function to micro liquidate user.
     * @param user The address of the LSA
     * @param reservesData Data of all the reserves
     * @param hf Health Factor of the user
     * @param oracle The price oracle address
     * @param bitmorLoan The Bitmor Protocol Loan provider address
     */
    function checkTypeOfLiquidation(
        address user,
        mapping(address => DataTypes.ReserveData) storage reservesData,
        uint256 hf,
        address oracle,
        ILoan bitmorLoan
    ) internal view returns (uint256) {
        DataTypes.LoanData memory loanData = bitmorLoan.getLoanByLSA(user);

        if (loanData.status != DataTypes.LoanStatus.Active) {
            return 0;
        }

        // If user is uninsured AND HF < threshold → full liquidation
        if ((loanData.insuranceID == 0) && !(hf >= GenericLogic.HEALTH_FACTOR_LIQUIDATION_THRESHOLD)) {
            return 1;
        }

        // If the EMI is not overdue → no liquidation
        if (
            loanData.lastPaymentTimestamp + bitmorLoan.getGracePeriod() + bitmorLoan.getRepaymentInterval()
                >= block.timestamp
        ) {
            return 0;
        }

        // Working variables packed in a memory struct to avoid "stack too deep"
        LiquidationVars memory v;

        uint256 bufferBPS = bitmorLoan.getLiquidationBuffer();

        v.collateralAsset = bitmorLoan.getCollateralAsset();
        v.debtAsset = bitmorLoan.getDebtAsset();

        // reserves: fetch decimals and variable debt token using collateral/debt asset addresses
        DataTypes.ReserveData storage collateralReserve = reservesData[v.collateralAsset];
        DataTypes.ReserveData storage debtReserve = reservesData[v.debtAsset];

        v.collateralDecimals = collateralReserve.configuration.getDecimals();
        v.debtDecimals = debtReserve.configuration.getDecimals();

        v.collateralUnitPrice = IPriceOracleGetter(oracle).getAssetPrice(v.collateralAsset);
        v.debtUnitPrice = IPriceOracleGetter(oracle).getAssetPrice(v.debtAsset);

        // collateral value in quote (USD if your oracle is USD)
        v.collateralValueInUSD = loanData.collateralAmount.mul(v.collateralUnitPrice).div(10 ** v.collateralDecimals);

        // current debt = balance of VARIABLE debt token
        (, v.currentDebtBalance) = Helpers.getUserCurrentDebt(user, debtReserve);

        // compute capped principal payment for this micro-liq
        v.amountToBeDeducted = _min(loanData.estimatedMonthlyPayment, v.currentDebtBalance);

        // total USDC leaving user’s position (principal paid + bonus to liquidator), but never exceed debt + bonus policy
        v.totalAmtToBeDeducted = v.amountToBeDeducted.add(v.amountToBeDeducted.percentMul(bufferBPS));

        // convert the outflow to USD (or quote)
        v.amountToBeDeductedInUSD = v.totalAmtToBeDeducted.mul(v.debtUnitPrice).div(10 ** v.debtDecimals);

        // If the collateral cannot even cover this micro-liq outflow → full liquidation
        if (v.collateralValueInUSD <= v.amountToBeDeductedInUSD) {
            return 1;
        }

        // remaining collateral value after selling BTC to cover (principal + bonus)
        v.remainingCollateralInUSD = v.collateralValueInUSD.sub(v.amountToBeDeductedInUSD);

        // new debt after paying ONLY the principal part
        v.debtBalanceAfter = v.currentDebtBalance.sub(v.amountToBeDeducted);

        // guard = debtAfter * (1 + bufferBPS)
        v.guardAmount = v.debtBalanceAfter.add(v.debtBalanceAfter.percentMul(bufferBPS));
        v.guardAmountInUSD = v.guardAmount.mul(v.debtUnitPrice).div(10 ** v.debtDecimals);

        if (v.remainingCollateralInUSD >= v.guardAmountInUSD) {
            // type 2 := micro-liquidation is sufficient
            return 2;
        } else {
            // full liquidation path — bonus based on remaining full debt
            return 1;
        }
    }

    function _min(uint256 a, uint256 b) private pure returns (uint256) {
        return a < b ? a : b;
    }
}
