// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.16;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

/// @title IStakedToken
/// @author webthethird
/// @notice Interface for the StakedToken contract
interface IStakedToken is IERC20Metadata {
    /// @notice Emitted when tokens are staked
    /// @param from Address of the user that staked tokens
    /// @param onBehalfOf Address of the user that tokens were staked on behalf of
    /// @param amount Amount of tokens staked
    event Staked(
        address indexed from,
        address indexed onBehalfOf,
        uint256 amount
    );

    /// @notice Emitted when tokens are redeemed
    /// @param from Address of the user that redeemed tokens
    /// @param to Address where redeemed tokens were sent to
    /// @param amount Amount of tokens redeemed
    event Redeem(address indexed from, address indexed to, uint256 amount);

    /// @notice Emitted when the cooldown period is started
    /// @param user Address of the user that started the cooldown period
    event Cooldown(address indexed user);

    /// @notice Error returned when 0 amount is passed to stake or redeem functions
    error StakedToken_InvalidZeroAmount();

    /// @notice Error returned when the caller has no balance when calling `cooldown`
    error StakedToken_ZeroBalanceAtCooldown();

    /// @notice Error returned when the caller tries to redeem before the cooldown period is over
    error StakedToken_InsufficientCooldown(uint256 cooldownEndTimestamp);

    /// @notice Error returned when the caller tries to redeem after the unstake window is over
    error StakedToken_UnstakeWindowFinished(uint256 unstakeWindowEndTimestamp);

    /// @notice Stakes tokens on behalf of the given address, and starts earning rewards
    /// @dev Tokens are transferred from the transaction sender, not from the `onBehalfOf` address
    /// @param onBehalfOf Address to stake on behalf of
    /// @param amount Amount of tokens to stake
    function stake(address onBehalfOf, uint256 amount) external;

    /// @notice Redeems staked tokens, and stop earning rewards
    /// @param to Address to redeem to
    /// @param amount Amount to redeem
    function redeem(address to, uint256 amount) external;

    /// @notice Activates the cooldown period to unstake
    /// @dev Can't be called if the user is not staking
    function cooldown() external;

    /// @notice Changes the SafetyModule contract used for reward management
    /// @dev Only callable by Governance
    /// @param _safetyModule Address of the new SafetyModule contract
    function setSafetyModule(address _safetyModule) external;
}
