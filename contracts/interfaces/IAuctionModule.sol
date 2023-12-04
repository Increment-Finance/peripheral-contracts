// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.16;

import {ISafetyModule} from "./ISafetyModule.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title IAuctionModule
/// @author webthethird
/// @notice Interface for the AuctionModule contract
interface IAuctionModule {
    /// @notice Emitted when a new auction is started
    /// @param auctionId ID of the auction
    /// @param token Address of the token being auctioned
    /// @param endTimestamp Timestamp when the auction ends
    /// @param lotPrice Price of each lot of tokens in payment token
    /// @param initialLotSize Initial number of tokens in each lot
    /// @param numLots Number of lots in the auction
    /// @param lotIncreaseIncrement Amount of tokens by which the lot size increases each period
    /// @param lotIncreasePeriod Number of seconds between each lot size increase
    event AuctionStarted(
        uint256 indexed auctionId,
        address indexed token,
        uint64 endTimestamp,
        uint128 lotPrice,
        uint128 initialLotSize,
        uint8 numLots,
        uint96 lotIncreaseIncrement,
        uint16 lotIncreasePeriod
    );

    /// @notice Emitted when an auction ends, because either all lots were sold or the time limit was reached
    /// @param auctionId ID of the auction
    /// @param remainingLots Number of lots that were not sold
    /// @param finalLotSize Lot size when the auction ended
    /// @param totalTokensSold Total number of tokens sold
    /// @param totalFundsRaised Total amount of payment tokens raised
    event AuctionEnded(
        uint256 indexed auctionId,
        uint8 remainingLots,
        uint256 finalLotSize,
        uint256 totalTokensSold,
        uint256 totalFundsRaised
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
        uint128 lotPrice
    );

    /// @notice Emitted when the payment token is changed
    /// @param newPaymentToken Address of the new payment token
    /// @param oldPaymentToken Address of the old payment token
    event PaymentTokenChanged(
        address indexed newPaymentToken,
        address oldPaymentToken
    );

    /// @notice Emitted when the SafetyModule contract is updated by governance
    /// @param oldSafetyModule Address of the old SafetyModule contract
    /// @param newSafetyModule Address of the new SafetyModule contract
    event SafetyModuleUpdated(address oldSafetyModule, address newSafetyModule);

    /// @notice Error returned when a caller other than the SafetyModule tries to call a restricted function
    /// @param caller Address of the caller
    error AuctionModule_CallerIsNotSafetyModule(address caller);

    /// @notice Error returned when a caller passes an invalid auction ID to a function
    /// @param invalidId ID that was passed
    error AuctionModule_InvalidAuctionId(uint256 invalidId);

    /// @notice Error returned when a caller passes a zero to a function that requires a non-zero value
    /// @param argIndex Index of the argument where a zero was passed
    error AuctionModule_InvalidZeroArgument(uint256 argIndex);

    /// @notice Error returned when a caller passes a zero address to a function that requires a non-zero address
    /// @param argIndex Index of the argument where a zero address was passed
    error AuctionModule_InvalidZeroAddress(uint256 argIndex);

    /// @notice Error returned when a user calls `buyLots` or the SafetyModule calls `terminateAuction`
    /// after the auction has ended
    /// @param auctionId ID of the auction
    error AuctionModule_AuctionNotActive(uint256 auctionId);

    /// @notice Error returned when a user calls `completeAuction` before the auction's end time
    /// @param auctionId ID of the auction
    /// @param endTime Timestamp when the auction ends
    error AuctionModule_AuctionStillActive(uint256 auctionId, uint256 endTime);

    /// @notice Error returned when a caller tries to complete an auction that has already been completed
    /// @param auctionId ID of the auction
    error AuctionModule_AuctionAlreadyCompleted(uint256 auctionId);

    /// @notice Error returned when a user tries to buy more than the number of lots remaining
    /// @param auctionId ID of the auction
    /// @param lotsRemaining Number of lots remaining
    error AuctionModule_NotEnoughLotsRemaining(
        uint256 auctionId,
        uint256 lotsRemaining
    );

    /// @notice Returns the SafetyModule contract which manages this contract
    /// @return SafetyModule contract
    function safetyModule() external view returns (ISafetyModule);

    /// @notice Returns the ERC20 token used for payments in all auctions
    /// @return ERC20 token used for payments
    function paymentToken() external view returns (IERC20);

    /// @notice Returns the ID of the next auction
    /// @return ID of the next auction
    function nextAuctionId() external view returns (uint256);

    /// @notice Returns the number of tokens sold in the auction
    /// @param _auctionId ID of the auction
    /// @return Number of tokens sold
    function tokensSoldPerAuction(
        uint256 _auctionId
    ) external view returns (uint256);

    /// @notice Returns the amount of funds raised in the auction
    /// @param _auctionId ID of the auction
    /// @return Number of payment tokens raised
    function fundsRaisedPerAuction(
        uint256 _auctionId
    ) external view returns (uint256);

    /// @notice Returns the current lot size of the auction
    /// @dev Lot size starts at `auction.initialLotSize` and increases by `auction.lotIncreaseIncrement` every
    /// `auction.lotIncreasePeriod` seconds, unless the lot size times the number of remaining lots reaches the
    /// contract's total balance of tokens, then the size remains fixed at `totalBalance / auction.remainingLots`
    /// @param _auctionId ID of the auction
    /// @return Current number of tokens per lot
    function getCurrentLotSize(
        uint256 _auctionId
    ) external view returns (uint256);

    /// @notice Returns the number of lots still available for sale in the auction
    /// @param _auctionId ID of the auction
    /// @return Number of lots still available for sale
    function getRemainingLots(
        uint256 _auctionId
    ) external view returns (uint256);

    /// @notice Returns the price of each lot in the auction
    /// @param _auctionId ID of the auction
    /// @return Price of each lot in payment tokens
    function getLotPrice(uint256 _auctionId) external view returns (uint256);

    /// @notice Returns the number of tokens by which the lot size increases each period
    /// @param _auctionId ID of the auction
    /// @return Size of each lot increase
    function getLotIncreaseIncrement(
        uint256 _auctionId
    ) external view returns (uint256);

    /// @notice Returns the amount of time between each lot size increase
    /// @param _auctionId ID of the auction
    /// @return Number of seconds between each lot size increase
    function getLotIncreasePeriod(
        uint256 _auctionId
    ) external view returns (uint256);

    /// @notice Returns the address of the token being auctioned
    /// @param _auctionId ID of the auction
    /// @return The ERC20 token being auctioned
    function getAuctionToken(uint256 _auctionId) external view returns (IERC20);

    /// @notice Returns the timestamp when the auction started
    /// @dev The auction starts when the SafetyModule calls `startAuction`
    /// @param _auctionId ID of the auction
    /// @return Timestamp when the auction started
    function getStartTime(uint256 _auctionId) external view returns (uint256);

    /// @notice Returns the timestamp when the auction ends
    /// @dev Auction can end early if all lots are sold or if the auction is terminated by the SafetyModule
    /// @param _auctionId ID of the auction
    /// @return Timestamp when the auction ends
    function getEndTime(uint256 _auctionId) external view returns (uint256);

    /// @notice Returns whether the auction is still active
    /// @param _auctionId ID of the auction
    /// @return True if the auction is still active, false otherwise
    function isAuctionActive(uint256 _auctionId) external view returns (bool);

    /// Sets the token required for payments in all auctions
    /// @param _paymentToken ERC20 token to use for payment
    function setPaymentToken(IERC20 _paymentToken) external;

    /// @notice Replaces the SafetyModule contract
    /// @param _newSafetyModule Address of the new SafetyModule contract
    function setSafetyModule(ISafetyModule _newSafetyModule) external;

    /// @notice Starts a new auction
    /// @dev First the SafetyModule slashes the StakedToken, sending the underlying slashed tokens here
    /// @param _token The ERC20 token to auction
    /// @param _numLots Number of lots in the auction
    /// @param _lotPrice Price of each lot of tokens in payment tokens
    /// @param _initialLotSize Initial number of tokens in each lot
    /// @param _lotIncreaseIncrement Amount of tokens by which the lot size increases each period
    /// @param _lotIncreasePeriod Number of seconds between each lot size increase
    /// @param _timeLimit Number of seconds before the auction ends if all lots are not sold
    /// @return ID of the auction
    function startAuction(
        IERC20 _token,
        uint8 _numLots,
        uint128 _lotPrice,
        uint128 _initialLotSize,
        uint96 _lotIncreaseIncrement,
        uint16 _lotIncreasePeriod,
        uint32 _timeLimit
    ) external returns (uint256);

    /// @notice Terminates an auction early and approves the transfer of unsold tokens and funds raised
    /// @param _auctionId ID of the auction
    function terminateAuction(uint256 _auctionId) external;

    /// @notice Ends an auction after the time limit has been reached and approves the transfer of
    /// unsold tokens and funds raised
    /// @dev This function can be called by anyone, but only after the auction's end time has passed
    /// @param _auctionId ID of the auction
    function completeAuction(uint256 _auctionId) external;

    /// @notice Buys one or more lots at the current lot size, and ends the auction if all lots are sold
    /// @dev The caller must approve this contract to transfer the lotPrice * numLotsToBuy in payment tokens
    /// @param _auctionId ID of the auction
    /// @param _numLotsToBuy Number of lots to buy
    function buyLots(uint256 _auctionId, uint8 _numLotsToBuy) external;
}
