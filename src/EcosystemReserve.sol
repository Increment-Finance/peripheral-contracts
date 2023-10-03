// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.16;

import "@aave-periphery/treasury/AdminControlledEcosystemReserve.sol";

contract EcosystemReserve is AdminControlledEcosystemReserve {
    error InvalidAdmin();

    constructor(address fundsAdmin) {
        _setFundsAdmin(fundsAdmin);
    }

    function transferAdmin(address newAdmin) external onlyFundsAdmin {
        if (newAdmin == address(0)) revert InvalidAdmin();
        _setFundsAdmin(newAdmin);
    }
}
