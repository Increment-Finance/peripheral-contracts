# ISafetyModule

[Git Source](https://github.com/Increment-Finance/peripheral-contracts/blob/50135f16a3332e293d1be01434556e7e68cc2f26/contracts/interfaces/ISafetyModule.sol)

**Inherits:**
IRewardContract

**Author:**
webthethird

Interface for the SafetyModule contract

## Functions

### auctionModule

Gets the address of the AuctionModule contract

```solidity
function auctionModule() external view returns (IAuctionModule);
```

**Returns**

| Name     | Type             | Description                |
| -------- | ---------------- | -------------------------- |
| `<none>` | `IAuctionModule` | The AuctionModule contract |

### smRewardDistributor

Gets the address of the SMRewardDistributor contract

```solidity
function smRewardDistributor() external view returns (ISMRewardDistributor);
```

**Returns**

| Name     | Type                   | Description                      |
| -------- | ---------------------- | -------------------------------- |
| `<none>` | `ISMRewardDistributor` | The SMRewardDistributor contract |

### stakingTokens

Gets the address of the StakedToken contract at the specified index in the `stakingTokens` array

```solidity
function stakingTokens(uint256 i) external view returns (IStakedToken);
```

**Parameters**

| Name | Type      | Description                |
| ---- | --------- | -------------------------- |
| `i`  | `uint256` | Index of the staking token |

**Returns**

| Name     | Type           | Description                         |
| -------- | -------------- | ----------------------------------- |
| `<none>` | `IStakedToken` | Address of the StakedToken contract |

### stakingTokenByAuctionId

Gets the StakedToken contract that was slashed for the given auction

```solidity
function stakingTokenByAuctionId(uint256 auctionId) external view returns (IStakedToken);
```

**Parameters**

| Name        | Type      | Description       |
| ----------- | --------- | ----------------- |
| `auctionId` | `uint256` | ID of the auction |

**Returns**

| Name     | Type           | Description                           |
| -------- | -------------- | ------------------------------------- |
| `<none>` | `IStakedToken` | StakedToken contract that was slashed |

### getNumStakingTokens

Gets the number of staking tokens registered in the SafetyModule

```solidity
function getNumStakingTokens() external view returns (uint256);
```

**Returns**

| Name     | Type      | Description              |
| -------- | --------- | ------------------------ |
| `<none>` | `uint256` | Number of staking tokens |

### getStakingTokenIdx

Returns the index of the staking token in the `stakingTokens` array

_Reverts with `SafetyModule_InvalidStakingToken` if the staking token is not registered_

```solidity
function getStakingTokenIdx(address token) external view returns (uint256);
```

**Parameters**

| Name    | Type      | Description                  |
| ------- | --------- | ---------------------------- |
| `token` | `address` | Address of the staking token |

**Returns**

| Name     | Type      | Description                                             |
| -------- | --------- | ------------------------------------------------------- |
| `<none>` | `uint256` | Index of the staking token in the `stakingTokens` array |

### slashAndStartAuction

Slashes a portion of all users' staked tokens, capped by maxPercentUserLoss, then
transfers the underlying tokens to the AuctionModule and starts an auction to sell them

```solidity
function slashAndStartAuction(
    address _stakedToken,
    uint8 _numLots,
    uint128 _lotPrice,
    uint128 _initialLotSize,
    uint64 _slashPercent,
    uint96 _lotIncreaseIncrement,
    uint16 _lotIncreasePeriod,
    uint32 _timeLimit
) external returns (uint256);
```

**Parameters**

| Name                    | Type      | Description                                                        |
| ----------------------- | --------- | ------------------------------------------------------------------ |
| `_stakedToken`          | `address` | Address of the staked token to slash                               |
| `_numLots`              | `uint8`   | Number of lots in the auction                                      |
| `_lotPrice`             | `uint128` | Fixed price of each lot in the auction                             |
| `_initialLotSize`       | `uint128` | Initial number of underlying tokens in each lot                    |
| `_slashPercent`         | `uint64`  | Percentage of staked tokens to slash, normalized to 1e18           |
| `_lotIncreaseIncrement` | `uint96`  | Amount of tokens by which the lot size increases each period       |
| `_lotIncreasePeriod`    | `uint16`  | Number of seconds between each lot size increase                   |
| `_timeLimit`            | `uint32`  | Number of seconds before the auction ends if all lots are not sold |

**Returns**

| Name     | Type      | Description       |
| -------- | --------- | ----------------- |
| `<none>` | `uint256` | ID of the auction |

### terminateAuction

Terminates an auction early and returns any remaining underlying tokens to the StakedToken

```solidity
function terminateAuction(uint256 _auctionId) external;
```

**Parameters**

| Name         | Type      | Description       |
| ------------ | --------- | ----------------- |
| `_auctionId` | `uint256` | ID of the auction |

### auctionEnded

Called by the AuctionModule when an auction ends, and returns the remaining balance of
underlying tokens from the auction to the StakedToken

```solidity
function auctionEnded(uint256 _auctionId, uint256 _remainingBalance) external;
```

**Parameters**

| Name                | Type      | Description                                            |
| ------------------- | --------- | ------------------------------------------------------ |
| `_auctionId`        | `uint256` | ID of the auction                                      |
| `_remainingBalance` | `uint256` | Amount of underlying tokens remaining from the auction |

### returnFunds

Donates underlying tokens to a StakedToken contract, raising its exchange rate

_Unsold tokens are returned automatically from the AuctionModule when one ends, so this is meant
for transferring tokens from some other source, which must approve the StakedToken to transfer first_

```solidity
function returnFunds(address _stakingToken, address _from, uint256 _amount) external;
```

**Parameters**

| Name            | Type      | Description                                                        |
| --------------- | --------- | ------------------------------------------------------------------ |
| `_stakingToken` | `address` | Address of the StakedToken contract to return underlying tokens to |
| `_from`         | `address` | Address of the account to transfer funds from                      |
| `_amount`       | `uint256` | Amount of underlying tokens to return                              |

### withdrawFundsRaisedFromAuction

Sends payment tokens raised in auctions from the AuctionModule to the governance treasury

```solidity
function withdrawFundsRaisedFromAuction(uint256 _amount) external;
```

**Parameters**

| Name      | Type      | Description                          |
| --------- | --------- | ------------------------------------ |
| `_amount` | `uint256` | Amount of payment tokens to withdraw |

### setAuctionModule

Sets the address of the AuctionModule contract

```solidity
function setAuctionModule(IAuctionModule _newAuctionModule) external;
```

**Parameters**

| Name                | Type             | Description                           |
| ------------------- | ---------------- | ------------------------------------- |
| `_newAuctionModule` | `IAuctionModule` | Address of the AuctionModule contract |

### setRewardDistributor

Sets the address of the SMRewardDistributor contract

```solidity
function setRewardDistributor(ISMRewardDistributor _newRewardDistributor) external;
```

**Parameters**

| Name                    | Type                   | Description                                 |
| ----------------------- | ---------------------- | ------------------------------------------- |
| `_newRewardDistributor` | `ISMRewardDistributor` | Address of the SMRewardDistributor contract |

### addStakingToken

Adds a new staking token to the SafetyModule's stakingTokens array

```solidity
function addStakingToken(IStakedToken _stakingToken) external;
```

**Parameters**

| Name            | Type           | Description                      |
| --------------- | -------------- | -------------------------------- |
| `_stakingToken` | `IStakedToken` | Address of the new staking token |

### pause

Pause the contract

```solidity
function pause() external;
```

### unpause

Unpause the contract

```solidity
function unpause() external;
```

## Events

### StakingTokenAdded

Emitted when a staking token is added

```solidity
event StakingTokenAdded(address indexed stakingToken);
```

**Parameters**

| Name           | Type      | Description                  |
| -------------- | --------- | ---------------------------- |
| `stakingToken` | `address` | Address of the staking token |

### StakingTokenRemoved

Emitted when a staking token is removed

```solidity
event StakingTokenRemoved(address indexed stakingToken);
```

**Parameters**

| Name           | Type      | Description                  |
| -------------- | --------- | ---------------------------- |
| `stakingToken` | `address` | Address of the staking token |

### AuctionModuleUpdated

Emitted when the AuctionModule is updated by governance

```solidity
event AuctionModuleUpdated(address oldAuctionModule, address newAuctionModule);
```

**Parameters**

| Name               | Type      | Description                      |
| ------------------ | --------- | -------------------------------- |
| `oldAuctionModule` | `address` | Address of the old AuctionModule |
| `newAuctionModule` | `address` | Address of the new AuctionModule |

### RewardDistributorUpdated

Emitted when the SMRewardDistributor is updated by governance

```solidity
event RewardDistributorUpdated(address oldRewardDistributor, address newRewardDistributor);
```

**Parameters**

| Name                   | Type      | Description                            |
| ---------------------- | --------- | -------------------------------------- |
| `oldRewardDistributor` | `address` | Address of the old SMRewardDistributor |
| `newRewardDistributor` | `address` | Address of the new SMRewardDistributor |

### TokensSlashedForAuction

Emitted when a staking token is slashed and the underlying tokens are sent to the AuctionModule

```solidity
event TokensSlashedForAuction(
    address indexed stakingToken, uint256 slashAmount, uint256 underlyingAmount, uint256 indexed auctionId
);
```

**Parameters**

| Name               | Type      | Description                                           |
| ------------------ | --------- | ----------------------------------------------------- |
| `stakingToken`     | `address` | Address of the staking token                          |
| `slashAmount`      | `uint256` | Amount of staking tokens slashed                      |
| `underlyingAmount` | `uint256` | Amount of underlying tokens sent to the AuctionModule |
| `auctionId`        | `uint256` | ID of the auction                                     |

### AuctionTerminated

Emitted when an auction is terminated by governance

```solidity
event AuctionTerminated(
    uint256 indexed auctionId, address stakingToken, address underlyingToken, uint256 underlyingBalanceReturned
);
```

**Parameters**

| Name                        | Type      | Description                                                   |
| --------------------------- | --------- | ------------------------------------------------------------- |
| `auctionId`                 | `uint256` | ID of the auction                                             |
| `stakingToken`              | `address` | Address of the staking token that was slashed for the auction |
| `underlyingToken`           | `address` | Address of the underlying token being sold in the auction     |
| `underlyingBalanceReturned` | `uint256` | Amount of underlying tokens returned from the AuctionModule   |

### AuctionEnded

Emitted when an auction ends, either because all lots were sold or the time limit was reached

```solidity
event AuctionEnded(
    uint256 indexed auctionId, address stakingToken, address underlyingToken, uint256 underlyingBalanceReturned
);
```

**Parameters**

| Name                        | Type      | Description                                                   |
| --------------------------- | --------- | ------------------------------------------------------------- |
| `auctionId`                 | `uint256` | ID of the auction                                             |
| `stakingToken`              | `address` | Address of the staking token that was slashed for the auction |
| `underlyingToken`           | `address` | Address of the underlying token being sold in the auction     |
| `underlyingBalanceReturned` | `uint256` | Amount of underlying tokens returned from the AuctionModule   |

## Errors

### SafetyModule_CallerIsNotStakingToken

Error returned a caller other than a registered staking token tries to call a restricted function

```solidity
error SafetyModule_CallerIsNotStakingToken(address caller);
```

**Parameters**

| Name     | Type      | Description           |
| -------- | --------- | --------------------- |
| `caller` | `address` | Address of the caller |

### SafetyModule_CallerIsNotAuctionModule

Error returned a caller other than the auction module tries to call a restricted function

```solidity
error SafetyModule_CallerIsNotAuctionModule(address caller);
```

**Parameters**

| Name     | Type      | Description           |
| -------- | --------- | --------------------- |
| `caller` | `address` | Address of the caller |

### SafetyModule_StakingTokenAlreadyRegistered

Error returned when trying to add a staking token that is already registered

```solidity
error SafetyModule_StakingTokenAlreadyRegistered(address stakingToken);
```

**Parameters**

| Name           | Type      | Description                  |
| -------------- | --------- | ---------------------------- |
| `stakingToken` | `address` | Address of the staking token |

### SafetyModule_InvalidStakingToken

Error returned when passing an invalid staking token address to a function

```solidity
error SafetyModule_InvalidStakingToken(address invalidAddress);
```

**Parameters**

| Name             | Type      | Description             |
| ---------------- | --------- | ----------------------- |
| `invalidAddress` | `address` | Address that was passed |

### SafetyModule_InvalidSlashPercentTooHigh

Error returned when passing a `slashPercent` value that is greater than 100% (1e18)

```solidity
error SafetyModule_InvalidSlashPercentTooHigh();
```

### SafetyModule_InsufficientSlashedTokensForAuction

Error returned when the maximum auctionable amount of underlying tokens is less than
the given initial lot size multiplied by the number of lots when calling `slashAndStartAuction`

```solidity
error SafetyModule_InsufficientSlashedTokensForAuction(IERC20 token, uint256 amount, uint256 maxAmount);
```

**Parameters**

| Name        | Type      | Description                                           |
| ----------- | --------- | ----------------------------------------------------- |
| `token`     | `IERC20`  | The underlying ERC20 token                            |
| `amount`    | `uint256` | The initial lot size multiplied by the number of lots |
| `maxAmount` | `uint256` | The maximum auctionable amount of underlying tokens   |
