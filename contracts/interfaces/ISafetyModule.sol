// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.16;

import {IStakedToken} from "./IStakedToken.sol";
import {IStakingContract} from "increment-protocol/interfaces/IStakingContract.sol";

/// @title ISafetyModule
/// @author webthethird
/// @notice Interface for the SafetyModule contract
interface ISafetyModule is IStakingContract {
    /// @notice Emitted when a staking token is added
    /// @param stakingToken Address of the staking token
    event StakingTokenAdded(address indexed stakingToken);

    /// @notice Emitted when a staking token is removed
    /// @param stakingToken Address of the staking token
    event StakingTokenRemoved(address indexed stakingToken);

    /// @notice Emitted when the max percent user loss is updated by governance
    /// @param maxPercentUserLoss New max percent user loss
    event MaxPercentUserLossUpdated(uint256 maxPercentUserLoss);

    /// @notice Emitted when the max reward multiplier is updated by governance
    /// @param maxRewardMultiplier New max reward multiplier
    event MaxRewardMultiplierUpdated(uint256 maxRewardMultiplier);

    /// @notice Emitted when the smoothing value is updated by governance
    /// @param smoothingValue New smoothing value
    event SmoothingValueUpdated(uint256 smoothingValue);

    /// @notice Error returned when the caller is not a registered staking token
    /// @param caller Address of the caller
    error SafetyModule_CallerIsNotStakingToken(address caller);

    /// @notice Error returned when trying to add a staking token that is already registered
    /// @param stakingToken Address of the staking token
    error SafetyModule_StakingTokenAlreadyRegistered(address stakingToken);

    /// @notice Error returned when passing an invalid staking token address to a function
    /// @param invalidAddress Address that was passed
    error SafetyModule_InvalidStakingToken(address invalidAddress);

    /// @notice Error returned when trying to set the max percent user loss to a value that is too high
    /// @param value Value that was passed
    /// @param max Maximum allowed value
    error SafetyModule_InvalidMaxUserLossTooHigh(uint256 value, uint256 max);

    /// @notice Error returned when trying to set the max reward multiplier to a value that is too low
    /// @param value Value that was passed
    /// @param min Minimum allowed value
    error SafetyModule_InvalidMaxMultiplierTooLow(uint256 value, uint256 min);

    /// @notice Error returned when trying to set the max reward multiplier to a value that is too high
    /// @param value Value that was passed
    /// @param max Maximum allowed value
    error SafetyModule_InvalidMaxMultiplierTooHigh(uint256 value, uint256 max);

    /// @notice Error returned when trying to set the smoothing value to a value that is too low
    /// @param value Value that was passed
    /// @param min Minimum allowed value
    error SafetyModule_InvalidSmoothingValueTooLow(uint256 value, uint256 min);

    /// @notice Error returned when trying to set the smoothing value to a value that is too high
    /// @param value Value that was passed
    /// @param max Maximum allowed value
    error SafetyModule_InvalidSmoothingValueTooHigh(uint256 value, uint256 max);

    /// @notice Gets the address of the Vault contract
    /// @return Address of the Vault contract
    function vault() external view returns (address);

    /// @notice Gets the address of the Auction contract
    /// @return Address of the Auction contract
    function auctionModule() external view returns (address);

    /// @notice Gets the address of the StakedToken contract at the specified index in the `stakingTokens` array
    /// @param i Index of the staking token
    /// @return Address of the StakedToken contract
    function stakingTokens(uint256 i) external view returns (IStakedToken);

    /// @notice Gets the maximum reward multiplier set by governance
    /// @return Maximum reward multiplier
    function maxRewardMultiplier() external view returns (uint256);

    /// @notice Gets the smoothing value set by governance
    /// @return Smoothing value
    function smoothingValue() external view returns (uint256);

    /// @notice Returns the index of the staking token in the `stakingTokens` array
    /// @dev Reverts with `SafetyModule_InvalidStakingToken` if the staking token is not registered
    /// @param token Address of the staking token
    /// @return Index of the staking token in the `stakingTokens` array
    function getStakingTokenIdx(address token) external view returns (uint256);

    /// @notice Returns the amount of the user's stake tokens that can be sold at auction in the event of
    /// an insolvency in the vault that cannot be covered by the insurance fund
    /// @param staker Address of the user
    /// @param token Address of the staking token
    /// @return Balance of the user multiplied by the maxPercentUserLoss
    function getAuctionableBalance(
        address staker,
        address token
    ) external view returns (uint256);

    /// @notice Returns the total amount of staked tokens that can be sold at auction in the event of
    /// an insolvency in the vault that cannot be covered by the insurance fund
    /// @param token Address of the staking token
    /// @return Total amount of staked tokens multiplied by the maxPercentUserLoss
    function getAuctionableTotal(address token) external view returns (uint256);

    /// @notice Computes the user's reward multiplier for the given staking token
    /// @dev Based on the max multiplier, smoothing factor and time since last withdrawal (or first deposit)
    /// @param _user Address of the staker
    /// @param _stakingToken Address of staking token earning rewards
    /// @return User's reward multiplier, scaled by 1e18
    function computeRewardMultiplier(
        address _user,
        address _stakingToken
    ) external view returns (uint256);

    /// @notice Sets the maximum percentage of user funds that can be sold at auction, normalized to 1e18
    /// @param _maxPercentUserLoss New maximum percentage of user funds that can be sold at auction, normalized to 1e18
    function setMaxPercentUserLoss(uint256 _maxPercentUserLoss) external;

    /// @notice Sets the maximum reward multiplier, normalized to 1e18
    /// @param _maxRewardMultiplier New maximum reward multiplier, normalized to 1e18
    function setMaxRewardMultiplier(uint256 _maxRewardMultiplier) external;

    /// @notice Sets the smoothing value used in calculating the reward multiplier, normalized to 1e18
    /// @param _smoothingValue New smoothing value, normalized to 1e18
    function setSmoothingValue(uint256 _smoothingValue) external;

    /// @notice Adds a new staking token to the SafetyModule's stakingTokens array
    /// @param _stakingToken Address of the new staking token
    function addStakingToken(IStakedToken _stakingToken) external;
}
