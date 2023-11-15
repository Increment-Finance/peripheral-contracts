# IBasePoolFactory
[Git Source](https://github.com/Increment-Finance/peripheral-contracts/blob/45559668fd9e29384d52be9948eb4e35f7e92b00/contracts/interfaces/balancer/IWeightedPoolFactory.sol)

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

