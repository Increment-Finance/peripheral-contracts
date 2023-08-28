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

    /// @notice INCR token used for rewards
    IERC20Metadata public override rewardToken;

    /// @notice Amount of time after which LPs can remove liquidity without penalties
    uint256 public override earlyWithdrawalThreshold;

    /// @notice Rewards accrued and not yet claimed by user
    mapping(address => uint256) public rewardsAccruedByUser;

    /// @notice Last timestamp when user withdrew liquidity from a market
    mapping(address => uint256[]) public lastDepositTimeByUserByMarket;

    /// @notice Latest LP positions per user and market index
    /// @dev Market index is ClearingHouse.perpetuals index
    mapping(address => uint256[]) public lpPositionsPerUser;

    /// @notice Total LP tokens registered for rewards per market per day
    /// @dev Market index is ClearingHouse.perpetuals index
    uint256[] public totalLiquidityPerMarket;

    /// @notice Reward accumulator for total market rewards
    /// @dev Market index is ClearingHouse.perpetuals index
    uint256[] public cumulativeRewardPerLpToken;

    /// @notice Timestamp of the most recent update to the reward accumulator
    /// @dev Market index is ClearingHouse.perpetuals index
    uint256[] public timeOfLastCumRewardUpdate;

    /// @notice Reward accumulator value when user rewards were last updated
    /// @dev Market index is ClearingHouse.perpetuals index
    mapping(address => uint256[]) public cumulativeRewardPerLpTokenPerUser;

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

    /// Updates the reward accumulator for a given market
    /// @dev Executes when any of the following variables are changed: inflationRate, gaugeWeights
    /// @param idx Index of the perpetual market in the ClearingHouse
    function updateMarketRewards(uint256 idx) public override nonReentrant {
        uint256 deltaTime = block.timestamp - timeOfLastCumRewardUpdate[idx];
        uint256 totalTimeElapsed = block.timestamp - initialTimestamp;
        // Calculate the new cumRewardPerLpToken by adding (inflationRatePerSecond x guageWeight x deltaTime) / liquidity to the previous cumRewardPerLpToken
        uint256 inflationRatePerSecond = inflationRate / 365 days / (reductionFactor ^ (totalTimeElapsed / 365 days));
        uint256 liquidity = totalLiquidityPerMarket[idx];
        address gauge = address(clearingHouse.perpetuals(idx));
        cumulativeRewardPerLpToken[idx] += (inflationRatePerSecond * gaugeWeights[gauge] / 10000 * deltaTime * 1e18) / liquidity;
        // Set timeOfLastCumRewardUpdate to the currentTime
        timeOfLastCumRewardUpdate[idx] = block.timestamp;
    }

    /// Accrues rewards and updates the stored LP position of a user and the total LP of a market
    /// @dev Executes whenever a user's liquidity is updated for any reason
    /// @param idx Index of the perpetual market in the ClearingHouse
    /// @param user Address of the liquidity provier
    function updateStakingPosition(uint256 idx, address user) external override nonReentrant onlyClearingHouse {
        require(idx < clearingHouse.getNumMarkets(), "RewardDistributor: Invalid perpetual index");
        updateMarketRewards(idx);
        IPerpetual perp = clearingHouse.perpetuals(idx);
        uint256 prevLpPosition = lpPositionsPerUser[user][idx];
        uint256 newLpPosition = perp.getLpLiquidity(user);
        /// newRewards = user.lpBalance x (global.cumRewardPerLpToken - user.cumRewardPerLpToken)
        uint256 newRewards = prevLpPosition * (cumulativeRewardPerLpToken[idx] - cumulativeRewardPerLpTokenPerUser[user][idx]);
        if (newLpPosition >= prevLpPosition) {
            // Added liquidity
            if (lastDepositTimeByUserByMarket[user][idx] == 0) {
                lastDepositTimeByUserByMarket[user][idx] = block.timestamp;
            }
        } else {
            // Removed liquidity - need to check if within early withdrawal threshold
            if (block.timestamp - lastDepositTimeByUserByMarket[user][idx] < earlyWithdrawalThreshold) {
                // Early withdrawal - apply penalty
                newRewards -= newRewards * (prevLpPosition - newLpPosition) / prevLpPosition;
            } 
            if (newLpPosition > 0) {
                // Reset timer
                lastDepositTimeByUserByMarket[user][idx] = block.timestamp;
            } else {
                // Full withdrawal, so next deposit is an initial deposit
                lastDepositTimeByUserByMarket[user][idx] = 0;
            }
        }
        rewardsAccruedByUser[user] += newRewards;
        lpPositionsPerUser[user][idx] = newLpPosition;
        cumulativeRewardPerLpTokenPerUser[user][idx] = cumulativeRewardPerLpToken[idx];
    }

    /* ****************** */
    /*    External User   */
    /* ****************** */

    /// Fetches and stores the caller's LP positions and updates the total liquidity in each market
    /// @dev Can only be called once per user, only necessary if user was an LP prior to this contract's deployment
    function registerPositions() external nonReentrant {
        uint256 numMarkets = clearingHouse.getNumMarkets();
        for(uint i; i < numMarkets; ++i) {
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
            _accrueRewards(i, user);
        }
        uint256 rewards = rewardsAccruedByUser[user];
        require(rewards > 0, "RewardDistributor: no rewards to claim");
        rewardsAccruedByUser[user] = _distributeReward(user, rewards);
        emit RewardClaimed(user, rewards);
    }


    /* ****************** */
    /*      Internal      */
    /* ****************** */

    function _accrueRewards(uint256 idx, address user) internal {
        // Used to update rewards before claiming them, assuming LP position hasn't changed
        // Updating rewards due to changes in LP position is handled by updateStakingPosition
        require(idx < clearingHouse.getNumMarkets(), "RewardDistributor: Invalid perpetual index");
        require(
            block.timestamp >= lastDepositTimeByUserByMarket[user][idx] + earlyWithdrawalThreshold,
            "RewardDistributor: Cannot manually accrue rewards for user before early withdrawal threshold"
        );
        IPerpetual perp = clearingHouse.perpetuals(idx);
        uint256 lpPosition = lpPositionsPerUser[user][idx];
        require(lpPosition == perp.getLpLiquidity(user), "RewardDistributor: LP position should not have changed");
        uint256 newRewards = lpPosition * (cumulativeRewardPerLpToken[idx] - cumulativeRewardPerLpTokenPerUser[user][idx]);
        rewardsAccruedByUser[user] += newRewards;
        cumulativeRewardPerLpTokenPerUser[user][idx] = cumulativeRewardPerLpToken[idx];
    }

    function _distributeReward(address _to, uint256 _amount) internal returns (uint256) {
        uint256 rewardsRemaining = _rewardTokenBalance();
        if (_amount > 0 && _amount <= rewardsRemaining) {
            rewardToken.safeTransfer(_to, _amount);
            return 0;
        }
        return _amount;
    }

    function _rewardTokenBalance() internal view returns (uint256) {
        return rewardToken.balanceOf(address(this));
    }
}
