// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.20;

/**
 * @title ISimulator
 * @author webthethird
 * @notice Interface to allow simulating calls to other contracts and revert execution from view functions.
 * @dev Based on https://github.com/gnosis/util-contracts/blob/main/contracts/storage/StorageSimulation.sol
 */
interface ISimulator {
    /**
     * @dev Performs a call on a targetContract and internally reverts execution to avoid side effects (making it static).
     *
     * This method reverts with data equal to `abi.encode(bool(success), bytes(response))`.
     * Specifically, the `returndata` after a call to this method will be:
     * `success:bool || response.length:uint256 || response:bytes`.
     *
     * @param targetContract Address of the contract to simulate the call to.
     * @param calldataPayload Calldata that should be sent to the target contract (encoded method name and arguments).
     */
    function simulateAndRevert(address targetContract, bytes memory calldataPayload) external view;
}
