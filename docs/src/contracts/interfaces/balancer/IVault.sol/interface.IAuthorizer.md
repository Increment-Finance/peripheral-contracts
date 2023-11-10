# IAuthorizer
[Git Source](https://github.com/Increment-Finance/peripheral-contracts/blob/b10b7c737f1995b97150c4bde2bb1f9387e53eef/src/interfaces/balancer/IVault.sol)


## Functions
### canPerform

*Returns true if `account` can perform the action described by `actionId` in the contract `where`.*


```solidity
function canPerform(bytes32 actionId, address account, address where) external view returns (bool);
```

