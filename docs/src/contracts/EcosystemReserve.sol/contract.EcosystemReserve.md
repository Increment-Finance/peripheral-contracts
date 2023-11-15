# EcosystemReserve
[Git Source](https://github.com/Increment-Finance/peripheral-contracts/blob/45559668fd9e29384d52be9948eb4e35f7e92b00/contracts/EcosystemReserve.sol)

**Inherits:**
AdminControlledEcosystemReserve

**Author:**
webthethird

Stores ERC20 tokens, and allows to dispose of them via approval or transfer dynamics

*Inherits from Aave's AdminControlledEcosystemReserve by BGD Labs, but with a transferable admin
and a constructor, as it is not intended to be used as a transparent proxy implementation*


## Functions
### constructor

EcosystemReserve constructor


```solidity
constructor(address fundsAdmin);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`fundsAdmin`|`address`|Address of the admin who can approve or transfer tokens from the reserve|


### transferAdmin

Sets the admin of the EcosystemReserve

*Only callable by the current admin*


```solidity
function transferAdmin(address newAdmin) external onlyFundsAdmin;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`newAdmin`|`address`|Address of the new admin|


## Errors
### EcosystemReserve_InvalidAdmin
Error returned when trying to set the admin to the zero address


```solidity
error EcosystemReserve_InvalidAdmin();
```

