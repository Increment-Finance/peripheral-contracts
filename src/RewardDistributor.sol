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

    /// @notice Reward accumulator for market rewards per reward token, as a number of reward tokens per LP/staking token
    /// @dev First address is reward token, second is the market
    mapping(address => mapping(address => uint256))
        public cumulativeRewardPerLpToken;

    /// @notice Reward accumulator value per reward token when user rewards were last updated
    /// @dev First address is user, second is reward token, third is the market
    mapping(address => mapping(address => mapping(address => uint256)))
        public cumulativeRewardPerLpTokenPerUser;

    /// @notice Timestamp of the most recent update to the per-market reward accumulator
    mapping(address => uint256) public timeOfLastCumRewardUpdate;

    /// @notice Total LP/staking tokens registered for rewards per market
    mapping(address => uint256) public totalLiquidityPerMarket;

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

    /// Returns the current position of the user in the market (i.e., perpetual market or staked token)
    /// @param lp Address of the user
    /// @param market Address of the market
    /// @return Current position of the user in the market
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

    /// Accrues rewards and updates the stored position of a user and the total liquidity of a market
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

    /// Sets the start time for accruing rewards to a market which has not been initialized yet
    /// @param _market Address of the market (i.e., perpetual market or staking token)
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
        if (unaccruedBalance > 0)
            IERC20Metadata(_token).safeTransferFrom(
                ecosystemReserve,
                msg.sender,
                unaccruedBalance
            );
        emit RewardTokenRemoved(_token, unclaimedAccruals, unaccruedBalance);
    }

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

    /// Fetches and stores the caller's LP/stake positions and updates the total liquidity in each market
    /// @dev Can only be called once per user, only necessary if user was an LP/staker prior to this contract's deployment
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
    /// @notice Assumes user's position hasn't changed since last accrual
    /// @dev Updating rewards due to changes in position is handled by updateStakingPosition
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
    function accrueRewards(address market, address user) public virtual;

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
    /// @return Amount of new rewards that would be accrued to the useridx Index
    function viewNewRewardAccrual(
        address market,
        address user,
        address token
    ) public view virtual returns (uint256);

    /* ****************** */
    /*      Internal      */
    /* ****************** */

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

    function _rewardTokenBalance(
        address _token
    ) internal view returns (uint256) {
        IERC20Metadata rewardToken = IERC20Metadata(_token);
        return rewardToken.balanceOf(ecosystemReserve);
    }
}
