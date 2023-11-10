# IBasePoolFactory
[Git Source](https://github.com/Increment-Finance/peripheral-contracts/blob/fc86e744c6664e8852ac82787aa2f73b160e6a5d/contracts/interfaces/balancer/IWeightedPoolFactory.sol)

**Inherits:**
[IAuthentication](/contracts/interfaces/balancer/IVault.sol/interface.IAuthentication.md), [IBaseSplitCodeFactory](/contracts/interfaces/balancer/IWeightedPoolFactory.sol/interface.IBaseSplitCodeFactory.md)


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

