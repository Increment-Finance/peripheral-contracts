# IAuctionModule

[Git Source](https://github.com/Increment-Finance/peripheral-contracts/blob/50135f16a3332e293d1be01434556e7e68cc2f26/contracts/interfaces/IAuctionModule.sol)

**Author:**
webthethird

Interface for the AuctionModule contract

## Functions

### safetyModule

Returns the SafetyModule contract which manages this contract

```solidity
function safetyModule() external view returns (ISafetyModule);
```

**Returns**

| Name     | Type            | Description           |
| -------- | --------------- | --------------------- |
| `<none>` | `ISafetyModule` | SafetyModule contract |

### paymentToken

Returns the ERC20 token used for payments in all auctions

```solidity
function paymentToken() external view returns (IERC20);
```

**Returns**

| Name     | Type     | Description                   |
| -------- | -------- | ----------------------------- |
| `<none>` | `IERC20` | ERC20 token used for payments |

### nextAuctionId

Returns the ID of the next auction

```solidity
function nextAuctionId() external view returns (uint256);
```

**Returns**

| Name     | Type      | Description            |
| -------- | --------- | ---------------------- |
| `<none>` | `uint256` | ID of the next auction |

### tokensSoldPerAuction

Returns the number of tokens sold in the auction

```solidity
function tokensSoldPerAuction(uint256 _auctionId) external view returns (uint256);
```

**Parameters**

| Name         | Type      | Description       |
| ------------ | --------- | ----------------- |
| `_auctionId` | `uint256` | ID of the auction |

**Returns**

| Name     | Type      | Description           |
| -------- | --------- | --------------------- |
| `<none>` | `uint256` | Number of tokens sold |

### fundsRaisedPerAuction

Returns the amount of funds raised in the auction

```solidity
function fundsRaisedPerAuction(uint256 _auctionId) external view returns (uint256);
```

**Parameters**

| Name         | Type      | Description       |
| ------------ | --------- | ----------------- |
| `_auctionId` | `uint256` | ID of the auction |

**Returns**

| Name     | Type      | Description                     |
| -------- | --------- | ------------------------------- |
| `<none>` | `uint256` | Number of payment tokens raised |

### getCurrentLotSize

Returns the current lot size of the auction

_Lot size starts at `auction.initialLotSize` and increases by `auction.lotIncreaseIncrement` every
`auction.lotIncreasePeriod` seconds, unless the lot size times the number of remaining lots reaches the
contract's total balance of tokens, then the size remains fixed at `totalBalance / auction.remainingLots`_

```solidity
function getCurrentLotSize(uint256 _auctionId) external view returns (uint256);
```

**Parameters**

| Name         | Type      | Description       |
| ------------ | --------- | ----------------- |
| `_auctionId` | `uint256` | ID of the auction |

**Returns**

| Name     | Type      | Description                      |
| -------- | --------- | -------------------------------- |
| `<none>` | `uint256` | Current number of tokens per lot |

### getRemainingLots

Returns the number of lots still available for sale in the auction

```solidity
function getRemainingLots(uint256 _auctionId) external view returns (uint256);
```

**Parameters**

| Name         | Type      | Description       |
| ------------ | --------- | ----------------- |
| `_auctionId` | `uint256` | ID of the auction |

**Returns**

| Name     | Type      | Description                             |
| -------- | --------- | --------------------------------------- |
| `<none>` | `uint256` | Number of lots still available for sale |

### getLotPrice

Returns the price of each lot in the auction

```solidity
function getLotPrice(uint256 _auctionId) external view returns (uint256);
```

**Parameters**

| Name         | Type      | Description       |
| ------------ | --------- | ----------------- |
| `_auctionId` | `uint256` | ID of the auction |

**Returns**

| Name     | Type      | Description                         |
| -------- | --------- | ----------------------------------- |
| `<none>` | `uint256` | Price of each lot in payment tokens |

### getLotIncreaseIncrement

Returns the number of tokens by which the lot size increases each period

```solidity
function getLotIncreaseIncrement(uint256 _auctionId) external view returns (uint256);
```

**Parameters**

| Name         | Type      | Description       |
| ------------ | --------- | ----------------- |
| `_auctionId` | `uint256` | ID of the auction |

**Returns**

| Name     | Type      | Description               |
| -------- | --------- | ------------------------- |
| `<none>` | `uint256` | Size of each lot increase |

### getLotIncreasePeriod

Returns the amount of time between each lot size increase

```solidity
function getLotIncreasePeriod(uint256 _auctionId) external view returns (uint256);
```

**Parameters**

| Name         | Type      | Description       |
| ------------ | --------- | ----------------- |
| `_auctionId` | `uint256` | ID of the auction |

**Returns**

| Name     | Type      | Description                                      |
| -------- | --------- | ------------------------------------------------ |
| `<none>` | `uint256` | Number of seconds between each lot size increase |

### getAuctionToken

Returns the address of the token being auctioned

```solidity
function getAuctionToken(uint256 _auctionId) external view returns (IERC20);
```

**Parameters**

| Name         | Type      | Description       |
| ------------ | --------- | ----------------- |
| `_auctionId` | `uint256` | ID of the auction |

**Returns**

| Name     | Type     | Description                     |
| -------- | -------- | ------------------------------- |
| `<none>` | `IERC20` | The ERC20 token being auctioned |

### getStartTime

Returns the timestamp when the auction started

_The auction starts when the SafetyModule calls `startAuction`_

```solidity
function getStartTime(uint256 _auctionId) external view returns (uint256);
```

**Parameters**

| Name         | Type      | Description       |
| ------------ | --------- | ----------------- |
| `_auctionId` | `uint256` | ID of the auction |

**Returns**

| Name     | Type      | Description                        |
| -------- | --------- | ---------------------------------- |
| `<none>` | `uint256` | Timestamp when the auction started |

### getEndTime

Returns the timestamp when the auction ends

_Auction can end early if all lots are sold or if the auction is terminated by the SafetyModule_

```solidity
function getEndTime(uint256 _auctionId) external view returns (uint256);
```

**Parameters**

| Name         | Type      | Description       |
| ------------ | --------- | ----------------- |
| `_auctionId` | `uint256` | ID of the auction |

**Returns**

| Name     | Type      | Description                     |
| -------- | --------- | ------------------------------- |
| `<none>` | `uint256` | Timestamp when the auction ends |

### isAuctionActive

Returns whether the auction is still active

```solidity
function isAuctionActive(uint256 _auctionId) external view returns (bool);
```

**Parameters**

| Name         | Type      | Description       |
| ------------ | --------- | ----------------- |
| `_auctionId` | `uint256` | ID of the auction |

**Returns**

| Name     | Type   | Description                                          |
| -------- | ------ | ---------------------------------------------------- |
| `<none>` | `bool` | True if the auction is still active, false otherwise |

### completeAuction

Ends an auction after the time limit has been reached and approves the transfer of
unsold tokens and funds raised

_This function can be called by anyone, but only after the auction's end time has passed_

```solidity
function completeAuction(uint256 _auctionId) external;
```

**Parameters**

| Name         | Type      | Description       |
| ------------ | --------- | ----------------- |
| `_auctionId` | `uint256` | ID of the auction |

### buyLots

Buys one or more lots at the current lot size, and ends the auction if all lots are sold

\_The caller must approve this contract to transfer the lotPrice x numLotsToBuy in payment tokens\*

```solidity
function buyLots(uint256 _auctionId, uint8 _numLotsToBuy) external;
```

**Parameters**

| Name            | Type      | Description           |
| --------------- | --------- | --------------------- |
| `_auctionId`    | `uint256` | ID of the auction     |
| `_numLotsToBuy` | `uint8`   | Number of lots to buy |

### setPaymentToken

Sets the token required for payments in all auctions

```solidity
function setPaymentToken(IERC20 _newPaymentToken) external;
```

**Parameters**

| Name               | Type     | Description                    |
| ------------------ | -------- | ------------------------------ |
| `_newPaymentToken` | `IERC20` | ERC20 token to use for payment |

### setSafetyModule

Replaces the SafetyModule contract

```solidity
function setSafetyModule(ISafetyModule _newSafetyModule) external;
```

**Parameters**

| Name               | Type            | Description                              |
| ------------------ | --------------- | ---------------------------------------- |
| `_newSafetyModule` | `ISafetyModule` | Address of the new SafetyModule contract |

### startAuction

Starts a new auction

_First the SafetyModule slashes the StakedToken, sending the underlying slashed tokens here_

```solidity
function startAuction(
    IERC20 _token,
    uint8 _numLots,
    uint128 _lotPrice,
    uint128 _initialLotSize,
    uint96 _lotIncreaseIncrement,
    uint16 _lotIncreasePeriod,
    uint32 _timeLimit
) external returns (uint256);
```

**Parameters**

| Name                    | Type      | Description                                                        |
| ----------------------- | --------- | ------------------------------------------------------------------ |
| `_token`                | `IERC20`  | The ERC20 token to auction                                         |
| `_numLots`              | `uint8`   | Number of lots in the auction                                      |
| `_lotPrice`             | `uint128` | Price of each lot of tokens in payment tokens                      |
| `_initialLotSize`       | `uint128` | Initial number of tokens in each lot                               |
| `_lotIncreaseIncrement` | `uint96`  | Amount of tokens by which the lot size increases each period       |
| `_lotIncreasePeriod`    | `uint16`  | Number of seconds between each lot size increase                   |
| `_timeLimit`            | `uint32`  | Number of seconds before the auction ends if all lots are not sold |

**Returns**

| Name     | Type      | Description       |
| -------- | --------- | ----------------- |
| `<none>` | `uint256` | ID of the auction |

### terminateAuction

Terminates an auction early and approves the transfer of unsold tokens and funds raised

```solidity
function terminateAuction(uint256 _auctionId) external;
```

**Parameters**

| Name         | Type      | Description       |
| ------------ | --------- | ----------------- |
| `_auctionId` | `uint256` | ID of the auction |

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

### AuctionStarted

Emitted when a new auction is started

```solidity
event AuctionStarted(
    uint256 indexed auctionId,
    address indexed token,
    uint64 endTimestamp,
    uint128 lotPrice,
    uint128 initialLotSize,
    uint8 numLots,
    uint96 lotIncreaseIncrement,
    uint16 lotIncreasePeriod
);
```

**Parameters**

| Name                   | Type      | Description                                                  |
| ---------------------- | --------- | ------------------------------------------------------------ |
| `auctionId`            | `uint256` | ID of the auction                                            |
| `token`                | `address` | Address of the token being auctioned                         |
| `endTimestamp`         | `uint64`  | Timestamp when the auction ends                              |
| `lotPrice`             | `uint128` | Price of each lot of tokens in payment token                 |
| `initialLotSize`       | `uint128` | Initial number of tokens in each lot                         |
| `numLots`              | `uint8`   | Number of lots in the auction                                |
| `lotIncreaseIncrement` | `uint96`  | Amount of tokens by which the lot size increases each period |
| `lotIncreasePeriod`    | `uint16`  | Number of seconds between each lot size increase             |

### AuctionEnded

Emitted when an auction ends, because either all lots were sold or the time limit was reached

```solidity
event AuctionEnded(
    uint256 indexed auctionId,
    uint8 remainingLots,
    uint256 finalLotSize,
    uint256 totalTokensSold,
    uint256 totalFundsRaised
);
```

**Parameters**

| Name               | Type      | Description                           |
| ------------------ | --------- | ------------------------------------- |
| `auctionId`        | `uint256` | ID of the auction                     |
| `remainingLots`    | `uint8`   | Number of lots that were not sold     |
| `finalLotSize`     | `uint256` | Lot size when the auction ended       |
| `totalTokensSold`  | `uint256` | Total number of tokens sold           |
| `totalFundsRaised` | `uint256` | Total amount of payment tokens raised |

### LotsSold

Emitted when a lot is sold

```solidity
event LotsSold(uint256 indexed auctionId, address indexed buyer, uint8 numLots, uint256 lotSize, uint128 lotPrice);
```

**Parameters**

| Name        | Type      | Description           |
| ----------- | --------- | --------------------- |
| `auctionId` | `uint256` | ID of the auction     |
| `buyer`     | `address` | Address of the buyer  |
| `numLots`   | `uint8`   | Number of lots sold   |
| `lotSize`   | `uint256` | Size of the lot sold  |
| `lotPrice`  | `uint128` | Price of the lot sold |

### PaymentTokenChanged

Emitted when the payment token is changed

```solidity
event PaymentTokenChanged(address oldPaymentToken, address newPaymentToken);
```

**Parameters**

| Name              | Type      | Description                      |
| ----------------- | --------- | -------------------------------- |
| `oldPaymentToken` | `address` | Address of the old payment token |
| `newPaymentToken` | `address` | Address of the new payment token |

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

## Errors

### AuctionModule_CallerIsNotSafetyModule

Error returned when a caller other than the SafetyModule tries to call a restricted function

```solidity
error AuctionModule_CallerIsNotSafetyModule(address caller);
```

**Parameters**

| Name     | Type      | Description           |
| -------- | --------- | --------------------- |
| `caller` | `address` | Address of the caller |

### AuctionModule_InvalidAuctionId

Error returned when a caller passes an invalid auction ID to a function

```solidity
error AuctionModule_InvalidAuctionId(uint256 invalidId);
```

**Parameters**

| Name        | Type      | Description        |
| ----------- | --------- | ------------------ |
| `invalidId` | `uint256` | ID that was passed |

### AuctionModule_InvalidZeroArgument

Error returned when a caller passes a zero to a function that requires a non-zero value

```solidity
error AuctionModule_InvalidZeroArgument(uint256 argIndex);
```

**Parameters**

| Name       | Type      | Description                                   |
| ---------- | --------- | --------------------------------------------- |
| `argIndex` | `uint256` | Index of the argument where a zero was passed |

### AuctionModule_InvalidZeroAddress

Error returned when a caller passes a zero address to a function that requires a non-zero address

```solidity
error AuctionModule_InvalidZeroAddress(uint256 argIndex);
```

**Parameters**

| Name       | Type      | Description                                           |
| ---------- | --------- | ----------------------------------------------------- |
| `argIndex` | `uint256` | Index of the argument where a zero address was passed |

### AuctionModule_AuctionNotActive

Error returned when a caller calls a function that requires the auction to be active

```solidity
error AuctionModule_AuctionNotActive(uint256 auctionId);
```

**Parameters**

| Name        | Type      | Description       |
| ----------- | --------- | ----------------- |
| `auctionId` | `uint256` | ID of the auction |

### AuctionModule_AuctionStillActive

Error returned when a user calls `completeAuction` before the auction's end time

```solidity
error AuctionModule_AuctionStillActive(uint256 auctionId, uint256 endTime);
```

**Parameters**

| Name        | Type      | Description                     |
| ----------- | --------- | ------------------------------- |
| `auctionId` | `uint256` | ID of the auction               |
| `endTime`   | `uint256` | Timestamp when the auction ends |

### AuctionModule_NotEnoughLotsRemaining

Error returned when a user tries to buy more than the number of lots remaining

```solidity
error AuctionModule_NotEnoughLotsRemaining(uint256 auctionId, uint256 lotsRemaining);
```

**Parameters**

| Name            | Type      | Description              |
| --------------- | --------- | ------------------------ |
| `auctionId`     | `uint256` | ID of the auction        |
| `lotsRemaining` | `uint256` | Number of lots remaining |
