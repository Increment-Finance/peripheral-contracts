// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.16;

import "@openzeppelin/contracts/proxy/Clones.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import "./IncrementVestingWallet.sol";

contract IncrementVestingWalletFactory {
    using Clones for address;

    address public immutable impl;

    // beneficiary => vesting wallet
    mapping(address => address) public vestingWallets;

    constructor(address _impl) {
        impl = _impl;
    }

    function deploy(ERC20Votes _token, address _beneficiaryAddress, uint64 _startTimestamp, uint64 _durationSeconds)
        external
        returns (IncrementVestingWallet vestingWallet)
    {
        vestingWallet = IncrementVestingWallet(payable(impl.clone()));
        vestingWallet.initialize(_token, _beneficiaryAddress, _startTimestamp, _durationSeconds);
        vestingWallets[_beneficiaryAddress] = address(vestingWallet);
    }
}
