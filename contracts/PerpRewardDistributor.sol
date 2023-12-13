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
    IClearingHouse public clearingHouse;

    /// @notice Amount of time after which LPs can remove liquidity without penalties
    uint256 public override earlyWithdrawalThreshold;

    /// @notice Modifier for functions that can only be called by the ClearingHouse, i.e., `updateStakingPosition`
    modifier onlyClearingHouse() {
        if (msg.sender != address(clearingHouse))
            revert PerpRewardDistributor_CallerIsNotClearingHouse(msg.sender);
        _;
    }

    /// @notice PerpRewardDistributor constructor
    /// @param _initialInflationRate The initial inflation rate for the first reward token, scaled by 1e18
    /// @param _initialReductionFactor The initial reduction factor for the first reward token, scaled by 1e18
    /// @param _rewardToken The address of the first reward token
    /// @param _clearingHouse The address of the ClearingHouse contract, which calls `updateStakingPosition`
    /// @param _ecosystemReserve The address of the EcosystemReserve contract, which stores reward tokens
    /// @param _earlyWithdrawalThreshold The amount of time after which LPs can remove liquidity without penalties
    /// @param _initialRewardWeights The initial reward weights for the first reward token, as basis points
    constructor(
        uint88 _initialInflationRate,
        uint88 _initialReductionFactor,
        address _rewardToken,
        address _clearingHouse,
        address _ecosystemReserve,
        uint256 _earlyWithdrawalThreshold,
        uint256[] memory _initialRewardWeights
    ) payable RewardDistributor(_ecosystemReserve) {
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
        uint256 numMarkets = _getNumMarkets();
        rewardInfoByToken[_rewardToken].token = IERC20Metadata(_rewardToken);
        rewardInfoByToken[_rewardToken].initialTimestamp = uint80(
            block.timestamp
        );
        rewardInfoByToken[_rewardToken]
            .initialInflationRate = _initialInflationRate;
        rewardInfoByToken[_rewardToken]
            .reductionFactor = _initialReductionFactor;
        rewardInfoByToken[_rewardToken].marketAddresses = new address[](
            numMarkets
        );
        for (uint256 i; i < numMarkets; ++i) {
            address market = _getMarketAddress(_getMarketIdx(i));
            rewardInfoByToken[_rewardToken].marketAddresses[i] = market;
            rewardInfoByToken[_rewardToken].marketWeights[
                    market
                ] = _initialRewardWeights[i];
            timeOfLastCumRewardUpdate[market] = block.timestamp;
        }
        rewardTokens.push(_rewardToken);
        emit RewardTokenAdded(
            _rewardToken,
            block.timestamp,
            _initialInflationRate,
            _initialReductionFactor
        );
    }

    /* ****************** */
    /*   Reward Accrual   */
    /* ****************** */

    /// @notice Accrues rewards and updates the stored LP position of a user and the total LP of a market
    /// @dev Executes whenever a user's liquidity is updated for any reason
    /// @param market Address of the perpetual market
    /// @param user Address of the liquidity provier
    function updateStakingPosition(
        address market,
        address user
    ) external virtual override onlyClearingHouse {
        _updateMarketRewards(market);
        uint256 prevLpPosition = lpPositionsPerUser[user][market];
        uint256 newLpPosition = _getCurrentPosition(user, market);
        uint256 numTokens = rewardTokens.length;
        for (uint256 i; i < numTokens; ++i) {
            address token = rewardTokens[i];
            // newRewards = user.lpBalance / global.lpBalance x (global.cumRewardPerLpToken - user.cumRewardPerLpToken)
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

    /// @notice Accrues rewards to a user for a given market
    /// @dev Assumes LP position hasn't changed since last accrual, since updating rewards due to changes in
    /// LP position is handled by `updateStakingPosition`
    /// @param market Address of the market in `ClearingHouse.perpetuals`
    /// @param user Address of the user
    function accrueRewards(
        address market,
        address user
    ) public virtual override {
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
        if (lpPosition != _getCurrentPosition(user, market))
            // only occurs if the user has a pre-existing liquidity position and has not registered for rewards,
            // since updating LP position calls updateStakingPosition which updates lpPositionsPerUser
            revert RewardDistributor_UserPositionMismatch(
                user,
                market,
                lpPosition,
                _getCurrentPosition(user, market)
            );
        if (totalLiquidityPerMarket[market] == 0) return;
        _updateMarketRewards(market);
        uint256 numTokens = rewardTokens.length;
        for (uint i; i < numTokens; ++i) {
            address token = rewardTokens[i];
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
    function setClearingHouse(IClearingHouse _newClearingHouse)
        external
        onlyRole(GOVERNANCE)
    {
        emit ClearingHouseUpdated(address(clearingHouse), address(_newClearingHouse));
        clearingHouse = _newClearingHouse;
    }

    /// @inheritdoc IPerpRewardDistributor
    /// @dev Only callable by governance
    function setEarlyWithdrawalThreshold(uint256 _newEarlyWithdrawalThreshold)
        external
        onlyRole(GOVERNANCE)
    {
        emit EarlyWithdrawalThresholdUpdated(
            earlyWithdrawalThreshold,
            _newEarlyWithdrawalThreshold
        );
        earlyWithdrawalThreshold = _newEarlyWithdrawalThreshold;
    }

    /* ****************** */
    /*      Internal      */
    /* ****************** */

    /// @inheritdoc RewardController
    function _getNumMarkets() internal view override returns (uint256) {
        return clearingHouse.getNumMarkets();
    }

    /// @inheritdoc RewardController
    function _getMarketAddress(
        uint256 idx
    ) internal view override returns (address) {
        return address(clearingHouse.perpetuals(idx));
    }

    /// @inheritdoc RewardController
    function _getMarketIdx(uint256 i) internal view override returns (uint256) {
        return clearingHouse.id(i);
    }

    /// @inheritdoc RewardController
    function _getCurrentPosition(
        address user,
        address market
    ) internal view override returns (uint256) {
        return IPerpetual(market).getLpLiquidity(user);
    }
}
