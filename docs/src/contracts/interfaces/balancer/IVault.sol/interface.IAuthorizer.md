# IAuthorizer
[Git Source](https://github.com/Increment-Finance/peripheral-contracts/blob/fc86e744c6664e8852ac82787aa2f73b160e6a5d/contracts/interfaces/balancer/IVault.sol)


## Functions
### canPerform

*Returns true if `account` can perform the action described by `actionId` in the contract `where`.*


```solidity
function canPerform(bytes32 actionId, address account, address where) external view returns (bool);
```

