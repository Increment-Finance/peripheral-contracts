// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.16;

// contracts
import "../../../contracts/SafetyModule.sol";
import "../../../contracts/StakedToken.sol";
import {Test} from "../../../lib/increment-protocol/lib/forge-std/src/Test.sol";
import {ERC20} from "../../../lib/increment-protocol/lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {Pausable} from "../../../lib/increment-protocol/lib/openzeppelin-contracts/contracts/security/Pausable.sol";

// interfaces
import {IRewardDistributor} from "../../../contracts/interfaces/IRewardDistributor.sol";

// libraries
import {strings} from "../../../lib/solidity-stringutils/strings.sol";
import {PRBMathUD60x18} from "../../../lib/increment-protocol/lib/prb-math/contracts/PRBMathUD60x18.sol";

interface ITestContract {
    function addStakedToken(StakedToken stakedToken, bool isStakedBPT) external;
}

contract SafetyModuleHandler is Test {
    using strings for *;
    using PRBMathUD60x18 for uint256;

    event StakedTokenAdded(address indexed stakedToken);

    event TokensSlashedForAuction(
        address indexed stakedToken, uint256 slashAmount, uint256 underlyingAmount, uint256 indexed auctionId
    );

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

    event AuctionEnded(
        uint256 indexed auctionId,
        uint8 remainingLots,
        uint256 finalLotSize,
        uint256 totalTokensSold,
        uint256 totalFundsRaised
    );

    event AuctionTerminated(
        uint256 indexed auctionId, address stakedToken, address underlyingToken, uint256 underlyingBalanceReturned
    );

    event FundsReturned(address indexed from, uint256 amount);

    event SlashingSettled();

    SafetyModule public safetyModule;

    IAuctionModule public auctionModule;

    ITestContract public testContract;

    address public governance;

    modifier useGovernance() {
        vm.startPrank(governance);
        _;
        vm.stopPrank();
    }

    constructor(SafetyModule _safetyModule, address _governance) {
        safetyModule = _safetyModule;
        governance = _governance;
        testContract = ITestContract(msg.sender);
        auctionModule = safetyModule.auctionModule();
    }

    /* ******************** */
    /* Governance Functions */
    /* ******************** */

    // function addStakedToken(
    //     string memory underlyingName,
    //     string memory underlyingSymbol,
    //     uint256 cooldownSeconds,
    //     uint256 unstakeWindowSeconds,
    //     uint256 maxStakeAmount
    // ) external useGovernance {
    //     cooldownSeconds = bound(cooldownSeconds, 1 hours, 1 weeks);
    //     unstakeWindowSeconds = bound(unstakeWindowSeconds, 1 hours, 1 weeks);
    //     maxStakeAmount = bound(maxStakeAmount, 10_000e18, 1_000_000e18);
    //     ERC20 underlying = new ERC20(underlyingName, underlyingSymbol);
    //     StakedToken stakedToken = new StakedToken(
    //         underlying,
    //         safetyModule,
    //         cooldownSeconds,
    //         unstakeWindowSeconds,
    //         maxStakeAmount,
    //         "Staked ".toSlice().concat(underlyingName.toSlice()),
    //         "stk".toSlice().concat(underlyingSymbol.toSlice())
    //     );
    //     vm.expectEmit(false, false, false, true);
    //     emit StakedTokenAdded(address(stakedToken));
    //     safetyModule.addStakedToken(stakedToken);
    //     vm.stopPrank();
    //     testContract.addStakedToken(stakedToken, false);
    // }

    function slashAndStartAuction(
        uint256 _stakedTokenIndexSeed,
        uint8 _numLots,
        uint128 _lotPrice,
        uint128 _initialLotSize,
        uint64 _slashPercent,
        uint96 _lotIncreaseIncrement,
        uint16 _lotIncreasePeriod,
        uint32 _timeLimit
    ) external useGovernance {
        IStakedToken stakedToken =
            safetyModule.stakedTokens(bound(_stakedTokenIndexSeed, 0, safetyModule.getNumStakedTokens() - 1));
        _numLots = uint8(bound(_numLots, 1, 100));
        _lotPrice = uint128(bound(_lotPrice, 1e6, type(uint128).max));
        _initialLotSize = uint128(bound(_initialLotSize, 1e12, type(uint128).max));
        _lotIncreaseIncrement = uint96(bound(_lotIncreaseIncrement, _initialLotSize / 100, _initialLotSize / 10));
        _lotIncreasePeriod = uint16(bound(_lotIncreasePeriod, 30 minutes, 12 hours));
        _timeLimit = uint32(bound(_timeLimit, 1 days, 4 weeks));
        _slashPercent = uint64(bound(_slashPercent, 1e16, 0.99e18));

        uint256 slashAmount = stakedToken.totalSupply().mul(_slashPercent);
        uint256 underlyingAmount = stakedToken.previewRedeem(slashAmount);
        uint256 getNextAuctionId = auctionModule.getNextAuctionId();
        bool expectFail;

        if (stakedToken.totalSupply().mul(_slashPercent) == 0) {
            expectFail = true;
            vm.expectRevert(abi.encodeWithSignature("StakedToken_InvalidZeroAmount()"));
        } else if (stakedToken.isInPostSlashingState()) {
            expectFail = true;
            vm.expectRevert(abi.encodeWithSignature("StakedToken_SlashingDisabledInPostSlashingState()"));
        } else if (underlyingAmount < uint256(_initialLotSize) * uint256(_numLots)) {
            expectFail = true;
            IERC20 underlyingToken = stakedToken.getUnderlyingToken();
            vm.expectRevert(
                abi.encodeWithSignature(
                    "SafetyModule_InsufficientSlashedTokensForAuction(address,uint256,uint256)",
                    address(underlyingToken),
                    uint256(_initialLotSize) * uint256(_numLots),
                    underlyingAmount
                )
            );
        } else if (Pausable(address(auctionModule)).paused()) {
            expectFail = true;
            vm.expectRevert(bytes("Pausable: paused"));
        }

        uint256 auctionId = safetyModule.slashAndStartAuction(
            address(stakedToken),
            _numLots,
            _lotPrice,
            _initialLotSize,
            slashAmount,
            _lotIncreaseIncrement,
            _lotIncreasePeriod,
            _timeLimit
        );

        if (expectFail) {
            return;
        }

        assertEq(auctionId, getNextAuctionId, "Auction ID mismatch");
        assertTrue(auctionModule.isAuctionActive(auctionId), "Auction not active");
        assertTrue(stakedToken.isInPostSlashingState(), "Staked token not in post slashing state");
        assertEq(auctionModule.getCurrentLotSize(auctionId), _initialLotSize, "Initial lot size mismatch");
        assertEq(auctionModule.getRemainingLots(auctionId), _numLots, "Remaining lots mismatch");
    }

    function terminateAuction(uint256 auctionId) external useGovernance {
        if (auctionModule.getNextAuctionId() == 0) {
            vm.expectRevert(abi.encodeWithSignature("AuctionModule_InvalidAuctionId(uint256)", auctionId));
            safetyModule.terminateAuction(auctionId);
            return;
        }
        auctionId = bound(auctionId, 0, auctionModule.getNextAuctionId() - 1);
        IERC20 token = auctionModule.getAuctionToken(auctionId);
        IStakedToken stakedToken = safetyModule.stakedTokenByAuctionId(auctionId);
        uint256 unsoldTokens = token.balanceOf(address(auctionModule));
        uint256 prevStakedUnderlyingBalance = token.balanceOf(address(stakedToken));
        uint256 exchangeRate = stakedToken.exchangeRate();
        bool isAuctionActive = auctionModule.isAuctionActive(auctionId);

        if (!isAuctionActive) {
            vm.expectRevert(abi.encodeWithSignature("AuctionModule_AuctionNotActive(uint256)", auctionId));
        } else {
            uint256 remainingLots = auctionModule.getRemainingLots(auctionId);
            uint256 finalLotSize = auctionModule.getCurrentLotSize(auctionId);
            uint256 totalTokensSold = auctionModule.getTokensSold(auctionId);
            uint256 totalFundsRaised = auctionModule.getFundsRaised(auctionId);
            vm.expectEmit(false, false, false, true);
            emit AuctionEnded(auctionId, uint8(remainingLots), finalLotSize, totalTokensSold, totalFundsRaised);
            if (unsoldTokens != 0) {
                vm.expectEmit(false, false, false, true);
                emit FundsReturned(address(auctionModule), unsoldTokens);
            }
            vm.expectEmit(false, false, false, true);
            emit SlashingSettled();
            vm.expectEmit(false, false, false, true);
            emit AuctionTerminated(auctionId, address(stakedToken), address(token), unsoldTokens);
        }

        auctionModule.terminateAuction(auctionId);
        if (!isAuctionActive) {
            return;
        }

        assertTrue(!auctionModule.isAuctionActive(auctionId), "Auction active after termination");
        assertTrue(!stakedToken.isInPostSlashingState(), "Staked token in post slashing state after termination");
        if (unsoldTokens != 0) {
            assertEq(token.balanceOf(address(auctionModule)), 0, "Unsold tokens not returned from auction module");
            assertEq(
                token.balanceOf(address(stakedToken)),
                prevStakedUnderlyingBalance + unsoldTokens,
                "Underlying balance mismatch after termination"
            );
            assertGt(stakedToken.exchangeRate(), exchangeRate, "Exchange rate mismatch after termination");
        }
    }

    function withdrawFundsRaisedFromAuction(uint256 amount) external useGovernance {
        IERC20 paymentToken = auctionModule.paymentToken();
        uint256 allowance = paymentToken.allowance(address(auctionModule), address(safetyModule));
        if (allowance < amount) {
            vm.expectRevert(bytes("ERC20: transfer amount exceeds allowance"));
            safetyModule.withdrawFundsRaisedFromAuction(amount);
            return;
        }
        uint256 prevAuctionModuleBalance = paymentToken.balanceOf(address(auctionModule));
        if (prevAuctionModuleBalance < amount) {
            vm.expectRevert(bytes("ERC20: transfer amount exceeds balance"));
            safetyModule.withdrawFundsRaisedFromAuction(amount);
            return;
        }
        uint256 prevGovernanceBalance = paymentToken.balanceOf(governance);
        safetyModule.withdrawFundsRaisedFromAuction(amount);
        assertEq(paymentToken.balanceOf(governance), prevGovernanceBalance + amount, "Governance balance mismatch");
        assertEq(
            paymentToken.balanceOf(address(auctionModule)),
            prevAuctionModuleBalance - amount,
            "Auction module balance mismatch"
        );
    }
}
