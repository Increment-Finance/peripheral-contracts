// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.16;

// interfaces
import {IRewardDistributor} from "./IRewardDistributor.sol";
import {IClearingHouse} from "increment-protocol/interfaces/IClearingHouse.sol";

interface IPerpRewardDistributor is IRewardDistributor {
    /// @notice Emitted when the ClearingHouse contract is updated by governance
    /// @param oldClearingHouse Address of the old ClearingHouse contract
    /// @param newClearingHouse Address of the new ClearingHouse contract
    event ClearingHouseUpdated(address oldClearingHouse, address newClearingHouse);

    /// @notice Emitted when the early withdrawal threshold is updated by governance
    /// @param oldEarlyWithdrawalThreshold Old early withdrawal threshold
    /// @param newEarlyWithdrawalThreshold New early withdrawal threshold
    event EarlyWithdrawalThresholdUpdated(uint256 oldEarlyWithdrawalThreshold, uint256 newEarlyWithdrawalThreshold);

    /// @notice Error returned when the caller of `updatePosition` is not the ClearingHouse
    /// @param caller Address of the caller
    error PerpRewardDistributor_CallerIsNotClearingHouse(address caller);

    /// @notice Gets the address of the ClearingHouse contract which stores the list of Perpetuals and can call `updatePosition`
    /// @return Address of the ClearingHouse contract
    function clearingHouse() external view returns (IClearingHouse);

    /// @notice Gets the number of seconds that a user must leave their liquidity in the market to avoid the early withdrawal penalty
    /// @return Length of the early withdrawal period in seconds
    function earlyWithdrawalThreshold() external view returns (uint256);

    /// @notice Start time of the user's early withdrawal timer for a specific market,
    /// i.e., when they last changed their position in the market
    /// @dev The user can withdraw their liquidity without penalty after `withdrawTimerStartByUserByMarket(user, market) + earlyWithdrawalThreshold`
    /// @param _user Address of the user
    /// @param _market Address of the market
    /// @return Timestamp when user last changed their position in the market
    function withdrawTimerStartByUserByMarket(address _user, address _market) external view returns (uint256);

    /// @notice Sets the number of seconds that a user must leave their liquidity in the market to avoid the early withdrawal penalty
    /// @param _newEarlyWithdrawalThreshold New early withdrawal threshold in seconds
    function setEarlyWithdrawalThreshold(uint256 _newEarlyWithdrawalThreshold) external;
}
