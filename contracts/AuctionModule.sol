// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.16;

// contracts
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IncreAccessControl} from "@increment/utils/IncreAccessControl.sol";

// libraries
import {LibMath} from "@increment/lib/LibMath.sol";
import {IAuctionModule} from "./interfaces/IAuctionModule.sol";
import {ISafetyModule} from "./interfaces/ISafetyModule.sol";
import {IStakedToken} from "./interfaces/IStakedToken.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title AuctionModule
/// @author webthethird
/// @notice Handles auctioning tokens slashed by the SafetyModule, triggered by governance
/// in the event of an insolvency in the vault which cannot be covered by the insurance fund
contract AuctionModule is
    IAuctionModule,
    IncreAccessControl,
    Pausable,
    ReentrancyGuard
{
    using LibMath for uint256;
    using SafeERC20 for IERC20;

    /// @notice Struct representing an auction
    /// @param token Address of the token being auctioned
    /// @param active Whether the auction is still active
    /// @param lotPrice Price of each lot of tokens, denominated in payment tokens
    /// @param initialLotSize Initial size of each lot
    /// @param numLots Total number of lots in the auction
    /// @param remainingLots Number of lots that have not been sold
    /// @param startTime Timestamp when the auction started
    /// @param endTime Timestamp when the auction ends
    /// @param lotIncreasePeriod Number of seconds between each lot size increase
    /// @param lotIncreaseIncrement Amount of tokens by which the lot size increases each period
    struct Auction {
        IERC20 token;
        bool active;
        uint128 lotPrice;
        uint128 initialLotSize;
        uint8 numLots;
        uint8 remainingLots;
        uint64 startTime;
        uint64 endTime;
        uint16 lotIncreasePeriod;
        uint96 lotIncreaseIncrement;
    }

    /// @notice SafetyModule contract which manages staked token rewards, slashing and auctions
    ISafetyModule public safetyModule;

    /// @notice Payment token used to purchase lots in auctions
    IERC20 public paymentToken;

    /// @notice ID of the next auction
    uint256 public nextAuctionId;

    /// @notice Mapping of auction IDs to auction information
    mapping(uint256 => Auction) public auctions;

    /// @notice Mapping of auction IDs to the number of tokens sold in that auction
    mapping(uint256 => uint256) public tokensSoldPerAuction;

    /// @notice Mapping of auction IDs to the number of payment tokens raised in that auction
    mapping(uint256 => uint256) public fundsRaisedPerAuction;

    /// @notice Modifier for functions that should only be called by the SafetyModule
    modifier onlySafetyModule() {
        if (msg.sender != address(safetyModule))
            revert AuctionModule_CallerIsNotSafetyModule(msg.sender);
        _;
    }

    /// @notice AuctionModule constructor
    /// @param _safetyModule SafetyModule contract to manage this contract
    /// @param _paymentToken ERC20 token used to purchase lots in auctions
    constructor(ISafetyModule _safetyModule, IERC20 _paymentToken) payable {
        safetyModule = _safetyModule;
        paymentToken = _paymentToken;
    }

    /* ****************** */
    /*   View Functions   */
    /* ****************** */

    /// @inheritdoc IAuctionModule
    function getCurrentLotSize(
        uint256 _auctionId
    ) external view returns (uint256) {
        if (_auctionId >= nextAuctionId)
            revert AuctionModule_InvalidAuctionId(_auctionId);
        if (
            !auctions[_auctionId].active ||
            auctions[_auctionId].endTime <= block.timestamp
        ) return 0;
        return _getCurrentLotSize(_auctionId);
    }

    /// @inheritdoc IAuctionModule
    function getRemainingLots(
        uint256 _auctionId
    ) external view returns (uint256) {
        return auctions[_auctionId].remainingLots;
    }

    /// @inheritdoc IAuctionModule
    function getLotPrice(uint256 _auctionId) external view returns (uint256) {
        return auctions[_auctionId].lotPrice;
    }

    /// @inheritdoc IAuctionModule
    function getLotIncreaseIncrement(
        uint256 _auctionId
    ) external view returns (uint256) {
        return auctions[_auctionId].lotIncreaseIncrement;
    }

    /// @inheritdoc IAuctionModule
    function getLotIncreasePeriod(
        uint256 _auctionId
    ) external view returns (uint256) {
        return auctions[_auctionId].lotIncreasePeriod;
    }

    /// @inheritdoc IAuctionModule
    function getAuctionToken(
        uint256 _auctionId
    ) external view returns (IERC20) {
        return auctions[_auctionId].token;
    }

    /// @inheritdoc IAuctionModule
    function getStartTime(uint256 _auctionId) external view returns (uint256) {
        return auctions[_auctionId].startTime;
    }

    /// @inheritdoc IAuctionModule
    function getEndTime(uint256 _auctionId) external view returns (uint256) {
        return auctions[_auctionId].endTime;
    }

    /// @inheritdoc IAuctionModule
    function isAuctionActive(uint256 _auctionId) external view returns (bool) {
        return
            auctions[_auctionId].active &&
            block.timestamp < auctions[_auctionId].endTime;
    }

    /* ***************** */
    /*   External User   */
    /* ***************** */

    /// @inheritdoc IAuctionModule
    function buyLots(
        uint256 _auctionId,
        uint8 _numLotsToBuy
    ) external nonReentrant whenNotPaused {
        // Safety checks
        if (_auctionId >= nextAuctionId)
            revert AuctionModule_InvalidAuctionId(_auctionId);
        if (_numLotsToBuy == 0) revert AuctionModule_InvalidZeroArgument(1);
        if (
            !auctions[_auctionId].active ||
            block.timestamp >= auctions[_auctionId].endTime
        ) revert AuctionModule_AuctionNotActive(_auctionId);
        uint256 remainingLots = auctions[_auctionId].remainingLots;
        if (_numLotsToBuy > remainingLots)
            revert AuctionModule_NotEnoughLotsRemaining(
                _auctionId,
                remainingLots
            );

        // Calculate payment and purchase amounts
        uint256 paymentAmount = _numLotsToBuy * auctions[_auctionId].lotPrice;
        uint256 currentLotSize = _getCurrentLotSize(_auctionId);
        uint256 purchaseAmount = _numLotsToBuy * currentLotSize;

        // Update auction in storage
        auctions[_auctionId].remainingLots -= _numLotsToBuy;
        tokensSoldPerAuction[_auctionId] += purchaseAmount;
        fundsRaisedPerAuction[_auctionId] += paymentAmount;

        // Handle payment
        paymentToken.safeTransferFrom(msg.sender, address(this), paymentAmount);

        // Transfer tokens
        auctions[_auctionId].token.safeTransfer(msg.sender, purchaseAmount);

        // Emit event
        emit LotsSold(
            _auctionId,
            msg.sender,
            _numLotsToBuy,
            currentLotSize,
            auctions[_auctionId].lotPrice
        );

        // Check if auction is over
        if (remainingLots - _numLotsToBuy == 0) {
            auctions[_auctionId].active = false;
            _completeAuction(_auctionId, false);
        }
    }

    function completeAuction(
        uint256 _auctionId
    ) external nonReentrant whenNotPaused {
        // Safety checks
        if (_auctionId >= nextAuctionId)
            revert AuctionModule_InvalidAuctionId(_auctionId);
        // Active flag must still be true, otherwise it has already been completed
        if (!auctions[_auctionId].active)
            revert AuctionModule_AuctionNotActive(_auctionId);
        // Auction timelimit must have passed to complete the auction
        if (block.timestamp >= auctions[_auctionId].endTime)
            auctions[_auctionId].active = false;
            // If the active flag is still true after checking the timelimit, the auction cannot be completed yet
        else
            revert AuctionModule_AuctionStillActive(
                _auctionId,
                auctions[_auctionId].endTime
            );

        _completeAuction(_auctionId, false);
    }

    /// @notice Indicates whether auctions are currently paused
    /// @dev Contract is paused if either this contract or the SafetyModule has been paused
    /// @return True if paused, false otherwise
    function paused() public view override returns (bool) {
        return super.paused() || Pausable(address(safetyModule)).paused();
    }

    /* ******************* */
    /*    Safety Module    */
    /* ******************* */

    /// @inheritdoc IAuctionModule
    /// @dev Only callable by the SafetyModule
    function startAuction(
        IERC20 _token,
        uint8 _numLots,
        uint128 _lotPrice,
        uint128 _initialLotSize,
        uint96 _lotIncreaseIncrement,
        uint16 _lotIncreasePeriod,
        uint32 _timeLimit
    ) external onlySafetyModule whenNotPaused returns (uint256) {
        // Safety checks
        if (_token == IERC20(address(0)))
            revert AuctionModule_InvalidZeroAddress(0);
        if (_numLots == 0) revert AuctionModule_InvalidZeroArgument(1);
        if (_lotPrice == 0) revert AuctionModule_InvalidZeroArgument(2);
        if (_initialLotSize == 0) revert AuctionModule_InvalidZeroArgument(3);
        if (_lotIncreaseIncrement == 0)
            revert AuctionModule_InvalidZeroArgument(4);
        if (_lotIncreasePeriod == 0)
            revert AuctionModule_InvalidZeroArgument(5);
        if (_timeLimit == 0) revert AuctionModule_InvalidZeroArgument(6);

        // Create auction
        uint256 auctionId = nextAuctionId;
        uint64 auctionStartTime = uint64(block.timestamp);
        uint64 auctionEndTime = auctionStartTime + _timeLimit;
        auctions[auctionId] = Auction({
            token: _token,
            active: true,
            lotPrice: _lotPrice,
            initialLotSize: _initialLotSize,
            numLots: _numLots,
            remainingLots: _numLots,
            startTime: auctionStartTime,
            endTime: auctionEndTime,
            lotIncreasePeriod: _lotIncreasePeriod,
            lotIncreaseIncrement: _lotIncreaseIncrement
        });
        nextAuctionId += 1;

        // Emit event
        emit AuctionStarted(
            auctionId,
            address(_token),
            auctionEndTime,
            _lotPrice,
            _initialLotSize,
            _numLots,
            _lotIncreaseIncrement,
            _lotIncreasePeriod
        );

        // Return auction ID
        return auctionId;
    }

    /// @inheritdoc IAuctionModule
    /// @dev Only callable by the SafetyModule
    function terminateAuction(uint256 _auctionId) external onlySafetyModule {
        // Safety checks
        if (_auctionId >= nextAuctionId)
            revert AuctionModule_InvalidAuctionId(_auctionId);
        if (!auctions[_auctionId].active)
            revert AuctionModule_AuctionNotActive(_auctionId);

        auctions[_auctionId].active = false;
        _completeAuction(_auctionId, true);
    }

    /* ****************** */
    /*     Governance     */
    /* ****************** */

    /// @inheritdoc IAuctionModule
    /// @dev Only callable by governance
    function setPaymentToken(
        IERC20 _newPaymentToken
    ) external onlyRole(GOVERNANCE) {
        if (address(_newPaymentToken) == address(0))
            revert AuctionModule_InvalidZeroAddress(0);
        emit PaymentTokenChanged(
            address(paymentToken),
            address(_newPaymentToken)
        );
        paymentToken = _newPaymentToken;
    }

    /// @inheritdoc IAuctionModule
    /// @dev Only callable by governance
    function setSafetyModule(
        ISafetyModule _newSafetyModule
    ) external onlyRole(GOVERNANCE) {
        if (address(_newSafetyModule) == address(0))
            revert AuctionModule_InvalidZeroAddress(0);
        emit SafetyModuleUpdated(
            address(safetyModule),
            address(_newSafetyModule)
        );
        safetyModule = _newSafetyModule;
    }

    /* ****************** */
    /*   Emergency Admin  */
    /* ****************** */

    /// @inheritdoc IAuctionModule
    /// @dev Can only be called by Emergency Admin
    function pause() external override onlyRole(EMERGENCY_ADMIN) {
        _pause();
    }

    /// @inheritdoc IAuctionModule
    /// @dev Can only be called by Emergency Admin
    function unpause() external override onlyRole(EMERGENCY_ADMIN) {
        _unpause();
    }

    /* ****************** */
    /*      Internal      */
    /* ****************** */

    function _getCurrentLotSize(
        uint256 _auctionId
    ) internal view returns (uint256) {
        uint256 incrementPeriods = (block.timestamp -
            auctions[_auctionId].startTime) /
            auctions[_auctionId].lotIncreasePeriod;
        uint256 lotSize = auctions[_auctionId].initialLotSize +
            incrementPeriods *
            auctions[_auctionId].lotIncreaseIncrement;
        uint256 tokenBalance = auctions[_auctionId].token.balanceOf(
            address(this)
        );
        uint256 remainingLots = auctions[_auctionId].remainingLots;
        if (lotSize * remainingLots > tokenBalance) {
            lotSize = tokenBalance / remainingLots;
        }
        return lotSize;
    }

    function _completeAuction(
        uint256 _auctionId,
        bool _terminatedEarly
    ) internal {
        // Approvals
        IERC20 auctionToken = auctions[_auctionId].token;
        IStakedToken stakedToken = safetyModule.stakingTokenByAuctionId(
            _auctionId
        );
        uint256 remainingBalance = auctionToken.balanceOf(address(this));
        uint256 fundsRaised = fundsRaisedPerAuction[_auctionId];
        uint256 finalLotSize = _getCurrentLotSize(_auctionId);

        // SafetyModule will tell the StakedToken to transfer the remaining balance to itself
        if (remainingBalance != 0)
            auctionToken.approve(address(stakedToken), remainingBalance);
        // SafetyModule will transfer funds to governance when `withdrawFundsRaisedFromAuction` is called
        if (fundsRaised != 0)
            paymentToken.approve(address(safetyModule), fundsRaised);
        // Notify SafetyModule if necessary
        if (!_terminatedEarly)
            safetyModule.auctionEnded(_auctionId, remainingBalance);

        // Emit event
        emit AuctionEnded(
            _auctionId,
            auctions[_auctionId].remainingLots,
            finalLotSize,
            tokensSoldPerAuction[_auctionId],
            fundsRaised
        );
    }
}
