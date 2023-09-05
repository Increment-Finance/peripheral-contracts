// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.15;

// contracts
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IncreAccessControl} from "increment-protocol/utils/IncreAccessControl.sol";

// interfaces
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IClearingHouse} from "increment-protocol/interfaces/IClearingHouse.sol";
import {IGaugeController} from "./interfaces/IGaugeController.sol";

abstract contract GaugeController is IGaugeController, IncreAccessControl, Pausable, ReentrancyGuard {

    uint256 public immutable initialTimestamp = block.timestamp;

    uint256 public immutable maxInflationRate;

    uint256 public immutable minReductionFactor;

    /// @notice The amount of INCR emitted per year
    /// @dev initial inflation rate = 1,463,752.93 x 10^18 INCR/year
    uint256 public inflationRate;

    /// @notice The factor by which the inflation rate is reduced each year
    /// @dev initial reduction factor = 2^0.25 = 1.189207115 x 10^18
    uint256 public reductionFactor;

    /// @notice Mapping of gauge address to weight
    /// @dev Weights are basis points, i.e., 100 = 1%, 10000 = 100%
    mapping(address => uint16) public gaugeWeights;

    /// @notice Clearing House contract
    IClearingHouse public clearingHouse;

    error CallerIsNotClearingHouse(address caller);
    error AboveMaxInflationRate(uint256 rate, uint256 max);
    error BelowMinReductionFactor(uint256 factor, uint256 min);
    error IncorrectWeightsCount(uint256 actual, uint256 expected);
    error IncorrectWeightsSum(uint16 actual, uint16 expected);
    error WeightExceedsMax(uint16 weight, uint16 max);

    modifier onlyClearingHouse {
        if(msg.sender != address(clearingHouse)) revert CallerIsNotClearingHouse(msg.sender);
        _;
    }

    constructor(
        uint256 _initialInflationRate,
        uint256 _maxInflationRate,
        uint256 _initialReductionFactor,
        uint256 _minReductionFactor,
        address _clearingHouse 
    ) {
        clearingHouse = IClearingHouse(_clearingHouse);
        if(_initialInflationRate > _maxInflationRate) revert AboveMaxInflationRate(_initialInflationRate, _maxInflationRate);
        inflationRate = _initialInflationRate;
        maxInflationRate = _maxInflationRate;
        if(_minReductionFactor > _initialReductionFactor) revert BelowMinReductionFactor(_initialReductionFactor, _minReductionFactor);
        reductionFactor = _initialReductionFactor;
        minReductionFactor = _minReductionFactor;
    }

    /* ****************** */
    /*      Abstract      */
    /* ****************** */

    /// Updates the reward accumulator for a given market
    /// @dev Executes when any of the following variables are changed: inflationRate, gaugeWeights, liquidity
    /// @param idx Index of the perpetual market in the ClearingHouse
    function updateMarketRewards(uint256 idx) public virtual;

    /* ****************** */
    /*     Governance     */
    /* ****************** */

    /// Sets the weights for all perpetual markets
    /// @param _weights List of weights for each gauge, in the order of perpetual markets
    /// @dev Weights are basis points, i.e., 100 = 1%, 10000 = 100%
    function updateGaugeWeights(
        uint16[] calldata _weights
    ) external nonReentrant onlyRole(GOVERNANCE) {
        uint256 perpetualsLength = clearingHouse.getNumMarkets();
        if(_weights.length != perpetualsLength) revert IncorrectWeightsCount(_weights.length, perpetualsLength);
        uint16 totalWeight;
        for (uint i; i < perpetualsLength; ++i) {
            updateMarketRewards(i);
            uint16 weight = _weights[i];
            if(weight > 10000) revert WeightExceedsMax(weight, 10000);
            address gauge = address(clearingHouse.perpetuals(i));
            gaugeWeights[gauge] = weight;
            totalWeight += weight;
            emit NewWeight(gauge, weight);
        }
        if(totalWeight != 10000) revert IncorrectWeightsSum(totalWeight, 10000);
    }

    /// Sets the inflation rate used to calculate emissions over time
    /// @param _newInflationRate The new inflation rate in INCR/year, scaled by 1e18
    function updateInflationRate(uint256 _newInflationRate) external onlyRole(GOVERNANCE) {
        if(_newInflationRate > maxInflationRate) revert AboveMaxInflationRate(_newInflationRate, maxInflationRate);
        uint256 perpetualsLength = clearingHouse.getNumMarkets();
        for (uint i; i < perpetualsLength; ++i) {
            updateMarketRewards(i);
        }
        inflationRate = _newInflationRate;
        emit NewInflationRate(_newInflationRate);
    }

    /// Sets the reduction factor used to reduce emissions over time
    /// @param _newReductionFactor The new reduction factor, scaled by 1e18
    function updateReductionFactor(uint256 _newReductionFactor) external onlyRole(GOVERNANCE) {
        if(minReductionFactor > _newReductionFactor) revert BelowMinReductionFactor(_newReductionFactor, minReductionFactor);
        reductionFactor = _newReductionFactor;
        emit NewReductionFactor(_newReductionFactor);
    }
}