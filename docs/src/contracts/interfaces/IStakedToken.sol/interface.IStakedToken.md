# IStakedToken

[Git Source](https://github.com/Increment-Finance/peripheral-contracts/blob/45559668fd9e29384d52be9948eb4e35f7e92b00/contracts/interfaces/IStakedToken.sol)

**Inherits:**
IERC20Metadata

**Author:**
webthethird

Interface for the StakedToken contract

## Functions

### stake

Stakes tokens on behalf of the given address, and starts earning rewards

_Tokens are transferred from the transaction sender, not from the `onBehalfOf` address_

```solidity
function stake(address onBehalfOf, uint256 amount) external;
```

**Parameters**

| Name         | Type      | Description                   |
| ------------ | --------- | ----------------------------- |
| `onBehalfOf` | `address` | Address to stake on behalf of |
| `amount`     | `uint256` | Amount of tokens to stake     |

### redeem

Redeems staked tokens, and stop earning rewards

```solidity
function redeem(address to, uint256 amount) external;
```

**Parameters**

| Name     | Type      | Description          |
| -------- | --------- | -------------------- |
| `to`     | `address` | Address to redeem to |
| `amount` | `uint256` | Amount to redeem     |

### cooldown

Activates the cooldown period to unstake

_Can't be called if the user is not staking_

```solidity
function cooldown() external;
```

### setSafetyModule

Changes the SafetyModule contract used for reward management

_Only callable by Governance_

```solidity
function setSafetyModule(address _safetyModule) external;
```

**Parameters**

| Name            | Type      | Description                              |
| --------------- | --------- | ---------------------------------------- |
| `_safetyModule` | `address` | Address of the new SafetyModule contract |

## Events

### Staked

Emitted when tokens are staked

```solidity
event Staked(address indexed from, address indexed onBehalfOf, uint256 amount);
```

**Parameters**

| Name         | Type      | Description                                              |
| ------------ | --------- | -------------------------------------------------------- |
| `from`       | `address` | Address of the user that staked tokens                   |
| `onBehalfOf` | `address` | Address of the user that tokens were staked on behalf of |
| `amount`     | `uint256` | Amount of tokens staked                                  |

### Redeem

Emitted when tokens are redeemed

```solidity
event Redeem(address indexed from, address indexed to, uint256 amount);
```

**Parameters**

| Name     | Type      | Description                                |
| -------- | --------- | ------------------------------------------ |
| `from`   | `address` | Address of the user that redeemed tokens   |
| `to`     | `address` | Address where redeemed tokens were sent to |
| `amount` | `uint256` | Amount of tokens redeemed                  |

### Cooldown

Emitted when the cooldown period is started

```solidity
event Cooldown(address indexed user);
```

**Parameters**

| Name   | Type      | Description                                          |
| ------ | --------- | ---------------------------------------------------- |
| `user` | `address` | Address of the user that started the cooldown period |

## Errors

### StakedToken_InvalidZeroAmount

Error returned when 0 amount is passed to stake or redeem functions

```solidity
error StakedToken_InvalidZeroAmount();
```

### StakedToken_ZeroBalanceAtCooldown

Error returned when the caller has no balance when calling `cooldown`

```solidity
error StakedToken_ZeroBalanceAtCooldown();
```

### StakedToken_InsufficientCooldown

Error returned when the caller tries to redeem before the cooldown period is over

```solidity
error StakedToken_InsufficientCooldown(uint256 cooldownEndTimestamp);
```

**Parameters**

| Name                   | Type      | Description                             |
| ---------------------- | --------- | --------------------------------------- |
| `cooldownEndTimestamp` | `uint256` | Timestamp when the cooldown period ends |

### StakedToken_UnstakeWindowFinished

Error returned when the caller tries to redeem after the unstake window is over

```solidity
error StakedToken_UnstakeWindowFinished(uint256 unstakeWindowEndTimestamp);
```

**Parameters**

| Name                        | Type      | Description                             |
| --------------------------- | --------- | --------------------------------------- |
| `unstakeWindowEndTimestamp` | `uint256` | Timestamp when the unstake window ended |

### StakedToken_AboveMaxStakeAmount

Error returned when the caller tries to stake more than the max stake amount

```solidity
error StakedToken_AboveMaxStakeAmount(uint256 maxStakeAmount, uint256 maxAmountMinusBalance);
```

**Parameters**

| Name                    | Type      | Description                                                                 |
| ----------------------- | --------- | --------------------------------------------------------------------------- |
| `maxStakeAmount`        | `uint256` | Maximum allowed amount to stake                                             |
| `maxAmountMinusBalance` | `uint256` | Amount that the user can still stake without exceeding the max stake amount |
