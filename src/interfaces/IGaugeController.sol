// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.15;

import {IClearingHouse} from "increment-protocol/interfaces/IClearingHouse.sol";

interface IGaugeController {
    /// Emitted when a gauge weight is updated
    /// @param gauge the address of the perp market or safety module (i.e., gauge)
    /// @param newWeight the new weight value
    event NewWeight(
        address indexed gauge, 
        uint16 newWeight
    );

    /// Emitted when a new inflation rate is set by governance
    /// @param newRate the new inflation rate
    event NewInflationRate(
        uint256 newRate
    );

    /// Emitted when a new reduction factor is set by governance
    /// @param newFactor the new reduction factor
    event NewReductionFactor(
        uint256 newFactor
    );

    function initialTimestamp() external view returns (uint256);
    function inflationRate() external view returns (uint256);
    function reductionFactor() external view returns (uint256);
    function clearingHouse() external view returns (IClearingHouse);
    function gaugeWeights(address gauge) external view returns (uint16);

    function updateGaugeWeights(uint16[] calldata weights) external;
    function updateInflationRate(uint256 _newInflationRate) external;
    function updateReductionFactor(uint256 _newReductionFactor) external;
}
