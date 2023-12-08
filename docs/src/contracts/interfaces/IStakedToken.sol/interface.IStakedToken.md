# IStakedToken

[Git Source](https://github.com/Increment-Finance/peripheral-contracts/blob/ecb136b3c508e89c22b16cec8dcfd7e319381983/contracts/interfaces/IStakedToken.sol)

**Inherits:**
IERC20Metadata

**Author:**
webthethird

Interface for the StakedToken contract

## Functions

### getUnderlyingToken

Returns the underlying ERC20 token

```solidity
function getUnderlyingToken() external view returns (IERC20);
```

**Returns**

| Name     | Type     | Description            |
| -------- | -------- | ---------------------- |
| `<none>` | `IERC20` | Underlying ERC20 token |

### getCooldownSeconds

Returns the length of the cooldown period

```solidity
function getCooldownSeconds() external view returns (uint256);
```

**Returns**

| Name     | Type      | Description                              |
| -------- | --------- | ---------------------------------------- |
| `<none>` | `uint256` | Number of seconds in the cooldown period |

### getUnstakeWindowSeconds

Returns the length of the unstake window

```solidity
function getUnstakeWindowSeconds() external view returns (uint256);
```

**Returns**

| Name     | Type      | Description                             |
| -------- | --------- | --------------------------------------- |
| `<none>` | `uint256` | Number of seconds in the unstake window |

### isInPostSlashingState

Returns whether the contract is in a post-slashing state

_In a post-slashing state, staking and slashing are disabled, and users can redeem without cooldown_

```solidity
function isInPostSlashingState() external view returns (bool);
```

**Returns**

| Name     | Type   | Description                                                       |
| -------- | ------ | ----------------------------------------------------------------- |
| `<none>` | `bool` | True if the contract is in a post-slashing state, false otherwise |

### previewStake

Returns the amount of staked tokens one would receive for staking an amount of underlying tokens

```solidity
function previewStake(uint256 amountToStake) external view returns (uint256);
```

**Parameters**

| Name            | Type      | Description                          |
| --------------- | --------- | ------------------------------------ |
| `amountToStake` | `uint256` | Amount of underlying tokens to stake |

**Returns**

| Name     | Type      | Description                                                                 |
| -------- | --------- | --------------------------------------------------------------------------- |
| `<none>` | `uint256` | Amount of staked tokens that would be received at the current exchange rate |

### previewRedeem

Returns the amount of underlying tokens one would receive for redeeming an amount of staked tokens

```solidity
function previewRedeem(uint256 amountToRedeem) external view returns (uint256);
```

**Parameters**

| Name             | Type      | Description                       |
| ---------------- | --------- | --------------------------------- |
| `amountToRedeem` | `uint256` | Amount of staked tokens to redeem |

**Returns**

| Name     | Type      | Description                                                                     |
| -------- | --------- | ------------------------------------------------------------------------------- |
| `<none>` | `uint256` | Amount of underlying tokens that would be received at the current exchange rate |

### stake

Stakes tokens from the sender and starts earning rewards

```solidity
function stake(uint256 amount) external;
```

**Parameters**

| Name     | Type      | Description                          |
| -------- | --------- | ------------------------------------ |
| `amount` | `uint256` | Amount of underlying tokens to stake |

### stakeOnBehalfOf

Stakes tokens on behalf of the given address, and starts earning rewards

_Tokens are transferred from the transaction sender, not from the `onBehalfOf` address_

```solidity
function stakeOnBehalfOf(address onBehalfOf, uint256 amount) external;
```

**Parameters**

| Name         | Type      | Description                          |
| ------------ | --------- | ------------------------------------ |
| `onBehalfOf` | `address` | Address to stake on behalf of        |
| `amount`     | `uint256` | Amount of underlying tokens to stake |

### redeem

Redeems staked tokens, and stop earning rewards

```solidity
function redeem(uint256 amount) external;
```

**Parameters**

| Name     | Type      | Description                                             |
| -------- | --------- | ------------------------------------------------------- |
| `amount` | `uint256` | Amount of staked tokens to redeem for underlying tokens |

### redeemTo

Redeems staked tokens, and stop earning rewards

_Staked tokens are redeemed from the sender, and underlying tokens are sent to the `to` address_

```solidity
function redeemTo(address to, uint256 amount) external;
```

**Parameters**

| Name     | Type      | Description                                             |
| -------- | --------- | ------------------------------------------------------- |
| `to`     | `address` | Address to redeem to                                    |
| `amount` | `uint256` | Amount of staked tokens to redeem for underlying tokens |

### cooldown

Activates the cooldown period to unstake

_Can't be called if the user is not staking_

```solidity
function cooldown() external;
```

### slash

Sends underlying tokens to the given address, lowers the exchange rate accordingly, and
changes the contract's state to `POST_SLASHING`, which disables staking, cooldown period and
further slashing until the state is returned to `RUNNING`

```solidity
function slash(address destination, uint256 amount) external returns (uint256);
```

**Parameters**

| Name          | Type      | Description                                      |
| ------------- | --------- | ------------------------------------------------ |
| `destination` | `address` | Address to send the slashed underlying tokens to |
| `amount`      | `uint256` | Amount of staked tokens to slash                 |

**Returns**

| Name     | Type      | Description                         |
| -------- | --------- | ----------------------------------- |
| `<none>` | `uint256` | Amount of underlying tokens slashed |

### returnFunds

Transfers underlying tokens from the given address to this contract and increases the
exchange rate accordingly

_The `from` address must have approved this contract to transfer the tokens_

```solidity
function returnFunds(address from, uint256 amount) external;
```

**Parameters**

| Name     | Type      | Description                             |
| -------- | --------- | --------------------------------------- |
| `from`   | `address` | Address to transfer tokens from         |
| `amount` | `uint256` | Amount of underlying tokens to transfer |

### settleSlashing

Sets `isInPostSlashingState` to false, which re-enables staking, slashing and cooldown period

```solidity
function settleSlashing() external;
```

### setSafetyModule

Changes the SafetyModule contract used for reward management

```solidity
function setSafetyModule(address _newSafetyModule) external;
```

**Parameters**

| Name               | Type      | Description                              |
| ------------------ | --------- | ---------------------------------------- |
| `_newSafetyModule` | `address` | Address of the new SafetyModule contract |

### setMaxStakeAmount

Sets the max amount of staked tokens allowed per user

```solidity
function setMaxStakeAmount(uint256 _newMaxStakeAmount) external;
```

**Parameters**

| Name                 | Type      | Description                                      |
| -------------------- | --------- | ------------------------------------------------ |
| `_newMaxStakeAmount` | `uint256` | New max amount of staked tokens allowed per user |

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
| `amount`     | `uint256` | Amount of underlying tokens staked                       |

### Redeemed

Emitted when tokens are redeemed

```solidity
event Redeemed(address indexed from, address indexed to, uint256 amount);
```

**Parameters**

| Name     | Type      | Description                                |
| -------- | --------- | ------------------------------------------ |
| `from`   | `address` | Address of the user that redeemed tokens   |
| `to`     | `address` | Address where redeemed tokens were sent to |
| `amount` | `uint256` | Amount of staked tokens redeemed           |

### Cooldown

Emitted when the cooldown period is started

```solidity
event Cooldown(address indexed user);
```

**Parameters**

| Name   | Type      | Description                                          |
| ------ | --------- | ---------------------------------------------------- |
| `user` | `address` | Address of the user that started the cooldown period |

### Slashed

Emitted when tokens are slashed

```solidity
event Slashed(address indexed destination, uint256 stakeAmount, uint256 underlyingAmount);
```

**Parameters**

| Name               | Type      | Description                                          |
| ------------------ | --------- | ---------------------------------------------------- |
| `destination`      | `address` | Address where slashed underlying tokens were sent to |
| `stakeAmount`      | `uint256` | Amount of staked tokens slashed                      |
| `underlyingAmount` | `uint256` | Amount of underlying tokens sent to the destination  |

### SlashingSettled

Emitted when staking, slashing and cooldown are re-enabled after a slashing event is concluded

```solidity
event SlashingSettled();
```

### FundsReturned

Emitted when underlying tokens are returned to the contract

```solidity
event FundsReturned(address indexed from, uint256 amount);
```

**Parameters**

| Name     | Type      | Description                                           |
| -------- | --------- | ----------------------------------------------------- |
| `from`   | `address` | Address where underlying tokens were transferred from |
| `amount` | `uint256` | Amount of underlying tokens returned                  |

### ExchangeRateUpdated

Emitted when the exchange rate is updated

```solidity
event ExchangeRateUpdated(uint256 exchangeRate);
```

**Parameters**

| Name           | Type      | Description                                                                       |
| -------------- | --------- | --------------------------------------------------------------------------------- |
| `exchangeRate` | `uint256` | New exchange rate, denominated in underlying per staked token, normalized to 1e18 |

### SafetyModuleUpdated

Emitted when the SafetyModule contract is updated by governance

```solidity
event SafetyModuleUpdated(address oldSafetyModule, address newSafetyModule);
```

**Parameters**

| Name              | Type      | Description                              |
| ----------------- | --------- | ---------------------------------------- |
| `oldSafetyModule` | `address` | Address of the old SafetyModule contract |
| `newSafetyModule` | `address` | Address of the new SafetyModule contract |

### MaxStakeAmountUpdated

Emitted when the max amount of staked tokens allowed per user is updated by governance

```solidity
event MaxStakeAmountUpdated(uint256 oldMaxStakeAmount, uint256 newMaxStakeAmount);
```

**Parameters**

| Name                | Type      | Description          |
| ------------------- | --------- | -------------------- |
| `oldMaxStakeAmount` | `uint256` | Old max stake amount |
| `newMaxStakeAmount` | `uint256` | New max stake amount |

## Errors

### StakedToken_InvalidZeroAmount

Error returned when 0 amount is passed to a function that expects a non-zero amount

```solidity
error StakedToken_InvalidZeroAmount();
```

### StakedToken_InvalidZeroAddress

Error returned when the zero address is passed to a function that expects a non-zero address

```solidity
error StakedToken_InvalidZeroAddress();
```

### StakedToken_ZeroBalanceAtCooldown

Error returned when the caller has no balance when calling `cooldown`

```solidity
error StakedToken_ZeroBalanceAtCooldown();
```

### StakedToken_ZeroExchangeRate

Error returned when the caller tries to stake or redeem tokens when the exchange rate is 0

_This can only happen if 100% of the underlying tokens have been slashed by the SafetyModule,
which should never occur in practice because the SafetyModule can only slash `maxPercentUserLoss`_

```solidity
error StakedToken_ZeroExchangeRate();
```

### StakedToken_StakingDisabledInPostSlashingState

Error returned when the caller tries to stake while the contract is in a post-slashing state

```solidity
error StakedToken_StakingDisabledInPostSlashingState();
```

### StakedToken_SlashingDisabledInPostSlashingState

Error returned when the caller tries to slash while the contract is in a post-slashing state

```solidity
error StakedToken_SlashingDisabledInPostSlashingState();
```

### StakedToken_CooldownDisabledInPostSlashingState

Error returned when the caller tries to activate the cooldown period while the contract is
in a post-slashing state

_In a post-slashing state, users can redeem without waiting for the cooldown period_

```solidity
error StakedToken_CooldownDisabledInPostSlashingState();
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

### StakedToken_AboveMaxSlashAmount

Error returned when the caller tries to slash more than the max percent user loss

```solidity
error StakedToken_AboveMaxSlashAmount(uint256 amount, uint256 maxSlashAmount);
```

**Parameters**

| Name             | Type      | Description                           |
| ---------------- | --------- | ------------------------------------- |
| `amount`         | `uint256` | Amount passed to the `slash` function |
| `maxSlashAmount` | `uint256` | Maximum allowed amount to slash       |

### StakedToken_CallerIsNotSafetyModule

Error returned when a caller other than the SafetyModule tries to call a restricted function

```solidity
error StakedToken_CallerIsNotSafetyModule(address caller);
```

**Parameters**

| Name     | Type      | Description           |
| -------- | --------- | --------------------- |
| `caller` | `address` | Address of the caller |
