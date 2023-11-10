# IRecoveryMode
[Git Source](https://github.com/Increment-Finance/peripheral-contracts/blob/fc86e744c6664e8852ac82787aa2f73b160e6a5d/contracts/interfaces/balancer/IWeightedPool.sol)


## Functions
### enableRecoveryMode

Enables Recovery Mode in the Pool, disabling protocol fee collection and allowing for safe proportional
exits with low computational complexity and no dependencies.


```solidity
function enableRecoveryMode() external;
```

### disableRecoveryMode

Disables Recovery Mode in the Pool, restoring protocol fee collection and disallowing proportional exits.


```solidity
function disableRecoveryMode() external;
```

### inRecoveryMode

Returns true if the Pool is in Recovery Mode.


```solidity
function inRecoveryMode() external view returns (bool);
```

## Events
### RecoveryModeStateChanged
*Emitted when the Recovery Mode status changes.*


```solidity
event RecoveryModeStateChanged(bool enabled);
```

