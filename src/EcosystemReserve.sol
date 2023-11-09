// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.16;

import "@aave-periphery/treasury/AdminControlledEcosystemReserve.sol";

contract EcosystemReserve is AdminControlledEcosystemReserve {
    /// @notice Error returned when trying to set the admin to the zero address
    error InvalidAdmin();

    constructor(address fundsAdmin) {
        _setFundsAdmin(fundsAdmin);
    }

    /// @notice Sets the admin of the EcosystemReserve
    /// @dev Only callable by the current admin
    /// @param newAdmin Address of the new admin
    function transferAdmin(address newAdmin) external onlyFundsAdmin {
        if (newAdmin == address(0)) revert InvalidAdmin();
        _setFundsAdmin(newAdmin);
    }
}
