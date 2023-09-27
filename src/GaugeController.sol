// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.16;

// contracts
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IncreAccessControl} from "increment-protocol/utils/IncreAccessControl.sol";

// interfaces
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IGaugeController} from "./interfaces/IGaugeController.sol";

// libraries
import {PRBMathUD60x18} from "prb-math/contracts/PRBMathUD60x18.sol";

abstract contract GaugeController is
    IGaugeController,
    IncreAccessControl,
    Pausable,
    ReentrancyGuard
{
    using PRBMathUD60x18 for uint256;

    /// @notice Data structure containing essential info for each reward token
    struct RewardInfo {
        IERC20Metadata token; // Address of the reward token
        uint256 initialTimestamp; // Time when the reward token was added
        uint256 inflationRate; // Amount of reward token emitted per year
        uint256 reductionFactor; // Factor by which the inflation rate is reduced each year
        uint16[] gaugeWeights; // Weights are basis points, i.e., 100 = 1%, 10000 = 100%
    }

    /// @notice Maximum inflation rate, applies to all reward tokens
    uint256 public constant MAX_INFLATION_RATE = 5e24;

    /// @notice Minimum reduction factor, applies to all reward tokens
    uint256 public constant MIN_REDUCTION_FACTOR = 1e18;

    /// @notice Maximum number of reward tokens supported
    uint256 public constant MAX_REWARD_TOKENS = 10;

    /// @notice List of reward token addresses
    /// @dev Length must be <= maxRewardTokens
    address[] public rewardTokens;

    /// @notice Info for each registered reward token
    mapping(address => RewardInfo) public rewardInfoByToken;

    constructor(
        uint256 _initialInflationRate,
        uint256 _initialReductionFactor
    ) {
        if (_initialInflationRate > MAX_INFLATION_RATE)
            revert GaugeController_AboveMaxInflationRate(
                _initialInflationRate,
                MAX_INFLATION_RATE
            );
        if (MIN_REDUCTION_FACTOR > _initialReductionFactor)
            revert GaugeController_BelowMinReductionFactor(
                _initialReductionFactor,
                MIN_REDUCTION_FACTOR
            );
    }

    /* ****************** */
    /*      Abstract      */
    /* ****************** */

    /// Updates the reward accumulator for a given market
    /// @dev Executes when any of the following variables are changed: inflationRate, gaugeWeights, liquidity
    /// @param idx Index of the perpetual market in the ClearingHouse
    function updateMarketRewards(uint256 idx) public virtual;

    /// Gets the number of gauges to be used for reward distribution
    /// @dev Gauges are the perpetual markets (for the MarketRewardDistributor) or staked tokens (for the SafetyModule)
    /// @return Number of gauges
    function getNumGauges() public view virtual returns (uint256);

    /// Gets the highest valid market index
    /// @return Highest valid market index
    function getMaxGaugeIdx() public view virtual returns (uint256);

    /// Gets the address of a gauge
    /// @dev Gauges are the perpetual markets (for the MarketRewardDistributor) or staked tokens (for the SafetyModule)
    /// @param idx Index of the gauge
    /// @return Address of the gauge
    function getGaugeAddress(uint256 idx) public view virtual returns (address);

    /// Gets the index of an allowlisted gauge
    /// @dev Gauges are the perpetual markets (for the MarketRewardDistributor) or staked tokens (for the SafetyModule)
    /// @param i Index of the gauge in the allowlist ids
    /// @return Index of the gauge in the gauge list
    function getGaugeIdx(uint256 i) public view virtual returns (uint256);

    /* ******************* */
    /*  Reward Info Views  */
    /* ******************* */

    /// Gets the number of reward tokens
    function getRewardTokenCount() external view returns (uint256) {
        return rewardTokens.length;
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
    function getBaseInflationRate(
        address rewardToken
    ) external view returns (uint256) {
        return rewardInfoByToken[rewardToken].inflationRate;
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
            rewardInfo.inflationRate.div(
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

    /// Gets the weights of all gauges for a reward token
    /// @param rewardToken Address of the reward token
    function getGaugeWeights(
        address rewardToken
    ) external view returns (uint16[] memory) {
        return rewardInfoByToken[rewardToken].gaugeWeights;
    }

    /* ****************** */
    /*     Governance     */
    /* ****************** */

    /// Sets the weights for all perpetual markets
    /// @param _weights List of weights for each gauge, in the order of perpetual markets
    /// @dev Weights are basis points, i.e., 100 = 1%, 10000 = 100%
    function updateGaugeWeights(
        address _token,
        uint16[] calldata _weights
    ) external nonReentrant onlyRole(GOVERNANCE) {
        if (
            _token == address(0) ||
            rewardInfoByToken[_token].token != IERC20Metadata(_token)
        ) revert GaugeController_InvalidRewardTokenAddress(_token);
        uint256 gaugesLength = getNumGauges();
        if (_weights.length != gaugesLength)
            revert GaugeController_IncorrectWeightsCount(
                _weights.length,
                gaugesLength
            );
        uint16 totalWeight;
        for (uint i; i < gaugesLength; ++i) {
            uint256 idx = getGaugeIdx(i);
            updateMarketRewards(idx);
            uint16 weight = _weights[i];
            if (weight > 10000)
                revert GaugeController_WeightExceedsMax(weight, 10000);
            address gauge = getGaugeAddress(idx);
            if (i == rewardInfoByToken[_token].gaugeWeights.length) {
                // Gauge added since last update
                rewardInfoByToken[_token].gaugeWeights.push(weight);
            } else {
                rewardInfoByToken[_token].gaugeWeights[i] = weight;
            }
            totalWeight += weight;
            emit NewWeight(gauge, _token, weight);
        }
        if (totalWeight != 10000)
            revert GaugeController_IncorrectWeightsSum(totalWeight, 10000);
    }

    /// Sets the inflation rate used to calculate emissions over time
    /// @param _newInflationRate The new inflation rate in INCR/year, scaled by 1e18
    function updateInflationRate(
        address _token,
        uint256 _newInflationRate
    ) external onlyRole(GOVERNANCE) {
        if (
            _token == address(0) ||
            rewardInfoByToken[_token].token != IERC20Metadata(_token)
        ) revert GaugeController_InvalidRewardTokenAddress(_token);
        if (_newInflationRate > MAX_INFLATION_RATE)
            revert GaugeController_AboveMaxInflationRate(
                _newInflationRate,
                MAX_INFLATION_RATE
            );
        uint256 gaugesLength = getNumGauges();
        for (uint i; i < gaugesLength; ++i) {
            uint256 idx = getGaugeIdx(i);
            updateMarketRewards(idx);
        }
        rewardInfoByToken[_token].inflationRate = _newInflationRate;
        emit NewInflationRate(_token, _newInflationRate);
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
        ) revert GaugeController_InvalidRewardTokenAddress(_token);
        if (MIN_REDUCTION_FACTOR > _newReductionFactor)
            revert GaugeController_BelowMinReductionFactor(
                _newReductionFactor,
                MIN_REDUCTION_FACTOR
            );
        rewardInfoByToken[_token].reductionFactor = _newReductionFactor;
        emit NewReductionFactor(_token, _newReductionFactor);
    }
}
