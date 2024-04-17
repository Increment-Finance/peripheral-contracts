// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.20;

// contracts
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ERC165, IERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";

// interfaces
import {IClaveAccount} from "clave-contracts/contracts/interfaces/IClave.sol";
import {IModuleManager} from "clave-contracts/contracts/interfaces/IModuleManager.sol";
import {IClearingHouseViewer} from "@increment/interfaces/IClearingHouseViewer.sol";
import {IClearingHouse} from "@increment/interfaces/IClearingHouse.sol";
import {IPerpetual} from "@increment/interfaces/IPerpetual.sol";
import {ILimitOrderBook} from "./interfaces/ILimitOrderBook.sol";
import {IIncrementLimitOrderModule, IModule} from "./interfaces/IIncrementLimitOrderModule.sol";

// libraries
import {Errors} from "clave-contracts/contracts/libraries/Errors.sol";
import {LibPerpetual} from "@increment/lib/LibPerpetual.sol";

contract IncrementLimitOrderModule is IIncrementLimitOrderModule, EIP712, ERC165 {
    ILimitOrderBook public immutable LIMIT_ORDER_BOOK;
    IClearingHouse public immutable CLEARING_HOUSE;
    IClearingHouseViewer public immutable CLEARING_HOUSE_VIEWER;

    mapping(address => bool) private _initialized;

    modifier onlyLimitOrderBook() {
        if (msg.sender != address(LIMIT_ORDER_BOOK)) {
            revert LimitOrderModule_OnlyLimitOrderBook();
        }
        _;
    }

    constructor(
        string memory name,
        string memory version,
        ILimitOrderBook limitOrderBook,
        IClearingHouse clearingHouse,
        IClearingHouseViewer clearingHouseViewer
    ) EIP712(name, version) {
        LIMIT_ORDER_BOOK = limitOrderBook;
        CLEARING_HOUSE = clearingHouse;
        CLEARING_HOUSE_VIEWER = clearingHouseViewer;
    }

    function executeLimitOrder(ILimitOrderBook.LimitOrder memory order) external override {
        executeMarketOrder(order.marketIdx, order.amount, order.account, order.side);
    }

    function executeMarketOrder(uint256 marketIdx, uint256 amount, address account, LibPerpetual.Side side)
        public
        override
        onlyLimitOrderBook
    {
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

    /**
     * @notice Initialize the module for the calling account with the given config
     * @dev Module must not be already inited for the account
     * @param initData bytes calldata
     */
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

    /**
     * @notice Disable the module for the calling account
     */
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

    function isInited(address account) public view returns (bool) {
        return _initialized[account];
    }

    function supportsInterface(bytes4 interfaceId) public view override(ERC165, IERC165) returns (bool) {
        return interfaceId == type(IModule).interfaceId || interfaceId == type(IIncrementLimitOrderModule).interfaceId
            || super.supportsInterface(interfaceId);
    }

    function _isSameSide(IPerpetual perp, address account, LibPerpetual.Side side) internal returns (bool) {
        LibPerpetual.TraderPosition memory traderPosition = perp.getTraderPosition(account);
        LibPerpetual.Side currentSide =
            traderPosition.positionSize > 0 ? LibPerpetual.Side.Long : LibPerpetual.Side.Short;
        return currentSide == side;
    }

    function _changePosition(uint256 marketIdx, uint256 amount, address account, LibPerpetual.Side side) internal {
        uint256 minAmount = CLEARING_HOUSE_VIEWER.getTraderDy(marketIdx, amount, side);
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
        uint256 closeMinAmount = CLEARING_HOUSE_VIEWER.getTraderDy(marketIdx, closeProposedAmount, side);
        uint256 openProposedAmount = amount - closeProposedAmount;
        uint256 openMinAmount = CLEARING_HOUSE_VIEWER.getTraderDy(marketIdx, openProposedAmount, side);
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
