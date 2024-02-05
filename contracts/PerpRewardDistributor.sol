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
    /// @dev Executes whenever a user's liquidity is updated for any reason
    /// @param market Address of the perpetual market
    /// @param user Address of the liquidity provier
    function updatePosition(address market, address user) external virtual override onlyClearingHouse {
        _updateMarketRewards(market);
        uint256 prevLpPosition = _lpPositionsPerUser[user][market];
        uint256 newLpPosition = _getCurrentPosition(user, market);
        uint256 numTokens = rewardTokens.length;
        for (uint256 i; i < numTokens;) {
            address token = rewardTokens[i];
            // newRewards = user.lpBalance x (global.cumRewardPerLpToken - user.cumRewardPerLpToken)
            uint256 newRewards = prevLpPosition.mul(
                _cumulativeRewardPerLpToken[token][market] - _cumulativeRewardPerLpTokenPerUser[user][token][market]
            );
            if (newLpPosition >= prevLpPosition) {
                // Added liquidity - reset early withdrawal timer
                _withdrawTimerStartByUserByMarket[user][market] = block.timestamp;
            } else {
                // Removed liquidity - need to check if within early withdrawal threshold
                uint256 deltaTime = block.timestamp - _withdrawTimerStartByUserByMarket[user][market];
                if (deltaTime < _earlyWithdrawalThreshold) {
                    // Early withdrawal - apply penalty
                    newRewards -= (newRewards * (_earlyWithdrawalThreshold - deltaTime)) / _earlyWithdrawalThreshold;
                }
                if (newLpPosition != 0) {
                    // Reset timer
                    _withdrawTimerStartByUserByMarket[user][market] = block.timestamp;
                } else {
                    // Full withdrawal, so next deposit is an initial deposit
                    _withdrawTimerStartByUserByMarket[user][market] = 0;
                }
            }
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
        _totalLiquidityPerMarket[market] = _totalLiquidityPerMarket[market] + newLpPosition - prevLpPosition;
        _lpPositionsPerUser[user][market] = newLpPosition;
        emit PositionUpdated(user, market, prevLpPosition, newLpPosition);
    }

    /* ****************** */
    /*   External Views   */
    /* ****************** */

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
        // Do not accrue rewards for the given market before the early withdrawal threshold has passed
        if (block.timestamp < _withdrawTimerStartByUserByMarket[user][market] + _earlyWithdrawalThreshold) return;
        uint256 lpPosition = _lpPositionsPerUser[user][market];
        if (lpPosition != _getCurrentPosition(user, market)) {
            // only occurs if the user has a pre-existing liquidity position and has not registered for rewards,
            // since updating LP position calls updatePosition which updates _lpPositionsPerUser
            revert RewardDistributor_UserPositionMismatch(user, market, lpPosition, _getCurrentPosition(user, market));
        }
        if (_totalLiquidityPerMarket[market] == 0) return;
        _updateMarketRewards(market);
        uint256 numTokens = rewardTokens.length;
        for (uint256 i; i < numTokens;) {
            address token = rewardTokens[i];
            uint256 newRewards = (
                lpPosition
                    * (_cumulativeRewardPerLpToken[token][market] - _cumulativeRewardPerLpTokenPerUser[user][token][market])
            ) / 1e18;
            _rewardsAccruedByUser[user][token] += newRewards;
            _totalUnclaimedRewards[token] += newRewards;
            _cumulativeRewardPerLpTokenPerUser[user][token][market] = _cumulativeRewardPerLpToken[token][market];
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
}
