# ITemporarilyPausable
[Git Source](https://github.com/Increment-Finance/peripheral-contracts/blob/b10b7c737f1995b97150c4bde2bb1f9387e53eef/src/interfaces/balancer/IVault.sol)


## Functions
### getPausedState

*Returns the current paused state.*


```solidity
function getPausedState()
    external
    view
    returns (bool paused, uint256 pauseWindowEndTime, uint256 bufferPeriodEndTime);
```

## Events
### PausedStateChanged
*Emitted every time the pause state changes by `_setPaused`.*


```solidity
event PausedStateChanged(bool paused);
```

