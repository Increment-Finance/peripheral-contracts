# ISafetyModule
[Git Source](https://github.com/Increment-Finance/peripheral-contracts/blob/b10b7c737f1995b97150c4bde2bb1f9387e53eef/src/interfaces/ISafetyModule.sol)

**Inherits:**
IStakingContract

**Author:**
webthethird

Interface for the SafetyModule contract


## Functions
### vault

Gets the address of the Vault contract


```solidity
function vault() external view returns (address);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`address`|Address of the Vault contract|


### auctionModule

Gets the address of the Auction contract


```solidity
function auctionModule() external view returns (address);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`address`|Address of the Auction contract|


### stakingTokens

Gets the address of the StakedToken contract at the specified index in the `stakingTokens` array


```solidity
function stakingTokens(uint256 i) external view returns (IStakedToken);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`i`|`uint256`|Index of the staking token|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`IStakedToken`|Address of the StakedToken contract|


### maxRewardMultiplier

Gets the maximum reward multiplier set by governance


```solidity
function maxRewardMultiplier() external view returns (uint256);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|Maximum reward multiplier|


### smoothingValue

Gets the smoothing value set by governance


```solidity
function smoothingValue() external view returns (uint256);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|Smoothing value|


### getStakingTokenIdx

Returns the index of the staking token in the `stakingTokens` array

*Reverts with `SafetyModule_InvalidStakingToken` if the staking token is not registered*


```solidity
function getStakingTokenIdx(address token) external view returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`token`|`address`|Address of the staking token|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|Index of the staking token in the `stakingTokens` array|


### getAuctionableBalance

Returns the amount of the user's staking tokens that can be sold at auction in the event of
an insolvency in the vault that cannot be covered by the insurance fund


```solidity
function getAuctionableBalance(address staker, address token) external view returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`staker`|`address`|Address of the user|
|`token`|`address`|Address of the staking token|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|Balance of the user multiplied by the maxPercentUserLoss|


### computeRewardMultiplier

Computes the user's reward multiplier for the given staking token

*Based on the max multiplier, smoothing factor and time since last withdrawal (or first deposit)*


```solidity
function computeRewardMultiplier(address _user, address _stakingToken) external view returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_user`|`address`|Address of the staker|
|`_stakingToken`|`address`|Address of staking token earning rewards|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|User's reward multiplier, scaled by 1e18|


### setMaxPercentUserLoss

Sets the maximum percentage of user funds that can be sold at auction, normalized to 1e18


```solidity
function setMaxPercentUserLoss(uint256 _maxPercentUserLoss) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_maxPercentUserLoss`|`uint256`|New maximum percentage of user funds that can be sold at auction, normalized to 1e18|


### setMaxRewardMultiplier

Sets the maximum reward multiplier, normalized to 1e18


```solidity
function setMaxRewardMultiplier(uint256 _maxRewardMultiplier) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_maxRewardMultiplier`|`uint256`|New maximum reward multiplier, normalized to 1e18|


### setSmoothingValue

Sets the smoothing value used in calculating the reward multiplier, normalized to 1e18


```solidity
function setSmoothingValue(uint256 _smoothingValue) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_smoothingValue`|`uint256`|New smoothing value, normalized to 1e18|


### addStakingToken

Adds a new staking token to the SafetyModule's stakingTokens array


```solidity
function addStakingToken(IStakedToken _stakingToken) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_stakingToken`|`IStakedToken`|Address of the new staking token|


## Events
### StakingTokenAdded
Emitted when a staking token is added


```solidity
event StakingTokenAdded(address indexed stakingToken);
```

### StakingTokenRemoved
Emitted when a staking token is removed


```solidity
event StakingTokenRemoved(address indexed stakingToken);
```

### MaxPercentUserLossUpdated
Emitted when the max percent user loss is updated by governance


```solidity
event MaxPercentUserLossUpdated(uint256 maxPercentUserLoss);
```

### MaxRewardMultiplierUpdated
Emitted when the max reward multiplier is updated by governance


```solidity
event MaxRewardMultiplierUpdated(uint256 maxRewardMultiplier);
```

### SmoothingValueUpdated
Emitted when the smoothing value is updated by governance


```solidity
event SmoothingValueUpdated(uint256 smoothingValue);
```

## Errors
### SafetyModule_CallerIsNotStakingToken
Error returned when the caller is not a registered staking token


```solidity
error SafetyModule_CallerIsNotStakingToken(address caller);
```

### SafetyModule_StakingTokenAlreadyRegistered
Error returned when trying to add a staking token that is already registered


```solidity
error SafetyModule_StakingTokenAlreadyRegistered(address stakingToken);
```

### SafetyModule_InvalidStakingToken
Error returned when passing an invalid staking token address to a function


```solidity
error SafetyModule_InvalidStakingToken(address invalidAddress);
```

### SafetyModule_InvalidMaxUserLossTooHigh
Error returned when trying to set the max percent user loss to a value that is too high


```solidity
error SafetyModule_InvalidMaxUserLossTooHigh(uint256 value, uint256 max);
```

### SafetyModule_InvalidMaxMultiplierTooLow
Error returned when trying to set the max reward multiplier to a value that is too low


```solidity
error SafetyModule_InvalidMaxMultiplierTooLow(uint256 value, uint256 min);
```

### SafetyModule_InvalidMaxMultiplierTooHigh
Error returned when trying to set the max reward multiplier to a value that is too high


```solidity
error SafetyModule_InvalidMaxMultiplierTooHigh(uint256 value, uint256 max);
```

### SafetyModule_InvalidSmoothingValueTooLow
Error returned when trying to set the smoothing value to a value that is too low


```solidity
error SafetyModule_InvalidSmoothingValueTooLow(uint256 value, uint256 min);
```

### SafetyModule_InvalidSmoothingValueTooHigh
Error returned when trying to set the smoothing value to a value that is too high


```solidity
error SafetyModule_InvalidSmoothingValueTooHigh(uint256 value, uint256 max);
```

