# IncrementLimitOrderModule

[Git Source](https://github.com/Increment-Finance/peripheral-contracts/blob/7b4166bd3bb6b2c678b84df162bcaf7af66b042d/contracts/IncrementLimitOrderModule.sol)

**Inherits:**
[IIncrementLimitOrderModule](/contracts/interfaces/IIncrementLimitOrderModule.sol/interface.IIncrementLimitOrderModule.md), IncreAccessControl, Pausable, ReentrancyGuard

**Author:**
webthethird

Limit order book module for Increment Protocol, allowing users with a Clave smart account to create orders that can be filled conditionally on their behalf by keepers

## State Variables

### CLEARING_HOUSE

ClearingHouse contract for executing orders

```solidity
IClearingHouse public immutable CLEARING_HOUSE;
```

### CLEARING_HOUSE_VIEWER

ClearingHouseViewer contract for computing expected/proposed amounts

```solidity
IClearingHouseViewer public immutable CLEARING_HOUSE_VIEWER;
```

### CLAVE_REGISTRY

ClaveRegistry contract for checking if account is a Clave

```solidity
IClaveRegistry public immutable CLAVE_REGISTRY;
```

### minTipFee

The minimum tip fee to accept per order

```solidity
uint256 public minTipFee;
```

### nextOrderId

The next order id to use

```solidity
uint256 public nextOrderId;
```

### openOrders

Array of order ids for open orders

```solidity
uint256[] public openOrders;
```

### limitOrders

Mapping from order id to order info

```solidity
mapping(uint256 => LimitOrder) public limitOrders;
```

### \_initialized

Mapping from account to whether the module is initialized for the account

_Set by `init` and `disable`, which must be called when adding/removing module to/from account respectively_

```solidity
mapping(address => bool) private _initialized;
```

## Functions

### constructor

```solidity
constructor(
    IClearingHouse clearingHouse,
    IClearingHouseViewer clearingHouseViewer,
    IClaveRegistry claveRegistry,
    uint256 initialMinTipFee
);
```

**Parameters**

| Name                  | Type                   | Description                                                        |
| --------------------- | ---------------------- | ------------------------------------------------------------------ |
| `clearingHouse`       | `IClearingHouse`       | The address of the Increment Protocol ClearingHouse contract       |
| `clearingHouseViewer` | `IClearingHouseViewer` | The address of the Increment Protocol ClearingHouseViewer contract |
| `claveRegistry`       | `IClaveRegistry`       | The address of the ClaveRegistry contract                          |
| `initialMinTipFee`    | `uint256`              | The initial minimum tip fee required per order to pay keepers      |

### createOrder

Creates a new limit order

_The `order.tipFee` in ETH must be sent with the transaction_

```solidity
function createOrder(LimitOrder memory order) external payable nonReentrant whenNotPaused returns (uint256 orderId);
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
) external payable nonReentrant;
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
function fillOrder(uint256 orderId) external nonReentrant whenNotPaused;
```

### cancelOrder

Cancels an existing limit order

_The `tipFee` in ETH is refunded to the order's owner_

```solidity
function cancelOrder(uint256 orderId) external nonReentrant;
```

### closeExpiredOrder

Closes an existing limit order if expired

_The `tipFee` in ETH is paid to the keeper who closes the order_

```solidity
function closeExpiredOrder(uint256 orderId) external nonReentrant;
```

### init

Initialize the module for the calling account

_Module must not be already inited for the account_

```solidity
function init(bytes calldata initData) external override;
```

**Parameters**

| Name       | Type    | Description   |
| ---------- | ------- | ------------- |
| `initData` | `bytes` | Must be empty |

### disable

Disable the module for the calling account

```solidity
function disable() external override;
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
function isReduceOnly(uint256 orderId) public view returns (bool);
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
function isInited(address account) public view returns (bool);
```

**Parameters**

| Name      | Type      | Description          |
| --------- | --------- | -------------------- |
| `account` | `address` | Account to check for |

**Returns**

| Name     | Type   | Description                                    |
| -------- | ------ | ---------------------------------------------- |
| `<none>` | `bool` | True if the account is inited, false otherwise |

### supportsInterface

_Returns true if this contract implements the interface defined by
`interfaceId`. See the corresponding
https://eips.ethereum.org/EIPS/eip-165#how-interfaces-are-identified[EIP section]
to learn more about how these ids are created.
This function call must use less than 30 000 gas._

```solidity
function supportsInterface(bytes4 interfaceId) public view override(AccessControl, IERC165) returns (bool);
```

### setMinTipFee

Updates the minimum tip fee for placing limit orders

_Only callable by governance_

```solidity
function setMinTipFee(uint256 newMinTipFee) external onlyRole(GOVERNANCE);
```

**Parameters**

| Name           | Type      | Description                  |
| -------------- | --------- | ---------------------------- |
| `newMinTipFee` | `uint256` | The new value of `minTipFee` |

### pause

Pauses creating and filling orders

_Only callable by emergency admin_

```solidity
function pause() external override onlyRole(EMERGENCY_ADMIN);
```

### unpause

Unpauses creating and filling orders

_Only callable by emergency admin_

```solidity
function unpause() external override onlyRole(EMERGENCY_ADMIN);
```

### \_executeLimitOrder

```solidity
function _executeLimitOrder(LimitOrder memory order) internal returns (bool, bytes memory);
```

### \_executeMarketOrder

```solidity
function _executeMarketOrder(uint256 marketIdx, uint256 amount, address account, LibPerpetual.Side side)
    internal
    returns (bool success, bytes memory err);
```

### \_getExecuteOrderData

```solidity
function _getExecuteOrderData(LimitOrder memory order) internal view returns (bytes memory);
```

### \_getExecuteOrderData

```solidity
function _getExecuteOrderData(uint256 marketIdx, uint256 amount, address account, LibPerpetual.Side side)
    internal
    view
    returns (bytes memory data);
```

### \_removeOrder

```solidity
function _removeOrder(uint256 orderId) internal;
```

### \_transferTipFee

```solidity
function _transferTipFee(address recipient, uint256 tipFee) internal;
```

### \_isSameSide

```solidity
function _isSameSide(IPerpetual perp, address account, LibPerpetual.Side side) internal view returns (bool);
```

### \_isReduceOnlyValid

```solidity
function _isReduceOnlyValid(uint256 marketIdx, uint256 amount, address account, IPerpetual perp, LibPerpetual.Side side)
    internal
    view
    returns (bool);
```

### \_getMinAmount

```solidity
function _getMinAmount(uint256 marketIdx, uint256 amount, LibPerpetual.Side side) internal view returns (uint256);
```

### \_getMinAmounts

```solidity
function _getMinAmounts(
    uint256 marketIdx,
    uint256 closeProposedAmount,
    uint256 openProposedAmount,
    LibPerpetual.Side side
) internal view returns (uint256 closeMinAmount, uint256 openMinAmount);
```

### \_getCloseProposedAmount

```solidity
function _getCloseProposedAmount(uint256 marketIdx, address account) internal view returns (uint256);
```

### \_changePosition

```solidity
function _changePosition(uint256 marketIdx, uint256 amount, address account, LibPerpetual.Side side)
    internal
    returns (bool, bytes memory);
```

### \_changePosition

```solidity
function _changePosition(uint256 marketIdx, uint256 amount, uint256 minAmount, address account, LibPerpetual.Side side)
    internal
    returns (bool success, bytes memory err);
```

### \_openReversePosition

```solidity
function _openReversePosition(
    uint256 marketIdx,
    uint256 amount,
    uint256 closeProposedAmount,
    address account,
    LibPerpetual.Side side
) internal returns (bool, bytes memory);
```

### \_openReversePosition

```solidity
function _openReversePosition(
    uint256 marketIdx,
    uint256 closeProposedAmount,
    uint256 closeMinAmount,
    uint256 openProposedAmount,
    uint256 openMinAmount,
    address account,
    LibPerpetual.Side side
) internal returns (bool success, bytes memory err);
```
