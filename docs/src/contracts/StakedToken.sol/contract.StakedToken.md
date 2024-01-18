# StakedToken

[Git Source](https://github.com/Increment-Finance/peripheral-contracts/blob/50135f16a3332e293d1be01434556e7e68cc2f26/contracts/StakedToken.sol)

**Inherits:**
[IStakedToken](/contracts/interfaces/IStakedToken.sol/interface.IStakedToken.md), ERC20Permit, IncreAccessControl, Pausable, ReentrancyGuard

**Author:**
webthethird

Based on Aave's StakedToken, but with reward management outsourced to the SafetyModule

## State Variables

### UNDERLYING_TOKEN

Address of the underlying token to stake

```solidity
IERC20 public immutable UNDERLYING_TOKEN;
```

### COOLDOWN_SECONDS

Seconds that user must wait between calling cooldown and redeem

```solidity
uint256 public immutable COOLDOWN_SECONDS;
```

### UNSTAKE_WINDOW

Seconds available to redeem once the cooldown period is fullfilled

```solidity
uint256 public immutable UNSTAKE_WINDOW;
```

### safetyModule

Address of the SafetyModule contract

```solidity
ISafetyModule public safetyModule;
```

### maxStakeAmount

Max amount of staked tokens allowed per user

```solidity
uint256 public maxStakeAmount;
```

### exchangeRate

Exchange rate between the underlying token and the staked token, normalized to 1e18

_Rate is the amount of underlying tokens held in this contract per staked token issued, so
it should be 1e18 in normal conditions, when all staked tokens are backed 1:1 by underlying tokens,
but it can be lower if users' stakes have been slashed for an auction by the SafetyModule_

```solidity
uint256 public exchangeRate;
```

### isInPostSlashingState

Whether the StakedToken is in a post-slashing state

_Post-slashing state disables staking and further slashing, and allows users to redeem their
staked tokens without waiting for the cooldown period_

```solidity
bool public isInPostSlashingState;
```

### stakersCooldowns

Timestamp of the start of the current cooldown period for each user

```solidity
mapping(address => uint256) public stakersCooldowns;
```

## Functions

### onlySafetyModule

Modifier for functions that can only be called by the SafetyModule contract

```solidity
modifier onlySafetyModule();
```

### constructor

StakedToken constructor

```solidity
constructor(
    IERC20 _underlyingToken,
    ISafetyModule _safetyModule,
    uint256 _cooldownSeconds,
    uint256 _unstakeWindow,
    uint256 _maxStakeAmount,
    string memory _name,
    string memory _symbol
) payable ERC20(_name, _symbol) ERC20Permit(_name);
```

**Parameters**

| Name               | Type            | Description                                                                        |
| ------------------ | --------------- | ---------------------------------------------------------------------------------- |
| `_underlyingToken` | `IERC20`        | The underlying token to stake                                                      |
| `_safetyModule`    | `ISafetyModule` | The SafetyModule contract to use for reward management                             |
| `_cooldownSeconds` | `uint256`       | The number of seconds that users must wait between calling `cooldown` and `redeem` |
| `_unstakeWindow`   | `uint256`       | The number of seconds available to redeem once the cooldown period is fullfilled   |
| `_maxStakeAmount`  | `uint256`       | The maximum amount of staked tokens allowed per user                               |
| `_name`            | `string`        | The name of the token                                                              |
| `_symbol`          | `string`        | The symbol of the token                                                            |

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

### previewStake

Returns the amount of staked tokens one would receive for staking an amount of underlying tokens

```solidity
function previewStake(uint256 amountToStake) public view returns (uint256);
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
function previewRedeem(uint256 amountToRedeem) public view returns (uint256);
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
function stake(uint256 amount) external override;
```

**Parameters**

| Name     | Type      | Description                          |
| -------- | --------- | ------------------------------------ |
| `amount` | `uint256` | Amount of underlying tokens to stake |

### stakeOnBehalfOf

Stakes tokens on behalf of the given address, and starts earning rewards

_Tokens are transferred from the transaction sender, not from the `onBehalfOf` address_

```solidity
function stakeOnBehalfOf(address onBehalfOf, uint256 amount) external override;
```

**Parameters**

| Name         | Type      | Description                          |
| ------------ | --------- | ------------------------------------ |
| `onBehalfOf` | `address` | Address to stake on behalf of        |
| `amount`     | `uint256` | Amount of underlying tokens to stake |

### redeem

Redeems staked tokens, and stop earning rewards

```solidity
function redeem(uint256 amount) external override;
```

**Parameters**

| Name     | Type      | Description                                             |
| -------- | --------- | ------------------------------------------------------- |
| `amount` | `uint256` | Amount of staked tokens to redeem for underlying tokens |

### redeemTo

Redeems staked tokens, and stop earning rewards

_Staked tokens are redeemed from the sender, and underlying tokens are sent to the `to` address_

```solidity
function redeemTo(address to, uint256 amount) external override;
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
function cooldown() external override;
```

### slash

Sends underlying tokens to the given address, lowers the exchange rate accordingly, and
changes the contract's state to `POST_SLASHING`, which disables staking, cooldown period and
further slashing until the state is returned to `RUNNING`

_Only callable by the SafetyModule contract_

```solidity
function slash(address destination, uint256 amount) external onlySafetyModule returns (uint256);
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

_Only callable by the SafetyModule contract_

```solidity
function returnFunds(address from, uint256 amount) external onlySafetyModule;
```

**Parameters**

| Name     | Type      | Description                             |
| -------- | --------- | --------------------------------------- |
| `from`   | `address` | Address to transfer tokens from         |
| `amount` | `uint256` | Amount of underlying tokens to transfer |

### settleSlashing

Sets `isInPostSlashingState` to false, which re-enables staking, slashing and cooldown period

_Only callable by the SafetyModule contract_

```solidity
function settleSlashing() external onlySafetyModule;
```

### getNextCooldownTimestamp

Calculates a new cooldown timestamp

\*Calculation depends on the sender/receiver situation, as follows:

- If the timestamp of the sender is "better" or the timestamp of the recipient is 0, we take the one of the recipient
- Weighted average of from/to cooldown timestamps if:
  - The sender doesn't have the cooldown activated (timestamp 0).
  - The sender timestamp is expired
  - The sender has a "worse" timestamp
- If the receiver's cooldown timestamp expired (too old), the next is 0\*

```solidity
function getNextCooldownTimestamp(
    uint256 fromCooldownTimestamp,
    uint256 amountToReceive,
    address toAddress,
    uint256 toBalance
) public view returns (uint256);
```

**Parameters**

| Name                    | Type      | Description                        |
| ----------------------- | --------- | ---------------------------------- |
| `fromCooldownTimestamp` | `uint256` | Cooldown timestamp of the sender   |
| `amountToReceive`       | `uint256` | Amount of staked tokens to receive |
| `toAddress`             | `address` | Address of the recipient           |
| `toBalance`             | `uint256` | Current balance of the receiver    |

**Returns**

| Name     | Type      | Description                |
| -------- | --------- | -------------------------- |
| `<none>` | `uint256` | The new cooldown timestamp |

### paused

Indicates whether staking and transferring are currently paused

_Contract is paused if either this contract or the SafetyModule has been paused_

```solidity
function paused() public view override returns (bool);
```

**Returns**

| Name     | Type   | Description                     |
| -------- | ------ | ------------------------------- |
| `<none>` | `bool` | True if paused, false otherwise |

### setSafetyModule

Changes the SafetyModule contract used for reward management

_Only callable by governance_

```solidity
function setSafetyModule(address _newSafetyModule) external onlyRole(GOVERNANCE);
```

**Parameters**

| Name               | Type      | Description                              |
| ------------------ | --------- | ---------------------------------------- |
| `_newSafetyModule` | `address` | Address of the new SafetyModule contract |

### setMaxStakeAmount

Sets the max amount of staked tokens allowed per user

_Only callable by governance_

```solidity
function setMaxStakeAmount(uint256 _newMaxStakeAmount) external onlyRole(GOVERNANCE);
```

**Parameters**

| Name                 | Type      | Description                                      |
| -------------------- | --------- | ------------------------------------------------ |
| `_newMaxStakeAmount` | `uint256` | New max amount of staked tokens allowed per user |

### pause

Pauses staking and transferring of staked tokens

_Only callable by governance_

```solidity
function pause() external onlyRole(GOVERNANCE);
```

### unpause

Unpauses staking and transferring of staked tokens

_Only callable by governance_

```solidity
function unpause() external onlyRole(GOVERNANCE);
```

### \_updateExchangeRate

Updates the exchange rate of the staked token, based on the current underlying token balance
held by this contract and the total supply of the staked token

```solidity
function _updateExchangeRate(uint256 totalAssets, uint256 totalShares) internal;
```

### \_transfer

Internal ERC20 `_transfer` of the tokenized staked tokens

_Updates the cooldown timestamps if necessary, and updates the staking positions of both users
in the SafetyModule, accruing rewards in the process_

```solidity
function _transfer(address from, address to, uint256 amount) internal override whenNotPaused;
```

**Parameters**

| Name     | Type      | Description              |
| -------- | --------- | ------------------------ |
| `from`   | `address` | Address to transfer from |
| `to`     | `address` | Address to transfer to   |
| `amount` | `uint256` | Amount to transfer       |

### \_stake

```solidity
function _stake(address from, address to, uint256 amount) internal whenNotPaused;
```

### \_redeem

```solidity
function _redeem(address from, address to, uint256 amount) internal;
```
