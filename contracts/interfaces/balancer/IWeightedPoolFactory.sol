// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "./IVault.sol";

interface IBaseSplitCodeFactory {
    function getCreationCodeContracts()
        external
        view
        returns (address contractA, address contractB);

    function getCreationCode() external view returns (bytes memory);
}

interface IBasePoolFactory is IAuthentication, IBaseSplitCodeFactory {
    function isPoolFromFactory(address pool) external view returns (bool);

    function isDisabled() external view returns (bool);

    function disable() external;

    function getVault() external view returns (IVault);

    function getAuthorizer() external view returns (IAuthorizer);
}

interface IWeightedPoolFactory is IBasePoolFactory {
    function create(
        string memory name,
        string memory symbol,
        address[] memory tokens,
        uint256[] memory normalizedWeights,
        address[] memory rateProviders,
        uint256 swapFeePercentage,
        address owner,
        bytes32 salt
    ) external returns (address);
}
