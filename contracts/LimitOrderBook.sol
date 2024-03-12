// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.16;

// contracts
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IncreAccessControl} from "@increment/utils/IncreAccessControl.sol";

// interfaces
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IPerpetual} from "@increment/interfaces/IPerpetual.sol";
import {IClearingHouse} from "@increment/interfaces/IClearingHouse.sol";
import {IClearingHouseViewer} from "@increment/interfaces/IClearingHouseViewer.sol";
import {ILimitOrderBook} from "./interfaces/ILimitOrderBook.sol";
import {IIncrementLimitOrderModule} from "./interfaces/IIncrementLimitOrderModule.sol";

// libraries
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {LibMath} from "@increment/lib/LibMath.sol";
import {LibPerpetual} from "@increment/lib/LibPerpetual.sol";
import {LibReserve} from "@increment/lib/LibReserve.sol";

contract LimitOrderBook is ILimitOrderBook, IncreAccessControl, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;
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
        uint256 marketIdx,
        uint256 limitPrice,
        uint256 amount,
        uint256 expiry,
        uint256 slippage,
        uint256 tipFee
    ) external payable returns (uint256) {
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
        if (limitPrice == 0) {
            revert LimitOrderBook_InvalidPrice();
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
            marketIdx: marketIdx,
            limitPrice: limitPrice,
            amount: amount,
            expiry: expiry,
            slippage: slippage,
            tipFee: tipFee
        });
        uint256 orderId = nextOrderId;
        nextOrderId += 1;
        limitOrders[orderId] = order;
        openOrders.push(orderId);

        emit OrderCreated(msg.sender, orderId);
        return orderId;
    }

    function changeOrder(
        uint256 orderId,
        uint256 limitPrice,
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
        if (limitPrice == 0) {
            revert LimitOrderBook_InvalidPrice();
        }
        if (expiry <= block.timestamp) {
            revert LimitOrderBook_InvalidExpiry();
        }
        LimitOrder memory order = limitOrders[orderId];
        if (msg.sender != order.account) {
            revert LimitOrderBook_InvalidSenderNotOrderOwner(msg.sender, order.account);
        }

        if (limitPrice != order.limitPrice) {
            limitOrders[orderId].limitPrice = limitPrice;
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

    function fillOrder(uint256 orderId) external {
        if (orderId >= nextOrderId) {
            revert LimitOrderBook_InvalidOrderId();
        }
        LimitOrder memory order = limitOrders[orderId];
        if (order.expiry <= block.timestamp) {
            revert LimitOrderBook_OrderExpired(order.expiry);
        }

        // ensure limit order is still valid

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
}
