// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.30;

import {ERC20} from '../dependencies/openzeppelin/ERC20.sol';

/**
 * @title ERC20Mintable
 * @dev ERC20 minting logic
 */
contract MintableERC20 is ERC20 {
  uint8 immutable i_customDecimals;

  constructor(string memory name, string memory symbol, uint8 _decimals) ERC20(name, symbol) {
    i_customDecimals = _decimals;
  }

  function decimals() public view override returns (uint8) {
    return i_customDecimals;
  }

  /**
   * @dev Function to mint tokens
   * @param value The amount of tokens to mint.
   * @return A boolean that indicates if the operation was successful.
   */
  function mint(uint256 value) public returns (bool) {
    _mint(_msgSender(), value);
    return true;
  }
}

contract MockUSDC is MintableERC20 {
  constructor() MintableERC20('MOCK USDC', 'mockUSDC', 6) {}
}

contract MockCbBTC is MintableERC20 {
  constructor() MintableERC20('Mock cbBTC', 'mockCBBTC', 8) {}
}
