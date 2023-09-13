// SPDX-License-Identifier: AGPL-3.0

pragma solidity 0.8.16;

import "forge-std/Script.sol";
import "../src/IncrementToken.sol";
import {TOKEN_DEPLOYER, TOKEN_SUPPLY, MULTI_SIG} from "./Constants.sol";

contract DeployToken is Script {
    function run() public returns (IncrementToken token) {
        // Deploy token
        vm.startBroadcast(TOKEN_DEPLOYER);
        token = new IncrementToken(TOKEN_SUPPLY, TOKEN_DEPLOYER);
        token.transfer(MULTI_SIG, TOKEN_SUPPLY);
        token.grantRole(token.OWNER_ROLE(), MULTI_SIG);
        token.renounceRole(token.OWNER_ROLE(), TOKEN_DEPLOYER);
        vm.stopBroadcast();

        // Set env for next script
        vm.setEnv("TOKEN", vm.toString(address(token)));
    }
}
