// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.15;

// contracts
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IncreAccessControl} from "increment-protocol/utils/IncreAccessControl.sol";
import {GaugeController} from "./GaugeController.sol";

// interfaces
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IClearingHouse} from "increment-protocol/interfaces/IClearingHouse.sol";
import {IPerpetual} from "increment-protocol/interfaces/IPerpetual.sol";
import {IInsurance} from "increment-protocol/interfaces/IInsurance.sol";
import {IVault} from "increment-protocol/interfaces/IVault.sol";
import {ICryptoSwap} from "increment-protocol/interfaces/ICryptoSwap.sol";
import {IStakingContract} from "increment-protocol/interfaces/IStakingContract.sol";
import {IRewardDistributor} from "./interfaces/IRewardDistributor.sol";

// libraries
import {LibMath} from "increment-protocol/lib/LibMath.sol";
import {LibPerpetual} from "increment-protocol/lib/LibPerpetual.sol";
import {LibReserve} from "increment-protocol/lib/LibReserve.sol";

contract RewardDistributor is IRewardDistributor, IStakingContract, GaugeController {
    using SafeERC20 for IERC20Metadata;
    using LibMath for uint256;

    /// @notice Rewards accrued and not yet claimed by user
    mapping(address => uint256) public rewardsAccruedByUser;

    /// @notice Last timestamp when user accrued rewards from a market
    mapping(address => mapping(uint256 => uint256)) public lastAccrualTimeByUserByMarket;

    /// @notice Last timestamp when user withdrew liquidity from a market
    mapping(address => mapping(uint256 => uint256)) public lastWithdrawalTimeByUserByMarket;

    /// @notice Latest LP positions per user and market index
    /// @dev Market index is ClearingHouse.perpetuals index
    mapping(address => uint256[]) public lpPositionsPerUser;

    /// @notice Total LP tokens registered for rewards per market
    /// @dev Market index is ClearingHouse.perpetuals index
    mapping(uint256 => uint256) public totalLiquidityPerMarket;

    /// @notice INCR token used for rewards
    IERC20Metadata public override rewardToken;

    /// @notice Amount of time after which LPs can remove liquidity without penalties
    uint256 public override earlyWithdrawalThreshold;

    constructor(
        uint256 _initialInflationRate,
        uint256 _initialReductionFactor,
        address _rewardToken, 
        address _clearingHouse,
        uint256 _earlyWithdrawalThreshold
    ) GaugeController(
        _initialInflationRate, 
        _initialReductionFactor, 
        _clearingHouse
    ) {
        rewardToken = IERC20Metadata(_rewardToken);
        earlyWithdrawalThreshold = _earlyWithdrawalThreshold;
    }

    /* ****************** */
    /*   Reward Accrual   */
    /* ****************** */

    /// Accrues rewards and updates the stored LP position of a user and the total LP of a market
    /// @param idx Index of the perpetual market in the ClearingHouse
    /// @param user Address of the liquidity provier
    function updateStakingPosition(uint256 idx, address user) external override nonReentrant onlyClearingHouse {
        require(idx < clearingHouse.getNumMarkets(), "RewardDistributor: Invalid perpetual index");
        IPerpetual perp = clearingHouse.perpetuals(idx);
        uint256 prevLpPosition = lpPositionsPerUser[user][idx];
        uint256 newLpPosition = perp.getLpLiquidity(user);
        uint256 prevTotalLiquidity = totalLiquidityPerMarket[idx];
        uint256 newRewards;
        if (newLpPosition >= prevLpPosition) {
            // Added liquidity
            newRewards = _calcUserRewards(
                user,
                idx,
                prevLpPosition,
                prevTotalLiquidity
            );
            totalLiquidityPerMarket[idx] += newLpPosition - prevLpPosition;
        } else {
            // Removed liquidity - need to check if within early withdrawal threshold
            if (block.timestamp - lastWithdrawalTimeByUserByMarket[user][idx] < earlyWithdrawalThreshold) {
                // Early withdrawal - apply penalty

            } else {
                // Not an early withdrawal - no penalty
                newRewards = _calcUserRewards(
                    user,
                    idx,
                    prevLpPosition,
                    prevTotalLiquidity
                );
            }
            totalLiquidityPerMarket[idx] -= prevLpPosition - newLpPosition;
            lastWithdrawalTimeByUserByMarket[user][idx] = block.timestamp;
        }
        rewardsAccruedByUser[user] += newRewards;
        lpPositionsPerUser[user][idx] = newLpPosition;
        lastAccrualTimeByUserByMarket[user][idx] = block.timestamp;
    }

    /// Accrues rewards for a user in a market
    /// @dev Requires that the user's LP position hasn't changed since the last call to updateStakingPosition
    /// @param idx Index of the perpetual market in the ClearingHouse
    /// @param user Address of the liquidity provier
    function accrueRewards(uint256 idx, address user) public override {
        require(idx < clearingHouse.getNumMarkets(), "RewardDistributor: Invalid perpetual index");
        require(
            block.timestamp >= lastWithdrawalTimeByUserByMarket[user][idx] + earlyWithdrawalThreshold,
            "RewardDistributor: Cannot manually accrue rewards for user before early withdrawal threshold"
        );
        IPerpetual perp = clearingHouse.perpetuals(idx);
        uint256 lpPosition = lpPositionsPerUser[user][idx];
        require(lpPosition == perp.getLpLiquidity(user), "RewardDistributor: LP position should not have changed");
        uint256 totalLiquidity = totalLiquidityPerMarket[idx];
        uint256 newRewards = _calcUserRewards(
            user,
            idx,
            lpPosition,
            totalLiquidity
        );
        rewardsAccruedByUser[user] += newRewards;
        lastAccrualTimeByUserByMarket[user][idx] = block.timestamp;
    }

    /* ****************** */
    /*    External User   */
    /* ****************** */

    /// Fetches and stores the caller's LP positions and updates the total liquidity in each market
    /// @dev Can only be called once per user, only necessary if user was an LP prior to this contract's deployment
    function registerPositions() external nonReentrant {
        uint256 numMarkets = clearingHouse.getNumMarkets();
        for(uint i; i < numMarkets; ++i) {
            require(i < clearingHouse.getNumMarkets(), "RewardDistributor: Invalid perpetual index");
            require(lpPositionsPerUser[msg.sender][i] == 0, "RewardDistributor: Position already registered");
            IPerpetual perp = clearingHouse.perpetuals(i);
            uint256 lpPosition = perp.getLpLiquidity(msg.sender);
            lpPositionsPerUser[msg.sender][i] = lpPosition;
            totalLiquidityPerMarket[i] += lpPosition;
        }
    }

    /// Fetches and stores the caller's LP positions and updates the total liquidity in each market
    /// @dev Can only be called once per user, only necessary if user was an LP prior to this contract's deployment
    /// @param _marketIndexes Indexes of the perpetual markets in the ClearingHouse to sync with
    function registerPositions(uint256[] calldata _marketIndexes) external nonReentrant {
        for(uint i; i < _marketIndexes.length; ++i) {
            uint256 idx = _marketIndexes[i];
            require(idx < clearingHouse.getNumMarkets(), "RewardDistributor: Invalid perpetual index");
            require(lpPositionsPerUser[msg.sender][idx] == 0, "RewardDistributor: Position already registered");
            IPerpetual perp = clearingHouse.perpetuals(idx);
            uint256 lpPosition = perp.getLpLiquidity(msg.sender);
            lpPositionsPerUser[msg.sender][idx] = lpPosition;
            totalLiquidityPerMarket[idx] += lpPosition;
        }
    }

    /// Accrues and then distributes rewards for all markets to the caller
    function claimRewards() public override {
        claimRewardsFor(msg.sender);
    }

    /// Accrues and then distributes rewards for all markets to the given user
    /// @param user Address of the user to claim rewards for
    function claimRewardsFor(address user) public override nonReentrant whenNotPaused {
        for (uint i; i < clearingHouse.getNumMarkets(); ++i) {
            accrueRewards(i, user);
        }
        uint256 rewards = rewardsAccruedByUser[user];
        require(rewards > 0, "RewardDistributor: no rewards to claim");
        rewardsAccruedByUser[user] = _distributeReward(user, rewards);
        emit RewardClaimed(user, rewards);
    }


    /* ****************** */
    /*      Internal      */
    /* ****************** */

    function _distributeReward(address _to, uint256 _amount) internal returns (uint256) {
        uint256 rewardsRemaining = _rewardTokenBalance();
        if (_amount > 0 && _amount <= rewardsRemaining) {
            rewardToken.safeTransfer(_to, _amount);
            return 0;
        }
        return _amount;
    }

    function _calcUserRewards(
        address lp, 
        uint256 idx, 
        uint256 position, 
        uint256 totalLiquidity
    ) internal view returns (uint256) {
        address perp = address(clearingHouse.perpetuals(idx));
        uint256 percentOfLP = position * 10000 / totalLiquidity;    // Percentauge of total LP tokens as BPS
        uint256 lastAccrualTimestamp = lastAccrualTimeByUserByMarket[lp][idx];
        uint256 marketEmissionsSinceLastAccrual = _calcEmmisionsPerGauge(perp, block.timestamp) 
                                                - _calcEmmisionsPerGauge(perp, lastAccrualTimestamp);
        return percentOfLP * marketEmissionsSinceLastAccrual / 10000;
    }

    function _rewardTokenBalance() internal view returns (uint256) {
        return rewardToken.balanceOf(address(this));
    }
}
