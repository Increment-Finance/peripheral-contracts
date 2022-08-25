// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/Helper.sol";
import "increment-protocol/interfaces/IVault.sol";
import "increment-protocol/interfaces/IUA.sol";

contract HelperTest is Test {
    IUA constant UA = IUA(0x0000000000000000000000000000000000000001);
    IVault constant VAULT = IVault(0x0000000000000000000000000000000000000002);

    Helper public helper;

    function setUp() public {
       helper = new Helper(UA, VAULT);
    }

    function testConstructor() public {
        assertEq(address(helper.ua()), address(UA));
        assertEq(address(helper.vault()), address(VAULT));
    }
}
