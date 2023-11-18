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
    /// @param amount Amount of underlying tokens staked
    event Staked(
        address indexed from,
        address indexed onBehalfOf,
        uint256 amount
    );

    /// @notice Emitted when tokens are redeemed
    /// @param from Address of the user that redeemed tokens
    /// @param to Address where redeemed tokens were sent to
    /// @param amount Amount of staked tokens redeemed
    event Redeem(address indexed from, address indexed to, uint256 amount);

    /// @notice Emitted when the cooldown period is started
    /// @param user Address of the user that started the cooldown period
    event Cooldown(address indexed user);

    /// @notice Error returned when 0 amount is passed to stake or redeem functions
    error StakedToken_InvalidZeroAmount();

    /// @notice Error returned when the caller has no balance when calling `cooldown`
    error StakedToken_ZeroBalanceAtCooldown();

    /// @notice Error returned when the caller tries to stake or redeem tokens when the exchange rate is 0
    /// @dev This can only happen if 100% of the underlying tokens have been slashed by the SafetyModule,
    /// which should never occur in practice because the SafetyModule can only slash `maxPercentUserLoss`
    error StakedToken_ZeroExchangeRate();

    /// @notice Error returned when the caller tries to stake while the contract is in a post-slashing state
    error StakedToken_StakingDisabledInPostSlashingState();

    /// @notice Error returned when the caller tries to slash while the contract is in a post-slashing state
    error StakedToken_SlashingDisabledInPostSlashingState();

    /// @notice Error returned when the caller tries to activate the cooldown period while the contract is
    /// in a post-slashing state
    /// @dev In a post-slashing state, users can redeem without waiting for the cooldown period
    error StakedToken_CooldownDisabledInPostSlashingState();

    /// @notice Error returned when the caller tries to redeem before the cooldown period is over
    /// @param cooldownEndTimestamp Timestamp when the cooldown period ends
    error StakedToken_InsufficientCooldown(uint256 cooldownEndTimestamp);

    /// @notice Error returned when the caller tries to redeem after the unstake window is over
    /// @param unstakeWindowEndTimestamp Timestamp when the unstake window ended
    error StakedToken_UnstakeWindowFinished(uint256 unstakeWindowEndTimestamp);

    /// @notice Error returned when the caller tries to stake more than the max stake amount
    /// @param maxStakeAmount Maximum allowed amount to stake
    /// @param maxAmountMinusBalance Amount that the user can still stake without exceeding the max stake amount
    error StakedToken_AboveMaxStakeAmount(
        uint256 maxStakeAmount,
        uint256 maxAmountMinusBalance
    );

    /// @notice Error returned when a caller other than the SafetyModule tries to call a restricted function
    /// @param caller Address of the caller
    error StakedToken_CallerIsNotSafetyModule(address caller);

    /// @notice Returns the amount of staked tokens one would receive for staking an amount of underlying tokens
    /// @param amountToStake Amount of underlying tokens to stake
    /// @return Amount of staked tokens that would be received at the current exchange rate
    function previewStake(
        uint256 amountToStake
    ) external view returns (uint256);

    /// @notice Returns the amount of underlying tokens one would receive for redeeming an amount of staked tokens
    /// @param amountToRedeem Amount of staked tokens to redeem
    /// @return Amount of underlying tokens that would be received at the current exchange rate
    function previewRedeem(
        uint256 amountToRedeem
    ) external view returns (uint256);

    /// @notice Stakes tokens from the sender and starts earning rewards
    /// @param amount Amount of underlying tokens to stake
    function stake(uint256 amount) external;

    /// @notice Stakes tokens on behalf of the given address, and starts earning rewards
    /// @dev Tokens are transferred from the transaction sender, not from the `onBehalfOf` address
    /// @param onBehalfOf Address to stake on behalf of
    /// @param amount Amount of underlying tokens to stake
    function stakeOnBehalfOf(address onBehalfOf, uint256 amount) external;

    /// @notice Redeems staked tokens, and stop earning rewards
    /// @param amount Amount of staked tokens to redeem for underlying tokens
    function redeem(uint256 amount) external;

    /// @notice Redeems staked tokens, and stop earning rewards
    /// @dev Staked tokens are redeemed from the sender, and underlying tokens are sent to the `to` address
    /// @param to Address to redeem to
    /// @param amount Amount of staked tokens to redeem for underlying tokens
    function redeemTo(address to, uint256 amount) external;

    /// @notice Activates the cooldown period to unstake
    /// @dev Can't be called if the user is not staking
    function cooldown() external;

    /// @notice Changes the SafetyModule contract used for reward management
    /// @param _safetyModule Address of the new SafetyModule contract
    function setSafetyModule(address _safetyModule) external;

    /// @notice Sets the max amount of staked tokens allowed per user
    /// @param _maxStakeAmount New max amount of staked tokens allowed per user
    function setMaxStakeAmount(uint256 _maxStakeAmount) external;
}
