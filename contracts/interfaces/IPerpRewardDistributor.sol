// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.16;

// interfaces
import {IClearingHouse} from "increment-protocol/interfaces/IClearingHouse.sol";

interface IPerpRewardDistributor {
    /// @notice Error returned when the caller of `updateStakingPosition` is not the ClearingHouse
    /// @param caller Address of the caller
    error PerpRewardDistributor_CallerIsNotClearingHouse(address caller);

    /// @notice Gets the address of the ClearingHouse contract which stores the list of Perpetuals and can call `updateStakingPosition`
    /// @return Address of the ClearingHouse contract
    function clearingHouse() external view returns (IClearingHouse);

    /// @notice Gets the number of seconds that a user must leave their liquidity in the market to avoid the early withdrawal penalty
    /// @return Length of the early withdrawal period in seconds
    function earlyWithdrawalThreshold() external view returns (uint256);
}
