// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.16;

// contracts
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";
import {IncreAccessControl} from "@increment/utils/IncreAccessControl.sol";

// interfaces
import {IPerpetual} from "@increment/interfaces/IPerpetual.sol";
import {IClearingHouse} from "@increment/interfaces/IClearingHouse.sol";
import {IClearingHouseViewer} from "@increment/interfaces/IClearingHouseViewer.sol";
import {ILimitOrderBook} from "./interfaces/ILimitOrderBook.sol";
import {IIncrementLimitOrderModule} from "./interfaces/IIncrementLimitOrderModule.sol";

// libraries
import {LibMath} from "@increment/lib/LibMath.sol";
import {LibPerpetual} from "@increment/lib/LibPerpetual.sol";

contract LimitOrderBook is ILimitOrderBook, IncreAccessControl, Pausable {
    using LibMath for int256;
    using LibMath for uint256;

    IClearingHouse public immutable CLEARING_HOUSE;

    uint256 public minTipFee;
    mapping(uint256 => LimitOrder) public limitOrders;
    uint256[] public openOrders;
    uint256 public nextOrderId;

    constructor(IClearingHouse _clearingHouse, uint256 _minTipFee) {
        CLEARING_HOUSE = _clearingHouse;
        minTipFee = _minTipFee;
    }

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
    ) external payable whenNotPaused returns (uint256) {
        if (tipFee < minTipFee) {
            revert LimitOrderBook_InsufficientTipFee();
        }
        if (msg.value != tipFee) {
            revert LimitOrderBook_InvalidFeeValue(msg.value, tipFee);
        }
        if (expiry <= block.timestamp) {
            revert LimitOrderBook_InvalidExpiry();
        }
        if (amount == 0) {
            revert LimitOrderBook_InvalidAmount();
        }
        if (targetPrice == 0) {
            revert LimitOrderBook_InvalidPrice();
        }
        if (slippage > 1e18) {
            revert LimitOrderBook_InvalidSlippage();
        }
        if (CLEARING_HOUSE.perpetuals(marketIdx) == IPerpetual(address(0))) {
            revert LimitOrderBook_InvalidMarketIdx();
        }
        if (!IIncrementLimitOrderModule(msg.sender).supportsInterface(type(IIncrementLimitOrderModule).interfaceId)) {
            revert LimitOrderBook_AccountDoesNotSupportLimitOrders(msg.sender);
        }

        LimitOrder memory order = LimitOrder({
            account: msg.sender,
            side: side,
            orderType: orderType,
            reduceOnly: reduceOnly,
            marketIdx: marketIdx,
            targetPrice: targetPrice,
            amount: amount,
            expiry: expiry,
            slippage: slippage,
            tipFee: tipFee
        });
        uint256 orderId = nextOrderId++;
        limitOrders[orderId] = order;
        openOrders.push(orderId);

        emit OrderCreated(msg.sender, orderId);
        return orderId;
    }

    function changeOrder(
        uint256 orderId,
        uint256 targetPrice,
        uint256 amount,
        uint256 expiry,
        uint256 slippage,
        uint256 tipFee
    ) external payable {
        if (orderId >= nextOrderId) {
            revert LimitOrderBook_InvalidOrderId();
        }
        if (tipFee < minTipFee) {
            revert LimitOrderBook_InsufficientTipFee();
        }
        if (amount == 0) {
            revert LimitOrderBook_InvalidAmount();
        }
        if (targetPrice == 0) {
            revert LimitOrderBook_InvalidPrice();
        }
        if (expiry <= block.timestamp) {
            revert LimitOrderBook_InvalidExpiry();
        }
        if (slippage > 1e18) {
            revert LimitOrderBook_InvalidSlippage();
        }
        LimitOrder memory order = limitOrders[orderId];
        if (msg.sender != order.account) {
            revert LimitOrderBook_InvalidSenderNotOrderOwner(msg.sender, order.account);
        }

        if (targetPrice != order.targetPrice) {
            limitOrders[orderId].targetPrice = targetPrice;
        }
        if (amount != order.amount) {
            limitOrders[orderId].amount = amount;
        }
        if (expiry != order.expiry) {
            limitOrders[orderId].expiry = expiry;
        }
        if (slippage != order.slippage) {
            limitOrders[orderId].slippage = slippage;
        }
        if (tipFee != order.tipFee) {
            uint256 oldTipFee = order.tipFee;
            limitOrders[orderId].tipFee = tipFee;
            if (tipFee > oldTipFee) {
                // Raising tipFee - msg.value must be equal to the difference
                if (msg.value != tipFee - oldTipFee) {
                    revert LimitOrderBook_InvalidFeeValue(msg.value, tipFee - oldTipFee);
                }
            } else {
                // Lowering tipFee - return the difference to the user
                (bool success,) = payable(msg.sender).call{value: oldTipFee - tipFee}("");
                if (!success) {
                    revert LimitOrderBook_TipFeeTransferFailed(msg.sender, oldTipFee - tipFee);
                }
            }
        }

        emit OrderChanged(msg.sender, orderId);
    }

    function fillOrder(uint256 orderId) external whenNotPaused {
        if (orderId >= nextOrderId) {
            revert LimitOrderBook_InvalidOrderId();
        }
        LimitOrder memory order = limitOrders[orderId];
        if (order.expiry <= block.timestamp) {
            revert LimitOrderBook_OrderExpired(order.expiry);
        }

        // ensure limit order is still valid
        IPerpetual perpetual = CLEARING_HOUSE.perpetuals(order.marketIdx);
        if (order.reduceOnly) {
            // reduce-only is only valid if the trader has an open position on the opposite side
            if (!perpetual.isTraderPositionOpen(order.account)) {
                revert LimitOrderBook_NoPositionToReduce(order.account, order.marketIdx);
            }
            LibPerpetual.TraderPosition memory position = perpetual.getTraderPosition(order.account);
            if (order.side == LibPerpetual.Side.Long) {
                if (position.positionSize > 0) {
                    revert LimitOrderBook_CannotReduceLongPositionWithLongOrder();
                }
            } else {
                if (position.positionSize < 0) {
                    revert LimitOrderBook_CannotReduceShortPositionWithShortOrder();
                }
            }
        }
        uint256 targetPrice = order.targetPrice;
        // for limit orders, check the market price, and for stop orders, check the index price
        uint256 price =
            order.orderType == OrderType.LIMIT ? perpetual.marketPrice() : perpetual.indexPrice().toUint256();
        if (order.side == LibPerpetual.Side.Long) {
            // for long orders, price must be less than or equal to the target price + slippage
            if (price > targetPrice.wadMul(1e18 + order.slippage)) {
                revert LimitOrderBook_InvalidPriceAtFill(price, targetPrice, order.slippage, order.side);
            }
        } else {
            // for short orders, price must be greater than or equal to the target price - slippage
            if (price < targetPrice.wadMul(1e18 - order.slippage)) {
                revert LimitOrderBook_InvalidPriceAtFill(price, targetPrice, order.slippage, order.side);
            }
        }

        // remove order from open orders
        uint256 numOrders = openOrders.length;
        for (uint256 i; i < numOrders;) {
            if (openOrders[i] == orderId) {
                openOrders[i] = openOrders[numOrders - 1];
                openOrders.pop();
                break;
            }
            unchecked {
                ++i;
            }
        }
        // delete order from limitOrders
        delete limitOrders[orderId];

        // call executeLimitOrder function on user's smart account
        IIncrementLimitOrderModule(order.account).executeLimitOrder(order);

        // transfer tip fee to caller
        (bool success,) = payable(msg.sender).call{value: order.tipFee}("");
        if (!success) {
            revert LimitOrderBook_TipFeeTransferFailed(msg.sender, order.tipFee);
        }

        emit OrderFilled(order.account, orderId);
    }

    function cancelOrder(uint256 orderId) external {
        if (orderId >= nextOrderId) {
            revert LimitOrderBook_InvalidOrderId();
        }
        if (msg.sender != limitOrders[orderId].account) {
            revert LimitOrderBook_InvalidSenderNotOrderOwner(msg.sender, limitOrders[orderId].account);
        }

        // remove order from open orders
        uint256 numOrders = openOrders.length;
        for (uint256 i; i < numOrders;) {
            if (openOrders[i] == orderId) {
                openOrders[i] = openOrders[numOrders - 1];
                openOrders.pop();
                break;
            }
            unchecked {
                ++i;
            }
        }
        // delete order from limitOrders
        uint256 tipFee = limitOrders[orderId].tipFee;
        delete limitOrders[orderId];

        // transfer tip fee back to order owner
        (bool success,) = payable(msg.sender).call{value: tipFee}("");
        if (!success) {
            revert LimitOrderBook_TipFeeTransferFailed(msg.sender, tipFee);
        }

        emit OrderCancelled(msg.sender, orderId);
    }

    function closeExpiredOrder(uint256 orderId) external {
        if (orderId >= nextOrderId) {
            revert LimitOrderBook_InvalidOrderId();
        }
        if (limitOrders[orderId].expiry > block.timestamp) {
            revert LimitOrderBook_OrderNotExpired(limitOrders[orderId].expiry);
        }

        // remove order from open orders
        uint256 numOrders = openOrders.length;
        for (uint256 i; i < numOrders;) {
            if (openOrders[i] == orderId) {
                openOrders[i] = openOrders[numOrders - 1];
                openOrders.pop();
                break;
            }
            unchecked {
                ++i;
            }
        }
        // delete order from limitOrders
        address account = limitOrders[orderId].account;
        uint256 tipFee = limitOrders[orderId].tipFee;
        delete limitOrders[orderId];

        // transfer tip fee to caller
        (bool success,) = payable(msg.sender).call{value: tipFee}("");
        if (!success) {
            revert LimitOrderBook_TipFeeTransferFailed(msg.sender, tipFee);
        }

        emit OrderExpired(account, orderId);
    }

    function getOrder(uint256 orderId) external view returns (LimitOrder memory) {
        if (orderId >= nextOrderId) {
            revert LimitOrderBook_InvalidOrderId();
        }
        return limitOrders[orderId];
    }

    function getTipFee(uint256 orderId) external view returns (uint256) {
        if (orderId >= nextOrderId) {
            revert LimitOrderBook_InvalidOrderId();
        }
        return limitOrders[orderId].tipFee;
    }

    function pause() external override onlyRole(EMERGENCY_ADMIN) {
        _pause();
    }

    function unpause() external override onlyRole(EMERGENCY_ADMIN) {
        _unpause();
    }
}
