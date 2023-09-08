// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.15;

// interfaces
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IClearingHouse} from "increment-protocol/interfaces/IClearingHouse.sol";
import {IPerpetual} from "increment-protocol/interfaces/IPerpetual.sol";

interface IRewardDistributor {

    /// Emitted when rewards are accrued to an LP
    /// @param lp Address of the liquidity provier
    /// @param perpetual Address of the perpetual market
    /// @param reward Amount of reward accrued
    event RewardAccrued(
        address indexed lp, 
        address rewardToken,
        address perpetual, 
        uint256 reward
    );

    /// Emitted when an LP claims their accrued rewards
    /// @param lp Address of the liquidity provier
    /// @param reward Amount of reward claimed
    event RewardClaimed(
        address indexed lp,
        address rewardToken,
        uint256 reward
    );

    /// Emitted when an LP's position is changed in the reward distributor 
    /// @param lp Address of the liquidity provier
    /// @param perpetualIndex Index of the perpetual market in the ClearingHouse
    /// @param prevPosition Previous LP position of the user
    /// @param newPosition New LP position of the user
    event PositionUpdated(
        address indexed lp, 
        uint256 perpetualIndex, 
        uint256 prevPosition, 
        uint256 newPosition
    );

    function earlyWithdrawalThreshold() external view returns (uint256);

    function registerPositions() external;
    function registerPositions(uint256[] calldata) external;
    function claimRewards() external;
    function claimRewardsFor(address) external;
    function claimRewardsFor(address, address[] memory) external;
}