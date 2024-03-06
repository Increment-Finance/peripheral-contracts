// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.16;

import {IERC20Metadata, IERC20} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {ISafetyModule} from "./ISafetyModule.sol";
import {ISMRewardDistributor} from "./ISMRewardDistributor.sol";

/// @title IStakedToken
/// @author webthethird
/// @notice Interface for the StakedToken contract
interface IStakedToken is IERC20Metadata {
    /* ****************** */
    /*       Events       */
    /* ****************** */

    /// @notice Emitted when tokens are staked
    /// @param from Address of the user that staked tokens
    /// @param onBehalfOf Address of the user that tokens were staked on behalf of
    /// @param amount Amount of underlying tokens staked
    event Staked(address indexed from, address indexed onBehalfOf, uint256 amount);

    /// @notice Emitted when tokens are redeemed
    /// @param from Address of the user that redeemed tokens
    /// @param to Address where redeemed tokens were sent to
    /// @param amount Amount of staked tokens redeemed
    event Redeemed(address indexed from, address indexed to, uint256 amount);

    /// @notice Emitted when the cooldown period is started
    /// @param user Address of the user that started the cooldown period
    event Cooldown(address indexed user);

    /// @notice Emitted when tokens are slashed
    /// @param destination Address where slashed underlying tokens were sent to
    /// @param stakeAmount Amount of staked tokens slashed
    /// @param underlyingAmount Amount of underlying tokens sent to the destination
    event Slashed(address indexed destination, uint256 stakeAmount, uint256 underlyingAmount);

    /// @notice Emitted when staking, slashing and cooldown are re-enabled after a slashing event is concluded
    event SlashingSettled();

    /// @notice Emitted when underlying tokens are returned to the contract
    /// @param from Address where underlying tokens were transferred from
    /// @param amount Amount of underlying tokens returned
    event FundsReturned(address indexed from, uint256 amount);

    /// @notice Emitted when the exchange rate is updated
    /// @param exchangeRate New exchange rate, denominated in underlying per staked token, normalized to 1e18
    event ExchangeRateUpdated(uint256 exchangeRate);

    /// @notice Emitted when the SafetyModule contract is updated by governance
    /// @param oldSafetyModule Address of the old SafetyModule contract
    /// @param newSafetyModule Address of the new SafetyModule contract
    event SafetyModuleUpdated(address oldSafetyModule, address newSafetyModule);

    /// @notice Emitted when the max amount of staked tokens allowed per user is updated by governance
    /// @param oldMaxStakeAmount Old max stake amount
    /// @param newMaxStakeAmount New max stake amount
    event MaxStakeAmountUpdated(uint256 oldMaxStakeAmount, uint256 newMaxStakeAmount);

    /* ****************** */
    /*       Errors       */
    /* ****************** */

    /// @notice Error returned when 0 amount is passed to a function that expects a non-zero amount
    error StakedToken_InvalidZeroAmount();

    /// @notice Error returned when the zero address is passed to a function that expects a non-zero address
    error StakedToken_InvalidZeroAddress();

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

    /// @notice Error returned when the caller tries to stake on behalf of a user who has staked already
    /// @dev Required to prevent griefing stakers by forcing them to accrue rewards at a lower multiplier
    error StakedToken_NoStakingOnBehalfOfExistingStaker();

    /// @notice Error returned when the caller tries to redeem before the cooldown period is over
    /// @param cooldownEndTimestamp Timestamp when the cooldown period ends
    error StakedToken_InsufficientCooldown(uint256 cooldownEndTimestamp);

    /// @notice Error returned when the caller tries to redeem after the unstake window is over
    /// @param unstakeWindowEndTimestamp Timestamp when the unstake window ended
    error StakedToken_UnstakeWindowFinished(uint256 unstakeWindowEndTimestamp);

    /// @notice Error returned when the caller tries to stake more than the max stake amount
    /// @param maxStakeAmount Maximum allowed amount to stake
    /// @param maxAmountMinusBalance Amount that the user can still stake without exceeding the max stake amount
    error StakedToken_AboveMaxStakeAmount(uint256 maxStakeAmount, uint256 maxAmountMinusBalance);

    /// @notice Error returned when a caller other than the SafetyModule tries to call a restricted function
    /// @param caller Address of the caller
    error StakedToken_CallerIsNotSafetyModule(address caller);

    /* ***************** */
    /*    Public Vars    */
    /* ***************** */

    /// @notice Address of the SafetyModule contract
    /// @return SafetyModule contract
    function safetyModule() external view returns (ISafetyModule);

    /// @notice Address of the SafetyModule's RewardDistributor contract
    /// @return SMRewardDistributor contract
    function smRewardDistributor() external view returns (ISMRewardDistributor);

    /// @notice Max amount of staked tokens allowed per user
    /// @return Max balance allowed per user
    function maxStakeAmount() external view returns (uint256);

    /// @notice Exchange rate between the underlying token and the staked token
    /// @return Ratio of underlying tokens held in this contract per staked token issued, normalized to 1e18
    function exchangeRate() external view returns (uint256);

    /* ***************** */
    /*       Views       */
    /* ***************** */

    /// @notice Returns the underlying ERC20 token
    /// @return Underlying ERC20 token
    function getUnderlyingToken() external view returns (IERC20);

    /// @notice Returns the length of the cooldown period
    /// @return Number of seconds in the cooldown period
    function getCooldownSeconds() external view returns (uint256);

    /// @notice Returns the length of the unstake window
    /// @return Number of seconds in the unstake window
    function getUnstakeWindowSeconds() external view returns (uint256);

    /// @notice Returns the start time of the latest cooldown period for a given user
    /// @param user Address of the user
    /// @return Timestamp when the user's latest cooldown period started
    function getCooldownStartTime(address user) external view returns (uint256);

    /// @notice Returns whether the contract is in a post-slashing state
    /// @dev In a post-slashing state, staking and slashing are disabled, and users can redeem without cooldown
    /// @return True if the contract is in a post-slashing state, false otherwise
    function isInPostSlashingState() external view returns (bool);

    /// @notice Returns the amount of staked tokens one would receive for staking an amount of underlying tokens
    /// @param amountToStake Amount of underlying tokens to stake
    /// @return Amount of staked tokens that would be received at the current exchange rate
    function previewStake(uint256 amountToStake) external view returns (uint256);

    /// @notice Returns the amount of underlying tokens one would receive for redeeming an amount of staked tokens
    /// @param amountToRedeem Amount of staked tokens to redeem
    /// @return Amount of underlying tokens that would be received at the current exchange rate
    function previewRedeem(uint256 amountToRedeem) external view returns (uint256);

    /// @notice Calculates a new cooldown timestamp
    /// @dev Calculation depends on the sender/receiver situation, as follows:
    ///  - If the timestamp of the sender is "better" or the timestamp of the recipient is 0, we take the one of the recipient
    ///  - Weighted average of from/to cooldown timestamps if:
    ///    - The sender doesn't have the cooldown activated (timestamp 0).
    ///    - The sender timestamp is expired
    ///    - The sender has a "worse" timestamp
    ///  - If the receiver's cooldown timestamp expired (too old), the next is 0
    /// @param fromCooldownTimestamp Cooldown timestamp of the sender
    /// @param amountToReceive Amount of staked tokens to receive
    /// @param toAddress Address of the recipient
    /// @param toBalance Current balance of the receiver
    /// @return The new cooldown timestamp
    function getNextCooldownTimestamp(
        uint256 fromCooldownTimestamp,
        uint256 amountToReceive,
        address toAddress,
        uint256 toBalance
    ) external view returns (uint256);

    /* ****************** */
    /*   External Users   */
    /* ****************** */

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

    /* ****************** */
    /*    SafetyModule    */
    /* ****************** */

    /// @notice Sends underlying tokens to the given address, lowers the exchange rate accordingly, and
    /// changes the contract's state to `POST_SLASHING`, which disables staking, cooldown period and
    /// further slashing until the state is returned to `RUNNING`
    /// @param destination Address to send the slashed underlying tokens to
    /// @param amount Amount of staked tokens to slash
    /// @return Amount of underlying tokens slashed
    function slash(address destination, uint256 amount) external returns (uint256);

    /// @notice Transfers underlying tokens from the given address to this contract and increases the
    /// exchange rate accordingly
    /// @dev The `from` address must have approved this contract to transfer the tokens
    /// @param from Address to transfer tokens from
    /// @param amount Amount of underlying tokens to transfer
    function returnFunds(address from, uint256 amount) external;

    /// @notice Sets `isInPostSlashingState` to false, which re-enables staking, slashing and cooldown period
    function settleSlashing() external;

    /// @notice Updates the stored SMRewardDistributor contract
    /// @param _newRewardDistributor Address of the new SMRewardDistributor contract
    function setRewardDistributor(ISMRewardDistributor _newRewardDistributor) external;

    /* ****************** */
    /*     Governance     */
    /* ****************** */

    /// @notice Changes the SafetyModule contract used for reward management
    /// @param _newSafetyModule Address of the new SafetyModule contract
    function setSafetyModule(address _newSafetyModule) external;

    /// @notice Sets the max amount of staked tokens allowed per user
    /// @param _newMaxStakeAmount New max amount of staked tokens allowed per user
    function setMaxStakeAmount(uint256 _newMaxStakeAmount) external;

    /// @notice Pauses staking and transferring of staked tokens
    function pause() external;

    /// @notice Unpauses staking and transferring of staked tokens
    function unpause() external;
}
