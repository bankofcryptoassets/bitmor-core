// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/// @title MockChainlinkOracle
/// @author Bitmor Protocol
/// @notice Mock Chainlink AggregatorV3Interface for testing oracle price feeds
/// @dev Supports `latestRoundData()`, `getRoundData()`, price updates, and staleness simulation.
///      Each call to `updateAnswer()` increments the round ID automatically.
contract MockChainlinkOracle {
    /// @notice Number of decimals for the price feed (e.g., 8 for USD pairs)
    uint8 public immutable DECIMALS;

    /// @notice Human-readable description of the price feed (e.g., "BTC / USD")
    string public description;

    /// @notice Chainlink aggregator version
    uint256 public constant VERSION = 3;

    /// @dev Latest price answer
    int256 private _latestAnswer;

    /// @dev Timestamp of the latest update
    uint256 private _latestTimestamp;

    /// @dev Latest round ID (auto-incremented on each update)
    uint80 private _latestRoundId;

    /// @dev Historical price answers by round ID
    mapping(uint80 => int256) private _answers;

    /// @dev Historical timestamps by round ID
    mapping(uint80 => uint256) private _timestamps;

    /// @notice Emitted when the oracle price is updated
    /// @param current The new price answer
    /// @param roundId The round ID for this update
    /// @param updatedAt Timestamp of the update
    event AnswerUpdated(int256 indexed current, uint256 indexed roundId, uint256 updatedAt);

    /// @notice Creates a new MockChainlinkOracle
    /// @param _decimals Number of decimals for the price feed
    /// @param _initialAnswer Initial price value
    /// @param _description Human-readable feed description
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

    /// @dev Internal helper to store a new answer, increment round ID, and emit event
    /// @param _answer The new price value
    function _updateAnswer(int256 _answer) internal {
        _latestRoundId++;
        _latestAnswer = _answer;
        _latestTimestamp = block.timestamp;
        _answers[_latestRoundId] = _answer;
        _timestamps[_latestRoundId] = block.timestamp;
        emit AnswerUpdated(_answer, _latestRoundId, block.timestamp);
    }
}
