// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.16;

// contracts
import {ERC20, ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/draft-ERC20Permit.sol";
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IncreAccessControl} from "increment-protocol/utils/IncreAccessControl.sol";

// interfaces
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IStakedToken} from "./interfaces/IStakedToken.sol";
import {ISafetyModule} from "./interfaces/ISafetyModule.sol";
import {ISMRewardDistributor} from "./interfaces/ISMRewardDistributor.sol";

// libraries
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {LibMath} from "increment-protocol/lib/LibMath.sol";

/**
 * @title StakedToken
 * @author webthethird
 * @notice Based on Aave's StakedToken, but with reward management outsourced to the SafetyModule
 */
contract StakedToken is IStakedToken, ERC20Permit, IncreAccessControl, Pausable {
    using SafeERC20 for IERC20;
    using LibMath for uint256;

    /// @notice Address of the underlying token to stake
    IERC20 internal immutable UNDERLYING_TOKEN;

    /// @notice Seconds that user must wait between calling cooldown and redeem
    uint256 internal immutable COOLDOWN_SECONDS;

    /// @notice Seconds available to redeem once the cooldown period is fullfilled
    uint256 internal immutable UNSTAKE_WINDOW;

    /// @notice Address of the SafetyModule contract
    ISafetyModule public safetyModule;

    /// @notice Address of the SafetyModule's SMRewardDistributor contract
    ISMRewardDistributor public smRewardDistributor;

    /// @notice Whether the StakedToken is in a post-slashing state
    /// @dev Post-slashing state disables staking and further slashing, and allows users to redeem their
    /// staked tokens without waiting for the cooldown period
    bool public isInPostSlashingState;

    /// @notice Max amount of staked tokens allowed per user
    uint256 public maxStakeAmount;

    /// @notice Exchange rate between the underlying token and the staked token, normalized to 1e18
    /// @dev Rate is the amount of underlying tokens held in this contract per staked token issued, so
    /// it should be 1e18 in normal conditions, when all staked tokens are backed 1:1 by underlying tokens,
    /// but it can be lower if users' stakes have been slashed for an auction by the SafetyModule
    uint256 public exchangeRate;

    /// @notice Timestamp of the start of the current cooldown period for each user
    mapping(address => uint256) internal _stakersCooldowns;

    /// @notice Modifier for functions that can only be called by the SafetyModule contract
    modifier onlySafetyModule() {
        if (msg.sender != address(safetyModule)) {
            revert StakedToken_CallerIsNotSafetyModule(msg.sender);
        }
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
    ) payable ERC20(_name, _symbol) ERC20Permit(_name) {
        UNDERLYING_TOKEN = _underlyingToken;
        COOLDOWN_SECONDS = _cooldownSeconds;
        UNSTAKE_WINDOW = _unstakeWindow;
        safetyModule = _safetyModule;
        smRewardDistributor = _safetyModule.smRewardDistributor();
        maxStakeAmount = _maxStakeAmount;
        exchangeRate = 1e18;
    }

    /* ****************** */
    /*   External Views   */
    /* ****************** */

    /// @inheritdoc IStakedToken
    function getUnderlyingToken() external view returns (IERC20) {
        return UNDERLYING_TOKEN;
    }

    /// @inheritdoc IStakedToken
    function getCooldownSeconds() external view returns (uint256) {
        return COOLDOWN_SECONDS;
    }

    /// @inheritdoc IStakedToken
    function getUnstakeWindowSeconds() external view returns (uint256) {
        return UNSTAKE_WINDOW;
    }

    /// @inheritdoc IStakedToken
    function getCooldownStartTime(address user) external view returns (uint256) {
        return _stakersCooldowns[user];
    }

    /// @inheritdoc IStakedToken
    function previewStake(uint256 amountToStake) public view returns (uint256) {
        if (exchangeRate == 0) return 0;
        return amountToStake.wadDiv(exchangeRate);
    }

    /// @inheritdoc IStakedToken
    function previewRedeem(uint256 amountToRedeem) public view returns (uint256) {
        return amountToRedeem.wadMul(exchangeRate);
    }

    /* ****************** */
    /*   External Users   */
    /* ****************** */

    /// @inheritdoc IStakedToken
    function stake(uint256 amount) external override {
        _stake(msg.sender, msg.sender, amount);
    }

    /// @inheritdoc IStakedToken
    function stakeOnBehalfOf(address onBehalfOf, uint256 amount) external override {
        if (onBehalfOf == address(0)) revert StakedToken_InvalidZeroAddress();
        _stake(msg.sender, onBehalfOf, amount);
    }

    /// @inheritdoc IStakedToken
    function redeem(uint256 amount) external override {
        _redeem(msg.sender, msg.sender, amount);
    }

    /// @inheritdoc IStakedToken
    function redeemTo(address to, uint256 amount) external override {
        if (to == address(0)) revert StakedToken_InvalidZeroAddress();
        _redeem(msg.sender, to, amount);
    }

    /// @inheritdoc IStakedToken
    function cooldown() external override {
        if (balanceOf(msg.sender) == 0) {
            revert StakedToken_ZeroBalanceAtCooldown();
        }
        if (isInPostSlashingState) {
            revert StakedToken_CooldownDisabledInPostSlashingState();
        }
        //solium-disable-next-line
        _stakersCooldowns[msg.sender] = block.timestamp;

        // Accrue rewards before resetting user's multiplier to 1
        smRewardDistributor.updatePosition(address(this), msg.sender);

        emit Cooldown(msg.sender);
    }

    /// @inheritdoc IStakedToken
    function getNextCooldownTimestamp(
        uint256 fromCooldownTimestamp,
        uint256 amountToReceive,
        address toAddress,
        uint256 toBalance
    ) public view returns (uint256) {
        uint256 toCooldownTimestamp = _stakersCooldowns[toAddress];
        if (toCooldownTimestamp == 0) return 0;

        uint256 minimalValidCooldownTimestamp = block.timestamp - COOLDOWN_SECONDS - UNSTAKE_WINDOW;

        if (minimalValidCooldownTimestamp > toCooldownTimestamp) return 0;
        if (minimalValidCooldownTimestamp > fromCooldownTimestamp) {
            fromCooldownTimestamp = block.timestamp;
        }

        if (fromCooldownTimestamp >= toCooldownTimestamp) {
            toCooldownTimestamp = (amountToReceive * fromCooldownTimestamp + (toBalance * toCooldownTimestamp))
                / (amountToReceive + toBalance);
        }

        return toCooldownTimestamp;
    }

    /// @notice Indicates whether staking and transferring are currently paused
    /// @dev Contract is paused if either this contract or the SafetyModule has been paused
    /// @return True if paused, false otherwise
    function paused() public view override returns (bool) {
        return super.paused() || Pausable(address(safetyModule)).paused();
    }

    /* ****************** */
    /*    SafetyModule    */
    /* ****************** */

    /// @inheritdoc IStakedToken
    function slash(address destination, uint256 amount) external onlySafetyModule returns (uint256) {
        if (amount == 0) revert StakedToken_InvalidZeroAmount();
        if (destination == address(0)) revert StakedToken_InvalidZeroAddress();
        if (isInPostSlashingState) {
            revert StakedToken_SlashingDisabledInPostSlashingState();
        }

        // Change state to post-slashing
        isInPostSlashingState = true;

        // Determine the amount of underlying tokens to transfer, given the current exchange rate
        uint256 underlyingAmount = previewRedeem(amount);

        // Update the exchange rate
        _updateExchangeRate(UNDERLYING_TOKEN.balanceOf(address(this)) - underlyingAmount, totalSupply());

        // Send the slashed underlying tokens to the destination
        UNDERLYING_TOKEN.safeTransfer(destination, underlyingAmount);

        emit Slashed(destination, amount, underlyingAmount);
        return underlyingAmount;
    }

    /// @inheritdoc IStakedToken
    /// @dev Only callable by the SafetyModule contract
    function returnFunds(address from, uint256 amount) external onlySafetyModule {
        if (amount == 0) revert StakedToken_InvalidZeroAmount();
        if (from == address(0)) revert StakedToken_InvalidZeroAddress();

        // Update the exchange rate
        _updateExchangeRate(UNDERLYING_TOKEN.balanceOf(address(this)) + amount, totalSupply());

        // Transfer the underlying tokens back to this contract
        UNDERLYING_TOKEN.safeTransferFrom(from, address(this), amount);
        emit FundsReturned(from, amount);
    }

    /// @inheritdoc IStakedToken
    /// @dev Only callable by the SafetyModule contract
    function settleSlashing() external onlySafetyModule {
        isInPostSlashingState = false;
        emit SlashingSettled();
    }

    /// @inheritdoc IStakedToken
    /// @dev Only callable by the SafetyModule contract in `SafetyModule.setRewardDistributor`
    function setRewardDistributor(ISMRewardDistributor _newRewardDistributor) external onlySafetyModule {
        smRewardDistributor = _newRewardDistributor;
    }

    /* ****************** */
    /*     Governance     */
    /* ****************** */

    /// @inheritdoc IStakedToken
    /// @dev Only callable by governance
    function setSafetyModule(address _newSafetyModule) external onlyRole(GOVERNANCE) {
        emit SafetyModuleUpdated(address(safetyModule), _newSafetyModule);
        safetyModule = ISafetyModule(_newSafetyModule);
        smRewardDistributor = safetyModule.smRewardDistributor();
    }

    /// @inheritdoc IStakedToken
    /// @dev Only callable by governance
    function setMaxStakeAmount(uint256 _newMaxStakeAmount) external onlyRole(GOVERNANCE) {
        emit MaxStakeAmountUpdated(maxStakeAmount, _newMaxStakeAmount);
        maxStakeAmount = _newMaxStakeAmount;
    }

    /// @inheritdoc IStakedToken
    /// @dev Only callable by governance
    function pause() external onlyRole(GOVERNANCE) {
        _pause();
    }

    /// @inheritdoc IStakedToken
    /// @dev Only callable by governance
    function unpause() external onlyRole(GOVERNANCE) {
        _unpause();
    }

    /* ****************** */
    /*      Internal      */
    /* ****************** */

    /// @notice Updates the exchange rate of the staked token,
    /// @dev Based on this contract's current underlying token balance and the total supply of the staked token
    function _updateExchangeRate(uint256 totalAssets, uint256 totalShares) internal {
        exchangeRate = totalAssets.wadDiv(totalShares);
        emit ExchangeRateUpdated(exchangeRate);
    }

    /// @notice Internal ERC20 `_transfer` of the tokenized staked tokens
    /// @dev Updates the cooldown timestamps if necessary, and updates the staking positions of both users
    /// in the SafetyModule, accruing rewards in the process
    /// @param from Address to transfer from
    /// @param to Address to transfer to
    /// @param amount Amount to transfer
    function _transfer(address from, address to, uint256 amount) internal override whenNotPaused {
        if (from != to) {
            uint256 balanceOfTo = balanceOf(to);
            if (balanceOfTo + amount > maxStakeAmount) {
                revert StakedToken_AboveMaxStakeAmount(maxStakeAmount, maxStakeAmount - balanceOfTo);
            }
            uint256 previousSenderCooldown = _stakersCooldowns[from];
            _stakersCooldowns[to] = getNextCooldownTimestamp(previousSenderCooldown, amount, to, balanceOfTo);
            // if cooldown was set and whole balance of sender was transferred - clear cooldown
            if (previousSenderCooldown != 0) {
                if (balanceOf(from) == amount) delete _stakersCooldowns[from];
            }
        }

        super._transfer(from, to, amount);

        // Update positions and accrue rewards to both users
        smRewardDistributor.updatePosition(address(this), from);
        smRewardDistributor.updatePosition(address(this), to);
    }

    /// @notice Internal staking function, accrues rewards after updating user's position
    /// @dev Transfers underlying tokens from the `from` address and mints staked tokens to the `to` address
    ///      Reverts if any of the following conditions are met:
    ///      - The contract is paused
    ///      - The amount to stake is zero
    ///      - The current exchange rate is zero (i.e., all underlying tokens have been slashed)
    ///      - The contract is in a post-slashing state
    ///      - The user's stake balance would exceed the max stake amount
    ///      - The user's underlying token balance is insufficient
    ///      - The user has not approved this contract to transfer the amount of underlying tokens
    /// @param from Address to transfer underlying tokens from
    /// @param to Address to mint staked tokens to
    /// @param amount Amount of underlying tokens to stake
    function _stake(address from, address to, uint256 amount) internal whenNotPaused {
        if (amount == 0) revert StakedToken_InvalidZeroAmount();
        if (exchangeRate == 0) revert StakedToken_ZeroExchangeRate();
        if (isInPostSlashingState) {
            revert StakedToken_StakingDisabledInPostSlashingState();
        }

        // Make sure the user's stake balance doesn't exceed the max stake amount
        uint256 stakeAmount = previewStake(amount);
        uint256 balanceOfUser = balanceOf(to);
        if (balanceOfUser + stakeAmount > maxStakeAmount) {
            revert StakedToken_AboveMaxStakeAmount(maxStakeAmount, maxStakeAmount - balanceOfUser);
        }

        // Update cooldown timestamp
        _stakersCooldowns[to] = getNextCooldownTimestamp(0, stakeAmount, to, balanceOfUser);

        // Mint staked tokens
        _mint(to, stakeAmount);

        // Transfer underlying tokens from the sender
        UNDERLYING_TOKEN.safeTransferFrom(from, address(this), amount);

        // Update user's position and rewards in the SafetyModule
        smRewardDistributor.updatePosition(address(this), to);

        emit Staked(from, to, amount);
    }

    /// @notice Internal redeeming function, accrues rewards after updating user's position
    /// @dev Burns staked tokens from the `from` address and transfers underlying tokens to the `to` address
    ///      Reverts if any of the following conditions are met:
    ///      - The user's staked token balance is zero
    ///      - The amount to redeem is zero
    ///      - The current exchange rate is zero (i.e., all underlying tokens have been slashed)
    ///      - The contract is not in a post-slashing state, and either:
    ///          - The user's cooldown period is not over
    ///          - The unstake window has passed
    /// @param from Address to burn staked tokens from
    /// @param to Address to transfer underlying tokens to
    /// @param amount Amount of staked tokens to redeem
    function _redeem(address from, address to, uint256 amount) internal {
        if (amount == 0) revert StakedToken_InvalidZeroAmount();
        if (exchangeRate == 0) revert StakedToken_ZeroExchangeRate();

        // Users can redeem without waiting for the cooldown period in a post-slashing state
        if (!isInPostSlashingState) {
            // Make sure the user's cooldown period is over and the unstake window didn't pass
            uint256 cooldownStartTimestamp = _stakersCooldowns[from];
            if (block.timestamp < cooldownStartTimestamp + COOLDOWN_SECONDS) {
                revert StakedToken_InsufficientCooldown(cooldownStartTimestamp + COOLDOWN_SECONDS);
            }
            if (block.timestamp - cooldownStartTimestamp + COOLDOWN_SECONDS > UNSTAKE_WINDOW) {
                revert StakedToken_UnstakeWindowFinished(cooldownStartTimestamp + COOLDOWN_SECONDS + UNSTAKE_WINDOW);
            }
        }

        // Check the sender's balance and adjust the redeem amount if necessary
        uint256 balanceOfFrom = balanceOf(from);
        if (amount > balanceOfFrom) amount = balanceOfFrom;
        if (amount == 0) revert StakedToken_InvalidZeroAmount();

        // Burn staked tokens
        _burn(from, amount);

        // Reset cooldown to zero if the user redeemed their whole balance
        if (balanceOfFrom - amount == 0) delete _stakersCooldowns[from];

        // Transfer underlying tokens to the recipient
        UNDERLYING_TOKEN.safeTransfer(to, previewRedeem(amount));

        // Update user's position and rewards in the SafetyModule
        smRewardDistributor.updatePosition(address(this), from);

        emit Redeemed(from, to, amount);
    }
}
