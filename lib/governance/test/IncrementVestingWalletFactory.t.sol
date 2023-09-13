// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.16;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/mocks/ERC20VotesMock.sol";
import "../src/IncrementVestingWalletFactory.sol";
import "../src/IncrementVestingWallet.sol";

contract TestIncrementVestingWalletFactory is Test {
    IncrementVestingWallet public impl;
    IncrementVestingWalletFactory public factory;
    ERC20VotesMock public token;

    function setUp() public {
        impl = new IncrementVestingWallet();
        factory = new IncrementVestingWalletFactory(address(impl));
        token = new ERC20VotesMock("Test", "TST");
    }

    function testDeploy(address beneficiary, uint64 startTimestamp, uint64 durationSeconds) public {
        vm.assume(beneficiary != address(0));

        IncrementVestingWallet vestingWallet = factory.deploy(token, beneficiary, startTimestamp, durationSeconds);

        assertEq(address(vestingWallet), factory.vestingWallets(beneficiary));
        assertEq(address(vestingWallet.vestingToken()), address(token));
        assertEq(vestingWallet.beneficiary(), beneficiary);
        assertEq(vestingWallet.start(), startTimestamp);
        assertEq(vestingWallet.duration(), durationSeconds);
        assertEq(vestingWallet.released(), 0);
    }
}
