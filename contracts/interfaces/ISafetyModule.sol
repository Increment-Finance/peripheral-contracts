// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.16;

import {IStakedToken, IERC20} from "./IStakedToken.sol";
import {IAuctionModule} from "./IAuctionModule.sol";
import {ISMRewardDistributor} from "./ISMRewardDistributor.sol";
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

    /// @notice Emitted when the AuctionModule is updated by governance
    /// @param oldAuctionModule Address of the old AuctionModule
    /// @param newAuctionModule Address of the new AuctionModule
    event AuctionModuleUpdated(
        address oldAuctionModule,
        address newAuctionModule
    );

    /// @notice Emitted when the SMRewardDistributor is updated by governance
    /// @param oldRewardDistributor Address of the old SMRewardDistributor
    /// @param newRewardDistributor Address of the new SMRewardDistributor
    event RewardDistributorUpdated(
        address oldRewardDistributor,
        address newRewardDistributor
    );

    /// @notice Emitted when the max percent user loss is updated by governance
    /// @param maxPercentUserLoss New max percent user loss
    event MaxPercentUserLossUpdated(uint256 maxPercentUserLoss);

    /// @notice Emitted when the max reward multiplier is updated by governance
    /// @param maxRewardMultiplier New max reward multiplier
    event MaxRewardMultiplierUpdated(uint256 maxRewardMultiplier);

    /// @notice Emitted when the smoothing value is updated by governance
    /// @param smoothingValue New smoothing value
    event SmoothingValueUpdated(uint256 smoothingValue);

    /// @notice Emitted when a staking token is slashed and the underlying tokens are sent to the AuctionModule
    /// @param stakingToken Address of the staking token
    /// @param slashAmount Amount of staking tokens slashed
    /// @param underlyingAmount Amount of underlying tokens sent to the AuctionModule
    /// @param auctionId ID of the auction
    event TokensSlashedForAuction(
        address indexed stakingToken,
        uint256 slashAmount,
        uint256 underlyingAmount,
        uint256 indexed auctionId
    );

    /// @notice Emitted when an auction is terminated by governance
    /// @param auctionId ID of the auction
    /// @param stakingToken Address of the staking token that was slashed for the auction
    /// @param underlyingToken Address of the underlying token being sold in the auction
    /// @param underlyingBalanceReturned Amount of underlying tokens returned from the AuctionModule
    event AuctionTerminated(
        uint256 indexed auctionId,
        address stakingToken,
        address underlyingToken,
        uint256 underlyingBalanceReturned
    );

    /// @notice Emitted when an auction ends, either because all lots were sold or the time limit was reached
    /// @param auctionId ID of the auction
    /// @param stakingToken Address of the staking token that was slashed for the auction
    /// @param underlyingToken Address of the underlying token being sold in the auction
    /// @param underlyingBalanceReturned Amount of underlying tokens returned from the AuctionModule
    event AuctionEnded(
        uint256 indexed auctionId,
        address stakingToken,
        address underlyingToken,
        uint256 underlyingBalanceReturned
    );

    /// @notice Error returned a caller other than a registered staking token tries to call a restricted function
    /// @param caller Address of the caller
    error SafetyModule_CallerIsNotStakingToken(address caller);

    /// @notice Error returned a caller other than the auction module tries to call a restricted function
    /// @param caller Address of the caller
    error SafetyModule_CallerIsNotAuctionModule(address caller);

    /// @notice Error returned when trying to add a staking token that is already registered
    /// @param stakingToken Address of the staking token
    error SafetyModule_StakingTokenAlreadyRegistered(address stakingToken);

    /// @notice Error returned when passing an invalid staking token address to a function
    /// @param invalidAddress Address that was passed
    error SafetyModule_InvalidStakingToken(address invalidAddress);

    /// @notice Error returned when passing an invalid auction ID to a function that interacts with the auction module
    /// @param invalidId ID that was passed
    error SafetyModule_InvalidAuctionId(uint256 invalidId);

    /// @notice Error returned when trying to set the max percent user loss to a value that is too high
    /// @param value Value that was passed
    /// @param max Maximum allowed value
    error SafetyModule_InvalidMaxUserLossTooHigh(uint256 value, uint256 max);

    /// @notice Error returned when the maximum auctionable amount of underlying tokens is less than
    /// the given initial lot size multiplied by the number of lots when calling `slashAndStartAuction`
    /// @param token The underlying ERC20 token
    /// @param amount The initial lot size multiplied by the number of lots
    /// @param maxAmount The maximum auctionable amount of underlying tokens
    error SafetyModule_InsufficientSlashedTokensForAuction(
        IERC20 token,
        uint256 amount,
        uint256 maxAmount
    );

    /// @notice Error returned when a caller passes a zero amount to a function that requires a non-zero value
    /// @param argIndex Index of the argument where a zero was passed
    error SafetyModule_InvalidZeroAmount(uint256 argIndex);

    /// @notice Error returned when a caller passes the zero address to a function that requires a non-zero address
    /// @param argIndex Index of the argument where a zero address was passed
    error SafetyModule_InvalidZeroAddress(uint256 argIndex);

    /// @notice Gets the address of the AuctionModule contract
    /// @return The AuctionModule contract
    function auctionModule() external view returns (IAuctionModule);

    /// @notice Gets the address of the SMRewardDistributor contract
    /// @return The SMRewardDistributor contract
    function smRewardDistributor() external view returns (ISMRewardDistributor);

    /// @notice Gets the address of the StakedToken contract at the specified index in the `stakingTokens` array
    /// @param i Index of the staking token
    /// @return Address of the StakedToken contract
    function stakingTokens(uint256 i) external view returns (IStakedToken);

    /// @notice Gets the StakedToken contract that was slashed for the given auction
    /// @param auctionId ID of the auction
    /// @return StakedToken contract that was slashed
    function stakingTokenByAuctionId(
        uint256 auctionId
    ) external view returns (IStakedToken);

    /// @notice Gets the maximum percentage of user funds that can be slashed and sold at auction, normalized to 1e18
    /// @return Maximum user loss percentage
    function maxPercentUserLoss() external view returns (uint256);

    /// @notice Gets the number of staking tokens registered in the SafetyModule
    /// @return Number of staking tokens
    function getNumStakingTokens() external view returns (uint256);

    /// @notice Returns the index of the staking token in the `stakingTokens` array
    /// @dev Reverts with `SafetyModule_InvalidStakingToken` if the staking token is not registered
    /// @param token Address of the staking token
    /// @return Index of the staking token in the `stakingTokens` array
    function getStakingTokenIdx(address token) external view returns (uint256);

    /// @notice Returns the total amount of staked tokens that can be sold at auction in the event of
    /// an insolvency in the vault that cannot be covered by the insurance fund
    /// @param token Address of the staking token
    /// @return Total amount of staked tokens multiplied by the maxPercentUserLoss
    function getAuctionableTotal(address token) external view returns (uint256);

    /// @notice Slashes a portion of all users' staked tokens, capped by maxPercentUserLoss, then
    /// transfers the underlying tokens to the AuctionModule and starts an auction to sell them
    /// @param _stakedToken Address of the staked token to slash
    /// @param _numLots Number of lots in the auction
    /// @param _lotPrice Fixed price of each lot in the auction
    /// @param _initialLotSize Initial number of underlying tokens in each lot
    /// @param _lotIncreaseIncrement Amount of tokens by which the lot size increases each period
    /// @param _lotIncreasePeriod Number of seconds between each lot size increase
    /// @param _timeLimit Number of seconds before the auction ends if all lots are not sold
    /// @return ID of the auction
    function slashAndStartAuction(
        address _stakedToken,
        uint8 _numLots,
        uint128 _lotPrice,
        uint128 _initialLotSize,
        uint96 _lotIncreaseIncrement,
        uint16 _lotIncreasePeriod,
        uint32 _timeLimit
    ) external returns (uint256);

    /// @notice Terminates an auction early and returns any remaining underlying tokens to the StakedToken
    /// @param _auctionId ID of the auction
    function terminateAuction(uint256 _auctionId) external;

    /// @notice Called by the AuctionModule when an auction ends, and returns the remaining balance of
    /// underlying tokens from the auction to the StakedToken
    /// @param _auctionId ID of the auction
    /// @param _remainingBalance Amount of underlying tokens remaining from the auction
    function auctionEnded(
        uint256 _auctionId,
        uint256 _remainingBalance
    ) external;

    /// @notice Donates underlying tokens to a StakedToken contract, raising its exchange rate
    /// @dev Unsold tokens are returned automatically from the AuctionModule when one ends, so this is meant
    /// for transferring tokens from some other source, which must approve the StakedToken to transfer first
    /// @param _stakingToken Address of the StakedToken contract to return underlying tokens to
    /// @param _from Address of the account to transfer funds from
    /// @param _amount Amount of underlying tokens to return
    function returnFunds(
        address _stakingToken,
        address _from,
        uint256 _amount
    ) external;

    /// @notice Sends payment tokens raised in auctions from the AuctionModule to the governance treasury
    /// @param _amount Amount of payment tokens to withdraw
    function withdrawFundsRaisedFromAuction(uint256 _amount) external;

    /// @notice Sets the address of the AuctionModule contract
    /// @param _newAuctionModule Address of the AuctionModule contract
    function setAuctionModule(IAuctionModule _newAuctionModule) external;

    /// @notice Sets the address of the SMRewardDistributor contract
    /// @param _newRewardDistributor Address of the SMRewardDistributor contract
    function setRewardDistributor(
        ISMRewardDistributor _newRewardDistributor
    ) external;

    /// @notice Sets the maximum percentage of user funds that can be sold at auction, normalized to 1e18
    /// @param _maxPercentUserLoss New maximum percentage of user funds that can be sold at auction, normalized to 1e18
    function setMaxPercentUserLoss(uint256 _maxPercentUserLoss) external;

    /// @notice Adds a new staking token to the SafetyModule's stakingTokens array
    /// @param _stakingToken Address of the new staking token
    function addStakingToken(IStakedToken _stakingToken) external;
}
