// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.16;

// contracts
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";
import {RewardController, IRewardController} from "./RewardController.sol";

// interfaces
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IClearingHouse} from "increment-protocol/interfaces/IClearingHouse.sol";
import {IPerpetual} from "increment-protocol/interfaces/IPerpetual.sol";
import {IRewardDistributor} from "./interfaces/IRewardDistributor.sol";

// libraries
import {PRBMathUD60x18, PRBMath} from "prb-math/contracts/PRBMathUD60x18.sol";

/// @title RewardDistributor
/// @author webthethird
/// @notice Abstract contract responsible for accruing and distributing rewards to users for providing
/// liquidity to perpetual markets (handled by PerpRewardDistributor) or staking tokens (with the SafetyModule)
/// @dev Inherits from RewardController, which defines the RewardInfo data structure and functions allowing
/// governance to add/remove reward tokens or update their parameters, and implements IRewardContract, the
/// interface used by the ClearingHouse to update user rewards any time a user's position is updated
abstract contract RewardDistributor is IRewardDistributor, RewardController {
    using SafeERC20 for IERC20Metadata;
    using PRBMath for uint256;
    using PRBMathUD60x18 for uint256;
    using PRBMathUD60x18 for uint88;

    /// @notice Address of the reward token vault
    address public immutable ecosystemReserve;

    /// @notice Rewards accrued and not yet claimed by user
    /// @dev First address is user, second is reward token
    mapping(address => mapping(address => uint256)) internal _rewardsAccruedByUser;

    /// @notice Total rewards accrued and not claimed by all users
    /// @dev Address is reward token
    mapping(address => uint256) internal _totalUnclaimedRewards;

    /// @notice Latest LP/staking positions per user and market
    /// @dev First address is user, second is the market
    mapping(address => mapping(address => uint256)) internal _lpPositionsPerUser;

    /// @notice Reward accumulator for market rewards per reward token, as a number of reward tokens
    /// per LP/staked token
    /// @dev First address is reward token, second is the market
    mapping(address => mapping(address => uint256)) internal _cumulativeRewardPerLpToken;

    /// @notice Reward accumulator value per reward token when user rewards were last updated
    /// @dev First address is user, second is reward token, third is the market
    mapping(address => mapping(address => mapping(address => uint256))) internal _cumulativeRewardPerLpTokenPerUser;

    /// @notice Timestamp of the most recent update to the per-market reward accumulator
    mapping(address => uint256) internal _timeOfLastCumRewardUpdate;

    /// @notice Total LP/staked tokens registered for rewards per market
    mapping(address => uint256) internal _totalLiquidityPerMarket;

    /// @notice RewardDistributor constructor
    /// @param _ecosystemReserve Address of the EcosystemReserve contract, which holds the reward tokens
    constructor(address _ecosystemReserve) payable {
        ecosystemReserve = _ecosystemReserve;
    }

    /* ****************** */
    /*   External Views   */
    /* ****************** */

    /// @inheritdoc IRewardDistributor
    function rewardsAccruedByUser(address _user, address _rewardToken) external view returns (uint256) {
        return _rewardsAccruedByUser[_user][_rewardToken];
    }

    /// @inheritdoc IRewardDistributor
    function totalUnclaimedRewards(address _rewardToken) external view returns (uint256) {
        return _totalUnclaimedRewards[_rewardToken];
    }

    /// @inheritdoc IRewardDistributor
    function lpPositionsPerUser(address _user, address _market) external view returns (uint256) {
        return _lpPositionsPerUser[_user][_market];
    }

    /// @inheritdoc IRewardDistributor
    function cumulativeRewardPerLpToken(address _rewardToken, address _market) external view returns (uint256) {
        return _cumulativeRewardPerLpToken[_rewardToken][_market];
    }

    /// @inheritdoc IRewardDistributor
    function cumulativeRewardPerLpTokenPerUser(address _user, address _rewardToken, address _market)
        external
        view
        returns (uint256)
    {
        return _cumulativeRewardPerLpTokenPerUser[_user][_rewardToken][_market];
    }

    /// @inheritdoc IRewardDistributor
    function timeOfLastCumRewardUpdate(address _market) external view returns (uint256) {
        return _timeOfLastCumRewardUpdate[_market];
    }

    /// @inheritdoc IRewardDistributor
    function totalLiquidityPerMarket(address _market) external view returns (uint256) {
        return _totalLiquidityPerMarket[_market];
    }

    /* ****************** */
    /*     Governance     */
    /* ****************** */

    /// @inheritdoc IRewardDistributor
    /// @dev Can only be called by governance
    function addRewardToken(
        address _rewardToken,
        uint88 _initialInflationRate,
        uint88 _initialReductionFactor,
        address[] calldata _markets,
        uint256[] calldata _marketWeights
    ) external onlyRole(GOVERNANCE) {
        if (_initialInflationRate > MAX_INFLATION_RATE) {
            revert RewardController_AboveMaxInflationRate(_initialInflationRate, MAX_INFLATION_RATE);
        }
        if (MIN_REDUCTION_FACTOR > _initialReductionFactor) {
            revert RewardController_BelowMinReductionFactor(_initialReductionFactor, MIN_REDUCTION_FACTOR);
        }
        if (_marketWeights.length != _markets.length) {
            revert RewardController_IncorrectWeightsCount(_marketWeights.length, _markets.length);
        }
        if (rewardTokens.length >= MAX_REWARD_TOKENS) {
            revert RewardController_AboveMaxRewardTokens(MAX_REWARD_TOKENS);
        }

        uint256 totalWeight;
        uint256 numMarkets = _markets.length;
        for (uint256 i; i < numMarkets;) {
            // Accrue other reward tokens to all markets before adding a new reward token
            address market = _markets[i];
            _updateMarketRewards(market);
            // Reset each market's reward accumulator for the new reward token, in case
            // the token was previously removed and is being re-added
            delete _cumulativeRewardPerLpToken[_rewardToken][market];
            // Validate weights
            uint256 weight = _marketWeights[i];
            if (weight == 0) {
                unchecked {
                    ++i; // saves 63 gas per iteration
                }
                continue;
            }
            if (weight > MAX_BASIS_POINTS) {
                revert RewardController_WeightExceedsMax(weight, MAX_BASIS_POINTS);
            }
            totalWeight += weight;
            // Store the market's weight for the new reward token
            _marketWeightsByToken[_rewardToken][market] = weight;
            emit NewWeight(market, _rewardToken, weight);
            unchecked {
                ++i; // saves 63 gas per iteration
            }
        }
        if (totalWeight != MAX_BASIS_POINTS) {
            revert RewardController_IncorrectWeightsSum(totalWeight, MAX_BASIS_POINTS);
        }
        // Add reward token info
        rewardTokens.push(_rewardToken);
        _rewardInfoByToken[_rewardToken].token = IERC20Metadata(_rewardToken);
        _rewardInfoByToken[_rewardToken].initialTimestamp = uint80(block.timestamp);
        _rewardInfoByToken[_rewardToken].initialInflationRate = _initialInflationRate;
        _rewardInfoByToken[_rewardToken].reductionFactor = _initialReductionFactor;
        _rewardInfoByToken[_rewardToken].marketAddresses = _markets;

        emit RewardTokenAdded(_rewardToken, block.timestamp, _initialInflationRate, _initialReductionFactor);
    }

    /// @inheritdoc IRewardDistributor
    /// @dev Can only be called by governance
    function removeRewardToken(address _rewardToken) external onlyRole(GOVERNANCE) {
        if (_rewardToken == address(0) || _rewardInfoByToken[_rewardToken].token != IERC20Metadata(_rewardToken)) {
            revert RewardController_InvalidRewardTokenAddress(_rewardToken);
        }

        // Clear the market's weight for the reward token after updating market rewards
        uint256 numMarkets = _rewardInfoByToken[_rewardToken].marketAddresses.length;
        for (uint256 i; i < numMarkets;) {
            address market = _rewardInfoByToken[_rewardToken].marketAddresses[i];
            delete _marketWeightsByToken[_rewardToken][market];
            unchecked {
                ++i; // saves 63 gas per iteration
            }
        }

        // Remove reward token address from list
        // The `delete` keyword applied to arrays does not reduce array length
        uint256 numRewards = rewardTokens.length;
        for (uint256 i; i < numRewards;) {
            if (rewardTokens[i] != _rewardToken) {
                unchecked {
                    ++i; // saves 63 gas per iteration
                }
                continue;
            }
            // Find the token in the array and swap it with the last element
            rewardTokens[i] = rewardTokens[numRewards - 1];
            // Delete the last element
            rewardTokens.pop();
            break;
        }
        // Delete reward token info
        delete _rewardInfoByToken[_rewardToken];

        // Determine how much of the removed token should be sent back to governance
        uint256 balance = _rewardTokenBalance(_rewardToken);
        uint256 unclaimedAccruals = _totalUnclaimedRewards[_rewardToken];
        uint256 unaccruedBalance;
        if (balance >= unclaimedAccruals) {
            unaccruedBalance = balance - unclaimedAccruals;
            // Transfer remaining tokens to governance (which is the sender)
            IERC20Metadata(_rewardToken).safeTransferFrom(ecosystemReserve, msg.sender, unaccruedBalance);
        }

        emit RewardTokenRemoved(_rewardToken, unclaimedAccruals, unaccruedBalance);
    }

    /* ****************** */
    /*    External User   */
    /* ****************** */

    /// @inheritdoc IRewardDistributor
    function registerPositions(address[] calldata _markets) external {
        uint256 numMarkets = _markets.length;
        for (uint256 i; i < numMarkets;) {
            address market = _markets[i];
            _registerPosition(msg.sender, market);
            unchecked {
                ++i; // saves 63 gas per iteration
            }
        }
    }

    /// @inheritdoc IRewardDistributor
    function claimRewards() public override {
        claimRewards(rewardTokens);
    }

    /// @inheritdoc IRewardDistributor
    /// @dev Non-reentrant because `_distributeReward` transfers reward tokens to the user
    function claimRewards(address[] memory _rewardTokens) public override nonReentrant whenNotPaused {
        uint256 numMarkets = _getNumMarkets();
        for (uint256 i; i < numMarkets;) {
            _accrueRewards(_getMarketAddress(_getMarketIdx(i)), msg.sender);
            unchecked {
                ++i; // saves 63 gas per iteration
            }
        }
        uint256 numTokens = _rewardTokens.length;
        for (uint256 i; i < numTokens;) {
            address token = _rewardTokens[i];
            uint256 rewards = _rewardsAccruedByUser[msg.sender][token];
            if (rewards != 0) {
                uint256 remainingRewards = _distributeReward(token, msg.sender, rewards);
                _rewardsAccruedByUser[msg.sender][token] = remainingRewards;
                if (rewards != remainingRewards) {
                    emit RewardClaimed(msg.sender, token, rewards - remainingRewards);
                }
                if (remainingRewards != 0) {
                    emit RewardTokenShortfall(token, _totalUnclaimedRewards[token]);
                }
            }
            unchecked {
                ++i; // saves 63 gas per iteration
            }
        }
    }

    /* ****************** */
    /*      Internal      */
    /* ****************** */

    /// @inheritdoc RewardController
    function _updateMarketRewards(address market) internal override {
        uint256 numTokens = rewardTokens.length;
        uint256 deltaTime = block.timestamp - _timeOfLastCumRewardUpdate[market];
        if (deltaTime == 0 || numTokens == 0) return;
        if (deltaTime == block.timestamp || _totalLiquidityPerMarket[market] == 0) {
            // Either the market has never been updated or it has no liquidity,
            // so just initialize the timeOfLastCumRewardUpdate and return
            _timeOfLastCumRewardUpdate[market] = block.timestamp;
            return;
        }
        // Each reward token has one reward accumulator per market, so loop over reward tokens and
        // update each accumulator for the given market
        for (uint256 i; i < numTokens;) {
            address token = rewardTokens[i];
            // Do not accrue rewards if:
            // - the reward token is paused
            // - the token's inflation rate is set to 0
            // - the market has no reward weight for the token
            if (
                _rewardInfoByToken[token].paused || _rewardInfoByToken[token].initialInflationRate == 0
                    || _marketWeightsByToken[token][market] == 0
            ) {
                unchecked {
                    ++i; // saves 63 gas per iteration
                }
                continue;
            }
            // Calculate the new rewards for the given market and reward token as
            // (inflationRatePerSecond x marketWeight x deltaTime) / totalLiquidity
            // Note: we divide by totalLiquidity here so users receive rewards proportional to their fraction
            // of the total liquidity, which may change in between any given user's actions, once we multiply
            // the difference in accumulator values by the user's position size in `updatePosition`. We also
            // upscale the accumulator value by 1e18 to avoid precision loss when dividing by totalLiquidity.
            // Note: using `mulDiv` and `div` here adds ~45 gas per iteration, but greatly improves readability.
            uint256 newRewards = getInflationRate(token).mulDiv(_marketWeightsByToken[token][market], MAX_BASIS_POINTS)
                .mulDiv(deltaTime, 365 days).div(_totalLiquidityPerMarket[market]);
            if (newRewards != 0) {
                _cumulativeRewardPerLpToken[token][market] += newRewards;
                emit RewardAccruedToMarket(market, token, newRewards);
            }
            unchecked {
                ++i; // saves 63 gas per iteration
            }
        }
        // Set timeOfLastCumRewardUpdate to the currentTime
        _timeOfLastCumRewardUpdate[market] = block.timestamp;
    }

    /// @notice Accrues rewards to a user for a given market
    /// @dev Assumes user's position hasn't changed since last accrual, since updating rewards due to changes in
    /// position is handled by `updatePosition`
    /// @param market Address of the market to accrue rewards for
    /// @param user Address of the user
    function _accrueRewards(address market, address user) internal virtual;

    /// @notice Distributes accrued rewards from the ecosystem reserve to a user for a given reward token
    /// @dev Checks if there are enough rewards remaining in the ecosystem reserve to distribute, updates
    /// `totalUnclaimedRewards`, and returns the amount of rewards that were not distributed
    /// @param _token Address of the reward token
    /// @param _to Address of the user to distribute rewards to
    /// @param _amount Amount of rewards to distribute
    /// @return Amount of rewards that were not distributed
    function _distributeReward(address _token, address _to, uint256 _amount) internal returns (uint256) {
        uint256 rewardsRemaining = _rewardTokenBalance(_token);
        if (rewardsRemaining == 0) return _amount;
        if (_amount <= rewardsRemaining) {
            _totalUnclaimedRewards[_token] -= _amount;
            IERC20Metadata(_token).safeTransferFrom(ecosystemReserve, _to, _amount);
            return 0;
        } else {
            _totalUnclaimedRewards[_token] -= rewardsRemaining;
            IERC20Metadata(_token).safeTransferFrom(ecosystemReserve, _to, rewardsRemaining);
            return _amount - rewardsRemaining;
        }
    }

    /// @notice Gets the current balance of a reward token in the ecosystem reserve
    /// @param _token Address of the reward token
    /// @return Balance of the reward token in the ecosystem reserve
    function _rewardTokenBalance(address _token) internal view returns (uint256) {
        return IERC20Metadata(_token).balanceOf(ecosystemReserve);
    }

    /// @notice Registers a user's pre-existing position for a given market
    /// @dev User should have a position predating this contract's deployment, which can only be registered once
    /// @param _user Address of the user to register
    /// @param _market Address of the market for which to register the user's position
    function _registerPosition(address _user, address _market) internal virtual {
        if (_lpPositionsPerUser[_user][_market] != 0) {
            revert RewardDistributor_PositionAlreadyRegistered(_user, _market, _lpPositionsPerUser[_user][_market]);
        }
        uint256 lpPosition = _getCurrentPosition(_user, _market);
        if (lpPosition == 0) return;
        _updateMarketRewards(_market);
        _lpPositionsPerUser[_user][_market] = lpPosition;
        _totalLiquidityPerMarket[_market] += lpPosition;
        uint256 numTokens = rewardTokens.length;
        for (uint256 i; i < numTokens;) {
            address token = rewardTokens[i];
            _cumulativeRewardPerLpTokenPerUser[_user][token][_market] = _cumulativeRewardPerLpToken[token][_market];
            unchecked {
                ++i; // saves 63 gas per iteration
            }
        }
        emit PositionUpdated(_user, _market, 0, lpPosition);
    }

    /// @inheritdoc RewardController
    function _getNumMarkets() internal view virtual override returns (uint256);

    /// @inheritdoc RewardController
    function _getMarketAddress(uint256 idx) internal view virtual override returns (address);

    /// @inheritdoc RewardController
    function _getMarketIdx(uint256 i) internal view virtual override returns (uint256);

    /// @inheritdoc RewardController
    function _getCurrentPosition(address user, address market) internal view virtual override returns (uint256);
}
