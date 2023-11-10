# ITemporarilyPausable
[Git Source](https://github.com/Increment-Finance/peripheral-contracts/blob/fc86e744c6664e8852ac82787aa2f73b160e6a5d/contracts/interfaces/balancer/IVault.sol)


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

