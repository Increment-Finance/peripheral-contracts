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

// import {console2 as console} from "forge/console2.sol";

contract RewardDistributor is
    IRewardDistributor,
    IStakingContract,
    RewardController
{
    using SafeERC20 for IERC20Metadata;
    using PRBMathUD60x18 for uint256;

    /// @notice Clearing House contract
    IClearingHouse public clearingHouse;

    /// @notice Address of the token vault
    address public tokenVault;

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

    /// @notice Reward accumulator for market rewards per reward token, as a number of reward tokens per LP token
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
        address _tokenVault,
        uint256 _earlyWithdrawalThreshold,
        uint16[] memory _initialRewardWeights
    ) RewardController(_initialInflationRate, _initialReductionFactor) {
        clearingHouse = IClearingHouse(_clearingHouse);
        tokenVault = _tokenVault;
        earlyWithdrawalThreshold = _earlyWithdrawalThreshold;
        // Add reward token info
        uint256 numMarkets = getNumMarkets();
        rewardInfoByToken[_rewardToken] = RewardInfo({
            token: IERC20Metadata(_rewardToken),
            initialTimestamp: block.timestamp,
            inflationRate: _initialInflationRate,
            reductionFactor: _initialReductionFactor,
            marketAddresses: new address[](numMarkets),
            marketWeights: _initialRewardWeights
        });
        for (uint256 i; i < numMarkets; ++i) {
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
    /*      Markets       */
    /* ****************** */

    /// @inheritdoc RewardController
    function getNumMarkets() public view virtual override returns (uint256) {
        return clearingHouse.getNumMarkets();
    }

    /// @inheritdoc RewardController
    function getMaxMarketIdx() public view virtual override returns (uint256) {
        return clearingHouse.marketIds() - 1;
    }

    /// @inheritdoc RewardController
    function getMarketAddress(
        uint256 index
    ) public view virtual override returns (address) {
        if (index > getMaxMarketIdx())
            revert RewardDistributor_InvalidMarketIndex(
                index,
                getMaxMarketIdx()
            );
        return address(clearingHouse.perpetuals(index));
    }

    /// @inheritdoc RewardController
    function getMarketIdx(
        uint256 i
    ) public view virtual override returns (uint256) {
        return clearingHouse.id(i);
    }

    /// @inheritdoc RewardController
    function getMarketWeightIdx(
        address token,
        address market
    ) public view virtual override returns (uint256) {
        RewardInfo memory rewardInfo = rewardInfoByToken[token];
        for (uint i; i < rewardInfo.marketAddresses.length; ++i) {
            if (rewardInfo.marketAddresses[i] == market) return i;
        }
        revert RewardDistributor_MarketHasNoRewardWeight(market, token);
    }

    /// Returns the current position of the user in the market (i.e., perpetual market)
    /// @param lp Address of the user
    /// @param market Address of the market
    /// @return Current position of the user in the market
    function getCurrentPosition(
        address lp,
        address market
    ) public view virtual returns (uint256) {
        return IPerpetual(market).getLpLiquidity(lp);
    }

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
            if (rewardInfo.marketWeights[weightIdx] == 0) continue;
            uint16 marketWeight = rewardInfo.marketWeights[weightIdx];
            uint256 totalTimeElapsed = block.timestamp -
                rewardInfo.initialTimestamp;
            // Calculate the new cumRewardPerLpToken by adding (inflationRatePerSecond x marketWeight x deltaTime) / liquidity to the previous cumRewardPerLpToken
            uint256 inflationRate = (
                rewardInfo.inflationRate.div(
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
    /*     Governance     */
    /* ****************** */

    /// Sets the start time for accruing rewards to a market which has not been initialized yet
    /// @param _market Address of the market (i.e., perpetual market)
    function initMarketStartTime(
        address _market
    ) external onlyRole(GOVERNANCE) {
        if (timeOfLastCumRewardUpdate[_market] != 0)
            revert RewardDistributor_AlreadyInitializedStartTime(_market);
        timeOfLastCumRewardUpdate[_market] = block.timestamp;
    }

    /// Adds a new reward token
    /// @param _rewardToken Address of the reward token
    /// @param _initialInflationRate Initial inflation rate for the new token
    /// @param _initialReductionFactor Initial reduction factor for the new token
    /// @param _markets Addresses of the markets to reward with the new token
    /// @param _marketWeights Initial weights per market for the new token
    function addRewardToken(
        address _rewardToken,
        uint256 _initialInflationRate,
        uint256 _initialReductionFactor,
        address[] calldata _markets,
        uint16[] calldata _marketWeights
    ) external nonReentrant onlyRole(GOVERNANCE) {
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
                revert RewardController_AboveMaxRewardTokens(MAX_REWARD_TOKENS);
            totalWeight += weight;
            rewardTokensPerMarket[market].push(_rewardToken);
            emit NewWeight(market, _rewardToken, weight);
        }
        if (totalWeight != 10000)
            revert RewardController_IncorrectWeightsSum(totalWeight, 10000);
        // Add reward token info
        rewardInfoByToken[_rewardToken] = RewardInfo({
            token: IERC20Metadata(_rewardToken),
            initialTimestamp: block.timestamp,
            inflationRate: _initialInflationRate,
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

    /// Removes a reward token
    /// @param _token Address of the reward token to remove
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
        IERC20Metadata(_token).safeTransferFrom(
            tokenVault,
            msg.sender,
            unaccruedBalance
        );
        emit RewardTokenRemoved(_token, unclaimedAccruals, unaccruedBalance);
    }

    /* ****************** */
    /*    External User   */
    /* ****************** */

    /// Fetches and stores the caller's LP positions and updates the total liquidity in each market
    /// @dev Can only be called once per user, only necessary if user was an LP prior to this contract's deployment
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

    /// Fetches and stores the caller's LP positions and updates the total liquidity in each market
    /// @dev Can only be called once per user, only necessary if user was an LP prior to this contract's deployment
    /// @param _markets Addresses of the perpetual markets in the ClearingHouse to sync with
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

    /// Accrues and then distributes rewards for all markets to the caller
    function claimRewards() public override {
        claimRewardsFor(msg.sender);
    }

    /// Accrues and then distributes rewards for all markets to the given user
    /// @param _user Address of the user to claim rewards for
    function claimRewardsFor(address _user) public override {
        for (uint i; i < getNumMarkets(); ++i) {
            uint256 idx = getMarketIdx(i);
            address market = getMarketAddress(idx);
            claimRewardsFor(_user, market);
        }
    }

    function claimRewardsFor(address _user, address _market) public override {
        claimRewardsFor(_user, rewardTokensPerMarket[_market]);
    }

    /// Accrues and then distributes rewards for all markets to the given user
    /// @param _user Address of the user to claim rewards for
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

    /// Accrues rewards to a user for all markets
    /// @notice Assumes LP position hasn't changed since last accrual
    /// @dev Updating rewards due to changes in LP position is handled by updateStakingPosition
    /// @param user Address of the user to accrue rewards for
    function accrueRewards(address user) external override {
        for (uint i; i < getNumMarkets(); ++i) {
            address market = getMarketAddress(getMarketIdx(i));
            accrueRewards(market, user);
        }
    }

    /// Accrues rewards to a user for a given market
    /// @notice Assumes LP position hasn't changed since last accrual
    /// @dev Updating rewards due to changes in LP position is handled by updateStakingPosition
    /// @param market Address of the market in ClearingHouse.perpetuals
    /// @param user Address of the user
    function accrueRewards(
        address market,
        address user
    ) public virtual nonReentrant {
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

    /// Returns the amount of rewards that would be accrued to a user for a given market
    /// @notice Serves as a static version of accrueRewards(uint256 idx, address user)
    /// @param market Address of the market in ClearingHouse.perpetuals
    /// @param user Address of the user
    /// @return Amount of new rewards that would be accrued to the user for each reward token
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

    /// Returns the amount of rewards that would be accrued to a user for a given market and reward token
    /// @param market Address of the market in ClearingHouse.perpetuals
    /// @param user Address of the user
    /// @param token Address of the reward token
    /// @return Amount of new rewards that would be accrued to the user
    function viewNewRewardAccrual(
        address market,
        address user,
        address token
    ) public view returns (uint256) {
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
        uint256 liquidity = totalLiquidityPerMarket[market];
        if (timeOfLastCumRewardUpdate[market] == 0)
            revert RewardDistributor_UninitializedStartTime(market);
        uint256 deltaTime = block.timestamp - timeOfLastCumRewardUpdate[market];
        if (liquidity == 0) return 0;
        RewardInfo memory rewardInfo = rewardInfoByToken[token];
        uint256 totalTimeElapsed = block.timestamp -
            rewardInfo.initialTimestamp;
        // Calculate the new cumRewardPerLpToken by adding (inflationRatePerSecond x guageWeight x deltaTime) to the previous cumRewardPerLpToken
        uint256 inflationRate = rewardInfo.inflationRate.div(
            rewardInfo.reductionFactor.pow(totalTimeElapsed.div(365 days))
        );
        uint256 weightIdx = getMarketWeightIdx(token, market);
        uint256 newMarketRewards = (((inflationRate *
            rewardInfo.marketWeights[weightIdx]) / 10000) * deltaTime) /
            365 days;
        uint256 newCumRewardPerLpToken = cumulativeRewardPerLpToken[token][
            market
        ] + (newMarketRewards * 1e18) / liquidity;
        uint256 newUserRewards = lpPosition.mul(
            (newCumRewardPerLpToken -
                cumulativeRewardPerLpTokenPerUser[user][token][market])
        );
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
        if (_amount <= rewardsRemaining) {
            rewardToken.safeTransferFrom(tokenVault, _to, _amount);
            totalUnclaimedRewards[_token] -= _amount;
            return 0;
        } else {
            rewardToken.safeTransferFrom(tokenVault, _to, rewardsRemaining);
            totalUnclaimedRewards[_token] -= rewardsRemaining;
            return _amount - rewardsRemaining;
        }
    }

    function _rewardTokenBalance(
        address _token
    ) internal view returns (uint256) {
        IERC20Metadata rewardToken = IERC20Metadata(_token);
        return rewardToken.balanceOf(tokenVault);
    }
}
