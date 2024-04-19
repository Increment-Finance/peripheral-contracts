// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.16;

// contracts
import "../../../contracts/AuctionModule.sol";
import {Test} from "../../../lib/increment-protocol/lib/forge-std/src/Test.sol";
import {
    ERC20, IERC20
} from "../../../lib/increment-protocol/lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

// libraries
import {PRBMathUD60x18} from "../../../lib/increment-protocol/lib/prb-math/contracts/PRBMathUD60x18.sol";

contract AuctionModuleHandler is Test {
    using PRBMathUD60x18 for uint256;

    event LotsSold(uint256 indexed auctionId, address indexed buyer, uint8 numLots, uint256 lotSize, uint128 lotPrice);

    event AuctionEnded(
        uint256 indexed auctionId,
        uint8 remainingLots,
        uint256 finalLotSize,
        uint256 totalTokensSold,
        uint256 totalFundsRaised
    );

    AuctionModule public auctionModule;
    IERC20 public paymentToken;

    address public governance;

    address[] public actors;

    address internal currentActor;

    uint256 internal currentAuction;

    modifier useAuction(uint256 auctionIndexSeed) {
        if (auctionModule.getNextAuctionId() == 0) {
            return;
        }
        currentAuction = bound(auctionIndexSeed, 0, auctionModule.getNextAuctionId() - 1);
        _;
    }

    modifier useActor(uint256 actorIndexSeed) {
        currentActor = actors[bound(actorIndexSeed, 0, actors.length - 1)];
        vm.startPrank(currentActor);
        _;
        vm.stopPrank();
    }

    modifier useGovernance() {
        vm.startPrank(governance);
        _;
        vm.stopPrank();
    }

    constructor(AuctionModule _auctionModule, address[] memory _actors, address _governance) {
        auctionModule = _auctionModule;
        paymentToken = _auctionModule.paymentToken();
        actors = _actors;
        governance = _governance;
    }

    /* ******************** */
    /*  Global Environment  */
    /* ******************** */

    function skipTime(uint256 time) external {
        time = bound(time, 1 hours, 1 weeks);
        skip(time);
    }

    /* ******************* */
    /*  Auction Functions  */
    /* ******************* */

    function buyLots(uint256 actorIndexSeed, uint256 auctionIndexSeed, uint8 numLotsToBuy)
        external
        useActor(actorIndexSeed)
        useAuction(auctionIndexSeed)
    {
        // Check for custom errors
        if (auctionModule.paused()) {
            vm.expectRevert(bytes("Pausable: paused"));
            auctionModule.completeAuction(currentAuction);
            return;
        }
        if (currentAuction >= auctionModule.getNextAuctionId()) {
            vm.expectRevert(abi.encodeWithSignature("AuctionModule_InvalidAuctionId(uint256)", currentAuction));
            auctionModule.buyLots(currentAuction, numLotsToBuy);
            return;
        }
        if (numLotsToBuy == 0) {
            vm.expectRevert(abi.encodeWithSignature("AuctionModule_InvalidZeroArgument(uint256)", 1));
            auctionModule.buyLots(currentAuction, numLotsToBuy);
            return;
        }
        if (!auctionModule.isAuctionActive(currentAuction)) {
            vm.expectRevert(abi.encodeWithSignature("AuctionModule_AuctionNotActive(uint256)", currentAuction));
            auctionModule.buyLots(currentAuction, numLotsToBuy);
            return;
        }
        if (auctionModule.getRemainingLots(currentAuction) < numLotsToBuy) {
            vm.expectRevert(
                abi.encodeWithSignature(
                    "AuctionModule_NotEnoughLotsRemaining(uint256,uint256)",
                    currentAuction,
                    auctionModule.getRemainingLots(currentAuction)
                )
            );
            auctionModule.buyLots(currentAuction, numLotsToBuy);
            return;
        }

        // Check for ERC20 errors
        uint128 lotPrice = uint128(auctionModule.getLotPrice(currentAuction));
        uint256 paymentAmount = lotPrice * numLotsToBuy;
        if (paymentToken.allowance(currentActor, address(auctionModule)) < paymentAmount) {
            vm.expectRevert(bytes("ERC20: transfer amount exceeds allowance"));
            auctionModule.buyLots(currentAuction, numLotsToBuy);
            return;
        }
        if (paymentToken.balanceOf(currentActor) < paymentAmount) {
            vm.expectRevert(bytes("ERC20: transfer amount exceeds balance"));
            auctionModule.buyLots(currentAuction, numLotsToBuy);
            return;
        }

        // Get expected values
        uint128 lotSize = uint128(auctionModule.getCurrentLotSize(currentAuction));
        uint256 purchaseAmount = lotSize * numLotsToBuy;
        IERC20 auctionToken = auctionModule.getAuctionToken(currentAuction);
        uint256 expectedTokenBalance = auctionToken.balanceOf(currentActor) + purchaseAmount;
        uint256 expectedPaymentBalance = paymentToken.balanceOf(currentActor) - paymentAmount;
        uint256 totalTokensSold = auctionModule.getTokensSold(currentAuction) + purchaseAmount;
        uint256 totalFundsRaised = auctionModule.getFundsRaised(currentAuction) + paymentAmount;
        uint256 remainingLots = auctionModule.getRemainingLots(currentAuction) - numLotsToBuy;

        vm.expectEmit(false, false, false, true);
        emit LotsSold(currentAuction, currentActor, numLotsToBuy, lotSize, lotPrice);
        if (remainingLots == 0) {
            vm.expectEmit(false, false, false, true);
            emit AuctionEnded(currentAuction, uint8(0), lotSize, totalTokensSold, totalFundsRaised);
        }
        auctionModule.buyLots(currentAuction, numLotsToBuy);

        assertEq(
            auctionToken.balanceOf(currentActor),
            expectedTokenBalance,
            "AuctionModule: Incorrect auction token balance after buyLots"
        );
        assertEq(
            paymentToken.balanceOf(currentActor),
            expectedPaymentBalance,
            "AuctionModule: Incorrect payment token balance after buyLots"
        );
        if (auctionModule.getRemainingLots(currentAuction) == 0) {
            assertTrue(
                !auctionModule.isAuctionActive(currentAuction), "AuctionModule: Sold out auction should be inactive"
            );
        }
    }

    function completeAuction(uint256 actorIndexSeed, uint256 auctionIndexSeed)
        external
        useActor(actorIndexSeed)
        useAuction(auctionIndexSeed)
    {
        // Check for custom errors
        if (auctionModule.paused()) {
            vm.expectRevert(bytes("Pausable: paused"));
            auctionModule.completeAuction(currentAuction);
            return;
        }
        if (currentAuction >= auctionModule.getNextAuctionId()) {
            vm.expectRevert(abi.encodeWithSignature("AuctionModule_InvalidAuctionId(uint256)", currentAuction));
            auctionModule.completeAuction(currentAuction);
            return;
        }
        if (!auctionModule.isAuctionActive(currentAuction)) {
            vm.expectRevert(abi.encodeWithSignature("AuctionModule_AuctionNotActive(uint256)", currentAuction));
            auctionModule.completeAuction(currentAuction);
            return;
        }
        if (block.timestamp < auctionModule.getEndTime(currentAuction)) {
            vm.expectRevert(
                abi.encodeWithSignature(
                    "AuctionModule_AuctionStillActive(uint256,uint256)",
                    currentAuction,
                    auctionModule.getEndTime(currentAuction)
                )
            );
            auctionModule.completeAuction(currentAuction);
            return;
        }

        // Get expected values
        uint128 lotSize = uint128(auctionModule.getCurrentLotSize(currentAuction));
        uint256 totalTokensSold = auctionModule.getTokensSold(currentAuction);
        uint256 totalFundsRaised = auctionModule.getFundsRaised(currentAuction);
        uint256 remainingLots = auctionModule.getRemainingLots(currentAuction);

        vm.expectEmit(false, false, false, true);
        emit AuctionEnded(currentAuction, uint8(remainingLots), lotSize, totalTokensSold, totalFundsRaised);
        auctionModule.completeAuction(currentAuction);

        assertTrue(
            !auctionModule.isAuctionActive(currentAuction), "AuctionModule: Completed auction should be inactive"
        );
    }

    /* ******************** */
    /* Governance Functions */
    /* ******************** */

    function pauseUnpause() external useGovernance {
        if (auctionModule.paused()) {
            auctionModule.unpause();
        } else {
            auctionModule.pause();
        }
    }
}
