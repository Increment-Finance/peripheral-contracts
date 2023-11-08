// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.16;

// interfaces
import {IRewardDistributor} from "./IRewardDistributor.sol";
import {IClearingHouse} from "increment-protocol/interfaces/IClearingHouse.sol";

interface IPerpRewardDistributor {
    error PerpRewardDistributor_CallerIsNotClearingHouse(address caller);

    function clearingHouse() external view returns (IClearingHouse);

    function earlyWithdrawalThreshold() external view returns (uint256);
}
