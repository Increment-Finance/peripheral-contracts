# VersionedInitializable

[Git Source](https://github.com/Increment-Finance/peripheral-contracts/blob/50135f16a3332e293d1be01434556e7e68cc2f26/contracts/AdminControlledEcosystemReserve.sol)

**Author:**
Aave, inspired by the OpenZeppelin Initializable contract

_Helper contract to support initializer functions. To use it, replace
the constructor with a function that has the `initializer` modifier.
WARNING: Unlike constructors, initializer functions must be manually
invoked. This applies both to deploying an Initializable contract, as well
as extending an Initializable contract via inheritance.
WARNING: When used with inheritance, manual care must be taken to not invoke
a parent initializer twice, or ensure that all initializers are idempotent,
because this is not dealt with automatically as with constructors._

## State Variables

### lastInitializedRevision

_Indicates that the contract has been initialized._

```solidity
uint256 internal lastInitializedRevision = 0;
```

### **\_\_**gap

```solidity
uint256[50] private ______gap;
```

## Functions

### initializer

_Modifier to use in the initializer function of a contract._

```solidity
modifier initializer();
```

### getRevision

_returns the revision number of the contract.
Needs to be defined in the inherited class as a constant._

```solidity
function getRevision() internal pure virtual returns (uint256);
```
