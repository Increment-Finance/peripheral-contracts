// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.16;

// interfaces
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IClearingHouse} from "increment-protocol/interfaces/IClearingHouse.sol";
import {IPerpetual} from "increment-protocol/interfaces/IPerpetual.sol";

interface IRewardDistributor {
    /// Emitted when rewards are accrued to an LP
    /// @param lp Address of the liquidity provier
    /// @param rewardToken Address of the reward token
    /// @param perpetual Address of the perpetual market
    /// @param reward Amount of reward accrued
    event RewardAccruedToUser(
        address indexed lp,
        address rewardToken,
        address perpetual,
        uint256 reward
    );

    /// Emitted when rewards are accrued to a market
    /// @param perpetual Address of the perpetual market
    /// @param rewardToken Address of the reward token
    /// @param reward Amount of reward accrued
    event RewardAccruedToMarket(
        address indexed perpetual,
        address rewardToken,
        uint256 reward
    );

    /// Emitted when an LP claims their accrued rewards
    /// @param lp Address of the liquidity provier
    /// @param rewardToken Address of the reward token
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

    error RewardDistributor_CallerIsNotClearingHouse(address caller);
    error RewardDistributor_InvalidMarketIndex(uint256 index, uint256 maxIndex);
    error RewardDistributor_MarketIndexNotAllowlisted(uint256 index);
    error RewardDistributor_UninitializedStartTime(address gauge);
    error RewardDistributor_AlreadyInitializedStartTime(address gauge);
    error RewardDistributor_NoRewardsToClaim(address user);
    error RewardDistributor_PositionAlreadyRegistered(
        address lp,
        uint256 marketIndex,
        uint256 position
    );
    error RewardDistributor_EarlyRewardAccrual(
        address user,
        uint256 marketIndex,
        uint256 claimAllowedTimestamp
    );
    error RewardDistributor_LpPositionMismatch(
        address lp,
        uint256 marketIndex,
        uint256 prevPosition,
        uint256 newPosition
    );

    function earlyWithdrawalThreshold() external view returns (uint256);

    function getCurrentPosition(
        address,
        address
    ) external view returns (uint256);

    function addRewardToken(
        address,
        uint256,
        uint256,
        uint16[] calldata
    ) external;

    function removeRewardToken(address) external;

    function registerPositions() external;

    function registerPositions(uint256[] calldata) external;

    function claimRewards() external;

    function claimRewardsFor(address) external;

    function claimRewardsFor(address, address[] memory) external;

    function accrueRewards(address) external;

    function accrueRewards(uint256, address) external;

    function viewNewRewardAccrual(
        address
    ) external view returns (uint256[] memory);

    function viewNewRewardAccrual(
        uint256,
        address
    ) external view returns (uint256[] memory);

    function viewNewRewardAccrual(
        uint256,
        address,
        address
    ) external view returns (uint256);
}
