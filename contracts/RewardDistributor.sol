// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.16;

// contracts
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";
import {RewardController, IRewardController} from "./RewardController.sol";

// interfaces
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IClearingHouse} from "increment-protocol/interfaces/IClearingHouse.sol";
import {IPerpetual} from "increment-protocol/interfaces/IPerpetual.sol";
import {IRewardContract} from "increment-protocol/interfaces/IRewardContract.sol";
import {IRewardDistributor} from "./interfaces/IRewardDistributor.sol";

// libraries
import {PRBMathUD60x18} from "prb-math/contracts/PRBMathUD60x18.sol";

/// @title RewardDistributor
/// @author webthethird
/// @notice Abstract contract responsible for accruing and distributing rewards to users for providing
/// liquidity to perpetual markets (handled by PerpRewardDistributor) or staking tokens (with the SafetyModule)
/// @dev Inherits from RewardController, which defines the RewardInfo data structure and functions allowing
/// governance to add/remove reward tokens or update their parameters, and implements IRewardContract, the
/// interface used by the ClearingHouse to update user rewards any time a user's position is updated
abstract contract RewardDistributor is
    IRewardDistributor,
    IRewardContract,
    RewardController
{
    using SafeERC20 for IERC20Metadata;
    using PRBMathUD60x18 for uint256;
    using PRBMathUD60x18 for uint88;

    /// @notice Address of the reward token vault
    address public ecosystemReserve;

    /// @notice Rewards accrued and not yet claimed by user
    /// @dev First address is user, second is reward token
    mapping(address => mapping(address => uint256)) public rewardsAccruedByUser;

    /// @notice Total rewards accrued and not claimed by all users
    /// @dev Address is reward token
    mapping(address => uint256) public totalUnclaimedRewards;

    /// @notice Last timestamp when user withdrew liquidity from a market
    /// @dev First address is user, second is the market
    mapping(address => mapping(address => uint256))
        public withdrawTimerStartByUserByMarket;

    /// @notice Latest LP/staking positions per user and market
    /// @dev First address is user, second is the market
    mapping(address => mapping(address => uint256)) public lpPositionsPerUser;

    /// @notice Reward accumulator for market rewards per reward token, as a number of reward tokens
    /// per LP/staked token
    /// @dev First address is reward token, second is the market
    mapping(address => mapping(address => uint256))
        public cumulativeRewardPerLpToken;

    /// @notice Reward accumulator value per reward token when user rewards were last updated
    /// @dev First address is user, second is reward token, third is the market
    mapping(address => mapping(address => mapping(address => uint256)))
        public cumulativeRewardPerLpTokenPerUser;

    /// @notice Timestamp of the most recent update to the per-market reward accumulator
    mapping(address => uint256) public timeOfLastCumRewardUpdate;

    /// @notice Total LP/staked tokens registered for rewards per market
    mapping(address => uint256) public totalLiquidityPerMarket;

    /// @notice RewardDistributor constructor
    /// @param _ecosystemReserve Address of the EcosystemReserve contract, which holds the reward tokens
    constructor(address _ecosystemReserve) payable {
        ecosystemReserve = _ecosystemReserve;
    }

    /* ****************** */
    /*   Reward Accrual   */
    /* ****************** */

    /// @notice Accrues rewards and updates the stored position of a user and the total liquidity of a market
    /// @dev Executes whenever a user's position is updated for any reason
    /// @param market Address of the market (i.e., perpetual market or staking token)
    /// @param user Address of the user
    function updatePosition(
        address market,
        address user
    ) external virtual;

    /* ****************** */
    /*     Governance     */
    /* ****************** */

    /// @inheritdoc IRewardDistributor
    /// @dev Can only be called by governance
    function initMarketStartTime(
        address _market
    ) external virtual onlyRole(GOVERNANCE) {
        if (timeOfLastCumRewardUpdate[_market] != 0)
            revert RewardDistributor_AlreadyInitializedStartTime(_market);
        timeOfLastCumRewardUpdate[_market] = block.timestamp;
    }

    /// @inheritdoc IRewardDistributor
    /// @dev Can only be called by governance
    function addRewardToken(
        address _rewardToken,
        uint88 _initialInflationRate,
        uint88 _initialReductionFactor,
        address[] calldata _markets,
        uint256[] calldata _marketWeights
    ) external onlyRole(GOVERNANCE) {
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
        if (_marketWeights.length != _markets.length)
            revert RewardController_IncorrectWeightsCount(
                _marketWeights.length,
                _markets.length
            );
        if (rewardTokens.length >= MAX_REWARD_TOKENS)
            revert RewardController_AboveMaxRewardTokens(MAX_REWARD_TOKENS);
        // Validate weights
        uint256 totalWeight;
        uint256 numMarkets = _markets.length;
        for (uint i; i < numMarkets;) {
            address market = _markets[i];
            _updateMarketRewards(market);
            uint256 weight = _marketWeights[i];
            if (weight == 0) {
                unchecked { ++i; }
                continue;
            }
            if (weight > 10000)
                revert RewardController_WeightExceedsMax(
                    weight,
                    10000
                );
            totalWeight += weight;
            marketWeightsByToken[_rewardToken][market] = weight;
            timeOfLastCumRewardUpdate[market] = block.timestamp;
            emit NewWeight(market, _rewardToken, weight);
            unchecked { ++i; }
        }
        if (totalWeight != 10000)
            revert RewardController_IncorrectWeightsSum(totalWeight, 10000);
        // Add reward token info
        rewardTokens.push(_rewardToken);
        rewardInfoByToken[_rewardToken].token = IERC20Metadata(_rewardToken);
        rewardInfoByToken[_rewardToken].initialTimestamp = uint80(
            block.timestamp
        );
        rewardInfoByToken[_rewardToken]
            .initialInflationRate = _initialInflationRate;
        rewardInfoByToken[_rewardToken]
            .reductionFactor = _initialReductionFactor;
        rewardInfoByToken[_rewardToken].marketAddresses = _markets;

        emit RewardTokenAdded(
            _rewardToken,
            block.timestamp,
            _initialInflationRate,
            _initialReductionFactor
        );
    }

    /// @inheritdoc IRewardDistributor
    /// @dev Can only be called by governance
    function removeRewardToken(
        address _rewardToken
    ) external onlyRole(GOVERNANCE) {
        if (
            _rewardToken == address(0) ||
            rewardInfoByToken[_rewardToken].token !=
            IERC20Metadata(_rewardToken)
        ) revert RewardController_InvalidRewardTokenAddress(_rewardToken);

        // Update rewards for all markets before removal
        uint256 numMarkets = rewardInfoByToken[_rewardToken]
            .marketAddresses
            .length;
        for (uint i; i < numMarkets;) {
            _updateMarketRewards(
                rewardInfoByToken[_rewardToken].marketAddresses[i]
            );
            unchecked { ++i; }
        }

        // Remove reward token address from list
        // The `delete` keyword applied to arrays does not reduce array length
        uint256 numRewards = rewardTokens.length;
        for (uint i; i < numRewards; ++i) {
            if (rewardTokens[i] != _rewardToken) {
                unchecked { ++i; }
                continue;
            }
            // Find the token in the array and swap it with the last element
            rewardTokens[i] = rewardTokens[numRewards - 1];
            // Delete the last element
            rewardTokens.pop();
            break;
        }
        // Delete reward token info
        delete rewardInfoByToken[_rewardToken];

        // Determine how much of the removed token should be sent back to governance
        uint256 balance = _rewardTokenBalance(_rewardToken);
        uint256 unclaimedAccruals = totalUnclaimedRewards[_rewardToken];
        uint256 unaccruedBalance;
        if (balance >= unclaimedAccruals) {
            unaccruedBalance = balance - unclaimedAccruals;
            // Transfer remaining tokens to governance (which is the sender)
            IERC20Metadata(_rewardToken).safeTransferFrom(
                ecosystemReserve,
                msg.sender,
                unaccruedBalance
            );
        }

        emit RewardTokenRemoved(
            _rewardToken,
            unclaimedAccruals,
            unaccruedBalance
        );
    }

    /// @inheritdoc IRewardDistributor
    /// @dev Can only be called by governance
    function setEcosystemReserve(
        address _newEcosystemReserve
    ) external onlyRole(GOVERNANCE) {
        if (_newEcosystemReserve == address(0))
            revert RewardDistributor_InvalidZeroAddress(0);
        emit EcosystemReserveUpdated(ecosystemReserve, _newEcosystemReserve);
        ecosystemReserve = _newEcosystemReserve;
    }

    /* ****************** */
    /*    External User   */
    /* ****************** */

    /// @inheritdoc IRewardDistributor
    function registerPositions(address[] calldata _markets) external {
        for (uint i; i < _markets.length; ++i) {
            address market = _markets[i];
            _registerPosition(msg.sender, market);
        }
    }

    /// @inheritdoc IRewardDistributor
    function claimRewardsFor(address _user) public override {
        claimRewardsFor(_user, rewardTokens);
    }

    /// @inheritdoc IRewardDistributor
    function claimRewardsFor(
        address _user,
        address[] memory _rewardTokens
    ) public override nonReentrant whenNotPaused {
        uint256 numMarkets = _getNumMarkets();
        for (uint i; i < numMarkets;) {
            _accrueRewards(_getMarketAddress(_getMarketIdx(i)), _user);
            unchecked { ++i; }
        }
        uint256 numTokens = _rewardTokens.length;
        for (uint i; i < numTokens;) {
            address token = _rewardTokens[i];
            uint256 rewards = rewardsAccruedByUser[_user][token];
            if (rewards != 0) {
                uint256 remainingRewards = _distributeReward(
                    token,
                    _user,
                    rewards
                );
                rewardsAccruedByUser[_user][token] = remainingRewards;
                emit RewardClaimed(_user, token, rewards - remainingRewards);
                if (remainingRewards != 0) {
                    emit RewardTokenShortfall(
                        token,
                        totalUnclaimedRewards[token]
                    );
                }
            }
            unchecked { ++i; }
        }
    }

    /* ****************** */
    /*      Internal      */
    /* ****************** */

    /// @inheritdoc RewardController
    function _updateMarketRewards(address market) internal override {
        uint256 numTokens = rewardTokens.length;
        uint256 deltaTime = block.timestamp - timeOfLastCumRewardUpdate[market];
        if (deltaTime == 0 || numTokens == 0) return;
        if (totalLiquidityPerMarket[market] == 0) {
            timeOfLastCumRewardUpdate[market] = block.timestamp;
            return;
        }
        for (uint256 i; i < numTokens;) {
            address token = rewardTokens[i];
            if (
                rewardInfoByToken[token].paused ||
                rewardInfoByToken[token].initialInflationRate == 0 ||
                marketWeightsByToken[token][market] == 0
            ) {
                unchecked { ++i; }
                continue;
            }
            // Calculate the new cumRewardPerLpToken by adding (inflationRatePerSecond x marketWeight x deltaTime) / liquidity to the previous cumRewardPerLpToken
            uint256 inflationRate = (
                rewardInfoByToken[token].initialInflationRate.div(
                    rewardInfoByToken[token].reductionFactor.pow(
                        (block.timestamp -
                            rewardInfoByToken[token].initialTimestamp).div(
                                365 days
                            )
                    )
                )
            );
            uint256 newRewards = (((((inflationRate *
                marketWeightsByToken[token][market]) / 10000) *
                deltaTime) / 365 days) * 1e18) /
                totalLiquidityPerMarket[market];
            if (newRewards != 0) {
                cumulativeRewardPerLpToken[token][market] += newRewards;
                emit RewardAccruedToMarket(market, token, newRewards);
            }
            unchecked { ++i; }
        }
        // Set timeOfLastCumRewardUpdate to the currentTime
        timeOfLastCumRewardUpdate[market] = block.timestamp;
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
    function _distributeReward(
        address _token,
        address _to,
        uint256 _amount
    ) internal returns (uint256) {
        uint256 rewardsRemaining = _rewardTokenBalance(_token);
        if (rewardsRemaining == 0) return _amount;
        if (_amount <= rewardsRemaining) {
            IERC20Metadata(_token).safeTransferFrom(
                ecosystemReserve,
                _to,
                _amount
            );
            totalUnclaimedRewards[_token] -= _amount;
            return 0;
        } else {
            IERC20Metadata(_token).safeTransferFrom(
                ecosystemReserve,
                _to,
                rewardsRemaining
            );
            totalUnclaimedRewards[_token] -= rewardsRemaining;
            return _amount - rewardsRemaining;
        }
    }

    /// @notice Gets the current balance of a reward token in the ecosystem reserve
    /// @param _token Address of the reward token
    /// @return Balance of the reward token in the ecosystem reserve
    function _rewardTokenBalance(
        address _token
    ) internal view returns (uint256) {
        return IERC20Metadata(_token).balanceOf(ecosystemReserve);
    }

    function _registerPosition(address _user, address _market) internal {
        if (lpPositionsPerUser[_user][_market] != 0)
            revert RewardDistributor_PositionAlreadyRegistered(
                _user,
                _market,
                lpPositionsPerUser[_user][_market]
            );
        uint256 lpPosition = _getCurrentPosition(_user, _market);
        lpPositionsPerUser[_user][_market] = lpPosition;
        totalLiquidityPerMarket[_market] += lpPosition;
    }

    /// @inheritdoc RewardController
    function _getNumMarkets() internal view virtual override returns (uint256);

    /// @inheritdoc RewardController
    function _getMarketAddress(
        uint256 idx
    ) internal view virtual override returns (address);

    /// @inheritdoc RewardController
    function _getMarketIdx(
        uint256 i
    ) internal view virtual override returns (uint256);

    /// @inheritdoc RewardController
    function _getCurrentPosition(
        address user,
        address market
    ) internal view virtual override returns (uint256);
}
