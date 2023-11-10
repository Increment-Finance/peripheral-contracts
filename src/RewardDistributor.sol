// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.16;

// contracts
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";
import {RewardController} from "./RewardController.sol";

// interfaces
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IClearingHouse} from "increment-protocol/interfaces/IClearingHouse.sol";
import {IPerpetual} from "increment-protocol/interfaces/IPerpetual.sol";
import {IStakingContract} from "increment-protocol/interfaces/IStakingContract.sol";
import {IRewardDistributor} from "./interfaces/IRewardDistributor.sol";

// libraries
import {PRBMathUD60x18} from "prb-math/contracts/PRBMathUD60x18.sol";

/// @title RewardDistributor
/// @author webthethird
/// @notice Abstract contract responsible for accruing and distributing rewards to users for providing
/// liquidity to perpetual markets (handled by PerpRewardDistributor) or staking tokens (with the SafetyModule)
/// @dev Inherits from RewardController, which defines the RewardInfo data structure and functions allowing
/// governance to add/remove reward tokens or update their parameters, and implements IStakingContract, the
/// interface used by the ClearingHouse to update user rewards any time a user's position is updated
abstract contract RewardDistributor is
    IRewardDistributor,
    IStakingContract,
    RewardController
{
    using SafeERC20 for IERC20Metadata;
    using PRBMathUD60x18 for uint256;

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
        public lastDepositTimeByUserByMarket;

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
    constructor(address _ecosystemReserve) {
        ecosystemReserve = _ecosystemReserve;
    }

    /* ****************** */
    /*   Market Getters   */
    /* ****************** */

    /// @inheritdoc RewardController
    function getNumMarkets() public view virtual override returns (uint256);

    /// @inheritdoc RewardController
    function getMaxMarketIdx() public view virtual override returns (uint256);

    /// @inheritdoc RewardController
    function getMarketAddress(
        uint256 index
    ) public view virtual override returns (address);

    /// @inheritdoc RewardController
    function getMarketIdx(
        uint256 i
    ) public view virtual override returns (uint256);

    /// @inheritdoc RewardController
    function getCurrentPosition(
        address lp,
        address market
    ) public view virtual override returns (uint256);

    /* ****************** */
    /*   Reward Accrual   */
    /* ****************** */

    /// @inheritdoc RewardController
    function updateMarketRewards(address market) public override {
        if (rewardTokensPerMarket[market].length == 0) return;
        uint256 liquidity = totalLiquidityPerMarket[market];
        uint256 deltaTime = block.timestamp - timeOfLastCumRewardUpdate[market];
        if (deltaTime == 0) return;
        if (liquidity == 0) {
            timeOfLastCumRewardUpdate[market] = block.timestamp;
            return;
        }
        for (uint256 i; i < rewardTokensPerMarket[market].length; ++i) {
            address token = rewardTokensPerMarket[market][i];
            uint256 weightIdx = getMarketWeightIdx(token, market);
            RewardInfo memory rewardInfo = rewardInfoByToken[token];
            if (
                rewardInfo.paused ||
                rewardInfo.initialInflationRate == 0 ||
                rewardInfo.marketWeights[weightIdx] == 0
            ) continue;
            uint16 marketWeight = rewardInfo.marketWeights[weightIdx];
            uint256 totalTimeElapsed = block.timestamp -
                rewardInfo.initialTimestamp;
            // Calculate the new cumRewardPerLpToken by adding (inflationRatePerSecond x marketWeight x deltaTime) / liquidity to the previous cumRewardPerLpToken
            uint256 inflationRate = (
                rewardInfo.initialInflationRate.div(
                    rewardInfo.reductionFactor.pow(
                        totalTimeElapsed.div(365 days)
                    )
                )
            );
            uint256 newRewards = (((((inflationRate * marketWeight) / 10000) *
                deltaTime) / 365 days) * 1e18) / liquidity;
            if (newRewards > 0) {
                cumulativeRewardPerLpToken[token][market] += newRewards;
                emit RewardAccruedToMarket(market, token, newRewards);
            }
        }
        // Set timeOfLastCumRewardUpdate to the currentTime
        timeOfLastCumRewardUpdate[market] = block.timestamp;
    }

    /// @notice Accrues rewards and updates the stored position of a user and the total liquidity of a market
    /// @dev Executes whenever a user's position is updated for any reason
    /// @param market Address of the market (i.e., perpetual market or staking token)
    /// @param user Address of the user
    function updateStakingPosition(
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
    ) external onlyRole(GOVERNANCE) {
        if (timeOfLastCumRewardUpdate[_market] != 0)
            revert RewardDistributor_AlreadyInitializedStartTime(_market);
        timeOfLastCumRewardUpdate[_market] = block.timestamp;
    }

    /// @inheritdoc IRewardDistributor
    /// @dev Can only be called by governance
    function addRewardToken(
        address _rewardToken,
        uint256 _initialInflationRate,
        uint256 _initialReductionFactor,
        address[] calldata _markets,
        uint16[] calldata _marketWeights
    ) external nonReentrant onlyRole(GOVERNANCE) {
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
        // Validate weights
        uint16 totalWeight;
        for (uint i; i < _markets.length; ++i) {
            address market = _markets[i];
            updateMarketRewards(market);
            uint16 weight = _marketWeights[i];
            if (weight == 0) continue;
            if (weight > 10000)
                revert RewardController_WeightExceedsMax(weight, 10000);
            if (rewardTokensPerMarket[market].length >= MAX_REWARD_TOKENS)
                revert RewardController_AboveMaxRewardTokens(
                    MAX_REWARD_TOKENS,
                    market
                );
            totalWeight += weight;
            rewardTokensPerMarket[market].push(_rewardToken);
            emit NewWeight(market, _rewardToken, weight);
        }
        if (totalWeight != 10000)
            revert RewardController_IncorrectWeightsSum(totalWeight, 10000);
        // Add reward token info
        rewardInfoByToken[_rewardToken] = RewardInfo({
            token: IERC20Metadata(_rewardToken),
            paused: false,
            initialTimestamp: block.timestamp,
            initialInflationRate: _initialInflationRate,
            reductionFactor: _initialReductionFactor,
            marketAddresses: _markets,
            marketWeights: _marketWeights
        });
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
        address _token
    ) external nonReentrant onlyRole(GOVERNANCE) {
        RewardInfo memory rewardInfo = rewardInfoByToken[_token];
        if (_token == address(0) || rewardInfo.token != IERC20Metadata(_token))
            revert RewardController_InvalidRewardTokenAddress(_token);
        // Update rewards for all markets before removal
        for (uint i; i < rewardInfo.marketAddresses.length; ++i) {
            address market = rewardInfo.marketAddresses[i];
            updateMarketRewards(market);
            // The `delete` keyword applied to arrays does not reduce array length
            uint256 numRewards = rewardTokensPerMarket[market].length;
            for (uint j = 0; j < numRewards; ++j) {
                if (rewardTokensPerMarket[market][j] != _token) continue;
                // Find the token in the array and swap it with the last element
                rewardTokensPerMarket[market][j] = rewardTokensPerMarket[
                    market
                ][numRewards - 1];
                // Delete the last element
                rewardTokensPerMarket[market].pop();
                break;
            }
        }
        delete rewardInfoByToken[_token];
        // Determine how much of the removed token should be sent back to governance
        uint256 balance = _rewardTokenBalance(_token);
        uint256 unclaimedAccruals = totalUnclaimedRewards[_token];
        uint256 unaccruedBalance = balance >= unclaimedAccruals
            ? balance - unclaimedAccruals
            : 0;
        // Transfer remaining tokens to governance (which is the sender)
        if (unaccruedBalance > 0)
            IERC20Metadata(_token).safeTransferFrom(
                ecosystemReserve,
                msg.sender,
                unaccruedBalance
            );
        emit RewardTokenRemoved(_token, unclaimedAccruals, unaccruedBalance);
    }

    /// @inheritdoc IRewardDistributor
    /// @dev Can only be called by governance
    function setEcosystemReserve(
        address _ecosystemReserve
    ) external onlyRole(GOVERNANCE) {
        if (_ecosystemReserve == address(0))
            revert RewardDistributor_InvalidEcosystemReserve(_ecosystemReserve);
        address prevEcosystemReserve = ecosystemReserve;
        ecosystemReserve = _ecosystemReserve;
        emit EcosystemReserveUpdated(prevEcosystemReserve, _ecosystemReserve);
    }

    /* ****************** */
    /*    External User   */
    /* ****************** */

    /// @inheritdoc IRewardDistributor
    function registerPositions() external nonReentrant {
        uint256 numMarkets = getNumMarkets();
        for (uint i; i < numMarkets; ++i) {
            address market = getMarketAddress(getMarketIdx(i));
            if (lpPositionsPerUser[msg.sender][market] != 0)
                revert RewardDistributor_PositionAlreadyRegistered(
                    msg.sender,
                    market,
                    lpPositionsPerUser[msg.sender][market]
                );
            uint256 lpPosition = getCurrentPosition(msg.sender, market);
            lpPositionsPerUser[msg.sender][market] = lpPosition;
            totalLiquidityPerMarket[market] += lpPosition;
        }
    }

    /// @inheritdoc IRewardDistributor
    function registerPositions(
        address[] calldata _markets
    ) external nonReentrant {
        for (uint i; i < _markets.length; ++i) {
            address market = _markets[i];
            if (lpPositionsPerUser[msg.sender][market] != 0)
                revert RewardDistributor_PositionAlreadyRegistered(
                    msg.sender,
                    market,
                    lpPositionsPerUser[msg.sender][market]
                );
            uint256 lpPosition = getCurrentPosition(msg.sender, market);
            lpPositionsPerUser[msg.sender][market] = lpPosition;
            totalLiquidityPerMarket[market] += lpPosition;
        }
    }

    /// @inheritdoc IRewardDistributor
    function claimRewards() public override {
        claimRewardsFor(msg.sender);
    }

    /// @inheritdoc IRewardDistributor
    function claimRewardsFor(address _user) public override {
        for (uint i; i < getNumMarkets(); ++i) {
            uint256 idx = getMarketIdx(i);
            address market = getMarketAddress(idx);
            claimRewardsFor(_user, market);
        }
    }

    /// @inheritdoc IRewardDistributor
    function claimRewardsFor(address _user, address _market) public override {
        claimRewardsFor(_user, rewardTokensPerMarket[_market]);
    }

    /// @inheritdoc IRewardDistributor
    function claimRewardsFor(
        address _user,
        address[] memory _rewardTokens
    ) public override whenNotPaused {
        for (uint i; i < getNumMarkets(); ++i) {
            address market = getMarketAddress(getMarketIdx(i));
            accrueRewards(market, _user);
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

    /// @inheritdoc IRewardDistributor
    function accrueRewards(address user) external override {
        for (uint i; i < getNumMarkets(); ++i) {
            address market = getMarketAddress(getMarketIdx(i));
            accrueRewards(market, user);
        }
    }

    /// @inheritdoc IRewardDistributor
    function accrueRewards(address market, address user) public virtual;

    /// @inheritdoc IRewardDistributor
    function viewNewRewardAccrual(
        address market,
        address user
    ) public view returns (uint256[] memory) {
        uint256[] memory newRewards = new uint256[](
            rewardTokensPerMarket[market].length
        );
        for (uint i; i < rewardTokensPerMarket[market].length; ++i) {
            address token = rewardTokensPerMarket[market][i];
            newRewards[i] = viewNewRewardAccrual(market, user, token);
        }
        return newRewards;
    }

    /// @inheritdoc IRewardDistributor
    function viewNewRewardAccrual(
        address market,
        address user,
        address token
    ) public view virtual returns (uint256);

    /* ****************** */
    /*      Internal      */
    /* ****************** */

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
        IERC20Metadata rewardToken = IERC20Metadata(_token);
        if (_amount <= rewardsRemaining) {
            rewardToken.safeTransferFrom(ecosystemReserve, _to, _amount);
            totalUnclaimedRewards[_token] -= _amount;
            return 0;
        } else {
            rewardToken.safeTransferFrom(
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
        IERC20Metadata rewardToken = IERC20Metadata(_token);
        return rewardToken.balanceOf(ecosystemReserve);
    }
}
