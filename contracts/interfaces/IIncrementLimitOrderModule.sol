// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.20;

// interfaces
import {IModule} from "clave-contracts/contracts/interfaces/IModule.sol";
import {ILimitOrderBook} from "./ILimitOrderBook.sol";

// libraries
import {LibPerpetual} from "@increment/lib/LibPerpetual.sol";

interface IIncrementLimitOrderModule is IModule {
    /// @notice Error emitted when an unauthorized address attempts to execute an order
    error LimitOrderModule_OnlyLimitOrderBook();

    /// @notice Error emitted when trying to disable a module that has not been initialized
    error LimitOrderModule_ModuleNotInited();

    /// @notice Error emitted when trying to initialize a module with non-empty `initData`
    error LimitOrderModule_InitDataShouldBeEmpty();

    /// @notice Executes a limit order on behalf of the user who created the order
    /// @dev All checks to determine order validity occur in LimitOrderBook, which must be the caller
    /// @param order The limit order to execute
    function executeLimitOrder(ILimitOrderBook.LimitOrder memory order) external;

    /// @notice Executes a market order on behalf of the user who created the order
    /// @dev All checks to determine order validity occur in LimitOrderBook, which must be the caller
    /// @param marketIdx The perpetual market's unique identifier in the ClearingHouse
    /// @param amount Amount in vQuote (if LONG) or vBase (if SHORT) to sell. 18 decimals
    /// @param account Address of the user's Clave account
    /// @param side Whether the trader wants to go in the LONG or SHORT direction
    function executeMarketOrder(uint256 marketIdx, uint256 amount, address account, LibPerpetual.Side side) external;
}
