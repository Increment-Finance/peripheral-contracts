// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.16;

import "@openzeppelin-upgradeable/contracts/finance/VestingWalletUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";

contract IncrementVestingWallet is VestingWalletUpgradeable {
    ERC20Votes private _vestingToken;

    constructor() {
        _disableInitializers();
    }

    function initialize(ERC20Votes token, address beneficiaryAddress, uint64 startTimestamp, uint64 durationSeconds)
        public
        initializer
    {
        __VestingWallet_init(beneficiaryAddress, startTimestamp, durationSeconds);
        _vestingToken = token;
    }

    // @dev Beneficiary can delegate their voting power to a delegatee
    // @param to The address to delegate votes to
    function delegate(address to) public {
        require(
            _msgSender() == beneficiary(), "IncrementVestingWallet: only beneficiary can delegate to another address"
        );
        vestingToken().delegate(to);
    }

    function vestingToken() public view virtual returns (ERC20Votes) {
        return _vestingToken;
    }
}
