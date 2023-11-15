# IAuthorizer
[Git Source](https://github.com/Increment-Finance/peripheral-contracts/blob/45559668fd9e29384d52be9948eb4e35f7e92b00/contracts/interfaces/balancer/IVault.sol)


## Functions
### canPerform

*Returns true if `account` can perform the action described by `actionId` in the contract `where`.*


```solidity
function canPerform(bytes32 actionId, address account, address where) external view returns (bool);
```

