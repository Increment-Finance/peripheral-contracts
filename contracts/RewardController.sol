// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.16;

// contracts
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IncreAccessControl} from "increment-protocol/utils/IncreAccessControl.sol";

// interfaces
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IRewardController} from "./interfaces/IRewardController.sol";

// libraries
import {PRBMathUD60x18} from "prb-math/contracts/PRBMathUD60x18.sol";

/// @title RewardController
/// @author webthethird
/// @notice Base contract for storing and updating reward info for multiple reward tokens, each with
/// - a gradually decreasing emission rate, based on an initial inflation rate, reduction factor, and time elapsed
/// - a list of markets for which the reward token is distributed
/// - a list of weights representing the percentage of rewards that go to each market
abstract contract RewardController is
    IRewardController,
    IncreAccessControl,
    Pausable,
    ReentrancyGuard
{
    using PRBMathUD60x18 for uint256;
    using PRBMathUD60x18 for uint88;

    /// @notice Data structure containing essential info for each reward token
    /// @param token Address of the reward token
    /// @param paused Whether the reward token accrual is paused
    /// @param initialTimestamp Time when the reward token was added
    /// @param initialInflationRate Initial rate of reward token emission per year
    /// @param reductionFactor Factor by which the inflation rate is reduced each year
    /// @param marketAddresses List of markets for which the reward token is distributed
    /// @param marketWeights Market reward weights as basis points, i.e., 100 = 1%, 10000 = 100%
    struct RewardInfo {
        IERC20Metadata token;
        bool paused;
        uint80 initialTimestamp;
        uint88 initialInflationRate;
        uint88 reductionFactor;
        address[] marketAddresses;
        mapping(address => uint256) marketWeights;
    }

    /// @notice Maximum inflation rate, applies to all reward tokens
    uint256 public constant MAX_INFLATION_RATE = 5e24;

    /// @notice Minimum reduction factor, applies to all reward tokens
    uint256 public constant MIN_REDUCTION_FACTOR = 1e18;

    /// @notice Maximum number of reward tokens allowed
    uint256 public constant MAX_REWARD_TOKENS = 10;

    /// @notice List of reward token addresses
    /// @dev Length must be <= MAX_REWARD_TOKENS
    address[] public rewardTokens;

    /// @notice Info for each registered reward token
    mapping(address => RewardInfo) internal rewardInfoByToken;

    /* ******************* */
    /*  Reward Info Views  */
    /* ******************* */

    /// @inheritdoc IRewardController
    function getRewardTokenCount() external view returns (uint256) {
        return rewardTokens.length;
    }

    /// @inheritdoc IRewardController
    function getInitialTimestamp(
        address rewardToken
    ) external view returns (uint256) {
        return rewardInfoByToken[rewardToken].initialTimestamp;
    }

    /// @inheritdoc IRewardController
    function getInitialInflationRate(
        address rewardToken
    ) external view returns (uint256) {
        return rewardInfoByToken[rewardToken].initialInflationRate;
    }

    /// @inheritdoc IRewardController
    function getInflationRate(
        address rewardToken
    ) external view returns (uint256) {
        uint256 totalTimeElapsed = block.timestamp -
            rewardInfoByToken[rewardToken].initialTimestamp;
        return
            rewardInfoByToken[rewardToken].initialInflationRate.div(
                rewardInfoByToken[rewardToken].reductionFactor.pow(
                    totalTimeElapsed.div(365 days)
                )
            );
    }

    /// @inheritdoc IRewardController
    function getReductionFactor(
        address rewardToken
    ) external view returns (uint256) {
        return rewardInfoByToken[rewardToken].reductionFactor;
    }

    /// @inheritdoc IRewardController
    function getRewardWeight(
        address rewardToken,
        address market
    ) external view returns (uint256) {
        return rewardInfoByToken[rewardToken].marketWeights[market];
    }

    /// @inheritdoc IRewardController
    function isTokenPaused(address rewardToken) external view returns (bool) {
        return rewardInfoByToken[rewardToken].paused;
    }

    /* ****************** */
    /*     Governance     */
    /* ****************** */

    /// @inheritdoc IRewardController
    /// @dev Only callable by Governance
    function updateRewardWeights(
        address rewardToken,
        address[] calldata markets,
        uint256[] calldata weights
    ) external onlyRole(GOVERNANCE) {
        if (
            rewardToken == address(0) ||
            rewardInfoByToken[rewardToken].token != IERC20Metadata(rewardToken)
        ) revert RewardController_InvalidRewardTokenAddress(rewardToken);
        if (weights.length != markets.length)
            revert RewardController_IncorrectWeightsCount(
                weights.length,
                markets.length
            );
        // Update rewards for all currently rewarded markets before changing weights
        uint256 numOldMarkets = rewardInfoByToken[rewardToken]
            .marketAddresses
            .length;
        uint256 numNewMarkets = markets.length;
        for (uint i; i < numOldMarkets; ++i) {
            address market = rewardInfoByToken[rewardToken].marketAddresses[i];
            _updateMarketRewards(market);
            // Check if market is being removed from rewards
            bool found;
            for (uint j; j < numNewMarkets; ++j) {
                if (markets[j] == market) {
                    found = true;
                    break;
                }
            }
            if (!found) {
                delete rewardInfoByToken[rewardToken].marketWeights[market];
                emit MarketRemovedFromRewards(market, rewardToken);
            }
        }
        // Validate weights and update rewards for any newly added markets
        uint256 totalWeight;
        for (uint i; i < numNewMarkets; ++i) {
            _updateMarketRewards(markets[i]);
            if (weights[i] > 10000)
                revert RewardController_WeightExceedsMax(weights[i], 10000);
            totalWeight += weights[i];
            rewardInfoByToken[rewardToken].marketWeights[markets[i]] = weights[
                i
            ];
            emit NewWeight(markets[i], rewardToken, weights[i]);
        }
        if (totalWeight != 10000)
            revert RewardController_IncorrectWeightsSum(totalWeight, 10000);
        // Replace stored lists of market addresses and weights
        rewardInfoByToken[rewardToken].marketAddresses = markets;
    }

    /// @inheritdoc IRewardController
    /// @dev Only callable by Governance
    function updateInitialInflationRate(
        address rewardToken,
        uint88 newInitialInflationRate
    ) external onlyRole(GOVERNANCE) {
        if (
            rewardToken == address(0) ||
            rewardInfoByToken[rewardToken].token != IERC20Metadata(rewardToken)
        ) revert RewardController_InvalidRewardTokenAddress(rewardToken);
        if (newInitialInflationRate > MAX_INFLATION_RATE)
            revert RewardController_AboveMaxInflationRate(
                newInitialInflationRate,
                MAX_INFLATION_RATE
            );
        uint256 numMarkets = rewardInfoByToken[rewardToken]
            .marketAddresses
            .length;
        for (uint i; i < numMarkets; ++i) {
            _updateMarketRewards(
                rewardInfoByToken[rewardToken].marketAddresses[i]
            );
        }
        rewardInfoByToken[rewardToken]
            .initialInflationRate = newInitialInflationRate;
        emit NewInitialInflationRate(rewardToken, newInitialInflationRate);
    }

    /// @inheritdoc IRewardController
    /// @dev Only callable by Governance
    function updateReductionFactor(
        address rewardToken,
        uint88 newReductionFactor
    ) external onlyRole(GOVERNANCE) {
        if (
            rewardToken == address(0) ||
            rewardInfoByToken[rewardToken].token != IERC20Metadata(rewardToken)
        ) revert RewardController_InvalidRewardTokenAddress(rewardToken);
        if (MIN_REDUCTION_FACTOR > newReductionFactor)
            revert RewardController_BelowMinReductionFactor(
                newReductionFactor,
                MIN_REDUCTION_FACTOR
            );
        rewardInfoByToken[rewardToken].reductionFactor = newReductionFactor;
        emit NewReductionFactor(rewardToken, newReductionFactor);
    }

    /* ****************** */
    /*   Emergency Admin  */
    /* ****************** */

    /// @inheritdoc IRewardController
    /// @dev Can only be called by Emergency Admin
    function pause() external override onlyRole(EMERGENCY_ADMIN) {
        _pause();
    }

    /// @inheritdoc IRewardController
    /// @dev Can only be called by Emergency Admin
    function unpause() external override onlyRole(EMERGENCY_ADMIN) {
        _unpause();
    }

    /// @inheritdoc IRewardController
    /// @dev Only callable by Emergency Admin
    function setPaused(
        address rewardToken,
        bool paused
    ) external onlyRole(EMERGENCY_ADMIN) {
        if (
            rewardToken == address(0) ||
            rewardInfoByToken[rewardToken].token != IERC20Metadata(rewardToken)
        ) revert RewardController_InvalidRewardTokenAddress(rewardToken);
        if (rewardInfoByToken[rewardToken].paused == false) {
            // If not currently paused, accrue rewards before pausing
            uint256 numMarkets = rewardInfoByToken[rewardToken]
                .marketAddresses
                .length;
            for (uint i; i < numMarkets; ++i) {
                _updateMarketRewards(
                    rewardInfoByToken[rewardToken].marketAddresses[i]
                );
            }
        }
        rewardInfoByToken[rewardToken].paused = paused;
    }

    /* **************** */
    /*     Internal     */
    /* **************** */

    /// @notice Updates the reward accumulator for a given market
    /// @dev Executes when any of the following variables are changed: `inflationRate`, `marketWeights`, `liquidity`
    /// @param market Address of the market
    function _updateMarketRewards(address market) internal virtual;

    /// @notice Gets the number of markets to be used for reward distribution
    /// @dev Markets are the perpetual markets (for the PerpRewardDistributor) or staked tokens (for the SafetyModule)
    /// @return Number of markets
    function _getNumMarkets() internal view virtual returns (uint256);

    /// @notice Returns the current position of the user in the market (i.e., perpetual market or staked token)
    /// @param user Address of the user
    /// @param market Address of the market
    /// @return Current position of the user in the market
    function _getCurrentPosition(
        address user,
        address market
    ) internal view virtual returns (uint256);

    /// @notice Gets the address of a market at a given index
    /// @dev Markets are the perpetual markets (for the PerpRewardDistributor) or staked tokens (for the SafetyModule)
    /// @param idx Index of the market
    /// @return Address of the market
    function _getMarketAddress(
        uint256 idx
    ) internal view virtual returns (address);

    /// @notice Gets the index of an allowlisted market
    /// @dev Markets are the perpetual markets (for the PerpRewardDistributor) or staked tokens (for the SafetyModule)
    /// @param i Index of the market in the allowlist `ClearingHouse.ids` (for the PerpRewardDistributor) or `stakingTokens` (for the SafetyModule)
    /// @return Index of the market in the market list
    function _getMarketIdx(uint256 i) internal view virtual returns (uint256);
}
