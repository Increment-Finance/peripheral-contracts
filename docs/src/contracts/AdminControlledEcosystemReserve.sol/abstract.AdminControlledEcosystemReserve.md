# AdminControlledEcosystemReserve

[Git Source](https://github.com/Increment-Finance/peripheral-contracts/blob/cf0cdb73c3067e3512acceef3935e48ab8394c32/contracts/AdminControlledEcosystemReserve.sol)

**Inherits:**
[VersionedInitializable](/contracts/AdminControlledEcosystemReserve.sol/abstract.VersionedInitializable.md), [IAdminControlledEcosystemReserve](/contracts/interfaces/IAdminControlledEcosystemReserve.sol/interface.IAdminControlledEcosystemReserve.md)

**Author:**
BGD Labs

Stores ERC20 tokens, and allows to dispose of them via approval or transfer dynamics
Adapted to be an implementation of a transparent proxy

_Done abstract to add an `initialize()` function on the child, with `initializer` modifier_

## State Variables

### \_fundsAdmin

```solidity
address internal _fundsAdmin;
```

### REVISION

```solidity
uint256 public constant REVISION = 1;
```

### ETH_MOCK_ADDRESS

Returns the mock ETH reference address

```solidity
address public constant ETH_MOCK_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
```

## Functions

### onlyFundsAdmin

```solidity
modifier onlyFundsAdmin();
```

### getRevision

```solidity
function getRevision() internal pure override returns (uint256);
```

### getFundsAdmin

Return the funds admin, only entity to be able to interact with this contract (controller of reserve)

```solidity
function getFundsAdmin() external view returns (address);
```

**Returns**

| Name     | Type      | Description                            |
| -------- | --------- | -------------------------------------- |
| `<none>` | `address` | address The address of the funds admin |

### approve

_Function for the funds admin to give ERC20 allowance to other parties_

```solidity
function approve(IERC20 token, address recipient, uint256 amount) external onlyFundsAdmin;
```

**Parameters**

| Name        | Type      | Description                                     |
| ----------- | --------- | ----------------------------------------------- |
| `token`     | `IERC20`  | The address of the token to give allowance from |
| `recipient` | `address` | Allowance's recipient                           |
| `amount`    | `uint256` | Allowance to approve                            |

### transfer

Function for the funds admin to transfer ERC20 tokens to other parties

```solidity
function transfer(IERC20 token, address recipient, uint256 amount) external onlyFundsAdmin;
```

**Parameters**

| Name        | Type      | Description                          |
| ----------- | --------- | ------------------------------------ |
| `token`     | `IERC20`  | The address of the token to transfer |
| `recipient` | `address` | Transfer's recipient                 |
| `amount`    | `uint256` | Amount to transfer                   |

### receive

_needed in order to receive ETH from the Aave v1 ecosystem reserve_

```solidity
receive() external payable;
```

### \_setFundsAdmin

```solidity
function _setFundsAdmin(address admin) internal;
```
