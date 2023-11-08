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

abstract contract RewardController is
    IRewardController,
    IncreAccessControl,
    Pausable,
    ReentrancyGuard
{
    using PRBMathUD60x18 for uint256;

    /// @notice Data structure containing essential info for each reward token
    struct RewardInfo {
        IERC20Metadata token; // Address of the reward token
        bool paused; // Whether the reward token accrual is paused
        uint256 initialTimestamp; // Time when the reward token was added
        uint256 initialInflationRate; // Amount of reward token emitted per year
        uint256 reductionFactor; // Factor by which the inflation rate is reduced each year
        address[] marketAddresses; // List of markets for which the reward token is distributed
        uint16[] marketWeights; // Weights are basis points, i.e., 100 = 1%, 10000 = 100%
    }

    /// @notice Maximum inflation rate, applies to all reward tokens
    uint256 public constant MAX_INFLATION_RATE = 5e24;

    /// @notice Minimum reduction factor, applies to all reward tokens
    uint256 public constant MIN_REDUCTION_FACTOR = 1e18;

    /// @notice Maximum number of reward tokens supported
    uint256 public constant MAX_REWARD_TOKENS = 10;

    /// @notice List of reward token addresses
    /// @dev Length must be <= maxRewardTokens
    mapping(address => address[]) public rewardTokensPerMarket;

    /// @notice Info for each registered reward token
    mapping(address => RewardInfo) public rewardInfoByToken;

    /* ****************** */
    /*      Abstract      */
    /* ****************** */

    /// Updates the reward accumulator for a given market
    /// @dev Executes when any of the following variables are changed: inflationRate, marketWeights, liquidity
    /// @param market Address of the market
    function updateMarketRewards(address market) public virtual;

    /// Gets the number of markets to be used for reward distribution
    /// @dev Markets are the perpetual markets (for the PerpRewardDistributor) or staked tokens (for the SafetyModule)
    /// @return Number of markets
    function getNumMarkets() public view virtual returns (uint256);

    /// Gets the highest valid market index
    /// @return Highest valid market index
    function getMaxMarketIdx() public view virtual returns (uint256);

    /// Gets the address of a market
    /// @dev Markets are the perpetual markets (for the PerpRewardDistributor) or staked tokens (for the SafetyModule)
    /// @param idx Index of the market
    /// @return Address of the market
    function getMarketAddress(
        uint256 idx
    ) public view virtual returns (address);

    /// Gets the index of an allowlisted market
    /// @dev Markets are the perpetual markets (for the PerpRewardDistributor) or staked tokens (for the SafetyModule)
    /// @param i Index of the market in the allowlist ids
    /// @return Index of the market in the market list
    function getMarketIdx(uint256 i) public view virtual returns (uint256);

    /// Gets the index of the market in the rewardInfo.marketWeights array for a given reward token
    /// @dev Markets are the perpetual markets (for the PerpRewardDistributor) or staked tokens (for the SafetyModule)
    /// @param token Address of the reward token
    /// @param market Address of the market
    /// @return Index of the market in the rewardInfo.marketWeights array
    function getMarketWeightIdx(
        address token,
        address market
    ) public view virtual returns (uint256);

    /* ******************* */
    /*  Reward Info Views  */
    /* ******************* */

    /// Gets the number of reward tokens
    function getRewardTokenCount(
        address market
    ) external view returns (uint256) {
        return rewardTokensPerMarket[market].length;
    }

    /// Gets the timestamp when a reward token was registered
    /// @param rewardToken Address of the reward token
    function getInitialTimestamp(
        address rewardToken
    ) external view returns (uint256) {
        return rewardInfoByToken[rewardToken].initialTimestamp;
    }

    /// Gets the inflation rate of a reward token (w/o factoring in reduction factor)
    /// @param rewardToken Address of the reward token
    function getInitialInflationRate(
        address rewardToken
    ) external view returns (uint256) {
        return rewardInfoByToken[rewardToken].initialInflationRate;
    }

    /// Gets the current inflation rate of a reward token (factoring in reduction factor)
    /// @notice inflationRate = initialInflationRate / reductionFactor^((block.timestamp - initialTimestamp) / secondsPerYear)
    /// @param rewardToken Address of the reward token
    function getInflationRate(
        address rewardToken
    ) external view returns (uint256) {
        RewardInfo memory rewardInfo = rewardInfoByToken[rewardToken];
        uint256 totalTimeElapsed = block.timestamp -
            rewardInfo.initialTimestamp;
        return
            rewardInfo.initialInflationRate.div(
                rewardInfo.reductionFactor.pow(totalTimeElapsed.div(365 days))
            );
    }

    /// Gets the reduction factor of a reward token
    /// @param rewardToken Address of the reward token
    function getReductionFactor(
        address rewardToken
    ) external view returns (uint256) {
        return rewardInfoByToken[rewardToken].reductionFactor;
    }

    /// Gets the weights of all markets for a reward token
    /// @param rewardToken Address of the reward token
    /// @return List of market addresses and their corresponding weights
    function getRewardWeights(
        address rewardToken
    ) external view returns (address[] memory, uint16[] memory) {
        return (
            rewardInfoByToken[rewardToken].marketAddresses,
            rewardInfoByToken[rewardToken].marketWeights
        );
    }

    /* ****************** */
    /*     Governance     */
    /* ****************** */

    /// Sets the weights for all perpetual markets
    /// @param _weights List of weights for each market, in the order of perp
    function updateRewardWeights(
        address _token,
        address[] calldata _markets,
        uint16[] calldata _weights
    ) external nonReentrant onlyRole(GOVERNANCE) {
        if (
            _token == address(0) ||
            rewardInfoByToken[_token].token != IERC20Metadata(_token)
        ) revert RewardController_InvalidRewardTokenAddress(_token);
        if (_weights.length != _markets.length)
            revert RewardController_IncorrectWeightsCount(
                _weights.length,
                _markets.length
            );
        // Update rewards for all currently rewarded markets before changing weights
        for (
            uint i;
            i < rewardInfoByToken[_token].marketAddresses.length;
            ++i
        ) {
            address market = rewardInfoByToken[_token].marketAddresses[i];
            updateMarketRewards(market);
            // Check if market is being removed from rewards
            bool found = false;
            for (uint j; j < _markets.length; ++j) {
                if (_markets[j] == market) {
                    found = true;
                    break;
                }
            }
            if (!found) {
                // Remove token from market's list of reward tokens
                for (uint j; j < rewardTokensPerMarket[market].length; ++j) {
                    if (rewardTokensPerMarket[market][j] == _token) {
                        rewardTokensPerMarket[market][
                            j
                        ] = rewardTokensPerMarket[market][
                            rewardTokensPerMarket[market].length - 1
                        ];
                        rewardTokensPerMarket[market].pop();
                        emit MarketRemovedFromRewards(market, _token);
                        break;
                    }
                }
            }
        }
        // Replace stored lists of market addresses and weights
        rewardInfoByToken[_token].marketAddresses = _markets;
        rewardInfoByToken[_token].marketWeights = _weights;
        // Validate weights
        uint16 totalWeight;
        for (uint i; i < _markets.length; ++i) {
            address market = _markets[i];
            uint16 weight = _weights[i];
            if (weight > 10000)
                revert RewardController_WeightExceedsMax(weight, 10000);
            totalWeight += weight;
            if (weight > 0) {
                // Check if token is already registered for this market
                bool found = false;
                for (uint j; j < rewardTokensPerMarket[market].length; ++j) {
                    if (rewardTokensPerMarket[market][j] == _token) {
                        found = true;
                        break;
                    }
                }
                // If the token was not previously registered for this market, add it
                if (!found) rewardTokensPerMarket[market].push(_token);
            }
            emit NewWeight(market, _token, weight);
        }
        if (totalWeight != 10000)
            revert RewardController_IncorrectWeightsSum(totalWeight, 10000);
    }

    /// Sets the inflation rate used to calculate emissions over time
    /// @param _newInflationRate The new inflation rate in INCR/year, scaled by 1e18
    function updateInflationRate(
        address _token,
        uint256 _newInflationRate
    ) external onlyRole(GOVERNANCE) {
        RewardInfo memory rewardInfo = rewardInfoByToken[_token];
        if (_token == address(0) || rewardInfo.token != IERC20Metadata(_token))
            revert RewardController_InvalidRewardTokenAddress(_token);
        if (_newInflationRate > MAX_INFLATION_RATE)
            revert RewardController_AboveMaxInflationRate(
                _newInflationRate,
                MAX_INFLATION_RATE
            );
        for (uint i; i < rewardInfo.marketAddresses.length; ++i) {
            address market = rewardInfoByToken[_token].marketAddresses[i];
            updateMarketRewards(market);
        }
        rewardInfoByToken[_token].initialInflationRate = _newInflationRate;
        emit NewInitialInflationRate(_token, _newInflationRate);
    }

    /// Sets the reduction factor used to reduce emissions over time
    /// @param _newReductionFactor The new reduction factor, scaled by 1e18
    function updateReductionFactor(
        address _token,
        uint256 _newReductionFactor
    ) external onlyRole(GOVERNANCE) {
        if (
            _token == address(0) ||
            rewardInfoByToken[_token].token != IERC20Metadata(_token)
        ) revert RewardController_InvalidRewardTokenAddress(_token);
        if (MIN_REDUCTION_FACTOR > _newReductionFactor)
            revert RewardController_BelowMinReductionFactor(
                _newReductionFactor,
                MIN_REDUCTION_FACTOR
            );
        rewardInfoByToken[_token].reductionFactor = _newReductionFactor;
        emit NewReductionFactor(_token, _newReductionFactor);
    }

    /* ****************** */
    /*   Emergency Admin  */
    /* ****************** */

    /// Pauses/unpauses the reward accrual for a reward token
    /// @param _token Address of the reward token
    /// @param _paused Whether to pause or unpause the reward token
    function setPaused(
        address _token,
        bool _paused
    ) external onlyRole(EMERGENCY_ADMIN) {
        RewardInfo memory rewardInfo = rewardInfoByToken[_token];
        if (_token == address(0) || rewardInfo.token != IERC20Metadata(_token))
            revert RewardController_InvalidRewardTokenAddress(_token);
        if (rewardInfo.paused == false) {
            // If not currently paused, accrue rewards before pausing
            uint256 marketsLength = rewardInfo.marketAddresses.length;
            for (uint i; i < marketsLength; ++i) {
                address market = rewardInfo.marketAddresses[i];
                updateMarketRewards(market);
            }
        }
        rewardInfoByToken[_token].paused = _paused;
    }
}
