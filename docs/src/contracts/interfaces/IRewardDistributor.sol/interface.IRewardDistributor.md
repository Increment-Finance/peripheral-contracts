# IRewardDistributor
[Git Source](https://github.com/Increment-Finance/peripheral-contracts/blob/fc86e744c6664e8852ac82787aa2f73b160e6a5d/contracts/interfaces/IRewardDistributor.sol)

**Author:**
webthethird

Interface for the RewardDistributor contract


## Functions
### ecosystemReserve

Gets the address of the reward token vault


```solidity
function ecosystemReserve() external view returns (address);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`address`|Address of the EcosystemReserve contract which serves as the reward token vault|


### rewardsAccruedByUser

Rewards accrued and not yet claimed by user


```solidity
function rewardsAccruedByUser(address user, address rewardToken) external view returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`user`|`address`|Address of the user|
|`rewardToken`|`address`|Address of the reward token|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|Rewards accrued and not yet claimed by user|


### totalUnclaimedRewards

Total rewards accrued and not claimed by all users


```solidity
function totalUnclaimedRewards(address rewardToken) external view returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`rewardToken`|`address`|Address of the reward token|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|Total rewards accrued and not claimed by all users|


### lastDepositTimeByUserByMarket

Last timestamp when user withdrew liquidity from a market


```solidity
function lastDepositTimeByUserByMarket(address user, address market) external view returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`user`|`address`|Address of the user|
|`market`|`address`|Address of the market|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|Timestamp when user last withdrew liquidity from the market|


### lpPositionsPerUser

Latest LP/staking positions per user and market


```solidity
function lpPositionsPerUser(address user, address market) external view returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`user`|`address`|Address of the user|
|`market`|`address`|Address of the market|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|Stored position of the user in the market|


### cumulativeRewardPerLpToken

Reward accumulator for market rewards per reward token, as a number of reward tokens per
LP/staked token


```solidity
function cumulativeRewardPerLpToken(address rewardToken, address market) external view returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`rewardToken`|`address`|Address of the reward token|
|`market`|`address`|Address of the market|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|Number of reward tokens per LP/staking token|


### cumulativeRewardPerLpTokenPerUser

Reward accumulator value per reward token when user rewards were last updated


```solidity
function cumulativeRewardPerLpTokenPerUser(address user, address rewardToken, address market)
    external
    view
    returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`user`|`address`|Address of the user|
|`rewardToken`|`address`|Address of the reward token|
|`market`|`address`|Address of the market|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|Number of reward tokens per Led token when user rewards were last updated|


### timeOfLastCumRewardUpdate

Gets the timestamp of the most recent update to the per-market reward accumulator


```solidity
function timeOfLastCumRewardUpdate(address market) external view returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`market`|`address`|Address of the market|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|Timestamp of the most recent update to the per-market reward accumulator|


### totalLiquidityPerMarket

Total LP/staked tokens registered for rewards per market


```solidity
function totalLiquidityPerMarket(address market) external view returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`market`|`address`|Address of the market|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|Stored total number of tokens per market|


### addRewardToken

Adds a new reward token


```solidity
function addRewardToken(
    address _rewardToken,
    uint256 _initialInflationRate,
    uint256 _initialReductionFactor,
    address[] calldata _markets,
    uint16[] calldata _marketWeights
) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_rewardToken`|`address`|Address of the reward token|
|`_initialInflationRate`|`uint256`|Initial inflation rate for the new token|
|`_initialReductionFactor`|`uint256`|Initial reduction factor for the new token|
|`_markets`|`address[]`|Addresses of the markets to reward with the new token|
|`_marketWeights`|`uint16[]`|Initial weights per market for the new token|


### removeRewardToken

Removes a reward token from all markets for which it is registered

*EcosystemReserve keeps the amount stored in `totalUnclaimedRewards[_rewardToken]` for users to
claim later, and the RewardDistributor sends the rest to governance*


```solidity
function removeRewardToken(address _rewardToken) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_rewardToken`|`address`|Address of the reward token to remove|


### setEcosystemReserve

Updates the address of the ecosystem reserve for storing reward tokens


```solidity
function setEcosystemReserve(address _ecosystemReserve) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_ecosystemReserve`|`address`|Address of the new ecosystem reserve|


### initMarketStartTime

Sets the start time for accruing rewards to a market which has not been initialized yet


```solidity
function initMarketStartTime(address _market) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_market`|`address`|Address of the market (i.e., perpetual market or staking token)|


### registerPositions

Fetches and stores the caller's LP/stake positions and updates the total liquidity in each market

*Can only be called once per user, only necessary if user was an LP/staker prior to this contract's deployment*


```solidity
function registerPositions() external;
```

### registerPositions

Fetches and stores the caller's LP/stake positions and updates the total liquidity in each of the
provided markets

*Can only be called once per user, only necessary if user was an LP prior to this contract's deployment*


```solidity
function registerPositions(address[] calldata _markets) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_markets`|`address[]`|Addresses of the markets to sync with|


### claimRewards

Accrues and then distributes rewards for all markets to the caller


```solidity
function claimRewards() external;
```

### claimRewardsFor

Accrues and then distributes rewards for all markets and reward tokens
and returns the amount of rewards that were not distributed to the given user


```solidity
function claimRewardsFor(address _user) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_user`|`address`|Address of the user to claim rewards for|


### claimRewardsFor

Accrues and then distributes rewards for a single market and all of its registered reward tokens
to the given user


```solidity
function claimRewardsFor(address _user, address _market) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_user`|`address`|Address of the user to claim rewards for|
|`_market`|`address`|Address of the market to claim rewards for|


### claimRewardsFor

Accrues and then distributes rewards for all markets that receive any of the provided reward tokens
to the given user


```solidity
function claimRewardsFor(address _user, address[] memory _rewardTokens) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_user`|`address`|Address of the user to claim rewards for|
|`_rewardTokens`|`address[]`|Addresses of the reward tokens to claim rewards for|


### accrueRewards

Accrues rewards to a user for all markets

*Assumes user's position hasn't changed since last accrual, since updating rewards due to changes
in position is handled by `updateStakingPosition`*


```solidity
function accrueRewards(address user) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`user`|`address`|Address of the user to accrue rewards for|


### accrueRewards

Accrues rewards to a user for a given market

*Assumes user's position hasn't changed since last accrual, since updating rewards due to changes in
position is handled by `updateStakingPosition`*


```solidity
function accrueRewards(address market, address user) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`market`|`address`|Address of the market to accrue rewards for|
|`user`|`address`|Address of the user|


### viewNewRewardAccrual

Returns the amount of rewards that would be accrued to a user for a given market

*Serves as a static version of `accrueRewards(address market, address user)`*


```solidity
function viewNewRewardAccrual(address market, address user) external view returns (uint256[] memory);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`market`|`address`|Address of the market to view new rewards for|
|`user`|`address`|Address of the user|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256[]`|Amount of new rewards that would be accrued to the user for each reward token the given market receives|


### viewNewRewardAccrual

Returns the amount of rewards that would be accrued to a user for a given market and reward token


```solidity
function viewNewRewardAccrual(address market, address user, address rewardToken) external view returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`market`|`address`|Address of the market to view new rewards for|
|`user`|`address`|Address of the user|
|`rewardToken`|`address`|Address of the reward token to view new rewards for|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|Amount of new rewards that would be accrued to the user|


## Events
### RewardAccruedToUser
Emitted when rewards are accrued to a user


```solidity
event RewardAccruedToUser(address indexed user, address rewardToken, address market, uint256 reward);
```

### RewardAccruedToMarket
Emitted when rewards are accrued to a market


```solidity
event RewardAccruedToMarket(address indexed market, address rewardToken, uint256 reward);
```

### RewardClaimed
Emitted when a user claims their accrued rewards


```solidity
event RewardClaimed(address indexed user, address rewardToken, uint256 reward);
```

### PositionUpdated
Emitted when a user's position is changed in the reward distributor


```solidity
event PositionUpdated(address indexed user, address market, uint256 prevPosition, uint256 newPosition);
```

### EcosystemReserveUpdated
Emitted when the address of the ecosystem reserve for storing reward tokens is updated


```solidity
event EcosystemReserveUpdated(address prevEcosystemReserve, address newEcosystemReserve);
```

## Errors
### RewardDistributor_InvalidMarketIndex
Error returned when an invalid index is passed into `getMarketAddress`


```solidity
error RewardDistributor_InvalidMarketIndex(uint256 index, uint256 maxIndex);
```

### RewardDistributor_UninitializedStartTime
Error returned when calling `viewNewRewardAccrual` with a market that has never accrued rewards

*Occurs when `timeOfLastCumRewardUpdate[market] == 0`. This value is updated whenever
`updateMarketRewards(market)` is called, which is quite often.*


```solidity
error RewardDistributor_UninitializedStartTime(address market);
```

### RewardDistributor_AlreadyInitializedStartTime
Error returned when calling `initMarketStartTime` with a market that already has a non-zero
`timeOfLastCumRewardUpdate`


```solidity
error RewardDistributor_AlreadyInitializedStartTime(address market);
```

### RewardDistributor_PositionAlreadyRegistered
Error returned if a user calls `registerPositions` when the reward distributor has already
stored their position for a market


```solidity
error RewardDistributor_PositionAlreadyRegistered(address user, address market, uint256 position);
```

### RewardDistributor_EarlyRewardAccrual
Error returned when a user tries to manually accrue rewards before the early withdrawal
penalty period is over


```solidity
error RewardDistributor_EarlyRewardAccrual(address user, address market, uint256 claimAllowedTimestamp);
```

### RewardDistributor_UserPositionMismatch
Error returned if a user's position stored in the RewardDistributor does not match their current position in a given market

*Only possible when the user had a pre-existing position in the market before the RewardDistributor
was deployed, and has not called `registerPositions` yet*


```solidity
error RewardDistributor_UserPositionMismatch(
    address user, address market, uint256 storedPosition, uint256 actualPosition
);
```

### RewardDistributor_InvalidEcosystemReserve
Error returned if governance tries to set the ecosystem reserve to the zero address


```solidity
error RewardDistributor_InvalidEcosystemReserve(address invalidAddress);
```

