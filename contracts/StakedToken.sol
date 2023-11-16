// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.16;

// contracts
import {ERC20, ERC20Permit, IERC20} from "@openzeppelin/contracts/token/ERC20/extensions/draft-ERC20Permit.sol";
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IncreAccessControl} from "increment-protocol/utils/IncreAccessControl.sol";

// interfaces
import {IStakedToken} from "./interfaces/IStakedToken.sol";
import {ISafetyModule} from "./interfaces/ISafetyModule.sol";

// libraries
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {LibMath} from "@increment/lib/LibMath.sol";

/**
 * @title StakedToken
 * @author webthethird
 * @notice Based on Aave's StakedToken, but with reward management outsourced to the SafetyModule
 */
contract StakedToken is
    IStakedToken,
    ERC20Permit,
    IncreAccessControl,
    Pausable,
    ReentrancyGuard
{
    using SafeERC20 for IERC20;
    using LibMath for uint256;

    /// @notice Address of the underlying token to stake
    IERC20 public immutable UNDERLYING_TOKEN;

    /// @notice Seconds that user must wait between calling cooldown and redeem
    uint256 public immutable COOLDOWN_SECONDS;

    /// @notice Seconds available to redeem once the cooldown period is fullfilled
    uint256 public immutable UNSTAKE_WINDOW;

    /// @notice Address of the SafetyModule contract
    ISafetyModule public safetyModule;

    /// @notice Max amount of staked tokens allowed per user
    uint256 public maxStakeAmount;

    /// @notice Exchange rate between the underlying token and the staked token, normalized to 1e18
    /// @dev Rate is the amount of underlying tokens held in this contract per staked token issued, so
    /// it should be 1e18 in normal conditions, when all staked tokens are backed 1:1 by underlying tokens,
    /// but it can be lower if users' stakes have been slashed for an auction by the SafetyModule
    uint256 public exchangeRate;

    /// @notice Timestamp of the start of the current cooldown period for each user
    mapping(address => uint256) public stakersCooldowns;

    /// @notice Modifier for functions that can only be called by the SafetyModule contract
    modifier onlySafetyModule() {
        if (msg.sender != address(safetyModule))
            revert StakedToken_CallerIsNotSafetyModule(msg.sender);
        _;
    }

    /// @notice StakedToken constructor
    /// @param _underlyingToken The underlying token to stake
    /// @param _safetyModule The SafetyModule contract to use for reward management
    /// @param _cooldownSeconds The number of seconds that users must wait between calling `cooldown` and `redeem`
    /// @param _unstakeWindow The number of seconds available to redeem once the cooldown period is fullfilled
    /// @param _maxStakeAmount The maximum amount of staked tokens allowed per user
    /// @param _name The name of the token
    /// @param _symbol The symbol of the token
    constructor(
        IERC20 _underlyingToken,
        ISafetyModule _safetyModule,
        uint256 _cooldownSeconds,
        uint256 _unstakeWindow,
        uint256 _maxStakeAmount,
        string memory _name,
        string memory _symbol
    ) ERC20(_name, _symbol) ERC20Permit(_name) {
        UNDERLYING_TOKEN = _underlyingToken;
        COOLDOWN_SECONDS = _cooldownSeconds;
        UNSTAKE_WINDOW = _unstakeWindow;
        safetyModule = _safetyModule;
        maxStakeAmount = _maxStakeAmount;
        exchangeRate = 1e18;
    }

    /**
     * @inheritdoc IStakedToken
     */
    function stake(address onBehalfOf, uint256 amount) external override {
        if (amount == 0) revert StakedToken_InvalidZeroAmount();
        if (exchangeRate == 0) revert StakedToken_ZeroExchangeRate();

        // Make sure the user's stake balance doesn't exceed the max stake amount
        uint256 stakeAmount = amount.wadDiv(exchangeRate);
        uint256 balanceOfUser = balanceOf(onBehalfOf);
        if (balanceOfUser + stakeAmount > maxStakeAmount)
            revert StakedToken_AboveMaxStakeAmount(
                maxStakeAmount,
                maxStakeAmount - balanceOfUser
            );

        // Update cooldown timestamp
        stakersCooldowns[onBehalfOf] = getNextCooldownTimestamp(
            0,
            stakeAmount,
            onBehalfOf,
            balanceOfUser
        );

        // Mint staked tokens
        _mint(onBehalfOf, stakeAmount);

        // Transfer underlying tokens from the sender
        IERC20(UNDERLYING_TOKEN).safeTransferFrom(
            msg.sender,
            address(this),
            amount
        );

        // Update user's position and rewards in the SafetyModule
        safetyModule.updateStakingPosition(address(this), onBehalfOf);

        emit Staked(msg.sender, onBehalfOf, amount);
    }

    /**
     * @inheritdoc IStakedToken
     */
    function redeem(address to, uint256 amount) external override {
        if (amount == 0) revert StakedToken_InvalidZeroAmount();
        if (exchangeRate == 0) revert StakedToken_ZeroExchangeRate();

        // Make sure the user's cooldown period is over and the unstake window didn't pass
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

        // Check the sender's balance and adjust the redeem amount if necessary
        uint256 balanceOfMessageSender = balanceOf(msg.sender);
        uint256 amountToRedeem = (amount > balanceOfMessageSender)
            ? balanceOfMessageSender
            : amount;

        // Burn staked tokens
        _burn(msg.sender, amountToRedeem);

        // Reset cooldown to zero if the user redeemed their whole balance
        if (balanceOfMessageSender - amountToRedeem == 0) {
            stakersCooldowns[msg.sender] = 0;
        }

        // Transfer underlying tokens to the recipient
        uint256 underlyingAmount = amountToRedeem.wadMul(exchangeRate);
        IERC20(UNDERLYING_TOKEN).safeTransfer(to, underlyingAmount);

        // Update user's position and rewards in the SafetyModule
        safetyModule.updateStakingPosition(address(this), msg.sender);

        emit Redeem(msg.sender, to, amountToRedeem);
    }

    /**
     * @inheritdoc IStakedToken
     */
    function cooldown() external override {
        if (balanceOf(msg.sender) == 0)
            revert StakedToken_ZeroBalanceAtCooldown();
        //solium-disable-next-line
        stakersCooldowns[msg.sender] = block.timestamp;

        emit Cooldown(msg.sender);
    }

    /**
     * @notice Calculates a new cooldown timestamp
     * @dev Calculation depends on the sender/receiver situation, as follows:
     *  - If the timestamp of the sender is "better" or the timestamp of the recipient is 0, we take the one of the recipient
     *  - Weighted average of from/to cooldown timestamps if:
     *    - The sender doesn't have the cooldown activated (timestamp 0).
     *    - The sender timestamp is expired
     *    - The sender has a "worse" timestamp
     *  - If the receiver's cooldown timestamp expired (too old), the next is 0
     * @param fromCooldownTimestamp Cooldown timestamp of the sender
     * @param amountToReceive Amount of staked tokens to receive
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

    /**
     * @inheritdoc IStakedToken
     * @dev Only callable by governance
     */
    function setSafetyModule(
        address _safetyModule
    ) external onlyRole(GOVERNANCE) {
        safetyModule = ISafetyModule(_safetyModule);
    }

    /**
     * @inheritdoc IStakedToken
     * @dev Only callable by governance
     */
    function setMaxStakeAmount(
        uint256 _maxStakeAmount
    ) external onlyRole(GOVERNANCE) {
        maxStakeAmount = _maxStakeAmount;
    }

    /* ****************** */
    /*      Internal      */
    /* ****************** */

    /**
     * @notice Updates the exchange rate of the staked token, based on the current underlying token balance
     * held by this contract and the total supply of the staked token
     */
    function _updateExchangeRate() internal {
        uint256 totalSupply = totalSupply();
        if (totalSupply == 0) {
            // If there are no staked tokens, reset the exchange rate to 1:1
            exchangeRate = 1e18;
        } else {
            exchangeRate = UNDERLYING_TOKEN.balanceOf(address(this)).wadDiv(
                totalSupply
            );
        }
    }

    /**
     * @notice Internal ERC20 `_transfer` of the tokenized staked tokens
     * @dev Updates the cooldown timestamps if necessary, and updates the staking positions of both users
     * in the SafetyModule, accruing rewards in the process
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
