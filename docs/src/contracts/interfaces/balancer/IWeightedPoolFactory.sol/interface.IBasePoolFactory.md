# IBasePoolFactory
[Git Source](https://github.com/Increment-Finance/peripheral-contracts/blob/b10b7c737f1995b97150c4bde2bb1f9387e53eef/src/interfaces/balancer/IWeightedPoolFactory.sol)

**Inherits:**
[IAuthentication](/src/interfaces/balancer/IVault.sol/interface.IAuthentication.md), [IBaseSplitCodeFactory](/src/interfaces/balancer/IWeightedPoolFactory.sol/interface.IBaseSplitCodeFactory.md)


## Functions
### isPoolFromFactory


```solidity
function isPoolFromFactory(address pool) external view returns (bool);
```

### isDisabled


```solidity
function isDisabled() external view returns (bool);
```

### disable


```solidity
function disable() external;
```

### getVault


```solidity
function getVault() external view returns (IVault);
```

### getAuthorizer


```solidity
function getAuthorizer() external view returns (IAuthorizer);
```

