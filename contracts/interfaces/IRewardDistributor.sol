// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.16;

// interfaces
import {IERC20Metadata} from
    "../../lib/increment-protocol/lib/openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IPerpetual} from "../../lib/increment-protocol/contracts/interfaces/IPerpetual.sol";
import {IRewardContract} from "../../lib/increment-protocol/contracts/interfaces/IRewardContract.sol";

/// @title IRewardDistributor
/// @author webthethird
/// @notice Interface for the RewardDistributor contract
interface IRewardDistributor is IRewardContract {
    /* ****************** */
    /*       Events       */
    /* ****************** */

    /// @notice Emitted when rewards are accrued to a user
    /// @param user Address of the user
    /// @param rewardToken Address of the reward token
    /// @param market Address of the market
    /// @param reward Amount of reward accrued
    event RewardAccruedToUser(address indexed user, address rewardToken, address market, uint256 reward);

    /// @notice Emitted when rewards are accrued to a market
    /// @param market Address of the market
    /// @param rewardToken Address of the reward token
    /// @param reward Amount of reward accrued
    event RewardAccruedToMarket(address indexed market, address rewardToken, uint256 reward);

    /// @notice Emitted when a user claims their accrued rewards
    /// @param user Address of the user
    /// @param rewardToken Address of the reward token
    /// @param reward Amount of reward claimed
    event RewardClaimed(address indexed user, address rewardToken, uint256 reward);

    /// @notice Emitted when a user's position is changed in the reward distributor
    /// @param user Address of the user
    /// @param market Address of the market
    /// @param prevPosition Previous position of the user
    /// @param newPosition New position of the user
    event PositionUpdated(address indexed user, address market, uint256 prevPosition, uint256 newPosition);

    /* ****************** */
    /*       Errors       */
    /* ****************** */

    /// @notice Error returned when calling `viewNewRewardAccrual` with a market that has never accrued rewards
    /// @dev Occurs when `timeOfLastCumRewardUpdate[market] == 0`. This value is updated whenever
    /// `_updateMarketRewards(market)` is called, which is quite often.
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
    error RewardDistributor_PositionAlreadyRegistered(address user, address market, uint256 position);

    /// @notice Error returned if a user's position stored in the RewardDistributor does not match their current position in a given market
    /// @dev Only possible when the user had a pre-existing position in the market before the RewardDistributor
    /// was deployed, and has not called `registerPositions` yet
    /// @param user Address of the user
    /// @param market Address of the market
    /// @param storedPosition Position stored in the RewardDistributor
    /// @param actualPosition Current position of the user
    error RewardDistributor_UserPositionMismatch(
        address user, address market, uint256 storedPosition, uint256 actualPosition
    );

    /// @notice Error returned when the zero address is passed to a function that expects a non-zero address
    error RewardDistributor_InvalidZeroAddress();

    /* ******************* */
    /*     Public Vars     */
    /* ******************* */

    /// @notice Gets the address of the reward token vault
    /// @return Address of the EcosystemReserve contract which serves as the reward token vault
    function ecosystemReserve() external view returns (address);

    /* ****************** */
    /*   External Views   */
    /* ****************** */

    /// @notice Rewards accrued and not yet claimed by user
    /// @param _user Address of the user
    /// @param _rewardToken Address of the reward token
    /// @return Rewards accrued and not yet claimed by user
    function rewardsAccruedByUser(address _user, address _rewardToken) external view returns (uint256);

    /// @notice Total rewards accrued and not claimed by all users
    /// @param _rewardToken Address of the reward token
    /// @return Total rewards accrued and not claimed by all users
    function totalUnclaimedRewards(address _rewardToken) external view returns (uint256);

    /// @notice Latest LP/staking positions per user and market
    /// @param _user Address of the user
    /// @param _market Address of the market
    /// @return Stored position of the user in the market
    function lpPositionsPerUser(address _user, address _market) external view returns (uint256);

    /// @notice Reward accumulator for market rewards per reward token, as a number of reward tokens per
    /// LP/staked token
    /// @param _rewardToken Address of the reward token
    /// @param _market Address of the market
    /// @return Number of reward tokens per LP/staking token
    function cumulativeRewardPerLpToken(address _rewardToken, address _market) external view returns (uint256);

    /// @notice Reward accumulator value per reward token when user rewards were last updated
    /// @param _user Address of the user
    /// @param _rewardToken Address of the reward token
    /// @param _market Address of the market
    /// @return Number of reward tokens per Led token when user rewards were last updated
    function cumulativeRewardPerLpTokenPerUser(address _user, address _rewardToken, address _market)
        external
        view
        returns (uint256);

    /// @notice Gets the timestamp of the most recent update to the per-market reward accumulator
    /// @param _market Address of the market
    /// @return Timestamp of the most recent update to the per-market reward accumulator
    function timeOfLastCumRewardUpdate(address _market) external view returns (uint256);

    /// @notice Total LP/staked tokens registered for rewards per market
    /// @param _market Address of the market
    /// @return Stored total number of tokens per market
    function totalLiquidityPerMarket(address _market) external view returns (uint256);

    /* ****************** */
    /*     Governance     */
    /* ****************** */

    /// @notice Adds a new reward token
    /// @param _rewardToken Address of the reward token
    /// @param _initialInflationRate Initial inflation rate for the new token
    /// @param _initialReductionFactor Initial reduction factor for the new token
    /// @param _markets Addresses of the markets to reward with the new token
    /// @param _marketWeights Initial weights per market for the new token
    function addRewardToken(
        address _rewardToken,
        uint88 _initialInflationRate,
        uint88 _initialReductionFactor,
        address[] calldata _markets,
        uint256[] calldata _marketWeights
    ) external;

    /// @notice Removes a reward token from all markets for which it is registered
    /// @dev EcosystemReserve keeps the amount stored in `totalUnclaimedRewards[_rewardToken]` for users to
    /// claim later, and the RewardDistributor sends the rest to governance
    /// @param _rewardToken Address of the reward token to remove
    function removeRewardToken(address _rewardToken) external;

    /// @notice Sets the start time for accruing rewards to a market which has not been initialized yet
    /// @param _market Address of the market (i.e., perpetual market or staking token)
    function initMarketStartTime(address _market) external;

    /* ****************** */
    /*   External Users   */
    /* ****************** */

    /// @notice Fetches and stores the caller's LP/stake positions and updates the total liquidity in each of the
    /// provided markets
    /// @dev Can only be called once per user, only necessary if user was an LP prior to this contract's deployment
    /// @param _markets Addresses of the markets to sync with
    function registerPositions(address[] calldata _markets) external;

    /// @notice Accrues and then distributes rewards for all markets and reward tokens
    /// and returns the amount of rewards that were not distributed to the given user
    /// @param _user Address of the user to claim rewards for
    function claimRewardsFor(address _user) external;

    /// @notice Accrues and then distributes rewards for all markets that receive any of the provided reward tokens
    /// to the given user
    /// @param _user Address of the user to claim rewards for
    /// @param _rewardTokens Addresses of the reward tokens to claim rewards for
    function claimRewardsFor(address _user, address[] memory _rewardTokens) external;
}
