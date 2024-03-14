// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.16;

import {LibPerpetual} from "@increment/lib/LibPerpetual.sol";

interface ILimitOrderBook {
    /* ******************* */
    /*   Data Structures   */
    /* ******************* */

    /// @notice Supported order types
    /// @dev LIMIT uses `marketPrice`, STOP uses `indexPrice`
    enum OrderType {
        LIMIT,
        STOP
    }

    /// @notice Data structure for storing order info
    /// @param account The trader's account
    /// @param side The side of the order, e.g., LONG or SHORT
    /// @param orderType The type of the order, e.g., LIMIT or STOP
    /// @param reduceOnly Whether the order is reduce only
    /// @param marketIdx The market's index in the clearing house
    /// @param targetPrice The price at which to execute the order, 18 decimals
    /// @param amount The amount in vQuote (if LONG) or vBase (if SHORT) to sell, 18 decimals
    /// @param expiry The timestamp at which the order expires
    /// @param slippage The maximum slippage percent allowed for the order, 18 decimals
    /// @param tipFee The fee paid to the keeper who executes the order in ETH, 18 decimals
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

    /* ****************** */
    /*       Events       */
    /* ****************** */

    /// @notice Emitted when a new order is created
    /// @param trader The trader's account
    /// @param orderId The order's unique identifier
    event OrderCreated(address indexed trader, uint256 orderId);

    /// @notice Emitted when an order is filled
    /// @param trader The trader's account
    /// @param orderId The order's unique identifier
    event OrderFilled(address indexed trader, uint256 orderId);

    /// @notice Emitted when an order is changed
    /// @param trader The trader's account
    /// @param orderId The order's unique identifier
    event OrderChanged(address indexed trader, uint256 orderId);

    /// @notice Emitted when an order is cancelled
    /// @param trader The trader's account
    /// @param orderId The order's unique identifier
    event OrderCancelled(address indexed trader, uint256 orderId);

    /// @notice Emitted when an order is closed due to expiry
    /// @param trader The trader's account
    /// @param orderId The order's unique identifier
    event OrderExpired(address indexed trader, uint256 orderId);

    /* ****************** */
    /*       Errors       */
    /* ****************** */

    /// @notice Error emitted when an invalid zero price is given as input
    error LimitOrderBook_InvalidTargetPrice();

    /// @notice Error emitted when an invalid zero amount is given as input
    error LimitOrderBook_InvalidAmount();

    /// @notice Error emitted when an invalid expiry time is given as input
    error LimitOrderBook_InvalidExpiry();

    /// @notice Error emitted when an invalid market index is given as input
    error LimitOrderBook_InvalidMarketIdx();

    /// @notice Error emitted when an invalid order id is given as input
    error LimitOrderBook_InvalidOrderId();

    /// @notice Error emitted when an invalid slippage percent is given as input
    error LimitOrderBook_InvalidSlippage();

    /// @notice Error emitted when an invalid tip fee is given as input
    error LimitOrderBook_InsufficientTipFee();

    /// @notice Error emitted when the given tip fee does not match msg.value
    /// @param value The actual value sent with the transaction
    /// @param expected The expected value for the tip fee
    error LimitOrderBook_InvalidFeeValue(uint256 value, uint256 expected);

    /// @notice Error emitted when the wrong user tries to change or cancel an order
    /// @param sender The address of the caller
    /// @param owner The address of the order owner
    error LimitOrderBook_InvalidSenderNotOrderOwner(address sender, address owner);

    /// @notice Error emitted when trying to fill an order that is already expired
    /// @param expiry The timestamp when the order expired
    error LimitOrderBook_OrderExpired(uint256 expiry);

    /// @notice Error emitted when trying to close an order that is not expired
    /// @param expiry The timestamp when the order will expire
    error LimitOrderBook_OrderNotExpired(uint256 expiry);

    /// @notice Error emitted when transferring the tip fee fails
    /// @param to The address of the intended recipient
    /// @param amount The amount of ETH to transfer
    error LimitOrderBook_TipFeeTransferFailed(address to, uint256 amount);

    /// @notice Error emitted when trying to create an order from an account that does not implement the IIncrementLimitOrderModule interface
    /// @param account The address of the account
    error LimitOrderBook_AccountDoesNotSupportLimitOrders(address account);

    /// @notice Error emitted when trying to fill a reduce-only order without an open position
    /// @param account The address of the account
    /// @param marketIdx The market index
    error LimitOrderBook_NoPositionToReduce(address account, uint256 marketIdx);

    /// @notice Error emitted when trying to fill a reduce-only order with the wrong side
    error LimitOrderBook_CannotReduceLongPositionWithLongOrder();

    /// @notice Error emitted when trying to fill a reduce-only order with the wrong side
    error LimitOrderBook_CannotReduceShortPositionWithShortOrder();

    /// @notice Error emitted when trying to fill an order with an invalid price
    error LimitOrderBook_InvalidPriceAtFill(
        uint256 price, uint256 limitPrice, uint256 maxSlippage, LibPerpetual.Side side
    );

    /* ***************** */
    /*    Public Vars    */
    /* ***************** */

    function minTipFee() external view returns (uint256);

    function nextOrderId() external view returns (uint256);

    function openOrders(uint256 i) external view returns (uint256);

    /* ****************** */
    /*   External Users   */
    /* ****************** */

    /// @notice Creates a new limit order
    /// @dev The `tipFee` in ETH must be sent with the transaction
    /// @param side The side of the order, e.g., LONG or SHORT
    /// @param orderType The type of the order, e.g., LIMIT or STOP
    /// @param reduceOnly Whether the order is reduce only
    /// @param marketIdx The market's index in the clearing house
    /// @param targetPrice The price at which to execute the order, 18 decimals
    /// @param amount The amount in vQuote (if LONG) or vBase (if SHORT) to sell, 18 decimals
    /// @param expiry The timestamp at which the order expires
    /// @param slippage The maximum slippage percent allowed for the order, 18 decimals
    /// @param tipFee The fee paid to the keeper who executes the order in ETH, 18 decimals
    /// @return orderId The order's unique identifier
    function createOrder(
        LibPerpetual.Side side,
        OrderType orderType,
        bool reduceOnly,
        uint256 marketIdx,
        uint256 targetPrice,
        uint256 amount,
        uint256 expiry,
        uint256 slippage,
        uint256 tipFee
    ) external payable returns (uint256 orderId);

    /// @notice Changes an existing limit order
    /// @dev If the `tipFee` is increased, the difference must be sent with the transaction, and if it is decreased, the difference will be refunded
    /// @param orderId The order's unique identifier
    /// @param targetPrice The price at which to execute the order, 18 decimals
    /// @param amount The amount in vQuote (if LONG) or vBase (if SHORT) to sell, 18 decimals
    /// @param expiry The timestamp at which the order expires
    /// @param slippage The maximum slippage percent allowed for the order, 18 decimals
    /// @param tipFee The fee paid to the keeper who executes the order in ETH, 18 decimals
    function changeOrder(
        uint256 orderId,
        uint256 targetPrice,
        uint256 amount,
        uint256 expiry,
        uint256 slippage,
        uint256 tipFee
    ) external payable;

    /// @notice Fills an existing limit order if valid
    /// @dev The `tipFee` in ETH is paid to the keeper who executes the order
    function fillOrder(uint256 orderId) external;

    /// @notice Cancels an existing limit order
    /// @dev The `tipFee` in ETH is refunded to the order's owner
    function cancelOrder(uint256 orderId) external;

    /// @notice Closes an existing limit order if expired
    /// @dev The `tipFee` in ETH is paid to the keeper who closes the order
    function closeExpiredOrder(uint256 orderId) external;

    /* ***************** */
    /*       Views       */
    /* ***************** */

    /// @notice Returns the order's info
    /// @param orderId The order's unique identifier
    /// @return order The order's info
    function getOrder(uint256 orderId) external view returns (LimitOrder memory);

    /// @notice Returns the order's tip fee amount
    /// @param orderId The order's unique identifier
    /// @return tipFee The order's tip fee amount
    function getTipFee(uint256 orderId) external view returns (uint256);

    /* ******************* */
    /*   Emergency Admin   */
    /* ******************* */

    /// @notice Pauses creating and filling orders
    function pause() external;

    /// @notice Unpauses creating and filling orders
    function unpause() external;
}
