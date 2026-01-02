// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.6.12;

interface IUSDCVault {
    /**
     * @notice Returns the total amount of underlying assets held by the vault
     * @return Total assets managed by the vault (in vault + deployed to protocols)
     */
    function totalAssets() external view returns (uint256);

    /**
     * @notice Returns the underlying asset token address
     * @return Address of the underlying asset (USDC)
     */
    function asset() external view returns (address);

    function reallocateAssets(uint256 amountToWithdraw) external;
}
