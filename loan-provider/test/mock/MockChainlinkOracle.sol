// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/// @title MockChainlinkOracle
/// @notice Mock Chainlink AggregatorV3Interface for testing
/// @dev Implements latestRoundData() and getRoundData() for oracle price feeds
contract MockChainlinkOracle {
    uint8 public immutable DECIMALS;
    string public description;
    uint256 public constant VERSION = 3;

    int256 private _latestAnswer;
    uint256 private _latestTimestamp;
    uint80 private _latestRoundId;

    mapping(uint80 => int256) private _answers;
    mapping(uint80 => uint256) private _timestamps;

    event AnswerUpdated(int256 indexed current, uint256 indexed roundId, uint256 updatedAt);

    constructor(uint8 _decimals, int256 _initialAnswer, string memory _description) {
        DECIMALS = _decimals;
        description = _description;
        _updateAnswer(_initialAnswer);
    }

    /// @notice Updates the oracle price
    /// @param _answer New price value
    function updateAnswer(int256 _answer) external {
        _updateAnswer(_answer);
    }

    /// @notice Makes the oracle data stale for testing staleness checks
    /// @param secondsOld How many seconds in the past to set the timestamp
    function makeStale(uint256 secondsOld) external {
        _latestTimestamp = block.timestamp - secondsOld;
        _timestamps[_latestRoundId] = _latestTimestamp;
    }

    /// @notice Returns the latest round data (Chainlink AggregatorV3Interface)
    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return (_latestRoundId, _latestAnswer, _latestTimestamp, _latestTimestamp, _latestRoundId);
    }

    /// @notice Returns data for a specific round
    function getRoundData(uint80 _roundId)
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return (_roundId, _answers[_roundId], _timestamps[_roundId], _timestamps[_roundId], _roundId);
    }

    /// @notice Returns the latest answer (legacy method)
    function latestAnswer() external view returns (int256) {
        return _latestAnswer;
    }

    /// @notice Returns decimals for the price feed
    function decimals() external view returns (uint8) {
        return DECIMALS;
    }

    function _updateAnswer(int256 _answer) internal {
        _latestRoundId++;
        _latestAnswer = _answer;
        _latestTimestamp = block.timestamp;
        _answers[_latestRoundId] = _answer;
        _timestamps[_latestRoundId] = block.timestamp;
        emit AnswerUpdated(_answer, _latestRoundId, block.timestamp);
    }
}
