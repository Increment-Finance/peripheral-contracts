// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.16;

// contracts
import "./RewardDistributor.sol";

// interfaces
import "./interfaces/IPerpRewardDistributor.sol";

contract PerpRewardDistributor is RewardDistributor, IPerpRewardDistributor {
    using SafeERC20 for IERC20Metadata;
    using PRBMathUD60x18 for uint256;

    /// @notice Clearing House contract
    IClearingHouse public clearingHouse;

    /// @notice Amount of time after which LPs can remove liquidity without penalties
    uint256 public override earlyWithdrawalThreshold;

    modifier onlyClearingHouse() {
        if (msg.sender != address(clearingHouse))
            revert PerpRewardDistributor_CallerIsNotClearingHouse(msg.sender);
        _;
    }

    constructor(
        uint256 _initialInflationRate,
        uint256 _initialReductionFactor,
        address _rewardToken,
        address _clearingHouse,
        address _ecosystemReserve,
        uint256 _earlyWithdrawalThreshold,
        uint16[] memory _initialRewardWeights
    ) RewardDistributor(_ecosystemReserve) {
        if (_initialInflationRate > MAX_INFLATION_RATE)
            revert RewardController_AboveMaxInflationRate(
                _initialInflationRate,
                MAX_INFLATION_RATE
            );
        if (MIN_REDUCTION_FACTOR > _initialReductionFactor)
            revert RewardController_BelowMinReductionFactor(
                _initialReductionFactor,
                MIN_REDUCTION_FACTOR
            );
        clearingHouse = IClearingHouse(_clearingHouse);
        earlyWithdrawalThreshold = _earlyWithdrawalThreshold;
        // Add reward token info
        uint256 numMarkets = getNumMarkets();
        rewardInfoByToken[_rewardToken] = RewardInfo({
            token: IERC20Metadata(_rewardToken),
            paused: false,
            initialTimestamp: block.timestamp,
            initialInflationRate: _initialInflationRate,
            reductionFactor: _initialReductionFactor,
            marketAddresses: new address[](numMarkets),
            marketWeights: _initialRewardWeights
        });
        for (uint256 i; i < getNumMarkets(); ++i) {
            uint256 idx = getMarketIdx(i);
            address market = getMarketAddress(idx);
            rewardInfoByToken[_rewardToken].marketAddresses[i] = market;
            rewardTokensPerMarket[market].push(_rewardToken);
            timeOfLastCumRewardUpdate[market] = block.timestamp;
        }
        emit RewardTokenAdded(
            _rewardToken,
            block.timestamp,
            _initialInflationRate,
            _initialReductionFactor
        );
    }

    /* ****************** */
    /*   Market Getters   */
    /* ****************** */

    /// @inheritdoc RewardController
    function getNumMarkets() public view override returns (uint256) {
        return clearingHouse.getNumMarkets();
    }

    /// @inheritdoc RewardController
    function getMaxMarketIdx() public view override returns (uint256) {
        return clearingHouse.marketIds() - 1;
    }

    /// @inheritdoc RewardController
    function getMarketAddress(
        uint256 index
    ) public view override returns (address) {
        if (index > getMaxMarketIdx())
            revert RewardDistributor_InvalidMarketIndex(
                index,
                getMaxMarketIdx()
            );
        return address(clearingHouse.perpetuals(index));
    }

    /// @inheritdoc RewardController
    function getMarketIdx(uint256 i) public view override returns (uint256) {
        return clearingHouse.id(i);
    }

    /// @inheritdoc RewardDistributor
    function getCurrentPosition(
        address lp,
        address market
    ) public view override returns (uint256) {
        return IPerpetual(market).getLpLiquidity(lp);
    }

    /* ****************** */
    /*   Reward Accrual   */
    /* ****************** */

    /// Accrues rewards and updates the stored LP position of a user and the total LP of a market
    /// @dev Executes whenever a user's liquidity is updated for any reason
    /// @param market Address of the perpetual market or staking contract
    /// @param user Address of the liquidity provier
    function updateStakingPosition(
        address market,
        address user
    ) external virtual override nonReentrant onlyClearingHouse {
        updateMarketRewards(market);
        uint256 prevLpPosition = lpPositionsPerUser[user][market];
        uint256 newLpPosition = getCurrentPosition(user, market);
        for (uint256 i; i < rewardTokensPerMarket[market].length; ++i) {
            address token = rewardTokensPerMarket[market][i];
            /// newRewards = user.lpBalance / global.lpBalance x (global.cumRewardPerLpToken - user.cumRewardPerLpToken)
            uint256 newRewards = (prevLpPosition *
                (cumulativeRewardPerLpToken[token][market] -
                    cumulativeRewardPerLpTokenPerUser[user][token][market])) /
                1e18;
            if (newLpPosition >= prevLpPosition) {
                // Added liquidity
                if (lastDepositTimeByUserByMarket[user][market] == 0) {
                    lastDepositTimeByUserByMarket[user][market] = block
                        .timestamp;
                }
            } else {
                // Removed liquidity - need to check if within early withdrawal threshold
                uint256 deltaTime = block.timestamp -
                    lastDepositTimeByUserByMarket[user][market];
                if (deltaTime < earlyWithdrawalThreshold) {
                    // Early withdrawal - apply penalty
                    newRewards -=
                        (newRewards * (earlyWithdrawalThreshold - deltaTime)) /
                        earlyWithdrawalThreshold;
                }
                if (newLpPosition > 0) {
                    // Reset timer
                    lastDepositTimeByUserByMarket[user][market] = block
                        .timestamp;
                } else {
                    // Full withdrawal, so next deposit is an initial deposit
                    lastDepositTimeByUserByMarket[user][market] = 0;
                }
            }
            cumulativeRewardPerLpTokenPerUser[user][token][
                market
            ] = cumulativeRewardPerLpToken[token][market];
            if (newRewards > 0) {
                rewardsAccruedByUser[user][token] += newRewards;
                totalUnclaimedRewards[token] += newRewards;
                emit RewardAccruedToUser(
                    user,
                    token,
                    address(market),
                    newRewards
                );
            }
        }
        totalLiquidityPerMarket[market] =
            totalLiquidityPerMarket[market] +
            newLpPosition -
            prevLpPosition;
        lpPositionsPerUser[user][market] = newLpPosition;
    }

    /* ****************** */
    /*    External User   */
    /* ****************** */

    /// Accrues rewards to a user for a given market
    /// @notice Assumes LP position hasn't changed since last accrual
    /// @dev Updating rewards due to changes in LP position is handled by updateStakingPosition
    /// @param market Address of the market in ClearingHouse.perpetuals
    /// @param user Address of the user
    function accrueRewards(
        address market,
        address user
    ) public virtual override nonReentrant {
        if (
            block.timestamp <
            lastDepositTimeByUserByMarket[user][market] +
                earlyWithdrawalThreshold
        )
            revert RewardDistributor_EarlyRewardAccrual(
                user,
                market,
                lastDepositTimeByUserByMarket[user][market] +
                    earlyWithdrawalThreshold
            );
        uint256 lpPosition = lpPositionsPerUser[user][market];
        if (lpPosition != getCurrentPosition(user, market))
            // only occurs if the user has a pre-existing liquidity position and has not registered for rewards,
            // since updating LP position calls updateStakingPosition which updates lpPositionsPerUser
            revert RewardDistributor_LpPositionMismatch(
                user,
                market,
                lpPosition,
                getCurrentPosition(user, market)
            );
        if (totalLiquidityPerMarket[market] == 0) return;
        updateMarketRewards(market);
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
    /// @param market Address of the market in ClearingHouse.perpetuals
    /// @param user Address of the user
    /// @param token Address of the reward token
    /// @return Amount of new rewards that would be accrued to the user
    function viewNewRewardAccrual(
        address market,
        address user,
        address token
    ) public view override returns (uint256) {
        if (
            block.timestamp <
            lastDepositTimeByUserByMarket[user][market] +
                earlyWithdrawalThreshold
        )
            revert RewardDistributor_EarlyRewardAccrual(
                user,
                market,
                lastDepositTimeByUserByMarket[user][market] +
                    earlyWithdrawalThreshold
            );
        if (
            lpPositionsPerUser[user][market] != getCurrentPosition(user, market)
        )
            // only occurs if the user has a pre-existing liquidity position and has not registered for rewards,
            // since updating LP position calls updateStakingPosition which updates lpPositionsPerUser
            revert RewardDistributor_LpPositionMismatch(
                user,
                market,
                lpPositionsPerUser[user][market],
                getCurrentPosition(user, market)
            );
        if (timeOfLastCumRewardUpdate[market] == 0)
            revert RewardDistributor_UninitializedStartTime(market);
        uint256 deltaTime = block.timestamp - timeOfLastCumRewardUpdate[market];
        if (totalLiquidityPerMarket[market] == 0) return 0;
        RewardInfo memory rewardInfo = rewardInfoByToken[token];
        uint256 totalTimeElapsed = block.timestamp -
            rewardInfo.initialTimestamp;
        // Calculate the new cumRewardPerLpToken by adding (inflationRatePerSecond x guageWeight x deltaTime) to the previous cumRewardPerLpToken
        uint256 inflationRate = rewardInfo.initialInflationRate.div(
            rewardInfo.reductionFactor.pow(totalTimeElapsed.div(365 days))
        );
        uint256 newMarketRewards = (((inflationRate *
            rewardInfo.marketWeights[getMarketWeightIdx(token, market)]) /
            10000) * deltaTime) / 365 days;
        uint256 newCumRewardPerLpToken = cumulativeRewardPerLpToken[token][
            market
        ] + (newMarketRewards * 1e18) / totalLiquidityPerMarket[market];
        uint256 newUserRewards = lpPositionsPerUser[user][market].mul(
            (newCumRewardPerLpToken -
                cumulativeRewardPerLpTokenPerUser[user][token][market])
        );
        return newUserRewards;
    }

    function paused() public view override returns (bool) {
        return super.paused() || Pausable(address(clearingHouse)).paused();
    }
}
