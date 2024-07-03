# IPerpRewardDistributor

[Git Source](https://github.com/Increment-Finance/peripheral-contracts/blob/7b4166bd3bb6b2c678b84df162bcaf7af66b042d/contracts/interfaces/IPerpRewardDistributor.sol)

**Inherits:**
[IRewardDistributor](/contracts/interfaces/IRewardDistributor.sol/interface.IRewardDistributor.md)

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

### withdrawTimerStartByUserByMarket

Start time of the user's early withdrawal timer for a specific market,
i.e., when they last changed their position in the market

_The user can withdraw their liquidity without penalty after `withdrawTimerStartByUserByMarket(user, market) + earlyWithdrawalThreshold`_

```solidity
function withdrawTimerStartByUserByMarket(address _user, address _market) external view returns (uint256);
```

**Parameters**

| Name      | Type      | Description           |
| --------- | --------- | --------------------- |
| `_user`   | `address` | Address of the user   |
| `_market` | `address` | Address of the market |

**Returns**

| Name     | Type      | Description                                                   |
| -------- | --------- | ------------------------------------------------------------- |
| `<none>` | `uint256` | Timestamp when user last changed their position in the market |

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

### EarlyWithdrawalPenaltyApplied

Emitted when a user incurs an early withdrawal penalty

```solidity
event EarlyWithdrawalPenaltyApplied(
    address indexed user, address indexed market, address indexed token, uint256 penalty
);
```

**Parameters**

| Name      | Type      | Description                 |
| --------- | --------- | --------------------------- |
| `user`    | `address` | Address of the user         |
| `market`  | `address` | Address of the market       |
| `token`   | `address` | Address of the reward token |
| `penalty` | `uint256` | Amount of penalty incurred  |

### EarlyWithdrawalTimerReset

Emitted when a user's early withdrawal timer is reset

```solidity
event EarlyWithdrawalTimerReset(address indexed user, address indexed market, uint256 expireTime);
```

**Parameters**

| Name         | Type      | Description                                              |
| ------------ | --------- | -------------------------------------------------------- |
| `user`       | `address` | Address of the user                                      |
| `market`     | `address` | Address of the market                                    |
| `expireTime` | `uint256` | New expiration time of the user's early withdrawal timer |

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
