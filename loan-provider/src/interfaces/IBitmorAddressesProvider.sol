// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/**
 * @title IBitmorAddressesProvider
 * @author Bitmor Protocol
 * @notice Registry of protocol-level addresses used by the Loan Provider
 * @dev Stores addresses for vault factory, swapper, fee collectors, and auto repayer.
 *      All setters are access-controlled via `AccessManaged`.
 * @custom:security-contact see https://bitmor.com/security
 */
interface IBitmorAddressesProvider {
    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Emitted when the vault factory address is updated
     * @param vaultFactory The new vault factory address
     */
    event BitmorAddressesProvider__VaultFactoryUpdated(address indexed vaultFactory);

    /**
     * @notice Emitted when the swapper address is updated
     * @param swapper The new swapper address
     */
    event BitmorAddressesProvider__SwapperUpdated(address indexed swapper);

    /**
     * @notice Emitted when the premium collector address is updated
     * @param premiumCollector The new premium collector address
     */
    event BitmorAddressesProvider__PremiumCollectorUpdated(address indexed premiumCollector);

    /**
     * @notice Emitted when the liquidation fee collector address is updated
     * @param liquidationFeeCollector The new liquidation fee collector address
     */
    event BitmorAddressesProvider__LiquidationFeeCollectorUpdated(address indexed liquidationFeeCollector);

    /**
     * @notice Emitted when the auto repayer address is updated
     * @param autoRepayer The new auto repayer address
     */
    event BitmorAddressesProvider__AutoRepayerUpdated(address indexed autoRepayer);

    /*//////////////////////////////////////////////////////////////
                        USER-FACING STATE-CHANGING
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Sets the vault factory address
     * @param _vaultFactory The new vault factory address
     * @custom:access Restricted via AccessManaged
     */
    function setVaultFactory(address _vaultFactory) external;

    /**
     * @notice Sets the swapper address
     * @param _swapper The new swapper address
     * @custom:access Restricted via AccessManaged
     */
    function setSwapper(address _swapper) external;

    /**
     * @notice Sets the premium collector address
     * @param _premiumCollector The new premium collector address
     * @custom:access Restricted via AccessManaged
     */
    function setPremiumCollector(address _premiumCollector) external;

    /**
     * @notice Sets the liquidation fee collector address
     * @param _liquidationFeeCollector The new liquidation fee collector address
     * @custom:access Restricted via AccessManaged
     */
    function setLiquidationFeeCollector(address _liquidationFeeCollector) external;

    /**
     * @notice Sets the auto repayer address
     * @param _autoRepayer The new auto repayer address
     * @custom:access Restricted via AccessManaged
     */
    function setAutoRepayer(address _autoRepayer) external;

    /*//////////////////////////////////////////////////////////////
                          USER-FACING READ-ONLY
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns the immutable Loan Provider address set at construction
    function i_LOAN_PROVIDER() external view returns (address);

    /**
     * @notice Returns the vault factory address
     * @return loanVaultFactory The current vault factory address
     */
    function getLoanVaultFactory() external view returns (address loanVaultFactory);

    /**
     * @notice Returns the swapper address
     * @return swapper The current swapper address
     */
    function getSwapper() external view returns (address swapper);

    /**
     * @notice Returns the premium collector address
     * @return premiumCollector The current premium collector address
     */
    function getPremiumCollector() external view returns (address premiumCollector);

    /**
     * @notice Returns the liquidation fee collector address
     * @return liquidationFeeCollector The current liquidation fee collector address
     */
    function getLiquidationFeeCollector() external view returns (address liquidationFeeCollector);

    /**
     * @notice Returns the auto repayer address
     * @return autoRepayer The current auto repayer address
     */
    function getAutoRepayer() external view returns (address autoRepayer);
}
