// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.16;

/// @title IRewardController
/// @author webthethird
/// @notice Interface for the RewardController contract
interface IRewardController {
    /// @notice Emitted when a new reward token is added
    /// @param rewardToken Reward token address
    /// @param initialTimestamp Timestamp when reward token was added
    /// @param initialInflationRate Initial inflation rate for the reward token
    /// @param initialReductionFactor Initial reduction factor for the reward token
    event RewardTokenAdded(
        address indexed rewardToken,
        uint256 initialTimestamp,
        uint256 initialInflationRate,
        uint256 initialReductionFactor
    );

    /// @notice Emitted when governance removes a reward token
    /// @param rewardToken The reward token address
    /// @param unclaimedRewards The amount of reward tokens still claimable
    /// @param remainingBalance The remaining balance of the reward token, sent to governance
    event RewardTokenRemoved(address indexed rewardToken, uint256 unclaimedRewards, uint256 remainingBalance);

    /// @notice Emitted when a reward token is removed from a market's list of rewards
    /// @param market The market address
    /// @param rewardToken The reward token address
    event MarketRemovedFromRewards(address indexed market, address indexed rewardToken);

    /// @notice Emitted when the contract runs out of a reward token
    /// @param rewardToken The reward token address
    /// @param shortfallAmount The amount of reward tokens needed to fulfill all rewards
    event RewardTokenShortfall(address indexed rewardToken, uint256 shortfallAmount);

    /// @notice Emitted when a gauge weight is updated
    /// @param market The address of the perp market or staked token
    /// @param rewardToken The reward token address
    /// @param newWeight The new weight value
    event NewWeight(address indexed market, address indexed rewardToken, uint256 newWeight);

    /// @notice Emitted when a new inflation rate is set by governance
    /// @param newRate The new inflation rate
    event NewInitialInflationRate(address indexed rewardToken, uint256 newRate);

    /// @notice Emitted when a new reduction factor is set by governance
    /// @param newFactor The new reduction factor
    event NewReductionFactor(address indexed rewardToken, uint256 newFactor);

    /// @notice Error returned when trying to add a reward token if the max number of reward tokens has been reached
    /// @param max The maximum number of reward tokens allowed
    error RewardController_AboveMaxRewardTokens(uint256 max);

    /// @notice Error returned when trying to set the inflation rate to a value that is too high
    /// @param rate The value that was passed
    /// @param max The maximum allowed value
    error RewardController_AboveMaxInflationRate(uint256 rate, uint256 max);

    /// @notice Error returned when trying to set the reduction factor to a value that is too low
    /// @param factor The value that was passed
    /// @param min The minimum allowed value
    error RewardController_BelowMinReductionFactor(uint256 factor, uint256 min);

    /// @notice Error returned when passing an invalid reward token address to a function
    /// @param invalidAddress The address that was passed
    error RewardController_InvalidRewardTokenAddress(address invalidAddress);

    /// @notice Error returned when trying to set the reward weights with markets and weights arrays of different lengths
    /// @param actual The length of the weights array provided
    /// @param expected The length of the markets array provided
    error RewardController_IncorrectWeightsCount(uint256 actual, uint256 expected);

    /// @notice Error returned when the sum of the weights provided is not equal to 100% (in basis points)
    /// @param actual The sum of the weights provided
    /// @param expected The expected sum of the weights (i.e., 10000)
    error RewardController_IncorrectWeightsSum(uint256 actual, uint256 expected);

    /// @notice Error returned when one of the weights provided is greater than the maximum allowed weight (i.e., 100% in basis points)
    /// @param weight The weight that was passed
    /// @param max The maximum allowed weight (i.e., 10000)
    error RewardController_WeightExceedsMax(uint256 weight, uint256 max);

    /// @notice Gets the address of the reward token at the specified index in the array of reward tokens
    /// @param i The index of the reward token
    /// @return The address of the reward token
    function rewardTokens(uint256 i) external view returns (address);

    /// @notice Gets the number of reward tokens
    /// @return Number of reward tokens
    function getRewardTokenCount() external view returns (uint256);

    /// @notice Gets the timestamp when a reward token was registered
    /// @param rewardToken Address of the reward token
    /// @return Timestamp when the reward token was registered
    function getInitialTimestamp(address rewardToken) external view returns (uint256);

    /// @notice Gets the inflation rate of a reward token (w/o factoring in reduction factor)
    /// @param rewardToken Address of the reward token
    /// @return Initial inflation rate of the reward token
    function getInitialInflationRate(address rewardToken) external view returns (uint256);

    /// @notice Gets the current inflation rate of a reward token (factoring in reduction factor)
    /// @dev `inflationRate = initialInflationRate / reductionFactor^((block.timestamp - initialTimestamp) / secondsPerYear)`
    /// @param rewardToken Address of the reward token
    /// @return Current inflation rate of the reward token
    function getInflationRate(address rewardToken) external view returns (uint256);

    /// @notice Gets the reduction factor of a reward token
    /// @param rewardToken Address of the reward token
    /// @return Reduction factor of the reward token
    function getReductionFactor(address rewardToken) external view returns (uint256);

    /// @notice Gets the reward weight of a given market for a reward token
    /// @param rewardToken Address of the reward token
    /// @param market Address of the market
    /// @return The reward weight of the market in basis points
    function getRewardWeight(address rewardToken, address market) external view returns (uint256);

    /// @notice Gets the list of all markets receiving a given reward token
    /// @param rewardToken Address of the reward token
    /// @return List of market addresses
    function getRewardMarkets(address rewardToken) external view returns (address[] memory);

    /// @notice Gets whether a reward token is paused
    /// @param rewardToken Address of the reward token
    /// @return True if the reward token is paused, false otherwise
    function isTokenPaused(address rewardToken) external view returns (bool);

    /// @notice Sets the market addresses and reward weights for a reward token
    /// @param rewardToken Address of the reward token
    /// @param markets List of market addresses to receive rewards
    /// @param weights List of weights for each market
    function updateRewardWeights(address rewardToken, address[] calldata markets, uint256[] calldata weights)
        external;

    /// @notice Sets the initial inflation rate used to calculate emissions over time for a given reward token
    /// @dev Current inflation rate still factors in the reduction factor and time elapsed since the initial timestamp
    /// @param rewardToken Address of the reward token
    /// @param newInitialInflationRate The new inflation rate in tokens/year, scaled by 1e18
    function updateInitialInflationRate(address rewardToken, uint88 newInitialInflationRate) external;

    /// @notice Sets the reduction factor used to reduce emissions over time for a given reward token
    /// @param rewardToken Address of the reward token
    /// @param newReductionFactor The new reduction factor, scaled by 1e18
    function updateReductionFactor(address rewardToken, uint88 newReductionFactor) external;

    /// @notice Pause the contract
    function pause() external;

    /// @notice Unpause the contract
    function unpause() external;

    /// @notice Pauses/unpauses the reward accrual for a particular reward token
    /// @dev Does not pause gradual reduction of inflation rate over time due to reduction factor
    /// @param rewardToken Address of the reward token
    /// @param paused Whether to pause or unpause the reward token
    function setPaused(address rewardToken, bool paused) external;
}
