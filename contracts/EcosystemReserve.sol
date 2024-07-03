// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.16;

import "./AdminControlledEcosystemReserve.sol";

/// @title EcosystemReserve
/// @author webthethird
/// @notice Stores ERC20 tokens, and allows to dispose of them via approval or transfer dynamics
/// @dev Inherits from Aave's AdminControlledEcosystemReserve by BGD Labs, but with a transferable admin
/// and a constructor, as it is not intended to be used as a transparent proxy implementation
contract EcosystemReserve is AdminControlledEcosystemReserve {
    /// @notice Error returned when trying to set the admin to the zero address
    error EcosystemReserve_InvalidAdmin();

    /// @notice EcosystemReserve constructor
    /// @param fundsAdmin Address of the admin who can approve or transfer tokens from the reserve
    constructor(address fundsAdmin) {
        _setFundsAdmin(fundsAdmin);
    }

    /// @notice Sets the admin of the EcosystemReserve
    /// @dev Only callable by the current admin
    /// @param newAdmin Address of the new admin
    function transferAdmin(address newAdmin) external onlyFundsAdmin {
        if (newAdmin == address(0)) revert EcosystemReserve_InvalidAdmin();
        _setFundsAdmin(newAdmin);
    }
}
