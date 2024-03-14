// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.16;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import "./ILimitOrderBook.sol";
import {LibPerpetual} from "@increment/lib/LibPerpetual.sol";

interface IIncrementLimitOrderModule is IERC165 {
    function executeLimitOrder(ILimitOrderBook.LimitOrder memory order) external;

    function executeMarketOrder(uint256 marketIdx, uint256 amount, LibPerpetual.Side side) external;
}
