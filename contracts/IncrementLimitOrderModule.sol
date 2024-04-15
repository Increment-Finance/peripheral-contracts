// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.20;

// contracts
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ERC165, IERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";

// interfaces
import {IClaveAccount} from "clave-contracts/contracts/interfaces/IClave.sol";
import {IClearingHouse} from "@increment/interfaces/IClearingHouse.sol";
import {ILimitOrderBook} from "./interfaces/ILimitOrderBook.sol";
import {IIncrementLimitOrderModule, IModule} from "./interfaces/IIncrementLimitOrderModule.sol";

// libraries
import {Errors} from "clave-contracts/contracts/libraries/Errors.sol";
import {LibPerpetual} from "@increment/lib/LibPerpetual.sol";

contract IncrementLimitOrderModule is IIncrementLimitOrderModule, EIP712, ERC165 {
    ILimitOrderBook public immutable LIMIT_ORDER_BOOK;
    IClearingHouse public immutable CLEARING_HOUSE;

    mapping(address => bool) private _initialized;

    modifier onlyLimitOrderBook() {
        if (msg.sender != address(LIMIT_ORDER_BOOK)) {
            revert LimitOrderModule_OnlyLimitOrderBook();
        }
        _;
    }

    constructor(string memory name, string memory version, ILimitOrderBook limitOrderBook, IClearingHouse clearingHouse)
        EIP712(name, version)
    {
        LIMIT_ORDER_BOOK = limitOrderBook;
        CLEARING_HOUSE = clearingHouse;
    }

    function executeLimitOrder(ILimitOrderBook.LimitOrder memory order) external override onlyLimitOrderBook {
        // execute limit order
    }

    function executeMarketOrder(uint256 marketIdx, uint256 amount, address account, LibPerpetual.Side side)
        external
        override
        onlyLimitOrderBook
    {
        // execute market order
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

        _initialized[msg.sender] = true;

        emit Inited(msg.sender);

        // _updateConfig(config);
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

        // _stopRecovery();
    }

    function isInited(address account) public view returns (bool) {
        return _initialized[account];
    }

    function supportsInterface(bytes4 interfaceId) public view override(ERC165, IERC165) returns (bool) {
        return interfaceId == type(IModule).interfaceId || interfaceId == type(IIncrementLimitOrderModule).interfaceId
            || super.supportsInterface(interfaceId);
    }
}
