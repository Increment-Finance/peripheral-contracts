// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.16;

// contracts
import "../../../lib/increment-protocol/lib/forge-std/src/Test.sol";
import "../../../lib/increment-protocol/test/mocks/TestClearingHouse.sol";
import "../../../lib/increment-protocol/test/mocks/TestClearingHouseViewer.sol";

// interfaces
import {IPerpetual} from "increment-protocol/interfaces/IPerpetual.sol";
import {IERC20, IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

// libraries
import {LibMath} from "../../../lib/increment-protocol/contracts/lib/LibMath.sol";
import {LibPerpetual} from "../../../lib/increment-protocol/contracts/lib/LibPerpetual.sol";

contract ClearingHouseHandler is Test {
    using LibMath for uint256;
    using LibMath for int256;

    uint256 internal constant VQUOTE_INDEX = 0; // index of quote asset in curve pool
    uint256 internal constant VBASE_INDEX = 1; // index of base asset in curve pool

    TestClearingHouse public clearingHouse;
    TestClearingHouseViewer public viewer;

    address[] public actors;

    address internal currentActor;

    IPerpetual internal currentMarket;

    uint256 internal idx;

    address internal governance;

    IVault internal vault;

    IERC20Metadata internal ua;

    modifier useActor(uint256 actorIndexSeed) {
        currentActor = actors[bound(actorIndexSeed, 0, actors.length - 1)];
        vm.startPrank(currentActor);
        _;
        vm.stopPrank();
    }

    modifier usePerp(uint256 perpIndexSeed) {
        idx = clearingHouse.id(bound(perpIndexSeed, 0, clearingHouse.getNumMarkets() - 1));
        currentMarket = clearingHouse.perpetuals(idx);
        _;
    }

    modifier useGovernance() {
        vm.startPrank(governance);
        _;
        vm.stopPrank();
    }

    constructor(
        TestClearingHouse _clearingHouse,
        TestClearingHouseViewer _clearingHouseViewer,
        address[] memory _actors,
        IERC20Metadata _ua
    ) {
        clearingHouse = _clearingHouse;
        viewer = _clearingHouseViewer;
        actors = _actors;
        governance = msg.sender;
        vault = clearingHouse.vault();
        ua = _ua;
    }

    /* ********************* */
    /* Test Helper Functions */
    /* ********************* */

    function fundAndPrepareAccount(uint256 actorIndexSeed, uint256 amount) public useActor(actorIndexSeed) {
        amount = bound(amount, 100e18, 100_000e18);
        deal(address(ua), currentActor, amount);
        ua.approve(address(vault), amount);
    }

    /* ********************* */
    /*  Liquidity Functions  */
    /* ********************* */

    function provideLiquidity(uint256 actorIndexSeed, uint256 perpIndexSeed, uint256 depositAmount)
        public
        useActor(actorIndexSeed)
        usePerp(perpIndexSeed)
    {
        uint256 uaBalance = ua.balanceOf(currentActor);
        if (uaBalance <= 100e18) return;
        depositAmount = bound(depositAmount, uaBalance / 100, uaBalance);
        if (ua.allowance(currentActor, address(vault)) < depositAmount) {
            ua.approve(address(vault), depositAmount);
        }
        clearingHouse.deposit(depositAmount, ua);

        uint256 quoteAmount = depositAmount / 2;
        uint256 baseAmount = quoteAmount.wadDiv(currentMarket.indexPrice().toUint256());
        clearingHouse.provideLiquidity(idx, [quoteAmount, baseAmount], 0);
    }

    function removeLiquidity(uint256 actorIndexSeed, uint256 perpIndexSeed, uint256 reductionRatio)
        public
        useActor(actorIndexSeed)
        usePerp(perpIndexSeed)
    {
        reductionRatio = bound(reductionRatio, 1e16, 1e18);
        LibPerpetual.LiquidityProviderPosition memory position = currentMarket.getLpPosition(currentActor);
        uint256 lpBalance = position.liquidityBalance;
        uint256 lockPeriod = currentMarket.lockPeriod();
        if (lpBalance == 0) return;
        uint256 amount = lpBalance.wadMul(reductionRatio);
        uint256[2] memory expectedAmountsOut =
            viewer.getExpectedVirtualTokenAmountsFromLpTokenAmount(idx, currentActor, amount);
        if (
            currentMarket.vBase().balanceOf(address(currentMarket.market())) <= expectedAmountsOut[VBASE_INDEX] + 1
                || currentMarket.vQuote().balanceOf(address(currentMarket.market())) <= expectedAmountsOut[VQUOTE_INDEX] + 1
        ) return;
        uint256 proposedAmount =
            viewer.getLpProposedAmount(idx, currentActor, reductionRatio, 100, [uint256(0), uint256(0)], 0);
        if (block.timestamp < position.depositTime + lockPeriod) {
            vm.expectRevert(
                abi.encodeWithSignature("Perpetual_LockPeriodNotReached(uint256)", position.depositTime + lockPeriod)
            );
        }
        clearingHouse.removeLiquidity(idx, amount, [uint256(0), uint256(0)], proposedAmount, 0);
    }
}
