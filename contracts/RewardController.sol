// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.16;

// contracts
import {Pausable} from "../lib/increment-protocol/lib/openzeppelin-contracts/contracts/security/Pausable.sol";
import {ReentrancyGuard} from
    "../lib/increment-protocol/lib/openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";
import {IncreAccessControl} from "../lib/increment-protocol/contracts/utils/IncreAccessControl.sol";

// interfaces
import {IERC20Metadata} from
    "../lib/increment-protocol/lib/openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IRewardController} from "./interfaces/IRewardController.sol";

// libraries
import {PRBMathUD60x18} from "../lib/increment-protocol/lib/prb-math/contracts/PRBMathUD60x18.sol";

/// @title RewardController
/// @author webthethird
/// @notice Base contract for storing and updating reward info for multiple reward tokens, each with
/// - a gradually decreasing emission rate, based on an initial inflation rate, reduction factor, and time elapsed
/// - a list of markets for which the reward token is distributed
/// - a list of weights representing the percentage of rewards that go to each market
abstract contract RewardController is IRewardController, IncreAccessControl, Pausable, ReentrancyGuard {
    using PRBMathUD60x18 for uint256;
    using PRBMathUD60x18 for uint88;

    /// @notice Data structure containing essential info for each reward token
    /// @param token Address of the reward token
    /// @param paused Whether the reward token accrual is paused
    /// @param initialTimestamp Time when the reward token was added
    /// @param initialInflationRate Initial rate of reward token emission per year
    /// @param reductionFactor Factor by which the inflation rate is reduced each year
    /// @param marketAddresses List of markets for which the reward token is distributed
    struct RewardInfo {
        IERC20Metadata token;
        bool paused;
        uint80 initialTimestamp;
        uint88 initialInflationRate;
        uint88 reductionFactor;
        address[] marketAddresses;
    }

    /// @notice Maximum inflation rate, applies to all reward tokens
    uint256 internal constant MAX_INFLATION_RATE = 5e24;

    /// @notice Minimum reduction factor, applies to all reward tokens
    uint256 internal constant MIN_REDUCTION_FACTOR = 1e18;

    /// @notice Maximum number of reward tokens allowed
    uint256 internal constant MAX_REWARD_TOKENS = 10;

    /// @notice 100% in basis points
    uint256 internal constant MAX_BASIS_POINTS = 10000;

    /// @notice List of reward token addresses
    /// @dev Length must be <= MAX_REWARD_TOKENS
    address[] public rewardTokens;

    /// @notice Info for each registered reward token
    mapping(address => RewardInfo) internal _rewardInfoByToken;

    /// @notice Mapping from reward token to reward weights for each market
    /// @dev Market reward weights are basis points, i.e., 100 = 1%, 10000 = 100%
    mapping(address => mapping(address => uint256)) internal _marketWeightsByToken;

    /* ******************* */
    /*  Reward Info Views  */
    /* ******************* */

    /// @inheritdoc IRewardController
    function getMaxInflationRate() external pure returns (uint256) {
        return MAX_INFLATION_RATE;
    }

    /// @inheritdoc IRewardController
    function getMinReductionFactor() external pure returns (uint256) {
        return MIN_REDUCTION_FACTOR;
    }

    /// @inheritdoc IRewardController
    function getMaxRewardTokens() external pure returns (uint256) {
        return MAX_REWARD_TOKENS;
    }

    /// @inheritdoc IRewardController
    function getRewardTokens() external view returns (address[] memory) {
        return rewardTokens;
    }

    /// @inheritdoc IRewardController
    function getRewardTokenCount() external view returns (uint256) {
        return rewardTokens.length;
    }

    /// @inheritdoc IRewardController
    function getInitialTimestamp(address rewardToken) external view returns (uint256) {
        return _rewardInfoByToken[rewardToken].initialTimestamp;
    }

    /// @inheritdoc IRewardController
    function getInitialInflationRate(address rewardToken) external view returns (uint256) {
        return _rewardInfoByToken[rewardToken].initialInflationRate;
    }

    /// @inheritdoc IRewardController
    function getInflationRate(address rewardToken) public view returns (uint256) {
        // The current annual inflation rate is a function of the initial rate, reduction factor and time elapsed
        uint256 totalTimeElapsed = block.timestamp - _rewardInfoByToken[rewardToken].initialTimestamp;
        return _rewardInfoByToken[rewardToken].initialInflationRate.div(
            _rewardInfoByToken[rewardToken].reductionFactor.pow(totalTimeElapsed.div(365 days))
        );
    }

    /// @inheritdoc IRewardController
    function getReductionFactor(address rewardToken) external view returns (uint256) {
        return _rewardInfoByToken[rewardToken].reductionFactor;
    }

    /// @inheritdoc IRewardController
    function getRewardWeight(address rewardToken, address market) external view returns (uint256) {
        return _marketWeightsByToken[rewardToken][market];
    }

    /// @inheritdoc IRewardController
    function getRewardMarkets(address rewardToken) external view returns (address[] memory) {
        return _rewardInfoByToken[rewardToken].marketAddresses;
    }

    /// @inheritdoc IRewardController
    function isTokenPaused(address rewardToken) external view returns (bool) {
        return _rewardInfoByToken[rewardToken].paused;
    }

    /* ****************** */
    /*     Governance     */
    /* ****************** */

    /// @inheritdoc IRewardController
    /// @dev Only callable by Governance
    function updateRewardWeights(address rewardToken, address[] calldata markets, uint256[] calldata weights)
        external
        onlyRole(GOVERNANCE)
    {
        if (rewardToken == address(0) || _rewardInfoByToken[rewardToken].token != IERC20Metadata(rewardToken)) {
            revert RewardController_InvalidRewardTokenAddress(rewardToken);
        }
        if (weights.length != markets.length) {
            revert RewardController_IncorrectWeightsCount(weights.length, markets.length);
        }
        // Accrue rewards for all currently rewarded markets before changing weights
        // Note: If `markets != _rewardInfoByToken[rewardToken].marketAddresses`, the list of markets receiving
        // this reward token will change, so while looping over the currently rewarded markets to accrue rewards,
        // we need to check each market to see if it's still in the new list, and if not, delete its reward weight.
        uint256 numOldMarkets = _rewardInfoByToken[rewardToken].marketAddresses.length;
        uint256 numNewMarkets = markets.length;
        for (uint256 i; i < numOldMarkets;) {
            address market = _rewardInfoByToken[rewardToken].marketAddresses[i];
            _updateMarketRewards(market);
            // Check if market is being removed from rewards
            bool found;
            for (uint256 j; j < numNewMarkets;) {
                if (markets[j] == market) {
                    found = true;
                    break;
                }
                unchecked {
                    ++j; // saves 63 gas per iteration
                }
            }
            // If market is not in the new list, delete its reward weight
            if (!found) {
                delete _marketWeightsByToken[rewardToken][market];
                emit MarketRemovedFromRewards(market, rewardToken);
            }
            unchecked {
                ++i; // saves 63 gas per iteration
            }
        }
        // Validate weights and accrue rewards for any newly added markets
        uint256 totalWeight;
        for (uint256 i; i < numNewMarkets;) {
            // This call should do nothing and return early if the market already accrued rewards above, but
            // if the market is new for this reward token, we may still need to accrue other reward tokens
            // and update `_timeOfLastCumRewardUpdate` for the new market.
            _updateMarketRewards(markets[i]);
            // Validate weight, given in basis points
            if (weights[i] > MAX_BASIS_POINTS) {
                revert RewardController_WeightExceedsMax(weights[i], MAX_BASIS_POINTS);
            }
            // Increment running total weight
            totalWeight += weights[i];
            // Update stored reward weight for the market for this reward token
            _marketWeightsByToken[rewardToken][markets[i]] = weights[i];
            emit NewWeight(markets[i], rewardToken, weights[i]);
            unchecked {
                ++i; // saves 63 gas per iteration
            }
        }
        // Validate that the total weight is 100%
        if (totalWeight != MAX_BASIS_POINTS) {
            revert RewardController_IncorrectWeightsSum(totalWeight, MAX_BASIS_POINTS);
        }
        // Replace stored lists of market addresses
        _rewardInfoByToken[rewardToken].marketAddresses = markets;
    }

    /// @inheritdoc IRewardController
    /// @dev Only callable by Governance
    function updateInitialInflationRate(address rewardToken, uint88 newInitialInflationRate)
        external
        onlyRole(GOVERNANCE)
    {
        if (rewardToken == address(0) || _rewardInfoByToken[rewardToken].token != IERC20Metadata(rewardToken)) {
            revert RewardController_InvalidRewardTokenAddress(rewardToken);
        }
        if (newInitialInflationRate > MAX_INFLATION_RATE) {
            revert RewardController_AboveMaxInflationRate(newInitialInflationRate, MAX_INFLATION_RATE);
        }
        // Accrue rewards for all currently rewarded markets before changing inflation rate
        uint256 numMarkets = _rewardInfoByToken[rewardToken].marketAddresses.length;
        for (uint256 i; i < numMarkets; ++i) {
            _updateMarketRewards(_rewardInfoByToken[rewardToken].marketAddresses[i]);
            unchecked {
                ++i; // saves 63 gas per iteration
            }
        }
        _rewardInfoByToken[rewardToken].initialInflationRate = newInitialInflationRate;
        emit NewInitialInflationRate(rewardToken, newInitialInflationRate);
    }

    /// @inheritdoc IRewardController
    /// @dev Only callable by Governance
    function updateReductionFactor(address rewardToken, uint88 newReductionFactor) external onlyRole(GOVERNANCE) {
        if (rewardToken == address(0) || _rewardInfoByToken[rewardToken].token != IERC20Metadata(rewardToken)) {
            revert RewardController_InvalidRewardTokenAddress(rewardToken);
        }
        if (MIN_REDUCTION_FACTOR > newReductionFactor) {
            revert RewardController_BelowMinReductionFactor(newReductionFactor, MIN_REDUCTION_FACTOR);
        }
        // Accrue rewards for all currently rewarded markets before changing reduction factor
        uint256 numMarkets = _rewardInfoByToken[rewardToken].marketAddresses.length;
        for (uint256 i; i < numMarkets;) {
            _updateMarketRewards(_rewardInfoByToken[rewardToken].marketAddresses[i]);
            unchecked {
                ++i; // saves 63 gas per iteration
            }
        }
        _rewardInfoByToken[rewardToken].reductionFactor = newReductionFactor;
        emit NewReductionFactor(rewardToken, newReductionFactor);
    }

    /* ****************** */
    /*   Emergency Admin  */
    /* ****************** */

    /// @inheritdoc IRewardController
    /// @dev Can only be called by Emergency Admin
    function pause() external virtual override onlyRole(EMERGENCY_ADMIN) {
        _pause();
    }

    /// @inheritdoc IRewardController
    /// @dev Can only be called by Emergency Admin
    function unpause() external virtual override onlyRole(EMERGENCY_ADMIN) {
        _unpause();
    }

    /// @inheritdoc IRewardController
    /// @dev Only callable by Emergency Admin
    function togglePausedReward(address _rewardToken) external virtual onlyRole(EMERGENCY_ADMIN) {
        _togglePausedReward(_rewardToken);
    }

    /* **************** */
    /*     Internal     */
    /* **************** */

    /// @notice Pauses/unpauses the reward accrual for a particular reward token
    /// @dev Does not pause gradual reduction of inflation rate over time due to reduction factor
    /// @param _rewardToken Address of the reward token
    function _togglePausedReward(address _rewardToken) internal {
        if (_rewardToken == address(0) || _rewardInfoByToken[_rewardToken].token != IERC20Metadata(_rewardToken)) {
            revert RewardController_InvalidRewardTokenAddress(_rewardToken);
        }
        // Accrue rewards to markets before pausing/unpausing accrual
        uint256 numMarkets = _rewardInfoByToken[_rewardToken].marketAddresses.length;
        for (uint256 i; i < numMarkets;) {
            // `_updateMarketRewards` will not accrue any paused reward tokens to the market, but
            // will update `_timeOfLastCumRewardUpdate` so rewards aren't accrued later for paused period
            _updateMarketRewards(_rewardInfoByToken[_rewardToken].marketAddresses[i]);
            unchecked {
                ++i; // saves 63 gas per iteration
            }
        }
        bool currentlyPaused = _rewardInfoByToken[_rewardToken].paused;
        _rewardInfoByToken[_rewardToken].paused = !currentlyPaused;
        if (currentlyPaused) {
            emit RewardTokenUnpaused(_rewardToken);
        } else {
            emit RewardTokenPaused(_rewardToken);
        }
    }

    /// @notice Updates the reward accumulators for a given market
    /// @dev Executes when any of the following values are changed:
    ///      - initial inflation rate per token,
    ///      - reduction factor per token,
    ///      - reward weights per market per token,
    ///      - liquidity in the market
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
    function _getCurrentPosition(address user, address market) internal view virtual returns (uint256);

    /// @notice Gets the address of a market at a given index
    /// @dev Markets are the perpetual markets (for the PerpRewardDistributor) or staked tokens (for the SafetyModule)
    /// @param idx Index of the market
    /// @return Address of the market
    function _getMarketAddress(uint256 idx) internal view virtual returns (address);

    /// @notice Gets the index of an allowlisted market
    /// @dev Markets are the perpetual markets (for the PerpRewardDistributor) or staked tokens (for the SafetyModule)
    /// @param i Index of the market in the allowlist `ClearingHouse.ids` (for the PerpRewardDistributor) or `stakingTokens` (for the SafetyModule)
    /// @return Index of the market in the market list
    function _getMarketIdx(uint256 i) internal view virtual returns (uint256);
}
