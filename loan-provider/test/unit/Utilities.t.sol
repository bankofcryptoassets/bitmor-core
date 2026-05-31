// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {DataTypes} from "@bitmor/libraries/types/DataTypes.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {Errors} from "@bitmor/libraries/helpers/Errors.sol";
import {ILendingPool} from "@bitmor/interfaces/ILendingPool.sol";
import {ILendingPoolAddressesProvider} from "@bitmor/interfaces/ILendingPoolAddressesProvider.sol";
import {IPriceOracleGetter} from "@bitmor/interfaces/IPriceOracleGetter.sol";
import {ILoanVault} from "@bitmor/interfaces/ILoanVault.sol";
import {IReserveInterestRateStrategy} from "@bitmor/interfaces/IReserveInterestRateStrategy.sol";
import {Loan} from "@bitmor/protocol/Loan.sol";

/// @title Utilities
/// @author Bitmor Protocol
/// @notice Shared utility contract for Bitmor Protocol tests providing token, oracle, time, and liquidation helpers
/// @dev Abstract base inheriting from `Test` for vm cheatcodes. Organized by category: token minting,
///      loan factory, reserve balances, oracle manipulation, time warping, assertions, and liquidation.
abstract contract Utilities is Test {
    // ============ Constants ============

    uint256 internal constant UTILITIES_RAY = 1e27;
    uint256 internal constant UTILITIES_LOAN_REPAYMENT_INTERVAL = 30 days;

    // ============ 0) Token Minting Helpers ============

    /// @notice Mint any token to any address using its mint(uint256) hook
    /// @dev Uses a low-level call so mocks can expose mint without a shared interface
    /// @param token The token address to mint
    /// @param to The address to mint to (will be pranked)
    /// @param amount Amount to mint
    function _utilMintTokenTo(address token, address to, uint256 amount) internal {
        vm.prank(to);
        (bool success,) = token.call(abi.encodeWithSignature("mint(uint256)", amount));
        assertTrue(success, "MINT_ERROR");
    }

    /// @notice Mint token and approve spender in a single helper
    /// @dev Combines minting + approval pattern used across multiple test files
    /// @param token The token address to mint
    /// @param to The address to mint to
    /// @param spender The address to approve for spending
    /// @param amount Amount to mint and approve
    function _utilMintTokenAndApprove(address token, address to, address spender, uint256 amount) internal {
        vm.startPrank(to);
        (bool success,) = token.call(abi.encodeWithSignature("mint(uint256)", amount));
        assertTrue(success, "MINT_ERROR");
        IERC20(token).approve(spender, amount);
        vm.stopPrank();
    }

    /// @notice Mint token and approve max spending
    /// @dev Useful for liquidators and other actors that need unlimited approval
    /// @param token The token address to mint
    /// @param to The address to mint to
    /// @param spender The address to approve for spending
    /// @param amount Amount to mint
    function _utilMintTokenAndApproveMax(address token, address to, address spender, uint256 amount) internal {
        vm.startPrank(to);
        (bool success,) = token.call(abi.encodeWithSignature("mint(uint256)", amount));
        assertTrue(success, "MINT_ERROR");
        IERC20(token).approve(spender, type(uint256).max);
        vm.stopPrank();
    }

    // ============ 1) Loan Factory / Scenario Helpers ============

    /// @notice Create a loan and return LSA address with loan data
    /// @param loanContract The Loan contract instance
    /// @param loanUser The user creating the loan
    /// @param btcAmount Amount of collateral for the loan
    /// @param duration Loan duration in months
    /// @param premiumAmount Premium amount for insurance
    /// @param data Additional loan data
    /// @return lsa The created Loan Smart Account address
    /// @return loanData The loan data struct
    function _utilCreateLoan(
        Loan loanContract,
        address loanUser,
        uint256 btcAmount,
        uint256 duration,
        uint256 premiumAmount,
        bytes memory data
    ) internal returns (address lsa, DataTypes.LoanData memory loanData) {
        (,, uint256 minDepositRequired) = loanContract.getLoanDetails(btcAmount, duration);

        vm.prank(loanUser);
        lsa = loanContract.initializeLoan(minDepositRequired, premiumAmount, btcAmount, duration, data);

        loanData = loanContract.getLoanByLSA(lsa);
    }

    /// @notice Get loan parameters for given collateral and duration
    /// @param loanContract The Loan contract instance
    /// @param btcAmount Amount of collateral
    /// @param duration Loan duration in months
    /// @return loanAmount The calculated loan amount
    /// @return minDepositRequired The minimum deposit required
    function _utilGetLoanParams(Loan loanContract, uint256 btcAmount, uint256 duration)
        internal
        view
        returns (uint256 loanAmount, uint256 minDepositRequired)
    {
        (loanAmount,, minDepositRequired) = loanContract.getLoanDetails(btcAmount, duration);
    }

    /// @notice Mint debt tokens to user and approve spending
    /// @param loanUser The user to fund
    /// @param debtAsset The debt asset address
    /// @param loanContract The loan contract to approve
    /// @param amount Amount to mint
    function _utilSeedUserAndApprove(address loanUser, address debtAsset, address loanContract, uint256 amount)
        internal
    {
        _utilMintTokenAndApprove(debtAsset, loanUser, loanContract, amount);
    }

    // ============ 2) Aave/Reserve Balance Helpers ============

    /// @notice Get variable debt token balance for an LSA
    /// @param bitmorPool The Bitmor lending pool address
    /// @param debtAsset The debt asset address
    /// @param lsa The Loan Smart Account address
    /// @return balance The variable debt token balance
    function _utilGetDebtBalance(address bitmorPool, address debtAsset, address lsa)
        internal
        view
        returns (uint256 balance)
    {
        DataTypes.ReserveData memory reserveData = ILendingPool(bitmorPool).getReserveData(debtAsset);
        balance = IERC20(reserveData.variableDebtTokenAddress).balanceOf(lsa);
    }

    /// @notice Get aToken balance for an account
    /// @param bitmorPool The Bitmor lending pool address
    /// @param collateralAsset The collateral asset address
    /// @param account The account to check
    /// @return balance The aToken balance
    function _utilGetATokenBalance(address bitmorPool, address collateralAsset, address account)
        internal
        view
        returns (uint256 balance)
    {
        DataTypes.ReserveData memory reserveData = ILendingPool(bitmorPool).getReserveData(collateralAsset);
        balance = IERC20(reserveData.aTokenAddress).balanceOf(account);
    }

    /// @notice Get underlying token balance
    /// @param token The token address
    /// @param account The account to check
    /// @return balance The token balance
    function _utilGetUnderlyingBalance(address token, address account) internal view returns (uint256 balance) {
        balance = IERC20(token).balanceOf(account);
    }

    /// @notice Get the aToken address for a given asset
    /// @param bitmorPool The Bitmor lending pool address
    /// @param asset The underlying asset address
    /// @return aToken The aToken address
    function _utilGetATokenAddress(address bitmorPool, address asset) internal view returns (address aToken) {
        DataTypes.ReserveData memory reserveData = ILendingPool(bitmorPool).getReserveData(asset);
        aToken = reserveData.aTokenAddress;
    }

    /// @notice Get the variable debt token address for a given asset
    /// @param bitmorPool The Bitmor lending pool address
    /// @param asset The underlying asset address
    /// @return variableDebtToken The variable debt token address
    function _utilGetVariableDebtTokenAddress(address bitmorPool, address asset)
        internal
        view
        returns (address variableDebtToken)
    {
        DataTypes.ReserveData memory reserveData = ILendingPool(bitmorPool).getReserveData(asset);
        variableDebtToken = reserveData.variableDebtTokenAddress;
    }

    /// @notice Get the liquidation bonus for a collateral asset (in bps)
    /// @param bitmorPool The Bitmor lending pool address
    /// @param collateralAsset The collateral asset address
    /// @return liquidationBonusBps The liquidation bonus in basis points (e.g., 10300 = 3% bonus)
    function _utilGetLiquidationBonus(address bitmorPool, address collateralAsset)
        internal
        view
        returns (uint256 liquidationBonusBps)
    {
        DataTypes.ReserveData memory reserveData = ILendingPool(bitmorPool).getReserveData(collateralAsset);
        // The liquidation bonus is stored in the configuration as percentage (e.g., 10300 = 103% = 3% bonus)
        // Decode liquidation bonus (Aave-style config packing): bits 32..47 (16 bits), in bps (e.g., 10300 = 3% bonus)
        liquidationBonusBps = (reserveData.configuration.data >> 32) & 0xFFFF;
    }

    // ============ 3) Oracle Helpers ============

    /// @notice Get Price Oracle address from AddressesProvider
    /// @param bitmorPool The Bitmor lending pool address
    /// @return oracle The price oracle address
    function _utilGetPriceOracle(address bitmorPool) internal view returns (address oracle) {
        address addressesProvider = address(ILendingPool(bitmorPool).getAddressesProvider());
        oracle = ILendingPoolAddressesProvider(addressesProvider).getPriceOracle();
    }

    /// @notice Mock the oracle price for an asset
    /// @param bitmorPool The Bitmor lending pool address
    /// @param asset The asset to mock price for
    /// @param newPrice The new price (8 decimals expected)
    function _utilSetOraclePrice(address bitmorPool, address asset, uint256 newPrice) internal {
        assertTrue(newPrice > 0, "INVALID_PRICE");
        address oracleAddress = _utilGetPriceOracle(bitmorPool);
        vm.mockCall(
            oracleAddress,
            abi.encodeWithSelector(IPriceOracleGetter.getAssetPrice.selector, asset),
            abi.encode(newPrice)
        );
    }

    /// @notice Drop oracle price by a percentage and mock the new price
    /// @param bitmorPool The Bitmor lending pool address
    /// @param asset The asset to drop price for
    /// @param dropPercent Percentage to drop (e.g., 15 = 15% drop)
    /// @return newPrice The newly mocked oracle price
    function _utilDropOraclePrice(address bitmorPool, address asset, uint256 dropPercent)
        internal
        returns (uint256 newPrice)
    {
        assertLe(dropPercent, 100, "DROP_TOO_HIGH");
        address oracleAddress = _utilGetPriceOracle(bitmorPool);

        uint256 currentPrice = IPriceOracleGetter(oracleAddress).getAssetPrice(asset);
        assertGt(currentPrice, 0, "INVALID_CURRENT_PRICE");

        newPrice = (currentPrice * (100 - dropPercent)) / 100;
        assertGt(newPrice, 0, "INVALID_NEW_PRICE");

        vm.mockCall(
            oracleAddress,
            abi.encodeWithSelector(IPriceOracleGetter.getAssetPrice.selector, asset),
            abi.encode(newPrice)
        );
    }

    /// @notice Get the current oracle price for an asset
    /// @param bitmorPool The Bitmor lending pool address
    /// @param asset The asset to get price for
    /// @return price The asset price (8 decimals)
    function _utilGetAssetPrice(address bitmorPool, address asset) internal view returns (uint256 price) {
        address oracleAddress = _utilGetPriceOracle(bitmorPool);
        price = IPriceOracleGetter(oracleAddress).getAssetPrice(asset);
    }

    // ============ 4) Time Warp Helpers ============

    /// @notice Warp time past the grace period to trigger liquidation eligibility
    /// @param gracePeriod The grace period in seconds
    function _utilWarpPastGracePeriod(uint256 gracePeriod) internal {
        uint256 timeToWarp = UTILITIES_LOAN_REPAYMENT_INTERVAL + gracePeriod + 1 days;
        vm.warp(block.timestamp + timeToWarp);
    }

    /// @notice Warp time past the loan repayment interval
    function _utilWarpPastRepaymentInterval() internal {
        vm.warp(block.timestamp + UTILITIES_LOAN_REPAYMENT_INTERVAL);
    }

    /// @notice Warp time by a specific number of seconds
    /// @param seconds_ Number of seconds to warp
    function _utilWarpBy(uint256 seconds_) internal {
        vm.warp(block.timestamp + seconds_);
    }

    /// @notice Warp time by a specific number of days
    /// @param days_ Number of days to warp
    function _utilWarpByDays(uint256 days_) internal {
        vm.warp(block.timestamp + (days_ * 1 days));
    }

    // ============ 5) Assertion Helpers ============

    /// @notice Assert LSA ownership invariants
    /// @param lsa The Loan Smart Account address
    /// @param expectedOwner Expected owner (typically the Loan contract)
    /// @param expectedBorrower Expected borrower
    function _utilAssertLSAOwnership(address lsa, address expectedOwner, address expectedBorrower) internal view {
        assertEq(ILoanVault(lsa).owner(), expectedOwner, "UNEXPECTED_LSA_OWNER");
        assertEq(ILoanVault(lsa).borrower(), expectedBorrower, "UNEXPECTED_LSA_BORROWER");
        assertTrue(ILoanVault(lsa).isInitialized(), "LSA_NOT_INITIALIZED");
    }

    // ============ 6) Liquidation Helpers ============

    /// @notice Fund liquidator with debt asset and approve spending
    /// @param liquidatorAddr The liquidator address
    /// @param debtAsset The debt asset address
    /// @param bitmorPool The Bitmor pool to approve
    /// @param amount Amount to mint
    function _utilFundLiquidator(address liquidatorAddr, address debtAsset, address bitmorPool, uint256 amount)
        internal
    {
        _utilMintTokenAndApproveMax(debtAsset, liquidatorAddr, bitmorPool, amount);
    }

    /// @notice Mint debt asset to liquidator WITHOUT approval (for testing revert cases)
    /// @param liquidatorAddr The liquidator address
    /// @param debtAsset The debt asset address
    /// @param amount Amount to mint
    function _utilMintToLiquidatorNoApproval(address liquidatorAddr, address debtAsset, uint256 amount) internal {
        _utilMintTokenTo(debtAsset, liquidatorAddr, amount);
    }

    /// @notice Execute micro liquidation
    /// @param bitmorPool The Bitmor lending pool address
    /// @param liquidatorAddr The liquidator address
    /// @param collateralAsset The collateral asset address
    /// @param debtAsset The debt asset address
    /// @param lsa The Loan Smart Account to liquidate
    function _utilExecuteMicroLiquidation(
        address bitmorPool,
        address liquidatorAddr,
        address collateralAsset,
        address debtAsset,
        address lsa
    ) internal {
        bytes memory liquidationData = abi.encode(collateralAsset, debtAsset, lsa);
        vm.prank(liquidatorAddr);
        ILendingPool(bitmorPool).microLiquidationCall(liquidationData);
    }

    /// @notice Execute full liquidation
    /// @param bitmorPool The Bitmor lending pool address
    /// @param liquidatorAddr The liquidator address
    /// @param collateralAsset The collateral asset address
    /// @param debtAsset The debt asset address
    /// @param lsa The Loan Smart Account to liquidate
    /// @param debtToCover Amount of debt to cover (use type(uint256).max for max)
    /// @param receiveAToken True to receive aTokens, false for underlying
    function _utilExecuteFullLiquidation(
        address bitmorPool,
        address liquidatorAddr,
        address collateralAsset,
        address debtAsset,
        address lsa,
        uint256 debtToCover,
        bool receiveAToken
    ) internal {
        vm.prank(liquidatorAddr);
        ILendingPool(bitmorPool).liquidationCall(collateralAsset, debtAsset, lsa, debtToCover, receiveAToken);
    }

    /// @notice Check liquidation type for an LSA
    /// @param bitmorPool The Bitmor lending pool address
    /// @param lsa The Loan Smart Account to check
    /// @return liquidationType 0=None, 1=Full, 2=Micro
    function _utilCheckLiquidationType(address bitmorPool, address lsa) internal returns (uint256 liquidationType) {
        liquidationType = ILendingPool(bitmorPool).checkTypeOfLiquidation(lsa);
    }

    /// @notice Calculate expected collateral to be seized given debt amount
    /// @param bitmorPool The Bitmor lending pool address
    /// @param collateralAsset The collateral asset address
    /// @param debtAsset The debt asset address
    /// @param debtAmount The debt amount being covered
    /// @return expectedCollateral The expected collateral amount (with liquidation bonus)
    function _utilCalculateExpectedCollateralSeized(
        address bitmorPool,
        address collateralAsset,
        address debtAsset,
        uint256 debtAmount
    ) internal view returns (uint256 expectedCollateral) {
        uint256 collateralPrice = _utilGetAssetPrice(bitmorPool, collateralAsset);
        uint256 debtPrice = _utilGetAssetPrice(bitmorPool, debtAsset);
        uint256 liquidationBonus = _utilGetLiquidationBonus(bitmorPool, collateralAsset);

        // Collateral decimals = 8 (BTC), Debt decimals = 6 (USDC)
        // Formula: (debtAmount * debtPrice * 10^collateralDecimals * liquidationBonus) / (collateralPrice * 10^debtDecimals * 10000)
        expectedCollateral = (debtAmount * debtPrice * 1e8 * liquidationBonus) / (collateralPrice * 1e6 * 10_000);
    }

    // ============ 7) AddressesProvider Helpers ============

    /// @notice Update AddressesProvider to point to test Loan contract
    /// @param bitmorPool The Bitmor lending pool address
    /// @param newLoanContract The new Loan contract address
    function _utilUpdateAddressesProviderBitmorLoan(address bitmorPool, address newLoanContract) internal {
        address addressesProvider = address(ILendingPool(bitmorPool).getAddressesProvider());
        address poolAdmin = ILendingPoolAddressesProvider(addressesProvider).getPoolAdmin();

        vm.prank(poolAdmin);
        ILendingPoolAddressesProvider(addressesProvider).setBitmorLoan(newLoanContract);

        // Verify update
        address updatedLoan = ILendingPoolAddressesProvider(addressesProvider).getBitmorLoan();
        assertEq(updatedLoan, newLoanContract, "ADDRESSES_PROVIDER_UPDATE_FAILED");
    }

    // ============ 8) Interest Rate Helpers ============

    /// @notice Get interest rate strategy parameters
    /// @param bitmorPool The Bitmor lending pool address
    /// @param debtAsset The debt asset address
    /// @return currentRate Current variable borrow rate in RAY
    /// @return baseRate Base variable borrow rate in RAY
    /// @return slope1 Variable rate slope 1 in RAY
    /// @return slope2 Variable rate slope 2 in RAY
    function _utilGetInterestRateParams(address bitmorPool, address debtAsset)
        internal
        view
        returns (uint256 currentRate, uint256 baseRate, uint256 slope1, uint256 slope2)
    {
        DataTypes.ReserveData memory reserveData = ILendingPool(bitmorPool).getReserveData(debtAsset);
        currentRate = reserveData.currentVariableBorrowRate;

        // Canonical Aave-style strategy interface from @bitmor/interfaces.
        IReserveInterestRateStrategy strategy = IReserveInterestRateStrategy(reserveData.interestRateStrategyAddress);
        baseRate = strategy.baseVariableBorrowRate();

        // Some strategies expose slope params as public getters, but these are not part of the canonical interface.
        // Pull them via staticcall to keep Utilities compatible across strategy implementations.
        (bool ok1, bytes memory ret1) =
            reserveData.interestRateStrategyAddress.staticcall(abi.encodeWithSignature("variableRateSlope1()"));
        if (ok1 && ret1.length >= 32) {
            slope1 = abi.decode(ret1, (uint256));
        }

        (bool ok2, bytes memory ret2) =
            reserveData.interestRateStrategyAddress.staticcall(abi.encodeWithSignature("variableRateSlope2()"));
        if (ok2 && ret2.length >= 32) {
            slope2 = abi.decode(ret2, (uint256));
        }
    }

    // ============ 9) Min Helper ============

    /// @notice Returns the minimum of two values
    /// @param a First value
    /// @param b Second value
    /// @return The smaller of the two values
    function _utilMin(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
}
