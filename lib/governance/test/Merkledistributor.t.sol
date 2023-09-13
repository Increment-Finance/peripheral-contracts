// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "@openzeppelin/contracts/mocks/ERC20Mock.sol";
import "murky/src/Merkle.sol";
import "../src/MerkleDistributor.sol";
import "../src/interfaces/IMerkleDistributor.sol";

contract MerkeDistributorTest is Test {
    uint256 public constant TOKEN_SUPPLY = 60 ether;
    // Random hash
    string public constant IPFS_HASH = "QmYwAPJzv5CZsnA625s3Xf2nemtYgPpHdWEz79ojWnPbdG";

    MerkleDistributor public distributor;
    IERC20 public token;

    Merkle public merkle;
    bytes32[] public data;
    bytes32 public root;

    function setUp() public {
        distributor = new MerkleDistributor();
        token = new ERC20Mock("Token", "TKN", address(this), TOKEN_SUPPLY);
        token.approve(address(distributor), TOKEN_SUPPLY);

        // Create Merkle root
        merkle = new Merkle();

        data = new bytes32[](3);
        data[0] = keccak256(abi.encodePacked(address(1), TOKEN_SUPPLY / 6, uint256(0)));
        data[1] = keccak256(abi.encodePacked(address(2), TOKEN_SUPPLY / 3, uint256(1)));
        data[2] = keccak256(abi.encodePacked(address(3), TOKEN_SUPPLY / 2, uint256(2)));

        root = merkle.getRoot(data);
    }

    function testInitialState() public {
        // Ensure next index is 0
        assertEq(distributor.nextCreatedIndex(), 0);

        // Ensure there is no merkle root set at index 0
        (bytes32 merkleRoot, uint256 remainingAmount, IERC20 rewardToken, string memory ipfsHash) =
            distributor.merkleWindows(0);
        assertEq(merkleRoot, bytes32(0));
        assertEq(remainingAmount, 0);
        assertEq(address(rewardToken), address(0));
        assertEq(ipfsHash, "");
    }

    function testSetWindow() public {
        // Create window
        distributor.setWindow(TOKEN_SUPPLY, address(token), root, IPFS_HASH);

        // Ensure next index is incremented
        assertEq(distributor.nextCreatedIndex(), 1);

        // Ensure window was set with correct values
        (bytes32 merkleRoot, uint256 remainingAmount, IERC20 rewardToken, string memory ipfsHash) =
            distributor.merkleWindows(0);
        assertEq(merkleRoot, root);
        assertEq(remainingAmount, TOKEN_SUPPLY);
        assertEq(address(rewardToken), address(token));
        assertEq(distributor.getRewardTokenForWindow(0), address(token));
        assertEq(ipfsHash, IPFS_HASH);
        assertEq(token.balanceOf(address(distributor)), TOKEN_SUPPLY);
    }

    function testFailNotOwnerSetWindow(address user) public {
        vm.assume(user != address(this) && user != address(0));

        // Attempt to set window when not owner (should fail)
        vm.prank(user);
        distributor.setWindow(TOKEN_SUPPLY, address(token), root, IPFS_HASH);
    }

    function testDeleteWindow() public {
        // Create window
        distributor.setWindow(TOKEN_SUPPLY, address(token), root, IPFS_HASH);

        // Delete window
        uint256 windowIndex = distributor.nextCreatedIndex() - 1;
        distributor.deleteWindow(windowIndex);

        // Ensure window was deleted
        (bytes32 merkleRoot, uint256 remainingAmount, IERC20 rewardToken, string memory ipfsHash) =
            distributor.merkleWindows(windowIndex);
        assertEq(merkleRoot, bytes32(0));
        assertEq(remainingAmount, 0);
        assertEq(address(rewardToken), address(0));
        assertEq(ipfsHash, "");
    }

    function testFailNotOwnerDeleteWindow(address user) public {
        vm.assume(user != address(this) && user != address(0));

        // Create window
        distributor.setWindow(TOKEN_SUPPLY, address(token), root, IPFS_HASH);

        // Attempt to delete window (should fail)
        uint256 windowIndex = distributor.nextCreatedIndex() - 1;
        vm.prank(user);
        distributor.deleteWindow(windowIndex);
    }

    function testWithdrawRewards(uint256 withdrawAmount) public {
        vm.assume(withdrawAmount < TOKEN_SUPPLY && withdrawAmount > 0);

        // Create window
        distributor.setWindow(TOKEN_SUPPLY, address(token), root, IPFS_HASH);

        // Retrieve tokens
        distributor.withdrawRewards(token, withdrawAmount);

        // Ensure balances are updated
        assertEq(token.balanceOf(address(distributor)), TOKEN_SUPPLY - withdrawAmount);
        assertEq(token.balanceOf(address(this)), withdrawAmount);
    }

    function testFailNotOwnerWithdrawRewards(address user, uint256 withdrawAmount) public {
        vm.assume(user != address(this) && user != address(0));
        vm.assume(withdrawAmount < TOKEN_SUPPLY && withdrawAmount > 0);

        // Create window
        distributor.setWindow(TOKEN_SUPPLY, address(token), root, IPFS_HASH);

        // Attempt to retrieve tokens (should fail)
        vm.prank(user);
        distributor.withdrawRewards(token, withdrawAmount);
    }

    function testClaim() public {
        // Create window
        distributor.setWindow(TOKEN_SUPPLY, address(token), root, IPFS_HASH);

        // Claim info
        uint256 windowIndex = distributor.nextCreatedIndex() - 1;
        uint256 amount = TOKEN_SUPPLY / 6;
        uint256 accountIndex = 0;
        address account = address(1);
        bytes32[] memory merkleProof = merkle.getProof(data, 0);

        // Claim tokens
        IMerkleDistributor.Claim memory claim = IMerkleDistributor.Claim({
            windowIndex: windowIndex,
            amount: amount,
            accountIndex: accountIndex,
            account: account,
            merkleProof: merkleProof
        });
        distributor.claim(claim);

        // Check balances updated
        assertEq(token.balanceOf(account), amount);
        assertEq(token.balanceOf(address(distributor)), TOKEN_SUPPLY - amount);

        // Check isClaimed updated
        assertTrue(distributor.isClaimed(windowIndex, accountIndex));
    }

    function testClaimMulti() public {
        // Create window
        distributor.setWindow(TOKEN_SUPPLY, address(token), root, IPFS_HASH);

        // Claims info
        uint256 windowIndex = distributor.nextCreatedIndex() - 1;

        IMerkleDistributor.Claim[] memory claims = new IMerkleDistributor.Claim[](3);
        claims[0] = (
            IMerkleDistributor.Claim({
                windowIndex: windowIndex,
                amount: TOKEN_SUPPLY / 6,
                accountIndex: 0,
                account: address(1),
                merkleProof: merkle.getProof(data, 0)
            })
        );

        claims[1] = (
            IMerkleDistributor.Claim({
                windowIndex: windowIndex,
                amount: TOKEN_SUPPLY / 3,
                accountIndex: 1,
                account: address(2),
                merkleProof: merkle.getProof(data, 1)
            })
        );

        claims[2] = (
            IMerkleDistributor.Claim({
                windowIndex: windowIndex,
                amount: TOKEN_SUPPLY / 2,
                accountIndex: 2,
                account: address(3),
                merkleProof: merkle.getProof(data, 2)
            })
        );

        // Claim tokens
        distributor.claimMulti(claims);

        // Check balances updated
        assertEq(token.balanceOf(address(1)), TOKEN_SUPPLY / 6);
        assertEq(token.balanceOf(address(2)), TOKEN_SUPPLY / 3);
        assertEq(token.balanceOf(address(3)), TOKEN_SUPPLY / 2);

        // Check isClaimed updated
        assertTrue(distributor.isClaimed(windowIndex, 0));
        assertTrue(distributor.isClaimed(windowIndex, 1));
        assertTrue(distributor.isClaimed(windowIndex, 2));
    }

    function testIsClaimed() public {
        // Create window
        distributor.setWindow(TOKEN_SUPPLY, address(token), root, IPFS_HASH);

        // Claim info
        uint256 windowIndex = distributor.nextCreatedIndex() - 1;
        uint256 amount = TOKEN_SUPPLY / 6;
        uint256 accountIndex = 0;
        address account = address(1);
        bytes32[] memory merkleProof = merkle.getProof(data, 0);

        // Ensure not claimed initially
        assertTrue(!distributor.isClaimed(windowIndex, accountIndex));

        // Claim tokens
        IMerkleDistributor.Claim memory claim = IMerkleDistributor.Claim({
            windowIndex: windowIndex,
            amount: amount,
            accountIndex: accountIndex,
            account: account,
            merkleProof: merkleProof
        });
        distributor.claim(claim);

        // Check balances updated
        assertEq(token.balanceOf(account), amount);
        assertEq(token.balanceOf(address(distributor)), TOKEN_SUPPLY - amount);

        // Check isClaimed updated
        assertTrue(distributor.isClaimed(windowIndex, accountIndex));
    }

    function testGetRewardTokenForWindow(uint256 anyWindowIndex) public {
        // Ensure initial token is not set for any window
        assertEq(distributor.getRewardTokenForWindow(anyWindowIndex), address(0));

        // Create window
        distributor.setWindow(TOKEN_SUPPLY, address(token), root, IPFS_HASH);

        // Ensure token is set correctly for window 0
        assertEq(distributor.getRewardTokenForWindow(0), address(token));

        // Create new token
        IERC20 altToken = new ERC20Mock("Token", "TKN", address(this), TOKEN_SUPPLY);
        altToken.approve(address(distributor), TOKEN_SUPPLY);

        // Create second window with new token (reuse old root & hash)
        distributor.setWindow(TOKEN_SUPPLY, address(altToken), root, IPFS_HASH);

        // Ensure token is set correctly for new window
        assertEq(distributor.getRewardTokenForWindow(1), address(altToken));
    }

    function testVerifyClaim() public {
        // Create window
        distributor.setWindow(TOKEN_SUPPLY, address(token), root, IPFS_HASH);

        // Claim info
        uint256 windowIndex = distributor.nextCreatedIndex() - 1;
        uint256 amount = TOKEN_SUPPLY / 6;
        uint256 accountIndex = 0;
        address account = address(1);
        bytes32[] memory merkleProof = merkle.getProof(data, 0);

        // Ensure true claim is valid
        IMerkleDistributor.Claim memory claim = IMerkleDistributor.Claim({
            windowIndex: windowIndex,
            amount: amount,
            accountIndex: accountIndex,
            account: account,
            merkleProof: merkleProof
        });
        assertTrue(distributor.verifyClaim(claim));

        // Ensure invalid amount in claim returns false
        IMerkleDistributor.Claim memory falseAmountClaim = IMerkleDistributor.Claim({
            windowIndex: windowIndex,
            amount: 0,
            accountIndex: accountIndex,
            account: account,
            merkleProof: merkleProof
        });
        assertTrue(!distributor.verifyClaim(falseAmountClaim));

        // Ensure invalid window in claim returns false
        IMerkleDistributor.Claim memory falseWindowIndexClaim = IMerkleDistributor.Claim({
            windowIndex: 100,
            amount: amount,
            accountIndex: accountIndex,
            account: account,
            merkleProof: merkleProof
        });
        assertTrue(!distributor.verifyClaim(falseWindowIndexClaim));

        // Ensure invalid accountIndex in claim returns false
        IMerkleDistributor.Claim memory falseAccountIndexClaim = IMerkleDistributor.Claim({
            windowIndex: windowIndex,
            amount: amount,
            accountIndex: 100,
            account: account,
            merkleProof: merkleProof
        });
        assertTrue(!distributor.verifyClaim(falseAccountIndexClaim));

        // Ensure invalid account in claim returns false
        IMerkleDistributor.Claim memory falseAccountClaim = IMerkleDistributor.Claim({
            windowIndex: windowIndex,
            amount: amount,
            accountIndex: accountIndex,
            account: address(100),
            merkleProof: merkleProof
        });
        assertTrue(!distributor.verifyClaim(falseAccountClaim));

        // Ensure invalid account in claim returns false
        IMerkleDistributor.Claim memory falseProofClaim = IMerkleDistributor.Claim({
            windowIndex: windowIndex,
            amount: amount,
            accountIndex: accountIndex,
            account: account,
            merkleProof: merkle.getProof(data, 1)
        });
        assertTrue(!distributor.verifyClaim(falseProofClaim));
    }
}
