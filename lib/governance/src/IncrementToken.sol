// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.16;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/draft-ERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

contract IncrementToken is ERC20, Pausable, AccessControl, ERC20Permit, ERC20Votes {
    bytes32 public constant OWNER_ROLE = keccak256("OWNER_ROLE");
    bytes32 public constant DISTRIBUTOR_ROLE = keccak256("DISTRIBUTOR_ROLE");

    constructor(uint256 initialSupply, address owner) ERC20("Increment", "INCR") ERC20Permit("Increment") {
        // Set owner
        _grantRole(OWNER_ROLE, owner);
        _setRoleAdmin(OWNER_ROLE, OWNER_ROLE);
        _setRoleAdmin(DISTRIBUTOR_ROLE, OWNER_ROLE);

        // Mint initial supply
        _mint(owner, initialSupply);

        // Contract is paused by default
        _pause();
    }

    function _beforeTokenTransfer(address from, address to, uint256 amount) internal override {
        super._beforeTokenTransfer(from, to, amount);

        // Cannot transfer while paused except from the owner of the contract
        require(
            !paused() || hasRole(OWNER_ROLE, _msgSender()) || hasRole(DISTRIBUTOR_ROLE, _msgSender()),
            "INCR: Cannot transfer while paused"
        );
    }

    function _afterTokenTransfer(address from, address to, uint256 amount) internal override(ERC20, ERC20Votes) {
        super._afterTokenTransfer(from, to, amount);
    }

    function _mint(address to, uint256 amount) internal override(ERC20, ERC20Votes) {
        super._mint(to, amount);
    }

    function _burn(address account, uint256 amount) internal override(ERC20, ERC20Votes) {
        super._burn(account, amount);
    }

    function unpause() public onlyRole(OWNER_ROLE) {
        _unpause();
    }
}
