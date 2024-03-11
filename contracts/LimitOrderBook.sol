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
    IClearingHouseViewer public immutable CLEARING_HOUSE_VIEWER;

    uint256 public minTipFee;
    mapping(uint256 => LimitOrder) public limitOrders;
    uint256[] public openOrders;
    uint256 public nextOrderId;

    constructor(IClearingHouse _clearingHouse, IClearingHouseViewer _clearingHouseViewer, uint256 _minTipFee) {
        CLEARING_HOUSE = _clearingHouse;
        CLEARING_HOUSE_VIEWER = _clearingHouseViewer;
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

        LimitOrder memory order = new LimitOrder({
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
        if (msg.sender != limitOrders[orderId].account) {
            revert LimitOrderBook_InvalidSenderNotOrderOwner(msg.sender, limitOrders[orderId].account);
        }
        if (tipFee != limitOrders[orderId].tipFee) {
            if (tipFee > limitOrders[orderId].tipFee) {
                if (msg.value != tipFee - limitOrders[orderId].tipFee) {
                    revert LimitOrderBook_InvalidFeeValue(msg.value, tipFee - limitOrders[orderId].tipFee);
                }
            } else {
                payable(msg.sender).call{value: limitOrders[orderId].tipFee - tipFee}("");
            }
        }
        limitOrders[orderId].limitPrice = limitPrice;
        limitOrders[orderId].amount = amount;
        limitOrders[orderId].expiry = expiry;
        limitOrders[orderId].slippage = slippage;
        limitOrders[orderId].tipFee = tipFee;

        emit OrderChanged(msg.sender, orderId);
    }

    function fillOrder(uint256 orderId) external {
        if (orderId >= nextOrderId) {
            revert LimitOrderBook_InvalidOrderId();
        }
        if (limitOrders[orderId].expiry <= block.timestamp) {
            revert LimitOrderBook_OrderExpired(limitOrders[orderId].expiry);
        }

        // ensure limit order is still valid

        // call executeLimitOrder function on user's smart account

        // remove order from open orders

        // delete order from limitOrders

        // transfer tip fee to caller
    }

    function cancelOrder(uint256 orderId) external {
        if (orderId >= nextOrderId) {
            revert LimitOrderBook_InvalidOrderId();
        }
        if (msg.sender != limitOrders[orderId].account) {
            revert LimitOrderBook_InvalidSenderNotOrderOwner(msg.sender, limitOrders[orderId].account);
        }

        // remove order from open orders

        // delete order from limitOrders

        // transfer tip fee back to order owner
    }

    function closeExpiredOrder(uint256 orderId) external {
        if (orderId >= nextOrderId) {
            revert LimitOrderBook_InvalidOrderId();
        }
        if (limitOrders[orderId].expiry > block.timestamp) {
            revert LimitOrderBook_OrderNotExpired(limitOrders[orderId].expiry);
        }

        // remove order from open orders

        // delete order from limitOrders

        // transfer tip fee to caller
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
