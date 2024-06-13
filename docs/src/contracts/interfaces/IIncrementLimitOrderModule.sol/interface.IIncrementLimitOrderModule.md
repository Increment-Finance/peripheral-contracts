# IIncrementLimitOrderModule

[Git Source](https://github.com/Increment-Finance/peripheral-contracts/blob/7b4166bd3bb6b2c678b84df162bcaf7af66b042d/contracts/interfaces/IIncrementLimitOrderModule.sol)

**Inherits:**
IModule

**Author:**
webthethird

Interface for the Increment x Clave Limit Order Module

## Functions

### minTipFee

```solidity
function minTipFee() external view returns (uint256);
```

### nextOrderId

```solidity
function nextOrderId() external view returns (uint256);
```

### openOrders

```solidity
function openOrders(uint256 i) external view returns (uint256);
```

### createOrder

Creates a new limit order

_The `order.tipFee` in ETH must be sent with the transaction_

```solidity
function createOrder(LimitOrder memory order) external payable returns (uint256 orderId);
```

**Parameters**

| Name    | Type         | Description      |
| ------- | ------------ | ---------------- |
| `order` | `LimitOrder` | The order's info |

**Returns**

| Name      | Type      | Description                   |
| --------- | --------- | ----------------------------- |
| `orderId` | `uint256` | The order's unique identifier |

### changeOrder

Changes an existing limit order

_If the `tipFee` is increased, the difference must be sent with the transaction, and if it is decreased, the difference will be refunded_

```solidity
function changeOrder(
    uint256 orderId,
    uint256 targetPrice,
    uint256 amount,
    uint256 expiry,
    uint256 slippage,
    uint256 tipFee
) external payable;
```

**Parameters**

| Name          | Type      | Description                                                             |
| ------------- | --------- | ----------------------------------------------------------------------- |
| `orderId`     | `uint256` | The order's unique identifier                                           |
| `targetPrice` | `uint256` | The price at which to execute the order, 18 decimals                    |
| `amount`      | `uint256` | The amount in vQuote (if LONG) or vBase (if SHORT) to sell, 18 decimals |
| `expiry`      | `uint256` | The timestamp at which the order expires                                |
| `slippage`    | `uint256` | The maximum slippage percent allowed for the order, 18 decimals         |
| `tipFee`      | `uint256` | The fee paid to the keeper who executes the order in ETH, 18 decimals   |

### fillOrder

Fills an existing limit order if valid

_The `tipFee` in ETH is paid to the keeper who executes the order_

```solidity
function fillOrder(uint256 orderId) external;
```

### cancelOrder

Cancels an existing limit order

_The `tipFee` in ETH is refunded to the order's owner_

```solidity
function cancelOrder(uint256 orderId) external;
```

### closeExpiredOrder

Closes an existing limit order if expired

_The `tipFee` in ETH is paid to the keeper who closes the order_

```solidity
function closeExpiredOrder(uint256 orderId) external;
```

### getOpenOrderIds

Returns a list of order IDs for all open orders

```solidity
function getOpenOrderIds() external view returns (uint256[] memory);
```

**Returns**

| Name     | Type        | Description        |
| -------- | ----------- | ------------------ |
| `<none>` | `uint256[]` | Array of order IDs |

### getOpenOrders

Returns a list of all open orders

```solidity
function getOpenOrders() external view returns (LimitOrder[] memory);
```

**Returns**

| Name     | Type           | Description                 |
| -------- | -------------- | --------------------------- |
| `<none>` | `LimitOrder[]` | Array of LimitOrder structs |

### getOrder

Returns the order's info

```solidity
function getOrder(uint256 orderId) external view returns (LimitOrder memory);
```

**Parameters**

| Name      | Type      | Description                   |
| --------- | --------- | ----------------------------- |
| `orderId` | `uint256` | The order's unique identifier |

**Returns**

| Name     | Type         | Description            |
| -------- | ------------ | ---------------------- |
| `<none>` | `LimitOrder` | order The order's info |

### getTipFee

Returns the order's tip fee amount

```solidity
function getTipFee(uint256 orderId) external view returns (uint256);
```

**Parameters**

| Name      | Type      | Description                   |
| --------- | --------- | ----------------------------- |
| `orderId` | `uint256` | The order's unique identifier |

**Returns**

| Name     | Type      | Description                       |
| -------- | --------- | --------------------------------- |
| `<none>` | `uint256` | tipFee The order's tip fee amount |

### isTargetPriceMet

Returns whether the target price is met for the given order, including slippage

```solidity
function isTargetPriceMet(uint256 orderId) external view returns (bool);
```

**Parameters**

| Name      | Type      | Description                   |
| --------- | --------- | ----------------------------- |
| `orderId` | `uint256` | The order's unique identifier |

**Returns**

| Name     | Type   | Description                                                                     |
| -------- | ------ | ------------------------------------------------------------------------------- |
| `<none>` | `bool` | True if the target price and slippage conditions are satisfied, false otherwise |

### isReduceOnly

Returns whether the given order is reduce-only

```solidity
function isReduceOnly(uint256 orderId) external view returns (bool);
```

**Parameters**

| Name      | Type      | Description                   |
| --------- | --------- | ----------------------------- |
| `orderId` | `uint256` | The order's unique identifier |

**Returns**

| Name     | Type   | Description                                                                            |
| -------- | ------ | -------------------------------------------------------------------------------------- |
| `<none>` | `bool` | True if order.reduceOnly is true or order.orderType is OrderType.STOP, false otherwise |

### isReduceOnlyValid

Returns whether the given order meets the reduce-only conditions

_Reverts if the order is not reduce-only_

```solidity
function isReduceOnlyValid(uint256 orderId) external view returns (bool);
```

**Parameters**

| Name      | Type      | Description                   |
| --------- | --------- | ----------------------------- |
| `orderId` | `uint256` | The order's unique identifier |

**Returns**

| Name     | Type   | Description                                                 |
| -------- | ------ | ----------------------------------------------------------- |
| `<none>` | `bool` | True if the order is valid for reduce-only, false otherwise |

### isOrderExpired

Returns whether the given order is expired

```solidity
function isOrderExpired(uint256 orderId) external view returns (bool);
```

**Parameters**

| Name      | Type      | Description                   |
| --------- | --------- | ----------------------------- |
| `orderId` | `uint256` | The order's unique identifier |

**Returns**

| Name     | Type   | Description                                   |
| -------- | ------ | --------------------------------------------- |
| `<none>` | `bool` | True if the order is expired, false otherwise |

### isInited

Returns whether the module is inited for the given account

```solidity
function isInited(address account) external view returns (bool);
```

**Parameters**

| Name      | Type      | Description          |
| --------- | --------- | -------------------- |
| `account` | `address` | Account to check for |

**Returns**

| Name     | Type   | Description                                    |
| -------- | ------ | ---------------------------------------------- |
| `<none>` | `bool` | True if the account is inited, false otherwise |

### setMinTipFee

Updates the minimum tip fee for placing limit orders

```solidity
function setMinTipFee(uint256 newMinTipFee) external;
```

**Parameters**

| Name           | Type      | Description                  |
| -------------- | --------- | ---------------------------- |
| `newMinTipFee` | `uint256` | The new value of `minTipFee` |

### pause

Pauses creating and filling orders

```solidity
function pause() external;
```

### unpause

Unpauses creating and filling orders

```solidity
function unpause() external;
```

## Events

### OrderCreated

Emitted when a new order is created

```solidity
event OrderCreated(address indexed trader, uint256 orderId);
```

**Parameters**

| Name      | Type      | Description                   |
| --------- | --------- | ----------------------------- |
| `trader`  | `address` | The trader's account          |
| `orderId` | `uint256` | The order's unique identifier |

### OrderFilled

Emitted when an order is filled

```solidity
event OrderFilled(address indexed trader, address indexed keeper, uint256 orderId);
```

**Parameters**

| Name      | Type      | Description                   |
| --------- | --------- | ----------------------------- |
| `trader`  | `address` | The trader's account          |
| `keeper`  | `address` | The keeper's account          |
| `orderId` | `uint256` | The order's unique identifier |

### OrderChanged

Emitted when an order is changed

```solidity
event OrderChanged(address indexed trader, uint256 orderId);
```

**Parameters**

| Name      | Type      | Description                   |
| --------- | --------- | ----------------------------- |
| `trader`  | `address` | The trader's account          |
| `orderId` | `uint256` | The order's unique identifier |

### OrderCancelled

Emitted when an order is cancelled

```solidity
event OrderCancelled(address indexed trader, uint256 orderId);
```

**Parameters**

| Name      | Type      | Description                   |
| --------- | --------- | ----------------------------- |
| `trader`  | `address` | The trader's account          |
| `orderId` | `uint256` | The order's unique identifier |

### OrderExpired

Emitted when an order is closed due to expiry

```solidity
event OrderExpired(address indexed trader, uint256 orderId);
```

**Parameters**

| Name      | Type      | Description                   |
| --------- | --------- | ----------------------------- |
| `trader`  | `address` | The trader's account          |
| `orderId` | `uint256` | The order's unique identifier |

### MinTipFeeUpdated

Emitted when governance updates the minimum required tip for keepers

```solidity
event MinTipFeeUpdated(uint256 oldMinTip, uint256 newMinTip);
```

**Parameters**

| Name        | Type      | Description                   |
| ----------- | --------- | ----------------------------- |
| `oldMinTip` | `uint256` | The previous minTipFee amount |
| `newMinTip` | `uint256` | The new minTipFee amount      |

## Errors

### LimitOrderModule_InvalidAccount

Error emitted when the caller of `createOrder` is not `order.account`

```solidity
error LimitOrderModule_InvalidAccount();
```

### LimitOrderModule_InvalidTargetPrice

Error emitted when an invalid zero price is given as input

```solidity
error LimitOrderModule_InvalidTargetPrice();
```

### LimitOrderModule_InvalidAmount

Error emitted when an invalid zero amount is given as input

```solidity
error LimitOrderModule_InvalidAmount();
```

### LimitOrderModule_InvalidExpiry

Error emitted when an invalid expiry time is given as input

```solidity
error LimitOrderModule_InvalidExpiry();
```

### LimitOrderModule_InvalidMarketIdx

Error emitted when an invalid market index is given as input

```solidity
error LimitOrderModule_InvalidMarketIdx();
```

### LimitOrderModule_InvalidOrderId

Error emitted when an invalid order id is given as input

```solidity
error LimitOrderModule_InvalidOrderId();
```

### LimitOrderModule_InvalidSlippage

Error emitted when an invalid slippage percent is given as input

```solidity
error LimitOrderModule_InvalidSlippage();
```

### LimitOrderModule_InsufficientTipFee

Error emitted when an invalid tip fee is given as input

```solidity
error LimitOrderModule_InsufficientTipFee();
```

### LimitOrderModule_InvalidFeeValue

Error emitted when the given tip fee does not match msg.value

```solidity
error LimitOrderModule_InvalidFeeValue(uint256 value, uint256 expected);
```

**Parameters**

| Name       | Type      | Description                                |
| ---------- | --------- | ------------------------------------------ |
| `value`    | `uint256` | The actual value sent with the transaction |
| `expected` | `uint256` | The expected value for the tip fee         |

### LimitOrderModule_InvalidSenderNotOrderOwner

Error emitted when the wrong user tries to change or cancel an order

```solidity
error LimitOrderModule_InvalidSenderNotOrderOwner(address sender, address owner);
```

**Parameters**

| Name     | Type      | Description                    |
| -------- | --------- | ------------------------------ |
| `sender` | `address` | The address of the caller      |
| `owner`  | `address` | The address of the order owner |

### LimitOrderModule_OrderExpired

Error emitted when trying to fill an order that is already expired

```solidity
error LimitOrderModule_OrderExpired(uint256 expiry);
```

**Parameters**

| Name     | Type      | Description                          |
| -------- | --------- | ------------------------------------ |
| `expiry` | `uint256` | The timestamp when the order expired |

### LimitOrderModule_OrderNotExpired

Error emitted when trying to close an order that is not expired

```solidity
error LimitOrderModule_OrderNotExpired(uint256 expiry);
```

**Parameters**

| Name     | Type      | Description                              |
| -------- | --------- | ---------------------------------------- |
| `expiry` | `uint256` | The timestamp when the order will expire |

### LimitOrderModule_TipFeeTransferFailed

Error emitted when transferring the tip fee fails

```solidity
error LimitOrderModule_TipFeeTransferFailed(address to, uint256 amount);
```

**Parameters**

| Name     | Type      | Description                           |
| -------- | --------- | ------------------------------------- |
| `to`     | `address` | The address of the intended recipient |
| `amount` | `uint256` | The amount of ETH to transfer         |

### LimitOrderModule_AccountIsNotClave

Error emitted when trying to create an order from an account that is not a Clave

```solidity
error LimitOrderModule_AccountIsNotClave(address account);
```

**Parameters**

| Name      | Type      | Description                |
| --------- | --------- | -------------------------- |
| `account` | `address` | The address of the account |

### LimitOrderModule_AccountDoesNotSupportLimitOrders

Error emitted when trying to create an order from an account that does not support the IIncrementLimitOrderModule module

```solidity
error LimitOrderModule_AccountDoesNotSupportLimitOrders(address account);
```

**Parameters**

| Name      | Type      | Description                |
| --------- | --------- | -------------------------- |
| `account` | `address` | The address of the account |

### LimitOrderModule_NoPositionToReduce

Error emitted when trying to fill a reduce-only order without an open position

```solidity
error LimitOrderModule_NoPositionToReduce(address account, uint256 marketIdx);
```

**Parameters**

| Name        | Type      | Description                |
| ----------- | --------- | -------------------------- |
| `account`   | `address` | The address of the account |
| `marketIdx` | `uint256` | The market index           |

### LimitOrderModule_CannotReducePositionWithSameSideOrder

Error emitted when trying to fill a reduce-only order with the wrong side

```solidity
error LimitOrderModule_CannotReducePositionWithSameSideOrder();
```

### LimitOrderModule_ReduceOnlyCannotReversePosition

Error emitted when trying to fill a reduce-only order would reverse the position

```solidity
error LimitOrderModule_ReduceOnlyCannotReversePosition();
```

### LimitOrderModule_InvalidPriceAtFill

Error emitted when trying to fill an order with an invalid price

```solidity
error LimitOrderModule_InvalidPriceAtFill(
    uint256 price, uint256 limitPrice, uint256 maxSlippage, LibPerpetual.Side side
);
```

**Parameters**

| Name          | Type                | Description                               |
| ------------- | ------------------- | ----------------------------------------- |
| `price`       | `uint256`           | The current price                         |
| `limitPrice`  | `uint256`           | The target price for the order            |
| `maxSlippage` | `uint256`           | The max slippage percentage for the order |
| `side`        | `LibPerpetual.Side` | The direction of the order                |

### LimitOrderModule_OrderExecutionReverted

Error emitted when trying to fill an order causes a protocol contract to revert

```solidity
error LimitOrderModule_OrderExecutionReverted(bytes reason);
```

**Parameters**

| Name     | Type    | Description                                      |
| -------- | ------- | ------------------------------------------------ |
| `reason` | `bytes` | The error data returned by the protocol contract |

### LimitOrderModule_ModuleNotInited

Error emitted when trying to disable a module that has not been initialized

```solidity
error LimitOrderModule_ModuleNotInited();
```

### LimitOrderModule_InitDataShouldBeEmpty

Error emitted when trying to initialize a module with non-empty `initData`

```solidity
error LimitOrderModule_InitDataShouldBeEmpty();
```

## Structs

### LimitOrder

Data structure for storing order info

```solidity
struct LimitOrder {
    address account;
    LibPerpetual.Side side;
    OrderType orderType;
    bool reduceOnly;
    uint256 marketIdx;
    uint256 targetPrice;
    uint256 amount;
    uint256 expiry;
    uint256 slippage;
    uint256 tipFee;
}
```

**Properties**

| Name          | Type                | Description                                                             |
| ------------- | ------------------- | ----------------------------------------------------------------------- |
| `account`     | `address`           | The trader's account                                                    |
| `side`        | `LibPerpetual.Side` | The side of the order, e.g., LONG or SHORT                              |
| `orderType`   | `OrderType`         | The type of the order, e.g., LIMIT or STOP                              |
| `reduceOnly`  | `bool`              | Whether the order is reduce only                                        |
| `marketIdx`   | `uint256`           | The market's index in the clearing house                                |
| `targetPrice` | `uint256`           | The price at which to execute the order, 18 decimals                    |
| `amount`      | `uint256`           | The amount in vQuote (if LONG) or vBase (if SHORT) to sell, 18 decimals |
| `expiry`      | `uint256`           | The timestamp at which the order expires                                |
| `slippage`    | `uint256`           | The maximum slippage percent allowed for the order, 18 decimals         |
| `tipFee`      | `uint256`           | The fee paid to the keeper who executes the order in ETH, 18 decimals   |

## Enums

### OrderType

Supported order types

_LIMIT uses `marketPrice`, STOP uses `indexPrice`_

```solidity
enum OrderType {
    LIMIT,
    STOP
}
```
