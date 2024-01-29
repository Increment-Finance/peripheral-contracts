// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.16;

// contracts
import "../../lib/increment-protocol/test/helpers/Deployment.MainnetFork.sol";
import "../../lib/increment-protocol/test/helpers/Utils.sol";
import "increment-protocol/ClearingHouse.sol";
import "../../lib/increment-protocol/test/mocks/TestPerpetual.sol";
import "increment-protocol/tokens/UA.sol";
import "increment-protocol/tokens/VBase.sol";
import "increment-protocol/tokens/VQuote.sol";
import {IncrementToken} from "@increment-governance/IncrementToken.sol";
import {TestPerpRewardDistributor, IRewardDistributor} from "../mocks/TestPerpRewardDistributor.sol";
import {EcosystemReserve} from "../../contracts/EcosystemReserve.sol";

// interfaces
import "increment-protocol/interfaces/ICryptoSwap.sol";
import "increment-protocol/interfaces/IPerpetual.sol";
import "increment-protocol/interfaces/IClearingHouse.sol";
import "increment-protocol/interfaces/ICurveCryptoFactory.sol";
import "increment-protocol/interfaces/IVault.sol";
import "increment-protocol/interfaces/IVBase.sol";
import "increment-protocol/interfaces/IVQuote.sol";
import "increment-protocol/interfaces/IInsurance.sol";
import {ERC20PresetFixedSupply} from "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetFixedSupply.sol";

// libraries
import {LibMath} from "increment-protocol/lib/LibMath.sol";
import "increment-protocol/lib/LibPerpetual.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {console2 as console} from "forge/console2.sol";

contract RewardsTest is Deployment, Utils {
    using LibMath for int256;
    using LibMath for uint256;

    event MarketRemovedFromRewards(address indexed market, address indexed rewardToken);
    event RewardTokenRemoved(address indexed rewardToken, uint256 unclaimedRewards, uint256 remainingBalance);
    event RewardTokenShortfall(address indexed rewardToken, uint256 shortfallAmount);
    event NewFundsAdmin(address indexed fundsAdmin);
    event EcosystemReserveUpdated(address prevEcosystemReserve, address newEcosystemReserve);

    uint88 constant INITIAL_INFLATION_RATE = 1463753e18;
    uint88 constant INITIAL_REDUCTION_FACTOR = 1.189207115e18;
    uint256 constant INITIAL_WITHDRAW_THRESHOLD = 10 days;
    uint256 constant INITIAL_MARKET_WEIGHT_0 = 7500;
    uint256 constant INITIAL_MARKET_WEIGHT_1 = 2500;

    address liquidityProviderOne = address(123);
    address liquidityProviderTwo = address(456);
    address traderOne = address(789);

    IncrementToken public rewardsToken;
    IncrementToken public rewardsToken2;

    EcosystemReserve public ecosystemReserve;
    TestPerpRewardDistributor public rewardDistributor;

    function setUp() public virtual override {
        deal(liquidityProviderOne, 100 ether);
        deal(liquidityProviderTwo, 100 ether);
        deal(traderOne, 100 ether);

        // Deploy protocol
        // increment-protocol/test/helpers/Deployment.MainnetFork.sol:setUp()
        super.setUp();

        // Deploy second perpetual contract
        _deployEthMarket();

        // Deploy the Ecosystem Reserve vault
        ecosystemReserve = new EcosystemReserve(address(this));

        // Deploy rewards tokens and distributor
        rewardsToken = new IncrementToken(20000000e18, address(this));
        rewardsToken2 = new IncrementToken(20000000e18, address(this));
        rewardsToken.unpause();
        rewardsToken2.unpause();

        uint256[] memory weights = new uint256[](2);
        weights[0] = INITIAL_MARKET_WEIGHT_0;
        weights[1] = INITIAL_MARKET_WEIGHT_1;

        rewardDistributor = new TestPerpRewardDistributor(
            INITIAL_INFLATION_RATE,
            INITIAL_REDUCTION_FACTOR,
            address(rewardsToken),
            address(clearingHouse),
            address(ecosystemReserve),
            INITIAL_WITHDRAW_THRESHOLD,
            weights
        );
        rewardDistributor.setClearingHouse(clearingHouse); // just for coverage, will likely never happen

        // Transfer all rewards tokens to the vault and approve the distributor
        rewardsToken.transfer(address(ecosystemReserve), rewardsToken.totalSupply());
        rewardsToken2.transfer(address(ecosystemReserve), rewardsToken2.totalSupply());
        ecosystemReserve.approve(rewardsToken, address(rewardDistributor), type(uint256).max);
        ecosystemReserve.approve(rewardsToken2, address(rewardDistributor), type(uint256).max);

        // initial liquidity
        fundAndPrepareAccount(liquidityProviderOne, 100_000e18, vault, ua);
        _provideLiquidity(10_000e18, liquidityProviderOne, perpetual);
        _provideLiquidity(10_000e18, liquidityProviderOne, eth_perpetual);
        address[] memory markets = new address[](2);
        markets[0] = address(perpetual);
        markets[1] = address(eth_perpetual);
        vm.startPrank(liquidityProviderOne);
        rewardDistributor.registerPositions(markets);
        vm.stopPrank();

        // Connect ClearingHouse to RewardsDistributor
        clearingHouse.addRewardContract(rewardDistributor);

        // Update ClearingHouse params to remove min open notional
        clearingHouse.setParameters(
            IClearingHouse.ClearingHouseParams({
                minMargin: 0.025 ether,
                minMarginAtCreation: 0.055 ether,
                minPositiveOpenNotional: 0 ether,
                liquidationReward: 0.015 ether,
                insuranceRatio: 0.1 ether,
                liquidationRewardInsuranceShare: 0.5 ether,
                liquidationDiscount: 0.95 ether,
                nonUACollSeizureDiscount: 0.75 ether,
                uaDebtSeizureThreshold: 10000 ether
            })
        );
        vBase.setHeartBeat(30 days);
        eth_vBase.setHeartBeat(30 days);
    }

    /* ******************** */
    /*   RewardController   */
    /* ******************** */

    // run tests via source .env && forge test --match <TEST_NAME> --fork-url $ETH_NODE_URI_MAINNET -vv

    function testDeployment() public {
        assertEq(clearingHouse.getNumMarkets(), 2, "Market count mismatch");
        assertEq(rewardDistributor.getRewardTokenCount(), 1, "Token count mismatch");
        address token = rewardDistributor.rewardTokens(0);
        assertEq(token, address(rewardsToken), "Reward token mismatch");
        assertEq(rewardDistributor.getInitialTimestamp(token), block.timestamp, "Initial timestamp mismatch");
        assertEq(
            rewardDistributor.getInitialInflationRate(token), INITIAL_INFLATION_RATE, "Base inflation rate mismatch"
        );
        assertEq(rewardDistributor.getInflationRate(token), INITIAL_INFLATION_RATE, "Inflation rate mismatch");
        assertEq(rewardDistributor.getReductionFactor(token), INITIAL_REDUCTION_FACTOR, "Reduction factor mismatch");
        assertEq(
            rewardDistributor.getRewardWeight(address(token), address(perpetual)),
            INITIAL_MARKET_WEIGHT_0,
            "Market weight mismatch"
        );
        assertEq(
            rewardDistributor.getRewardWeight(address(token), address(eth_perpetual)),
            INITIAL_MARKET_WEIGHT_1,
            "Market weight mismatch"
        );
        assertEq(
            rewardDistributor.earlyWithdrawalThreshold(),
            INITIAL_WITHDRAW_THRESHOLD,
            "Early withdrawal threshold mismatch"
        );
    }

    function testInflationAndReduction(
        uint256 timeIncrement,
        uint88 initialInflationRate,
        uint88 initialReductionFactor
    ) public {
        /* bounds */
        initialInflationRate = uint88(bound(initialInflationRate, 1e18, 5e24));
        initialReductionFactor = uint88(bound(initialReductionFactor, 1e18, 2e18));

        // Update inflation rate and reduction factor
        rewardDistributor.updateInitialInflationRate(address(rewardsToken), initialInflationRate);
        rewardDistributor.updateReductionFactor(address(rewardsToken), initialReductionFactor);

        // Set heartbeats to 1 year
        vBase.setHeartBeat(365 days);
        eth_vBase.setHeartBeat(365 days);

        // Keeper bot will ensure that market rewards are updated every month at least
        timeIncrement = bound(timeIncrement, 1 days, 7 days);
        uint256 endYear = block.timestamp + 365 days;
        uint256 updatesPerYear = 365 days / timeIncrement;

        // Accrue rewards throughout the year
        for (uint256 i = 0; i < updatesPerYear; i++) {
            skip(timeIncrement);
            rewardDistributor.accrueRewards(liquidityProviderOne);
        }

        // Skip to the end of the year
        vm.warp(endYear);

        // Check accrued rewards
        rewardDistributor.accrueRewards(liquidityProviderOne);
        uint256 accruedRewards = rewardDistributor.rewardsAccruedByUser(liquidityProviderOne, address(rewardsToken));

        // Accrued rewards should be within 5% of the average inflation rate
        uint256 currentInflationRate = rewardDistributor.getInflationRate(address(rewardsToken));
        uint256 approxRewards = (currentInflationRate + initialInflationRate) / 2;
        assertApproxEqRel(accruedRewards, approxRewards, 5e16, "Incorrect annual rewards");
    }

    function testRewardControllerErrors(
        uint88 inflationRate,
        uint88 reductionFactor,
        address[] memory markets,
        uint256[] memory marketWeights,
        address token
    ) public {
        vm.assume(token != address(rewardsToken) && token != address(rewardsToken2) && token != address(0));
        vm.assume(markets.length > 2);
        vm.assume(marketWeights.length > 2);
        vm.assume(markets.length != marketWeights.length);
        vm.assume(marketWeights[0] <= type(uint256).max / 2 && marketWeights[1] <= type(uint256).max / 2);
        vm.assume(marketWeights[0] + marketWeights[1] != 10000);
        inflationRate = uint88(bound(inflationRate, 5e24 + 1, type(uint88).max));
        reductionFactor = uint88(bound(reductionFactor, 0, 1e18 - 1));

        // test wrong token address
        _expectInvalidRewardTokenAddress(token);
        rewardDistributor.updateRewardWeights(token, markets, marketWeights);
        _expectInvalidRewardTokenAddress(token);
        rewardDistributor.updateInitialInflationRate(token, inflationRate);
        _expectInvalidRewardTokenAddress(token);
        rewardDistributor.updateReductionFactor(token, reductionFactor);
        _expectInvalidRewardTokenAddress(token);
        rewardDistributor.setPaused(token, true);

        // test max inflation rate & min reduction factor
        _expectAboveMaxInflationRate(inflationRate, 5e24);
        rewardDistributor.updateInitialInflationRate(address(rewardsToken), inflationRate);
        _expectAboveMaxInflationRate(inflationRate, 5e24);
        rewardDistributor.addRewardToken(address(rewardsToken), inflationRate, reductionFactor, markets, marketWeights);
        _expectBelowMinReductionFactor(reductionFactor, 1e18);
        rewardDistributor.updateReductionFactor(address(rewardsToken), reductionFactor);
        _expectBelowMinReductionFactor(reductionFactor, 1e18);
        rewardDistributor.addRewardToken(
            address(rewardsToken), INITIAL_INFLATION_RATE, reductionFactor, markets, marketWeights
        );

        // test incorrect market weights
        _expectIncorrectWeightsCount(marketWeights.length, markets.length);
        rewardDistributor.updateRewardWeights(address(rewardsToken), markets, marketWeights);
        address[] memory markets2 = new address[](2);
        markets2[0] = markets[0];
        markets2[1] = markets[1];
        uint256[] memory marketWeights2 = new uint256[](2);
        marketWeights2[0] = marketWeights[0];
        marketWeights2[1] = marketWeights[1];
        if (marketWeights2[0] > 10000) {
            _expectWeightExceedsMax(marketWeights2[0], 10000);
        } else if (marketWeights[1] > 10000) {
            _expectWeightExceedsMax(marketWeights2[1], 10000);
        } else {
            _expectIncorrectWeightsSum(marketWeights2[0] + marketWeights2[1], 10000);
        }
        rewardDistributor.updateRewardWeights(address(rewardsToken), markets2, marketWeights2);
        if (marketWeights2[0] > 10000) {
            _expectWeightExceedsMax(marketWeights2[0], 10000);
        } else if (marketWeights[1] > 10000) {
            _expectWeightExceedsMax(marketWeights2[1], 10000);
        } else {
            _expectIncorrectWeightsSum(marketWeights2[0] + marketWeights2[1], 10000);
        }
        rewardDistributor.addRewardToken(
            address(rewardsToken2), INITIAL_INFLATION_RATE, INITIAL_REDUCTION_FACTOR, markets2, marketWeights2
        );
    }

    /* ******************* */
    /*  RewardDistributor  */
    /* ******************* */

    function testDelayedDeposit(uint256 providedLiquidity1, uint256 providedLiquidity2) public {
        /* bounds */
        providedLiquidity1 = bound(providedLiquidity1, 100e18, 10_000e18);
        providedLiquidity2 = bound(providedLiquidity2, 100e18, 10_000e18);

        // skip some time
        skip(10 days);

        // get the initial cumulative rewards per token after 10 days of only user 1's liquidity
        uint256 expectedCumulativeRewards1 =
            _calcExpectedCumulativeRewards(address(rewardsToken), address(perpetual), 10 days);
        uint256 expectedCumulativeRewards2 =
            _calcExpectedCumulativeRewards(address(rewardsToken), address(eth_perpetual), 10 days);

        // provide liquidity from user 2
        _provideLiquidityBothPerps(liquidityProviderTwo, providedLiquidity1, providedLiquidity2);

        // skip some more time
        skip(10 days);

        // accrue rewards for user 1 with initial liquidity 10_000e18
        _accrueAndCheckUserRewards(address(rewardsToken), liquidityProviderOne, 0);

        // check cumulative rewards after 20 days
        uint256 cumulativeRewards1 =
            rewardDistributor.cumulativeRewardPerLpToken(address(rewardsToken), address(perpetual));
        uint256 cumulativeRewards2 =
            rewardDistributor.cumulativeRewardPerLpToken(address(rewardsToken), address(eth_perpetual));

        // add the additional cumulative rewards after 10 more days with both users' liquidity
        expectedCumulativeRewards1 += _calcExpectedCumulativeRewards(address(rewardsToken), address(perpetual), 10 days);
        expectedCumulativeRewards2 +=
            _calcExpectedCumulativeRewards(address(rewardsToken), address(eth_perpetual), 10 days);

        assertApproxEqRel(
            cumulativeRewards1,
            expectedCumulativeRewards1,
            5e16, // 5%, accounts for reduction factor
            "Incorrect cumulative rewards"
        );
        assertApproxEqRel(
            cumulativeRewards2,
            expectedCumulativeRewards2,
            5e16, // 5%, accounts for reduction factor
            "Incorrect cumulative rewards"
        );

        // check rewards for user 2
        _accrueAndCheckUserRewards(address(rewardsToken), liquidityProviderTwo, 0);
    }

    function testMultipleRewardTokens(
        uint256 providedLiquidity1,
        uint256 providedLiquidity2,
        uint88 inflationRate2,
        uint88 reductionFactor2,
        uint256 marketWeight1
    ) public {
        /* bounds */
        providedLiquidity1 = bound(providedLiquidity1, 100e18, 10_000e18);
        providedLiquidity2 = bound(providedLiquidity2, 100e18, 10_000e18);
        inflationRate2 = uint88(bound(inflationRate2, 1e20, 5e24));
        reductionFactor2 = uint88(bound(reductionFactor2, 1e18, 5e18));
        marketWeight1 = marketWeight1 % 10000;

        _provideLiquidityBothPerps(liquidityProviderTwo, providedLiquidity1, providedLiquidity2);

        // skip some time
        skip(10 days);

        // add a new reward token
        rewardsToken2 = _addRewardToken(marketWeight1, 20000000e18, inflationRate2, reductionFactor2);

        // skip some more time
        skip(10 days);

        // accrue rewards for both tokens and users
        uint256[] memory previewAccruals1 = _viewNewRewardAccrual(liquidityProviderOne);
        uint256[] memory previewAccruals2 = _viewNewRewardAccrual(liquidityProviderTwo);
        rewardDistributor.accrueRewards(liquidityProviderOne);
        rewardDistributor.accrueRewards(liquidityProviderTwo);

        // check that accrued rewards are correct for both tokens and users
        uint256[][] memory accruedRewards = new uint256[][](2);
        for (uint256 i; i < 2; i++) {
            accruedRewards[i] = new uint256[](2);
            address token = i == 0 ? address(rewardsToken) : address(rewardsToken2);
            uint256 skipTime = i == 0 ? 20 days : 10 days;
            for (uint256 j; j < 2; j++) {
                address user = j == 0 ? liquidityProviderOne : liquidityProviderTwo;
                accruedRewards[i][j] = _checkRewards(token, user, skipTime, 0);
                assertApproxEqRel(
                    accruedRewards[i][j],
                    j == 0 ? previewAccruals1[i] : previewAccruals2[i],
                    1e15, // 0.1%
                    "Incorrect accrued rewards preview"
                );
            }
        }

        // remove reward token 2
        vm.expectEmit(false, false, false, true);
        emit RewardTokenRemoved(
            address(rewardsToken2),
            accruedRewards[1][0] + accruedRewards[1][1],
            20000000e18 - accruedRewards[1][0] - accruedRewards[1][1]
        );
        rewardDistributor.removeRewardToken(address(rewardsToken2));

        // claim rewards
        vm.startPrank(liquidityProviderTwo);
        address[] memory tokens = new address[](2);
        tokens[0] = address(rewardsToken);
        tokens[1] = address(rewardsToken2);
        rewardDistributor.claimRewardsFor(liquidityProviderTwo, tokens);
        // try claiming twice in a row to ensure rewards aren't distributed twice
        rewardDistributor.claimRewardsFor(liquidityProviderTwo, tokens);

        // check claimed rewards for user 2
        assertEq(rewardsToken.balanceOf(liquidityProviderTwo), accruedRewards[0][1], "Incorrect claimed balance");
        assertEq(rewardsToken2.balanceOf(liquidityProviderTwo), accruedRewards[1][1], "Incorrect claimed balance");

        // make sure user 1's accrued rewards are still available after removing token 2,
        // while the rest of the supply of token 2 has been transfered back to governance
        assertEq(
            rewardsToken2.balanceOf(address(ecosystemReserve)),
            accruedRewards[1][0],
            "Incorrect remaining accrued balance"
        );
        assertEq(
            rewardsToken2.balanceOf(address(this)),
            20000000e18 - accruedRewards[1][1] - accruedRewards[1][0],
            "Incorrect returned balance"
        );
    }

    function testShortfallMultipleRewards(
        uint256 providedLiquidity1,
        uint256 providedLiquidity2,
        uint88 inflationRate2,
        uint88 reductionFactor2,
        uint256 marketWeight1
    ) public {
        /* bounds */
        providedLiquidity1 = bound(providedLiquidity1, 100e18, 10_000e18);
        providedLiquidity2 = bound(providedLiquidity2, 100e18, 10_000e18);
        inflationRate2 = uint88(bound(inflationRate2, 1e24, 5e24));
        reductionFactor2 = uint88(bound(reductionFactor2, 1e18, 5e18));
        marketWeight1 = marketWeight1 % 10000;

        _provideLiquidityBothPerps(liquidityProviderTwo, providedLiquidity1, providedLiquidity2);

        // add a new reward token with a low total supply
        rewardsToken2 = _addRewardToken(marketWeight1, 10e18, inflationRate2, reductionFactor2);

        // skip some time
        skip(10 days);

        // check previews and rewards for both tokens
        uint256[] memory previewAccruals = _viewNewRewardAccrual(liquidityProviderTwo);
        rewardDistributor.accrueRewards(liquidityProviderTwo);
        uint256 accruedRewards1 = _checkRewards(address(rewardsToken), liquidityProviderTwo, 10 days, 0);
        assertApproxEqRel(
            accruedRewards1,
            previewAccruals[0],
            1e15, // 0.1%
            "Incorrect accrued rewards preview: token 1"
        );
        uint256 accruedRewards2 = _checkRewards(address(rewardsToken2), liquidityProviderTwo, 10 days, 0);
        assertApproxEqRel(
            accruedRewards2,
            previewAccruals[1],
            1e15, // 0.1%
            "Incorrect accrued rewards preview: token 2"
        );

        // claim rewards, causing shortfall for token 2
        vm.expectEmit(false, false, false, true);
        emit RewardTokenShortfall(address(rewardsToken2), accruedRewards2 - 10e18);
        rewardDistributor.claimRewardsFor(liquidityProviderTwo);
        assertEq(rewardsToken.balanceOf(liquidityProviderTwo), accruedRewards1, "Incorrect claimed balance");
        assertEq(rewardsToken2.balanceOf(liquidityProviderTwo), 10e18, "Incorrect claimed balance");
        assertEq(
            rewardDistributor.totalUnclaimedRewards(address(rewardsToken2)),
            accruedRewards2 - 10e18,
            "Incorrect unclaimed rewards"
        );

        // skip some more time
        skip(10 days);

        // accrue more rewards by adding more liquidity
        _provideLiquidityBothPerps(liquidityProviderTwo, providedLiquidity1, providedLiquidity2);

        // check that rewards are still accruing for token 2
        assertGt(
            rewardDistributor.rewardsAccruedByUser(liquidityProviderTwo, address(rewardsToken2)),
            accruedRewards2,
            "Rewards not accrued after adding more liquidity"
        );
        accruedRewards2 = rewardDistributor.rewardsAccruedByUser(liquidityProviderTwo, address(rewardsToken2));

        // fail to claim rewards again after token 2 is depleted
        rewardDistributor.claimRewardsFor(liquidityProviderTwo);
        assertEq(rewardsToken2.balanceOf(liquidityProviderTwo), 10e18, "Tokens claimed after token 2 depleted");
        assertEq(
            rewardDistributor.totalUnclaimedRewards(address(rewardsToken2)),
            accruedRewards2,
            "Incorrect unclaimed rewards after second accrual"
        );
    }

    function testEarlyWithdrawal(
        uint256 providedLiquidity1,
        uint256 providedLiquidity2,
        uint256 reductionRatio,
        uint256 thresholdTime,
        uint256 skipTime
    ) public {
        /* bounds */
        providedLiquidity1 = bound(providedLiquidity1, 100e18, 10_000e18);
        providedLiquidity2 = bound(providedLiquidity2, 100e18, 10_000e18);
        reductionRatio = bound(reductionRatio, 1e16, 5e17);
        thresholdTime = bound(thresholdTime, 1 days, 10 days);
        skipTime = bound(skipTime, thresholdTime / 10, thresholdTime / 2);

        // set early withdrawal threshold and provide liquidity
        rewardDistributor.setEarlyWithdrawalThreshold(thresholdTime);
        _provideLiquidityBothPerps(liquidityProviderTwo, providedLiquidity1, providedLiquidity2);

        // store initial state before removing liquidity
        uint256[] memory balances = _getUserBalances(liquidityProviderTwo);
        uint256[] memory prevCumRewards = _getCumulativeRewardsByToken(address(rewardsToken));
        uint256[] memory prevTotalLiquidity = _getTotalLiquidityPerMarket();

        // skip some time
        skip(skipTime);

        // remove some liquidity from and accrue rewards for first perpetual
        _removeSomeLiquidity(liquidityProviderTwo, perpetual, reductionRatio);

        // check that early withdrawal penalty was applied to rewards
        uint256[] memory skipTimes = new uint256[](2);
        skipTimes[0] = skipTime;
        uint256 accruedRewards = _checkRewards(
            address(rewardsToken), liquidityProviderTwo, skipTimes, balances, prevCumRewards, prevTotalLiquidity, 0
        );

        // skip to the end of the early withdrawal window
        skip(thresholdTime - skipTime);
        skipTimes[0] = thresholdTime - skipTime;
        skipTimes[1] = thresholdTime;

        // store updated balance and cumulative rewards per lp token before removing more liquidity
        balances[0] = perpetual.getLpLiquidity(liquidityProviderTwo);
        prevCumRewards = _getCumulativeRewardsByToken(address(rewardsToken));
        prevTotalLiquidity = _getTotalLiquidityPerMarket();

        // remove some liquidity again from first perpetual
        _removeSomeLiquidity(liquidityProviderTwo, perpetual, reductionRatio);

        // remove all liquidity from and accrue rewards for second perpetual
        _removeAllLiquidity(liquidityProviderTwo, eth_perpetual);

        // check that penalty was applied again, but only for the first perpetual
        accruedRewards = _checkRewards(
            address(rewardsToken),
            liquidityProviderTwo,
            skipTimes,
            balances,
            prevCumRewards,
            prevTotalLiquidity,
            accruedRewards
        );

        // check that the early withdrawal timer is updated correctly after partial and full withdrawals
        assertEq(
            rewardDistributor.withdrawTimerStartByUserByMarket(liquidityProviderTwo, address(perpetual)),
            block.timestamp,
            "Early withdrawal timer not reset to one after partial withdrawal"
        );
        assertEq(
            rewardDistributor.withdrawTimerStartByUserByMarket(liquidityProviderTwo, address(eth_perpetual)),
            0,
            "Early withdrawal timer not reset to zero after full withdrawal"
        );

        // check that early withdrawal timer is reset after adding liquidity
        skip(skipTime);
        _provideLiquidityBothPerps(liquidityProviderTwo, providedLiquidity1, providedLiquidity2);
        assertEq(
            rewardDistributor.withdrawTimerStartByUserByMarket(liquidityProviderTwo, address(perpetual)),
            block.timestamp,
            "Early withdrawal timer not reset after adding liquidity"
        );
    }

    function testPausingAccrual(uint256 providedLiquidity1) public {
        /* bounds */
        providedLiquidity1 = bound(providedLiquidity1, 100e18, 10_000e18);
        require(providedLiquidity1 >= 100e18 && providedLiquidity1 <= 10_000e18);

        // add liquidity to first perpetual
        fundAndPrepareAccount(liquidityProviderTwo, providedLiquidity1, vault, ua);
        _provideLiquidity(providedLiquidity1, liquidityProviderTwo, perpetual);

        // pause accrual
        vm.startPrank(address(this));
        rewardDistributor.setPaused(address(rewardsToken), true);
        bool paused = rewardDistributor.isTokenPaused(address(rewardsToken));
        assertTrue(paused, "Rewards not paused");

        // skip some time
        skip(10 days);

        // check that no rewards were accrued
        rewardDistributor.accrueRewards(liquidityProviderTwo);
        uint256 accruedRewards = rewardDistributor.rewardsAccruedByUser(liquidityProviderTwo, address(rewardsToken));
        assertEq(accruedRewards, 0, "Rewards accrued while paused");

        // unpause accrual
        rewardDistributor.setPaused(address(rewardsToken), false);
        paused = rewardDistributor.isTokenPaused(address(rewardsToken));
        assertTrue(!paused, "Rewards not unpaused");

        // skip some more time
        skip(10 days);

        // check that rewards were accrued
        rewardDistributor.claimRewardsFor(liquidityProviderTwo);
        accruedRewards = rewardsToken.balanceOf(liquidityProviderTwo);
        assertGt(accruedRewards, 0, "Rewards not accrued after unpausing");
    }

    function testAddNewMarket(uint256 providedLiquidity1, uint256 providedLiquidity2, uint256 providedLiquidity3)
        public
    {
        /* bounds */
        providedLiquidity1 = bound(providedLiquidity1, 100e18, 10_000e18);
        providedLiquidity2 = bound(providedLiquidity2, 100e18, 10_000e18);
        providedLiquidity3 = bound(providedLiquidity3, 100e18, 10_000e18);

        // add liquidity to first two perpetuals
        _provideLiquidityBothPerps(liquidityProviderTwo, providedLiquidity1, providedLiquidity2);

        // deploy new market contracts
        TestPerpetual perpetual3 = _deployTestPerpetual();
        clearingHouse.allowListPerpetual(perpetual3);

        // skip some time
        skip(10 days);

        // get initial expected cumulative rewards
        uint256 expectedCumulativeRewards1 =
            _calcExpectedCumulativeRewards(address(rewardsToken), address(perpetual), 10 days);
        uint256 expectedCumulativeRewards2 =
            _calcExpectedCumulativeRewards(address(rewardsToken), address(eth_perpetual), 10 days);
        uint256 expectedCumulativeRewards3 = 0;

        // set new market weights
        {
            address[] memory markets = new address[](3);
            markets[0] = address(perpetual);
            markets[1] = address(eth_perpetual);
            markets[2] = address(perpetual3);
            uint256[] memory marketWeights = new uint256[](3);
            marketWeights[0] = 5000;
            marketWeights[1] = 3000;
            marketWeights[2] = 2000;
            rewardDistributor.updateRewardWeights(address(rewardsToken), markets, marketWeights);
        }

        // check that rewards were accrued to first two perpetuals at previous weights
        rewardDistributor.accrueRewards(liquidityProviderTwo);
        uint256 cumulativeRewards1 =
            rewardDistributor.cumulativeRewardPerLpToken(address(rewardsToken), address(perpetual));
        uint256 cumulativeRewards2 =
            rewardDistributor.cumulativeRewardPerLpToken(address(rewardsToken), address(eth_perpetual));
        uint256 cumulativeRewards3 =
            rewardDistributor.cumulativeRewardPerLpToken(address(rewardsToken), address(perpetual3));
        assertApproxEqRel(
            cumulativeRewards1,
            expectedCumulativeRewards1,
            5e16, // 5%, accounts for reduction factor
            "Incorrect cumulative rewards 1 after 10 days"
        );
        assertApproxEqRel(
            cumulativeRewards2,
            expectedCumulativeRewards2,
            5e16, // 5%, accounts for reduction factor
            "Incorrect cumulative rewards 2 after 10 days"
        );
        assertEq(cumulativeRewards3, expectedCumulativeRewards3, "Incorrect cumulative rewards 3 after 10 days");

        // provide liquidity to new perpetual
        _provideLiquidity(10_000e18, liquidityProviderOne, perpetual3);
        fundAndPrepareAccount(liquidityProviderTwo, providedLiquidity3, vault, ua);
        _provideLiquidity(providedLiquidity3, liquidityProviderTwo, perpetual3);

        // skip some more time
        skip(10 days);

        // check that rewards were accrued to all three perpetuals at new weights
        rewardDistributor.accrueRewards(liquidityProviderTwo);
        cumulativeRewards1 = rewardDistributor.cumulativeRewardPerLpToken(address(rewardsToken), address(perpetual));
        cumulativeRewards2 = rewardDistributor.cumulativeRewardPerLpToken(address(rewardsToken), address(eth_perpetual));
        cumulativeRewards3 = rewardDistributor.cumulativeRewardPerLpToken(address(rewardsToken), address(perpetual3));
        expectedCumulativeRewards1 += _calcExpectedCumulativeRewards(address(rewardsToken), address(perpetual), 10 days);
        expectedCumulativeRewards2 +=
            _calcExpectedCumulativeRewards(address(rewardsToken), address(eth_perpetual), 10 days);
        expectedCumulativeRewards3 +=
            _calcExpectedCumulativeRewards(address(rewardsToken), address(perpetual3), 10 days);
        assertApproxEqRel(
            cumulativeRewards1,
            expectedCumulativeRewards1,
            5e16, // 5%, accounts for reduction factor
            "Incorrect cumulative rewards 1 after 20 days"
        );
        assertApproxEqRel(
            cumulativeRewards2,
            expectedCumulativeRewards2,
            5e16, // 5%, accounts for reduction factor
            "Incorrect cumulative rewards 2 after 20 days"
        );
        assertApproxEqRel(
            cumulativeRewards3,
            expectedCumulativeRewards3,
            5e16, // 5%, accounts for reduction factor
            "Incorrect cumulative rewards 3 after 20 days"
        );
    }

    function testDelistAndReplace(uint256 providedLiquidity1, uint256 providedLiquidity2, uint256 providedLiquidity3)
        public
    {
        /* bounds */
        providedLiquidity1 = bound(providedLiquidity1, 100e18, 10_000e18);
        providedLiquidity2 = bound(providedLiquidity2, 100e18, 10_000e18);
        providedLiquidity3 = bound(providedLiquidity3, 100e18, 10_000e18);

        // add liquidity to first two perpetuals
        _provideLiquidityBothPerps(liquidityProviderTwo, providedLiquidity1, providedLiquidity2);

        // skip some time
        skip(10 days);

        // check that rewards were accrued to first two perpetuals at previous weights
        rewardDistributor.accrueRewards(liquidityProviderTwo);
        uint256 cumulativeRewards1 =
            rewardDistributor.cumulativeRewardPerLpToken(address(rewardsToken), address(perpetual));
        uint256 cumulativeRewards2 =
            rewardDistributor.cumulativeRewardPerLpToken(address(rewardsToken), address(eth_perpetual));
        uint256 expectedCumulativeRewards1 =
            _calcExpectedCumulativeRewards(address(rewardsToken), address(perpetual), 10 days);
        uint256 expectedCumulativeRewards2 =
            _calcExpectedCumulativeRewards(address(rewardsToken), address(eth_perpetual), 10 days);
        assertApproxEqRel(
            cumulativeRewards1,
            expectedCumulativeRewards1,
            5e16, // 5%, accounts for reduction factor
            "Incorrect cumulative rewards"
        );
        assertApproxEqRel(
            cumulativeRewards2,
            expectedCumulativeRewards2,
            5e16, // 5%, accounts for reduction factor
            "Incorrect cumulative rewards"
        );

        // delist second perpertual
        console.log("Delisting second perpetual: %s", address(eth_perpetual));
        vm.startPrank(address(this));
        clearingHouse.delistPerpetual(eth_perpetual);

        // replace it with a new perpetual
        TestPerpetual perpetual3 = _deployTestPerpetual();
        clearingHouse.allowListPerpetual(perpetual3);
        console.log("Added new perpetual: %s", address(perpetual3));
        assertEq(clearingHouse.getNumMarkets(), 2, "Incorrect number of markets");

        rewardDistributor.initMarketStartTime(address(perpetual3));
        assertEq(
            _viewNewRewardAccrual(address(perpetual3), liquidityProviderTwo, address(rewardsToken)),
            0,
            "Incorrect accrued rewards preview for new perp without liquidity"
        );

        // set new market weights
        address[] memory markets = new address[](2);
        uint256[] memory marketWeights = new uint256[](2);
        markets[0] = address(perpetual);
        markets[1] = address(perpetual3);
        marketWeights[0] = INITIAL_MARKET_WEIGHT_0;
        marketWeights[1] = INITIAL_MARKET_WEIGHT_1;
        vm.expectEmit(false, false, false, true);
        emit MarketRemovedFromRewards(address(eth_perpetual), address(rewardsToken));
        rewardDistributor.updateRewardWeights(address(rewardsToken), markets, marketWeights);

        // provide liquidity to new perpetual
        _provideLiquidity(10_000e18, liquidityProviderOne, perpetual3);
        fundAndPrepareAccount(liquidityProviderTwo, providedLiquidity3, vault, ua);
        _provideLiquidity(providedLiquidity3, liquidityProviderTwo, perpetual3);

        // skip some time
        skip(10 days);

        // check that rewards were accrued to first perpetual and new one at previous weights
        rewardDistributor.accrueRewards(liquidityProviderTwo);
        cumulativeRewards1 = rewardDistributor.cumulativeRewardPerLpToken(address(rewardsToken), address(perpetual));
        cumulativeRewards2 = rewardDistributor.cumulativeRewardPerLpToken(address(rewardsToken), address(perpetual3));
        expectedCumulativeRewards1 = _calcExpectedCumulativeRewards(address(rewardsToken), address(perpetual), 20 days);
        expectedCumulativeRewards2 = _calcExpectedCumulativeRewards(address(rewardsToken), address(perpetual3), 10 days);
        assertApproxEqRel(
            cumulativeRewards1,
            expectedCumulativeRewards1,
            5e16, // 5%, accounts for reduction factor
            "Incorrect cumulative rewards"
        );
        assertApproxEqRel(
            cumulativeRewards2,
            expectedCumulativeRewards2,
            5e16, // 5%, accounts for reduction factor
            "Incorrect cumulative rewards"
        );
    }

    function testPreExistingLiquidity(uint256 providedLiquidity1, uint256 providedLiquidity2) public {
        /* bounds */
        providedLiquidity1 = bound(providedLiquidity1, 100e18, 10_000e18);
        providedLiquidity2 = bound(providedLiquidity2, 100e18, 10_000e18);

        // add liquidity to first two perpetuals
        _provideLiquidityBothPerps(liquidityProviderTwo, providedLiquidity1, providedLiquidity2);

        // redeploy rewards distributor
        uint256[] memory weights = new uint256[](2);
        weights[0] = INITIAL_MARKET_WEIGHT_0;
        weights[1] = INITIAL_MARKET_WEIGHT_1;

        TestPerpRewardDistributor newRewardsDistributor = new TestPerpRewardDistributor(
            INITIAL_INFLATION_RATE,
            INITIAL_REDUCTION_FACTOR,
            address(rewardsToken),
            address(clearingHouse),
            address(ecosystemReserve),
            INITIAL_WITHDRAW_THRESHOLD,
            weights
        );
        vm.startPrank(address(this));
        ecosystemReserve.approve(rewardsToken, address(newRewardsDistributor), type(uint256).max);
        ecosystemReserve.approve(rewardsToken2, address(newRewardsDistributor), type(uint256).max);
        vm.stopPrank();

        // Connect ClearingHouse to new RewardsDistributor
        vm.startPrank(address(this));
        clearingHouse.addRewardContract(newRewardsDistributor);

        // skip some time
        skip(10 days);

        // before registering positions, expect accruing rewards to fail
        _expectUserPositionMismatch(
            liquidityProviderTwo, address(perpetual), 0, perpetual.getLpLiquidity(liquidityProviderTwo)
        );
        newRewardsDistributor.accrueRewards(liquidityProviderTwo);

        // register user positions
        address[] memory markets = new address[](2);
        markets[0] = address(perpetual);
        markets[1] = address(eth_perpetual);
        vm.startPrank(liquidityProviderOne);
        newRewardsDistributor.registerPositions(markets);
        vm.startPrank(liquidityProviderTwo);
        newRewardsDistributor.registerPositions(markets);

        // skip some time
        skip(10 days);

        // check that rewards were accrued correctly to the markets,
        // regardless of when the users registered their positions
        newRewardsDistributor.accrueRewards(liquidityProviderTwo);
        uint256 cumulativeRewards1 =
            newRewardsDistributor.cumulativeRewardPerLpToken(address(rewardsToken), address(perpetual));
        uint256 cumulativeRewards2 =
            newRewardsDistributor.cumulativeRewardPerLpToken(address(rewardsToken), address(eth_perpetual));
        uint256 expectedCumulativeRewards1 =
            _calcExpectedCumulativeRewards(address(rewardsToken), address(perpetual), 20 days);
        uint256 expectedCumulativeRewards2 =
            _calcExpectedCumulativeRewards(address(rewardsToken), address(eth_perpetual), 20 days);
        assertApproxEqRel(
            cumulativeRewards1,
            expectedCumulativeRewards1,
            5e16, // 5%, accounts for reduction factor
            "Incorrect cumulative rewards"
        );
        assertApproxEqRel(
            cumulativeRewards2,
            expectedCumulativeRewards2,
            5e16, // 5%, accounts for reduction factor
            "Incorrect cumulative rewards"
        );
    }

    function testRewardDistributorErrors() public {
        // updatePosition
        _expectCallerIsNotClearingHouse(address(this));
        rewardDistributor.updatePosition(address(perpetual), liquidityProviderOne);

        // initMarketStartTime
        _expectAlreadyInitializedStartTime(address(perpetual));
        rewardDistributor.initMarketStartTime(address(perpetual));

        // removeRewardToken
        _expectInvalidRewardTokenAddress(address(0));
        rewardDistributor.removeRewardToken(address(0));

        // registerPositions
        vm.startPrank(liquidityProviderOne);
        address[] memory markets = new address[](1);
        markets[0] = address(perpetual);
        uint256 position = perpetual.getLpLiquidity(liquidityProviderOne);
        _expectPositionAlreadyRegistered(liquidityProviderOne, address(perpetual), position);
        rewardDistributor.registerPositions(markets);
        vm.stopPrank();

        // addRewardToken
        vm.startPrank(address(this));
        address[] memory markets2 = new address[](2);
        markets2[0] = address(perpetual);
        markets2[1] = address(eth_perpetual);
        uint256[] memory weights1 = new uint256[](1);
        _expectIncorrectWeightsCount(1, 2);
        rewardDistributor.addRewardToken(address(rewardsToken), 1e18, 1e18, markets2, weights1);
        uint256[] memory weights2 = new uint256[](2);
        weights2[0] = type(uint256).max;
        _expectWeightExceedsMax(type(uint256).max, 10000);
        rewardDistributor.addRewardToken(address(rewardsToken), 1e18, 1e18, markets2, weights2);
        weights2[0] = 0;
        _expectIncorrectWeightsSum(0, 10000);
        rewardDistributor.addRewardToken(address(rewardsToken), 1e18, 1e18, markets2, weights2);
        weights2[0] = 5000;
        weights2[1] = 5000;
        for (uint256 i; i < 9; ++i) {
            rewardDistributor.addRewardToken(address(rewardsToken), 1e18, 1e18, markets2, weights2);
        }
        _expectAboveMaxRewardTokens(10);
        rewardDistributor.addRewardToken(address(rewardsToken), 1e18, 1e18, markets2, weights2);

        // paused
        vm.startPrank(address(this));
        clearingHouse.pause();
        assertTrue(rewardDistributor.paused(), "Reward distributor not paused when clearing house is paused");
        vm.startPrank(liquidityProviderOne);
        vm.expectRevert(bytes("Pausable: paused"));
        rewardDistributor.claimRewardsFor(liquidityProviderOne);
        vm.stopPrank();
        clearingHouse.unpause();
        rewardDistributor.pause();
        assertTrue(rewardDistributor.paused(), "Reward distributor not paused directly");
        vm.startPrank(liquidityProviderOne);
        vm.expectRevert(bytes("Pausable: paused"));
        rewardDistributor.claimRewardsFor(liquidityProviderOne);
        vm.stopPrank();
        rewardDistributor.unpause();
        assertTrue(!rewardDistributor.paused(), "Reward distributor not unpaused directly");
    }

    function testEcosystemReserve() public {
        // access control errors
        vm.startPrank(liquidityProviderOne);
        vm.expectRevert(bytes("ONLY_BY_FUNDS_ADMIN"));
        ecosystemReserve.transferAdmin(liquidityProviderOne);
        _expectAccessControlGovernanceRole(liquidityProviderOne);
        rewardDistributor.setEcosystemReserve(address(ecosystemReserve));
        vm.stopPrank();

        // invalid address errors
        vm.expectRevert(abi.encodeWithSignature("EcosystemReserve_InvalidAdmin()"));
        ecosystemReserve.transferAdmin(address(0));
        vm.expectRevert(abi.encodeWithSignature("RewardDistributor_InvalidZeroAddress()"));
        rewardDistributor.setEcosystemReserve(address(0));

        // no errors
        EcosystemReserve newEcosystemReserve = new EcosystemReserve(address(this));
        vm.expectEmit(false, false, false, true);
        emit NewFundsAdmin(address(this));
        ecosystemReserve.transferAdmin(address(this));
        vm.expectEmit(false, false, false, true);
        emit EcosystemReserveUpdated(address(ecosystemReserve), address(newEcosystemReserve));
        rewardDistributor.setEcosystemReserve(address(newEcosystemReserve));
    }

    /* ****************** */
    /*  Helper Functions  */
    /* ****************** */

    function _accrueAndCheckUserRewards(address token, address user, uint256 initialRewards)
        internal
        returns (uint256)
    {
        uint256 numMarkets = clearingHouse.getNumMarkets();
        uint256[] memory priorCumRewards = new uint256[](numMarkets);
        IPerpetual[] memory markets = new IPerpetual[](numMarkets);
        for (uint256 i; i < numMarkets; ++i) {
            markets[i] = clearingHouse.perpetuals(clearingHouse.id(i));
            priorCumRewards[i] = rewardDistributor.cumulativeRewardPerLpTokenPerUser(user, token, address(markets[i]));
        }
        rewardDistributor.accrueRewards(user);
        uint256 accruedRewards = rewardDistributor.rewardsAccruedByUser(user, token);
        assertGt(accruedRewards, 0, "Rewards not accrued");
        uint256 expectedAccruedRewards = initialRewards;
        for (uint256 i; i < numMarkets; ++i) {
            IPerpetual market = markets[i];
            uint256 cumulativeRewards = rewardDistributor.cumulativeRewardPerLpToken(token, address(market));
            expectedAccruedRewards += (cumulativeRewards - priorCumRewards[i]).wadMul(market.getLpLiquidity(user));
        }
        assertApproxEqRel(
            accruedRewards,
            expectedAccruedRewards,
            1e15, // 0.1%
            "Incorrect user rewards"
        );
        return accruedRewards;
    }

    function _getUserBalances(address user) internal view returns (uint256[] memory) {
        uint256 numMarkets = clearingHouse.getNumMarkets();
        uint256[] memory balances = new uint256[](numMarkets);
        for (uint256 i; i < numMarkets; ++i) {
            balances[i] = clearingHouse.perpetuals(clearingHouse.id(i)).getLpLiquidity(user);
        }
        return balances;
    }

    function _getCumulativeRewardsByToken(address token) internal view returns (uint256[] memory) {
        uint256 numMarkets = clearingHouse.getNumMarkets();
        uint256[] memory cumulativeRewards = new uint256[](numMarkets);
        for (uint256 i; i < numMarkets; ++i) {
            cumulativeRewards[i] = rewardDistributor.cumulativeRewardPerLpToken(
                token, address(clearingHouse.perpetuals(clearingHouse.id(i)))
            );
        }
        return cumulativeRewards;
    }

    function _getTotalLiquidityPerMarket() internal view returns (uint256[] memory) {
        uint256 numMarkets = clearingHouse.getNumMarkets();
        uint256[] memory totalLiquidity = new uint256[](numMarkets);
        for (uint256 i; i < numMarkets; ++i) {
            totalLiquidity[i] =
                rewardDistributor.totalLiquidityPerMarket(address(clearingHouse.perpetuals(clearingHouse.id(i))));
        }
        return totalLiquidity;
    }

    function _checkRewards(address token, address user, uint256 skipTime, uint256 initialRewards)
        internal
        returns (uint256)
    {
        uint256 accruedRewards = rewardDistributor.rewardsAccruedByUser(user, token);
        assertGt(accruedRewards, 0, "Rewards not accrued");
        uint256 expectedAccruedRewards = initialRewards;
        uint256 numMarkets = clearingHouse.getNumMarkets();
        for (uint256 i; i < numMarkets; ++i) {
            IPerpetual market = clearingHouse.perpetuals(clearingHouse.id(i));
            uint256 cumulativeRewards = rewardDistributor.cumulativeRewardPerLpToken(token, address(market));
            uint256 expectedCumulativeRewards = _calcExpectedCumulativeRewards(token, address(market), skipTime);
            assertApproxEqRel(
                cumulativeRewards,
                expectedCumulativeRewards,
                5e16, // 5%, accounts for reduction factor
                "Incorrect cumulative rewards"
            );
            uint256 lpBalance = market.getLpLiquidity(user);
            expectedAccruedRewards +=
                _calcExpectedUserRewards(rewardDistributor, cumulativeRewards, skipTime, lpBalance);
        }
        assertApproxEqRel(
            accruedRewards,
            expectedAccruedRewards,
            1e15, // 0.1%
            "Incorrect user rewards"
        );
        return accruedRewards;
    }

    function _checkRewards(
        address token,
        address user,
        uint256[] memory skipTimes,
        uint256[] memory lpBalances,
        uint256[] memory initialCumRewards,
        uint256[] memory priorTotalLiquidity,
        uint256 initialUserRewards
    ) internal returns (uint256) {
        require(skipTimes.length == lpBalances.length, "Invalid input");
        require(skipTimes.length == initialCumRewards.length, "Invalid input");
        require(skipTimes.length == priorTotalLiquidity.length, "Invalid input");

        uint256 accruedRewards = rewardDistributor.rewardsAccruedByUser(user, token);
        assertGt(accruedRewards, 0, "Rewards not accrued");
        uint256 expectedAccruedRewards = _checkMarketRewards(
            token, initialUserRewards, skipTimes, lpBalances, initialCumRewards, priorTotalLiquidity
        );
        assertApproxEqRel(
            accruedRewards,
            expectedAccruedRewards,
            1e15, // 0.1%
            "Incorrect user rewards"
        );
        return accruedRewards;
    }

    function _checkMarketRewards(
        address token,
        uint256 initialUserRewards,
        uint256[] memory skipTimes,
        uint256[] memory lpBalances,
        uint256[] memory initialCumRewards,
        uint256[] memory priorTotalLiquidity
    ) internal returns (uint256) {
        uint256 expectedAccruedRewards = initialUserRewards;
        uint256 numMarkets = clearingHouse.getNumMarkets();
        require(numMarkets == skipTimes.length, "Invalid input");
        for (uint256 i; i < numMarkets; ++i) {
            IPerpetual market = clearingHouse.perpetuals(clearingHouse.id(i));
            uint256 cumulativeRewards =
                rewardDistributor.cumulativeRewardPerLpToken(token, address(market)) - initialCumRewards[i];
            uint256 expectedCumulativeRewards =
                _calcExpectedCumulativeRewards(token, address(market), skipTimes[i], priorTotalLiquidity[i]);
            assertApproxEqRel(
                cumulativeRewards,
                expectedCumulativeRewards,
                5e16, // 5%, accounts for reduction factor
                "Incorrect cumulative rewards"
            );
            expectedAccruedRewards +=
                _calcExpectedUserRewards(rewardDistributor, cumulativeRewards, skipTimes[i], lpBalances[i]);
        }
        return expectedAccruedRewards;
    }

    function _calcExpectedCumulativeRewards(address token, address market, uint256 skipTime)
        internal
        view
        returns (uint256)
    {
        uint256 totalLiquidity = rewardDistributor.totalLiquidityPerMarket(market);
        return _calcExpectedCumulativeRewards(token, market, skipTime, totalLiquidity);
    }

    function _calcExpectedCumulativeRewards(address token, address market, uint256 skipTime, uint256 totalLiquidity)
        internal
        view
        returns (uint256)
    {
        uint256 inflationRate = rewardDistributor.getInflationRate(token);
        uint256 marketWeight = rewardDistributor.getRewardWeight(token, market);
        uint256 weightedAnnualInflationRate = inflationRate * marketWeight / 10000; // basis points
        uint256 weightedInflation = weightedAnnualInflationRate * skipTime / 365 days;
        return weightedInflation.wadDiv(totalLiquidity);
    }

    function _calcExpectedUserRewards(
        TestPerpRewardDistributor distributor,
        uint256 cumulativeRewards,
        uint256 skipTime,
        uint256 lpBalance
    ) internal view returns (uint256) {
        uint256 thresholdTime = distributor.earlyWithdrawalThreshold();
        if (skipTime > thresholdTime) {
            skipTime = thresholdTime;
        }
        return cumulativeRewards.wadMul(lpBalance) * skipTime / thresholdTime;
    }

    function _provideLiquidityBothPerps(address user, uint256 amount1, uint256 amount2)
        internal
        returns (uint256 percentOfLiquidity1, uint256 percentOfLiquidity2)
    {
        // provide some liquidity
        fundAndPrepareAccount(user, amount1 + amount2, vault, ua);
        _provideLiquidity(amount1, user, perpetual);
        _provideLiquidity(amount2, user, eth_perpetual);
        percentOfLiquidity1 = (amount1 * 1e18) / (10_000e18 + amount1);
        percentOfLiquidity2 = (amount2 * 1e18) / (10_000e18 + amount2);
    }

    function _provideLiquidity(uint256 depositAmount, address user, TestPerpetual perp) internal {
        vm.startPrank(user);

        clearingHouse.deposit(depositAmount, ua);
        uint256 quoteAmount = depositAmount / 2;
        uint256 baseAmount = quoteAmount.wadDiv(perp.indexPrice().toUint256());
        clearingHouse.provideLiquidity(
            perp == perpetual ? 0 : perp == eth_perpetual ? 1 : 2, [quoteAmount, baseAmount], 0
        );
        vm.stopPrank();
    }

    function _removeAllLiquidity(address user, TestPerpetual perp) internal {
        vm.startPrank(user);

        uint256 proposedAmount = _getLiquidityProviderProposedAmount(user, perp, 1e18);
        /*
        according to curve v2 whitepaper:
        discard values that do not converge
        */
        // vm.assume(proposedAmount > 1e17);

        clearingHouse.removeLiquidity(
            perp == perpetual ? 0 : perp == eth_perpetual ? 1 : 2,
            perp.getLpPosition(user).liquidityBalance,
            [uint256(0), uint256(0)],
            proposedAmount,
            0
        );

        // clearingHouse.withdrawAll(ua);
    }

    function _removeSomeLiquidity(address user, TestPerpetual perp, uint256 reductionRatio) internal {
        uint256 lpBalance = perp.getLpPosition(user).liquidityBalance;
        uint256 amount = (lpBalance * reductionRatio) / 1e18;
        uint256 idx = perp == perpetual ? 0 : perp == eth_perpetual ? 1 : 2;
        vm.startPrank(user);
        uint256 proposedAmount = _getLiquidityProviderProposedAmount(user, perp, reductionRatio);
        clearingHouse.removeLiquidity(idx, amount, [uint256(0), uint256(0)], proposedAmount, 0);

        // clearingHouse.withdrawAll(ua);
    }

    function _getLiquidityProviderProposedAmount(address user, IPerpetual perp, uint256 reductionRatio)
        internal
        returns (uint256 proposedAmount)
    {
        LibPerpetual.LiquidityProviderPosition memory lp = perp.getLpPosition(user);
        if (lp.liquidityBalance == 0) revert("No liquidity provided");
        uint256 idx = perp == perpetual ? 0 : perp == eth_perpetual ? 1 : 2;
        return viewer.getLpProposedAmount(idx, user, reductionRatio, 100, [uint256(0), uint256(0)], 0);
    }

    function _viewNewRewardAccrual(address user) internal view returns (uint256[] memory) {
        uint256 numMarkets = clearingHouse.getNumMarkets();
        uint256 numTokens = rewardDistributor.getRewardTokenCount();
        uint256[] memory newRewards = new uint256[](numTokens);
        for (uint256 i; i < numMarkets; ++i) {
            address market = address(clearingHouse.perpetuals(clearingHouse.id(i)));
            uint256[] memory marketRewards = _viewNewRewardAccrual(market, user);
            for (uint256 j; j < numTokens; ++j) {
                newRewards[j] += marketRewards[j];
            }
        }
        return newRewards;
    }

    function _viewNewRewardAccrual(address market, address user) internal view returns (uint256[] memory) {
        uint256 numTokens = rewardDistributor.getRewardTokenCount();
        uint256[] memory newRewards = new uint256[](numTokens);
        for (uint256 i; i < numTokens; ++i) {
            newRewards[i] = _viewNewRewardAccrual(market, user, rewardDistributor.rewardTokens(i));
        }
        return newRewards;
    }

    function _viewNewRewardAccrual(address market, address user, address token) internal view returns (uint256) {
        uint256 timeOfLastCumRewardUpdate = rewardDistributor.timeOfLastCumRewardUpdate(market);
        uint256 deltaTime = block.timestamp - timeOfLastCumRewardUpdate;
        if (rewardDistributor.totalLiquidityPerMarket(market) == 0) return 0;
        // Calculate the new cumRewardPerLpToken by adding (inflationRatePerSecond x guageWeight x deltaTime) to the previous cumRewardPerLpToken
        uint256 marketWeight = rewardDistributor.getRewardWeight(token, market);
        uint256 newMarketRewards =
            (((rewardDistributor.getInflationRate(token) * marketWeight) / 10000) * deltaTime) / 365 days;
        uint256 newCumRewardPerLpToken = rewardDistributor.cumulativeRewardPerLpToken(token, market)
            + (newMarketRewards * 1e18) / rewardDistributor.totalLiquidityPerMarket(market);
        uint256 newUserRewards = rewardDistributor.lpPositionsPerUser(user, market).wadMul(
            (newCumRewardPerLpToken - rewardDistributor.cumulativeRewardPerLpTokenPerUser(user, token, market))
        );
        return newUserRewards;
    }

    function _addRewardToken(uint256 marketWeight1, uint256 totalSupply, uint88 inflationRate, uint88 reductionFactor)
        internal
        returns (IncrementToken token)
    {
        address[] memory markets = new address[](2);
        markets[0] = address(perpetual);
        markets[1] = address(eth_perpetual);
        uint256[] memory marketWeights = new uint256[](2);
        marketWeights[0] = marketWeight1;
        marketWeights[1] = 10000 - marketWeight1;
        token = new IncrementToken(totalSupply, address(this));
        token.unpause();
        rewardDistributor.addRewardToken(address(token), inflationRate, reductionFactor, markets, marketWeights);
        token.transfer(address(ecosystemReserve), token.totalSupply());
        ecosystemReserve.approve(token, address(rewardDistributor), type(uint256).max);
    }

    function _deployTestPerpetual() internal returns (TestPerpetual) {
        AggregatorV3Interface dai_baseOracle =
            AggregatorV3Interface(address(0xAed0c38402a5d19df6E4c03F4E2DceD6e29c1ee9));
        VBase vBase3 =
            new VBase("vDAI base token", "vDAI", dai_baseOracle, 30 days, sequencerUptimeFeed, ETHUSD.gracePeriod);
        VQuote vQuote3 = new VQuote("vUSD quote token", "vUSD");
        (, int256 answer,,,) = baseOracle.latestRoundData();
        uint8 decimals = dai_baseOracle.decimals();
        uint256 initialPrice = answer.toUint256() * (10 ** (18 - decimals));
        TestPerpetual perpetual3 = new TestPerpetual(
            vBase3,
            vQuote3,
            ICryptoSwap(
                factory.deploy_pool(
                    "DAI_USD",
                    "DAI_USD",
                    [address(vQuote3), address(vBase3)],
                    ETHUSD.A,
                    ETHUSD.gamma,
                    ETHUSD.mid_fee,
                    ETHUSD.out_fee,
                    ETHUSD.allowed_extra_profit,
                    ETHUSD.fee_gamma,
                    ETHUSD.adjustment_step,
                    ETHUSD.admin_fee,
                    ETHUSD.ma_half_time,
                    initialPrice
                )
            ),
            clearingHouse,
            curveCryptoViews,
            true,
            IPerpetual.PerpetualParams(
                ETHUSD.riskWeight,
                ETHUSD.maxLiquidityProvided,
                ETHUSD.twapFrequency,
                ETHUSD.sensitivity,
                ETHUSD.maxBlockTradeAmount,
                ETHUSD.insuranceFee,
                ETHUSD.lpDebtCoef,
                ETHUSD.lockPeriod
            )
        );

        vBase3.transferPerpOwner(address(perpetual3));
        vQuote3.transferPerpOwner(address(perpetual3));
        return perpetual3;
    }

    /* ***************** */
    /*   Error Helpers   */
    /* ***************** */

    function _expectInvalidRewardTokenAddress(address token) internal {
        vm.expectRevert(abi.encodeWithSignature("RewardController_InvalidRewardTokenAddress(address)", token));
    }

    function _expectAboveMaxInflationRate(uint256 inflationRate, uint256 maxInflationRate) internal {
        vm.expectRevert(
            abi.encodeWithSignature(
                "RewardController_AboveMaxInflationRate(uint256,uint256)", inflationRate, maxInflationRate
            )
        );
    }

    function _expectBelowMinReductionFactor(uint256 reductionFactor, uint256 minReductionFactor) internal {
        vm.expectRevert(
            abi.encodeWithSignature(
                "RewardController_BelowMinReductionFactor(uint256,uint256)", reductionFactor, minReductionFactor
            )
        );
    }

    function _expectAboveMaxRewardTokens(uint256 numTokens) internal {
        vm.expectRevert(abi.encodeWithSignature("RewardController_AboveMaxRewardTokens(uint256)", numTokens));
    }

    function _expectIncorrectWeightsCount(uint256 numWeights, uint256 numMarkets) internal {
        vm.expectRevert(
            abi.encodeWithSignature("RewardController_IncorrectWeightsCount(uint256,uint256)", numWeights, numMarkets)
        );
    }

    function _expectWeightExceedsMax(uint256 weight, uint256 maxWeight) internal {
        vm.expectRevert(
            abi.encodeWithSignature("RewardController_WeightExceedsMax(uint256,uint256)", weight, maxWeight)
        );
    }

    function _expectIncorrectWeightsSum(uint256 sum, uint256 expected) internal {
        vm.expectRevert(abi.encodeWithSignature("RewardController_IncorrectWeightsSum(uint256,uint256)", sum, expected));
    }

    function _expectCallerIsNotClearingHouse(address caller) internal {
        vm.expectRevert(abi.encodeWithSignature("PerpRewardDistributor_CallerIsNotClearingHouse(address)", caller));
    }

    function _expectAlreadyInitializedStartTime(address market) internal {
        vm.expectRevert(abi.encodeWithSignature("RewardDistributor_AlreadyInitializedStartTime(address)", market));
    }

    function _expectPositionAlreadyRegistered(address user, address market, uint256 position) internal {
        vm.expectRevert(
            abi.encodeWithSignature(
                "RewardDistributor_PositionAlreadyRegistered(address,address,uint256)", user, market, position
            )
        );
    }

    function _expectUserPositionMismatch(address user, address market, uint256 expected, uint256 actual) internal {
        vm.expectRevert(
            abi.encodeWithSignature(
                "RewardDistributor_UserPositionMismatch(address,address,uint256,uint256)",
                user,
                market,
                expected,
                actual
            )
        );
    }

    function _expectAccessControlGovernanceRole(address account) internal {
        vm.expectRevert(
            bytes(
                string(
                    abi.encodePacked(
                        "AccessControl: account ",
                        Strings.toHexString(account),
                        " is missing role ",
                        Strings.toHexString(uint256(keccak256("GOVERNANCE")), 32)
                    )
                )
            )
        );
    }
}
