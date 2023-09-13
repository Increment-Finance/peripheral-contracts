// SPDX-License-Identifier: AGPL-3.0

pragma solidity 0.8.16;

import "forge-std/Script.sol";
import "forge-std/Test.sol";
import "solidity-stringutils/strings.sol";
import "murky/src/Merkle.sol";

contract MerkleGenerator is Script, Test {
    using strings for *;

    bytes32[] public treeData;
    Merkle public merkle;
    uint256 public totalAmount = 0;
    string public csvPath;

    constructor(string memory _csvPath) {
        merkle = new Merkle();

        string memory projectRoot = vm.projectRoot();
        csvPath = string(abi.encodePacked(projectRoot, "/", _csvPath));

        // Convert to merkle root data
        uint256 i = 0;

        while (true) {
            try vm.readLine(csvPath) returns (string memory line) {
                if (bytes(line).length == 0) break;

                (address receiver, uint256 amount) = _parseClaim(line);
                totalAmount += amount;

                treeData.push(keccak256(abi.encodePacked(receiver, amount, i)));
                i++;
            } catch {
                break;
            }
        }

        vm.closeFile(csvPath);
    }

    function stringToUint(string memory numString) public pure returns (uint256) {
        uint256 val = 0;
        bytes memory stringBytes = bytes(numString);
        for (uint256 i = 0; i < stringBytes.length; i++) {
            uint256 exp = stringBytes.length - i;
            bytes1 ival = stringBytes[i];
            uint8 uval = uint8(ival);
            uint256 jval = uval - uint256(0x30);

            val += (uint256(jval) * (10 ** (exp - 1)));
        }
        return val;
    }

    function getClaimData(uint256 claimId) public returns (address receiver, uint256 amount) {
        for (uint256 i = 0; i < claimId; i++) {
            vm.readLine(csvPath);
        }

        (receiver, amount) = _parseClaim(vm.readLine(csvPath));
        vm.closeFile(csvPath);
    }

    function getTreeData() public view returns (bytes32[] memory) {
        return treeData;
    }

    function getMerkleRoot() public view returns (bytes32) {
        return merkle.getRoot(treeData);
    }

    function getMerkleProof(uint256 id) public view returns (bytes32[] memory) {
        return merkle.getProof(treeData, id);
    }

    function _parseClaim(string memory claim) internal returns (address receiver, uint256 amount) {
        // Parse csv values
        strings.slice memory slice = claim.toSlice();
        strings.slice memory delim = ",".toSlice();
        string[2] memory data = [slice.split(delim).toString(), slice.split(delim).toString()];

        // Convert utf-8 encoded string to address
        string[] memory inputs = new string[](3);
        inputs[0] = "echo";
        inputs[1] = "-n";
        inputs[2] = data[0];
        receiver = address(bytes20(vm.ffi(inputs)));

        // Convert utf-8 encoded string to uint256
        amount = stringToUint(data[1]);
    }
}
