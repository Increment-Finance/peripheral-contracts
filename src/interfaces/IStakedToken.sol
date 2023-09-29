// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.16;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

interface IStakedToken is IERC20Metadata {
    event Staked(
        address indexed from,
        address indexed onBehalfOf,
        uint256 amount
    );
    event Redeem(address indexed from, address indexed to, uint256 amount);
    event Cooldown(address indexed user);

    function stake(address onBehalfOf, uint256 amount) external;

    function redeem(address to, uint256 amount) external;

    function cooldown() external;
}
