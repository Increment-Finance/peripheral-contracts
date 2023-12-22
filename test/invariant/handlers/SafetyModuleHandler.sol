// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.16;

// contracts
import "../../../contracts/SafetyModule.sol";
import "../../../contracts/StakedToken.sol";
import {Test} from "forge/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// interfaces
import {IRewardDistributor} from "../../../contracts/interfaces/IRewardDistributor.sol";

// libraries
import "stringutils/strings.sol";

interface ITestContract {
    function addStakedToken(StakedToken stakedToken) external;
}

contract SafetyModuleHandler is Test {
    using strings for *;

    event StakingTokenAdded(address indexed stakingToken);

    event TokensSlashedForAuction(
        address indexed stakingToken,
        uint256 slashAmount,
        uint256 underlyingAmount,
        uint256 indexed auctionId
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
        uint256 indexed auctionId,
        address stakingToken,
        address underlyingToken,
        uint256 underlyingBalanceReturned
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

    function addStakingToken(
        string memory underlyingName,
        string memory underlyingSymbol,
        uint256 cooldownSeconds,
        uint256 unstakeWindowSeconds,
        uint256 maxStakeAmount
    ) external useGovernance {
        cooldownSeconds = bound(cooldownSeconds, 1 hours, 1 weeks);
        unstakeWindowSeconds = bound(unstakeWindowSeconds, 1 hours, 1 weeks);
        maxStakeAmount = bound(maxStakeAmount, 10_000e18, 1_000_000e18);
        ERC20 underlying = new ERC20(underlyingName, underlyingSymbol);
        StakedToken stakedToken = new StakedToken(
            underlying,
            safetyModule,
            cooldownSeconds,
            unstakeWindowSeconds,
            maxStakeAmount,
            "stk".toSlice().concat(underlyingName.toSlice()),
            "stk".toSlice().concat(underlyingSymbol.toSlice())
        );
        vm.expectEmit(false, false, false, true);
        emit StakingTokenAdded(address(stakedToken));
        safetyModule.addStakingToken(stakedToken);
        testContract.addStakedToken(stakedToken);
    }
    // function addStakingToken(
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
    //         "stk".toSlice().concat(underlyingName.toSlice()),
    //         "stk".toSlice().concat(underlyingSymbol.toSlice())
    //     );
    //     vm.expectEmit(false, false, false, true);
    //     emit StakingTokenAdded(address(stakedToken));
    //     safetyModule.addStakingToken(stakedToken);
    //     vm.stopPrank();
    //     testContract.addStakedToken(stakedToken);
    // }

    function setMaxPercentUserLoss(
        uint256 maxPercentUserLoss
    ) external useGovernance {
        if (maxPercentUserLoss > 1e18) {
            vm.expectRevert(
                abi.encodeWithSignature(
                    "SafetyModule_InvalidMaxUserLossTooHigh(uint256,uint256)",
                    maxPercentUserLoss,
                    1e18
                )
            );
        }
        safetyModule.setMaxPercentUserLoss(maxPercentUserLoss);
    }

    function slashAndStartAuction(
        uint256 _stakedTokenIndexSeed,
        uint8 _numLots,
        uint128 _lotPrice,
        uint128 _initialLotSize,
        uint96 _lotIncreaseIncrement,
        uint16 _lotIncreasePeriod,
        uint32 _timeLimit
    ) external useGovernance {
        uint256 stakedTokenIndex = bound(
            _stakedTokenIndexSeed,
            0,
            safetyModule.getNumStakingTokens() - 1
        );
        _numLots = uint8(bound(_numLots, 1, 100));
        _lotPrice = uint128(bound(_lotPrice, 1e6, type(uint128).max));
        _initialLotSize = uint128(
            bound(_initialLotSize, 1e12, type(uint128).max)
        );
        _lotIncreaseIncrement = uint96(
            bound(
                _lotIncreaseIncrement,
                _initialLotSize / 100,
                _initialLotSize / 10
            )
        );
        _lotIncreasePeriod = uint16(
            bound(_lotIncreasePeriod, 30 minutes, 12 hours)
        );
        _timeLimit = uint32(bound(_timeLimit, 1 days, 4 weeks));

        IStakedToken stakedToken = safetyModule.stakingTokens(stakedTokenIndex);
        uint256 slashAmount = safetyModule.getAuctionableTotal(
            address(stakedToken)
        );
        uint256 underlyingAmount = stakedToken.previewRedeem(slashAmount);
        uint256 initialTotalTokens = uint256(_initialLotSize) *
            uint256(_numLots);
        uint256 nextAuctionId = auctionModule.nextAuctionId();
        bool isInPostSlashingState = stakedToken.isInPostSlashingState();

        if (slashAmount == 0) {
            vm.expectRevert(
                abi.encodeWithSignature("StakedToken_InvalidZeroAmount()")
            );
        } else if (isInPostSlashingState) {
            vm.expectRevert(
                abi.encodeWithSignature(
                    "StakedToken_SlashingDisabledInPostSlashingState()"
                )
            );
        } else if (underlyingAmount < initialTotalTokens) {
            vm.expectRevert(
                abi.encodeWithSignature(
                    "SafetyModule_InsufficientSlashedTokensForAuction(address,uint256,uint256)",
                    address(stakedToken.getUnderlyingToken()),
                    initialTotalTokens,
                    underlyingAmount
                )
            );
        } else {
            vm.expectEmit(false, false, false, true);
            emit TokensSlashedForAuction(
                address(stakedToken),
                slashAmount,
                underlyingAmount,
                nextAuctionId
            );
            vm.expectEmit(false, false, false, true);
            emit AuctionStarted(
                nextAuctionId,
                address(stakedToken.getUnderlyingToken()),
                uint64(block.timestamp + _timeLimit),
                _lotPrice,
                _initialLotSize,
                _numLots,
                _lotIncreaseIncrement,
                _lotIncreasePeriod
            );
        }

        uint256 auctionId = safetyModule.slashAndStartAuction(
            address(stakedToken),
            _numLots,
            _lotPrice,
            _initialLotSize,
            _lotIncreaseIncrement,
            _lotIncreasePeriod,
            _timeLimit
        );

        if (
            slashAmount == 0 ||
            isInPostSlashingState ||
            underlyingAmount < initialTotalTokens
        ) {
            return;
        }

        assertEq(auctionId, nextAuctionId, "Auction ID mismatch");
        assertTrue(
            auctionModule.isAuctionActive(auctionId),
            "Auction not active"
        );
        assertTrue(
            stakedToken.isInPostSlashingState(),
            "Staked token not in post slashing state"
        );
        assertEq(
            auctionModule.getCurrentLotSize(auctionId),
            _initialLotSize,
            "Initial lot size mismatch"
        );
        assertEq(
            auctionModule.getRemainingLots(auctionId),
            _numLots,
            "Remaining lots mismatch"
        );
    }

    function terminateAuction(uint256 auctionId) external useGovernance {
        if (auctionModule.nextAuctionId() == 0) {
            vm.expectRevert(
                abi.encodeWithSignature(
                    "AuctionModule_InvalidAuctionId(uint256)",
                    auctionId
                )
            );
            safetyModule.terminateAuction(auctionId);
            return;
        }
        auctionId = bound(auctionId, 0, auctionModule.nextAuctionId() - 1);
        IERC20 token = auctionModule.getAuctionToken(auctionId);
        IStakedToken stakedToken = safetyModule.stakingTokenByAuctionId(
            auctionId
        );
        uint256 unsoldTokens = token.balanceOf(address(auctionModule));
        uint256 prevStakedUnderlyingBalance = token.balanceOf(
            address(stakedToken)
        );
        uint256 exchangeRate = stakedToken.exchangeRate();
        bool isAuctionActive = auctionModule.isAuctionActive(auctionId);

        if (!isAuctionActive) {
            vm.expectRevert(
                abi.encodeWithSignature(
                    "AuctionModule_AuctionNotActive(uint256)",
                    auctionId
                )
            );
        } else {
            uint256 remainingLots = auctionModule.getRemainingLots(auctionId);
            uint256 finalLotSize = auctionModule.getCurrentLotSize(auctionId);
            uint256 totalTokensSold = auctionModule.tokensSoldPerAuction(
                auctionId
            );
            uint256 totalFundsRaised = auctionModule.fundsRaisedPerAuction(
                auctionId
            );
            vm.expectEmit(false, false, false, true);
            emit AuctionEnded(
                auctionId,
                uint8(remainingLots),
                finalLotSize,
                totalTokensSold,
                totalFundsRaised
            );
            if (unsoldTokens != 0) {
                vm.expectEmit(false, false, false, true);
                emit FundsReturned(address(auctionModule), unsoldTokens);
            }
            vm.expectEmit(false, false, false, true);
            emit SlashingSettled();
            vm.expectEmit(false, false, false, true);
            emit AuctionTerminated(
                auctionId,
                address(stakedToken),
                address(token),
                unsoldTokens
            );
        }

        auctionModule.terminateAuction(auctionId);
        if (!isAuctionActive) {
            return;
        }

        assertTrue(
            !auctionModule.isAuctionActive(auctionId),
            "Auction active after termination"
        );
        assertTrue(
            !stakedToken.isInPostSlashingState(),
            "Staked token in post slashing state after termination"
        );
        if (unsoldTokens != 0) {
            assertEq(
                token.balanceOf(address(auctionModule)),
                0,
                "Unsold tokens not returned from auction module"
            );
            assertEq(
                token.balanceOf(address(stakedToken)),
                prevStakedUnderlyingBalance + unsoldTokens,
                "Underlying balance mismatch after termination"
            );
            assertGt(
                stakedToken.exchangeRate(),
                exchangeRate,
                "Exchange rate mismatch after termination"
            );
        }
    }
}
