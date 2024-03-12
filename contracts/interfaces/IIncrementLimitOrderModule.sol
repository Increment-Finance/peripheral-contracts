// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.16;

import "./ILimitOrderBook.sol";

interface IIncrementLimitOrderModule {
    function executeLimitOrder(
        ILimitOrderBook.LimitOrder memory order
    ) external;
}