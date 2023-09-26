// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.16;

// contracts
import {PerpetualUtils} from "../lib/increment-protocol/test/foundry/helpers/PerpetualUtils.sol";
import {Test} from "forge-std/Test.sol";
import "increment-protocol/ClearingHouse.sol";
import "increment-protocol/test/TestPerpetual.sol";
import "increment-protocol/tokens/UA.sol";
import "increment-protocol/tokens/VBase.sol";
import "increment-protocol/tokens/VQuote.sol";
import "increment-protocol/mocks/MockAggregator.sol";
import "@increment-governance/IncrementToken.sol";
import "../src/RewardDistributor.sol";

// interfaces
import "increment-protocol/interfaces/ICryptoSwap.sol";
import "increment-protocol/interfaces/IPerpetual.sol";
import "increment-protocol/interfaces/IClearingHouse.sol";
import "increment-protocol/interfaces/ICurveCryptoFactory.sol";
import "increment-protocol/interfaces/IVault.sol";
import "increment-protocol/interfaces/IVBase.sol";
import "increment-protocol/interfaces/IVQuote.sol";
import "increment-protocol/interfaces/IInsurance.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetFixedSupply.sol";

// libraries
import "increment-protocol/lib/LibMath.sol";
import "increment-protocol/lib/LibPerpetual.sol";
import {console2 as console} from "forge/console2.sol";

contract RewardsTest is PerpetualUtils {
    using LibMath for int256;
    using LibMath for uint256;

    uint256 constant INITIAL_INFLATION_RATE = 1463753e18;
    uint256 constant INITIAL_REDUCTION_FACTOR = 1.189207115e18;

    address liquidityProviderOne = address(123);
    address liquidityProviderTwo = address(456);
    address traderOne = address(789);

    ICryptoSwap public cryptoSwap2;
    TestPerpetual public perpetual2;
    AggregatorV3Interface public gbpOracle;
    VBase public vBase2;
    VQuote public vQuote2;
    IERC20Metadata public lpToken2;

    IncrementToken public rewardsToken;
    IncrementToken public rewardsToken2;

    RewardDistributor public rewardsDistributor;

    function setUp() public virtual override {
        deal(liquidityProviderOne, 100 ether);
        deal(liquidityProviderTwo, 100 ether);
        deal(traderOne, 100 ether);

        // increment-protocol/test/foundry/helpers/Deployment.sol:setUp()
        super.setUp();

        // Deploy second perpetual contract
        gbpOracle = AggregatorV3Interface(
            address(0x5c0Ab2d9b5a7ed9f470386e82BB36A3613cDd4b5)
        );
        vBase2 = new VBase(
            "vGBP base token",
            "vGBP",
            gbpOracle,
            vBaseHeartBeat,
            sequencerUptimeFeed,
            gracePeriod
        );
        vQuote2 = new VQuote("vUSD quote token", "vUSD");
        cryptoSwap2 = ICryptoSwap(
            factory.deploy_pool(
                "GBP_USD",
                "GBP_USD",
                [address(vQuote2), address(vBase2)],
                A,
                gamma,
                mid_fee,
                out_fee,
                allowed_extra_profit,
                fee_gamma,
                adjustment_step,
                admin_fee,
                ma_half_time,
                initial_price
            )
        );
        lpToken2 = IERC20Metadata(cryptoSwap2.token());
        perpetual2 = new TestPerpetual(
            vBase2,
            vQuote2,
            cryptoSwap2,
            clearingHouse,
            curveCryptoViews,
            true,
            perp_params
        );

        vBase2.transferPerpOwner(address(perpetual2));
        vQuote2.transferPerpOwner(address(perpetual2));
        clearingHouse.allowListPerpetual(perpetual2);

        // Deploy rewards tokens and distributor
        rewardsToken = new IncrementToken(20000000e18, address(this));
        rewardsToken2 = new IncrementToken(20000000e18, address(this));
        rewardsToken.unpause();
        rewardsToken2.unpause();

        uint16[] memory weights = new uint16[](2);
        weights[0] = 7500;
        weights[1] = 2500;

        rewardsDistributor = new RewardDistributor(
            INITIAL_INFLATION_RATE,
            INITIAL_REDUCTION_FACTOR,
            address(rewardsToken),
            address(clearingHouse),
            10 days,
            weights
        );
        rewardsToken.transfer(
            address(rewardsDistributor),
            rewardsToken.totalSupply()
        );
        rewardsToken2.transfer(
            address(rewardsDistributor),
            rewardsToken2.totalSupply()
        );

        // initial liquidity
        fundAndPrepareAccount(liquidityProviderOne, 100_000e18, vault, ua);
        _provideLiquidity(10_000e18, liquidityProviderOne, perpetual);
        _provideLiquidity(10_000e18, liquidityProviderOne, perpetual2);
        rewardsDistributor.registerPositions();

        // Connect ClearingHouse to RewardsDistributor
        vm.startPrank(address(this));
        clearingHouse.addStakingContract(rewardsDistributor);

        // Update ClearingHouse params to remove min open notional
        clearingHouse_params = IClearingHouse.ClearingHouseParams({
            minMargin: 0.025 ether,
            minMarginAtCreation: 0.055 ether,
            minPositiveOpenNotional: 0 ether,
            liquidationReward: 0.015 ether,
            insuranceRatio: 0.1 ether,
            liquidationRewardInsuranceShare: 0.5 ether,
            liquidationDiscount: 0.95 ether,
            nonUACollSeizureDiscount: 0.75 ether,
            uaDebtSeizureThreshold: 10000 ether
        });
        clearingHouse.setParameters(clearingHouse_params);
        vBase.setHeartBeat(30 days);
        vBase2.setHeartBeat(30 days);
    }

    /* ******************* */
    /*   GaugeController   */
    /* ******************* */

    function testDeployment() public {
        assertEq(rewardsDistributor.getNumGauges(), 2, "Gauge count mismatch");
        assertEq(
            rewardsDistributor.getGaugeAddress(0),
            address(perpetual),
            "Gauge address mismatch"
        );
        assertEq(
            rewardsDistributor.getRewardTokenCount(),
            1,
            "Token count mismatch"
        );
        address token = rewardsDistributor.rewardTokens(0);
        assertEq(token, address(rewardsToken), "Reward token mismatch");
        assertEq(
            rewardsDistributor.getInitialTimestamp(token),
            block.timestamp,
            "Initial timestamp mismatch"
        );
        assertEq(
            rewardsDistributor.getBaseInflationRate(token),
            INITIAL_INFLATION_RATE,
            "Base inflation rate mismatch"
        );
        assertEq(
            rewardsDistributor.getInflationRate(token),
            INITIAL_INFLATION_RATE,
            "Inflation rate mismatch"
        );
        assertEq(
            rewardsDistributor.getReductionFactor(token),
            INITIAL_REDUCTION_FACTOR,
            "Reduction factor mismatch"
        );
        uint16[] memory weights = rewardsDistributor.getGaugeWeights(token);
        assertEq(weights[0], 7500, "Gauge weight mismatch");
        assertEq(weights[1], 2500, "Gauge weight mismatch");
        assertEq(
            rewardsDistributor.earlyWithdrawalThreshold(),
            10 days,
            "Early withdrawal threshold mismatch"
        );
    }

    function testInflationAndReduction(
        uint256 timeIncrement,
        uint256 initialInflationRate,
        uint256 initialReductionFactor
    ) public {
        /* bounds */
        initialInflationRate = bound(initialInflationRate, 1e22, 5e24);
        initialReductionFactor = bound(initialReductionFactor, 1e18, 2e18);

        // Update inflation rate and reduction factor
        rewardsDistributor.updateInflationRate(
            address(rewardsToken),
            initialInflationRate
        );
        rewardsDistributor.updateReductionFactor(
            address(rewardsToken),
            initialReductionFactor
        );

        // Set heartbeats to 1 year
        vBase.setHeartBeat(365 days);
        vBase2.setHeartBeat(365 days);

        // Keeper bot will ensure that market rewards are updated every month at least
        timeIncrement = bound(timeIncrement, 7 days, 30 days);
        console.log("Time increment: %s days", timeIncrement / 1 days);
        uint256 endYear = block.timestamp + 365 days;
        uint256 updatesPerYear = 365 days / timeIncrement;

        // Accrue rewards throughout the year
        for (uint256 i = 0; i < updatesPerYear; i++) {
            skip(timeIncrement);
            rewardsDistributor.accrueRewards(liquidityProviderOne);
        }

        // Skip to the end of the year
        vm.warp(endYear);
        rewardsDistributor.accrueRewards(liquidityProviderOne);

        // Check accrued rewards
        uint256 accruedRewards = rewardsDistributor.rewardsAccruedByUser(
            liquidityProviderOne,
            address(rewardsToken)
        );

        // Accrued rewards should be within 5% of the average inflation rate
        uint256 currentInflationRate = rewardsDistributor.getInflationRate(
            address(rewardsToken)
        );
        uint256 approxRewards = (currentInflationRate + initialInflationRate) /
            2;
        assertApproxEqRel(
            accruedRewards,
            approxRewards,
            5e16,
            "Incorrect annual rewards"
        );
    }

    function testGaugeControllerErrors(
        uint256 inflationRate,
        uint256 reductionFactor,
        uint16[] memory gaugeWeights,
        address token
    ) public {
        vm.assume(
            token != address(rewardsToken) &&
                token != address(rewardsToken2) &&
                token != address(0)
        );
        vm.assume(gaugeWeights.length > 2);
        vm.assume(
            uint256(gaugeWeights[0]) + gaugeWeights[1] <= type(uint16).max
        );
        vm.assume(gaugeWeights[0] + gaugeWeights[1] != 10000);
        inflationRate = bound(inflationRate, 5e24 + 1, 1e36);
        reductionFactor = bound(reductionFactor, 0, 1e18 - 1);

        vm.startPrank(address(this));

        // test wrong token address
        console.log(
            "updateGaugeWeights: GaugeController_InvalidRewardTokenAddress"
        );
        vm.expectRevert(
            abi.encodeWithSignature(
                "GaugeController_InvalidRewardTokenAddress(address)",
                token
            )
        );
        rewardsDistributor.updateGaugeWeights(token, gaugeWeights);
        console.log(
            "updateInflationRate: GaugeController_InvalidRewardTokenAddress"
        );
        vm.expectRevert(
            abi.encodeWithSignature(
                "GaugeController_InvalidRewardTokenAddress(address)",
                token
            )
        );
        rewardsDistributor.updateInflationRate(token, inflationRate);
        console.log(
            "updateReductionFactor: GaugeController_InvalidRewardTokenAddress"
        );
        vm.expectRevert(
            abi.encodeWithSignature(
                "GaugeController_InvalidRewardTokenAddress(address)",
                token
            )
        );
        rewardsDistributor.updateReductionFactor(token, reductionFactor);

        // test max inflation rate & min reduction factor
        console.log(
            "updateInflationRate: GaugeController_AboveMaxInflationRate"
        );
        vm.expectRevert(
            abi.encodeWithSignature(
                "GaugeController_AboveMaxInflationRate(uint256,uint256)",
                inflationRate,
                5e24
            )
        );
        rewardsDistributor.updateInflationRate(
            address(rewardsToken),
            inflationRate
        );
        console.log(
            "updateReductionFactor: GaugeController_BelowMinReductionFactor"
        );
        vm.expectRevert(
            abi.encodeWithSignature(
                "GaugeController_BelowMinReductionFactor(uint256,uint256)",
                reductionFactor,
                1e18
            )
        );
        rewardsDistributor.updateReductionFactor(
            address(rewardsToken),
            reductionFactor
        );

        // test incorrect gauge weights
        console.log(
            "updateGaugeWeights: GaugeController_IncorrectWeightsCount"
        );
        vm.expectRevert(
            abi.encodeWithSignature(
                "GaugeController_IncorrectWeightsCount(uint256,uint256)",
                gaugeWeights.length,
                2
            )
        );
        rewardsDistributor.updateGaugeWeights(
            address(rewardsToken),
            gaugeWeights
        );
        uint16[] memory gaugeWeights2 = new uint16[](2);
        gaugeWeights2[0] = gaugeWeights[0];
        gaugeWeights2[1] = gaugeWeights[1];
        console.log(
            "gauge weights: [%s, %s]",
            gaugeWeights2[0],
            gaugeWeights2[1]
        );
        if (gaugeWeights2[0] > 10000) {
            console.log("updateGaugeWeights: GaugeController_WeightExceedsMax");
            vm.expectRevert(
                abi.encodeWithSignature(
                    "GaugeController_WeightExceedsMax(uint16,uint16)",
                    gaugeWeights2[0],
                    10000
                )
            );
        } else if (gaugeWeights[1] > 10000) {
            console.log("updateGaugeWeights: GaugeController_WeightExceedsMax");
            vm.expectRevert(
                abi.encodeWithSignature(
                    "GaugeController_WeightExceedsMax(uint16,uint16)",
                    gaugeWeights2[1],
                    10000
                )
            );
        } else {
            console.log(
                "updateGaugeWeights: GaugeController_IncorrectWeightsSum"
            );
            vm.expectRevert(
                abi.encodeWithSignature(
                    "GaugeController_IncorrectWeightsSum(uint16,uint16)",
                    gaugeWeights2[0] + gaugeWeights2[1],
                    10000
                )
            );
        }
        rewardsDistributor.updateGaugeWeights(
            address(rewardsToken),
            gaugeWeights2
        );
    }

    /* ******************* */
    /*  RewardDistributor  */
    /* ******************* */

    function testMultipleRewardScenario(
        uint256 providedLiquidity1,
        uint256 providedLiquidity2,
        uint256 inflationRate2,
        uint256 reductionFactor2,
        uint16 gaugeWeight1
    ) public {
        /* bounds */
        providedLiquidity1 = bound(providedLiquidity1, 100e18, 10_000e18);
        providedLiquidity2 = bound(providedLiquidity2, 100e18, 10_000e18);
        inflationRate2 = bound(inflationRate2, 1e20, 5e24);
        reductionFactor2 = bound(reductionFactor2, 1e18, 5e18);
        gaugeWeight1 = gaugeWeight1 % 10000;
        require(
            providedLiquidity1 >= 100e18 && providedLiquidity1 <= 10_000e18
        );
        require(
            providedLiquidity2 >= 100e18 && providedLiquidity2 <= 10_000e18
        );

        (
            uint256 percentOfLiquidity1,
            uint256 percentOfLiquidity2
        ) = _provideLiquidityBothPerps(providedLiquidity1, providedLiquidity2);

        // skip some time
        skip(10 days);

        // add a new reward token
        vm.startPrank(address(this));
        uint16[] memory gaugeWeights = new uint16[](2);
        gaugeWeights[0] = gaugeWeight1;
        gaugeWeights[1] = 10000 - gaugeWeight1;
        console.log("Inflation Rate: %s", inflationRate2);
        console.log("Reduction Factor: %s", reductionFactor2);
        console.log(
            "Gauge Weights: [%s, %s]",
            gaugeWeights[0],
            gaugeWeights[1]
        );
        rewardsDistributor.addRewardToken(
            address(rewardsToken2),
            inflationRate2,
            reductionFactor2,
            gaugeWeights
        );

        // skip some more time
        skip(10 days);

        // check rewards for token 1
        rewardsDistributor.accrueRewards(liquidityProviderOne);
        rewardsDistributor.accrueRewards(liquidityProviderTwo);
        uint256 accruedRewards = _checkRewards(
            address(rewardsToken),
            liquidityProviderTwo,
            percentOfLiquidity1,
            percentOfLiquidity2,
            7500,
            2500,
            20
        );

        // check rewards for token 2
        uint256 accruedRewards2 = _checkRewards(
            address(rewardsToken2),
            liquidityProviderTwo,
            percentOfLiquidity1,
            percentOfLiquidity2,
            gaugeWeights[0],
            gaugeWeights[1],
            10
        );
        uint256 accruedRewards21 = _checkRewards(
            address(rewardsToken2),
            liquidityProviderOne,
            1e18 - percentOfLiquidity1,
            1e18 - percentOfLiquidity2,
            gaugeWeights[0],
            gaugeWeights[1],
            10
        );

        // remove reward token 2
        vm.startPrank(address(this));
        rewardsDistributor.removeRewardToken(address(rewardsToken2));

        // claim rewards
        vm.startPrank(liquidityProviderTwo);
        address[] memory tokens = new address[](2);
        tokens[0] = address(rewardsToken);
        tokens[1] = address(rewardsToken2);
        rewardsDistributor.claimRewardsFor(liquidityProviderTwo, tokens);
        assertEq(
            rewardsToken.balanceOf(liquidityProviderTwo),
            accruedRewards,
            "Incorrect claimed balance"
        );
        assertEq(
            rewardsToken2.balanceOf(liquidityProviderTwo),
            accruedRewards2,
            "Incorrect claimed balance"
        );
        assertEq(
            rewardsToken2.balanceOf(address(rewardsDistributor)),
            accruedRewards21,
            "Incorrect remaining accrued balance"
        );
        assertEq(
            rewardsToken2.balanceOf(address(this)),
            20000000e18 - accruedRewards2 - accruedRewards21,
            "Incorrect returned balance"
        );
    }

    function testMultipleRewardShortfallScenario(
        uint256 providedLiquidity1,
        uint256 providedLiquidity2,
        uint256 inflationRate2,
        uint256 reductionFactor2,
        uint16 gaugeWeight1
    ) public {
        /* bounds */
        providedLiquidity1 = bound(providedLiquidity1, 100e18, 10_000e18);
        providedLiquidity2 = bound(providedLiquidity2, 100e18, 10_000e18);
        inflationRate2 = bound(inflationRate2, 1e24, 5e24);
        reductionFactor2 = bound(reductionFactor2, 1e18, 5e18);
        gaugeWeight1 = gaugeWeight1 % 10000;
        require(
            providedLiquidity1 >= 100e18 && providedLiquidity1 <= 10_000e18
        );
        require(
            providedLiquidity2 >= 100e18 && providedLiquidity2 <= 10_000e18
        );

        (
            uint256 percentOfLiquidity1,
            uint256 percentOfLiquidity2
        ) = _provideLiquidityBothPerps(providedLiquidity1, providedLiquidity2);

        // add a new reward token
        vm.startPrank(address(this));
        uint16[] memory gaugeWeights = new uint16[](2);
        gaugeWeights[0] = gaugeWeight1;
        gaugeWeights[1] = 10000 - gaugeWeight1;
        console.log("Inflation Rate: %s", inflationRate2);
        console.log("Reduction Factor: %s", reductionFactor2);
        console.log(
            "Gauge Weights: [%s, %s]",
            gaugeWeights[0],
            gaugeWeights[1]
        );
        rewardsToken2 = new IncrementToken(10e18, address(this));
        rewardsToken2.unpause();
        rewardsDistributor.addRewardToken(
            address(rewardsToken2),
            inflationRate2,
            reductionFactor2,
            gaugeWeights
        );
        rewardsToken2.transfer(
            address(rewardsDistributor),
            rewardsToken2.totalSupply()
        );

        // skip some time
        skip(10 days);

        // check rewards for token 1
        rewardsDistributor.accrueRewards(liquidityProviderTwo);
        uint256 accruedRewards = _checkRewards(
            address(rewardsToken),
            liquidityProviderTwo,
            percentOfLiquidity1,
            percentOfLiquidity2,
            7500,
            2500,
            10
        );

        // check rewards for token 2
        uint256 accruedRewards2 = _checkRewards(
            address(rewardsToken2),
            liquidityProviderTwo,
            percentOfLiquidity1,
            percentOfLiquidity2,
            gaugeWeights[0],
            gaugeWeights[1],
            10
        );
        // vm.assume(accruedRewards2 > 10e18);

        // claim rewards
        vm.startPrank(liquidityProviderTwo);
        rewardsDistributor.claimRewards();
        assertEq(
            rewardsToken.balanceOf(liquidityProviderTwo),
            accruedRewards,
            "Incorrect claimed balance"
        );
        assertEq(
            rewardsToken2.balanceOf(liquidityProviderTwo),
            10e18,
            "Incorrect claimed balance"
        );
        assertEq(
            rewardsDistributor.totalUnclaimedRewards(address(rewardsToken2)),
            accruedRewards2 - 10e18,
            "Incorrect unclaimed rewards"
        );
    }

    function testEarlyWithdrawScenario(
        uint256 providedLiquidity1,
        uint256 providedLiquidity2,
        uint256 reductionRatio
    ) public {
        /* bounds */
        providedLiquidity1 = bound(providedLiquidity1, 100e18, 10_000e18);
        providedLiquidity2 = bound(providedLiquidity2, 100e18, 10_000e18);
        reductionRatio = bound(reductionRatio, 1e16, 1e18);
        console.log("Reduction Ratio: %s", reductionRatio);
        require(
            providedLiquidity1 >= 100e18 && providedLiquidity1 <= 10_000e18
        );
        require(
            providedLiquidity2 >= 100e18 && providedLiquidity2 <= 10_000e18
        );

        (
            uint256 percentOfLiquidity1,
            uint256 percentOfLiquidity2
        ) = _provideLiquidityBothPerps(providedLiquidity1, providedLiquidity2);

        // skip some time
        skip(5 days);

        // remove some liquidity from first perpetual
        _removeSomeLiquidity(liquidityProviderTwo, perpetual, reductionRatio);

        // check rewards
        uint256 accruedRewards = rewardsDistributor.rewardsAccruedByUser(
            liquidityProviderTwo,
            address(rewardsToken)
        );
        assertGt(accruedRewards, 0, "Rewards not accrued");
        uint256 cumulativeRewards1 = rewardsDistributor
            .cumulativeRewardPerLpToken(
                address(rewardsToken),
                address(perpetual)
            );
        console.log("Cumulative rewards: %s", cumulativeRewards1);
        assertApproxEqRel(
            accruedRewards,
            cumulativeRewards1.wadMul(percentOfLiquidity1).wadMul(
                1e18 - reductionRatio
            ),
            1e16,
            "Incorrect rewards"
        );

        // skip some time again
        skip(5 days);

        // remove some liquidity again from first perpetual
        percentOfLiquidity1 = rewardsDistributor
            .lpPositionsPerUser(liquidityProviderTwo, address(perpetual))
            .wadDiv(
                rewardsDistributor.totalLiquidityPerMarket(address(perpetual))
            );
        _removeSomeLiquidity(liquidityProviderTwo, perpetual, reductionRatio);

        // remove all liquidity from second perpetual
        _removeAllLiquidity(liquidityProviderTwo, perpetual2);

        // check that penalty was applied again, but only for the first perpetual
        accruedRewards =
            rewardsDistributor.rewardsAccruedByUser(
                liquidityProviderTwo,
                address(rewardsToken)
            ) -
            accruedRewards;
        cumulativeRewards1 =
            rewardsDistributor.cumulativeRewardPerLpToken(
                address(rewardsToken),
                address(perpetual)
            ) -
            cumulativeRewards1;
        uint256 cumulativeRewards2 = rewardsDistributor
            .cumulativeRewardPerLpToken(
                address(rewardsToken),
                address(perpetual2)
            );
        assertApproxEqRel(
            accruedRewards,
            cumulativeRewards1.wadMul(percentOfLiquidity1).wadMul(
                1e18 - reductionRatio
            ) + cumulativeRewards2.wadMul(percentOfLiquidity2),
            1e16,
            "Incorrect rewards"
        );
    }

    function testAddNewGauge(
        uint256 providedLiquidity1,
        uint256 providedLiquidity2,
        uint256 providedLiquidity3
    ) public {
        /* bounds */
        providedLiquidity1 = bound(providedLiquidity1, 100e18, 10_000e18);
        providedLiquidity2 = bound(providedLiquidity2, 100e18, 10_000e18);
        providedLiquidity3 = bound(providedLiquidity3, 100e18, 10_000e18);
        require(
            providedLiquidity1 >= 100e18 && providedLiquidity1 <= 10_000e18
        );
        require(
            providedLiquidity2 >= 100e18 && providedLiquidity2 <= 10_000e18
        );
        require(
            providedLiquidity3 >= 100e18 && providedLiquidity3 <= 10_000e18
        );

        // add liquidity to first two perpetuals
        _provideLiquidityBothPerps(providedLiquidity1, providedLiquidity2);

        // deploy new gauge contracts
        vm.startPrank(address(this));
        VBase vBase3 = new VBase(
            "vDAI base token",
            "vDAI",
            AggregatorV3Interface(
                address(0xAed0c38402a5d19df6E4c03F4E2DceD6e29c1ee9)
            ),
            30 days,
            sequencerUptimeFeed,
            gracePeriod
        );
        VQuote vQuote3 = new VQuote("vUSD quote token", "vUSD");
        TestPerpetual perpetual3 = new TestPerpetual(
            vBase3,
            vQuote3,
            ICryptoSwap(
                factory.deploy_pool(
                    "DAI_USD",
                    "DAI_USD",
                    [address(vQuote3), address(vBase3)],
                    A,
                    gamma,
                    mid_fee,
                    out_fee,
                    allowed_extra_profit,
                    fee_gamma,
                    adjustment_step,
                    admin_fee,
                    ma_half_time,
                    initial_price
                )
            ),
            clearingHouse,
            curveCryptoViews,
            true,
            perp_params
        );

        vBase3.transferPerpOwner(address(perpetual3));
        vQuote3.transferPerpOwner(address(perpetual3));
        clearingHouse.allowListPerpetual(perpetual3);

        // skip some time
        skip(10 days);

        // set new gauge weights
        uint16[] memory gaugeWeights = new uint16[](3);
        gaugeWeights[0] = 5000;
        gaugeWeights[1] = 3000;
        gaugeWeights[2] = 2000;
        rewardsDistributor.updateGaugeWeights(
            address(rewardsToken),
            gaugeWeights
        );

        // check that rewards were accrued to first two perpetuals at previous weights
        rewardsDistributor.accrueRewards(liquidityProviderTwo);
        uint256 cumulativeRewards1 = rewardsDistributor
            .cumulativeRewardPerLpToken(
                address(rewardsToken),
                address(perpetual)
            );
        uint256 cumulativeRewards2 = rewardsDistributor
            .cumulativeRewardPerLpToken(
                address(rewardsToken),
                address(perpetual2)
            );
        uint256 cumulativeRewards3 = rewardsDistributor
            .cumulativeRewardPerLpToken(
                address(rewardsToken),
                address(perpetual3)
            );
        (, , uint256 inflationRate, ) = rewardsDistributor.rewardInfoByToken(
            address(rewardsToken)
        );
        uint256 expectedCumulativeRewards1 = ((((inflationRate * 7500) /
            10000) * 10) / 365);
        uint256 expectedCumulativeRewards2 = ((((inflationRate * 2500) /
            10000) * 10) / 365);
        uint256 expectedCumulativeRewards3 = 0;
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
        assertEq(
            cumulativeRewards3,
            expectedCumulativeRewards3,
            "Incorrect cumulative rewards"
        );

        // provide liquidity to new perpetual
        _provideLiquidity(10_000e18, liquidityProviderOne, perpetual3);
        fundAndPrepareAccount(
            liquidityProviderTwo,
            providedLiquidity3,
            vault,
            ua
        );
        _provideLiquidity(providedLiquidity3, liquidityProviderTwo, perpetual3);

        // skip some more time
        skip(10 days);

        // check that rewards were accrued to all three perpetuals at new weights
        rewardsDistributor.accrueRewards(liquidityProviderTwo);
        cumulativeRewards1 = rewardsDistributor.cumulativeRewardPerLpToken(
            address(rewardsToken),
            address(perpetual)
        );
        cumulativeRewards2 = rewardsDistributor.cumulativeRewardPerLpToken(
            address(rewardsToken),
            address(perpetual2)
        );
        cumulativeRewards3 = rewardsDistributor.cumulativeRewardPerLpToken(
            address(rewardsToken),
            address(perpetual3)
        );
        expectedCumulativeRewards1 += ((((inflationRate * 5000) / 10000) * 10) /
            365);
        expectedCumulativeRewards2 += ((((inflationRate * 3000) / 10000) * 10) /
            365);
        expectedCumulativeRewards3 += ((((inflationRate * 2000) / 10000) * 10) /
            365);
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
        assertApproxEqRel(
            cumulativeRewards3,
            expectedCumulativeRewards3,
            5e16, // 5%, accounts for reduction factor
            "Incorrect cumulative rewards"
        );
    }

    function _checkRewards(
        address token,
        address user,
        uint256 percentOfLiquidity1,
        uint256 percentOfLiquidity2,
        uint16 gaugeWeight1,
        uint16 gaugeWeight2,
        uint256 numDays
    ) internal returns (uint256) {
        uint256 accruedRewards = rewardsDistributor.rewardsAccruedByUser(
            user,
            token
        );
        assertGt(accruedRewards, 0, "Rewards not accrued");
        uint256 cumulativeRewards1 = rewardsDistributor
            .cumulativeRewardPerLpToken(token, address(perpetual));
        uint256 cumulativeRewards2 = rewardsDistributor
            .cumulativeRewardPerLpToken(token, address(perpetual2));
        (, , uint256 inflationRate, ) = rewardsDistributor.rewardInfoByToken(
            token
        );
        uint256 expectedCumulativeRewards1 = ((((inflationRate * gaugeWeight1) /
            10000) * numDays) / 365);
        uint256 expectedCumulativeRewards2 = ((((inflationRate * gaugeWeight2) /
            10000) * numDays) / 365);
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
        assertApproxEqRel(
            accruedRewards,
            cumulativeRewards1.wadMul(percentOfLiquidity1) +
                cumulativeRewards2.wadMul(percentOfLiquidity2),
            1e15, // 0.1%
            "Incorrect user rewards"
        );
        return accruedRewards;
    }

    function _provideLiquidityBothPerps(
        uint256 providedLiquidity1,
        uint256 providedLiquidity2
    )
        internal
        returns (uint256 percentOfLiquidity1, uint256 percentOfLiquidity2)
    {
        // provide some liquidity
        fundAndPrepareAccount(
            liquidityProviderTwo,
            providedLiquidity1 + providedLiquidity2,
            vault,
            ua
        );
        _provideLiquidity(providedLiquidity1, liquidityProviderTwo, perpetual);
        _provideLiquidity(providedLiquidity2, liquidityProviderTwo, perpetual2);
        console.log("Provided liquidity 1: %s", providedLiquidity1);
        console.log("Provided liquidity 2: %s", providedLiquidity2);
        percentOfLiquidity1 =
            (providedLiquidity1 * 1e18) /
            (10_000e18 + providedLiquidity1);
        percentOfLiquidity2 =
            (providedLiquidity2 * 1e18) /
            (10_000e18 + providedLiquidity2);
        console.log("Percent of liquidity 1: %s / 1e18", percentOfLiquidity1);
        console.log("Percent of liquidity 2: %s / 1e18", percentOfLiquidity2);
    }

    function _provideLiquidity(
        uint256 depositAmount,
        address user,
        TestPerpetual perp
    ) internal {
        vm.startPrank(user);

        clearingHouse.deposit(depositAmount, ua);
        uint256 quoteAmount = depositAmount / 2;
        uint256 baseAmount = quoteAmount.wadDiv(perp.indexPrice().toUint256());
        clearingHouse.provideLiquidity(
            perp == perpetual ? 0 : perp == perpetual2 ? 1 : 2,
            [quoteAmount, baseAmount],
            0
        );
    }

    function _removeAllLiquidity(address user, TestPerpetual perp) internal {
        vm.startPrank(user);

        uint256 proposedAmount = _getLiquidityProviderProposedAmount(
            user,
            perp,
            1e18
        );
        /*
        according to curve v2 whitepaper:
        discard values that do not converge
        */
        vm.assume(proposedAmount > 1e17);

        clearingHouse.removeLiquidity(
            perp == perpetual ? 0 : perp == perpetual2 ? 1 : 2,
            perp.getLpPosition(user).liquidityBalance,
            [uint256(0), uint256(0)],
            proposedAmount,
            0
        );

        // clearingHouse.withdrawAll(ua);
    }

    function _removeSomeLiquidity(
        address user,
        TestPerpetual perp,
        uint256 reductionRatio
    ) internal {
        uint256 amount = (perp.getLpPosition(user).liquidityBalance *
            reductionRatio) / 1e18;
        vm.startPrank(user);
        uint256 proposedAmount = _getLiquidityProviderProposedAmount(
            user,
            perp,
            reductionRatio
        );
        console.log("Proposed amount: %s", proposedAmount);
        clearingHouse.removeLiquidity(
            perp == perpetual ? 0 : perp == perpetual2 ? 1 : 2,
            amount,
            [uint256(0), uint256(0)],
            proposedAmount,
            0
        );

        // clearingHouse.withdrawAll(ua);
    }

    function _getLiquidityProviderProposedAmount(
        address user,
        IPerpetual perp,
        uint256 reductionRatio
    ) internal returns (uint256 proposedAmount) {
        LibPerpetual.LiquidityProviderPosition memory lp = perpetual
            .getLpPosition(user);
        if (lp.liquidityBalance == 0) revert("No liquidity provided");
        uint256 idx = perp == perpetual ? 0 : perp == perpetual2 ? 1 : 2;
        return
            viewer.getLpProposedAmount(
                idx,
                user,
                reductionRatio,
                40,
                [uint256(0), uint256(0)],
                0
            );
    }
}
