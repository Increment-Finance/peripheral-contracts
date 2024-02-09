// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.16;

import {IStakedToken, IERC20} from "./IStakedToken.sol";
import {IAuctionModule} from "./IAuctionModule.sol";
import {ISMRewardDistributor} from "./ISMRewardDistributor.sol";

/// @title ISafetyModule
/// @author webthethird
/// @notice Interface for the SafetyModule contract
interface ISafetyModule {
    /* ****************** */
    /*       Events       */
    /* ****************** */

    /// @notice Emitted when a staked token is added
    /// @param stakedToken Address of the staked token
    event StakedTokenAdded(address indexed stakedToken);

    /// @notice Emitted when the AuctionModule is updated by governance
    /// @param oldAuctionModule Address of the old AuctionModule
    /// @param newAuctionModule Address of the new AuctionModule
    event AuctionModuleUpdated(address oldAuctionModule, address newAuctionModule);

    /// @notice Emitted when the SMRewardDistributor is updated by governance
    /// @param oldRewardDistributor Address of the old SMRewardDistributor
    /// @param newRewardDistributor Address of the new SMRewardDistributor
    event RewardDistributorUpdated(address oldRewardDistributor, address newRewardDistributor);

    /// @notice Emitted when a staked token is slashed and the underlying tokens are sent to the AuctionModule
    /// @param stakedToken Address of the staked token
    /// @param slashAmount Amount of staked tokens slashed
    /// @param underlyingAmount Amount of underlying tokens sent to the AuctionModule
    /// @param auctionId ID of the auction
    event TokensSlashedForAuction(
        address indexed stakedToken, uint256 slashAmount, uint256 underlyingAmount, uint256 indexed auctionId
    );

    /// @notice Emitted when an auction is terminated by governance
    /// @param auctionId ID of the auction
    /// @param stakedToken Address of the staked token that was slashed for the auction
    /// @param underlyingToken Address of the underlying token being sold in the auction
    /// @param underlyingBalanceReturned Amount of underlying tokens returned from the AuctionModule
    event AuctionTerminated(
        uint256 indexed auctionId, address stakedToken, address underlyingToken, uint256 underlyingBalanceReturned
    );

    /// @notice Emitted when an auction ends, either because all lots were sold or the time limit was reached
    /// @param auctionId ID of the auction
    /// @param stakedToken Address of the staked token that was slashed for the auction
    /// @param underlyingToken Address of the underlying token being sold in the auction
    /// @param underlyingBalanceReturned Amount of underlying tokens returned from the AuctionModule
    event AuctionEnded(
        uint256 indexed auctionId, address stakedToken, address underlyingToken, uint256 underlyingBalanceReturned
    );

    /* ****************** */
    /*       Errors       */
    /* ****************** */

    /// @notice Error returned when a caller other than the auction module tries to call a restricted function
    /// @param caller Address of the caller
    error SafetyModule_CallerIsNotAuctionModule(address caller);

    /// @notice Error returned when trying to add a staked token that is already registered
    /// @param stakedToken Address of the staked token
    error SafetyModule_StakedTokenAlreadyRegistered(address stakedToken);

    /// @notice Error returned when passing an invalid staked token address to a function
    /// @param invalidAddress Address that was passed
    error SafetyModule_InvalidStakedToken(address invalidAddress);

    /// @notice Error returned when passing a `slashPercent` value that is greater than 100% (1e18)
    error SafetyModule_InvalidSlashPercentTooHigh();

    /// @notice Error returned when the maximum auctionable amount of underlying tokens is less than
    /// the given initial lot size multiplied by the number of lots when calling `slashAndStartAuction`
    /// @param token The underlying ERC20 token
    /// @param amount The initial lot size multiplied by the number of lots
    /// @param maxAmount The maximum auctionable amount of underlying tokens
    error SafetyModule_InsufficientSlashedTokensForAuction(IERC20 token, uint256 amount, uint256 maxAmount);

    /* ***************** */
    /*    Public Vars    */
    /* ***************** */

    /// @notice Gets the address of the AuctionModule contract
    /// @return The AuctionModule contract
    function auctionModule() external view returns (IAuctionModule);

    /// @notice Gets the address of the SMRewardDistributor contract
    /// @return The SMRewardDistributor contract
    function smRewardDistributor() external view returns (ISMRewardDistributor);

    /// @notice Gets the address of the StakedToken contract at the specified index in the `stakedTokens` array
    /// @param i Index of the staked token
    /// @return Address of the StakedToken contract
    function stakedTokens(uint256 i) external view returns (IStakedToken);

    /// @notice Gets the StakedToken contract that was slashed for the given auction
    /// @param auctionId ID of the auction
    /// @return StakedToken contract that was slashed
    function stakedTokenByAuctionId(uint256 auctionId) external view returns (IStakedToken);

    /* ****************** */
    /*   External Views   */
    /* ****************** */

    /// @notice Returns the full list of staked tokens registered in the SafetyModule
    /// @return Array of StakedToken contracts
    function getStakedTokens() external view returns (IStakedToken[] memory);

    /// @notice Gets the number of staked tokens registered in the SafetyModule
    /// @return Number of staked tokens
    function getNumStakedTokens() external view returns (uint256);

    /// @notice Returns the index of the staked token in the `stakedTokens` array
    /// @dev Reverts with `SafetyModule_InvalidStakedToken` if the staked token is not registered
    /// @param token Address of the staked token
    /// @return Index of the staked token in the `stakedTokens` array
    function getStakedTokenIdx(address token) external view returns (uint256);

    /// @notice Slashes a portion of all users' staked tokens, capped by maxPercentUserLoss, then
    /// transfers the underlying tokens to the AuctionModule and starts an auction to sell them
    /// @param _stakedToken Address of the staked token to slash
    /// @param _numLots Number of lots in the auction
    /// @param _lotPrice Fixed price of each lot in the auction
    /// @param _initialLotSize Initial number of underlying tokens in each lot
    /// @param _slashPercent Percentage of staked tokens to slash, normalized to 1e18
    /// @param _lotIncreaseIncrement Amount of tokens by which the lot size increases each period
    /// @param _lotIncreasePeriod Number of seconds between each lot size increase
    /// @param _timeLimit Number of seconds before the auction ends if all lots are not sold
    /// @return ID of the auction
    function slashAndStartAuction(
        address _stakedToken,
        uint8 _numLots,
        uint128 _lotPrice,
        uint128 _initialLotSize,
        uint64 _slashPercent,
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
    function auctionEnded(uint256 _auctionId, uint256 _remainingBalance) external;

    /// @notice Donates underlying tokens to a StakedToken contract, raising its exchange rate
    /// @dev Unsold tokens are returned automatically from the AuctionModule when one ends, so this is meant
    /// for transferring tokens from some other source, which must approve the StakedToken to transfer first
    /// @param _stakedToken Address of the StakedToken contract to return underlying tokens to
    /// @param _from Address of the account to transfer funds from
    /// @param _amount Amount of underlying tokens to return
    function returnFunds(address _stakedToken, address _from, uint256 _amount) external;

    /// @notice Sends payment tokens raised in auctions from the AuctionModule to the governance treasury
    /// @param _amount Amount of payment tokens to withdraw
    function withdrawFundsRaisedFromAuction(uint256 _amount) external;

    /// @notice Sets the address of the AuctionModule contract
    /// @param _newAuctionModule Address of the AuctionModule contract
    function setAuctionModule(IAuctionModule _newAuctionModule) external;

    /// @notice Sets the address of the SMRewardDistributor contract
    /// @param _newRewardDistributor Address of the SMRewardDistributor contract
    function setRewardDistributor(ISMRewardDistributor _newRewardDistributor) external;

    /// @notice Adds a new staked token to the SafetyModule's stakedTokens array
    /// @param _stakedToken Address of the new staked token
    function addStakedToken(IStakedToken _stakedToken) external;

    /// @notice Pause the contract
    function pause() external;

    /// @notice Unpause the contract
    function unpause() external;
}
