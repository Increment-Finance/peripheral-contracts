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
import {RewardDistributor} from "../src/RewardDistributor.sol";

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
            1463753e18,
            1.189207115e18,
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

        // Connect ClearingHouse to RewardsDistributor
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
        vm.startPrank(address(this));
        clearingHouse.setParameters(clearingHouse_params);
        vBase.setHeartBeat(30 days);
        vBase2.setHeartBeat(30 days);
    }

    function testDeployment() public {
        assertEq(rewardsDistributor.getNumGauges(), 2, "Gauge count mismatch");
        assertEq(
            rewardsDistributor.getGaugeAddress(0),
            address(perpetual),
            "Gauge address mismatch"
        );
        (
            IERC20Metadata token,
            ,
            uint256 inflationRate,
            uint256 reductionFactor
        ) = rewardsDistributor.rewardInfoByToken(address(rewardsToken));
        assertEq(
            address(token),
            address(rewardsToken),
            "Reward token mismatch"
        );
        assertEq(inflationRate, 1463753e18, "Inflation rate mismatch");
        assertEq(reductionFactor, 1.189207115e18, "Reduction factor mismatch");
        assertEq(
            rewardsDistributor.earlyWithdrawalThreshold(),
            10 days,
            "Early withdrawal threshold mismatch"
        );
    }

    function testBasicScenario(
        uint256 providedLiquidity1,
        uint256 providedLiquidity2
    ) public {
        /* bounds */
        providedLiquidity1 = bound(providedLiquidity1, 100e18, 10_000e18);
        providedLiquidity2 = bound(providedLiquidity2, 100e18, 10_000e18);
        require(
            providedLiquidity1 >= 100e18 && providedLiquidity1 <= 10_000e18
        );
        require(
            providedLiquidity2 >= 100e18 && providedLiquidity2 <= 10_000e18
        );

        // initial liquidity
        fundAndPrepareAccount(liquidityProviderOne, 100_000e18, vault, ua);
        _provideLiquidity(10_000e18, liquidityProviderOne, perpetual);
        _provideLiquidity(10_000e18, liquidityProviderOne, perpetual2);
        console.log("Initial liquidity: %s", 10_000e18);

        // provide some more liquidity
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
        uint256 percentOfLiquidity = (providedLiquidity1 * 1e18) /
            (10_000e18 + providedLiquidity1);
        uint256 percentOfLiquidity2 = (providedLiquidity2 * 1e18) /
            (10_000e18 + providedLiquidity2);
        console.log("Percent of liquidity1: %s / 1e18", percentOfLiquidity);
        console.log("Percent of liquidity2: %s / 1e18", percentOfLiquidity2);

        // skip some time
        skip(10 days);

        // check rewards
        rewardsDistributor.accrueRewards(liquidityProviderTwo);
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
        uint256 cumulativeRewards2 = rewardsDistributor
            .cumulativeRewardPerLpToken(
                address(rewardsToken),
                address(perpetual2)
            );
        console.log("Cumulative rewards 1: %s", cumulativeRewards1);
        console.log("Cumulative rewards 2: %s", cumulativeRewards2);
        (, , uint256 inflationRate, ) = rewardsDistributor.rewardInfoByToken(
            address(rewardsToken)
        );
        uint256 expectedCumulativeRewards1 = ((((inflationRate * 3) / 4) * 10) /
            365);
        uint256 expectedCumulativeRewards2 = (((inflationRate / 4) * 10) / 365);
        console.log(
            "Expected cumulative rewards 1: %s",
            expectedCumulativeRewards1
        );
        console.log(
            "Expected cumulative rewards 2: %s",
            expectedCumulativeRewards2
        );
        assertApproxEqRel(
            cumulativeRewards1,
            expectedCumulativeRewards1,
            1e16, // 1%, accounts for reduction factor
            "Incorrect cumulative rewards"
        );
        assertApproxEqRel(
            cumulativeRewards2,
            expectedCumulativeRewards2,
            1e16, // 1%, accounts for reduction factor
            "Incorrect cumulative rewards"
        );
        assertApproxEqRel(
            accruedRewards,
            cumulativeRewards1.wadMul(percentOfLiquidity) +
                cumulativeRewards2.wadMul(percentOfLiquidity2),
            1e15, // 0.1%
            "Incorrect user rewards"
        );

        // claim rewards
        rewardsDistributor.claimRewards();
        assertEq(
            rewardsToken.balanceOf(liquidityProviderTwo),
            accruedRewards,
            "Incorrect claimed balance"
        );
    }

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

        // initial liquidity
        fundAndPrepareAccount(liquidityProviderOne, 100_000e18, vault, ua);
        _provideLiquidity(10_000e18, liquidityProviderOne, perpetual);
        _provideLiquidity(10_000e18, liquidityProviderOne, perpetual2);
        console.log("Initial liquidity: %s", 10_000e18);

        // provide some more liquidity
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
        uint256 percentOfLiquidity1 = (providedLiquidity1 * 1e18) /
            (10_000e18 + providedLiquidity1);
        uint256 percentOfLiquidity2 = (providedLiquidity2 * 1e18) /
            (10_000e18 + providedLiquidity2);
        console.log("Percent of liquidity 1: %s / 1e18", percentOfLiquidity1);
        console.log("Percent of liquidity 2: %s / 1e18", percentOfLiquidity2);

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
        rewardsDistributor.accrueRewards(liquidityProviderTwo);
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
        uint256 cumulativeRewards2 = rewardsDistributor
            .cumulativeRewardPerLpToken(
                address(rewardsToken),
                address(perpetual2)
            );
        console.log("Cumulative rewards 1: %s", cumulativeRewards1);
        console.log("Cumulative rewards 2: %s", cumulativeRewards2);
        (, , uint256 inflationRate, ) = rewardsDistributor.rewardInfoByToken(
            address(rewardsToken)
        );
        uint256 expectedCumulativeRewards1 = ((((inflationRate * 3) / 4) * 20) /
            365);
        uint256 expectedCumulativeRewards2 = (((inflationRate / 4) * 20) / 365);
        assertApproxEqRel(
            cumulativeRewards1,
            expectedCumulativeRewards1,
            1e16, // 1%, accounts for reduction factor
            "Incorrect cumulative rewards"
        );
        assertApproxEqRel(
            cumulativeRewards2,
            expectedCumulativeRewards2,
            1e16, // 1%, accounts for reduction factor
            "Incorrect cumulative rewards"
        );
        assertApproxEqRel(
            accruedRewards,
            cumulativeRewards1.wadMul(percentOfLiquidity1) +
                cumulativeRewards2.wadMul(percentOfLiquidity2),
            1e15, // 0.1%
            "Incorrect user rewards"
        );

        // check rewards for token 2
        rewardsDistributor.accrueRewards(liquidityProviderTwo);
        accruedRewards = rewardsDistributor.rewardsAccruedByUser(
            liquidityProviderTwo,
            address(rewardsToken2)
        );
        assertGt(accruedRewards, 0, "Rewards not accrued");
        cumulativeRewards1 = rewardsDistributor.cumulativeRewardPerLpToken(
            address(rewardsToken2),
            address(perpetual)
        );
        cumulativeRewards2 = rewardsDistributor.cumulativeRewardPerLpToken(
            address(rewardsToken2),
            address(perpetual2)
        );
        console.log("Cumulative rewards 1: %s", cumulativeRewards1);
        console.log("Cumulative rewards 2: %s", cumulativeRewards2);
        (, , inflationRate, ) = rewardsDistributor.rewardInfoByToken(
            address(rewardsToken2)
        );
        expectedCumulativeRewards1 = ((((inflationRate2 * gaugeWeights[0]) /
            10000) * 10) / 365);
        expectedCumulativeRewards2 = ((((inflationRate2 * gaugeWeights[1]) /
            10000) * 10) / 365);
        assertApproxEqRel(
            cumulativeRewards1,
            expectedCumulativeRewards1,
            5e16, // 5%, accounts for variable reduction factor
            "Incorrect cumulative rewards"
        );
        assertApproxEqRel(
            cumulativeRewards2,
            expectedCumulativeRewards2,
            5e16, // 5%, accounts for variable reduction factor
            "Incorrect cumulative rewards"
        );
        assertApproxEqRel(
            accruedRewards,
            cumulativeRewards1.wadMul(percentOfLiquidity1) +
                cumulativeRewards2.wadMul(percentOfLiquidity2),
            1e15, // 0.1%
            "Incorrect user rewards"
        );

        // claim rewards
        vm.startPrank(liquidityProviderTwo);
        rewardsDistributor.claimRewards();
        assertEq(
            rewardsToken2.balanceOf(liquidityProviderTwo),
            accruedRewards,
            "Incorrect claimed balance"
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

        // initial liquidity
        fundAndPrepareAccount(liquidityProviderOne, 100_000e18, vault, ua);
        _provideLiquidity(10_000e18, liquidityProviderOne, perpetual);
        _provideLiquidity(10_000e18, liquidityProviderOne, perpetual2);
        console.log("Initial liquidity: %s", 10_000e18);

        // provide some more liquidity
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
        uint256 percentOfLiquidity1 = (providedLiquidity1 * 1e18) /
            (10_000e18 + providedLiquidity1);
        uint256 percentOfLiquidity2 = (providedLiquidity2 * 1e18) /
            (10_000e18 + providedLiquidity2);
        console.log("Percent of liquidity 1: %s / 1e18", percentOfLiquidity1);
        console.log("Percent of liquidity 2: %s / 1e18", percentOfLiquidity2);

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
            perp == perpetual ? 0 : 1,
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
            perp == perpetual ? 0 : 1,
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
            perp == perpetual ? 0 : 1,
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
        uint256 idx = perp == perpetual ? 0 : 1;
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
