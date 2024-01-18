# IPerpRewardDistributor

[Git Source](https://github.com/Increment-Finance/peripheral-contracts/blob/50135f16a3332e293d1be01434556e7e68cc2f26/contracts/interfaces/IPerpRewardDistributor.sol)

## Functions

### clearingHouse

Gets the address of the ClearingHouse contract which stores the list of Perpetuals and can call `updatePosition`

```solidity
function clearingHouse() external view returns (IClearingHouse);
```

**Returns**

| Name     | Type             | Description                           |
| -------- | ---------------- | ------------------------------------- |
| `<none>` | `IClearingHouse` | Address of the ClearingHouse contract |

### earlyWithdrawalThreshold

Gets the number of seconds that a user must leave their liquidity in the market to avoid the early withdrawal penalty

```solidity
function earlyWithdrawalThreshold() external view returns (uint256);
```

**Returns**

| Name     | Type      | Description                                      |
| -------- | --------- | ------------------------------------------------ |
| `<none>` | `uint256` | Length of the early withdrawal period in seconds |

### setClearingHouse

Sets the address of the ClearingHouse contract which stores the list of Perpetuals and can call `updatePosition`

```solidity
function setClearingHouse(IClearingHouse _newClearingHouse) external;
```

**Parameters**

| Name                | Type             | Description                |
| ------------------- | ---------------- | -------------------------- |
| `_newClearingHouse` | `IClearingHouse` | New ClearingHouse contract |

### setEarlyWithdrawalThreshold

Sets the number of seconds that a user must leave their liquidity in the market to avoid the early withdrawal penalty

```solidity
function setEarlyWithdrawalThreshold(uint256 _newEarlyWithdrawalThreshold) external;
```

**Parameters**

| Name                           | Type      | Description                               |
| ------------------------------ | --------- | ----------------------------------------- |
| `_newEarlyWithdrawalThreshold` | `uint256` | New early withdrawal threshold in seconds |

## Events

### ClearingHouseUpdated

Emitted when the ClearingHouse contract is updated by governance

```solidity
event ClearingHouseUpdated(address oldClearingHouse, address newClearingHouse);
```

**Parameters**

| Name               | Type      | Description                               |
| ------------------ | --------- | ----------------------------------------- |
| `oldClearingHouse` | `address` | Address of the old ClearingHouse contract |
| `newClearingHouse` | `address` | Address of the new ClearingHouse contract |

### EarlyWithdrawalThresholdUpdated

Emitted when the early withdrawal threshold is updated by governance

```solidity
event EarlyWithdrawalThresholdUpdated(uint256 oldEarlyWithdrawalThreshold, uint256 newEarlyWithdrawalThreshold);
```

**Parameters**

| Name                          | Type      | Description                    |
| ----------------------------- | --------- | ------------------------------ |
| `oldEarlyWithdrawalThreshold` | `uint256` | Old early withdrawal threshold |
| `newEarlyWithdrawalThreshold` | `uint256` | New early withdrawal threshold |

## Errors

### PerpRewardDistributor_CallerIsNotClearingHouse

Error returned when the caller of `updatePosition` is not the ClearingHouse

```solidity
error PerpRewardDistributor_CallerIsNotClearingHouse(address caller);
```

**Parameters**

| Name     | Type      | Description           |
| -------- | --------- | --------------------- |
| `caller` | `address` | Address of the caller |
