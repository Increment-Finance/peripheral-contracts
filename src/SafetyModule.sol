// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.16;

import {ISafetyModule} from "./interfaces/ISafetyModule.sol";
import {IStakedToken} from "./interfaces/IStakedToken.sol";
import {RewardDistributor} from "./RewardDistributor.sol";
import {LibMath} from "@increment/lib/LibMath.sol";

contract SafetyModule is ISafetyModule, RewardDistributor {
    using LibMath for uint256;

    address public vault;
    address public auctionModule;
    IStakedToken[] public stakingTokens;

    /// @notice The maximum reward multiplier, scaled by 1e18
    uint256 public maxRewardMultiplier;

    /// @notice The smoothing value, scaled by 1e18
    /// @dev The higher the value, the slower the multiplier approaches its max
    uint256 public smoothingValue;

    /// @notice Stores the timestamp of the first deposit or most recent withdrawal
    /// @dev First address is user, second is staking token
    mapping(address => mapping(address => uint256))
        public multiplierStartTimeByUser;

    modifier onlyStakingToken() {
        bool isStakingToken = false;
        for (uint i; i < stakingTokens.length; ++i) {
            if (msg.sender == address(stakingTokens[i])) {
                isStakingToken = true;
                break;
            }
        }
        if (!isStakingToken) revert CallerIsNotStakingToken(msg.sender);
        _;
    }

    constructor(
        address _vault,
        address _auctionModule,
        IStakedToken[] memory _stakingTokens,
        uint256 _maxRewardMultiplier,
        uint256 _smoothingValue,
        uint256 _initialInflationRate,
        uint256 _initialReductionFactor,
        address _rewardToken,
        address _clearingHouse,
        uint256 _earlyWithdrawalThreshold,
        uint16[] memory _initialRewardWeights
    )
        RewardDistributor(
            _initialInflationRate,
            _initialReductionFactor,
            _rewardToken,
            _clearingHouse,
            _earlyWithdrawalThreshold,
            _initialRewardWeights
        )
    {
        vault = _vault;
        auctionModule = _auctionModule;
        stakingTokens = _stakingTokens;
        maxRewardMultiplier = _maxRewardMultiplier;
        smoothingValue = _smoothingValue;
    }

    /* ****************** */
    /*      Markets       */
    /* ****************** */

    /// @inheritdoc RewardDistributor
    function getNumMarkets() public view virtual override returns (uint256) {
        return stakingTokens.length;
    }

    /// @inheritdoc RewardDistributor
    function getMarketAddress(
        uint256 index
    ) public view virtual override returns (address) {
        return address(stakingTokens[index]);
    }

    /// @inheritdoc RewardDistributor
    function getMarketIdx(
        uint256 i
    ) public view virtual override returns (uint256) {
        if (i >= getNumMarkets())
            revert RewardDistributor_InvalidMarketIndex(i, getNumMarkets());
        return i;
    }

    /// @inheritdoc RewardDistributor
    function getAllowlistIdx(
        uint256 idx
    ) public view virtual override returns (uint256) {
        return getMarketIdx(idx);
    }

    /// Returns the current position of the user in the market (i.e., perpetual market)
    /// @param lp Address of the user
    /// @param market Address of the market
    /// @return Current position of the user in the market
    function getCurrentPosition(
        address lp,
        address market
    ) public view virtual override returns (uint256) {
        return IStakedToken(market).balanceOf(lp);
    }

    /* ****************** */
    /*   Reward Accrual   */
    /* ****************** */

    /// Accrues rewards and updates the stored stake position of a user and the total tokens staked
    /// @dev Executes whenever a user's stake is updated for any reason
    /// @param idx Index of the staking token in stakingTokens
    /// @param user Address of the staker
    function updateStakingPosition(
        uint256 idx,
        address user
    ) external virtual override nonReentrant onlyStakingToken {
        if (idx >= getNumMarkets())
            revert RewardDistributor_InvalidMarketIndex(idx, getNumMarkets());
        updateMarketRewards(idx);
        address market = getMarketAddress(idx);
        uint256 prevPosition = lpPositionsPerUser[user][market];
        uint256 newPosition = getCurrentPosition(user, market);
        totalLiquidityPerMarket[market] =
            totalLiquidityPerMarket[market] +
            newPosition -
            prevPosition;
        for (uint256 i; i < rewardTokensPerMarket[market].length; ++i) {
            address token = rewardTokensPerMarket[market][i];
            /// newRewards = user.lpBalance x (global.cumRewardPerLpToken - user.cumRewardPerLpToken)
            /// newRewards does not include multiplier yet
            uint256 newRewards = prevPosition *
                (cumulativeRewardPerLpToken[token][market] -
                    cumulativeRewardPerLpTokenPerUser[user][token][market]);
            uint256 rewardMultiplier = computeRewardMultiplier(user, market);
            if (newPosition < prevPosition || prevPosition == 0) {
                // Removed stake or staked for the first time - need to reset multiplier
                multiplierStartTimeByUser[user][market] = block.timestamp;
            }
            rewardsAccruedByUser[user][token] += newRewards * rewardMultiplier;
            totalUnclaimedRewards[token] += newRewards * rewardMultiplier;
            cumulativeRewardPerLpTokenPerUser[user][token][
                market
            ] = cumulativeRewardPerLpToken[token][market];
            emit RewardAccruedToUser(user, token, address(market), newRewards);
        }
        // TODO: What if a staking token is removed?
        lpPositionsPerUser[user][market] = newPosition;
    }

    /* ******************* */
    /*  Reward Multiplier  */
    /* ******************* */

    /// Computes the user's reward multiplier for the given staking token
    /// @notice Based on the max multiplier, smoothing factor and time since last withdrawal (or first deposit)
    /// @param _user Address of the staker
    /// @param _stakingToken Address of staking token earning rewards
    function computeRewardMultiplier(
        address _user,
        address _stakingToken
    ) public view returns (uint256) {
        uint256 startTime = multiplierStartTimeByUser[_user][_stakingToken];
        uint256 timeDelta = block.timestamp - startTime;
        uint256 deltaDays = timeDelta.wadDiv(1 days);
        /**
         * Multiplier formula:
         *   maxRewardMultiplier - 1 / ((1 / smoothingValue) * deltaDays + (1 / (maxRewardMultiplier - 1)))
         * = maxRewardMultiplier - smoothingValue / (deltaDays + (smoothingValue / (maxRewardMultiplier - 1)))
         * = maxRewardMultiplier - (smoothingValue * (maxRewardMultiplier - 1)) / ((deltaDays * (maxRewardMultiplier - 1)) + smoothingValue)
         */
        return
            maxRewardMultiplier -
            (smoothingValue * (maxRewardMultiplier - 1e18)) /
            ((deltaDays * (maxRewardMultiplier - 1e18)) /
                1e18 +
                smoothingValue);
    }

    /* ****************** */
    /*     Governance     */
    /* ****************** */

    function setMaxRewardMultiplier(
        uint256 _maxRewardMultiplier
    ) external onlyRole(GOVERNANCE) {
        maxRewardMultiplier = _maxRewardMultiplier;
    }

    function setSmoothingValue(
        uint256 _smoothingValue
    ) external onlyRole(GOVERNANCE) {
        smoothingValue = _smoothingValue;
    }

    function addStakingToken(
        IStakedToken _stakingToken
    ) external onlyRole(GOVERNANCE) {
        for (uint i; i < stakingTokens.length; ++i) {
            if (address(stakingTokens[i]) == address(_stakingToken))
                revert StakingTokenAlreadyRegistered(address(_stakingToken));
        }
        stakingTokens.push(_stakingToken);
    }
}
