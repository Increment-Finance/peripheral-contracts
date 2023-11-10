# StakedToken

[Git Source](https://github.com/Increment-Finance/peripheral-contracts/blob/fc86e744c6664e8852ac82787aa2f73b160e6a5d/contracts/StakedToken.sol)

**Inherits:**
[IStakedToken](/contracts/interfaces/IStakedToken.sol/interface.IStakedToken.md), ERC20Permit, IncreAccessControl, Pausable, ReentrancyGuard

**Author:**
webthethird

Based on Aave's StakedToken, but with reward management outsourced to the SafetyModule

## State Variables

### STAKED_TOKEN

Address of the underlying token to stake

```solidity
IERC20 public immutable STAKED_TOKEN;
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

### stakersCooldowns

Timestamp of the start of the current cooldown period for each user

```solidity
mapping(address => uint256) public stakersCooldowns;
```

## Functions

### constructor

StakedToken constructor

```solidity
constructor(
    IERC20 _stakedToken,
    ISafetyModule _safetyModule,
    uint256 _cooldownSeconds,
    uint256 _unstakeWindow,
    string memory _name,
    string memory _symbol
) ERC20(_name, _symbol) ERC20Permit(_name);
```

**Parameters**

| Name               | Type            | Description                                                                        |
| ------------------ | --------------- | ---------------------------------------------------------------------------------- |
| `_stakedToken`     | `IERC20`        | The underlying token to stake                                                      |
| `_safetyModule`    | `ISafetyModule` | The SafetyModule contract to use for reward management                             |
| `_cooldownSeconds` | `uint256`       | The number of seconds that users must wait between calling `cooldown` and `redeem` |
| `_unstakeWindow`   | `uint256`       | The number of seconds available to redeem once the cooldown period is fullfilled   |
| `_name`            | `string`        | The name of the token                                                              |
| `_symbol`          | `string`        | The symbol of the token                                                            |

### stake

Stakes tokens on behalf of the given address, and starts earning rewards

_Tokens are transferred from the transaction sender, not from the `onBehalfOf` address_

```solidity
function stake(address onBehalfOf, uint256 amount) external override;
```

**Parameters**

| Name         | Type      | Description                   |
| ------------ | --------- | ----------------------------- |
| `onBehalfOf` | `address` | Address to stake on behalf of |
| `amount`     | `uint256` | Amount of tokens to stake     |

### redeem

Redeems staked tokens, and stop earning rewards

```solidity
function redeem(address to, uint256 amount) external override;
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
function cooldown() external override;
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

| Name                    | Type      | Description                      |
| ----------------------- | --------- | -------------------------------- |
| `fromCooldownTimestamp` | `uint256` | Cooldown timestamp of the sender |
| `amountToReceive`       | `uint256` | Amount                           |
| `toAddress`             | `address` | Address of the recipient         |
| `toBalance`             | `uint256` | Current balance of the receiver  |

**Returns**

| Name     | Type      | Description                |
| -------- | --------- | -------------------------- |
| `<none>` | `uint256` | The new cooldown timestamp |

### setSafetyModule

Changes the SafetyModule contract used for reward management

_Only callable by Governance_

```solidity
function setSafetyModule(address _safetyModule) external onlyRole(GOVERNANCE);
```

**Parameters**

| Name            | Type      | Description                              |
| --------------- | --------- | ---------------------------------------- |
| `_safetyModule` | `address` | Address of the new SafetyModule contract |

### \_transfer

Internal ERC20 `_transfer` of the tokenized staked tokens

_Updates the cooldown timestamps if necessary, and updates the staking positions of both users
in the SafetyModule, accruing rewards in the process_

```solidity
function _transfer(address from, address to, uint256 amount) internal override;
```

**Parameters**

| Name     | Type      | Description              |
| -------- | --------- | ------------------------ |
| `from`   | `address` | Address to transfer from |
| `to`     | `address` | Address to transfer to   |
| `amount` | `uint256` | Amount to transfer       |
