// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.20;

// interfaces
import {IModule} from "clave-contracts/contracts/interfaces/IModule.sol";
import "./ILimitOrderBook.sol";

// libraries
import {LibPerpetual} from "@increment/lib/LibPerpetual.sol";

interface IIncrementLimitOrderModule is IModule {
    error LimitOrderModule_OnlyLimitOrderBook();

    function executeLimitOrder(ILimitOrderBook.LimitOrder memory order) external;

    function executeMarketOrder(uint256 marketIdx, uint256 amount, LibPerpetual.Side side) external;
}
