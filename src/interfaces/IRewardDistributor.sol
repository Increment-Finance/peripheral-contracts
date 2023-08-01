// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.15;

// interfaces
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IClearingHouse} from "increment-protocol/interfaces/IClearingHouse.sol";
import {IPerpetual} from "increment-protocol/interfaces/IPerpetual.sol";
import {IVault} from "increment-protocol/interfaces/IVault.sol";

interface IRewardDistributor {
    event RewardDistributed(address lp, uint256 gauge, uint256 reward);

    function rewardsAccruedByUser(address) external view returns (uint256);
    function rewardToken() external view returns (IERC20Metadata);
    function vault() external view returns (IVault);
}