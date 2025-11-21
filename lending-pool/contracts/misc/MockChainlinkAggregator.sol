// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.6.12;

import {IChainlinkAggregator} from '../interfaces/IChainlinkAggregator.sol';

contract MockChainlinkAggregator is IChainlinkAggregator {
  int256 private _price;
  uint8 private _decimals;
  uint256 private _timestamp;
  uint256 private _round;

  constructor(int256 price_, uint8 decimals_) public {
    _price = price_;
    _decimals = decimals_;
    _timestamp = block.timestamp;
    _round = 1;
  }

  function latestAnswer() external view override returns (int256) {
    return _price;
  }

  function decimals() external view override returns (uint8) {
    return _decimals;
  }

  function latestTimestamp() external view override returns (uint256) {
    return _timestamp;
  }

  function latestRound() external view override returns (uint256) {
    return _round;
  }

  function getAnswer(uint256) external view override returns (int256) {
    return _price;
  }

  function getTimestamp(uint256) external view override returns (uint256) {
    return _timestamp;
  }

  function setPrice(int256 newPrice) external {
    _price = newPrice;
    _timestamp = block.timestamp;
    _round++;
  }
}
