# AuctionModule

[Git Source](https://github.com/Increment-Finance/peripheral-contracts/blob/cf0cdb73c3067e3512acceef3935e48ab8394c32/contracts/AuctionModule.sol)

**Inherits:**
[IAuctionModule](/contracts/interfaces/IAuctionModule.sol/interface.IAuctionModule.md), IncreAccessControl, Pausable, ReentrancyGuard

**Author:**
webthethird

Handles auctioning tokens slashed by the SafetyModule, triggered by governance
in the event of an insolvency in the vault which cannot be covered by the insurance fund

## State Variables

### safetyModule

SafetyModule contract which manages staked token rewards, slashing and auctions

```solidity
ISafetyModule public safetyModule;
```

### paymentToken

Payment token used to purchase lots in auctions

```solidity
IERC20 public paymentToken;
```

### \_nextAuctionId

ID of the next auction

```solidity
uint256 internal _nextAuctionId;
```

### \_auctions

Mapping of auction IDs to auction information

```solidity
mapping(uint256 => Auction) internal _auctions;
```

### \_tokensSoldPerAuction

Mapping of auction IDs to the number of tokens sold in that auction

```solidity
mapping(uint256 => uint256) internal _tokensSoldPerAuction;
```

### \_fundsRaisedPerAuction

Mapping of auction IDs to the number of payment tokens raised in that auction

```solidity
mapping(uint256 => uint256) internal _fundsRaisedPerAuction;
```

## Functions

### onlySafetyModule

Modifier for functions that should only be called by the SafetyModule

```solidity
modifier onlySafetyModule();
```

### constructor

AuctionModule constructor

```solidity
constructor(ISafetyModule _safetyModule, IERC20 _paymentToken) payable;
```

**Parameters**

| Name            | Type            | Description                                   |
| --------------- | --------------- | --------------------------------------------- |
| `_safetyModule` | `ISafetyModule` | SafetyModule contract to manage this contract |
| `_paymentToken` | `IERC20`        | ERC20 token used to purchase lots in auctions |

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

### getTokensSold

Returns the number of tokens sold in the auction

```solidity
function getTokensSold(uint256 _auctionId) external view returns (uint256);
```

**Parameters**

| Name         | Type      | Description       |
| ------------ | --------- | ----------------- |
| `_auctionId` | `uint256` | ID of the auction |

**Returns**

| Name     | Type      | Description           |
| -------- | --------- | --------------------- |
| `<none>` | `uint256` | Number of tokens sold |

### getFundsRaised

Returns the amount of funds raised in the auction

```solidity
function getFundsRaised(uint256 _auctionId) external view returns (uint256);
```

**Parameters**

| Name         | Type      | Description       |
| ------------ | --------- | ----------------- |
| `_auctionId` | `uint256` | ID of the auction |

**Returns**

| Name     | Type      | Description                     |
| -------- | --------- | ------------------------------- |
| `<none>` | `uint256` | Number of payment tokens raised |

### getNextAuctionId

Returns the ID of the next auction

```solidity
function getNextAuctionId() external view returns (uint256);
```

**Returns**

| Name     | Type      | Description            |
| -------- | --------- | ---------------------- |
| `<none>` | `uint256` | ID of the next auction |

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

### buyLots

Buys one or more lots at the current lot size, and ends the auction if all lots are sold

_The caller must approve this contract to transfer the lotPrice x numLotsToBuy in payment tokens_

```solidity
function buyLots(uint256 _auctionId, uint8 _numLotsToBuy) external nonReentrant whenNotPaused;
```

**Parameters**

| Name            | Type      | Description           |
| --------------- | --------- | --------------------- |
| `_auctionId`    | `uint256` | ID of the auction     |
| `_numLotsToBuy` | `uint8`   | Number of lots to buy |

### completeAuction

```solidity
function completeAuction(uint256 _auctionId) external nonReentrant whenNotPaused;
```

### paused

Indicates whether auctions are currently paused

_Contract is paused if either this contract or the SafetyModule has been paused_

```solidity
function paused() public view override returns (bool);
```

**Returns**

| Name     | Type   | Description                     |
| -------- | ------ | ------------------------------- |
| `<none>` | `bool` | True if paused, false otherwise |

### startAuction

Starts a new auction

_Only callable by the SafetyModule_

```solidity
function startAuction(
    IERC20 _token,
    uint8 _numLots,
    uint128 _lotPrice,
    uint128 _initialLotSize,
    uint96 _lotIncreaseIncrement,
    uint16 _lotIncreasePeriod,
    uint32 _timeLimit
) external onlySafetyModule whenNotPaused returns (uint256);
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

_Only callable by the SafetyModule_

```solidity
function terminateAuction(uint256 _auctionId) external onlySafetyModule;
```

**Parameters**

| Name         | Type      | Description       |
| ------------ | --------- | ----------------- |
| `_auctionId` | `uint256` | ID of the auction |

### setPaymentToken

Sets the token required for payments in all auctions

_Only callable by governance_

```solidity
function setPaymentToken(IERC20 _newPaymentToken) external onlyRole(GOVERNANCE);
```

**Parameters**

| Name               | Type     | Description                    |
| ------------------ | -------- | ------------------------------ |
| `_newPaymentToken` | `IERC20` | ERC20 token to use for payment |

### setSafetyModule

Replaces the SafetyModule contract

_Only callable by governance_

```solidity
function setSafetyModule(ISafetyModule _newSafetyModule) external onlyRole(GOVERNANCE);
```

**Parameters**

| Name               | Type            | Description                              |
| ------------------ | --------------- | ---------------------------------------- |
| `_newSafetyModule` | `ISafetyModule` | Address of the new SafetyModule contract |

### pause

Pause the contract

_Only callable by governance_

```solidity
function pause() external override onlyRole(GOVERNANCE);
```

### unpause

Unpause the contract

_Only callable by governance_

```solidity
function unpause() external override onlyRole(GOVERNANCE);
```

### \_getCurrentLotSize

```solidity
function _getCurrentLotSize(uint256 _auctionId) internal view returns (uint256);
```

### \_completeAuction

```solidity
function _completeAuction(uint256 _auctionId, bool _terminatedEarly) internal;
```

## Structs

### Auction

Struct representing an auction

```solidity
struct Auction {
    IERC20 token;
    bool active;
    uint128 lotPrice;
    uint128 initialLotSize;
    uint8 numLots;
    uint8 remainingLots;
    uint64 startTime;
    uint64 endTime;
    uint16 lotIncreasePeriod;
    uint96 lotIncreaseIncrement;
}
```

**Properties**

| Name                   | Type      | Description                                                  |
| ---------------------- | --------- | ------------------------------------------------------------ |
| `token`                | `IERC20`  | Address of the token being auctioned                         |
| `active`               | `bool`    | Whether the auction is still active                          |
| `lotPrice`             | `uint128` | Price of each lot of tokens, denominated in payment tokens   |
| `initialLotSize`       | `uint128` | Initial size of each lot                                     |
| `numLots`              | `uint8`   | Total number of lots in the auction                          |
| `remainingLots`        | `uint8`   | Number of lots that have not been sold                       |
| `startTime`            | `uint64`  | Timestamp when the auction started                           |
| `endTime`              | `uint64`  | Timestamp when the auction ends                              |
| `lotIncreasePeriod`    | `uint16`  | Number of seconds between each lot size increase             |
| `lotIncreaseIncrement` | `uint96`  | Amount of tokens by which the lot size increases each period |
