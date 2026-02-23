// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.30;

import {ERC20} from "@openzeppelin/token/ERC20/ERC20.sol";

/**
 * @title MintableERC20
 * @author Bitmor Protocol
 * @notice ERC20 token with unrestricted public minting for deployment and testing
 * @dev Used for deploying mock tokens (cbBTC, USDC) on testnets where real tokens are unavailable
 */
contract MintableERC20 is ERC20 {
    /// @notice Custom decimal precision for the token
    uint8 immutable i_customDecimals;

    /**
     * @notice Deploys the token with a custom name, symbol, and decimal precision
     * @param name The token name
     * @param symbol The token symbol
     * @param _decimals The number of decimals for token precision
     */
    constructor(string memory name, string memory symbol, uint8 _decimals) ERC20(name, symbol) {
        i_customDecimals = _decimals;
    }

    /// @notice Returns the custom decimal precision for this token.
    function decimals() public view override returns (uint8) {
        return i_customDecimals;
    }

    /**
     * @notice Mints `value` tokens to `to`
     * @param to The address to receive the minted tokens
     * @param value The amount of tokens to mint
     * @return True if the minting operation succeeded
     */
    function mint(address to, uint256 value) public returns (bool) {
        _mint(to, value);
        return true;
    }
}

/**
 * @title MockUSDC
 * @notice Mock USDC token with 6 decimals for testnet deployment
 */
contract MockUSDC is MintableERC20 {
    constructor() MintableERC20("MOCK USDC", "mockUSDC", 6) {}
}

/**
 * @title MockCbBTC
 * @notice Mock cbBTC token with 8 decimals for testnet deployment
 */
contract MockCbBTC is MintableERC20 {
    constructor() MintableERC20("Mock cbBTC", "mockCBBTC", 8) {}
}
