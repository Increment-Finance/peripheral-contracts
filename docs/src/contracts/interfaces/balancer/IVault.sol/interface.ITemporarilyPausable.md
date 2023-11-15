# ITemporarilyPausable
[Git Source](https://github.com/Increment-Finance/peripheral-contracts/blob/45559668fd9e29384d52be9948eb4e35f7e92b00/contracts/interfaces/balancer/IVault.sol)


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

