// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.16;

import "forge-std/Test.sol";
import "../src/IncrementToken.sol";

contract IncrementTokenHarness is IncrementToken {
    constructor(uint256 initialSupply, address owner) IncrementToken(initialSupply, owner) {}

    function exposed_mint(address to, uint256 amount) public {
        super._mint(to, amount);
    }

    function exposed_burn(address to, uint256 amount) public {
        super._burn(to, amount);
    }
}

contract IncrementTokenTest is Test {
    uint256 public constant TOKEN_SUPPLY = 1_000_000 ether;
    IncrementToken public token;

    function setUp() public {
        token = new IncrementToken(TOKEN_SUPPLY, address(this));
    }

    function testConstructor() public {
        // Ensure token data is set correctly
        assertEq(token.name(), "Increment");
        assertEq(token.symbol(), "INCR");
        assertEq(token.totalSupply(), TOKEN_SUPPLY);
        assertEq(token.balanceOf(address(this)), TOKEN_SUPPLY);
        assertTrue(token.paused());

        // Ensure roles are initialized correctly
        assertTrue(token.hasRole(token.OWNER_ROLE(), address(this)));
        assertEq(token.getRoleAdmin(token.OWNER_ROLE()), token.OWNER_ROLE());
        assertEq(token.getRoleAdmin(token.DISTRIBUTOR_ROLE()), token.OWNER_ROLE());
    }

    function testOwnerTransferWhilePaused(uint256 amount, address to) public {
        // Ensure receiver is not this contract, the zero address or the token address
        vm.assume(to != address(this) && to != address(0) && to != address(token));
        vm.assume(amount < TOKEN_SUPPLY && amount > 0);

        // Can transfer with owner role
        token.transfer(to, amount);
    }

    function testDistributorTransferWhilePaused(uint256 amount, address to, address distributor) public {
        // Ensure receiver is not this contract, the zero address or the token address
        vm.assume(to != address(this) && to != address(0) && to != address(token));
        vm.assume(distributor != address(this) && distributor != address(0) && distributor != address(token));
        vm.assume(amount < TOKEN_SUPPLY && amount > 0);

        // Grant distributor role
        token.grantRole(token.DISTRIBUTOR_ROLE(), distributor);

        // Fund distributor
        token.transfer(distributor, amount);

        // Can transfer with distributor role
        vm.prank(distributor);
        token.transfer(to, amount);
    }

    function testFailNoRoleTransferWhilePaused(uint256 amount, address to, address alice, address bob) public {
        // Ensure addresses are not this contract, the zero address or the token address
        vm.assume(to != address(this) && to != address(0) && to != address(token));
        vm.assume(alice != address(this) && alice != address(0) && alice != address(token));
        vm.assume(bob != address(this) && bob != address(0) && bob != address(token));
        vm.assume(amount < TOKEN_SUPPLY && amount > 0);

        // Fund alice
        token.transfer(alice, amount);
        vm.prank(alice);

        // Attempt transfer (should fail)
        token.transfer(bob, amount);
    }

    function testTransferWhileUnpaused(uint256 amount, address user, address to) public {
        // Ensure addresses are not this contract, the zero address or the token address
        vm.assume(user != address(this) && user != address(0) && user != address(token));
        vm.assume(to != address(this) && to != address(0) && to != address(token));
        vm.assume(amount < TOKEN_SUPPLY && amount > 0);

        // Unpause contract
        token.unpause();

        // Fund user
        token.transfer(user, amount);
        vm.prank(user);

        // Test transfer
        token.transfer(to, amount);
    }

    function testOwnerPauseUnpause() public {
        // Ensure owner can unpause
        token.unpause();
    }

    function testFailDistributorUnpause(address distributor) public {
        // Ensure distributor is not this contract, the zero address or the token address
        vm.assume(distributor != address(this) && distributor != address(0) && distributor != address(token));

        // Grant distributor role
        token.grantRole(token.DISTRIBUTOR_ROLE(), distributor);

        // Attempt to upause as distributor (should fail)
        vm.prank(distributor);
        token.unpause();
    }

    function testFailNoRoleUnpause(address user) public {
        // Ensure user is not this contract, the zero address or the token address
        vm.assume(user != address(this) && user != address(0) && user != address(token));

        // Attempt to upause as user (should fail)
        vm.prank(user);
        token.unpause();
    }

    function testMint() public {
        // Deploy token harness to test internal functions
        IncrementTokenHarness tokenHarness = new IncrementTokenHarness(0, address(this));

        // Ensure initial balance is 0
        assertEq(tokenHarness.balanceOf(address(this)), 0);
        assertEq(tokenHarness.totalSupply(), 0);

        // Mint tokens
        tokenHarness.exposed_mint(address(this), TOKEN_SUPPLY);

        // Ensure balance updated
        assertEq(tokenHarness.balanceOf(address(this)), TOKEN_SUPPLY);
        assertEq(tokenHarness.totalSupply(), TOKEN_SUPPLY);
    }

    function testBurn() public {
        // Deploy token harness to test internal functions
        IncrementTokenHarness tokenHarness = new IncrementTokenHarness(TOKEN_SUPPLY, address(this));

        // Ensure initial balance is TOKEN_SUPPLY
        assertEq(tokenHarness.balanceOf(address(this)), TOKEN_SUPPLY);
        assertEq(tokenHarness.totalSupply(), TOKEN_SUPPLY);

        // Burn all tokens
        tokenHarness.exposed_burn(address(this), TOKEN_SUPPLY);

        // Ensure balance updated
        assertEq(tokenHarness.balanceOf(address(this)), 0);
        assertEq(tokenHarness.totalSupply(), 0);
    }
}
