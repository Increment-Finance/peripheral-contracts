# ISMRewardDistributor

[Git Source](https://github.com/Increment-Finance/peripheral-contracts/blob/50135f16a3332e293d1be01434556e7e68cc2f26/contracts/interfaces/ISMRewardDistributor.sol)

**Inherits:**
[IRewardDistributor](/contracts/interfaces/IRewardDistributor.sol/interface.IRewardDistributor.md), IRewardContract

**Author:**
webthethird

Interface for the Safety Module's Reward Distributor contract

## Functions

### safetyModule

Gets the address of the SafetyModule contract which stores the list of StakedTokens and can call `updatePosition`

```solidity
function safetyModule() external view returns (ISafetyModule);
```

**Returns**

| Name     | Type            | Description                          |
| -------- | --------------- | ------------------------------------ |
| `<none>` | `ISafetyModule` | Address of the SafetyModule contract |

### maxRewardMultiplier

Gets the maximum reward multiplier set by governance

```solidity
function maxRewardMultiplier() external view returns (uint256);
```

**Returns**

| Name     | Type      | Description                               |
| -------- | --------- | ----------------------------------------- |
| `<none>` | `uint256` | Maximum reward multiplier, scaled by 1e18 |

### smoothingValue

Gets the smoothing value set by governance

```solidity
function smoothingValue() external view returns (uint256);
```

**Returns**

| Name     | Type      | Description                     |
| -------- | --------- | ------------------------------- |
| `<none>` | `uint256` | Smoothing value, scaled by 1e18 |

### multiplierStartTimeByUser

Gets the starting timestamp used to calculate the user's reward multiplier for a given staking token

```solidity
function multiplierStartTimeByUser(address user, address stakingToken) external view returns (uint256);
```

**Parameters**

| Name           | Type      | Description                  |
| -------------- | --------- | ---------------------------- |
| `user`         | `address` | Address of the user          |
| `stakingToken` | `address` | Address of the staking token |

### computeRewardMultiplier

Computes the user's reward multiplier for the given staking token

_Based on the max multiplier, smoothing factor and time since last withdrawal (or first deposit)_

```solidity
function computeRewardMultiplier(address _user, address _stakingToken) external view returns (uint256);
```

**Parameters**

| Name            | Type      | Description                              |
| --------------- | --------- | ---------------------------------------- |
| `_user`         | `address` | Address of the staker                    |
| `_stakingToken` | `address` | Address of staking token earning rewards |

**Returns**

| Name     | Type      | Description                              |
| -------- | --------- | ---------------------------------------- |
| `<none>` | `uint256` | User's reward multiplier, scaled by 1e18 |

### setSafetyModule

Replaces the SafetyModule contract

```solidity
function setSafetyModule(ISafetyModule _newSafetyModule) external;
```

**Parameters**

| Name               | Type            | Description                              |
| ------------------ | --------------- | ---------------------------------------- |
| `_newSafetyModule` | `ISafetyModule` | Address of the new SafetyModule contract |

### setMaxRewardMultiplier

Sets the maximum reward multiplier

```solidity
function setMaxRewardMultiplier(uint256 _maxRewardMultiplier) external;
```

**Parameters**

| Name                   | Type      | Description                                   |
| ---------------------- | --------- | --------------------------------------------- |
| `_maxRewardMultiplier` | `uint256` | New maximum reward multiplier, scaled by 1e18 |

### setSmoothingValue

Sets the smoothing value used in calculating the reward multiplier

```solidity
function setSmoothingValue(uint256 _smoothingValue) external;
```

**Parameters**

| Name              | Type      | Description                         |
| ----------------- | --------- | ----------------------------------- |
| `_smoothingValue` | `uint256` | New smoothing value, scaled by 1e18 |

## Events

### MaxRewardMultiplierUpdated

Emitted when the max reward multiplier is updated by governance

```solidity
event MaxRewardMultiplierUpdated(uint256 oldMaxRewardMultiplier, uint256 newMaxRewardMultiplier);
```

**Parameters**

| Name                     | Type      | Description               |
| ------------------------ | --------- | ------------------------- |
| `oldMaxRewardMultiplier` | `uint256` | Old max reward multiplier |
| `newMaxRewardMultiplier` | `uint256` | New max reward multiplier |

### SmoothingValueUpdated

Emitted when the smoothing value is updated by governance

```solidity
event SmoothingValueUpdated(uint256 oldSmoothingValue, uint256 newSmoothingValue);
```

**Parameters**

| Name                | Type      | Description         |
| ------------------- | --------- | ------------------- |
| `oldSmoothingValue` | `uint256` | Old smoothing value |
| `newSmoothingValue` | `uint256` | New smoothing value |

### SafetyModuleUpdated

Emitted when the SafetyModule contract is updated by governance

```solidity
event SafetyModuleUpdated(address oldSafetyModule, address newSafetyModule);
```

**Parameters**

| Name              | Type      | Description                              |
| ----------------- | --------- | ---------------------------------------- |
| `oldSafetyModule` | `address` | Address of the old SafetyModule contract |
| `newSafetyModule` | `address` | Address of the new SafetyModule contract |

## Errors

### SMRD_CallerIsNotSafetyModule

Error returned when the caller of `updatePosition` is not the SafetyModule

```solidity
error SMRD_CallerIsNotSafetyModule(address caller);
```

**Parameters**

| Name     | Type      | Description           |
| -------- | --------- | --------------------- |
| `caller` | `address` | Address of the caller |

### SMRD_InvalidMaxMultiplierTooLow

Error returned when trying to set the max reward multiplier to a value that is too low

```solidity
error SMRD_InvalidMaxMultiplierTooLow(uint256 value, uint256 min);
```

**Parameters**

| Name    | Type      | Description           |
| ------- | --------- | --------------------- |
| `value` | `uint256` | Value that was passed |
| `min`   | `uint256` | Minimum allowed value |

### SMRD_InvalidMaxMultiplierTooHigh

Error returned when trying to set the max reward multiplier to a value that is too high

```solidity
error SMRD_InvalidMaxMultiplierTooHigh(uint256 value, uint256 max);
```

**Parameters**

| Name    | Type      | Description           |
| ------- | --------- | --------------------- |
| `value` | `uint256` | Value that was passed |
| `max`   | `uint256` | Maximum allowed value |

### SMRD_InvalidSmoothingValueTooLow

Error returned when trying to set the smoothing value to a value that is too low

```solidity
error SMRD_InvalidSmoothingValueTooLow(uint256 value, uint256 min);
```

**Parameters**

| Name    | Type      | Description           |
| ------- | --------- | --------------------- |
| `value` | `uint256` | Value that was passed |
| `min`   | `uint256` | Minimum allowed value |

### SMRD_InvalidSmoothingValueTooHigh

Error returned when trying to set the smoothing value to a value that is too high

```solidity
error SMRD_InvalidSmoothingValueTooHigh(uint256 value, uint256 max);
```

**Parameters**

| Name    | Type      | Description           |
| ------- | --------- | --------------------- |
| `value` | `uint256` | Value that was passed |
| `max`   | `uint256` | Maximum allowed value |
