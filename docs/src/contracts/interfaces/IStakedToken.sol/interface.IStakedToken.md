# IStakedToken
[Git Source](https://github.com/Increment-Finance/peripheral-contracts/blob/fc86e744c6664e8852ac82787aa2f73b160e6a5d/contracts/interfaces/IStakedToken.sol)

**Inherits:**
IERC20Metadata

**Author:**
webthethird

Interface for the StakedToken contract


## Functions
### stake

Stakes tokens on behalf of the given address, and starts earning rewards

*Tokens are transferred from the transaction sender, not from the `onBehalfOf` address*


```solidity
function stake(address onBehalfOf, uint256 amount) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`onBehalfOf`|`address`|Address to stake on behalf of|
|`amount`|`uint256`|Amount of tokens to stake|


### redeem

Redeems staked tokens, and stop earning rewards


```solidity
function redeem(address to, uint256 amount) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`to`|`address`|Address to redeem to|
|`amount`|`uint256`|Amount to redeem|


### cooldown

Activates the cooldown period to unstake

*Can't be called if the user is not staking*


```solidity
function cooldown() external;
```

### setSafetyModule

Changes the SafetyModule contract used for reward management

*Only callable by Governance*


```solidity
function setSafetyModule(address _safetyModule) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_safetyModule`|`address`|Address of the new SafetyModule contract|


## Events
### Staked
Emitted when tokens are staked


```solidity
event Staked(address indexed from, address indexed onBehalfOf, uint256 amount);
```

### Redeem
Emitted when tokens are redeemed


```solidity
event Redeem(address indexed from, address indexed to, uint256 amount);
```

### Cooldown
Emitted when the cooldown period is started


```solidity
event Cooldown(address indexed user);
```

## Errors
### StakedToken_InvalidZeroAmount
Error returned when 0 amount is passed to stake or redeem functions


```solidity
error StakedToken_InvalidZeroAmount();
```

### StakedToken_ZeroBalanceAtCooldown
Error returned when the caller has no balance when calling `cooldown`


```solidity
error StakedToken_ZeroBalanceAtCooldown();
```

### StakedToken_InsufficientCooldown
Error returned when the caller tries to redeem before the cooldown period is over


```solidity
error StakedToken_InsufficientCooldown(uint256 cooldownEndTimestamp);
```

### StakedToken_UnstakeWindowFinished
Error returned when the caller tries to redeem after the unstake window is over


```solidity
error StakedToken_UnstakeWindowFinished(uint256 unstakeWindowEndTimestamp);
```

