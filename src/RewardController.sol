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
        uint256 initialTimestamp;
        uint256 initialInflationRate;
        uint256 reductionFactor;
        address[] marketAddresses;
        uint16[] marketWeights;
    }

    /// @notice Maximum inflation rate, applies to all reward tokens
    uint256 public constant MAX_INFLATION_RATE = 5e24;

    /// @notice Minimum reduction factor, applies to all reward tokens
    uint256 public constant MIN_REDUCTION_FACTOR = 1e18;

    /// @notice Maximum number of reward tokens allowed for each market
    uint256 public constant MAX_REWARD_TOKENS = 10;

    /// @notice List of reward token addresses for each market
    /// @dev Length must be <= MAX_REWARD_TOKENS
    mapping(address => address[]) public rewardTokensPerMarket;

    /// @notice Info for each registered reward token
    mapping(address => RewardInfo) public rewardInfoByToken;

    /* ****************** */
    /*      Abstract      */
    /* ****************** */

    /// @inheritdoc IRewardController
    function updateMarketRewards(address market) public virtual;

    /// @inheritdoc IRewardController
    function getNumMarkets() public view virtual returns (uint256);

    /// @inheritdoc IRewardController
    function getMaxMarketIdx() public view virtual returns (uint256);

    /// @inheritdoc IRewardController
    function getMarketAddress(
        uint256 idx
    ) public view virtual returns (address);

    /// @inheritdoc IRewardController
    function getMarketIdx(uint256 i) public view virtual returns (uint256);

    /// @inheritdoc IRewardController
    function getMarketWeightIdx(
        address token,
        address market
    ) public view virtual returns (uint256) {
        RewardInfo memory rewardInfo = rewardInfoByToken[token];
        for (uint i; i < rewardInfo.marketAddresses.length; ++i) {
            if (rewardInfo.marketAddresses[i] == market) return i;
        }
        revert RewardController_MarketHasNoRewardWeight(market, token);
    }

    /// @inheritdoc IRewardController
    function getCurrentPosition(
        address lp,
        address market
    ) public view virtual returns (uint256);

    /* ******************* */
    /*  Reward Info Views  */
    /* ******************* */

    /// @inheritdoc IRewardController
    function getRewardTokenCount(
        address market
    ) external view returns (uint256) {
        return rewardTokensPerMarket[market].length;
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
        RewardInfo memory rewardInfo = rewardInfoByToken[rewardToken];
        uint256 totalTimeElapsed = block.timestamp -
            rewardInfo.initialTimestamp;
        return
            rewardInfo.initialInflationRate.div(
                rewardInfo.reductionFactor.pow(totalTimeElapsed.div(365 days))
            );
    }

    /// @inheritdoc IRewardController
    function getReductionFactor(
        address rewardToken
    ) external view returns (uint256) {
        return rewardInfoByToken[rewardToken].reductionFactor;
    }

    /// @inheritdoc IRewardController
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

    /// @inheritdoc IRewardController
    /// @dev Only callable by Governance
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
                if (_markets[j] != market) continue;
                found = true;
                break;
            }
            if (found) continue;
            // Remove token from market's list of reward tokens
            for (uint j; j < rewardTokensPerMarket[market].length; ++j) {
                if (rewardTokensPerMarket[market][j] != _token) continue;
                rewardTokensPerMarket[market][j] = rewardTokensPerMarket[
                    market
                ][rewardTokensPerMarket[market].length - 1];
                rewardTokensPerMarket[market].pop();
                emit MarketRemovedFromRewards(market, _token);
                break;
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
                    if (rewardTokensPerMarket[market][j] != _token) continue;
                    found = true;
                    break;
                }
                // If the token was not previously registered for this market, add it
                if (!found) rewardTokensPerMarket[market].push(_token);
            }
            emit NewWeight(market, _token, weight);
        }
        if (totalWeight != 10000)
            revert RewardController_IncorrectWeightsSum(totalWeight, 10000);
    }

    /// @inheritdoc IRewardController
    /// @dev Only callable by Governance
    function updateInitialInflationRate(
        address _token,
        uint256 _newInitialInflationRate
    ) external onlyRole(GOVERNANCE) {
        RewardInfo memory rewardInfo = rewardInfoByToken[_token];
        if (_token == address(0) || rewardInfo.token != IERC20Metadata(_token))
            revert RewardController_InvalidRewardTokenAddress(_token);
        if (_newInitialInflationRate > MAX_INFLATION_RATE)
            revert RewardController_AboveMaxInflationRate(
                _newInitialInflationRate,
                MAX_INFLATION_RATE
            );
        for (uint i; i < rewardInfo.marketAddresses.length; ++i) {
            address market = rewardInfoByToken[_token].marketAddresses[i];
            updateMarketRewards(market);
        }
        rewardInfoByToken[_token]
            .initialInflationRate = _newInitialInflationRate;
        emit NewInitialInflationRate(_token, _newInitialInflationRate);
    }

    /// @inheritdoc IRewardController
    /// @dev Only callable by Governance
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

    /// @inheritdoc IRewardController
    /// @dev Only callable by Emergency Admin
    function setPaused(
        address _token,
        bool _paused
    ) external onlyRole(EMERGENCY_ADMIN) {
        RewardInfo memory rewardInfo = rewardInfoByToken[_token];
        if (_token == address(0) || rewardInfo.token != IERC20Metadata(_token))
            revert RewardController_InvalidRewardTokenAddress(_token);
        if (rewardInfo.paused == false) {
            // If not currently paused, accrue rewards before pausing
            for (uint i; i < rewardInfo.marketAddresses.length; ++i) {
                address market = rewardInfo.marketAddresses[i];
                updateMarketRewards(market);
            }
        }
        rewardInfoByToken[_token].paused = _paused;
    }
}
