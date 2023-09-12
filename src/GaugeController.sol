// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.15;

// contracts
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IncreAccessControl} from "increment-protocol/utils/IncreAccessControl.sol";

// interfaces
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IGaugeController} from "./interfaces/IGaugeController.sol";

abstract contract GaugeController is IGaugeController, IncreAccessControl, Pausable, ReentrancyGuard {

    /// @notice Data structure containing essential info for each reward token
    struct RewardInfo {
        IERC20Metadata token;       // Address of the reward token
        uint256 initialTimestamp;   // Time when the reward token was added
        uint256 inflationRate;      // Amount of reward token emitted per year
        uint256 reductionFactor;    // Factor by which the inflation rate is reduced each year
        uint16[] gaugeWeights;      // Weights are basis points, i.e., 100 = 1%, 10000 = 100%
    }

    /// @notice Maximum inflation rate, applies to all reward tokens
    uint256 public immutable maxInflationRate;

    /// @notice Minimum reduction factor, applies to all reward tokens
    uint256 public immutable minReductionFactor;

    /// @notice Maximum number of reward tokens supported
    uint256 public immutable maxRewardTokens;

    /// @notice List of reward token addresses
    /// @dev Length must be <= maxRewardTokens
    address[] public rewardTokens;

    /// @notice Info for each registered reward token
    mapping(address => RewardInfo) public rewardInfoByToken;

    error CallerIsNotClearingHouse(address caller);
    error AboveMaxRewardTokens(uint256 max);
    error AboveMaxInflationRate(uint256 rate, uint256 max);
    error BelowMinReductionFactor(uint256 factor, uint256 min);
    error InvalidRewardTokenAddress(address token);
    error IncorrectWeightsCount(uint256 actual, uint256 expected);
    error IncorrectWeightsSum(uint16 actual, uint16 expected);
    error WeightExceedsMax(uint16 weight, uint16 max);

    constructor(
        uint256 _maxRewardTokens,
        uint256 _initialInflationRate,
        uint256 _maxInflationRate,
        uint256 _initialReductionFactor,
        uint256 _minReductionFactor
    ) {
        maxRewardTokens = _maxRewardTokens;
        if(_maxRewardTokens < 1) revert AboveMaxRewardTokens(_maxRewardTokens);
        if(_initialInflationRate > _maxInflationRate) revert AboveMaxInflationRate(_initialInflationRate, _maxInflationRate);
        if(_minReductionFactor > _initialReductionFactor) revert BelowMinReductionFactor(_initialReductionFactor, _minReductionFactor);
        maxInflationRate = _maxInflationRate;
        minReductionFactor = _minReductionFactor;
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

    /// Gets the address of a gauge
    /// @dev Gauges are the perpetual markets (for the MarketRewardDistributor) or staked tokens (for the SafetyModule)
    /// @param idx Index of the gauge
    /// @return Address of the gauge
    function getGaugeAddress(uint256 idx) public view virtual returns (address);

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
        if(rewardInfoByToken[_token].token != IERC20Metadata(_token)) revert InvalidRewardTokenAddress(_token);
        uint256 gaugesLength = getNumGauges();
        if(_weights.length != gaugesLength) revert IncorrectWeightsCount(_weights.length, gaugesLength);
        uint16 totalWeight;
        for (uint i; i < gaugesLength; ++i) {
            updateMarketRewards(i);
            uint16 weight = _weights[i];
            if(weight > 10000) revert WeightExceedsMax(weight, 10000);
            address gauge = getGaugeAddress(i);
            rewardInfoByToken[_token].gaugeWeights[i] = weight;
            totalWeight += weight;
            emit NewWeight(gauge, _token, weight);
        }
        if(totalWeight != 10000) revert IncorrectWeightsSum(totalWeight, 10000);
    }

    /// Sets the inflation rate used to calculate emissions over time
    /// @param _newInflationRate The new inflation rate in INCR/year, scaled by 1e18
    function updateInflationRate(
        address _token,
        uint256 _newInflationRate
    ) external onlyRole(GOVERNANCE) {
        if(rewardInfoByToken[_token].token != IERC20Metadata(_token)) revert InvalidRewardTokenAddress(_token);
        if(_newInflationRate > maxInflationRate) revert AboveMaxInflationRate(_newInflationRate, maxInflationRate);
        uint256 gaugesLength = getNumGauges();
        for (uint i; i < gaugesLength; ++i) {
            updateMarketRewards(i);
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
        if(rewardInfoByToken[_token].token != IERC20Metadata(_token)) revert InvalidRewardTokenAddress(_token);
        if(minReductionFactor > _newReductionFactor) revert BelowMinReductionFactor(_newReductionFactor, minReductionFactor);
        rewardInfoByToken[_token].reductionFactor = _newReductionFactor;
        emit NewReductionFactor(_token, _newReductionFactor);
    }
}