// SPDX-License-Identifier: AGPL-3.0

pragma solidity 0.8.16;

import "forge-std/Script.sol";
import "@openzeppelin/contracts/governance/TimelockController.sol";
import "../src/IncrementToken.sol";
import "../src/IncrementGovernor.sol";
import {TIMELOCK_DURATION, MULTI_SIG} from "./Constants.sol";

contract DeployGovernor is Script {
    function run() public returns (TimelockController timelock, IncrementGovernor governor) {
        IncrementToken token = IncrementToken(vm.envAddress("TOKEN"));

        // Deploy Timelock & Governor
        address[] memory timelockProposers = new address[](0);
        address[] memory timelockExecuters = new address[](0);

        vm.startBroadcast(MULTI_SIG);
        timelock = new TimelockController(TIMELOCK_DURATION, timelockProposers, timelockExecuters, MULTI_SIG);
        governor = new IncrementGovernor(token, timelock);

        // Give proposer & cancellor roles to governor
        timelock.grantRole(timelock.PROPOSER_ROLE(), address(governor));
        timelock.grantRole(timelock.EXECUTOR_ROLE(), address(governor));
        timelock.grantRole(timelock.CANCELLER_ROLE(), address(governor));

        // Renounce admin role so that Timelock is the only admin
        timelock.renounceRole(timelock.TIMELOCK_ADMIN_ROLE(), MULTI_SIG);
        vm.stopBroadcast();

        // Set env for next script
        vm.setEnv("TIMELOCK", vm.toString(address(timelock)));
    }
}
