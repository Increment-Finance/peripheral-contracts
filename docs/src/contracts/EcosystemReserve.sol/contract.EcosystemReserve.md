# EcosystemReserve

[Git Source](https://github.com/Increment-Finance/peripheral-contracts/blob/b10b7c737f1995b97150c4bde2bb1f9387e53eef/src/EcosystemReserve.sol)

**Inherits:**
[AdminControlledEcosystemReserve](https://github.com/aave/aave-v3-periphery/blob/master/contracts/treasury/AdminControlledEcosystemReserve.sol)

**Author:**
webthethird

Stores ERC20 tokens, and allows to dispose of them via approval or transfer dynamics

_Inherits from Aave's AdminControlledEcosystemReserve by BGD Labs, but with a transferable admin
and a constructor, as it is not intended to be used as a transparent proxy implementation_

## Functions

### constructor

EcosystemReserve constructor

```solidity
constructor(address fundsAdmin);
```

**Parameters**

| Name         | Type      | Description                                                              |
| ------------ | --------- | ------------------------------------------------------------------------ |
| `fundsAdmin` | `address` | Address of the admin who can approve or transfer tokens from the reserve |

### transferAdmin

Sets the admin of the EcosystemReserve

_Only callable by the current admin_

```solidity
function transferAdmin(address newAdmin) external onlyFundsAdmin;
```

**Parameters**

| Name       | Type      | Description              |
| ---------- | --------- | ------------------------ |
| `newAdmin` | `address` | Address of the new admin |

## Errors

### EcosystemReserve_InvalidAdmin

Error returned when trying to set the admin to the zero address

```solidity
error EcosystemReserve_InvalidAdmin();
```
