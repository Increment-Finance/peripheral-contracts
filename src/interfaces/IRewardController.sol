// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.16;

/// @title IRewardController
/// @author webthethird
/// @notice Interface for the RewardController contract
interface IRewardController {
    /// @notice Emitted when a new reward token is added
    /// @param rewardToken reward token address
    /// @param initialTimestamp timestamp when reward token was added
    /// @param initialInflationRate initial inflation rate for the reward token
    /// @param initialReductionFactor initial reduction factor for the reward token
    event RewardTokenAdded(
        address indexed rewardToken,
        uint256 initialTimestamp,
        uint256 initialInflationRate,
        uint256 initialReductionFactor
    );

    /// @notice Emitted when governance removes a reward token
    /// @param rewardToken the reward token address
    /// @param unclaimedRewards the amount of reward tokens still claimable
    /// @param remainingBalance the remaining balance of the reward token, sent to governance
    event RewardTokenRemoved(
        address indexed rewardToken,
        uint256 unclaimedRewards,
        uint256 remainingBalance
    );

    /// @notice Emitted when a reward token is removed from a market's list of rewards
    /// @param market the market address
    /// @param rewardToken the reward token address
    event MarketRemovedFromRewards(
        address indexed market,
        address indexed rewardToken
    );

    /// @notice Emitted when the contract runs out of a reward token
    /// @param rewardToken the reward token address
    /// @param shortfallAmount the amount of reward tokens needed to fulfill all rewards
    event RewardTokenShortfall(
        address indexed rewardToken,
        uint256 shortfallAmount
    );

    /// @notice Emitted when a gauge weight is updated
    /// @param market the address of the perp market or staked token
    /// @param rewardToken the reward token address
    /// @param newWeight the new weight value
    event NewWeight(
        address indexed market,
        address indexed rewardToken,
        uint16 newWeight
    );

    /// @notice Emitted when a new inflation rate is set by governance
    /// @param newRate the new inflation rate
    event NewInitialInflationRate(address indexed rewardToken, uint256 newRate);

    /// @notice Emitted when a new reduction factor is set by governance
    /// @param newFactor the new reduction factor
    event NewReductionFactor(address indexed rewardToken, uint256 newFactor);

    /// @notice Error returned when trying to add a reward token if the max number of reward tokens has been reached
    /// @param max the maximum number of reward tokens allowed
    error RewardController_AboveMaxRewardTokens(uint256 max);

    /// @notice Error returned when trying to set the inflation rate to a value that is too high
    /// @param rate the value that was passed
    /// @param max the maximum allowed value
    error RewardController_AboveMaxInflationRate(uint256 rate, uint256 max);

    /// @notice Error returned when trying to set the reduction factor to a value that is too low
    /// @param factor the value that was passed
    /// @param min the minimum allowed value
    error RewardController_BelowMinReductionFactor(uint256 factor, uint256 min);

    /// @notice Error returned when passing an invalid reward token address to a function
    /// @param invalidAddress the address that was passed
    error RewardController_InvalidRewardTokenAddress(address invalidAddress);

    /// @notice Error returned when a given market address has no reward weight stored in the RewardInfo for a given reward token
    /// @param market the market address
    /// @param rewardToken the reward token address
    error RewardController_MarketHasNoRewardWeight(
        address market,
        address rewardToken
    );

    /// @notice Error returned when trying to set the reward weights with markets and weights arrays of different lengths
    /// @param actual The length of the weights array provided
    /// @param expected The length of the markets array provided
    error RewardController_IncorrectWeightsCount(
        uint256 actual,
        uint256 expected
    );

    /// @notice Error returned when the sum of the weights provided is not equal to 100% (in basis points)
    /// @param actual The sum of the weights provided
    /// @param expected The expected sum of the weights (i.e., 10000)
    error RewardController_IncorrectWeightsSum(uint16 actual, uint16 expected);

    /// @notice Error returned when one of the weights provided is greater than the maximum allowed weight (i.e., 100% in basis points)
    /// @param weight The weight that was passed
    /// @param max The maximum allowed weight (i.e., 10000)
    error RewardController_WeightExceedsMax(uint16 weight, uint16 max);

    /// @notice Gets the address of the reward token at the specified index in the array of reward tokens for a given market
    /// @param market The market address
    /// @param i The index of the reward token
    /// @return The address of the reward token
    function rewardTokensPerMarket(
        address market,
        uint256 i
    ) external view returns (address);

    /// @notice Gets the number of markets to be used for reward distribution
    /// @dev Markets are the perpetual markets (for the PerpRewardDistributor) or staked tokens (for the SafetyModule)
    /// @return Number of markets
    function getNumMarkets() external view returns (uint256);

    /// @notice Gets the highest valid market index
    /// @return Highest valid market index
    function getMaxMarketIdx() external view returns (uint256);

    /// @notice Gets the address of a market at a given index
    /// @dev Markets are the perpetual markets (for the PerpRewardDistributor) or staked tokens (for the SafetyModule)
    /// @param idx Index of the market
    /// @return Address of the market
    function getMarketAddress(uint256 idx) external view returns (address);

    /// @notice Gets the index of an allowlisted market
    /// @dev Markets are the perpetual markets (for the PerpRewardDistributor) or staked tokens (for the SafetyModule)
    /// @param i Index of the market in the allowlist ClearingHouse.ids (for the PerpRewardDistributor) or stakingTokens (for the SafetyModule)
    /// @return Index of the market in the market list
    function getMarketIdx(uint256 i) external view returns (uint256);

    /// @notice Gets the index of the market in the rewardInfo.marketWeights array for a given reward token
    /// @dev Markets are the perpetual markets (for the PerpRewardDistributor) or staked tokens (for the SafetyModule)
    /// @param token Address of the reward token
    /// @param market Address of the market
    /// @return Index of the market in the rewardInfo.marketWeights array
    function getMarketWeightIdx(
        address token,
        address market
    ) external view returns (uint256);

    /// @notice Returns the current position of the user in the market (i.e., perpetual market or staked token)
    /// @param user Address of the user
    /// @param market Address of the market
    /// @return Current position of the user in the market
    function getCurrentPosition(
        address user,
        address market
    ) external view returns (uint256);

    /// @notice Gets the number of reward tokens for a given market
    /// @param market The market address
    /// @return Number of reward tokens for the market
    function getRewardTokenCount(
        address market
    ) external view returns (uint256);

    /// @notice Gets the timestamp when a reward token was registered
    /// @param rewardToken Address of the reward token
    /// @return Timestamp when the reward token was registered
    function getInitialTimestamp(
        address rewardToken
    ) external view returns (uint256);

    /// @notice Gets the inflation rate of a reward token (w/o factoring in reduction factor)
    /// @param rewardToken Address of the reward token
    /// @return Initial inflation rate of the reward token
    function getInitialInflationRate(
        address rewardToken
    ) external view returns (uint256);

    /// @notice Gets the current inflation rate of a reward token (factoring in reduction factor)
    /// @dev inflationRate = initialInflationRate / reductionFactor^((block.timestamp - initialTimestamp) / secondsPerYear)
    /// @param rewardToken Address of the reward token
    /// @return Current inflation rate of the reward token
    function getInflationRate(
        address rewardToken
    ) external view returns (uint256);

    /// @notice Gets the reduction factor of a reward token
    /// @param rewardToken Address of the reward token
    /// @return Reduction factor of the reward token
    function getReductionFactor(
        address rewardToken
    ) external view returns (uint256);

    /// @notice Gets the addresses and weights of all markets for a reward token
    /// @param rewardToken Address of the reward token
    /// @return List of market addresses and their corresponding weights
    function getRewardWeights(
        address rewardToken
    ) external view returns (address[] memory, uint16[] memory);

    /// @notice Updates the reward accumulator for a given market
    /// @dev Executes when any of the following variables are changed: inflationRate, marketWeights, liquidity
    /// @param market Address of the market
    function updateMarketRewards(address market) external;

    /// @notice Sets the market addresses and reward weights for a reward token
    /// @param rewardToken Address of the reward token
    /// @param markets List of market addresses to receive rewards
    /// @param weights List of weights for each market
    function updateRewardWeights(
        address rewardToken,
        address[] calldata markets,
        uint16[] calldata weights
    ) external;

    /// @notice Sets the initial inflation rate used to calculate emissions over time for a given reward token
    /// @dev Current inflation rate still factors in the reduction factor and time elapsed since the initial timestamp
    /// @param rewardToken Address of the reward token
    /// @param newInitialInflationRate The new inflation rate in INCR/year, scaled by 1e18
    function updateInitialInflationRate(
        address rewardToken,
        uint256 newInitialInflationRate
    ) external;

    /// @notice Sets the reduction factor used to reduce emissions over time for a given reward token
    /// @param rewardToken Address of the reward token
    /// @param newReductionFactor The new reduction factor, scaled by 1e18
    function updateReductionFactor(
        address rewardToken,
        uint256 newReductionFactor
    ) external;

    /// @notice Pauses/unpauses the reward accrual for a reward token
    /// @dev Does not pause gradual reduction of inflation rate over time due to reduction factor
    /// @param rewardToken Address of the reward token
    /// @param paused Whether to pause or unpause the reward token
    function setPaused(address rewardToken, bool paused) external;
}
