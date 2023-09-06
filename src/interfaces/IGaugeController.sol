// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.15;

import {IClearingHouse} from "increment-protocol/interfaces/IClearingHouse.sol";

interface IGaugeController {
    /// Emitted when a gauge weight is updated
    /// @param gauge the address of the perp market or safety module (i.e., gauge)
    /// @param newWeight the new weight value
    event NewWeight(
        address indexed gauge, 
        address indexed rewardToken,
        uint16 newWeight
    );

    /// Emitted when a new inflation rate is set by governance
    /// @param newRate the new inflation rate
    event NewInflationRate(
        address indexed rewardToken,
        uint256 newRate
    );

    /// Emitted when a new reduction factor is set by governance
    /// @param newFactor the new reduction factor
    event NewReductionFactor(
        address indexed rewardToken,
        uint256 newFactor
    );
    function clearingHouse() external view returns (IClearingHouse);
    function rewardTokens(uint256) external view returns (address);

    function updateMarketRewards(uint256) external;
    function updateGaugeWeights(address, uint16[] calldata) external;
    function updateInflationRate(address, uint256) external;
    function updateReductionFactor(address, uint256) external;
}
