// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.16;

// contracts
import "./RewardDistributor.sol";

// interfaces
import "./interfaces/IStakedToken.sol";
import "./interfaces/ISMRewardDistributor.sol";
import "./interfaces/IRewardController.sol";

/// @title SMRewardDistributor
/// @author webthethird
/// @notice Reward distributor for the Safety Module
contract SMRewardDistributor is RewardDistributor, ISMRewardDistributor {
    using PRBMath for uint256;
    using PRBMathUD60x18 for uint256;

    /// @notice The SafetyModule contract which stores the list of StakedTokens and can call `updatePosition`
    ISafetyModule public safetyModule;

    /// @notice The maximum reward multiplier, scaled by 1e18
    uint256 internal _maxRewardMultiplier;

    /// @notice The smoothing value, scaled by 1e18
    /// @dev The higher the value, the slower the multiplier approaches its max
    uint256 internal _smoothingValue;

    /// @notice The starting timestamp used to calculate the user's reward multiplier for a given staked token
    /// @dev First address is user, second is staked token
    mapping(address => mapping(address => uint256)) internal _multiplierStartTimeByUser;

    /// @notice Modifier for functions that should only be called by the SafetyModule, i.e., `initMarketStartTime`
    modifier onlySafetyModule() {
        if (msg.sender != address(safetyModule)) {
            revert SMRD_CallerIsNotSafetyModule(msg.sender);
        }
        _;
    }

    /// @notice SafetyModule constructor
    /// @param _safetyModule The address of the SafetyModule contract
    /// @param _maxMultiplier The maximum reward multiplier, scaled by 1e18
    /// @param _smoothingVal The smoothing value, scaled by 1e18
    /// @param _ecosystemReserve The address of the EcosystemReserve contract, where reward tokens are stored
    constructor(ISafetyModule _safetyModule, uint256 _maxMultiplier, uint256 _smoothingVal, address _ecosystemReserve)
        payable
        RewardDistributor(_ecosystemReserve)
    {
        safetyModule = _safetyModule;
        _maxRewardMultiplier = _maxMultiplier;
        _smoothingValue = _smoothingVal;
        emit SafetyModuleUpdated(address(0), address(_safetyModule));
        emit MaxRewardMultiplierUpdated(0, _maxRewardMultiplier);
        emit SmoothingValueUpdated(0, _smoothingVal);
    }

    /* ****************** */
    /*   Reward Accrual   */
    /* ****************** */

    /// @notice Accrues rewards and updates the stored stake position of a user and the total tokens staked
    /// @dev Only callable by a registered StakedToken, executes whenever a user's stake is updated for any reason
    /// @param market Address of the staked token in `SafetyModule.stakedTokens`
    /// @param user Address of the staker
    function updatePosition(address market, address user) external virtual override {
        // Check that the market is a registered staked token
        safetyModule.getStakedTokenIdx(market); // will revert if not found
        // Check that the caller is the staked token
        if (msg.sender != market) {
            revert SMRD_CallerIsNotStakedToken(msg.sender);
        }

        // Accrue rewards to the market
        _updateMarketRewards(market);

        // Update the total liquidity in the market
        uint256 prevPosition = _lpPositionsPerUser[user][market];
        uint256 newPosition = _getCurrentPosition(user, market);
        _totalLiquidityPerMarket[market] = _totalLiquidityPerMarket[market] + newPosition - prevPosition;

        // Accrue rewards to the user for each reward token
        uint256 rewardMultiplier = computeRewardMultiplier(user, market);
        uint256 numTokens = rewardTokens.length;
        for (uint256 i; i < numTokens;) {
            address token = rewardTokens[i];
            /// newRewards = user.lpBalance x (global.cumRewardPerLpToken - user.cumRewardPerLpToken) x user.rewardMultiplier
            uint256 newRewards = prevPosition.mul(
                _cumulativeRewardPerLpToken[token][market] - _cumulativeRewardPerLpTokenPerUser[user][token][market]
            ).mul(rewardMultiplier);
            // Update the user's stored accumulator value
            _cumulativeRewardPerLpTokenPerUser[user][token][market] = _cumulativeRewardPerLpToken[token][market];
            if (newRewards == 0) {
                unchecked {
                    ++i;
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
                ++i;
            }
        }
        if (prevPosition == 0 || newPosition <= prevPosition) {
            // Removed stake, started cooldown or staked for the first time - need to reset multiplier
            if (newPosition != 0) {
                // Partial removal, cooldown or first stake - reset multiplier to 1
                _multiplierStartTimeByUser[user][market] = block.timestamp;
            } else {
                // Full removal - set multiplier to 0 until the user stakes again
                delete _multiplierStartTimeByUser[user][market];
            }
        } else {
            // User added to their existing stake - need to update multiplier start time
            // To prevent users from gaming the system by staked a small amount early to start the multiplier
            // and then staked a large amount once their multiplier is very high in order to claim a large
            // amount of rewards, we shift the start time of the multiplier forward by an amount proportional
            // to the ratio of the increase in stake (newPosition - prevPosition) to the new position
            _multiplierStartTimeByUser[user][market] += (block.timestamp - _multiplierStartTimeByUser[user][market]).mul(
                (newPosition - prevPosition).div(newPosition)
            );
        }

        // Update the user's stored stake position
        _lpPositionsPerUser[user][market] = newPosition;
        emit PositionUpdated(user, market, prevPosition, newPosition);
    }

    /* ****************** */
    /*   External Views   */
    /* ****************** */

    /// @inheritdoc ISMRewardDistributor
    function getMaxRewardMultiplier() external view returns (uint256) {
        return _maxRewardMultiplier;
    }

    /// @inheritdoc ISMRewardDistributor
    function getSmoothingValue() external view returns (uint256) {
        return _smoothingValue;
    }

    /// @inheritdoc ISMRewardDistributor
    function multiplierStartTimeByUser(address _user, address _stakedToken) public view override returns (uint256) {
        return _multiplierStartTimeByUser[_user][_stakedToken];
    }

    /// @notice Indicates whether claiming rewards is currently paused
    /// @dev Contract is paused if either this contract or the SafetyModule has been paused
    /// @return True if paused, false otherwise
    function paused() public view override returns (bool) {
        return super.paused() || Pausable(address(safetyModule)).paused();
    }

    /* ******************* */
    /*  Reward Multiplier  */
    /* ******************* */

    /// @inheritdoc ISMRewardDistributor
    function computeRewardMultiplier(address _user, address _stakedToken) public view returns (uint256) {
        uint256 startTime = _multiplierStartTimeByUser[_user][_stakedToken];
        // If the user has never staked, return zero
        if (startTime == 0) return 0;
        uint256 deltaDays = (block.timestamp - startTime).div(1 days);
        /**
         * Multiplier formula, rearranged to limit divisions:
         *   maxRewardMultiplier - 1 / ((1 / smoothingValue) * deltaDays + (1 / (maxRewardMultiplier - 1)))
         * = maxRewardMultiplier - smoothingValue / (deltaDays + (smoothingValue / (maxRewardMultiplier - 1)))
         * = maxRewardMultiplier - (smoothingValue * (maxRewardMultiplier - 1)) / ((deltaDays * (maxRewardMultiplier - 1)) + smoothingValue)
         *
         * Example w/ maxRewardMultiplier = 4e18 and smoothingValue = 30e18:
         * t = 0 days:  4e18 - (30e18 * 3e18) / ((0 * 3e18) + 30e18) = 4e18 - 90e18 / 30e18 = 4e18 - 3e18 = 1e18
         * t = 2 days:  4e18 - (30e18 * 3e18) / ((2 * 3e18) + 30e18) = 4e18 - 90e18 / 36e18 = 4e18 - 2.5e18 = 1.5e18
         * t = 5 days:  4e18 - (30e18 * 3e18) / ((5 * 3e18) + 30e18) = 4e18 - 90e18 / 45e18 = 4e18 - 2e18 = 2e18
         * t = 10 days: 4e18 - (30e18 * 3e18) / ((10 * 3e18) + 30e18) = 4e18 - 90e18 / 60e18 = 4e18 - 1.5e18 = 2.5e18
         * t = 20 days: 4e18 - (30e18 * 3e18) / ((20 * 3e18) + 30e18) = 4e18 - 90e18 / 90e18 = 4e18 - 1e18 = 3e18
         * t = 50 days: 4e18 - (30e18 * 3e18) / ((50 * 3e18) + 30e18) = 4e18 - 90e18 / 180e18 = 4e18 - 0.5e18 = 3.5e18
         */
        return _maxRewardMultiplier
            - _smoothingValue.mulDiv(
                _maxRewardMultiplier - 1e18, deltaDays.mul(_maxRewardMultiplier - 1e18) + _smoothingValue
            );
    }

    /* ******************* */
    /*    Safety Module    */
    /* ******************* */

    /// @inheritdoc IRewardDistributor
    /// @dev Can only be called by the SafetyModule
    function initMarketStartTime(address _market) external onlySafetyModule {
        if (_timeOfLastCumRewardUpdate[_market] != 0) {
            revert RewardDistributor_AlreadyInitializedStartTime(_market);
        }
        _timeOfLastCumRewardUpdate[_market] = block.timestamp;
    }

    /* ****************** */
    /*     Governance     */
    /* ****************** */

    /// @inheritdoc ISMRewardDistributor
    /// @dev Only callable by governance
    function setSafetyModule(ISafetyModule _newSafetyModule) external onlyRole(GOVERNANCE) {
        if (address(_newSafetyModule) == address(0)) {
            revert RewardDistributor_InvalidZeroAddress();
        }
        emit SafetyModuleUpdated(address(safetyModule), address(_newSafetyModule));
        safetyModule = _newSafetyModule;
    }

    /// @inheritdoc ISMRewardDistributor
    /// @dev Only callable by governance, reverts if the new value is less than 1e18 (100%) or greater than 10e18 (1000%)
    function setMaxRewardMultiplier(uint256 _newMaxMultiplier) external onlyRole(GOVERNANCE) {
        if (_newMaxMultiplier < 1e18) {
            revert SMRD_InvalidMaxMultiplierTooLow(_newMaxMultiplier, 1e18);
        } else if (_newMaxMultiplier > 10e18) {
            revert SMRD_InvalidMaxMultiplierTooHigh(_newMaxMultiplier, 10e18);
        }
        emit MaxRewardMultiplierUpdated(_maxRewardMultiplier, _newMaxMultiplier);
        _maxRewardMultiplier = _newMaxMultiplier;
    }

    /// @inheritdoc ISMRewardDistributor
    /// @dev Only callable by governance, reverts if the new value is less than 10e18 or greater than 100e18
    function setSmoothingValue(uint256 _newSmoothingValue) external onlyRole(GOVERNANCE) {
        if (_newSmoothingValue < 10e18) {
            revert SMRD_InvalidSmoothingValueTooLow(_newSmoothingValue, 10e18);
        } else if (_newSmoothingValue > 100e18) {
            revert SMRD_InvalidSmoothingValueTooHigh(_newSmoothingValue, 100e18);
        }
        emit SmoothingValueUpdated(_smoothingValue, _newSmoothingValue);
        _smoothingValue = _newSmoothingValue;
    }

    /// @inheritdoc IRewardController
    /// @dev Only callable by governance
    function pause() external override onlyRole(GOVERNANCE) {
        _pause();
    }

    /// @inheritdoc IRewardController
    /// @dev Only callable by governance
    function unpause() external override onlyRole(GOVERNANCE) {
        _unpause();
    }

    /// @inheritdoc IRewardController
    /// @dev Only callable by governance
    function togglePausedReward(address _rewardToken) external override onlyRole(GOVERNANCE) {
        _togglePausedReward(_rewardToken);
    }

    /* **************** */
    /*     Internal     */
    /* **************** */

    /// @inheritdoc RewardDistributor
    function _getNumMarkets() internal view virtual override returns (uint256) {
        return safetyModule.getNumStakedTokens();
    }

    /// @inheritdoc RewardDistributor
    function _getMarketAddress(uint256 index) internal view virtual override returns (address) {
        return address(safetyModule.stakedTokens(index));
    }

    /// @inheritdoc RewardDistributor
    function _getMarketIdx(uint256 i) internal view virtual override returns (uint256) {
        return i;
    }

    /// @notice Returns the user's staked token balance
    /// @param staker Address of the user
    /// @param token Address of the staked token
    /// @return Current balance of the user in the staked token
    function _getCurrentPosition(address staker, address token) internal view virtual override returns (uint256) {
        return IStakedToken(token).balanceOf(staker);
    }

    /// @notice Accrues rewards to a user for a given staked token
    /// @dev Assumes stake position hasn't changed since last accrual, since updating rewards due to changes in
    /// stake position is handled by `updatePosition`
    /// @param market Address of the token in `stakedTokens`
    /// @param user Address of the user
    function _accrueRewards(address market, address user) internal virtual override {
        uint256 userPosition = _lpPositionsPerUser[user][market];
        if (userPosition != _getCurrentPosition(user, market)) {
            // only occurs if the user has a pre-existing balance and has not registered for rewards,
            // since updating stake position calls updatePosition which updates _lpPositionsPerUser
            revert RewardDistributor_UserPositionMismatch(user, market, userPosition, _getCurrentPosition(user, market));
        }
        if (_totalLiquidityPerMarket[market] == 0) return;
        _updateMarketRewards(market);
        uint256 rewardMultiplier = computeRewardMultiplier(user, market);
        uint256 numTokens = rewardTokens.length;
        for (uint256 i; i < numTokens;) {
            address token = rewardTokens[i];
            uint256 newRewards = userPosition.mul(
                _cumulativeRewardPerLpToken[token][market] - _cumulativeRewardPerLpTokenPerUser[user][token][market]
            ).mul(rewardMultiplier);
            _cumulativeRewardPerLpTokenPerUser[user][token][market] = _cumulativeRewardPerLpToken[token][market];
            if (newRewards == 0) {
                unchecked {
                    ++i;
                }
                continue;
            }
            _rewardsAccruedByUser[user][token] += newRewards;
            _totalUnclaimedRewards[token] += newRewards;
            emit RewardAccruedToUser(user, token, market, newRewards);
            uint256 rewardTokenBalance = _rewardTokenBalance(token);
            if (_totalUnclaimedRewards[token] > rewardTokenBalance) {
                emit RewardTokenShortfall(token, _totalUnclaimedRewards[token] - rewardTokenBalance);
            }
            unchecked {
                ++i;
            }
        }
    }

    /// @inheritdoc RewardDistributor
    function _registerPosition(address _user, address _market) internal override {
        super._registerPosition(_user, _market);
        if (_lpPositionsPerUser[_user][_market] != 0) {
            _multiplierStartTimeByUser[_user][_market] = block.timestamp;
        }
    }
}
