# ISafetyModule

[Git Source](https://github.com/Increment-Finance/peripheral-contracts/blob/7b4166bd3bb6b2c678b84df162bcaf7af66b042d/contracts/interfaces/ISafetyModule.sol)

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

### stakedTokens

Gets the address of the StakedToken contract at the specified index in the `stakedTokens` array

```solidity
function stakedTokens(uint256 i) external view returns (IStakedToken);
```

**Parameters**

| Name | Type      | Description               |
| ---- | --------- | ------------------------- |
| `i`  | `uint256` | Index of the staked token |

**Returns**

| Name     | Type           | Description                         |
| -------- | -------------- | ----------------------------------- |
| `<none>` | `IStakedToken` | Address of the StakedToken contract |

### stakedTokenByAuctionId

Gets the StakedToken contract that was slashed for the given auction

```solidity
function stakedTokenByAuctionId(uint256 auctionId) external view returns (IStakedToken);
```

**Parameters**

| Name        | Type      | Description       |
| ----------- | --------- | ----------------- |
| `auctionId` | `uint256` | ID of the auction |

**Returns**

| Name     | Type           | Description                           |
| -------- | -------------- | ------------------------------------- |
| `<none>` | `IStakedToken` | StakedToken contract that was slashed |

### getStakedTokens

Returns the full list of staked tokens registered in the SafetyModule

```solidity
function getStakedTokens() external view returns (IStakedToken[] memory);
```

**Returns**

| Name     | Type             | Description                    |
| -------- | ---------------- | ------------------------------ |
| `<none>` | `IStakedToken[]` | Array of StakedToken contracts |

### getNumStakedTokens

Gets the number of staked tokens registered in the SafetyModule

```solidity
function getNumStakedTokens() external view returns (uint256);
```

**Returns**

| Name     | Type      | Description             |
| -------- | --------- | ----------------------- |
| `<none>` | `uint256` | Number of staked tokens |

### getStakedTokenIdx

Returns the index of the staked token in the `stakedTokens` array

_Reverts with `SafetyModule_InvalidStakedToken` if the staked token is not registered_

```solidity
function getStakedTokenIdx(address token) external view returns (uint256);
```

**Parameters**

| Name    | Type      | Description                 |
| ------- | --------- | --------------------------- |
| `token` | `address` | Address of the staked token |

**Returns**

| Name     | Type      | Description                                           |
| -------- | --------- | ----------------------------------------------------- |
| `<none>` | `uint256` | Index of the staked token in the `stakedTokens` array |

### slashAndStartAuction

Slashes a portion of all users' staked tokens, capped by maxPercentUserLoss, then
transfers the underlying tokens to the AuctionModule and starts an auction to sell them

```solidity
function slashAndStartAuction(
    address _stakedToken,
    uint8 _numLots,
    uint128 _lotPrice,
    uint128 _initialLotSize,
    uint256 _slashAmount,
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
| `_slashAmount`          | `uint256` | Amount of staked tokens to slash                                   |
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

### addStakedToken

Adds a new staked token to the SafetyModule's stakedTokens array

```solidity
function addStakedToken(IStakedToken _stakedToken) external;
```

**Parameters**

| Name           | Type           | Description                     |
| -------------- | -------------- | ------------------------------- |
| `_stakedToken` | `IStakedToken` | Address of the new staked token |

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

### StakedTokenAdded

Emitted when a staked token is added

```solidity
event StakedTokenAdded(address indexed stakedToken);
```

**Parameters**

| Name          | Type      | Description                 |
| ------------- | --------- | --------------------------- |
| `stakedToken` | `address` | Address of the staked token |

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

Emitted when a staked token is slashed and the underlying tokens are sent to the AuctionModule

```solidity
event TokensSlashedForAuction(
    address indexed stakedToken, uint256 slashAmount, uint256 underlyingAmount, uint256 indexed auctionId
);
```

**Parameters**

| Name               | Type      | Description                                           |
| ------------------ | --------- | ----------------------------------------------------- |
| `stakedToken`      | `address` | Address of the staked token                           |
| `slashAmount`      | `uint256` | Amount of staked tokens slashed                       |
| `underlyingAmount` | `uint256` | Amount of underlying tokens sent to the AuctionModule |
| `auctionId`        | `uint256` | ID of the auction                                     |

### AuctionTerminated

Emitted when an auction is terminated by governance

```solidity
event AuctionTerminated(
    uint256 indexed auctionId, address stakedToken, address underlyingToken, uint256 underlyingBalanceReturned
);
```

**Parameters**

| Name                        | Type      | Description                                                  |
| --------------------------- | --------- | ------------------------------------------------------------ |
| `auctionId`                 | `uint256` | ID of the auction                                            |
| `stakedToken`               | `address` | Address of the staked token that was slashed for the auction |
| `underlyingToken`           | `address` | Address of the underlying token being sold in the auction    |
| `underlyingBalanceReturned` | `uint256` | Amount of underlying tokens returned from the AuctionModule  |

### AuctionEnded

Emitted when an auction ends, either because all lots were sold or the time limit was reached

```solidity
event AuctionEnded(
    uint256 indexed auctionId, address stakedToken, address underlyingToken, uint256 underlyingBalanceReturned
);
```

**Parameters**

| Name                        | Type      | Description                                                  |
| --------------------------- | --------- | ------------------------------------------------------------ |
| `auctionId`                 | `uint256` | ID of the auction                                            |
| `stakedToken`               | `address` | Address of the staked token that was slashed for the auction |
| `underlyingToken`           | `address` | Address of the underlying token being sold in the auction    |
| `underlyingBalanceReturned` | `uint256` | Amount of underlying tokens returned from the AuctionModule  |

## Errors

### SafetyModule_CallerIsNotAuctionModule

Error returned when a caller other than the auction module tries to call a restricted function

```solidity
error SafetyModule_CallerIsNotAuctionModule(address caller);
```

**Parameters**

| Name     | Type      | Description           |
| -------- | --------- | --------------------- |
| `caller` | `address` | Address of the caller |

### SafetyModule_StakedTokenAlreadyRegistered

Error returned when trying to add a staked token that is already registered

```solidity
error SafetyModule_StakedTokenAlreadyRegistered(address stakedToken);
```

**Parameters**

| Name          | Type      | Description                 |
| ------------- | --------- | --------------------------- |
| `stakedToken` | `address` | Address of the staked token |

### SafetyModule_InvalidStakedToken

Error returned when passing an invalid staked token address to a function

```solidity
error SafetyModule_InvalidStakedToken(address invalidAddress);
```

**Parameters**

| Name             | Type      | Description             |
| ---------------- | --------- | ----------------------- |
| `invalidAddress` | `address` | Address that was passed |

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

### SafetyModule_CannotReplaceAuctionModuleActiveAuction

Error returned when trying to replace the AuctionModule while an auction is active

```solidity
error SafetyModule_CannotReplaceAuctionModuleActiveAuction();
```
