// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.16;

import {LibPerpetual} from "@increment/lib/LibPerpetual.sol";

interface ILimitOrderBook {
    enum OrderType {
        LIMIT,
        STOP
    }

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

    event OrderCreated(address indexed trader, uint256 orderId);
    event OrderFilled(address indexed trader, uint256 orderId);
    event OrderChanged(address indexed trader, uint256 orderId);
    event OrderCancelled(address indexed trader, uint256 orderId);
    event OrderExpired(address indexed trader, uint256 orderId);

    error LimitOrderBook_InvalidPrice();
    error LimitOrderBook_InvalidAmount();
    error LimitOrderBook_InvalidExpiry();
    error LimitOrderBook_InvalidMarketIdx();
    error LimitOrderBook_InvalidOrderId();
    error LimitOrderBook_InvalidSlippage();
    error LimitOrderBook_InsufficientTipFee();
    error LimitOrderBook_InvalidFeeValue(uint256 value, uint256 expected);
    error LimitOrderBook_InvalidSenderNotOrderOwner(address sender, address owner);
    error LimitOrderBook_OrderExpired(uint256 expiry);
    error LimitOrderBook_OrderNotExpired(uint256 expiry);
    error LimitOrderBook_TipFeeTransferFailed(address to, uint256 amount);
    error LimitOrderBook_AccountDoesNotSupportLimitOrders(address account);
    error LimitOrderBook_NoPositionToReduce(address account, uint256 marketIdx);
    error LimitOrderBook_CannotReduceLongPositionWithLongOrder();
    error LimitOrderBook_CannotReduceShortPositionWithShortOrder();
    error LimitOrderBook_InvalidPriceAtFill(
        uint256 price, uint256 limitPrice, uint256 maxSlippage, LibPerpetual.Side side
    );

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
    ) external payable returns (uint256);

    function changeOrder(
        uint256 orderId,
        uint256 targetPrice,
        uint256 amount,
        uint256 expiry,
        uint256 slippage,
        uint256 tipFee
    ) external payable;

    function fillOrder(uint256 orderId) external;

    function cancelOrder(uint256 orderId) external;

    function closeExpiredOrder(uint256 orderId) external;

    function getOrder(uint256 orderId) external view returns (LimitOrder memory);

    function getTipFee(uint256 orderId) external view returns (uint256);

    function pause() external;

    function unpause() external;
}
