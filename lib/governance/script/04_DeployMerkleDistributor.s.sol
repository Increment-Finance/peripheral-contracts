// SPDX-License-Identifier: AGPL-3.0

pragma solidity 0.8.16;

import "forge-std/Script.sol";
import "../src/IncrementToken.sol";
import "../src/MerkleDistributor.sol";
import "./MerkleGenerator.s.sol";
import {TOKEN_SUPPLY, MULTI_SIG, MERKLE_TREE_IPFS_HASH} from "./Constants.sol";

contract DeployMerkleDistributor is Script {
    function run() public returns (MerkleDistributor merkleDistributor, MerkleGenerator merkleGenerator) {
        IncrementToken token = IncrementToken(vm.envAddress("TOKEN"));
        address timelock = vm.envAddress("TIMELOCK");

        string memory csvPath = vm.envString("CSV_PATH");

        merkleGenerator = new MerkleGenerator(csvPath);
        bytes32 root = merkleGenerator.getMerkleRoot();
        vm.startBroadcast(MULTI_SIG);

        // Deploy Merkle Distributor
        merkleDistributor = new MerkleDistributor();
        token.approve(address(merkleDistributor), merkleGenerator.totalAmount());
        token.grantRole(token.DISTRIBUTOR_ROLE(), address(merkleDistributor));
        merkleDistributor.setWindow(merkleGenerator.totalAmount(), address(token), root, MERKLE_TREE_IPFS_HASH);

        // Transfer MerkleDistribution ownership to Timelock
        merkleDistributor.transferOwnership(address(timelock));
        vm.stopBroadcast();
    }
}
