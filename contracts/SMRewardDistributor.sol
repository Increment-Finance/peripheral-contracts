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
    using PRBMathUD60x18 for uint256;

    /// @notice The SafetyModule contract which stores the list of StakedTokens and can call `updatePosition`
    ISafetyModule public safetyModule;

    /// @notice The maximum reward multiplier, scaled by 1e18
    uint256 public maxRewardMultiplier;

    /// @notice The smoothing value, scaled by 1e18
    /// @dev The higher the value, the slower the multiplier approaches its max
    uint256 public smoothingValue;

    /// @notice The starting timestamp used to calculate the user's reward multiplier for a given staking token
    /// @dev First address is user, second is staking token
    mapping(address => mapping(address => uint256)) public multiplierStartTimeByUser;

    /// @notice Modifier for functions that should only be called by the SafetyModule
    modifier onlySafetyModule() {
        if (msg.sender != address(safetyModule)) {
            revert SMRD_CallerIsNotSafetyModule(msg.sender);
        }
        _;
    }

    /// @notice SafetyModule constructor
    /// @param _safetyModule The address of the SafetyModule contract
    /// @param _maxRewardMultiplier The maximum reward multiplier, scaled by 1e18
    /// @param _smoothingValue The smoothing value, scaled by 1e18
    /// @param _ecosystemReserve The address of the EcosystemReserve contract, where reward tokens are stored
    constructor(
        ISafetyModule _safetyModule,
        uint256 _maxRewardMultiplier,
        uint256 _smoothingValue,
        address _ecosystemReserve
    ) payable RewardDistributor(_ecosystemReserve) {
        safetyModule = _safetyModule;
        maxRewardMultiplier = _maxRewardMultiplier;
        smoothingValue = _smoothingValue;
        emit SafetyModuleUpdated(address(0), address(_safetyModule));
        emit MaxRewardMultiplierUpdated(0, _maxRewardMultiplier);
        emit SmoothingValueUpdated(0, _smoothingValue);
    }

    /* ****************** */
    /*   Reward Accrual   */
    /* ****************** */

    /// @notice Accrues rewards and updates the stored stake position of a user and the total tokens staked
    /// @dev Executes whenever a user's stake is updated for any reason
    /// @param market Address of the staking token in `stakingTokens`
    /// @param user Address of the staker
    function updatePosition(address market, address user)
        external
        virtual
        override(IRewardContract, RewardDistributor)
        onlySafetyModule
    {
        _updateMarketRewards(market);
        uint256 prevPosition = lpPositionsPerUser[user][market];
        uint256 newPosition = _getCurrentPosition(user, market);
        totalLiquidityPerMarket[market] = totalLiquidityPerMarket[market] + newPosition - prevPosition;
        uint256 rewardMultiplier = computeRewardMultiplier(user, market);
        uint256 numTokens = rewardTokens.length;
        for (uint256 i; i < numTokens;) {
            address token = rewardTokens[i];
            /// newRewards = user.lpBalance x (global.cumRewardPerLpToken - user.cumRewardPerLpToken) x user.rewardMultiplier
            uint256 newRewards = prevPosition.mul(
                cumulativeRewardPerLpToken[token][market] - cumulativeRewardPerLpTokenPerUser[user][token][market]
            ).mul(rewardMultiplier);
            cumulativeRewardPerLpTokenPerUser[user][token][market] = cumulativeRewardPerLpToken[token][market];
            if (newRewards == 0) {
                unchecked {
                    ++i;
                }
                continue;
            }
            rewardsAccruedByUser[user][token] += newRewards;
            totalUnclaimedRewards[token] += newRewards;
            emit RewardAccruedToUser(user, token, market, newRewards);
            uint256 rewardTokenBalance = _rewardTokenBalance(token);
            if (totalUnclaimedRewards[token] > rewardTokenBalance) {
                emit RewardTokenShortfall(token, totalUnclaimedRewards[token] - rewardTokenBalance);
            }
            unchecked {
                ++i;
            }
        }
        if (prevPosition == 0 || newPosition <= prevPosition) {
            // Removed stake, started cooldown or staked for the first time - need to reset multiplier
            if (newPosition != 0) {
                // Partial removal, cooldown or first stake - reset multiplier to 1
                multiplierStartTimeByUser[user][market] = block.timestamp;
            } else {
                // Full removal - set multiplier to 0 until the user stakes again
                multiplierStartTimeByUser[user][market] = 0;
            }
        } else {
            // User added to their existing stake - need to update multiplier start time
            // To prevent users from gaming the system by staking a small amount early to start the multiplier
            // and then staking a large amount once their multiplier is very high in order to claim a large
            // amount of rewards, we shift the start time of the multiplier forward by an amount proportional
            // to the ratio of the increase in stake (newPosition - prevPosition) to the new position
            multiplierStartTimeByUser[user][market] += (block.timestamp - multiplierStartTimeByUser[user][market]).mul(
                (newPosition - prevPosition).div(newPosition)
            );
        }
        lpPositionsPerUser[user][market] = newPosition;
        emit PositionUpdated(user, market, prevPosition, newPosition);
    }

    /* ****************** */
    /*    External User   */
    /* ****************** */

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
    function computeRewardMultiplier(address _user, address _stakingToken) public view returns (uint256) {
        uint256 startTime = multiplierStartTimeByUser[_user][_stakingToken];
        // If the user has never staked, return zero
        if (startTime == 0) return 0;
        uint256 deltaDays = (block.timestamp - startTime).div(1 days);
        /**
         * Multiplier formula:
         *   maxRewardMultiplier - 1 / ((1 / smoothingValue) * deltaDays + (1 / (maxRewardMultiplier - 1)))
         * = maxRewardMultiplier - smoothingValue / (deltaDays + (smoothingValue / (maxRewardMultiplier - 1)))
         * = maxRewardMultiplier - (smoothingValue * (maxRewardMultiplier - 1)) / ((deltaDays * (maxRewardMultiplier - 1)) + smoothingValue)
         */
        return maxRewardMultiplier
            - (smoothingValue * (maxRewardMultiplier - 1e18))
                / ((deltaDays * (maxRewardMultiplier - 1e18)) / 1e18 + smoothingValue);
    }

    /* ******************* */
    /*    Safety Module    */
    /* ******************* */

    /// @inheritdoc IRewardDistributor
    /// @dev Can only be called by the SafetyModule
    function initMarketStartTime(address _market)
        external
        override(IRewardDistributor, RewardDistributor)
        onlySafetyModule
    {
        if (timeOfLastCumRewardUpdate[_market] != 0) {
            revert RewardDistributor_AlreadyInitializedStartTime(_market);
        }
        timeOfLastCumRewardUpdate[_market] = block.timestamp;
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
    function setMaxRewardMultiplier(uint256 _maxRewardMultiplier) external onlyRole(GOVERNANCE) {
        if (_maxRewardMultiplier < 1e18) {
            revert SMRD_InvalidMaxMultiplierTooLow(_maxRewardMultiplier, 1e18);
        } else if (_maxRewardMultiplier > 10e18) {
            revert SMRD_InvalidMaxMultiplierTooHigh(_maxRewardMultiplier, 10e18);
        }
        emit MaxRewardMultiplierUpdated(maxRewardMultiplier, _maxRewardMultiplier);
        maxRewardMultiplier = _maxRewardMultiplier;
    }

    /// @inheritdoc ISMRewardDistributor
    /// @dev Only callable by governance, reverts if the new value is less than 10e18 or greater than 100e18
    function setSmoothingValue(uint256 _smoothingValue) external onlyRole(GOVERNANCE) {
        if (_smoothingValue < 10e18) {
            revert SMRD_InvalidSmoothingValueTooLow(_smoothingValue, 10e18);
        } else if (_smoothingValue > 100e18) {
            revert SMRD_InvalidSmoothingValueTooHigh(_smoothingValue, 100e18);
        }
        emit SmoothingValueUpdated(smoothingValue, _smoothingValue);
        smoothingValue = _smoothingValue;
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

    /* **************** */
    /*     Internal     */
    /* **************** */

    /// @inheritdoc RewardDistributor
    function _getNumMarkets() internal view virtual override returns (uint256) {
        return safetyModule.getNumStakingTokens();
    }

    /// @inheritdoc RewardDistributor
    function _getMarketAddress(uint256 index) internal view virtual override returns (address) {
        return address(safetyModule.stakingTokens(index));
    }

    /// @inheritdoc RewardDistributor
    function _getMarketIdx(uint256 i) internal view virtual override returns (uint256) {
        return i;
    }

    /// @notice Returns the user's staking token balance
    /// @param staker Address of the user
    /// @param token Address of the staking token
    /// @return Current balance of the user in the staking token
    function _getCurrentPosition(address staker, address token) internal view virtual override returns (uint256) {
        return IStakedToken(token).balanceOf(staker);
    }

    /// @notice Accrues rewards to a user for a given staking token
    /// @dev Assumes stake position hasn't changed since last accrual, since updating rewards due to changes in
    /// stake position is handled by `updatePosition`
    /// @param market Address of the token in `stakingTokens`
    /// @param user Address of the user
    function _accrueRewards(address market, address user) internal virtual override {
        uint256 userPosition = lpPositionsPerUser[user][market];
        if (userPosition != _getCurrentPosition(user, market)) {
            // only occurs if the user has a pre-existing balance and has not registered for rewards,
            // since updating stake position calls updatePosition which updates lpPositionsPerUser
            revert RewardDistributor_UserPositionMismatch(user, market, userPosition, _getCurrentPosition(user, market));
        }
        if (totalLiquidityPerMarket[market] == 0) return;
        _updateMarketRewards(market);
        uint256 rewardMultiplier = computeRewardMultiplier(user, market);
        uint256 numTokens = rewardTokens.length;
        for (uint256 i; i < numTokens;) {
            address token = rewardTokens[i];
            uint256 newRewards = userPosition.mul(
                cumulativeRewardPerLpToken[token][market] - cumulativeRewardPerLpTokenPerUser[user][token][market]
            ).mul(rewardMultiplier);
            cumulativeRewardPerLpTokenPerUser[user][token][market] = cumulativeRewardPerLpToken[token][market];
            if (newRewards == 0) {
                unchecked {
                    ++i;
                }
                continue;
            }
            rewardsAccruedByUser[user][token] += newRewards;
            totalUnclaimedRewards[token] += newRewards;
            emit RewardAccruedToUser(user, token, market, newRewards);
            uint256 rewardTokenBalance = _rewardTokenBalance(token);
            if (totalUnclaimedRewards[token] > rewardTokenBalance) {
                emit RewardTokenShortfall(token, totalUnclaimedRewards[token] - rewardTokenBalance);
            }
            unchecked {
                ++i;
            }
        }
    }

    /// @inheritdoc RewardDistributor
    function _registerPosition(address _user, address _market) internal override {
        super._registerPosition(_user, _market);
        if (lpPositionsPerUser[_user][_market] != 0) {
            multiplierStartTimeByUser[_user][_market] = block.timestamp;
        }
    }
}
