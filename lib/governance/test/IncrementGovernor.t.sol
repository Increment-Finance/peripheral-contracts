// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.16;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/mocks/ERC20VotesMock.sol";
import "@openzeppelin/contracts/governance/TimelockController.sol";
import "../src/IncrementGovernor.sol";
import "@openzeppelin/contracts/governance/IGovernor.sol";

contract IncrementGovernorTest is Test {
    ERC20VotesMock public token;
    TimelockController public timelock;
    IncrementGovernor public governor;

    function setUp() public {
        address[] memory timelockProposers = new address[](0);
        address[] memory timelockExecuters = new address[](0);

        timelock = new TimelockController(10, timelockProposers, timelockExecuters, address(this));
        token = new ERC20VotesMock("Token", "TKN");
        governor = new IncrementGovernor(token, timelock);

        // Give proposer & cancellor roles to governor
        timelock.grantRole(timelock.PROPOSER_ROLE(), address(governor));
        timelock.grantRole(timelock.EXECUTOR_ROLE(), address(governor));
        timelock.grantRole(timelock.CANCELLER_ROLE(), address(governor));

        // Renounce admin role so that Timelock is the only admin
        timelock.renounceRole(timelock.TIMELOCK_ADMIN_ROLE(), address(this));

        // Mint tokens & delegate to this address
        token.mint(address(this), 1000 ether);
        token.delegate(address(this));
        vm.roll(block.number + governor.votingDelay());
    }

    function testConstructor() public {
        // Ensure constructor params have been set properly
        assertEq(governor.name(), "Increment Governor");
        assertEq(governor.votingDelay(), 1);
        assertEq(governor.votingPeriod(), 50400);
        assertEq(governor.proposalThreshold(), 100 ether);
        assertEq(address(governor.token()), address(token));
        assertEq(governor.quorumNumerator(), 2);
        assertEq(address(governor.timelock()), address(timelock));
    }

    function testProposalCreation(uint256 amount) public {
        // Ensure no address collision
        address receiver = address(0);

        // Test sending eth from governor to receiver
        uint256 initialReceiverBalance = receiver.balance;

        // Prep proposal params
        address[] memory targets = new address[](1);
        targets[0] = receiver;
        uint256[] memory values = new uint256[](1);
        values[0] = amount;
        bytes[] memory calldatas = new bytes[](1);
        string memory description = "Test Proposal";

        // Set governor balance
        vm.deal(address(timelock), amount);

        // Create proposal
        uint256 proposalId = governor.propose(targets, values, calldatas, description);

        // Ensure proposal was created
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Pending));

        // Ensure proposal is active after votingDelay
        vm.roll(block.number + governor.votingDelay() + 1);
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Active));

        // Vote in favor of proposal
        governor.castVote(proposalId, 1);
        vm.roll(block.number + governor.votingPeriod());
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Succeeded));

        // Queue proposal for timelock
        governor.queue(targets, values, calldatas, keccak256(abi.encodePacked(description)));
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Queued));

        // Execute proposal
        vm.warp(block.number + 11);
        governor.execute(targets, values, calldatas, keccak256(abi.encodePacked(description)));
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Executed));

        assertEq(receiver.balance, amount + initialReceiverBalance);
    }
}
