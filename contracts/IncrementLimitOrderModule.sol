// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.20;

// contracts
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";
import {IncreAccessControl, AccessControl} from "@increment/utils/IncreAccessControl.sol";

// interfaces
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IClaveRegistry} from "clave-contracts/contracts/interfaces/IClaveRegistry.sol";
import {IClaveAccount} from "clave-contracts/contracts/interfaces/IClave.sol";
import {IModuleManager} from "clave-contracts/contracts/interfaces/IModuleManager.sol";
import {IClearingHouseViewer} from "@increment/interfaces/IClearingHouseViewer.sol";
import {IClearingHouse} from "@increment/interfaces/IClearingHouse.sol";
import {IPerpetual} from "@increment/interfaces/IPerpetual.sol";
import {IIncrementLimitOrderModule, IModule} from "./interfaces/IIncrementLimitOrderModule.sol";

// libraries
import {Errors} from "clave-contracts/contracts/libraries/Errors.sol";
import {LibMath} from "@increment/lib/LibMath.sol";
import {LibPerpetual} from "@increment/lib/LibPerpetual.sol";

contract IncrementLimitOrderModule is IIncrementLimitOrderModule, IncreAccessControl, Pausable {
    using LibMath for int256;
    using LibMath for uint256;

    IClearingHouse public immutable CLEARING_HOUSE;
    IClearingHouseViewer public immutable CLEARING_HOUSE_VIEWER;
    IClaveRegistry public immutable CLAVE_REGISTRY;

    /// @notice The minimum tip fee to accept per order
    uint256 public minTipFee;

    /// @notice The next order id to use
    uint256 public nextOrderId;

    /// @notice Array of order ids for open orders
    uint256[] public openOrders;

    /// @notice Mapping from order id to order info
    mapping(uint256 => LimitOrder) public limitOrders;

    mapping(address => bool) private _initialized;

    constructor(
        IClearingHouse clearingHouse,
        IClearingHouseViewer clearingHouseViewer,
        IClaveRegistry _claveRegistry,
        uint256 _minTipFee
    ) {
        CLEARING_HOUSE = clearingHouse;
        CLEARING_HOUSE_VIEWER = clearingHouseViewer;
        CLAVE_REGISTRY = _claveRegistry;
        minTipFee = _minTipFee;
    }

    /* ****************** */
    /*   External Users   */
    /* ****************** */

    /// @inheritdoc IIncrementLimitOrderModule
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
    ) external payable whenNotPaused returns (uint256 orderId) {
        if (tipFee < minTipFee) {
            revert LimitOrderModule_InsufficientTipFee();
        }
        if (msg.value != tipFee) {
            revert LimitOrderModule_InvalidFeeValue(msg.value, tipFee);
        }
        if (expiry <= block.timestamp) {
            revert LimitOrderModule_InvalidExpiry();
        }
        if (amount == 0) {
            revert LimitOrderModule_InvalidAmount();
        }
        if (targetPrice == 0) {
            revert LimitOrderModule_InvalidTargetPrice();
        }
        if (slippage > 1e18) {
            revert LimitOrderModule_InvalidSlippage();
        }
        if (CLEARING_HOUSE.perpetuals(marketIdx) == IPerpetual(address(0))) {
            revert LimitOrderModule_InvalidMarketIdx();
        }
        if (!CLAVE_REGISTRY.isClave(msg.sender)) {
            revert LimitOrderModule_AccountIsNotClave(msg.sender);
        }
        if (!IModuleManager(msg.sender).isModule(address(this))) {
            revert LimitOrderModule_AccountDoesNotSupportLimitOrders(msg.sender);
        }

        // check if the order can be executed immediately as a market trade
        IPerpetual perpetual = CLEARING_HOUSE.perpetuals(marketIdx);
        uint256 price = orderType == OrderType.LIMIT ? perpetual.marketPrice() : perpetual.indexPrice().toUint256();
        if (side == LibPerpetual.Side.Long) {
            if (price <= targetPrice) {
                _executeMarketOrder(marketIdx, amount, msg.sender, side);
                return type(uint256).max;
            }
        } else {
            if (price >= targetPrice) {
                _executeMarketOrder(marketIdx, amount, msg.sender, side);
                return type(uint256).max;
            }
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
        orderId = nextOrderId++;
        limitOrders[orderId] = order;
        openOrders.push(orderId);

        emit OrderCreated(msg.sender, orderId);
        return orderId;
    }

    /// @inheritdoc IIncrementLimitOrderModule
    function changeOrder(
        uint256 orderId,
        uint256 targetPrice,
        uint256 amount,
        uint256 expiry,
        uint256 slippage,
        uint256 tipFee
    ) external payable {
        if (orderId >= nextOrderId) {
            revert LimitOrderModule_InvalidOrderId();
        }
        if (tipFee < minTipFee) {
            revert LimitOrderModule_InsufficientTipFee();
        }
        if (amount == 0) {
            revert LimitOrderModule_InvalidAmount();
        }
        if (targetPrice == 0) {
            revert LimitOrderModule_InvalidTargetPrice();
        }
        if (expiry <= block.timestamp) {
            revert LimitOrderModule_InvalidExpiry();
        }
        if (slippage > 1e18) {
            revert LimitOrderModule_InvalidSlippage();
        }
        LimitOrder memory order = limitOrders[orderId];
        if (msg.sender != order.account) {
            revert LimitOrderModule_InvalidSenderNotOrderOwner(msg.sender, order.account);
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
                    revert LimitOrderModule_InvalidFeeValue(msg.value, tipFee - oldTipFee);
                }
            } else {
                // Lowering tipFee - return the difference to the user
                (bool success,) = payable(msg.sender).call{value: oldTipFee - tipFee}("");
                if (!success) {
                    revert LimitOrderModule_TipFeeTransferFailed(msg.sender, oldTipFee - tipFee);
                }
            }
        }

        emit OrderChanged(msg.sender, orderId);
    }

    /// @inheritdoc IIncrementLimitOrderModule
    function fillOrder(uint256 orderId) external whenNotPaused {
        if (orderId >= nextOrderId) {
            revert LimitOrderModule_InvalidOrderId();
        }
        LimitOrder memory order = limitOrders[orderId];
        if (order.expiry <= block.timestamp) {
            revert LimitOrderModule_OrderExpired(order.expiry);
        }

        // ensure limit order is still valid
        IPerpetual perpetual = CLEARING_HOUSE.perpetuals(order.marketIdx);
        if (order.reduceOnly || order.orderType == OrderType.STOP) {
            // reduce-only is only valid if the trader has an open position on the opposite side
            if (!perpetual.isTraderPositionOpen(order.account)) {
                revert LimitOrderModule_NoPositionToReduce(order.account, order.marketIdx);
            }
            LibPerpetual.TraderPosition memory position = perpetual.getTraderPosition(order.account);
            if (order.side == LibPerpetual.Side.Long) {
                if (position.positionSize > 0) {
                    revert LimitOrderModule_CannotReduceLongPositionWithLongOrder();
                }
            } else {
                if (position.positionSize < 0) {
                    revert LimitOrderModule_CannotReduceShortPositionWithShortOrder();
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
                revert LimitOrderModule_InvalidPriceAtFill(price, targetPrice, order.slippage, order.side);
            }
        } else {
            // for short orders, price must be greater than or equal to the target price - slippage
            if (price < targetPrice.wadMul(1e18 - order.slippage)) {
                revert LimitOrderModule_InvalidPriceAtFill(price, targetPrice, order.slippage, order.side);
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

        // call executeLimitOrder function on the IncrementLimitOrderModule
        _executeLimitOrder(order);

        // transfer tip fee to caller
        (bool success,) = payable(msg.sender).call{value: order.tipFee}("");
        if (!success) {
            revert LimitOrderModule_TipFeeTransferFailed(msg.sender, order.tipFee);
        }

        emit OrderFilled(order.account, orderId);
    }

    /// @inheritdoc IIncrementLimitOrderModule
    function cancelOrder(uint256 orderId) external {
        if (orderId >= nextOrderId) {
            revert LimitOrderModule_InvalidOrderId();
        }
        if (msg.sender != limitOrders[orderId].account) {
            revert LimitOrderModule_InvalidSenderNotOrderOwner(msg.sender, limitOrders[orderId].account);
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
            revert LimitOrderModule_TipFeeTransferFailed(msg.sender, tipFee);
        }

        emit OrderCancelled(msg.sender, orderId);
    }

    /// @inheritdoc IIncrementLimitOrderModule
    function closeExpiredOrder(uint256 orderId) external {
        if (orderId >= nextOrderId) {
            revert LimitOrderModule_InvalidOrderId();
        }
        if (limitOrders[orderId].expiry > block.timestamp) {
            revert LimitOrderModule_OrderNotExpired(limitOrders[orderId].expiry);
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
            revert LimitOrderModule_TipFeeTransferFailed(msg.sender, tipFee);
        }

        emit OrderExpired(account, orderId);
    }

    /// @notice Initialize the module for the calling account
    /// @dev Module must not be already inited for the account
    /// @param initData Must be empty
    function init(bytes calldata initData) external override {
        if (isInited(msg.sender)) {
            revert Errors.ALREADY_INITED();
        }

        if (!IClaveAccount(msg.sender).isModule(address(this))) {
            revert Errors.MODULE_NOT_ADDED_CORRECTLY();
        }

        if (initData.length > 0) {
            revert LimitOrderModule_InitDataShouldBeEmpty();
        }

        _initialized[msg.sender] = true;

        emit Inited(msg.sender);
    }

    /// @notice Disable the module for the calling account
    function disable() external override {
        if (!isInited(msg.sender)) {
            revert LimitOrderModule_ModuleNotInited();
        }

        if (IClaveAccount(msg.sender).isModule(address(this))) {
            revert Errors.MODULE_NOT_REMOVED_CORRECTLY();
        }

        delete _initialized[msg.sender];

        emit Disabled(msg.sender);
    }

    /* ***************** */
    /*       Views       */
    /* ***************** */

    /// @inheritdoc IIncrementLimitOrderModule
    function getOrder(uint256 orderId) external view returns (LimitOrder memory) {
        if (orderId >= nextOrderId) {
            revert LimitOrderModule_InvalidOrderId();
        }
        return limitOrders[orderId];
    }

    /// @inheritdoc IIncrementLimitOrderModule
    function getTipFee(uint256 orderId) external view returns (uint256) {
        if (orderId >= nextOrderId) {
            revert LimitOrderModule_InvalidOrderId();
        }
        return limitOrders[orderId].tipFee;
    }

    /// @inheritdoc IIncrementLimitOrderModule
    function canFillOrder(uint256 orderId) external view returns (bool) {
        if (orderId >= nextOrderId) {
            revert LimitOrderModule_InvalidOrderId();
        }
        LimitOrder memory order = limitOrders[orderId];
        if (order.expiry <= block.timestamp) {
            return false;
        }

        // ensure limit order is still valid
        IPerpetual perpetual = CLEARING_HOUSE.perpetuals(order.marketIdx);
        if (order.reduceOnly || order.orderType == OrderType.STOP) {
            // reduce-only is only valid if the trader has an open position on the opposite side
            if (!perpetual.isTraderPositionOpen(order.account)) {
                return false;
            }
            LibPerpetual.TraderPosition memory position = perpetual.getTraderPosition(order.account);
            if (order.side == LibPerpetual.Side.Long) {
                if (position.positionSize > 0) {
                    return false;
                }
            } else {
                if (position.positionSize < 0) {
                    return false;
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
                return false;
            }
        } else {
            // for short orders, price must be greater than or equal to the target price - slippage
            if (price < targetPrice.wadMul(1e18 - order.slippage)) {
                return false;
            }
        }

        return true;
    }

    /// @inheritdoc IIncrementLimitOrderModule
    function isInited(address account) public view returns (bool) {
        return _initialized[account];
    }

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) public view override(AccessControl, IERC165) returns (bool) {
        return interfaceId == type(IModule).interfaceId || interfaceId == type(IIncrementLimitOrderModule).interfaceId
            || super.supportsInterface(interfaceId);
    }

    /* ****************** */
    /*     Governance     */
    /* ****************** */

    /// @inheritdoc IIncrementLimitOrderModule
    /// @dev Only callable by governance
    function setMinTipFee(uint256 newMinTipFee) external onlyRole(GOVERNANCE) {
        emit MinTipFeeUpdated(minTipFee, newMinTipFee);
        minTipFee = newMinTipFee;
    }

    /* ******************* */
    /*   Emergency Admin   */
    /* ******************* */

    /// @inheritdoc IIncrementLimitOrderModule
    /// @dev Only callable by emergency admin
    function pause() external override onlyRole(EMERGENCY_ADMIN) {
        _pause();
    }

    /// @inheritdoc IIncrementLimitOrderModule
    /// @dev Only callable by emergency admin
    function unpause() external override onlyRole(EMERGENCY_ADMIN) {
        _unpause();
    }

    /* ****************** */
    /*      Internal      */
    /* ****************** */

    function _executeLimitOrder(LimitOrder memory order) internal {
        // Checks to confirm that the limit order can be executed occur in the LimitOrderBook
        _executeMarketOrder(order.marketIdx, order.amount, order.account, order.side);
    }

    function _executeMarketOrder(uint256 marketIdx, uint256 amount, address account, LibPerpetual.Side side) internal {
        IPerpetual perp = CLEARING_HOUSE.perpetuals(marketIdx);
        // Check if account has an open position already
        if (perp.isTraderPositionOpen(account)) {
            // Account has an open position
            // Determine if we are opening a reverse position or increasing/reducing the current position
            // Check if the current side is the same as the market order side
            if (_isSameSide(perp, account, side)) {
                // Increasing position
                _changePosition(marketIdx, amount, account, side);
            } else {
                // Reducing or reversing position
                uint256 closeProposedAmount =
                    CLEARING_HOUSE_VIEWER.getTraderProposedAmount(marketIdx, account, 1e18, 100, 0);
                if (closeProposedAmount < amount) {
                    // Reversing position
                    _openReversePosition(marketIdx, amount, closeProposedAmount, account, side);
                } else {
                    // Reducing position
                    _changePosition(marketIdx, amount, account, side);
                }
            }
        } else {
            // Account does not have an open position
            _changePosition(marketIdx, amount, account, side);
        }
    }

    function _isSameSide(IPerpetual perp, address account, LibPerpetual.Side side) internal view returns (bool) {
        LibPerpetual.TraderPosition memory traderPosition = perp.getTraderPosition(account);
        LibPerpetual.Side currentSide =
            traderPosition.positionSize > 0 ? LibPerpetual.Side.Long : LibPerpetual.Side.Short;
        return currentSide == side;
    }

    function _changePosition(uint256 marketIdx, uint256 amount, address account, LibPerpetual.Side side) internal {
        uint256 minAmount;
        if (side == LibPerpetual.Side.Long) {
            minAmount = CLEARING_HOUSE_VIEWER.getExpectedVBaseAmount(marketIdx, amount);
        } else {
            minAmount = CLEARING_HOUSE_VIEWER.getExpectedVQuoteAmount(marketIdx, amount);
        }
        _changePosition(marketIdx, amount, minAmount, account, side);
    }

    function _changePosition(
        uint256 marketIdx,
        uint256 amount,
        uint256 minAmount,
        address account,
        LibPerpetual.Side side
    ) internal {
        bytes memory data =
            abi.encodeWithSelector(IClearingHouse.changePosition.selector, marketIdx, amount, minAmount, side);
        IModuleManager(account).executeFromModule(address(CLEARING_HOUSE), 0, data);
    }

    function _openReversePosition(
        uint256 marketIdx,
        uint256 amount,
        uint256 closeProposedAmount,
        address account,
        LibPerpetual.Side side
    ) internal {
        uint256 openProposedAmount = amount - closeProposedAmount;
        uint256 closeMinAmount;
        uint256 openMinAmount;
        if (side == LibPerpetual.Side.Long) {
            closeMinAmount = CLEARING_HOUSE_VIEWER.getExpectedVBaseAmount(marketIdx, closeProposedAmount);
            openMinAmount = CLEARING_HOUSE_VIEWER.getExpectedVBaseAmount(marketIdx, openProposedAmount);
        } else {
            closeMinAmount = CLEARING_HOUSE_VIEWER.getExpectedVQuoteAmount(marketIdx, closeProposedAmount);
            openMinAmount = CLEARING_HOUSE_VIEWER.getExpectedVQuoteAmount(marketIdx, openProposedAmount);
        }
        _openReversePosition(
            marketIdx, closeProposedAmount, closeMinAmount, openProposedAmount, openMinAmount, account, side
        );
    }

    function _openReversePosition(
        uint256 marketIdx,
        uint256 closeProposedAmount,
        uint256 closeMinAmount,
        uint256 openProposedAmount,
        uint256 openMinAmount,
        address account,
        LibPerpetual.Side side
    ) internal {
        bytes memory data = abi.encodeWithSelector(
            IClearingHouse.openReversePosition.selector,
            marketIdx,
            closeProposedAmount,
            closeMinAmount,
            openProposedAmount,
            openMinAmount,
            side
        );
        IModuleManager(account).executeFromModule(address(CLEARING_HOUSE), 0, data);
    }
}
