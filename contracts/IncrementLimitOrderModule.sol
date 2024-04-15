// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.20;

// contracts
import {EIP712} from "clave-contracts/contracts/helpers/EIP712.sol";

// interfaces
import {IClaveAccount} from "clave-contracts/contracts/interfaces/IClave.sol";
import {IClearingHouse} from "@increment/interfaces/IClearingHouse.sol";
import {ILimitOrderBook} from "./interfaces/ILimitOrderBook.sol";
import {IIncrementLimitOrderModule} from "./interfaces/IIncrementLimitOrderModule.sol";

// libraries
import {Errors} from "clave-contracts/contracts/libraries/Errors.sol";
import {LibPerpetual} from "@increment/lib/LibPerpetual.sol";

contract IncrementLimitOrderModule is IIncrementLimitOrderModule, EIP712 {
    ILimitOrderBook public immutable LIMIT_ORDER_BOOK;
    IClearingHouse public immutable CLEARING_HOUSE;

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

    function executeMarketOrder(uint256 marketIdx, uint256 amount, LibPerpetual.Side side)
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

        // RecoveryConfig memory config = abi.decode(initData, (RecoveryConfig));

        emit Inited(msg.sender);

        // _updateConfig(config);
    }

    /**
     * @notice Disable the module for the calling account
     */
    function disable() external override {
        if (!isInited(msg.sender)) {
            revert Errors.RECOVERY_NOT_INITED();
        }

        if (IClaveAccount(msg.sender).isModule(address(this))) {
            revert Errors.MODULE_NOT_REMOVED_CORRECTLY();
        }

        // delete recoveryConfigs[msg.sender];

        emit Disabled(msg.sender);

        // _stopRecovery();
    }
}
