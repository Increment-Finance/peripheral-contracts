// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.16;

// interfaces
import {ISafetyModule} from "./ISafetyModule.sol";
import {IRewardDistributor} from "./IRewardDistributor.sol";

/// @title ISMRewardDistributor
/// @author webthethird
/// @notice Interface for the Safety Module's Reward Distributor contract
interface ISMRewardDistributor is IRewardDistributor {
    /* ****************** */
    /*       Events       */
    /* ****************** */

    /// @notice Emitted when the max reward multiplier is updated by governance
    /// @param oldMaxRewardMultiplier Old max reward multiplier
    /// @param newMaxRewardMultiplier New max reward multiplier
    event MaxRewardMultiplierUpdated(uint256 oldMaxRewardMultiplier, uint256 newMaxRewardMultiplier);

    /// @notice Emitted when the smoothing value is updated by governance
    /// @param oldSmoothingValue Old smoothing value
    /// @param newSmoothingValue New smoothing value
    event SmoothingValueUpdated(uint256 oldSmoothingValue, uint256 newSmoothingValue);

    /// @notice Emitted when the SafetyModule contract is updated by governance
    /// @param oldSafetyModule Address of the old SafetyModule contract
    /// @param newSafetyModule Address of the new SafetyModule contract
    event SafetyModuleUpdated(address oldSafetyModule, address newSafetyModule);

    /* ****************** */
    /*       Errors       */
    /* ****************** */

    /// @notice Error returned when the caller of `initMarketStartTime` is not the SafetyModule
    /// @param caller Address of the caller
    error SMRD_CallerIsNotSafetyModule(address caller);

    /// @notice Error returned when the caller of `updatePosition` is not a registered StakedToken
    /// @param caller Address of the caller
    error SMRD_CallerIsNotStakedToken(address caller);

    /// @notice Error returned when trying to set the max reward multiplier to a value that is too low
    /// @param value Value that was passed
    /// @param min Minimum allowed value
    error SMRD_InvalidMaxMultiplierTooLow(uint256 value, uint256 min);

    /// @notice Error returned when trying to set the max reward multiplier to a value that is too high
    /// @param value Value that was passed
    /// @param max Maximum allowed value
    error SMRD_InvalidMaxMultiplierTooHigh(uint256 value, uint256 max);

    /// @notice Error returned when trying to set the smoothing value to a value that is too low
    /// @param value Value that was passed
    /// @param min Minimum allowed value
    error SMRD_InvalidSmoothingValueTooLow(uint256 value, uint256 min);

    /// @notice Error returned when trying to set the smoothing value to a value that is too high
    /// @param value Value that was passed
    /// @param max Maximum allowed value
    error SMRD_InvalidSmoothingValueTooHigh(uint256 value, uint256 max);

    /* ***************** */
    /*    Public Vars    */
    /* ***************** */

    /// @notice Gets the address of the SafetyModule contract which stores the list of StakedTokens and can call `updatePosition`
    /// @return Address of the SafetyModule contract
    function safetyModule() external view returns (ISafetyModule);

    /* ****************** */
    /*   External Views   */
    /* ****************** */

    /// @notice Gets the maximum reward multiplier set by governance
    /// @return Maximum reward multiplier, scaled by 1e18
    function getMaxRewardMultiplier() external view returns (uint256);

    /// @notice Gets the smoothing value set by governance
    /// @return Smoothing value, scaled by 1e18
    function getSmoothingValue() external view returns (uint256);

    /// @notice Gets the starting timestamp used to calculate the user's reward multiplier for a given staked token
    /// @dev This value is updated whenever `updatePosition` is called, according to the user's change in stake
    /// @param _user Address of the user
    /// @param _stakedToken Address of the staked token
    /// @return User's multiplier starting timestamp
    function multiplierStartTimeByUser(address _user, address _stakedToken) external view returns (uint256);

    /// @notice Computes the user's reward multiplier for the given staked token
    /// @dev Based on the max multiplier, smoothing factor and time since last withdrawal (or first deposit)
    /// @param _user Address of the staker
    /// @param _stakedToken Address of staked token earning rewards
    /// @return User's reward multiplier, scaled by 1e18
    function computeRewardMultiplier(address _user, address _stakedToken) external view returns (uint256);

    /* ****************** */
    /*     Governance     */
    /* ****************** */

    /// @notice Replaces the SafetyModule contract
    /// @param _newSafetyModule Address of the new SafetyModule contract
    function setSafetyModule(ISafetyModule _newSafetyModule) external;

    /// @notice Sets the maximum reward multiplier
    /// @param _newMaxMultiplier New maximum reward multiplier, scaled by 1e18
    function setMaxRewardMultiplier(uint256 _newMaxMultiplier) external;

    /// @notice Sets the smoothing value used in calculating the reward multiplier
    /// @param _newSmoothingValue New smoothing value, scaled by 1e18
    function setSmoothingValue(uint256 _newSmoothingValue) external;
}
