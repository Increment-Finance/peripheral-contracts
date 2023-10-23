// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.16;

// contracts
import {RewardDistributor} from "./RewardDistributor.sol";

// interfaces
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {ISafetyModule, IStakingContract} from "./interfaces/ISafetyModule.sol";
import {IStakedToken} from "./interfaces/IStakedToken.sol";

// libraries
import {LibMath} from "@increment/lib/LibMath.sol";
import {PRBMathUD60x18} from "prb-math/contracts/PRBMathUD60x18.sol";

contract SafetyModule is ISafetyModule, RewardDistributor {
    using LibMath for uint256;
    using PRBMathUD60x18 for uint256;

    address public vault;
    address public auctionModule;
    IStakedToken[] public stakingTokens;

    /// @notice The maximum percentage of user funds that can be sold at auction, normalized to 1e18
    uint256 public maxPercentUserLoss;

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
        if (!isStakingToken)
            revert SafetyModule_CallerIsNotStakingToken(msg.sender);
        _;
    }

    constructor(
        address _vault,
        address _auctionModule,
        uint256 _maxPercentUserLoss,
        uint256 _maxRewardMultiplier,
        uint256 _smoothingValue,
        address _tokenVault
    ) RewardDistributor(_tokenVault) {
        vault = _vault;
        auctionModule = _auctionModule;
        maxPercentUserLoss = _maxPercentUserLoss;
        maxRewardMultiplier = _maxRewardMultiplier;
        smoothingValue = _smoothingValue;
        emit MaxPercentUserLossUpdated(_maxPercentUserLoss);
        emit MaxRewardMultiplierUpdated(_maxRewardMultiplier);
        emit SmoothingValueUpdated(_smoothingValue);
    }

    /* ****************** */
    /*      Markets       */
    /* ****************** */

    /// @inheritdoc RewardDistributor
    function getNumMarkets() public view virtual override returns (uint256) {
        return stakingTokens.length;
    }

    /// @inheritdoc RewardDistributor
    function getMaxMarketIdx() public view override returns (uint256) {
        return stakingTokens.length - 1;
    }

    /// @inheritdoc RewardDistributor
    function getMarketAddress(
        uint256 index
    ) public view virtual override returns (address) {
        if (index > getMaxMarketIdx())
            revert RewardDistributor_InvalidMarketIndex(
                index,
                getMaxMarketIdx()
            );
        return address(stakingTokens[index]);
    }

    /// @inheritdoc RewardDistributor
    function getMarketIdx(
        uint256 i
    ) public view virtual override returns (uint256) {
        if (i > getMaxMarketIdx())
            revert RewardDistributor_InvalidMarketIndex(i, getMaxMarketIdx());
        return i;
    }

    function getStakingTokenIdx(address token) public view returns (uint256) {
        for (uint256 i; i < stakingTokens.length; ++i) {
            if (address(stakingTokens[i]) == token) return i;
        }
        revert SafetyModule_InvalidStakingToken(token);
    }

    /// @inheritdoc RewardDistributor
    function getAllowlistIdx(
        uint256 idx
    ) public view virtual override returns (uint256) {
        return getMarketIdx(idx);
    }

    /// Returns the user's staking token balance
    /// @param staker Address of the user
    /// @param token Address of the staking token
    /// @return Current balance of the user in the staking token
    function getCurrentPosition(
        address staker,
        address token
    ) public view virtual override returns (uint256) {
        return IStakedToken(token).balanceOf(staker);
    }

    /// Returns the amount of the user's staking tokens that can be sold at auction
    /// in the event of an insolvency in the vault that cannot be covered by the insurance fund
    /// @param staker Address of the user
    /// @param token Address of the staking token
    /// @return Balance of the user multiplied by the maxPercentUserLoss
    function getAuctionableBalance(
        address staker,
        address token
    ) public view virtual returns (uint256) {
        return getCurrentPosition(staker, token).mul(maxPercentUserLoss);
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
    )
        external
        virtual
        override(IStakingContract, RewardDistributor)
        nonReentrant
        onlyStakingToken
    {
        if (idx >= getNumMarkets())
            revert RewardDistributor_InvalidMarketIndex(idx, getMaxMarketIdx());
        updateMarketRewards(idx);
        address market = getMarketAddress(idx);
        uint256 prevPosition = lpPositionsPerUser[user][market];
        uint256 newPosition = getCurrentPosition(user, market);
        totalLiquidityPerMarket[market] =
            totalLiquidityPerMarket[market] +
            newPosition -
            prevPosition;
        uint256 rewardMultiplier = computeRewardMultiplier(user, market);
        for (uint256 i; i < rewardTokensPerMarket[market].length; ++i) {
            address token = rewardTokensPerMarket[market][i];
            /// newRewards = user.lpBalance x (global.cumRewardPerLpToken - user.cumRewardPerLpToken)
            /// newRewards does not include multiplier yet
            uint256 newRewards = prevPosition *
                (cumulativeRewardPerLpToken[token][market] -
                    cumulativeRewardPerLpTokenPerUser[user][token][market]);
            if (newPosition < prevPosition || prevPosition == 0) {
                // Removed stake or staked for the first time - need to reset multiplier
                if (newPosition > 0) {
                    multiplierStartTimeByUser[user][market] = block.timestamp;
                } else {
                    multiplierStartTimeByUser[user][market] = 0;
                }
            }
            cumulativeRewardPerLpTokenPerUser[user][token][
                market
            ] = cumulativeRewardPerLpToken[token][market];
            if (newRewards > 0) {
                rewardsAccruedByUser[user][token] +=
                    newRewards *
                    rewardMultiplier;
                totalUnclaimedRewards[token] += newRewards * rewardMultiplier;
                emit RewardAccruedToUser(
                    user,
                    token,
                    address(market),
                    newRewards
                );
                uint256 rewardTokenBalance = _rewardTokenBalance(token);
                if (totalUnclaimedRewards[token] > rewardTokenBalance) {
                    emit RewardTokenShortfall(
                        token,
                        totalUnclaimedRewards[token] - rewardTokenBalance
                    );
                }
            }
        }
        // TODO: What if a staking token is removed?
        lpPositionsPerUser[user][market] = newPosition;
    }

    /* ****************** */
    /*    External User   */
    /* ****************** */

    function accrueRewards(
        uint256 idx,
        address user
    ) public virtual override nonReentrant {
        address market = getMarketAddress(idx);
        uint256 lpPosition = lpPositionsPerUser[user][market];
        if (lpPosition != getCurrentPosition(user, market))
            // only occurs if the user has a pre-existing balance and has not registered for rewards,
            // since updating stake position calls updateStakingPosition which updates lpPositionsPerUser
            revert RewardDistributor_LpPositionMismatch(
                user,
                idx,
                lpPosition,
                getCurrentPosition(user, market)
            );
        if (totalLiquidityPerMarket[market] == 0) return;
        updateMarketRewards(idx);
        for (uint i; i < rewardTokensPerMarket[market].length; ++i) {
            address token = rewardTokensPerMarket[market][i];
            uint256 newRewards = (lpPosition *
                (cumulativeRewardPerLpToken[token][market] -
                    cumulativeRewardPerLpTokenPerUser[user][token][market])) /
                1e18;
            rewardsAccruedByUser[user][token] += newRewards;
            totalUnclaimedRewards[token] += newRewards;
            cumulativeRewardPerLpTokenPerUser[user][token][
                market
            ] = cumulativeRewardPerLpToken[token][market];
            emit RewardAccruedToUser(user, token, market, newRewards);
        }
    }

    /// Returns the amount of rewards that would be accrued to a user for a given market and reward token
    /// @param idx Index of the staking token in stakingTokens
    /// @param user Address of the user
    /// @param token Address of the reward token
    /// @return Amount of new rewards that would be accrued to the user
    function viewNewRewardAccrual(
        uint256 idx,
        address user,
        address token
    ) public view override returns (uint256) {
        address market = getMarketAddress(idx);
        uint256 lpPosition = lpPositionsPerUser[user][market];
        if (lpPosition != getCurrentPosition(user, market))
            // only occurs if the user has a pre-existing liquidity position and has not registered for rewards,
            // since updating LP position calls updateStakingPosition which updates lpPositionsPerUser
            revert RewardDistributor_LpPositionMismatch(
                user,
                idx,
                lpPosition,
                getCurrentPosition(user, market)
            );
        uint256 liquidity = totalLiquidityPerMarket[market];
        if (timeOfLastCumRewardUpdate[market] == 0)
            revert RewardDistributor_UninitializedStartTime(market);
        uint256 deltaTime = block.timestamp - timeOfLastCumRewardUpdate[market];
        if (liquidity == 0) return 0;
        RewardInfo memory rewardInfo = rewardInfoByToken[token];
        uint256 totalTimeElapsed = block.timestamp -
            rewardInfo.initialTimestamp;
        // Calculate the new cumRewardPerLpToken by adding (inflationRatePerSecond x guageWeight x deltaTime) to the previous cumRewardPerLpToken
        uint256 inflationRate = rewardInfo.initialInflationRate.div(
            rewardInfo.reductionFactor.pow(totalTimeElapsed.div(365 days))
        );
        uint256 newMarketRewards = (((inflationRate *
            rewardInfo.marketWeights[idx]) / 10000) * deltaTime) / 365 days;
        uint256 newCumRewardPerLpToken = cumulativeRewardPerLpToken[token][
            market
        ] + (newMarketRewards * 1e18) / liquidity;
        uint256 newUserRewards = lpPosition.mul(
            (newCumRewardPerLpToken -
                cumulativeRewardPerLpTokenPerUser[user][token][market])
        );
        return newUserRewards;
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
        // If the user has never staked, return zero
        if (startTime == 0) return 0;
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

    function setMaxPercentUserLoss(
        uint256 _maxPercentUserLoss
    ) external onlyRole(GOVERNANCE) {
        if (_maxPercentUserLoss > 1e18)
            revert SafetyModule_InvalidMaxUserLossTooHigh(
                _maxPercentUserLoss,
                1e18
            );
        maxPercentUserLoss = _maxPercentUserLoss;
        emit MaxPercentUserLossUpdated(_maxPercentUserLoss);
    }

    function setMaxRewardMultiplier(
        uint256 _maxRewardMultiplier
    ) external onlyRole(GOVERNANCE) {
        if (_maxRewardMultiplier < 1e18)
            revert SafetyModule_InvalidMaxMultiplierTooLow(
                _maxRewardMultiplier,
                1e18
            );
        else if (_maxRewardMultiplier > 10e18)
            revert SafetyModule_InvalidMaxMultiplierTooHigh(
                _maxRewardMultiplier,
                10e18
            );
        maxRewardMultiplier = _maxRewardMultiplier;
        emit MaxRewardMultiplierUpdated(_maxRewardMultiplier);
    }

    function setSmoothingValue(
        uint256 _smoothingValue
    ) external onlyRole(GOVERNANCE) {
        if (_smoothingValue < 10e18)
            revert SafetyModule_InvalidSmoothingValueTooLow(
                _smoothingValue,
                10e18
            );
        else if (_smoothingValue > 100e18)
            revert SafetyModule_InvalidSmoothingValueTooHigh(
                _smoothingValue,
                100e18
            );
        smoothingValue = _smoothingValue;
        emit SmoothingValueUpdated(_smoothingValue);
    }

    function addStakingToken(
        IStakedToken _stakingToken
    ) external onlyRole(GOVERNANCE) {
        for (uint i; i < stakingTokens.length; ++i) {
            if (address(stakingTokens[i]) == address(_stakingToken))
                revert SafetyModule_StakingTokenAlreadyRegistered(
                    address(_stakingToken)
                );
        }
        stakingTokens.push(_stakingToken);
        emit StakingTokenAdded(address(_stakingToken));
    }
}
