// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.15;

import {IClearingHouse} from "increment-protocol/interfaces/IClearingHouse.sol";

interface IGaugeController {
    /// Emitted when a gauge weight is updated
    /// @param gauge the address of the perp market or safety module (i.e., gauge)
    /// @param prevWeight the previous weight value
    /// @param newWeight the new weight value
    event NewWeight(
        address indexed gauge, 
        uint16 prevWeight, 
        uint16 newWeight
    );

    event NewInflationRate(
        uint256 indexed timestamp,
        uint256 prevRate,
        uint256 newRate
    );

    event NewReductionFactor(
        uint256 indexed timestamp,
        uint256 prevFactor,
        uint256 newFactor
    );

    event NewSafetyModule(
        uint256 indexed timestamp,
        address indexed prevModule,
        address indexed newModule
    );

    function initialTimestamp() external view returns (uint256);
    function inflationRate() external view returns (uint256);
    function reductionFactor() external view returns (uint256);
    function clearingHouse() external view returns (IClearingHouse);
    function safetyModule() external view returns (address);
    function gaugeWeights(address gauge) external view returns (uint16);

    function updateGaugeWeights(uint16[] calldata weights) external;
    function updateInflationRate(uint256 _newInflationRate) external;
    function updateReductionFactor(uint256 _newReductionFactor) external;
    function setSafetyModule(address _safetyModule) external;
}
