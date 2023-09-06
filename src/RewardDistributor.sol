// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.15;

// contracts
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";
import {GaugeController} from "./GaugeController.sol";

// interfaces
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IPerpetual} from "increment-protocol/interfaces/IPerpetual.sol";
import {IStakingContract} from "increment-protocol/interfaces/IStakingContract.sol";
import {IRewardDistributor} from "./interfaces/IRewardDistributor.sol";

// libraries
import {LibMath} from "increment-protocol/lib/LibMath.sol";

contract RewardDistributor is IRewardDistributor, IStakingContract, GaugeController {
    using SafeERC20 for IERC20Metadata;
    using LibMath for uint256;

    /// @notice Amount of time after which LPs can remove liquidity without penalties
    uint256 public override earlyWithdrawalThreshold;

    /// @notice Rewards accrued and not yet claimed by user
    /// @dev First address is user, second is reward token
    mapping(address => mapping(address => uint256)) public rewardsAccruedByUser;

    /// @notice Last timestamp when user withdrew liquidity from a market
    mapping(address => uint256[]) public lastDepositTimeByUserByMarket;

    /// @notice Latest LP positions per user and market index
    /// @dev Market index is ClearingHouse.perpetuals index
    mapping(address => uint256[]) public lpPositionsPerUser;

    /// @notice Total LP tokens registered for rewards per market per day
    /// @dev Market index is ClearingHouse.perpetuals index
    uint256[] public totalLiquidityPerMarket;

    /// @notice Reward accumulator for total market rewards per reward token
    /// @dev Address is reward token, array index is ClearingHouse.perpetuals index
    mapping(address => uint256[]) public cumulativeRewardPerLpToken;

    /// @notice Timestamp of the most recent update to the reward accumulator
    /// @dev Market index is ClearingHouse.perpetuals index
    uint256[] public timeOfLastCumRewardUpdate;

    /// @notice Reward accumulator value per reward token when user rewards were last updated
    /// @dev First address is user, second is reward token, array index is ClearingHouse.perpetuals index
    mapping(address => mapping(address => uint256[])) public cumulativeRewardPerLpTokenPerUser;

    error InvalidMarketIndex(uint256 index, uint256 maxIndex);
    error NoRewardsToClaim(address user);
    error PositionAlreadyRegistered(address lp, uint256 marketIndex, uint256 position);
    error EarlyRewardAccrual(address user, uint256 marketIndex, uint256 claimAllowedTimestamp);
    error LpPositionMismatch(address lp, uint256 marketIndex, uint256 prevPosition, uint256 newPosition);

    constructor(
        uint256 _initialInflationRate,
        uint256 _maxRewardTokens,
        uint256 _maxInflationRate,
        uint256 _initialReductionFactor,
        uint256 _minReductionFactor,
        address _rewardToken, 
        address _clearingHouse,
        uint256 _earlyWithdrawalThreshold
    ) GaugeController(
        _rewardToken,
        _maxRewardTokens,
        _initialInflationRate, 
        _maxInflationRate,
        _initialReductionFactor, 
        _minReductionFactor,
        _clearingHouse
    ) {
        // rewardToken = IERC20Metadata(_rewardToken);
        earlyWithdrawalThreshold = _earlyWithdrawalThreshold;
    }

    /* ****************** */
    /*   Reward Accrual   */
    /* ****************** */

    /// Updates the reward accumulator for a given market
    /// @dev Executes when any of the following variables are changed: inflationRate, gaugeWeights
    /// @param idx Index of the perpetual market in the ClearingHouse
    function updateMarketRewards(uint256 idx) public override nonReentrant {
        uint256 liquidity = totalLiquidityPerMarket[idx];
        for(uint256 i; i < rewardTokens.length; ++i) {
            address token = rewardTokens[i];
            RewardInfo memory rewardInfo = rewardInfoByToken[token];
            uint256 deltaTime = block.timestamp - timeOfLastCumRewardUpdate[idx];
            uint256 totalTimeElapsed = block.timestamp - rewardInfo.initialTimestamp;
            // Calculate the new cumRewardPerLpToken by adding (inflationRatePerSecond x guageWeight x deltaTime) / liquidity to the previous cumRewardPerLpToken
            uint256 inflationRatePerSecond = rewardInfo.inflationRate / 365 days 
                                           / (rewardInfo.reductionFactor ^ (totalTimeElapsed / 365 days));
            cumulativeRewardPerLpToken[token][idx] += (
                inflationRatePerSecond * rewardInfo.gaugeWeights[idx] / 10000 * deltaTime * 1e18
            ) / liquidity;
        }
        // Set timeOfLastCumRewardUpdate to the currentTime
        timeOfLastCumRewardUpdate[idx] = block.timestamp;
    }

    /// Accrues rewards and updates the stored LP position of a user and the total LP of a market
    /// @dev Executes whenever a user's liquidity is updated for any reason
    /// @param idx Index of the perpetual market in the ClearingHouse
    /// @param user Address of the liquidity provier
    function updateStakingPosition(uint256 idx, address user) external override nonReentrant onlyClearingHouse {
        if(idx >= clearingHouse.getNumMarkets()) revert InvalidMarketIndex(idx, clearingHouse.getNumMarkets());
        updateMarketRewards(idx);
        IPerpetual perp = clearingHouse.perpetuals(idx);
        uint256 prevLpPosition = lpPositionsPerUser[user][idx];
        uint256 newLpPosition = perp.getLpLiquidity(user);
        for(uint256 i; i < rewardTokens.length; ++i) {
            address token = rewardTokens[i];
            /// newRewards = user.lpBalance x (global.cumRewardPerLpToken - user.cumRewardPerLpToken)
            uint256 newRewards = prevLpPosition * (
                cumulativeRewardPerLpToken[token][idx] - cumulativeRewardPerLpTokenPerUser[user][token][idx]
            );
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
            rewardsAccruedByUser[user][token] += newRewards;
            cumulativeRewardPerLpTokenPerUser[user][token][idx] = cumulativeRewardPerLpToken[token][idx];
            emit RewardAccrued(user, token, address(perp), newRewards);
        }
        lpPositionsPerUser[user][idx] = newLpPosition;
    }

    /* ****************** */
    /*    External User   */
    /* ****************** */

    /// Fetches and stores the caller's LP positions and updates the total liquidity in each market
    /// @dev Can only be called once per user, only necessary if user was an LP prior to this contract's deployment
    function registerPositions() external nonReentrant {
        uint256 numMarkets = clearingHouse.getNumMarkets();
        for(uint i; i < numMarkets; ++i) {
            if(lpPositionsPerUser[msg.sender][i] != 0) revert PositionAlreadyRegistered(msg.sender, i, lpPositionsPerUser[msg.sender][i]);
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
            if(idx >= clearingHouse.getNumMarkets()) revert InvalidMarketIndex(idx, clearingHouse.getNumMarkets());
            if(lpPositionsPerUser[msg.sender][idx] != 0) revert PositionAlreadyRegistered(msg.sender, idx, lpPositionsPerUser[msg.sender][idx]);
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
        for (uint i; i < rewardTokens.length; ++i) {
            address token = rewardTokens[i];
            uint256 rewards = rewardsAccruedByUser[user][token];
            if(rewards == 0) revert NoRewardsToClaim(user);
            rewardsAccruedByUser[user][token] = _distributeReward(token, user, rewards);
            emit RewardClaimed(user, token, rewards);
        }
    }

    function paused() public view override returns (bool) {
        return super.paused() || Pausable(address(clearingHouse)).paused();
    }


    /* ****************** */
    /*      Internal      */
    /* ****************** */

    function _accrueRewards(uint256 idx, address user) internal {
        // Used to update rewards before claiming them, assuming LP position hasn't changed
        // Updating rewards due to changes in LP position is handled by updateStakingPosition
        if(idx >= clearingHouse.getNumMarkets()) revert InvalidMarketIndex(idx, clearingHouse.getNumMarkets());
        if(
            block.timestamp < lastDepositTimeByUserByMarket[user][idx] + earlyWithdrawalThreshold
        ) revert EarlyRewardAccrual(user, idx, lastDepositTimeByUserByMarket[user][idx] + earlyWithdrawalThreshold);
        IPerpetual perp = clearingHouse.perpetuals(idx);
        uint256 lpPosition = lpPositionsPerUser[user][idx];
        if(lpPosition != perp.getLpLiquidity(user)) revert LpPositionMismatch(user, idx, lpPosition, perp.getLpLiquidity(user));
        for(uint i; i < rewardTokens.length; ++i) {
            address token = rewardTokens[i];
            uint256 newRewards = lpPosition * (
                cumulativeRewardPerLpToken[token][idx] - cumulativeRewardPerLpTokenPerUser[user][token][idx]
            );
            rewardsAccruedByUser[user][token] += newRewards;
            cumulativeRewardPerLpTokenPerUser[user][token][idx] = cumulativeRewardPerLpToken[token][idx];
            emit RewardAccrued(user, token, address(perp), newRewards);
        }
    }

    function _distributeReward(address _token, address _to, uint256 _amount) internal returns (uint256) {
        uint256 rewardsRemaining = _rewardTokenBalance(_token);
        if (_amount > 0 && _amount <= rewardsRemaining) {
            IERC20Metadata rewardToken = IERC20Metadata(_token);
            rewardToken.safeTransfer(_to, _amount);
            return 0;
        }
        return _amount;
    }

    function _rewardTokenBalance(address _token) internal view returns (uint256) {
        IERC20Metadata rewardToken = IERC20Metadata(_token);
        return rewardToken.balanceOf(address(this));
    }
}
