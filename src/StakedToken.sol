// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.16;

import {ERC20, ERC20Permit, IERC20} from "@openzeppelin/contracts/token/ERC20/extensions/draft-ERC20Permit.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IncreAccessControl} from "increment-protocol/utils/IncreAccessControl.sol";
import {IStakedToken} from "./interfaces/IStakedToken.sol";
import {ISafetyModule} from "./interfaces/ISafetyModule.sol";

contract StakedToken is
    IStakedToken,
    ERC20Permit,
    IncreAccessControl,
    Pausable,
    ReentrancyGuard
{
    using SafeERC20 for IERC20;

    IERC20 public immutable STAKED_TOKEN;
    uint256 public immutable COOLDOWN_SECONDS;

    /// @notice Seconds available to redeem once the cooldown period is fullfilled
    uint256 public immutable UNSTAKE_WINDOW;

    ISafetyModule public safetyModule;

    /// @notice Max amount of staked tokens allowed per user
    uint256 public maxStakeAmount;

    mapping(address => uint256) public stakersCooldowns;

    constructor(
        IERC20 _stakedToken,
        ISafetyModule _safetyModule,
        uint256 _cooldownSeconds,
        uint256 _unstakeWindow,
        uint256 _maxStakeAmount,
        string memory _name,
        string memory _symbol
    ) ERC20(_name, _symbol) ERC20Permit(_name) {
        STAKED_TOKEN = _stakedToken;
        COOLDOWN_SECONDS = _cooldownSeconds;
        UNSTAKE_WINDOW = _unstakeWindow;
        safetyModule = _safetyModule;
        maxStakeAmount = _maxStakeAmount;
    }

    function stake(address onBehalfOf, uint256 amount) external override {
        if (amount == 0) revert StakedToken_InvalidZeroAmount();
        uint256 balanceOfUser = balanceOf(onBehalfOf);
        if (balanceOfUser + amount > maxStakeAmount)
            revert StakedToken_AboveMaxStakeAmount(
                maxStakeAmount,
                maxStakeAmount - balanceOfUser
            );

        stakersCooldowns[onBehalfOf] = getNextCooldownTimestamp(
            0,
            amount,
            onBehalfOf,
            balanceOfUser
        );

        _mint(onBehalfOf, amount);
        IERC20(STAKED_TOKEN).safeTransferFrom(
            msg.sender,
            address(this),
            amount
        );

        safetyModule.updateStakingPosition(address(this), onBehalfOf);

        emit Staked(msg.sender, onBehalfOf, amount);
    }

    /**
     * @dev Redeems staked tokens, and stop earning rewards
     * @param to Address to redeem to
     * @param amount Amount to redeem
     **/
    function redeem(address to, uint256 amount) external override {
        if (amount == 0) revert StakedToken_InvalidZeroAmount();
        //solium-disable-next-line
        uint256 cooldownStartTimestamp = stakersCooldowns[msg.sender];
        if (block.timestamp < cooldownStartTimestamp + COOLDOWN_SECONDS)
            revert StakedToken_InsufficientCooldown(
                cooldownStartTimestamp + COOLDOWN_SECONDS
            );
        if (
            block.timestamp - cooldownStartTimestamp + COOLDOWN_SECONDS >
            UNSTAKE_WINDOW
        )
            revert StakedToken_UnstakeWindowFinished(
                cooldownStartTimestamp + COOLDOWN_SECONDS + UNSTAKE_WINDOW
            );
        uint256 balanceOfMessageSender = balanceOf(msg.sender);

        uint256 amountToRedeem = (amount > balanceOfMessageSender)
            ? balanceOfMessageSender
            : amount;

        _burn(msg.sender, amountToRedeem);

        if (balanceOfMessageSender - amountToRedeem == 0) {
            stakersCooldowns[msg.sender] = 0;
        }

        IERC20(STAKED_TOKEN).safeTransfer(to, amountToRedeem);

        safetyModule.updateStakingPosition(address(this), msg.sender);

        emit Redeem(msg.sender, to, amountToRedeem);
    }

    /**
     * @dev Activates the cooldown period to unstakeaddress
     * - It can't be called if the user is not staking
     **/
    function cooldown() external override {
        if (balanceOf(msg.sender) == 0)
            revert StakedToken_ZeroBalanceAtCooldown();
        //solium-disable-next-line
        stakersCooldowns[msg.sender] = block.timestamp;

        emit Cooldown(msg.sender);
    }

    /**
     * @dev Calculates a new cooldown timestamp depending on the sender/receiver situation
     *  - If the timestamp of the sender is "better" or the timestamp of the recipient is 0, we take the one of the recipient
     *  - Weighted average of from/to cooldown timestamps if:
     *    # The sender doesn't have the cooldown activated (timestamp 0).
     *    # The sender timestamp is expired
     *    # The sender has a "worse" timestamp
     *  - If the receiver's cooldown timestamp expired (too old), the next is 0
     * @param fromCooldownTimestamp Cooldown timestamp of the sender
     * @param amountToReceive Amount
     * @param toAddress Address of the recipient
     * @param toBalance Current balance of the receiver
     * @return The new cooldown timestamp
     **/
    function getNextCooldownTimestamp(
        uint256 fromCooldownTimestamp,
        uint256 amountToReceive,
        address toAddress,
        uint256 toBalance
    ) public view returns (uint256) {
        uint256 toCooldownTimestamp = stakersCooldowns[toAddress];
        if (toCooldownTimestamp == 0) {
            return 0;
        }

        uint256 minimalValidCooldownTimestamp = block.timestamp -
            COOLDOWN_SECONDS -
            UNSTAKE_WINDOW;

        if (minimalValidCooldownTimestamp > toCooldownTimestamp) {
            toCooldownTimestamp = 0;
        } else {
            fromCooldownTimestamp = (minimalValidCooldownTimestamp >
                fromCooldownTimestamp)
                ? block.timestamp
                : fromCooldownTimestamp;

            if (fromCooldownTimestamp < toCooldownTimestamp) {
                return toCooldownTimestamp;
            } else {
                toCooldownTimestamp =
                    (amountToReceive *
                        fromCooldownTimestamp +
                        (toBalance * toCooldownTimestamp)) /
                    (amountToReceive + toBalance);
            }
        }

        return toCooldownTimestamp;
    }

    /* ****************** */
    /*     Governance     */
    /* ****************** */

    function setSafetyModule(
        address _safetyModule
    ) external onlyRole(GOVERNANCE) {
        safetyModule = ISafetyModule(_safetyModule);
    }

    /// @notice Sets the max amount of staked tokens allowed per user, callable only by governance
    /// @param _maxStakeAmount New max amount of staked tokens allowed per user
    function setMaxStakeAmount(
        uint256 _maxStakeAmount
    ) external onlyRole(GOVERNANCE) {
        maxStakeAmount = _maxStakeAmount;
    }

    /* ****************** */
    /*      Internal      */
    /* ****************** */

    /**
     * @dev Internal ERC20 _transfer of the tokenized staked tokens
     * @param from Address to transfer from
     * @param to Address to transfer to
     * @param amount Amount to transfer
     **/
    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        // Sender
        uint256 balanceOfFrom = balanceOf(from);

        // Recipient
        if (from != to) {
            uint256 balanceOfTo = balanceOf(to);
            if (balanceOfTo + amount > maxStakeAmount)
                revert StakedToken_AboveMaxStakeAmount(
                    maxStakeAmount,
                    maxStakeAmount - balanceOfTo
                );
            uint256 previousSenderCooldown = stakersCooldowns[from];
            stakersCooldowns[to] = getNextCooldownTimestamp(
                previousSenderCooldown,
                amount,
                to,
                balanceOfTo
            );
            // if cooldown was set and whole balance of sender was transferred - clear cooldown
            if (balanceOfFrom == amount && previousSenderCooldown != 0) {
                stakersCooldowns[from] = 0;
            }
        }

        super._transfer(from, to, amount);

        // Update SafetyModule
        safetyModule.updateStakingPosition(address(this), from);
        safetyModule.updateStakingPosition(address(this), to);
    }
}
