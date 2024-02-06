# SafetyModule

[Git Source](https://github.com/Increment-Finance/peripheral-contracts/blob/cf0cdb73c3067e3512acceef3935e48ab8394c32/contracts/SafetyModule.sol)

**Inherits:**
[ISafetyModule](/contracts/interfaces/ISafetyModule.sol/interface.ISafetyModule.md), IncreAccessControl, Pausable, ReentrancyGuard

**Author:**
webthethird

Handles reward accrual and distribution for staked tokens, and allows governance to auction a
percentage of user funds in the event of an insolvency in the vault

## State Variables

### auctionModule

Address of the auction module, which sells user funds in the event of an insolvency

```solidity
IAuctionModule public auctionModule;
```

### smRewardDistributor

Address of the SMRewardDistributor contract, which distributes rewards to stakers

```solidity
ISMRewardDistributor public smRewardDistributor;
```

### stakedTokens

Array of staked tokens that are registered with the SafetyModule

```solidity
IStakedToken[] public stakedTokens;
```

### stakedTokenByAuctionId

Mapping from auction ID to staked token that was slashed for the auction

```solidity
mapping(uint256 => IStakedToken) public stakedTokenByAuctionId;
```

## Functions

### onlyStakedToken

Modifier for functions that can only be called by a registered StakedToken contract,
i.e., `updatePosition`

```solidity
modifier onlyStakedToken();
```

### onlyAuctionModule

Modifier for functions that can only be called by the AuctionModule contract,
i.e., `auctionEnded`

```solidity
modifier onlyAuctionModule();
```

### constructor

SafetyModule constructor

```solidity
constructor(address _auctionModule, address _smRewardDistributor) payable;
```

**Parameters**

| Name                   | Type      | Description                                                                         |
| ---------------------- | --------- | ----------------------------------------------------------------------------------- |
| `_auctionModule`       | `address` | Address of the auction module, which sells user funds in the event of an insolvency |
| `_smRewardDistributor` | `address` | Address of the SMRewardDistributor contract, which distributes rewards to stakers   |

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
function getNumStakedTokens() public view returns (uint256);
```

**Returns**

| Name     | Type      | Description             |
| -------- | --------- | ----------------------- |
| `<none>` | `uint256` | Number of staked tokens |

### getStakedTokenIdx

Returns the index of the staked token in the `stakedTokens` array

_Reverts with `SafetyModule_InvalidStakedToken` if the staked token is not registered_

```solidity
function getStakedTokenIdx(address token) public view returns (uint256);
```

**Parameters**

| Name    | Type      | Description                 |
| ------- | --------- | --------------------------- |
| `token` | `address` | Address of the staked token |

**Returns**

| Name     | Type      | Description                                           |
| -------- | --------- | ----------------------------------------------------- |
| `<none>` | `uint256` | Index of the staked token in the `stakedTokens` array |

### updatePosition

Updates the position of a user for a given staked token and accrues rewards to the user

_Only callable by a registered StakedToken contract_

```solidity
function updatePosition(address stakedToken, address staker) external override nonReentrant onlyStakedToken;
```

**Parameters**

| Name          | Type      | Description                 |
| ------------- | --------- | --------------------------- |
| `stakedToken` | `address` | Address of the staked token |
| `staker`      | `address` | Address of the staker       |

### auctionEnded

Called by the AuctionModule when an auction ends, and returns the remaining balance of
underlying tokens from the auction to the StakedToken

_Only callable by the auction module_

```solidity
function auctionEnded(uint256 _auctionId, uint256 _remainingBalance) external onlyAuctionModule;
```

**Parameters**

| Name                | Type      | Description                                            |
| ------------------- | --------- | ------------------------------------------------------ |
| `_auctionId`        | `uint256` | ID of the auction                                      |
| `_remainingBalance` | `uint256` | Amount of underlying tokens remaining from the auction |

### slashAndStartAuction

Slashes a portion of all users' staked tokens, capped by maxPercentUserLoss, then
transfers the underlying tokens to the AuctionModule and starts an auction to sell them

_Only callable by governance_

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
) external onlyRole(GOVERNANCE) returns (uint256);
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

_Only callable by governance_

```solidity
function terminateAuction(uint256 _auctionId) external onlyRole(GOVERNANCE);
```

**Parameters**

| Name         | Type      | Description       |
| ------------ | --------- | ----------------- |
| `_auctionId` | `uint256` | ID of the auction |

### returnFunds

Donates underlying tokens to a StakedToken contract, raising its exchange rate

_Only callable by governance_

```solidity
function returnFunds(address _stakedToken, address _from, uint256 _amount) external onlyRole(GOVERNANCE);
```

**Parameters**

| Name           | Type      | Description                                                        |
| -------------- | --------- | ------------------------------------------------------------------ |
| `_stakedToken` | `address` | Address of the StakedToken contract to return underlying tokens to |
| `_from`        | `address` | Address of the account to transfer funds from                      |
| `_amount`      | `uint256` | Amount of underlying tokens to return                              |

### withdrawFundsRaisedFromAuction

Sends payment tokens raised in auctions from the AuctionModule to the governance treasury

_Only callable by governance_

```solidity
function withdrawFundsRaisedFromAuction(uint256 _amount) external onlyRole(GOVERNANCE);
```

**Parameters**

| Name      | Type      | Description                          |
| --------- | --------- | ------------------------------------ |
| `_amount` | `uint256` | Amount of payment tokens to withdraw |

### setAuctionModule

Sets the address of the AuctionModule contract

_Only callable by governance_

```solidity
function setAuctionModule(IAuctionModule _newAuctionModule) external onlyRole(GOVERNANCE);
```

**Parameters**

| Name                | Type             | Description                           |
| ------------------- | ---------------- | ------------------------------------- |
| `_newAuctionModule` | `IAuctionModule` | Address of the AuctionModule contract |

### setRewardDistributor

Sets the address of the SMRewardDistributor contract

_Only callable by governance_

```solidity
function setRewardDistributor(ISMRewardDistributor _newRewardDistributor) external onlyRole(GOVERNANCE);
```

**Parameters**

| Name                    | Type                   | Description                                 |
| ----------------------- | ---------------------- | ------------------------------------------- |
| `_newRewardDistributor` | `ISMRewardDistributor` | Address of the SMRewardDistributor contract |

### addStakedToken

Adds a new staked token to the SafetyModule's stakedTokens array

_Only callable by governance, reverts if the staked token is already registered_

```solidity
function addStakedToken(IStakedToken _stakedToken) external onlyRole(GOVERNANCE);
```

**Parameters**

| Name           | Type           | Description                     |
| -------------- | -------------- | ------------------------------- |
| `_stakedToken` | `IStakedToken` | Address of the new staked token |

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

### \_returnFunds

```solidity
function _returnFunds(IStakedToken _stakedToken, address _from, uint256 _amount) internal;
```

### \_settleSlashing

```solidity
function _settleSlashing(IStakedToken _stakedToken) internal;
```
