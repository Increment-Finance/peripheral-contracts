// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.15;

import {IClearingHouse} from "increment-protocol/interfaces/IClearingHouse.sol";

interface IGaugeController {
    /// Emitted when a new reward token is added
    /// @param rewardToken reward token address
    /// @param initialTimestamp timestamp when reward token was added
    /// @param initialInflationRate initial inflation rate for the reward token
    /// @param initialReductionFactor initial reduction factor for the reward token
    event RewardTokenAdded(
        address indexed rewardToken,
        uint256 initialTimestamp,
        uint256 initialInflationRate,
        uint256 initialReductionFactor
    );

    /// Emitted when governance removes a reward token
    /// @param rewardToken the reward token address
    /// @param unclaimedRewards the amount of reward tokens still claimable
    /// @param remainingBalance the remaining balance of the reward token, sent to governance
    event RewardTokenRemoved(
        address indexed rewardToken,
        uint256 unclaimedRewards,
        uint256 remainingBalance
    );

    /// Emitted when a gauge weight is updated
    /// @param gauge the address of the perp market or safety module (i.e., gauge)
    /// @param rewardToken the reward token address
    /// @param newWeight the new weight value
    event NewWeight(
        address indexed gauge,
        address indexed rewardToken,
        uint16 newWeight
    );

    /// Emitted when a new inflation rate is set by governance
    /// @param newRate the new inflation rate
    event NewInflationRate(address indexed rewardToken, uint256 newRate);

    /// Emitted when a new reduction factor is set by governance
    /// @param newFactor the new reduction factor
    event NewReductionFactor(address indexed rewardToken, uint256 newFactor);

    function clearingHouse() external view returns (IClearingHouse);

    function rewardTokens(uint256) external view returns (address);

    function getNumGauges() external view returns (uint256);

    function getGaugeAddress(uint256) external view returns (address);

    function updateMarketRewards(uint256) external;

    function updateGaugeWeights(address, uint16[] calldata) external;

    function updateInflationRate(address, uint256) external;

    function updateReductionFactor(address, uint256) external;
}
