// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.16;

// interfaces
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IPerpetual} from "increment-protocol/interfaces/IPerpetual.sol";

interface IRewardDistributor {
    /// Emitted when rewards are accrued to an LP
    /// @param lp Address of the liquidity provier
    /// @param rewardToken Address of the reward token
    /// @param market Address of the market
    /// @param reward Amount of reward accrued
    event RewardAccruedToUser(
        address indexed lp,
        address rewardToken,
        address market,
        uint256 reward
    );

    /// Emitted when rewards are accrued to a market
    /// @param market Address of the market
    /// @param rewardToken Address of the reward token
    /// @param reward Amount of reward accrued
    event RewardAccruedToMarket(
        address indexed market,
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
    /// @param market Address of the market
    /// @param prevPosition Previous LP position of the user
    /// @param newPosition New LP position of the user
    event PositionUpdated(
        address indexed lp,
        address market,
        uint256 prevPosition,
        uint256 newPosition
    );

    /// Emitted when the address of the ecosystem reserve for storing reward tokens is updated
    /// @param newEcosystemReserve Address of the new ecosystem reserve
    event EcosystemReserveUpdated(
        address prevEcosystemReserve,
        address newEcosystemReserve
    );

    error RewardDistributor_InvalidMarketIndex(uint256 index, uint256 maxIndex);
    error RewardDistributor_MarketHasNoRewardWeight(
        address market,
        address rewardToken
    );
    error RewardDistributor_UninitializedStartTime(address market);
    error RewardDistributor_AlreadyInitializedStartTime(address market);
    error RewardDistributor_NoRewardsToClaim(address user);
    error RewardDistributor_PositionAlreadyRegistered(
        address lp,
        address market,
        uint256 position
    );
    error RewardDistributor_EarlyRewardAccrual(
        address user,
        address market,
        uint256 claimAllowedTimestamp
    );
    error RewardDistributor_LpPositionMismatch(
        address lp,
        address market,
        uint256 prevPosition,
        uint256 newPosition
    );
    error RewardDistributor_InvalidEcosystemReserve(address invalidAddress);

    function getCurrentPosition(
        address,
        address
    ) external view returns (uint256);

    function addRewardToken(
        address,
        uint256,
        uint256,
        address[] calldata,
        uint16[] calldata
    ) external;

    function removeRewardToken(address) external;

    function setEcosystemReserve(address) external;

    function registerPositions() external;

    function registerPositions(address[] calldata) external;

    function claimRewards() external;

    function claimRewardsFor(address) external;

    function claimRewardsFor(address, address) external;

    function claimRewardsFor(address, address[] memory) external;

    function accrueRewards(address) external;

    function accrueRewards(address, address) external;

    function viewNewRewardAccrual(
        address,
        address
    ) external view returns (uint256[] memory);

    function viewNewRewardAccrual(
        address,
        address,
        address
    ) external view returns (uint256);
}
