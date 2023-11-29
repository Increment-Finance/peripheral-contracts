// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.16;

// contracts
import {RewardDistributor} from "./RewardDistributor.sol";

// interfaces
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {ISafetyModule, IStakingContract} from "./interfaces/ISafetyModule.sol";
import {IStakedToken, IERC20} from "./interfaces/IStakedToken.sol";
import {IAuctionModule} from "./interfaces/IAuctionModule.sol";

// libraries
import {LibMath} from "@increment/lib/LibMath.sol";
import {PRBMathUD60x18} from "prb-math/contracts/PRBMathUD60x18.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title SafetyModule
/// @author webthethird
/// @notice Handles reward accrual and distribution for staking tokens, and allows governance to auction a
/// percentage of user funds in the event of an insolvency in the vault
/// @dev Auction module and related logic is not yet implemented
contract SafetyModule is ISafetyModule, RewardDistributor {
    using LibMath for uint256;
    using PRBMathUD60x18 for uint256;
    using SafeERC20 for IERC20;

    /// @notice Address of the auction module, which sells user funds in the event of an insolvency
    IAuctionModule public auctionModule;

    /// @notice Array of staking tokens that are registered with the SafetyModule
    IStakedToken[] public stakingTokens;

    /// @notice Mapping from auction ID to staking token that was slashed for the auction
    mapping(uint256 => IStakedToken) public stakingTokenByAuctionId;

    /// @notice The maximum percentage of user funds that can be sold at auction, normalized to 1e18
    uint256 public maxPercentUserLoss;

    /// @notice The maximum reward multiplier, scaled by 1e18
    uint256 public maxRewardMultiplier;

    /// @notice The smoothing value, scaled by 1e18
    /// @dev The higher the value, the slower the multiplier approaches its max
    uint256 public smoothingValue;

    /// @notice Stores the timestamp of the first deposit or most recent withdrawal
    /// @dev First address is user, second is staking token
    mapping(address => mapping(address => uint256))
        public multiplierStartTimeByUser;

    /// @notice Modifier for functions that can only be called by a registered StakedToken contract,
    /// i.e., `updateStakingPosition`
    modifier onlyStakingToken() {
        bool isStakingToken = false;
        for (uint i; i < stakingTokens.length; ++i) {
            if (msg.sender == address(stakingTokens[i])) {
                isStakingToken = true;
                break;
            }
        }
        if (!isStakingToken)
            revert SafetyModule_CallerIsNotStakingToken(msg.sender);
        _;
    }

    /// @notice Modifier for functions that can only be called by the AuctionModule contract,
    /// i.e., `auctionEnded`
    modifier onlyAuctionModule() {
        if (msg.sender != address(auctionModule))
            revert SafetyModule_CallerIsNotAuctionModule(msg.sender);
        _;
    }

    /// @notice SafetyModule constructor
    /// @param _auctionModule Address of the auction module, which sells user funds in the event of an insolvency
    /// @param _maxPercentUserLoss The max percentage of user funds that can be sold at auction, normalized to 1e18
    /// @param _maxRewardMultiplier The maximum reward multiplier, scaled by 1e18
    /// @param _smoothingValue The smoothing value, scaled by 1e18
    /// @param _ecosystemReserve The address of the EcosystemReserve contract, where reward tokens are stored
    constructor(
        address _auctionModule,
        uint256 _maxPercentUserLoss,
        uint256 _maxRewardMultiplier,
        uint256 _smoothingValue,
        address _ecosystemReserve
    ) RewardDistributor(_ecosystemReserve) {
        auctionModule = IAuctionModule(_auctionModule);
        maxPercentUserLoss = _maxPercentUserLoss;
        maxRewardMultiplier = _maxRewardMultiplier;
        smoothingValue = _smoothingValue;
        emit MaxPercentUserLossUpdated(_maxPercentUserLoss);
        emit MaxRewardMultiplierUpdated(_maxRewardMultiplier);
        emit SmoothingValueUpdated(_smoothingValue);
    }

    /* ****************** */
    /*      Markets       */
    /* ****************** */

    /// @inheritdoc RewardDistributor
    function getNumMarkets() public view virtual override returns (uint256) {
        return stakingTokens.length;
    }

    /// @inheritdoc RewardDistributor
    function getMaxMarketIdx() public view override returns (uint256) {
        return stakingTokens.length - 1;
    }

    /// @inheritdoc RewardDistributor
    function getMarketAddress(
        uint256 index
    ) public view virtual override returns (address) {
        if (index > getMaxMarketIdx())
            revert RewardDistributor_InvalidMarketIndex(
                index,
                getMaxMarketIdx()
            );
        return address(stakingTokens[index]);
    }

    /// @inheritdoc RewardDistributor
    function getMarketIdx(
        uint256 i
    ) public view virtual override returns (uint256) {
        if (i > getMaxMarketIdx())
            revert RewardDistributor_InvalidMarketIndex(i, getMaxMarketIdx());
        return i;
    }

    /// @inheritdoc ISafetyModule
    function getStakingTokenIdx(address token) public view returns (uint256) {
        for (uint256 i; i < stakingTokens.length; ++i) {
            if (address(stakingTokens[i]) == token) return i;
        }
        revert SafetyModule_InvalidStakingToken(token);
    }

    /// @notice Returns the user's staking token balance
    /// @param staker Address of the user
    /// @param token Address of the staking token
    /// @return Current balance of the user in the staking token
    function getCurrentPosition(
        address staker,
        address token
    ) public view virtual override returns (uint256) {
        return IStakedToken(token).balanceOf(staker);
    }

    /// @inheritdoc ISafetyModule
    function getAuctionableBalance(
        address staker,
        address token
    ) public view virtual returns (uint256) {
        getStakingTokenIdx(token); // Called to make sure the staking token is registered
        return getCurrentPosition(staker, token).mul(maxPercentUserLoss);
    }

    /// @inheritdoc ISafetyModule
    function getAuctionableTotal(
        address token
    ) public view virtual returns (uint256) {
        getStakingTokenIdx(token); // Called to make sure the staking token is registered
        return IStakedToken(token).totalSupply().mul(maxPercentUserLoss);
    }

    /* ****************** */
    /*   Reward Accrual   */
    /* ****************** */

    /// @notice Accrues rewards and updates the stored stake position of a user and the total tokens staked
    /// @dev Executes whenever a user's stake is updated for any reason
    /// @param market Address of the staking token in `stakingTokens`
    /// @param user Address of the staker
    function updateStakingPosition(
        address market,
        address user
    )
        external
        virtual
        override(IStakingContract, RewardDistributor)
        nonReentrant
        onlyStakingToken
    {
        getStakingTokenIdx(market); // Called to make sure the staking token is registered
        updateMarketRewards(market);
        uint256 prevPosition = lpPositionsPerUser[user][market];
        uint256 newPosition = getCurrentPosition(user, market);
        totalLiquidityPerMarket[market] =
            totalLiquidityPerMarket[market] +
            newPosition -
            prevPosition;
        uint256 rewardMultiplier = computeRewardMultiplier(user, market);
        for (uint256 i; i < rewardTokensPerMarket[market].length; ++i) {
            address token = rewardTokensPerMarket[market][i];
            /// newRewards = user.lpBalance x (global.cumRewardPerLpToken - user.cumRewardPerLpToken) x user.rewardMultiplier
            uint256 newRewards = prevPosition
                .mul(
                    cumulativeRewardPerLpToken[token][market] -
                        cumulativeRewardPerLpTokenPerUser[user][token][market]
                )
                .mul(rewardMultiplier);
            cumulativeRewardPerLpTokenPerUser[user][token][
                market
            ] = cumulativeRewardPerLpToken[token][market];
            if (newRewards == 0) continue;
            rewardsAccruedByUser[user][token] += newRewards;
            totalUnclaimedRewards[token] += newRewards;
            emit RewardAccruedToUser(user, token, market, newRewards);
            uint256 rewardTokenBalance = _rewardTokenBalance(token);
            if (totalUnclaimedRewards[token] > rewardTokenBalance) {
                emit RewardTokenShortfall(
                    token,
                    totalUnclaimedRewards[token] - rewardTokenBalance
                );
            }
        }
        if (prevPosition == 0 || newPosition < prevPosition) {
            // Removed stake or staked for the first time - need to reset multiplier
            if (newPosition > 0) {
                // Partial removal or first stake - reset multiplier to 1
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
            uint256 timeDelta = block.timestamp -
                multiplierStartTimeByUser[user][market];
            uint256 increaseRatio = (newPosition - prevPosition).div(
                newPosition
            );
            multiplierStartTimeByUser[user][market] += timeDelta.mul(
                increaseRatio
            );
        }
        lpPositionsPerUser[user][market] = newPosition;
    }

    /* ****************** */
    /*    External User   */
    /* ****************** */

    /// @notice Accrues rewards to a user for a given staking token
    /// @dev Assumes stake position hasn't changed since last accrual, since updating rewards due to changes in
    /// stake position is handled by `updateStakingPosition`
    /// @param market Address of the token in `stakingTokens`
    /// @param user Address of the user
    function accrueRewards(
        address market,
        address user
    ) public virtual override nonReentrant {
        uint256 userPosition = lpPositionsPerUser[user][market];
        uint256 currentPosition = getCurrentPosition(user, market);
        if (userPosition != currentPosition)
            // only occurs if the user has a pre-existing balance and has not registered for rewards,
            // since updating stake position calls updateStakingPosition which updates lpPositionsPerUser
            revert RewardDistributor_UserPositionMismatch(
                user,
                market,
                userPosition,
                currentPosition
            );
        if (totalLiquidityPerMarket[market] == 0) return;
        updateMarketRewards(market);
        uint256 rewardMultiplier = computeRewardMultiplier(user, market);
        for (uint i; i < rewardTokensPerMarket[market].length; ++i) {
            address token = rewardTokensPerMarket[market][i];
            uint256 newRewards = userPosition
                .mul(
                    cumulativeRewardPerLpToken[token][market] -
                        cumulativeRewardPerLpTokenPerUser[user][token][market]
                )
                .mul(rewardMultiplier);
            cumulativeRewardPerLpTokenPerUser[user][token][
                market
            ] = cumulativeRewardPerLpToken[token][market];
            if (newRewards == 0) continue;
            rewardsAccruedByUser[user][token] += newRewards;
            totalUnclaimedRewards[token] += newRewards;
            emit RewardAccruedToUser(user, token, market, newRewards);
            uint256 rewardTokenBalance = _rewardTokenBalance(token);
            if (totalUnclaimedRewards[token] > rewardTokenBalance) {
                emit RewardTokenShortfall(
                    token,
                    totalUnclaimedRewards[token] - rewardTokenBalance
                );
            }
        }
    }

    /// @notice Returns the amount of new rewards that would be accrued to a user by calling `accrueRewards`
    /// for a given market and reward token
    /// @param market Address of the staking token in `stakingTokens`
    /// @param user Address of the user
    /// @param token Address of the reward token
    /// @return Amount of new rewards that would be accrued to the user
    function viewNewRewardAccrual(
        address market,
        address user,
        address token
    ) public view override returns (uint256) {
        uint256 lpPosition = lpPositionsPerUser[user][market];
        if (lpPosition != getCurrentPosition(user, market))
            // only occurs if the user has a pre-existing liquidity position and has not registered for rewards,
            // since updating LP position calls updateStakingPosition which updates lpPositionsPerUser
            revert RewardDistributor_UserPositionMismatch(
                user,
                market,
                lpPosition,
                getCurrentPosition(user, market)
            );
        uint256 deltaTime = block.timestamp - timeOfLastCumRewardUpdate[market];
        if (totalLiquidityPerMarket[market] == 0) return 0;
        RewardInfo memory rewardInfo = rewardInfoByToken[token];
        uint256 totalTimeElapsed = block.timestamp -
            rewardInfo.initialTimestamp;
        // Calculate the new cumRewardPerLpToken by adding (inflationRatePerSecond x guageWeight x deltaTime) to the previous cumRewardPerLpToken
        uint256 inflationRate = rewardInfo.initialInflationRate.div(
            rewardInfo.reductionFactor.pow(totalTimeElapsed.div(365 days))
        );
        uint256 newMarketRewards = (((inflationRate *
            rewardInfo.marketWeights[getMarketWeightIdx(token, market)]) /
            10000) * deltaTime) / 365 days;
        uint256 newCumRewardPerLpToken = cumulativeRewardPerLpToken[token][
            market
        ] + (newMarketRewards * 1e18) / totalLiquidityPerMarket[market];
        return
            lpPosition
                .mul(
                    (newCumRewardPerLpToken -
                        cumulativeRewardPerLpTokenPerUser[user][token][market])
                )
                .mul(computeRewardMultiplier(user, market));
    }

    /* ******************* */
    /*  Reward Multiplier  */
    /* ******************* */

    /// @inheritdoc ISafetyModule
    function computeRewardMultiplier(
        address _user,
        address _stakingToken
    ) public view returns (uint256) {
        uint256 startTime = multiplierStartTimeByUser[_user][_stakingToken];
        // If the user has never staked, return zero
        if (startTime == 0) return 0;
        uint256 timeDelta = block.timestamp - startTime;
        uint256 deltaDays = timeDelta.wadDiv(1 days);
        /**
         * Multiplier formula:
         *   maxRewardMultiplier - 1 / ((1 / smoothingValue) * deltaDays + (1 / (maxRewardMultiplier - 1)))
         * = maxRewardMultiplier - smoothingValue / (deltaDays + (smoothingValue / (maxRewardMultiplier - 1)))
         * = maxRewardMultiplier - (smoothingValue * (maxRewardMultiplier - 1)) / ((deltaDays * (maxRewardMultiplier - 1)) + smoothingValue)
         */
        return
            maxRewardMultiplier -
            (smoothingValue * (maxRewardMultiplier - 1e18)) /
            ((deltaDays * (maxRewardMultiplier - 1e18)) /
                1e18 +
                smoothingValue);
    }

    /* ****************** */
    /*   Auction Module   */
    /* ****************** */

    /// @inheritdoc ISafetyModule
    /// @dev Only callable by the auction module
    function auctionEnded(
        uint256 _auctionId,
        uint256 _remainingBalance
    ) external onlyAuctionModule {
        IStakedToken stakingToken = stakingTokenByAuctionId[_auctionId];
        if (address(stakingToken) == address(0))
            revert SafetyModule_InvalidAuctionId(_auctionId);
        stakingToken.returnFunds(address(auctionModule), _remainingBalance);
        stakingToken.settleSlashing();
        emit AuctionEnded(
            _auctionId,
            address(stakingToken),
            address(stakingToken.getUnderlyingToken()),
            _remainingBalance
        );
    }

    /* ****************** */
    /*     Governance     */
    /* ****************** */

    /// @inheritdoc ISafetyModule
    /// @dev Only callable by governance
    function slashAndStartAuction(
        address _stakedToken,
        uint8 _numLots,
        uint128 _lotPrice,
        uint128 _initialLotSize,
        uint96 _lotIncreaseIncrement,
        uint16 _lotIncreasePeriod,
        uint32 _timeLimit
    ) external onlyRole(GOVERNANCE) returns (uint256) {
        IStakedToken stakedToken = stakingTokens[
            getStakingTokenIdx(_stakedToken)
        ];

        // Slash the staked tokens and transfer the underlying tokens to the auction module
        // Note: the StakedToken contract will revert if the slash amount exceeds the max slash amount,
        //       but that should never happen because we slash exactly the max auctionable amount
        uint256 slashAmount = getAuctionableTotal(_stakedToken);
        uint256 underlyingAmount = stakedToken.slash(
            address(auctionModule),
            slashAmount
        );

        // Make sure the amount of underlying tokens transferred to the auction module is enough to
        // cover the initial lot size and number of lots to auction
        uint256 initialAuctionAmount = uint256(_initialLotSize) *
            uint256(_numLots);
        if (underlyingAmount < initialAuctionAmount)
            revert SafetyModule_InsufficientSlashedTokensForAuction(
                stakedToken.getUnderlyingToken(),
                initialAuctionAmount,
                underlyingAmount
            );

        // Start the auction and return the auction ID
        // Note: the AuctionModule contract will revert if zero is passed for any of the parameters
        uint256 auctionId = auctionModule.startAuction(
            stakedToken.getUnderlyingToken(),
            _numLots,
            _lotPrice,
            _initialLotSize,
            _lotIncreaseIncrement,
            _lotIncreasePeriod,
            _timeLimit
        );
        stakingTokenByAuctionId[auctionId] = stakedToken;
        emit TokensSlashedForAuction(
            _stakedToken,
            slashAmount,
            underlyingAmount,
            auctionId
        );
        return auctionId;
    }

    /// @inheritdoc ISafetyModule
    /// @dev Only callable by governance
    function returnFunds(
        address _stakingToken,
        address _from,
        uint256 _amount
    ) external onlyRole(GOVERNANCE) {
        if (_stakingToken == address(0))
            revert SafetyModule_InvalidZeroAddress(0);
        if (_from == address(0)) revert SafetyModule_InvalidZeroAddress(1);
        if (_amount == 0) revert SafetyModule_InvalidZeroAmount(2);
        IStakedToken stakingToken = stakingTokens[
            getStakingTokenIdx(_stakingToken)
        ];
        stakingToken.returnFunds(_from, _amount);
    }

    /// @inheritdoc ISafetyModule
    /// @dev Only callable by governance
    function setAuctionModule(
        IAuctionModule _auctionModule
    ) external onlyRole(GOVERNANCE) {
        auctionModule = _auctionModule;
    }

    /// @inheritdoc ISafetyModule
    /// @dev Only callable by governance, reverts if the new value is greater than 1e18, i.e., 100%
    function setMaxPercentUserLoss(
        uint256 _maxPercentUserLoss
    ) external onlyRole(GOVERNANCE) {
        if (_maxPercentUserLoss > 1e18)
            revert SafetyModule_InvalidMaxUserLossTooHigh(
                _maxPercentUserLoss,
                1e18
            );
        maxPercentUserLoss = _maxPercentUserLoss;
        emit MaxPercentUserLossUpdated(_maxPercentUserLoss);
    }

    /// @inheritdoc ISafetyModule
    /// @dev Only callable by governance, reverts if the new value is less than 1e18 (100%) or greater than 10e18 (1000%)
    function setMaxRewardMultiplier(
        uint256 _maxRewardMultiplier
    ) external onlyRole(GOVERNANCE) {
        if (_maxRewardMultiplier < 1e18)
            revert SafetyModule_InvalidMaxMultiplierTooLow(
                _maxRewardMultiplier,
                1e18
            );
        else if (_maxRewardMultiplier > 10e18)
            revert SafetyModule_InvalidMaxMultiplierTooHigh(
                _maxRewardMultiplier,
                10e18
            );
        maxRewardMultiplier = _maxRewardMultiplier;
        emit MaxRewardMultiplierUpdated(_maxRewardMultiplier);
    }

    /// @inheritdoc ISafetyModule
    /// @dev Only callable by governance, reverts if the new value is less than 10e18 or greater than 100e18
    function setSmoothingValue(
        uint256 _smoothingValue
    ) external onlyRole(GOVERNANCE) {
        if (_smoothingValue < 10e18)
            revert SafetyModule_InvalidSmoothingValueTooLow(
                _smoothingValue,
                10e18
            );
        else if (_smoothingValue > 100e18)
            revert SafetyModule_InvalidSmoothingValueTooHigh(
                _smoothingValue,
                100e18
            );
        smoothingValue = _smoothingValue;
        emit SmoothingValueUpdated(_smoothingValue);
    }

    /// @inheritdoc ISafetyModule
    /// @dev Only callable by governance, reverts if the staking token is already registered
    function addStakingToken(
        IStakedToken _stakingToken
    ) external onlyRole(GOVERNANCE) {
        for (uint i; i < stakingTokens.length; ++i) {
            if (stakingTokens[i] == _stakingToken)
                revert SafetyModule_StakingTokenAlreadyRegistered(
                    address(_stakingToken)
                );
        }
        stakingTokens.push(_stakingToken);
        timeOfLastCumRewardUpdate[address(_stakingToken)] = block.timestamp;
        emit StakingTokenAdded(address(_stakingToken));
    }
}
