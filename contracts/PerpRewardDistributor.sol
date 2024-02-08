// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.16;

// contracts
import "./RewardDistributor.sol";

// interfaces
import "./interfaces/IPerpRewardDistributor.sol";
import "./interfaces/IRewardController.sol";

/// @title PerpRewardDistributor
/// @author webthethird
/// @notice Handles reward accrual and distribution for liquidity providers in Perpetual markets
contract PerpRewardDistributor is RewardDistributor, IPerpRewardDistributor {
    using SafeERC20 for IERC20Metadata;
    using PRBMathUD60x18 for uint256;

    /// @notice Clearing House contract
    IClearingHouse public immutable clearingHouse;

    /// @notice Amount of time after which LPs can remove liquidity without penalties
    uint256 internal _earlyWithdrawalThreshold;

    /// @notice Last timestamp when user changed their position in a market
    /// @dev First address is user, second is the market
    mapping(address => mapping(address => uint256)) internal _withdrawTimerStartByUserByMarket;

    /// @notice Modifier for functions that can only be called by the ClearingHouse, i.e., `updatePosition`
    modifier onlyClearingHouse() {
        if (msg.sender != address(clearingHouse)) {
            revert PerpRewardDistributor_CallerIsNotClearingHouse(msg.sender);
        }
        _;
    }

    /// @notice PerpRewardDistributor constructor
    /// @param _initialInflationRate The initial inflation rate for the first reward token, scaled by 1e18
    /// @param _initialReductionFactor The initial reduction factor for the first reward token, scaled by 1e18
    /// @param _rewardToken The address of the first reward token
    /// @param _clearingHouse The address of the ClearingHouse contract, which calls `updatePosition`
    /// @param _ecosystemReserve The address of the EcosystemReserve contract, which stores reward tokens
    /// @param _earlyWithdrawThreshold The amount of time after which LPs can remove liquidity without penalties
    /// @param _initialRewardWeights The initial reward weights for the first reward token, as basis points
    constructor(
        uint88 _initialInflationRate,
        uint88 _initialReductionFactor,
        address _rewardToken,
        address _clearingHouse,
        address _ecosystemReserve,
        uint256 _earlyWithdrawThreshold,
        uint256[] memory _initialRewardWeights
    ) payable RewardDistributor(_ecosystemReserve) {
        if (_initialInflationRate > MAX_INFLATION_RATE) {
            revert RewardController_AboveMaxInflationRate(_initialInflationRate, MAX_INFLATION_RATE);
        }
        if (MIN_REDUCTION_FACTOR > _initialReductionFactor) {
            revert RewardController_BelowMinReductionFactor(_initialReductionFactor, MIN_REDUCTION_FACTOR);
        }
        clearingHouse = IClearingHouse(_clearingHouse);
        _earlyWithdrawalThreshold = _earlyWithdrawThreshold;
        // Add reward token info
        uint256 numMarkets = _getNumMarkets();
        if (_initialRewardWeights.length != numMarkets) {
            revert RewardController_IncorrectWeightsCount(_initialRewardWeights.length, numMarkets);
        }
        _rewardInfoByToken[_rewardToken].token = IERC20Metadata(_rewardToken);
        _rewardInfoByToken[_rewardToken].initialTimestamp = uint80(block.timestamp);
        _rewardInfoByToken[_rewardToken].initialInflationRate = _initialInflationRate;
        _rewardInfoByToken[_rewardToken].reductionFactor = _initialReductionFactor;
        _rewardInfoByToken[_rewardToken].marketAddresses = new address[](numMarkets);
        for (uint256 i; i < numMarkets;) {
            address market = _getMarketAddress(_getMarketIdx(i));
            _rewardInfoByToken[_rewardToken].marketAddresses[i] = market;
            _marketWeightsByToken[_rewardToken][market] = _initialRewardWeights[i];
            _timeOfLastCumRewardUpdate[market] = block.timestamp;
            unchecked {
                ++i;
            }
        }
        rewardTokens.push(_rewardToken);
        emit RewardTokenAdded(_rewardToken, block.timestamp, _initialInflationRate, _initialReductionFactor);
    }

    /* ****************** */
    /*   Reward Accrual   */
    /* ****************** */

    /// @notice Accrues rewards and updates the stored LP position of a user and the total LP of a market
    /// @dev Only callable by the clearing house, executes whenever a user's liquidity is updated for any reason
    /// @param market Address of the perpetual market
    /// @param user Address of the liquidity provier
    function updatePosition(address market, address user) external virtual override onlyClearingHouse {
        // Accrue rewards to the market
        _updateMarketRewards(market);

        // Update the total liquidity in the market
        uint256 prevLpPosition = _lpPositionsPerUser[user][market];
        uint256 newLpPosition = _getCurrentPosition(user, market);
        _totalLiquidityPerMarket[market] = _totalLiquidityPerMarket[market] + newLpPosition - prevLpPosition;

        // Accrue rewards to the user for each reward token
        uint256 numTokens = rewardTokens.length;
        for (uint256 i; i < numTokens;) {
            address token = rewardTokens[i];
            /**
             * Accumulator values are denominated in `rewards per LP token` or `reward/LP`, with changes in the market's
             * total liquidity baked into the accumulators every time `_updateMarketRewards` is called. Each time a user
             * accrues rewards we make a copy of the current global value, `_cumulativeRewardPerLpToken[token][market]`,
             * for the user and store it in `_cumulativeRewardPerLpTokenPerUser[user][token][market]`. Thus, subtracting
             * the user's stored value from the current global value gives the new reward/LP accrued to the market since
             * the user last accrued rewards. Multiplying this by the user's LP position gives the new rewards accrued
             * to the user before accounting for any penalties.
             *
             * newRewards = user.lpBalance x (global.cumRewardPerLpToken - user.cumRewardPerLpToken)
             */
            uint256 newRewards = prevLpPosition.mul(
                _cumulativeRewardPerLpToken[token][market] - _cumulativeRewardPerLpTokenPerUser[user][token][market]
            );
            if (newLpPosition < prevLpPosition) {
                // Removed liquidity - need to check if within early withdrawal threshold
                uint256 deltaTime = block.timestamp - _withdrawTimerStartByUserByMarket[user][market];
                if (deltaTime < _earlyWithdrawalThreshold) {
                    // Early withdrawal - apply penalty
                    // Penalty is linearly proportional to the time remaining in the early withdrawal period
                    uint256 penalty = (newRewards * (_earlyWithdrawalThreshold - deltaTime)) / _earlyWithdrawalThreshold;
                    newRewards -= penalty;
                    emit EarlyWithdrawalPenaltyApplied(user, market, token, penalty);
                }
            }
            // Update the user's stored accumulator value
            _cumulativeRewardPerLpTokenPerUser[user][token][market] = _cumulativeRewardPerLpToken[token][market];
            if (newRewards == 0) {
                unchecked {
                    ++i; // saves 63 gas per iteration
                }
                continue;
            }
            // Update the user's rewards and total unclaimed rewards
            _rewardsAccruedByUser[user][token] += newRewards;
            _totalUnclaimedRewards[token] += newRewards;
            emit RewardAccruedToUser(user, token, market, newRewards);

            // Check for reward token shortfall
            uint256 rewardTokenBalance = _rewardTokenBalance(token);
            if (_totalUnclaimedRewards[token] > rewardTokenBalance) {
                emit RewardTokenShortfall(token, _totalUnclaimedRewards[token] - rewardTokenBalance);
            }

            unchecked {
                ++i; // saves 63 gas per iteration
            }
        }
        if (newLpPosition != 0) {
            // Added or partially removed liquidity - reset early withdrawal timer
            _withdrawTimerStartByUserByMarket[user][market] = block.timestamp;
            emit EarlyWithdrawalTimerReset(user, market, block.timestamp + _earlyWithdrawalThreshold);
        } else {
            // Full withdrawal, so next deposit is an initial deposit
            delete _withdrawTimerStartByUserByMarket[user][market];
            emit EarlyWithdrawalTimerReset(user, market, 0);
        }

        // Update the user's stored lp position
        _lpPositionsPerUser[user][market] = newLpPosition;
        emit PositionUpdated(user, market, prevLpPosition, newLpPosition);
    }

    /* ****************** */
    /*   External Views   */
    /* ****************** */

    /// @inheritdoc IPerpRewardDistributor
    function earlyWithdrawalThreshold() external view returns (uint256) {
        return _earlyWithdrawalThreshold;
    }

    /// @inheritdoc IPerpRewardDistributor
    function withdrawTimerStartByUserByMarket(address _user, address _market) external view returns (uint256) {
        return _withdrawTimerStartByUserByMarket[_user][_market];
    }

    /// @notice Indicates whether claiming rewards is currently paused
    /// @dev Contract is paused if either this contract or the ClearingHouse has been paused
    /// @return True if paused, false otherwise
    function paused() public view override returns (bool) {
        return super.paused() || Pausable(address(clearingHouse)).paused();
    }

    /* ****************** */
    /*     Governance     */
    /* ****************** */

    /// @inheritdoc IRewardDistributor
    /// @dev Only callable by governance
    function initMarketStartTime(address _market) external onlyRole(GOVERNANCE) {
        if (_timeOfLastCumRewardUpdate[_market] != 0) {
            revert RewardDistributor_AlreadyInitializedStartTime(_market);
        }
        _timeOfLastCumRewardUpdate[_market] = block.timestamp;
    }

    /// @inheritdoc IPerpRewardDistributor
    /// @dev Only callable by governance
    function setEarlyWithdrawalThreshold(uint256 _newEarlyWithdrawalThreshold) external onlyRole(GOVERNANCE) {
        emit EarlyWithdrawalThresholdUpdated(_earlyWithdrawalThreshold, _newEarlyWithdrawalThreshold);
        _earlyWithdrawalThreshold = _newEarlyWithdrawalThreshold;
    }

    /* ****************** */
    /*      Internal      */
    /* ****************** */

    /// @inheritdoc RewardController
    function _getNumMarkets() internal view override returns (uint256) {
        return clearingHouse.getNumMarkets();
    }

    /// @inheritdoc RewardController
    function _getMarketAddress(uint256 idx) internal view override returns (address) {
        return address(clearingHouse.perpetuals(idx));
    }

    /// @inheritdoc RewardController
    function _getMarketIdx(uint256 i) internal view override returns (uint256) {
        return clearingHouse.id(i);
    }

    /// @inheritdoc RewardController
    function _getCurrentPosition(address user, address market) internal view override returns (uint256) {
        return IPerpetual(market).getLpLiquidity(user);
    }

    /// @notice Accrues rewards to a user for a given market
    /// @dev Assumes LP position hasn't changed since last accrual, since updating rewards due to changes in
    /// LP position is handled by `updatePosition`
    /// @param market Address of the market in `ClearingHouse.perpetuals`
    /// @param user Address of the user
    function _accrueRewards(address market, address user) internal virtual override {
        // Do not accrue rewards for the given market before the early withdrawal threshold has passed, because
        // we cannot apply penalties to rewards that have already been accrued
        if (block.timestamp < _withdrawTimerStartByUserByMarket[user][market] + _earlyWithdrawalThreshold) return;
        uint256 lpPosition = _lpPositionsPerUser[user][market];
        if (lpPosition != _getCurrentPosition(user, market)) {
            // Only occurs if the user has a pre-existing liquidity position and has not registered for rewards,
            // since any change in LP position calls `updatePosition` which updates `_lpPositionsPerUser`
            revert RewardDistributor_UserPositionMismatch(user, market, lpPosition, _getCurrentPosition(user, market));
        }
        // Accrue rewards to the market, or initialize it and return if it has no liquidity
        _updateMarketRewards(market);
        if (_totalLiquidityPerMarket[market] == 0) return;

        // Accrue rewards to the user for each reward token
        uint256 numTokens = rewardTokens.length;
        for (uint256 i; i < numTokens;) {
            address token = rewardTokens[i];
            /**
             * Accumulator values are denominated in `rewards per LP token` or `reward/LP`, with changes in the market's
             * total liquidity baked into the accumulators every time `_updateMarketRewards` is called. Each time a user
             * accrues rewards we make a copy of the current global value, `_cumulativeRewardPerLpToken[token][market]`,
             * for the user and store it in `_cumulativeRewardPerLpTokenPerUser[user][token][market]`. Thus, subtracting
             * the user's stored value from the current global value gives the new reward/LP accrued to the market since
             * the user last accrued rewards. Multiplying this by the user's LP position gives the new rewards accrued
             * to the user before accounting for any penalties.
             *
             * newRewards = user.lpBalance x (global.cumRewardPerLpToken - user.cumRewardPerLpToken)
             */
            uint256 newRewards = lpPosition.mul(
                _cumulativeRewardPerLpToken[token][market] - _cumulativeRewardPerLpTokenPerUser[user][token][market]
            );
            // Update the user's stored accumulator value
            _cumulativeRewardPerLpTokenPerUser[user][token][market] = _cumulativeRewardPerLpToken[token][market];
            if (newRewards == 0) {
                unchecked {
                    ++i; // saves 63 gas per iteration
                }
                continue;
            }
            // Update the user's rewards and total unclaimed rewards
            _rewardsAccruedByUser[user][token] += newRewards;
            _totalUnclaimedRewards[token] += newRewards;
            emit RewardAccruedToUser(user, token, market, newRewards);

            // Check for reward token shortfall
            uint256 rewardTokenBalance = _rewardTokenBalance(token);
            if (_totalUnclaimedRewards[token] > rewardTokenBalance) {
                emit RewardTokenShortfall(token, _totalUnclaimedRewards[token] - rewardTokenBalance);
            }
            unchecked {
                ++i; // saves 63 gas per iteration
            }
        }
    }
}
