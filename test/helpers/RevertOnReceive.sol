// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.20;

import {console2 as console} from "forge/console2.sol";

contract RevertOnReceive {
    receive() external payable {
        console.log("RevertOnReceive.receive: msg.value = %s", msg.value);
        require(false, "RevertOnReceive.receive: receive not allowed");
    }
}
