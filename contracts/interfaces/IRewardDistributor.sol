// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.16;

// interfaces
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IPerpetual} from "increment-protocol/interfaces/IPerpetual.sol";

/// @title IRewardDistributor
/// @author webthethird
/// @notice Interface for the RewardDistributor contract
interface IRewardDistributor {
    /// @notice Emitted when rewards are accrued to a user
    /// @param user Address of the user
    /// @param rewardToken Address of the reward token
    /// @param market Address of the market
    /// @param reward Amount of reward accrued
    event RewardAccruedToUser(
        address indexed user,
        address rewardToken,
        address market,
        uint256 reward
    );

    /// @notice Emitted when rewards are accrued to a market
    /// @param market Address of the market
    /// @param rewardToken Address of the reward token
    /// @param reward Amount of reward accrued
    event RewardAccruedToMarket(
        address indexed market,
        address rewardToken,
        uint256 reward
    );

    /// @notice Emitted when a user claims their accrued rewards
    /// @param user Address of the user
    /// @param rewardToken Address of the reward token
    /// @param reward Amount of reward claimed
    event RewardClaimed(
        address indexed user,
        address rewardToken,
        uint256 reward
    );

    /// @notice Emitted when a user's position is changed in the reward distributor
    /// @param user Address of the user
    /// @param market Address of the market
    /// @param prevPosition Previous position of the user
    /// @param newPosition New position of the user
    event PositionUpdated(
        address indexed user,
        address market,
        uint256 prevPosition,
        uint256 newPosition
    );

    /// @notice Emitted when the address of the ecosystem reserve for storing reward tokens is updated
    /// @param prevEcosystemReserve Address of the previous ecosystem reserve
    /// @param newEcosystemReserve Address of the new ecosystem reserve
    event EcosystemReserveUpdated(
        address prevEcosystemReserve,
        address newEcosystemReserve
    );

    /// @notice Error returned when an invalid index is passed into `getMarketAddress`
    /// @param index Index that was passed
    /// @param maxIndex Maximum allowed index
    error RewardDistributor_InvalidMarketIndex(uint256 index, uint256 maxIndex);

    /// @notice Error returned when calling `viewNewRewardAccrual` with a market that has never accrued rewards
    /// @dev Occurs when `timeOfLastCumRewardUpdate[market] == 0`. This value is updated whenever
    /// `updateMarketRewards(market)` is called, which is quite often.
    /// @param market Address of the market
    error RewardDistributor_UninitializedStartTime(address market);

    /// @notice Error returned when calling `initMarketStartTime` with a market that already has a non-zero
    /// `timeOfLastCumRewardUpdate`
    /// @param market Address of the market
    error RewardDistributor_AlreadyInitializedStartTime(address market);

    /// @notice Error returned if a user calls `registerPositions` when the reward distributor has already
    /// stored their position for a market
    /// @param user Address of the user
    /// @param market Address of the market
    /// @param position Position of the user
    error RewardDistributor_PositionAlreadyRegistered(
        address user,
        address market,
        uint256 position
    );

    /// @notice Error returned when a user tries to manually accrue rewards before the early withdrawal
    /// penalty period is over
    /// @param user Address of the user
    /// @param market Address of the market
    /// @param claimAllowedTimestamp Timestamp when the early withdrawal penalty period is over
    error RewardDistributor_EarlyRewardAccrual(
        address user,
        address market,
        uint256 claimAllowedTimestamp
    );

    /// @notice Error returned if a user's position stored in the RewardDistributor does not match their current position in a given market
    /// @dev Only possible when the user had a pre-existing position in the market before the RewardDistributor
    /// was deployed, and has not called `registerPositions` yet
    /// @param user Address of the user
    /// @param market Address of the market
    /// @param storedPosition Position stored in the RewardDistributor
    /// @param actualPosition Current position of the user
    error RewardDistributor_UserPositionMismatch(
        address user,
        address market,
        uint256 storedPosition,
        uint256 actualPosition
    );

    /// @notice Error returned if governance tries to set the ecosystem reserve to the zero address
    /// @param invalidAddress Address that was passed (i.e., `address(0)`)
    error RewardDistributor_InvalidEcosystemReserve(address invalidAddress);

    /// @notice Gets the address of the reward token vault
    /// @return Address of the EcosystemReserve contract which serves as the reward token vault
    function ecosystemReserve() external view returns (address);

    /// @notice Rewards accrued and not yet claimed by user
    /// @param user Address of the user
    /// @param rewardToken Address of the reward token
    /// @return Rewards accrued and not yet claimed by user
    function rewardsAccruedByUser(
        address user,
        address rewardToken
    ) external view returns (uint256);

    /// @notice Total rewards accrued and not claimed by all users
    /// @param rewardToken Address of the reward token
    /// @return Total rewards accrued and not claimed by all users
    function totalUnclaimedRewards(
        address rewardToken
    ) external view returns (uint256);

    /// @notice Last timestamp when user withdrew liquidity from a market
    /// @param user Address of the user
    /// @param market Address of the market
    /// @return Timestamp when user last withdrew liquidity from the market
    function lastDepositTimeByUserByMarket(
        address user,
        address market
    ) external view returns (uint256);

    /// @notice Latest LP/staking positions per user and market
    /// @param user Address of the user
    /// @param market Address of the market
    /// @return Stored position of the user in the market
    function lpPositionsPerUser(
        address user,
        address market
    ) external view returns (uint256);

    /// @notice Reward accumulator for market rewards per reward token, as a number of reward tokens per
    /// LP/staked token
    /// @param rewardToken Address of the reward token
    /// @param market Address of the market
    /// @return Number of reward tokens per LP/staking token
    function cumulativeRewardPerLpToken(
        address rewardToken,
        address market
    ) external view returns (uint256);

    /// @notice Reward accumulator value per reward token when user rewards were last updated
    /// @param user Address of the user
    /// @param rewardToken Address of the reward token
    /// @param market Address of the market
    /// @return Number of reward tokens per Led token when user rewards were last updated
    function cumulativeRewardPerLpTokenPerUser(
        address user,
        address rewardToken,
        address market
    ) external view returns (uint256);

    /// @notice Gets the timestamp of the most recent update to the per-market reward accumulator
    /// @param market Address of the market
    /// @return Timestamp of the most recent update to the per-market reward accumulator
    function timeOfLastCumRewardUpdate(
        address market
    ) external view returns (uint256);

    /// @notice Total LP/staked tokens registered for rewards per market
    /// @param market Address of the market
    /// @return Stored total number of tokens per market
    function totalLiquidityPerMarket(
        address market
    ) external view returns (uint256);

    /// @notice Adds a new reward token
    /// @param _rewardToken Address of the reward token
    /// @param _initialInflationRate Initial inflation rate for the new token
    /// @param _initialReductionFactor Initial reduction factor for the new token
    /// @param _markets Addresses of the markets to reward with the new token
    /// @param _marketWeights Initial weights per market for the new token
    function addRewardToken(
        address _rewardToken,
        uint256 _initialInflationRate,
        uint256 _initialReductionFactor,
        address[] calldata _markets,
        uint16[] calldata _marketWeights
    ) external;

    /// @notice Removes a reward token from all markets for which it is registered
    /// @dev EcosystemReserve keeps the amount stored in `totalUnclaimedRewards[_rewardToken]` for users to
    /// claim later, and the RewardDistributor sends the rest to governance
    /// @param _rewardToken Address of the reward token to remove
    function removeRewardToken(address _rewardToken) external;

    /// @notice Updates the address of the ecosystem reserve for storing reward tokens
    /// @param _ecosystemReserve Address of the new ecosystem reserve
    function setEcosystemReserve(address _ecosystemReserve) external;

    /// @notice Sets the start time for accruing rewards to a market which has not been initialized yet
    /// @param _market Address of the market (i.e., perpetual market or staking token)
    function initMarketStartTime(address _market) external;

    /// @notice Fetches and stores the caller's LP/stake positions and updates the total liquidity in each market
    /// @dev Can only be called once per user, only necessary if user was an LP/staker prior to this contract's deployment
    function registerPositions() external;

    /// @notice Fetches and stores the caller's LP/stake positions and updates the total liquidity in each of the
    /// provided markets
    /// @dev Can only be called once per user, only necessary if user was an LP prior to this contract's deployment
    /// @param _markets Addresses of the markets to sync with
    function registerPositions(address[] calldata _markets) external;

    /// @notice Accrues and then distributes rewards for all markets to the caller
    function claimRewards() external;

    /// @notice Accrues and then distributes rewards for all markets and reward tokens
    /// and returns the amount of rewards that were not distributed to the given user
    /// @param _user Address of the user to claim rewards for
    function claimRewardsFor(address _user) external;

    /// @notice Accrues and then distributes rewards for all markets that receive any of the provided reward tokens
    /// to the given user
    /// @param _user Address of the user to claim rewards for
    /// @param _rewardTokens Addresses of the reward tokens to claim rewards for
    function claimRewardsFor(
        address _user,
        address[] memory _rewardTokens
    ) external;

    /// @notice Accrues rewards to a user for all markets
    /// @dev Assumes user's position hasn't changed since last accrual, since updating rewards due to changes
    /// in position is handled by `updateStakingPosition`
    /// @param user Address of the user to accrue rewards for
    function accrueRewards(address user) external;

    /// @notice Accrues rewards to a user for a given market
    /// @dev Assumes user's position hasn't changed since last accrual, since updating rewards due to changes in
    /// position is handled by `updateStakingPosition`
    /// @param market Address of the market to accrue rewards for
    /// @param user Address of the user
    function accrueRewards(address market, address user) external;

    /// @notice Returns the amount of rewards that would be accrued to a user for a given market
    /// @dev Serves as a static version of `accrueRewards(address market, address user)`
    /// @param market Address of the market to view new rewards for
    /// @param user Address of the user
    /// @return Amount of new rewards that would be accrued to the user for each reward token the given market receives
    function viewNewRewardAccrual(
        address market,
        address user
    ) external view returns (uint256[] memory);

    /// @notice Returns the amount of rewards that would be accrued to a user for a given market and reward token
    /// @param market Address of the market to view new rewards for
    /// @param user Address of the user
    /// @param rewardToken Address of the reward token to view new rewards for
    /// @return Amount of new rewards that would be accrued to the user
    function viewNewRewardAccrual(
        address market,
        address user,
        address rewardToken
    ) external view returns (uint256);
}
