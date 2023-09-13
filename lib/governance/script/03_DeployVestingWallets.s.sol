// SPDX-License-Identifier: AGPL-3.0

pragma solidity 0.8.16;

import "forge-std/Script.sol";
import "@openzeppelin/contracts/governance/TimelockController.sol";
import "../src/IncrementToken.sol";
import "../src/IncrementVestingWallet.sol";
import "../src/IncrementVestingWalletFactory.sol";
import {
    MULTI_SIG,
    CORE_CONTRIBUTOR_0,
    CORE_CONTRIBUTOR_1,
    CORE_CONTRIBUTOR_2,
    INVESTOR_0,
    INVESTOR_1,
    INVESTOR_2,
    INVESTOR_3,
    INVESTOR_4,
    INVESTOR_5,
    ANGEL_0,
    ANGEL_1,
    ANGEL_2,
    ANGEL_3,
    DEVELOPMENT_FUND,
    ECOSYSTEM_FUND
} from "./Constants.sol";

contract DeployVestingWallets is Script {
    function run() public returns (IncrementVestingWallet[] memory vestingWallets) {
        bytes[] memory vestingParties = new bytes[](15);
        vestingParties[0] = CORE_CONTRIBUTOR_0;
        vestingParties[1] = CORE_CONTRIBUTOR_1;
        vestingParties[2] = CORE_CONTRIBUTOR_2;
        vestingParties[3] = INVESTOR_0;
        vestingParties[4] = INVESTOR_1;
        vestingParties[5] = INVESTOR_2;
        vestingParties[6] = INVESTOR_3;
        vestingParties[7] = INVESTOR_4;
        vestingParties[8] = INVESTOR_5;
        vestingParties[9] = ANGEL_0;
        vestingParties[10] = ANGEL_1;
        vestingParties[11] = ANGEL_2;
        vestingParties[12] = ANGEL_3;
        vestingParties[13] = DEVELOPMENT_FUND;
        vestingParties[14] = ECOSYSTEM_FUND;

        IncrementToken token = IncrementToken(vm.envAddress("TOKEN"));
        address timelock = vm.envAddress("TIMELOCK");

        // Create implementation and vesting wallet
        vm.startBroadcast(MULTI_SIG);
        IncrementVestingWallet implementation = new IncrementVestingWallet();
        IncrementVestingWalletFactory factory = new IncrementVestingWalletFactory(address(implementation));
        vm.stopBroadcast();

        uint64 currentTime = uint64(block.timestamp);
        vestingWallets = new IncrementVestingWallet[](vestingParties.length);

        for (uint256 i = 0; i < vestingParties.length; i++) {
            bytes memory party = vestingParties[i];
            (address beneficiary, uint256 amount, uint64 cliff, uint64 duration) =
                abi.decode(party, (address, uint256, uint64, uint64));

            // Replace 0 address with timelock address
            if (beneficiary == address(0)) beneficiary = timelock;

            // Create Vesting wallet
            vm.startBroadcast(MULTI_SIG);
            vestingWallets[i] = factory.deploy(token, beneficiary, currentTime + cliff, duration);
            token.transfer(address(vestingWallets[i]), amount);
            token.grantRole(token.DISTRIBUTOR_ROLE(), address(vestingWallets[i]));
            vm.stopBroadcast();
        }
    }
}
