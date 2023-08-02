// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.15;

// contracts
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IncreAccessControl} from "increment-protocol/utils/IncreAccessControl.sol";

// interfaces
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IClearingHouse} from "increment-protocol/interfaces/IClearingHouse.sol";
import {IPerpetual} from "increment-protocol/interfaces/IPerpetual.sol";
import {IInsurance} from "increment-protocol/interfaces/IInsurance.sol";
import {IVault} from "increment-protocol/interfaces/IVault.sol";
import {ICryptoSwap} from "increment-protocol/interfaces/ICryptoSwap.sol";
import {IStakingContract} from "increment-protocol/interfaces/IStakingContract.sol";
import {IRewardDistributor} from "./interfaces/IRewardDistributor.sol";
import {IGaugeController} from "./interfaces/IGaugeController.sol";

// libraries
import {LibMath} from "increment-protocol/lib/LibMath.sol";
import {LibPerpetual} from "increment-protocol/lib/LibPerpetual.sol";
import {LibReserve} from "increment-protocol/lib/LibReserve.sol";

contract GaugeController is IGaugeController, IncreAccessControl, Pausable, ReentrancyGuard {

    uint256 public immutable initialTimestamp = block.timestamp;

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

    modifier onlyClearingHouse {
        require(msg.sender == address(clearingHouse), "GaugeController: caller must be clearing house");
        _;
    }

    constructor(
        uint256 _initialInflationRate,
        uint256 _initialReductionFactor,
        address _clearingHouse 
    ) {
        clearingHouse = IClearingHouse(_clearingHouse);
        inflationRate = _initialInflationRate;
        reductionFactor = _initialReductionFactor;
    }

    /* ****************** */
    /*     Governance     */
    /* ****************** */

    /// Sets the weights for all perpetual markets and the safety module
    /// @param _weights List of weights for each gauge, in the order of perpetual markets, then safety module
    /// @dev Weights are basis points, i.e., 100 = 1%, 10000 = 100%
    function updateGaugeWeights(
        uint16[] calldata _weights
    ) external nonReentrant onlyRole(GOVERNANCE) {
        uint256 perpetualsLength = clearingHouse.getNumMarkets();
        require(_weights.length == perpetualsLength + 1, "Incorrect number of weights");
        uint16 totalWeight;
        for (uint i; i < perpetualsLength; ++i) {
            uint16 weight = _weights[i];
            require(weight <= 10000, "Weight exceeds 100%");
            address gauge = address(clearingHouse.perpetuals(i));
            gaugeWeights[gauge] = weight;
            totalWeight += weight;
        }
        require(totalWeight == 10000, "Total weight does not equal 100%");
    }

    /// Sets the inflation rate used to calculate emissions over time
    /// @param _newInflationRate The new inflation rate in INCR/year, scaled by 1e18
    function updateInflationRate(uint256 _newInflationRate) external onlyRole(GOVERNANCE) {
        uint256 oldInflationRate = inflationRate;
        inflationRate = _newInflationRate;
        emit NewInflationRate(block.timestamp, oldInflationRate, _newInflationRate);
    }

    /// Sets the reduction factor used to reduce emissions over time
    /// @param _newReductionFactor The new reduction factor, scaled by 1e18
    function updateReductionFactor(uint256 _newReductionFactor) external onlyRole(GOVERNANCE) {
        uint256 oldReductionFactor = reductionFactor;
        reductionFactor = _newReductionFactor;
        emit NewReductionFactor(block.timestamp, oldReductionFactor, _newReductionFactor);
    }

    /* ****************** */
    /*      Internal      */
    /* ****************** */

    function _calcEmissions(uint256 timestamp) internal view returns (uint256) {
        uint256 timeElapsed = timestamp - initialTimestamp;
        uint256 emissions = inflationRate / (reductionFactor ^ (timeElapsed / 365 days));
        return emissions;
    }

    function _calcEmmisionsPerGauge(address gauge, uint256 timestamp) internal view returns (uint256) {
        uint256 emissions = _calcEmissions(timestamp);
        return emissions * gaugeWeights[gauge] / 10000;
    }
}