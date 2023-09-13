// SPDX-License-Identifier: AGPL-3.0

pragma solidity 0.8.16;

import "forge-std/Script.sol";
import "../src/IncrementToken.sol";
import {TOKEN_SUPPLY, MULTI_SIG} from "./Constants.sol";

contract RenounceOwnership is Script {
    function run() public {
        IncrementToken token = IncrementToken(vm.envAddress("TOKEN"));
        address timelock = vm.envAddress("TIMELOCK");

        vm.startBroadcast(MULTI_SIG);
        // Send remainder to timelock
        token.transfer(address(timelock), token.balanceOf(MULTI_SIG));

        // Give token admin roles to timelock
        token.grantRole(token.OWNER_ROLE(), address(timelock));
        token.renounceRole(token.OWNER_ROLE(), MULTI_SIG);
        vm.stopBroadcast();
    }
}
