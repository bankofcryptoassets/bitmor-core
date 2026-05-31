// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/// @title ChainlinkOracleWrapper
/// @author Bitmor Protocol
/// @notice Testnet oracle wrapper: forwards to real Chainlink by default, allows public price overrides with optional TTL
/// @dev Implements the same interface as Chainlink AggregatorV3 so AaveOracle can use it as a drop-in source.
///      Both override and forwarded paths return `block.timestamp` as `updatedAt` to prevent AaveOracle
///      MAX_STALENESS (3600s) rejections.
contract ChainlinkOracleWrapper {
    /// @notice The underlying Chainlink price feed
    IChainlinkFeed public immutable CHAINLINK_FEED;

    /// @dev Override state
    struct PriceOverride {
        int256 price;
        uint256 expiresAt;
        bool active;
    }

    PriceOverride private _override;

    /// @dev Round ID counter for override rounds (starts at 1_000_000 to avoid collision with Chainlink rounds)
    uint80 private _overrideRoundId = 1_000_000;

    /// @notice Emitted when a price override is set
    /// @param price The override price
    /// @param expiresAt Expiry timestamp (0 = no expiry)
    event OverrideSet(int256 price, uint256 expiresAt);

    /// @notice Emitted when a price override is cleared
    event OverrideCleared();

    /// @notice Creates a new ChainlinkOracleWrapper
    /// @param chainlinkFeed Address of the real Chainlink aggregator to wrap
    constructor(address chainlinkFeed) {
        require(chainlinkFeed != address(0), "zero address");
        CHAINLINK_FEED = IChainlinkFeed(chainlinkFeed);
    }

    /// @notice Sets a price override with optional TTL
    /// @param price Override price (8 decimals for USD pairs)
    /// @param ttl Time-to-live in seconds. 0 = no expiry (stays until manually cleared)
    function setOverridePrice(int256 price, uint256 ttl) external {
        uint256 expiresAt = ttl == 0 ? 0 : block.timestamp + ttl;
        _override = PriceOverride({price: price, expiresAt: expiresAt, active: true});
        _overrideRoundId++;
        emit OverrideSet(price, expiresAt);
    }

    /// @notice Clears the active override, resuming live Chainlink prices
    function clearOverride() external {
        _override.active = false;
        emit OverrideCleared();
    }

    /// @notice Whether an override is currently active (set and not expired)
    function isOverrideActive() external view returns (bool) {
        return _isOverrideActive();
    }

    /// @notice Returns the latest round data
    /// @dev If override is active, returns override price with `block.timestamp` as `updatedAt`.
    ///      If no override, forwards to Chainlink but replaces `updatedAt` with `block.timestamp`
    ///      to prevent AaveOracle staleness rejection.
    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        if (_isOverrideActive()) {
            return (_overrideRoundId, _override.price, block.timestamp, block.timestamp, _overrideRoundId);
        }

        (uint80 clRoundId, int256 clAnswer,,,) = CHAINLINK_FEED.latestRoundData();
        return (clRoundId, clAnswer, block.timestamp, block.timestamp, clRoundId);
    }

    /// @notice Returns data for a specific historical round (forwards to Chainlink)
    /// @param _roundId The round ID to query
    function getRoundData(uint80 _roundId)
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return CHAINLINK_FEED.getRoundData(_roundId);
    }

    /// @notice Returns the number of decimals in the price feed
    function decimals() external view returns (uint8) {
        return CHAINLINK_FEED.decimals();
    }

    /// @notice Returns the description of the price feed
    function description() external view returns (string memory) {
        return CHAINLINK_FEED.description();
    }

    /// @notice Returns the aggregator version
    function version() external view returns (uint256) {
        return CHAINLINK_FEED.version();
    }

    /// @notice Returns the latest answer (legacy method)
    function latestAnswer() external view returns (int256) {
        if (_isOverrideActive()) {
            return _override.price;
        }
        (, int256 answer,,,) = CHAINLINK_FEED.latestRoundData();
        return answer;
    }

    /// @dev Checks if override is active and not expired
    function _isOverrideActive() internal view returns (bool) {
        if (!_override.active) return false;
        if (_override.expiresAt == 0) return true;
        return block.timestamp < _override.expiresAt;
    }
}

/// @dev Minimal interface for Chainlink AggregatorV3
interface IChainlinkFeed {
    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);

    function getRoundData(uint80 _roundId)
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);

    function decimals() external view returns (uint8);
    function description() external view returns (string memory);
    function version() external view returns (uint256);
}
