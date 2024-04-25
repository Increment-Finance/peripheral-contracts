// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.20;

// interfaces
import {IModule} from "clave-contracts/contracts/interfaces/IModule.sol";

// libraries
import {LibPerpetual} from "@increment/lib/LibPerpetual.sol";

interface IIncrementLimitOrderModule is IModule {
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

    /// @notice Emitted when governance updates the minimum required tip for keepers
    /// @param oldMinTip The previous minTipFee amount
    /// @param newMinTip The new minTipFee amount
    event MinTipFeeUpdated(uint256 oldMinTip, uint256 newMinTip);

    /* ****************** */
    /*       Errors       */
    /* ****************** */

    /// @notice Error emitted when the caller of `createOrder` is not `order.account`
    error LimitOrderModule_InvalidAccount();

    /// @notice Error emitted when an invalid zero price is given as input
    error LimitOrderModule_InvalidTargetPrice();

    /// @notice Error emitted when an invalid zero amount is given as input
    error LimitOrderModule_InvalidAmount();

    /// @notice Error emitted when an invalid expiry time is given as input
    error LimitOrderModule_InvalidExpiry();

    /// @notice Error emitted when an invalid market index is given as input
    error LimitOrderModule_InvalidMarketIdx();

    /// @notice Error emitted when an invalid order id is given as input
    error LimitOrderModule_InvalidOrderId();

    /// @notice Error emitted when an invalid slippage percent is given as input
    error LimitOrderModule_InvalidSlippage();

    /// @notice Error emitted when an invalid tip fee is given as input
    error LimitOrderModule_InsufficientTipFee();

    /// @notice Error emitted when the given tip fee does not match msg.value
    /// @param value The actual value sent with the transaction
    /// @param expected The expected value for the tip fee
    error LimitOrderModule_InvalidFeeValue(uint256 value, uint256 expected);

    /// @notice Error emitted when the wrong user tries to change or cancel an order
    /// @param sender The address of the caller
    /// @param owner The address of the order owner
    error LimitOrderModule_InvalidSenderNotOrderOwner(address sender, address owner);

    /// @notice Error emitted when trying to fill an order that is already expired
    /// @param expiry The timestamp when the order expired
    error LimitOrderModule_OrderExpired(uint256 expiry);

    /// @notice Error emitted when trying to close an order that is not expired
    /// @param expiry The timestamp when the order will expire
    error LimitOrderModule_OrderNotExpired(uint256 expiry);

    /// @notice Error emitted when transferring the tip fee fails
    /// @param to The address of the intended recipient
    /// @param amount The amount of ETH to transfer
    error LimitOrderModule_TipFeeTransferFailed(address to, uint256 amount);

    /// @notice Error emitted when trying to create an order from an account that is not a Clave
    /// @param account The address of the account
    error LimitOrderModule_AccountIsNotClave(address account);

    /// @notice Error emitted when trying to create an order from an account that does not support the IIncrementLimitOrderModule module
    /// @param account The address of the account
    error LimitOrderModule_AccountDoesNotSupportLimitOrders(address account);

    /// @notice Error emitted when trying to fill a reduce-only order without an open position
    /// @param account The address of the account
    /// @param marketIdx The market index
    error LimitOrderModule_NoPositionToReduce(address account, uint256 marketIdx);

    /// @notice Error emitted when trying to fill a reduce-only order with the wrong side
    error LimitOrderModule_CannotReducePositionWithSameSideOrder();

    /// @notice Error emitted when trying to fill a reduce-only order would reverse the position
    error LimitOrderModule_ReduceOnlyCannotReversePosition();

    /// @notice Error emitted when trying to fill an order with an invalid price
    /// @param price The current price
    /// @param limitPrice The target price for the order
    /// @param maxSlippage The max slippage percentage for the order
    /// @param side The direction of the order
    error LimitOrderModule_InvalidPriceAtFill(
        uint256 price, uint256 limitPrice, uint256 maxSlippage, LibPerpetual.Side side
    );

    /// @notice Error emitted when trying to fill an order causes a protocol contract to revert
    /// @param reason The error data returned by the protocol contract
    error LimitOrderModule_OrderExecutionReverted(bytes reason);

    /// @notice Error emitted when trying to disable a module that has not been initialized
    error LimitOrderModule_ModuleNotInited();

    /// @notice Error emitted when trying to initialize a module with non-empty `initData`
    error LimitOrderModule_InitDataShouldBeEmpty();

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
    /// @param order The order's info, including:
    ///        account: The trader's account
    ///        side: The side of the order, e.g., LONG or SHORT
    ///        orderType: The type of the order, e.g., LIMIT or STOP
    ///        reduceOnly: Whether the order is reduce only
    ///        marketIdx: The market's index in the clearing house
    ///        targetPrice: The price at which to execute the order, 18 decimals
    ///        amount: The amount in vQuote (if LONG) or vBase (if SHORT) to sell, 18 decimals
    ///        expiry: The timestamp at which the order expires
    ///        slippage: The maximum slippage percent allowed for the order, 18 decimals
    ///        tipFee: The fee paid to the keeper who executes the order in ETH, 18 decimals
    /// @return orderId The order's unique identifier
    function createOrder(LimitOrder memory order) external payable returns (uint256 orderId);

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

    /// @notice Returns whether the order can be filled
    /// @param orderId The order's unique identifier
    /// @return canFill Whether the order can be filled
    function canFillOrder(uint256 orderId) external view returns (bool);

    /// @notice Returns whether the module is inited for the given account
    /// @param account Account to check for
    /// @return True if the account is inited, false otherwise
    function isInited(address account) external view returns (bool);

    /* ****************** */
    /*     Governance     */
    /* ****************** */

    /// @notice Updates the minimum tip fee for placing limit orders
    /// @param newMinTipFee The new value of `minTipFee`
    function setMinTipFee(uint256 newMinTipFee) external;

    /* ******************* */
    /*   Emergency Admin   */
    /* ******************* */

    /// @notice Pauses creating and filling orders
    function pause() external;

    /// @notice Unpauses creating and filling orders
    function unpause() external;
}
