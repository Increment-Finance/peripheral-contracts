// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.16;

import "increment-protocol/interfaces/IVault.sol";
import "increment-protocol/interfaces/IUA.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract Helper {
    IUA public ua;
    IVault public vault;

    constructor(IUA _ua, IVault _vault) {
        ua = _ua;
        vault = _vault;
    }
}
