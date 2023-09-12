// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.15;

import {ISafetyModule} from "./interfaces/ISafetyModule.sol";
import {IStakedToken} from "./interfaces/IStakedToken.sol";
import {RewardDistributor} from "./RewardDistributor.sol";

contract SafetyModule is ISafetyModule, RewardDistributor {
    address public vault;
    address public auctionModule;
    IStakedToken[] public stakingTokens;
    uint256 public maxRewardMultiplier;
    uint256 public smoothingValue;

    mapping(address => uint256) public lastWithdrawalTimeByUser;

    error CallerIsNotStakingToken(address caller);

    modifier onlyStakingToken() {
        bool isStakingToken = false;
        for(uint i; i < stakingTokens.length; ++i) {
            if(msg.sender == address(stakingTokens[i])) {
                isStakingToken = true;
                break;
            }
        }
        if(!isStakingToken) revert CallerIsNotStakingToken(msg.sender);
        _;
    }

    constructor(
        address _vault,
        address _auctionModule,
        IStakedToken[] memory _stakingTokens,
        uint256 _maxRewardMultiplier,
        uint256 _smoothingValue,
        uint256 _initialInflationRate,
        uint256 _maxRewardTokens,
        uint256 _maxInflationRate,
        uint256 _initialReductionFactor,
        uint256 _minReductionFactor,
        address _rewardToken, 
        address _clearingHouse,
        uint256 _earlyWithdrawalThreshold,
        uint16[] memory _initialGaugeWeights
    ) RewardDistributor(
        _initialInflationRate,
        _maxRewardTokens,
        _maxInflationRate,
        _initialReductionFactor,
        _minReductionFactor,
        _rewardToken,
        _clearingHouse,
        _earlyWithdrawalThreshold,
        _initialGaugeWeights
    ) {
        vault = _vault;
        auctionModule = _auctionModule;
        stakingTokens = _stakingTokens;
        maxRewardMultiplier = _maxRewardMultiplier;
        smoothingValue = _smoothingValue;
    }

    /* ****************** */
    /*       Gauges       */
    /* ****************** */

    /// @inheritdoc RewardDistributor
    function getNumGauges() public view virtual override returns (uint256) {
        return stakingTokens.length;
    }

    /// @inheritdoc RewardDistributor
    function getGaugeAddress(uint256 index) public view virtual override returns (address) {
        return address(stakingTokens[index]);
    }

    /// Returns the current position of the user in the gauge (i.e., perpetual market)
    /// @param lp Address of the user
    /// @param gauge Address of the gauge
    /// @return Current position of the user in the gauge
    function getCurrentPosition(address lp, address gauge) public view virtual override returns (uint256) {
        return IStakedToken(gauge).balanceOf(lp);
    }

    /* ****************** */
    /*   Reward Accrual   */
    /* ****************** */

    /// Accrues rewards and updates the stored stake position of a user and the total tokens staked
    /// @dev Executes whenever a user's stake is updated for any reason
    /// @param idx Index of the staking token in stakingTokens
    /// @param user Address of the staker
    function updateStakingPosition(uint256 idx, address user) external virtual override nonReentrant onlyStakingToken {
        if(idx >= getNumGauges()) revert InvalidMarketIndex(idx, getNumGauges());
        updateMarketRewards(idx);
        address gauge = getGaugeAddress(idx);
        uint256 prevPosition = lpPositionsPerUser[user][idx];
        uint256 newPosition = getCurrentPosition(user, gauge);
        for(uint256 i; i < rewardTokens.length; ++i) {
            address token = rewardTokens[i];
            /// newRewards = user.lpBalance x (global.cumRewardPerLpToken - user.cumRewardPerLpToken)
            /// newRewards does not include multiplier yet
            uint256 newRewards = prevPosition * (
                cumulativeRewardPerLpToken[token][idx] - cumulativeRewardPerLpTokenPerUser[user][token][idx]
            );
            uint256 rewardMultiplier = computeRewardMultiplier(user, address(stakingTokens[idx]));
            if (newPosition < prevPosition || prevPosition == 0) {
                // Removed stake or staked for the first time - need to reset multiplier
                lastWithdrawalTimeByUser[user] = block.timestamp;
            }
            rewardsAccruedByUser[user][token] += newRewards * rewardMultiplier;
            totalUnclaimedRewards[token] += newRewards * rewardMultiplier;
            cumulativeRewardPerLpTokenPerUser[user][token][idx] = cumulativeRewardPerLpToken[token][idx];
            emit RewardAccrued(user, token, address(gauge), newRewards);
        }
        // TODO: What if a staking token is removed? Can we still use a mapping(address => uint256[])?
        lpPositionsPerUser[user][idx] = newPosition;
    }

    /* ******************* */
    /*  Reward Multiplier  */
    /* ******************* */

    function computeRewardMultiplier(address _user, address _stakingToken) public view returns (uint256) {

    }

    /* ****************** */
    /*     Governance     */
    /* ****************** */

    function setMaxRewardMultiplier(uint256 _maxRewardMultiplier) external onlyRole(GOVERNANCE) {
        maxRewardMultiplier = _maxRewardMultiplier;
    }

    function setSmoothingValue(uint256 _smoothingValue) external onlyRole(GOVERNANCE) {
        smoothingValue = _smoothingValue;
    }
}