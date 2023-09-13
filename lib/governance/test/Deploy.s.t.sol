// SPDX-License-Identifier: AGPL-3.0

pragma solidity 0.8.16;

import "forge-std/Test.sol";
import "../script/01_DeployToken.s.sol";
import "../script/02_DeployGovernor.s.sol";
import "../script/03_DeployVestingWallets.s.sol";
import "../script/04_DeployMerkleDistributor.s.sol";
import "../script/05_RenounceOwnership.s.sol";
import {
    TOKEN_DEPLOYER,
    TOKEN_SUPPLY,
    CORE_CONTRIBUTOR_0,
    CORE_CONTRIBUTOR_1,
    CORE_CONTRIBUTOR_2,
    INVESTOR_0,
    INVESTOR_1,
    INVESTOR_2,
    INVESTOR_3,
    INVESTOR_3,
    INVESTOR_4,
    INVESTOR_5,
    ANGEL_0,
    ANGEL_1,
    ANGEL_2,
    ANGEL_3,
    DEVELOPMENT_FUND,
    ECOSYSTEM_FUND
} from "../script/Constants.sol";

contract TestDeploy is Test {
    TimelockController public timelock;
    IncrementGovernor public governor;
    IncrementToken public token;
    IncrementVestingWallet[] public vestingWallets;
    MerkleDistributor public merkleDistributor;
    MerkleGenerator public merkleGenerator;

    bytes[] public vestingParties;

    function setUp() public {
        vm.setEnv("CSV_PATH", "test/airdrop.csv");

        token = (new DeployToken()).run();
        (timelock, governor) = (new DeployGovernor()).run();
        vestingWallets = (new DeployVestingWallets()).run();
        (merkleDistributor, merkleGenerator) = (new DeployMerkleDistributor()).run();
        (new RenounceOwnership()).run();

        vestingParties.push(CORE_CONTRIBUTOR_0);
        vestingParties.push(CORE_CONTRIBUTOR_1);
        vestingParties.push(CORE_CONTRIBUTOR_2);
        vestingParties.push(INVESTOR_0);
        vestingParties.push(INVESTOR_1);
        vestingParties.push(INVESTOR_2);
        vestingParties.push(INVESTOR_3);
        vestingParties.push(INVESTOR_4);
        vestingParties.push(INVESTOR_5);
        vestingParties.push(ANGEL_0);
        vestingParties.push(ANGEL_1);
        vestingParties.push(ANGEL_2);
        vestingParties.push(ANGEL_3);
        vestingParties.push(DEVELOPMENT_FUND);
        vestingParties.push(ECOSYSTEM_FUND);

        assertEq(vestingParties.length, vestingWallets.length);
    }

    function testTokenSupply() public {
        assertEq(token.totalSupply(), TOKEN_SUPPLY);
    }

    function testBalances() public {
        // Check vesting balances
        uint256 totalVestingBalance = 0;
        for (uint256 i = 0; i < vestingParties.length; i++) {
            (, uint256 vestingBalance,,) = abi.decode(vestingParties[i], (address, uint256, uint256, uint256));
            totalVestingBalance += vestingBalance;
            assertEq(token.balanceOf(address(vestingWallets[i])), vestingBalance);
        }

        // Check Distributor balance
        assertEq(token.balanceOf(address(merkleDistributor)), merkleGenerator.totalAmount());

        // Check Remaining balances
        assertEq(token.balanceOf(address(governor)), 0);
        assertEq(
            token.balanceOf(address(timelock)),
            token.totalSupply() - totalVestingBalance - merkleGenerator.totalAmount()
        );
    }

    function testTokenRoles() public {
        // Get Admin Roles
        bytes32 ownerAdminRole = token.getRoleAdmin(token.OWNER_ROLE());
        bytes32 distributorAdminRole = token.getRoleAdmin(token.DISTRIBUTOR_ROLE());

        // Assert OWNER_ROLE is admin for all roles
        assertEq(ownerAdminRole, token.OWNER_ROLE());
        assertEq(distributorAdminRole, token.OWNER_ROLE());

        // Ensure timelock has the correct roles
        assertTrue(token.hasRole(token.OWNER_ROLE(), address(timelock)));
        assertTrue(!token.hasRole(token.DISTRIBUTOR_ROLE(), address(timelock)));

        // Ensure vestingWallets have distributor role
        for (uint256 i = 0; i < vestingWallets.length; i++) {
            address vestingWallet = address(vestingWallets[i]);
            assertTrue(token.hasRole(token.DISTRIBUTOR_ROLE(), address(vestingWallet)));
            assertTrue(!token.hasRole(token.OWNER_ROLE(), address(vestingWallet)));
        }

        // Ensure MerkleDistributor has distributor role
        assertTrue(token.hasRole(token.DISTRIBUTOR_ROLE(), address(merkleDistributor)));
        assertTrue(!token.hasRole(token.OWNER_ROLE(), address(merkleDistributor)));

        // Ensure deployer revoked all roles
        assertTrue(!token.hasRole(token.DISTRIBUTOR_ROLE(), address(TOKEN_DEPLOYER)));
        assertTrue(!token.hasRole(token.OWNER_ROLE(), address(TOKEN_DEPLOYER)));
        assertTrue(!token.hasRole(token.DISTRIBUTOR_ROLE(), address(MULTI_SIG)));
        assertTrue(!token.hasRole(token.OWNER_ROLE(), address(MULTI_SIG)));
    }

    function testMerkleDistributorRoles() public {
        assertEq(merkleDistributor.owner(), address(timelock));
    }

    function testTimelockRoles() public {
        // Assert Governor has correct roles
        assertTrue(timelock.hasRole(timelock.PROPOSER_ROLE(), address(governor)));
        assertTrue(timelock.hasRole(timelock.EXECUTOR_ROLE(), address(governor)));
        assertTrue(timelock.hasRole(timelock.CANCELLER_ROLE(), address(governor)));

        // Assert only timelock holds admin role
        assertTrue(timelock.hasRole(timelock.TIMELOCK_ADMIN_ROLE(), address(timelock)));
        assertTrue(!timelock.hasRole(timelock.TIMELOCK_ADMIN_ROLE(), address(governor)));
        assertTrue(!timelock.hasRole(timelock.TIMELOCK_ADMIN_ROLE(), address(TOKEN_DEPLOYER)));
        assertTrue(!timelock.hasRole(timelock.TIMELOCK_ADMIN_ROLE(), address(MULTI_SIG)));

        // Assert deployer renounced all roles
        assertTrue(!timelock.hasRole(timelock.PROPOSER_ROLE(), address(TOKEN_DEPLOYER)));
        assertTrue(!timelock.hasRole(timelock.EXECUTOR_ROLE(), address(TOKEN_DEPLOYER)));
        assertTrue(!timelock.hasRole(timelock.CANCELLER_ROLE(), address(TOKEN_DEPLOYER)));
        assertTrue(!timelock.hasRole(timelock.PROPOSER_ROLE(), address(MULTI_SIG)));
        assertTrue(!timelock.hasRole(timelock.EXECUTOR_ROLE(), address(MULTI_SIG)));
        assertTrue(!timelock.hasRole(timelock.CANCELLER_ROLE(), address(MULTI_SIG)));
    }

    function testVestingDelegation() public {
        // Ensure vestingWallet beneficiaries can delegate
        for (uint256 i = 0; i < vestingWallets.length; i++) {
            IncrementVestingWallet vestingWallet = vestingWallets[i];
            assertEq(token.delegates(address(vestingWallet)), address(0));

            vm.startPrank(vestingWallet.beneficiary());
            vestingWallet.delegate(vestingWallet.beneficiary());
            vm.stopPrank();

            assertEq(token.delegates(address(vestingWallet)), vestingWallet.beneficiary());
        }
    }

    function testVestingClaim(uint256 receiverId, uint256 timePassed) public {
        // Ensure valid index
        vm.assume(receiverId < vestingWallets.length);

        // Time travel
        vm.warp(timePassed);

        // Get wallet & party
        IncrementVestingWallet vestingWallet = vestingWallets[receiverId];
        (address receiver, uint256 amount, uint256 cliff, uint256 duration) =
            abi.decode(vestingParties[receiverId], (address, uint256, uint256, uint256));
        uint256 start = cliff + 1;

        if (receiver == address(0)) receiver = address(timelock);
        uint256 initialBalance = token.balanceOf(receiver);

        // Ensure vestingWallet matches party
        assertEq(vestingWallet.beneficiary(), receiver);
        assertEq(vestingWallet.start(), start);
        assertEq(vestingWallet.duration(), duration);

        // Check all cases
        if (timePassed < start) {
            // Ensure vested amount is 0
            assertEq(vestingWallet.releasable(address(token)), uint256(0));

            // Claim tokens
            assertEq(token.balanceOf(address(vestingWallet)), amount);
            vestingWallet.release(address(token));

            // Ensure 0 tokens were claimed
            assertEq(token.balanceOf(address(vestingWallet)), amount);
            assertEq(token.balanceOf(address(receiver)), initialBalance);
        } else if (timePassed >= start && timePassed <= start + duration) {
            uint256 expectedAmount = (amount * (block.timestamp - start)) / duration;

            // Ensure vested amount is expectedAmount
            assertEq(vestingWallet.releasable(address(token)), expectedAmount);

            // Claim tokens
            assertEq(token.balanceOf(address(vestingWallet)), amount);
            vestingWallet.release(address(token));

            // Ensure 0 tokens were claimed
            assertEq(token.balanceOf(address(vestingWallet)), amount - expectedAmount);
            assertEq(token.balanceOf(address(receiver)), expectedAmount + initialBalance);
        } else if (timePassed > start + duration) {
            // Ensure vested amount is full amount
            assertEq(vestingWallet.releasable(address(token)), amount);

            // Claim tokens
            assertEq(token.balanceOf(address(vestingWallet)), amount);
            vestingWallet.release(address(token));

            // Ensure 0 tokens were claimed
            assertEq(token.balanceOf(address(vestingWallet)), 0);
            assertEq(token.balanceOf(address(receiver)), amount + initialBalance);
        }
    }

    function testMerkleClaim(uint256 claimId) public {
        // Generate treeData
        bytes32[] memory treeData = merkleGenerator.getTreeData();

        // Ensure claimId is in range
        vm.assume(claimId < treeData.length);

        // Get proof
        bytes32[] memory proof = merkleGenerator.getMerkleProof(claimId);

        // Get claim data
        (address receiver, uint256 amount) = merkleGenerator.getClaimData(claimId);
        IMerkleDistributor.Claim memory claim = IMerkleDistributor.Claim({
            windowIndex: 0,
            amount: amount,
            accountIndex: claimId,
            account: receiver,
            merkleProof: proof
        });

        // Test claim
        merkleDistributor.claim(claim);

        // Check balances
        assertEq(token.balanceOf(receiver), amount);
        emit log_named_address("generator", address(merkleGenerator));
        assertEq(token.balanceOf(address(merkleDistributor)), merkleGenerator.totalAmount() - amount);
    }
}
