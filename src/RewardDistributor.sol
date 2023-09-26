// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.16;

// contracts
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";
import {GaugeController} from "./GaugeController.sol";

// interfaces
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IClearingHouse} from "increment-protocol/interfaces/IClearingHouse.sol";
import {IPerpetual} from "increment-protocol/interfaces/IPerpetual.sol";
import {IStakingContract} from "increment-protocol/interfaces/IStakingContract.sol";
import {IRewardDistributor} from "./interfaces/IRewardDistributor.sol";

// libraries
import {PRBMathUD60x18} from "prb-math/contracts/PRBMathUD60x18.sol";

import {console2 as console} from "forge/console2.sol";

contract RewardDistributor is
    IRewardDistributor,
    IStakingContract,
    GaugeController
{
    using SafeERC20 for IERC20Metadata;
    using PRBMathUD60x18 for uint256;

    /// @notice Clearing House contract
    IClearingHouse public clearingHouse;

    /// @notice Amount of time after which LPs can remove liquidity without penalties
    uint256 public override earlyWithdrawalThreshold;

    /// @notice Rewards accrued and not yet claimed by user
    /// @dev First address is user, second is reward token
    mapping(address => mapping(address => uint256)) public rewardsAccruedByUser;

    /// @notice Total rewards accrued and not claimed by all users
    /// @dev Address is reward token
    mapping(address => uint256) public totalUnclaimedRewards;

    /// @notice Last timestamp when user withdrew liquidity from a market
    /// @dev First address is user, second is from ClearingHouse.perpetuals
    mapping(address => mapping(address => uint256))
        public lastDepositTimeByUserByMarket;

    /// @notice Latest LP positions per user and market index
    /// @dev First address is user, second is from ClearingHouse.perpetuals
    mapping(address => mapping(address => uint256)) public lpPositionsPerUser;

    /// @notice Reward accumulator for total market rewards per reward token
    /// @dev First address is reward token, second is from ClearingHouse.perpetuals
    mapping(address => mapping(address => uint256))
        public cumulativeRewardPerLpToken;

    /// @notice Reward accumulator value per reward token when user rewards were last updated
    /// @dev First address is user, second is reward token, third is from ClearingHouse.perpetuals
    mapping(address => mapping(address => mapping(address => uint256)))
        public cumulativeRewardPerLpTokenPerUser;

    /// @notice Timestamp of the most recent update to the reward accumulator
    /// @dev Address is from ClearingHouse.perpetuals array
    mapping(address => uint256) public timeOfLastCumRewardUpdate;

    /// @notice Total LP tokens registered for rewards per market per day
    /// @dev Address is from ClearingHouse.perpetuals array
    mapping(address => uint256) public totalLiquidityPerMarket;

    error RewardDistributor_CallerIsNotClearingHouse(address caller);
    error RewardDistributor_InvalidMarketIndex(uint256 index, uint256 maxIndex);
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

    modifier onlyClearingHouse() {
        if (msg.sender != address(clearingHouse))
            revert RewardDistributor_CallerIsNotClearingHouse(msg.sender);
        _;
    }

    constructor(
        uint256 _initialInflationRate,
        uint256 _initialReductionFactor,
        address _rewardToken,
        address _clearingHouse,
        uint256 _earlyWithdrawalThreshold,
        uint16[] memory _initialGaugeWeights
    ) GaugeController(_initialInflationRate, _initialReductionFactor) {
        clearingHouse = IClearingHouse(_clearingHouse);
        earlyWithdrawalThreshold = _earlyWithdrawalThreshold;
        // Add reward token info
        rewardTokens.push(_rewardToken);
        rewardInfoByToken[_rewardToken] = RewardInfo({
            token: IERC20Metadata(_rewardToken),
            initialTimestamp: block.timestamp,
            inflationRate: _initialInflationRate,
            reductionFactor: _initialReductionFactor,
            gaugeWeights: _initialGaugeWeights
        });
        for (uint256 i; i < clearingHouse.getNumMarkets(); ++i) {
            uint256 idx = clearingHouse.id(i);
            address gauge = getGaugeAddress(idx);
            timeOfLastCumRewardUpdate[gauge] = block.timestamp;
        }
        emit RewardTokenAdded(
            _rewardToken,
            block.timestamp,
            _initialInflationRate,
            _initialReductionFactor
        );
    }

    /* ****************** */
    /*       Gauges       */
    /* ****************** */

    /// @inheritdoc GaugeController
    function getNumGauges() public view virtual override returns (uint256) {
        return clearingHouse.getNumMarkets();
    }

    /// @inheritdoc GaugeController
    function getMaxGaugeIdx() public view virtual override returns (uint256) {
        return clearingHouse.marketIds() - 1;
    }

    /// @inheritdoc GaugeController
    function getGaugeAddress(
        uint256 index
    ) public view virtual override returns (address) {
        if (index > getMaxGaugeIdx())
            revert RewardDistributor_InvalidMarketIndex(
                index,
                getMaxGaugeIdx()
            );
        return address(clearingHouse.perpetuals(index));
    }

    function getGaugeIdx(
        uint256 i
    ) public view virtual override returns (uint256) {
        return clearingHouse.id(i);
    }

    /// Returns the current position of the user in the gauge (i.e., perpetual market)
    /// @param lp Address of the user
    /// @param gauge Address of the gauge
    /// @return Current position of the user in the gauge
    function getCurrentPosition(
        address lp,
        address gauge
    ) public view virtual returns (uint256) {
        return IPerpetual(gauge).getLpLiquidity(lp);
    }

    /* ****************** */
    /*   Reward Accrual   */
    /* ****************** */

    /// @inheritdoc GaugeController
    function updateMarketRewards(uint256 idx) public override {
        console.log("updateMarketRewards(%s)", idx);
        address gauge = getGaugeAddress(idx);
        console.log("gauge: %s", gauge);
        uint256 liquidity = totalLiquidityPerMarket[gauge];
        console.log("liquidity: %s", liquidity);
        uint256 deltaTime = block.timestamp - timeOfLastCumRewardUpdate[gauge];
        console.log(
            "timeOfLastCumRewardUpdate[%s]: %s",
            gauge,
            timeOfLastCumRewardUpdate[gauge]
        );
        if (liquidity == 0) {
            timeOfLastCumRewardUpdate[gauge] = block.timestamp;
            return;
        }
        for (uint256 i; i < rewardTokens.length; ++i) {
            address token = rewardTokens[i];
            RewardInfo memory rewardInfo = rewardInfoByToken[token];
            if (
                idx >= rewardInfo.gaugeWeights.length ||
                rewardInfo.gaugeWeights[idx] == 0
            ) continue;
            uint16 gaugeWeight = rewardInfo.gaugeWeights[idx];
            console.log("gaugeWeight: %s", gaugeWeight);
            if (timeOfLastCumRewardUpdate[gauge] == 0 && gaugeWeight != 0)
                revert RewardDistributor_UninitializedStartTime(gauge);
            uint256 totalTimeElapsed = block.timestamp -
                rewardInfo.initialTimestamp;
            // Calculate the new cumRewardPerLpToken by adding (inflationRatePerSecond x guageWeight x deltaTime) to the previous cumRewardPerLpToken
            uint256 inflationRatePerSecond = (
                rewardInfo.inflationRate.div(
                    rewardInfo.reductionFactor.pow(
                        totalTimeElapsed.div(365 days)
                    )
                )
            ) / 365 days;
            uint256 newRewards = ((inflationRatePerSecond *
                rewardInfo.gaugeWeights[idx]) / 10000) * deltaTime;
            cumulativeRewardPerLpToken[token][gauge] += newRewards;
            emit RewardAccruedToMarket(gauge, token, newRewards);
        }
        // Set timeOfLastCumRewardUpdate to the currentTime
        timeOfLastCumRewardUpdate[gauge] = block.timestamp;
    }

    /// Accrues rewards and updates the stored LP position of a user and the total LP of a market
    /// @dev Executes whenever a user's liquidity is updated for any reason
    /// @param idx Index of the perpetual market in the ClearingHouse
    /// @param user Address of the liquidity provier
    function updateStakingPosition(
        uint256 idx,
        address user
    ) external virtual override nonReentrant onlyClearingHouse {
        updateMarketRewards(idx);
        address gauge = getGaugeAddress(idx);
        uint256 prevLpPosition = lpPositionsPerUser[user][gauge];
        uint256 newLpPosition = getCurrentPosition(user, gauge);
        uint256 prevTotalLiquidity = totalLiquidityPerMarket[gauge];
        for (uint256 i; i < rewardTokens.length; ++i) {
            address token = rewardTokens[i];
            /// newRewards = user.lpBalance / global.lpBalance x (global.cumRewardPerLpToken - user.cumRewardPerLpToken)
            uint256 newRewards = prevTotalLiquidity > 0
                ? (prevLpPosition *
                    (cumulativeRewardPerLpToken[token][gauge] -
                        cumulativeRewardPerLpTokenPerUser[user][token][
                            gauge
                        ])) / prevTotalLiquidity
                : 0;
            if (newLpPosition >= prevLpPosition) {
                // Added liquidity
                if (lastDepositTimeByUserByMarket[user][gauge] == 0) {
                    lastDepositTimeByUserByMarket[user][gauge] = block
                        .timestamp;
                }
            } else {
                // Removed liquidity - need to check if within early withdrawal threshold
                if (
                    block.timestamp -
                        lastDepositTimeByUserByMarket[user][gauge] <
                    earlyWithdrawalThreshold
                ) {
                    // Early withdrawal - apply penalty
                    newRewards -=
                        (newRewards * (prevLpPosition - newLpPosition)) /
                        prevLpPosition;
                }
                if (newLpPosition > 0) {
                    // Reset timer
                    lastDepositTimeByUserByMarket[user][gauge] = block
                        .timestamp;
                } else {
                    // Full withdrawal, so next deposit is an initial deposit
                    lastDepositTimeByUserByMarket[user][gauge] = 0;
                }
            }
            rewardsAccruedByUser[user][token] += newRewards;
            totalUnclaimedRewards[token] += newRewards;
            cumulativeRewardPerLpTokenPerUser[user][token][
                gauge
            ] = cumulativeRewardPerLpToken[token][gauge];
            emit RewardAccruedToUser(user, token, address(gauge), newRewards);
        }
        totalLiquidityPerMarket[gauge] =
            totalLiquidityPerMarket[gauge] +
            newLpPosition -
            prevLpPosition;
        lpPositionsPerUser[user][gauge] = newLpPosition;
    }

    /* ****************** */
    /*     Governance     */
    /* ****************** */

    /// Sets the start time for accruing rewards to a gauge which has not been initialized yet
    /// @param _gauge Address of the gauge (i.e., perpetual market)
    function initGaugeStartTime(address _gauge) external onlyRole(GOVERNANCE) {
        if (timeOfLastCumRewardUpdate[_gauge] != 0)
            revert RewardDistributor_AlreadyInitializedStartTime(_gauge);
        timeOfLastCumRewardUpdate[_gauge] = block.timestamp;
    }

    /// Adds a new reward token
    /// @param _rewardToken Address of the reward token
    /// @param _initialInflationRate Initial inflation rate for the new token
    /// @param _initialReductionFactor Initial reduction factor for the new token
    /// @param _gaugeWeights Initial weights per gauge/market for the new token
    function addRewardToken(
        address _rewardToken,
        uint256 _initialInflationRate,
        uint256 _initialReductionFactor,
        uint16[] calldata _gaugeWeights
    ) external nonReentrant onlyRole(GOVERNANCE) {
        if (rewardTokens.length >= MAX_REWARD_TOKENS)
            revert GaugeController_AboveMaxRewardTokens(MAX_REWARD_TOKENS);
        uint256 gaugesLength = getNumGauges();
        if (_gaugeWeights.length != gaugesLength)
            revert GaugeController_IncorrectWeightsCount(
                _gaugeWeights.length,
                gaugesLength
            );
        // Validate weights
        uint16 totalWeight;
        for (uint i; i < gaugesLength; ++i) {
            uint256 idx = clearingHouse.id(i);
            updateMarketRewards(idx);
            uint16 weight = _gaugeWeights[i];
            if (weight > 10000)
                revert GaugeController_WeightExceedsMax(weight, 10000);
            address gauge = getGaugeAddress(idx);
            totalWeight += weight;
            emit NewWeight(gauge, _rewardToken, weight);
        }
        if (totalWeight != 10000)
            revert GaugeController_IncorrectWeightsSum(totalWeight, 10000);
        // Add reward token info
        rewardTokens.push(_rewardToken);
        rewardInfoByToken[_rewardToken] = RewardInfo({
            token: IERC20Metadata(_rewardToken),
            initialTimestamp: block.timestamp,
            inflationRate: _initialInflationRate,
            reductionFactor: _initialReductionFactor,
            gaugeWeights: _gaugeWeights
        });
        emit RewardTokenAdded(
            _rewardToken,
            block.timestamp,
            _initialInflationRate,
            _initialReductionFactor
        );
    }

    /// Removes a reward token
    /// @param _token Address of the reward token to remove
    function removeRewardToken(
        address _token
    ) external nonReentrant onlyRole(GOVERNANCE) {
        if (rewardInfoByToken[_token].token != IERC20Metadata(_token))
            revert GaugeController_InvalidRewardTokenAddress(_token);
        uint256 gaugesLength = getNumGauges();
        // Update rewards for all markets before removal
        for (uint i; i < gaugesLength; ++i) {
            uint256 idx = clearingHouse.id(i);
            updateMarketRewards(idx);
        }
        // The `delete` keyword applied to arrays does not reduce array length
        for (uint i = 0; i < rewardTokens.length; ++i) {
            if (rewardTokens[i] == _token) {
                // Find the token in the array and swap it with the last element
                rewardTokens[i] = rewardTokens[rewardTokens.length - 1];
                // Delete the last element
                rewardTokens.pop();
                break;
            }
        }
        delete rewardInfoByToken[_token];
        // Determine how much of the removed token should be sent back to governance
        uint256 balance = IERC20Metadata(_token).balanceOf(address(this));
        uint256 unclaimedAccruals = totalUnclaimedRewards[_token];
        uint256 unaccruedBalance = balance >= unclaimedAccruals
            ? balance - unclaimedAccruals
            : 0;
        // Transfer remaining tokens to governance (which is the sender)
        IERC20Metadata(_token).safeTransfer(msg.sender, unaccruedBalance);
        emit RewardTokenRemoved(_token, unclaimedAccruals, unaccruedBalance);
    }

    /* ****************** */
    /*    External User   */
    /* ****************** */

    /// Fetches and stores the caller's LP positions and updates the total liquidity in each market
    /// @dev Can only be called once per user, only necessary if user was an LP prior to this contract's deployment
    function registerPositions() external nonReentrant {
        uint256 numMarkets = getNumGauges();
        for (uint i; i < numMarkets; ++i) {
            uint idx = clearingHouse.id(i);
            address gauge = getGaugeAddress(idx);
            if (lpPositionsPerUser[msg.sender][gauge] != 0)
                revert RewardDistributor_PositionAlreadyRegistered(
                    msg.sender,
                    i,
                    lpPositionsPerUser[msg.sender][gauge]
                );
            uint256 lpPosition = getCurrentPosition(msg.sender, gauge);
            lpPositionsPerUser[msg.sender][gauge] = lpPosition;
            totalLiquidityPerMarket[gauge] += lpPosition;
        }
    }

    /// Fetches and stores the caller's LP positions and updates the total liquidity in each market
    /// @dev Can only be called once per user, only necessary if user was an LP prior to this contract's deployment
    /// @param _marketIndexes Indexes of the perpetual markets in the ClearingHouse to sync with
    function registerPositions(
        uint256[] calldata _marketIndexes
    ) external nonReentrant {
        for (uint i; i < _marketIndexes.length; ++i) {
            uint256 idx = _marketIndexes[i];
            address gauge = getGaugeAddress(idx);
            if (lpPositionsPerUser[msg.sender][gauge] != 0)
                revert RewardDistributor_PositionAlreadyRegistered(
                    msg.sender,
                    idx,
                    lpPositionsPerUser[msg.sender][gauge]
                );
            uint256 lpPosition = getCurrentPosition(msg.sender, gauge);
            lpPositionsPerUser[msg.sender][gauge] = lpPosition;
            totalLiquidityPerMarket[gauge] += lpPosition;
        }
    }

    /// Accrues and then distributes rewards for all markets to the caller
    function claimRewards() public override {
        claimRewardsFor(msg.sender);
    }

    /// Accrues and then distributes rewards for all markets to the given user
    /// @param _user Address of the user to claim rewards for
    function claimRewardsFor(address _user) public override {
        claimRewardsFor(_user, rewardTokens);
    }

    /// Accrues and then distributes rewards for all markets to the given user
    /// @param _user Address of the user to claim rewards for
    function claimRewardsFor(
        address _user,
        address[] memory _rewardTokens
    ) public override whenNotPaused {
        for (uint i; i < getNumGauges(); ++i) {
            uint256 idx = clearingHouse.id(i);
            accrueRewards(idx, _user);
        }
        for (uint i; i < _rewardTokens.length; ++i) {
            address token = _rewardTokens[i];
            uint256 rewards = rewardsAccruedByUser[_user][token];
            if (rewards > 0) {
                uint256 remainingRewards = _distributeReward(
                    token,
                    _user,
                    rewards
                );
                rewardsAccruedByUser[_user][token] = remainingRewards;
                emit RewardClaimed(_user, token, rewards - remainingRewards);
                if (remainingRewards > 0) {
                    emit RewardTokenShortfall(
                        token,
                        totalUnclaimedRewards[token]
                    );
                }
            }
        }
    }

    /// Accrues rewards to a user for all markets
    /// @notice Assumes LP position hasn't changed since last accrual
    /// @dev Updating rewards due to changes in LP position is handled by updateStakingPosition
    /// @param user Address of the user to accrue rewards for
    function accrueRewards(address user) external override {
        for (uint i; i < getNumGauges(); ++i) {
            uint256 idx = clearingHouse.id(i);
            accrueRewards(idx, user);
        }
    }

    /// Accrues rewards to a user for a given market
    /// @notice Assumes LP position hasn't changed since last accrual
    /// @dev Updating rewards due to changes in LP position is handled by updateStakingPosition
    /// @param idx Index of the market in ClearingHouse.perpetuals
    /// @param user Address of the user
    function accrueRewards(uint256 idx, address user) public nonReentrant {
        address gauge = getGaugeAddress(idx);
        if (
            block.timestamp <
            lastDepositTimeByUserByMarket[user][gauge] +
                earlyWithdrawalThreshold
        )
            revert RewardDistributor_EarlyRewardAccrual(
                user,
                idx,
                lastDepositTimeByUserByMarket[user][gauge] +
                    earlyWithdrawalThreshold
            );
        uint256 lpPosition = lpPositionsPerUser[user][gauge];
        if (lpPosition != getCurrentPosition(user, gauge))
            revert RewardDistributor_LpPositionMismatch(
                user,
                idx,
                lpPosition,
                getCurrentPosition(user, gauge)
            );
        if (totalLiquidityPerMarket[gauge] == 0) return;
        updateMarketRewards(idx);
        for (uint i; i < rewardTokens.length; ++i) {
            address token = rewardTokens[i];
            uint256 newRewards = (lpPosition *
                (cumulativeRewardPerLpToken[token][gauge] -
                    cumulativeRewardPerLpTokenPerUser[user][token][gauge])) /
                totalLiquidityPerMarket[gauge];
            rewardsAccruedByUser[user][token] += newRewards;
            totalUnclaimedRewards[token] += newRewards;
            cumulativeRewardPerLpTokenPerUser[user][token][
                gauge
            ] = cumulativeRewardPerLpToken[token][gauge];
            emit RewardAccruedToUser(user, token, gauge, newRewards);
        }
    }

    /// Returns the amount of rewards that would be accrued to a user if they called accrueRewards(address user)
    /// @notice Serves as a static version of accrueRewards(address user)
    /// @param user Address of the user
    /// @return Amount of new rewards that would be accrued to the user for each reward token
    function viewNewRewardAccrual(
        address user
    ) external view returns (uint256[] memory) {
        uint256[] memory newRewards = new uint256[](rewardTokens.length);
        for (uint i; i < rewardTokens.length; ++i) {
            address token = rewardTokens[i];
            for (uint j; j < getNumGauges(); ++j) {
                uint256 idx = clearingHouse.id(j);
                newRewards[i] += viewNewRewardAccrual(idx, user, token);
            }
        }
        return newRewards;
    }

    /// Returns the amount of rewards that would be accrued to a user for a given market
    /// @notice Serves as a static version of accrueRewards(uint256 idx, address user)
    /// @param idx Index of the market in ClearingHouse.perpetuals
    /// @param user Address of the user
    /// @return Amount of new rewards that would be accrued to the user for each reward token
    function viewNewRewardAccrual(
        uint256 idx,
        address user
    ) public view returns (uint256[] memory) {
        uint256[] memory newRewards = new uint256[](rewardTokens.length);
        for (uint i; i < rewardTokens.length; ++i) {
            address token = rewardTokens[i];
            newRewards[i] = viewNewRewardAccrual(idx, user, token);
        }
        return newRewards;
    }

    /// Returns the amount of rewards that would be accrued to a user for a given market and reward token
    /// @param idx Index of the market in ClearingHouse.perpetuals
    /// @param user Address of the user
    /// @param token Address of the reward token
    /// @return Amount of new rewards that would be accrued to the user
    function viewNewRewardAccrual(
        uint256 idx,
        address user,
        address token
    ) public view returns (uint256) {
        address gauge = getGaugeAddress(idx);
        if (
            block.timestamp <
            lastDepositTimeByUserByMarket[user][gauge] +
                earlyWithdrawalThreshold
        )
            revert RewardDistributor_EarlyRewardAccrual(
                user,
                idx,
                lastDepositTimeByUserByMarket[user][gauge] +
                    earlyWithdrawalThreshold
            );
        uint256 lpPosition = lpPositionsPerUser[user][gauge];
        if (lpPosition != getCurrentPosition(user, gauge))
            revert RewardDistributor_LpPositionMismatch(
                user,
                idx,
                lpPosition,
                getCurrentPosition(user, gauge)
            );
        uint256 liquidity = totalLiquidityPerMarket[gauge];
        if (timeOfLastCumRewardUpdate[gauge] == 0)
            revert RewardDistributor_UninitializedStartTime(gauge);
        uint256 deltaTime = block.timestamp - timeOfLastCumRewardUpdate[gauge];
        if (liquidity == 0) return 0;
        RewardInfo memory rewardInfo = rewardInfoByToken[token];
        uint256 totalTimeElapsed = block.timestamp -
            rewardInfo.initialTimestamp;
        // Calculate the new cumRewardPerLpToken by adding (inflationRatePerSecond x guageWeight x deltaTime) to the previous cumRewardPerLpToken
        uint256 inflationRatePerSecond = (
            rewardInfo.inflationRate.div(
                rewardInfo.reductionFactor.pow(totalTimeElapsed.div(365 days))
            )
        ) / 365 days;
        uint256 newMarketRewards = ((inflationRatePerSecond *
            rewardInfo.gaugeWeights[idx]) / 10000) * deltaTime;
        uint256 newCumRewardPerLpToken = cumulativeRewardPerLpToken[token][
            gauge
        ] + newMarketRewards;
        uint256 newUserRewards = (lpPosition *
            (newCumRewardPerLpToken -
                cumulativeRewardPerLpTokenPerUser[user][token][gauge])) /
            totalLiquidityPerMarket[gauge];
        return newUserRewards;
    }

    function paused() public view override returns (bool) {
        return super.paused() || Pausable(address(clearingHouse)).paused();
    }

    /* ****************** */
    /*      Internal      */
    /* ****************** */

    function _distributeReward(
        address _token,
        address _to,
        uint256 _amount
    ) internal returns (uint256) {
        uint256 rewardsRemaining = _rewardTokenBalance(_token);
        IERC20Metadata rewardToken = IERC20Metadata(_token);
        if (_amount > 0 && _amount <= rewardsRemaining) {
            rewardToken.safeTransfer(_to, _amount);
            totalUnclaimedRewards[_token] -= _amount;
            return 0;
        } else if (_amount > rewardsRemaining) {
            rewardToken.safeTransfer(_to, rewardsRemaining);
            totalUnclaimedRewards[_token] -= rewardsRemaining;
            return _amount - rewardsRemaining;
        }
        return _amount;
    }

    function _rewardTokenBalance(
        address _token
    ) internal view returns (uint256) {
        IERC20Metadata rewardToken = IERC20Metadata(_token);
        return rewardToken.balanceOf(address(this));
    }
}
