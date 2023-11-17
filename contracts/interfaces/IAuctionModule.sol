// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.16;

import {ISafetyModule} from "./ISafetyModule.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title IAuctionModule
/// @author webthethird
/// @notice Interface for the AuctionModule contract
interface IAuctionModule {
    /// @notice Emitted when a new auction is started
    /// @param token Address of the token being auctioned
    /// @param auctionId ID of the auction
    /// @param startTimestamp Timestamp when the auction started
    /// @param endTimestamp Timestamp when the auction ends
    /// @param lotPrice Price of each lot of tokens in USDC
    /// @param numLots Number of lots in the auction
    /// @param initialLotSize Initial size of each lot
    /// @param lotIncreaseIncrement Amount of tokens by which the lot size increases each period
    /// @param lotIncreasePeriod Number of seconds between each lot size increase
    event AuctionStarted(
        address indexed token,
        uint256 indexed auctionId,
        uint256 startTimestamp,
        uint256 endTimestamp,
        uint256 lotPrice,
        uint256 numLots,
        uint256 initialLotSize,
        uint256 lotIncreaseIncrement,
        uint256 lotIncreasePeriod
    );

    /// @notice Emitted when an auction ends, because either all lots were sold or the time limit was reached
    /// @param auctionId ID of the auction
    /// @param remainingLots Number of lots that were not sold
    /// @param finalLotSize Lot size when the auction ended
    /// @param totalTokensSold Total number of tokens sold
    /// @param totalUSDCRaised Total amount of USDC raised
    event AuctionEnded(
        uint256 indexed auctionId,
        uint256 remainingLots,
        uint256 finalLotSize,
        uint256 totalTokensSold,
        uint256 totalUSDCRaised
    );

    /// @notice Emitted when an auction is terminated by the SafetyModule
    /// @param auctionId ID of the auction
    /// @param remainingBalance Amount of remaining tokens returned to the SafetyModule
    event AuctionTerminated(
        uint256 indexed auctionId,
        uint256 remainingBalance
    );

    /// @notice Emitted when a lot is sold
    /// @param auctionId ID of the auction
    /// @param buyer Address of the buyer
    /// @param lotSize Size of the lot sold
    /// @param lotPrice Price of the lot sold
    event LotSold(
        uint256 indexed auctionId,
        address indexed buyer,
        uint256 lotSize,
        uint256 lotPrice
    );

    /// @notice Error returned when a caller other than the SafetyModule tries to call a restricted function
    /// @param caller Address of the caller
    error AuctionModule_CallerIsNotSafetyModule(address caller);

    /// @notice Error returned when a caller passes an invalid auction ID to a function
    /// @param invalidId ID that was passed
    error AuctionModule_InvalidAuctionId(uint256 invalidId);

    /// @notice Error returned when a caller passes a zero argument to a function that requires a non-zero value
    /// @param argIndex Index of the argument where a zero was passed
    error AuctionModule_InvalidZeroArgument(uint256 argIndex);

    /// @notice Error returned when a user calls buyLots after the auction has ended
    /// @param auctionId ID of the auction
    error AuctionModule_AuctionNotActive(uint256 auctionId);

    /// @notice Error returned when a user tries to buy more than the number of lots remaining
    /// @param auctionId ID of the auction
    /// @param lotsRemaining Number of lots remaining
    error AuctionModule_NotEnoughLotsRemaining(
        uint256 auctionId,
        uint256 lotsRemaining
    );

    /// @notice Returns the address of the SafetyModule
    function safetyModule() external view returns (ISafetyModule);

    /// @notice Returns the address of the USDC token
    function usdc() external view returns (IERC20);

    /// @notice Returns the current lot size of the auction
    /// @param auctionId ID of the auction
    /// @return Current number of tokens per lot
    function getCurrentLotSize(
        uint256 auctionId
    ) external view returns (uint256);

    /// @notice Returns the number of lots still available for sale in the auction
    /// @param auctionId ID of the auction
    /// @return Number of lots still available for sale
    function getRemainingLots(
        uint256 auctionId
    ) external view returns (uint256);

    /// @notice Returns the price of each lot in the auction
    /// @param auctionId ID of the auction
    /// @return Price of each lot in USDC
    function getLotPrice(uint256 auctionId) external view returns (uint256);

    /// @notice Returns the address of the token being auctioned
    /// @param auctionId ID of the auction
    /// @return The ERC20 token being auctioned
    function getAuctionToken(uint256 auctionId) external view returns (IERC20);

    /// @notice Returns the timestamp when the auction started
    /// @param auctionId ID of the auction
    /// @return Timestamp when the auction started
    function getStartTime(uint256 auctionId) external view returns (uint256);

    /// @notice Returns the timestamp when the auction ends
    /// @param auctionId ID of the auction
    /// @return Timestamp when the auction ends
    function getEndTime(uint256 auctionId) external view returns (uint256);

    /// @notice Returns whether the auction is still active
    /// @param auctionId ID of the auction
    /// @return True if the auction is still active, false otherwise
    function isAuctionActive(uint256 auctionId) external view returns (bool);

    /// @notice Starts a new auction
    /// @dev First the SafetyModule slashes the StakedToken, removing the underlying slashed tokens,
    /// and approves this contract to transfer them from the SafetyModule to itself
    /// @param token The ERC20 token to auction
    /// @param lotPrice Price of each lot of tokens in USDC
    /// @param numLots Number of lots in the auction
    /// @param initialLotSize Initial number of tokens in each lot
    /// @param lotIncreaseIncrement Amount of tokens by which the lot size increases each period
    /// @param lotIncreasePeriod Number of seconds between each lot size increase
    /// @param timeLimit Number of seconds before the auction ends if all lots are not sold
    /// @return ID of the auction
    function startAuction(
        IERC20 token,
        uint256 lotPrice,
        uint256 numLots,
        uint256 initialLotSize,
        uint256 lotIncreaseIncrement,
        uint256 lotIncreasePeriod,
        uint256 timeLimit
    ) external returns (uint256);

    /// @notice Terminates an auction and sends the remaining tokens back to the SafetyModule
    /// @param auctionId ID of the auction
    function terminateAuction(uint256 auctionId) external;

    /// @notice Buys one or more lots in an auction at the current lot size
    /// @dev The caller must approve this contract to transfer the lotPrice * numLotsToBuy in USDC
    /// @param auctionId ID of the auction
    /// @param numLotsToBuy Number of lots to buy
    function buyLots(uint256 auctionId, uint256 numLotsToBuy) external;
}
