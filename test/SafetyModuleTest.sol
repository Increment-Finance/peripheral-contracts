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
import "../contracts/SafetyModule.sol";
import "../contracts/StakedToken.sol";
import {EcosystemReserve, IERC20 as AaveIERC20} from "../contracts/EcosystemReserve.sol";

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
import {IBalancerPoolToken, IWeightedPool, IWETH, JoinKind} from "../contracts/interfaces/balancer/IWeightedPool.sol";
import {IWeightedPoolFactory, IAsset, IVault as IBalancerVault} from "../contracts/interfaces/balancer/IWeightedPoolFactory.sol";

// libraries
import "increment-protocol/lib/LibMath.sol";
import "increment-protocol/lib/LibPerpetual.sol";
import {console2 as console} from "forge/console2.sol";

contract SafetyModuleTest is PerpetualUtils {
    using LibMath for int256;
    using LibMath for uint256;

    event RewardTokenShortfall(
        address indexed rewardToken,
        uint256 shortfallAmount
    );

    event Transfer(address indexed from, address indexed to, uint256 value);

    uint256 constant INITIAL_INFLATION_RATE = 1463753e18;
    uint256 constant INITIAL_REDUCTION_FACTOR = 1.189207115e18;
    uint256 constant INITIAL_MAX_USER_LOSS = 0.5e18;
    uint256 constant INITIAL_MAX_MULTIPLIER = 4e18;
    uint256 constant INITIAL_SMOOTHING_VALUE = 30e18;
    uint256 constant COOLDOWN_SECONDS = 1 days;
    uint256 constant UNSTAKE_WINDOW = 10 days;
    uint256 constant MAX_STAKE_AMOUNT_1 = 1_000_000e18;
    uint256 constant MAX_STAKE_AMOUNT_2 = 100_000e18;

    address liquidityProviderOne = address(123);
    address liquidityProviderTwo = address(456);

    IncrementToken public rewardsToken;
    IWETH public weth;
    StakedToken public stakedToken1;
    StakedToken public stakedToken2;

    EcosystemReserve public rewardVault;
    SafetyModule public safetyModule;
    IWeightedPoolFactory public weightedPoolFactory;
    IWeightedPool public balancerPool;
    IBalancerVault public balancerVault;
    bytes32 public poolId;
    IAsset[] public poolAssets;

    function setUp() public virtual override {
        deal(liquidityProviderOne, 100 ether);
        deal(liquidityProviderTwo, 100 ether);
        deal(address(this), 100 ether);

        // increment-protocol/test/foundry/helpers/Deployment.sol:setUp()
        super.setUp();

        // Deploy rewards tokens
        rewardsToken = new IncrementToken(20_000_000e18, address(this));
        rewardsToken.unpause();

        // Deploy the Ecosystem Reserve vault
        rewardVault = new EcosystemReserve(address(this));

        uint16[] memory weights = new uint16[](2);
        weights[0] = 5000;
        weights[1] = 5000;

        // Deploy safety module
        safetyModule = new SafetyModule(
            address(vault),
            address(0),
            INITIAL_MAX_USER_LOSS,
            INITIAL_MAX_MULTIPLIER,
            INITIAL_SMOOTHING_VALUE,
            address(rewardVault)
        );

        // Transfer half of the rewards tokens to the reward vault
        rewardsToken.transfer(
            address(rewardVault),
            rewardsToken.totalSupply() / 2
        );
        rewardVault.approve(
            AaveIERC20(address(rewardsToken)),
            address(safetyModule),
            type(uint256).max
        );

        // Transfer some of the rewards tokens to the liquidity providers
        rewardsToken.transfer(liquidityProviderOne, 10_000 ether);
        rewardsToken.transfer(liquidityProviderTwo, 10_000 ether);

        // Deploy Balancer pool
        weightedPoolFactory = IWeightedPoolFactory(
            0x897888115Ada5773E02aA29F775430BFB5F34c51
        );
        address[] memory poolTokens = new address[](2);
        poolTokens[0] = address(rewardsToken);
        poolTokens[1] = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        weth = IWETH(poolTokens[1]);
        uint256[] memory poolWeights = new uint256[](2);
        poolWeights[0] = 0.5e18;
        poolWeights[1] = 0.5e18;
        balancerPool = IWeightedPool(
            weightedPoolFactory.create(
                "50INCR-50WETH",
                "50INCR-50WETH",
                poolTokens,
                poolWeights,
                new address[](2),
                1e15,
                address(this),
                bytes32(0)
            )
        );

        // Add initial liquidity to the Balancer pool
        poolId = balancerPool.getPoolId();
        balancerVault = balancerPool.getVault();
        (IERC20[] memory poolERC20s, , ) = balancerVault.getPoolTokens(poolId);
        poolAssets = new IAsset[](2);
        poolAssets[0] = IAsset(address(poolERC20s[0]));
        poolAssets[1] = IAsset(address(poolERC20s[1]));
        uint256[] memory maxAmountsIn = new uint256[](2);
        maxAmountsIn[0] = 10_000 ether;
        maxAmountsIn[1] = 10 ether;
        IBalancerVault.JoinPoolRequest memory joinRequest = IBalancerVault
            .JoinPoolRequest(
                poolAssets,
                maxAmountsIn,
                abi.encode(JoinKind.INIT, maxAmountsIn),
                false
            );
        rewardsToken.approve(address(balancerVault), type(uint256).max);
        weth.approve(address(balancerVault), type(uint256).max);
        weth.deposit{value: 10 ether}();
        balancerVault.joinPool(
            poolId,
            address(this),
            address(this),
            joinRequest
        );

        // Deploy staking tokens
        stakedToken1 = new StakedToken(
            rewardsToken,
            safetyModule,
            COOLDOWN_SECONDS,
            UNSTAKE_WINDOW,
            MAX_STAKE_AMOUNT_1,
            "Staked INCR",
            "stINCR"
        );
        stakedToken2 = new StakedToken(
            balancerPool,
            safetyModule,
            COOLDOWN_SECONDS,
            UNSTAKE_WINDOW,
            MAX_STAKE_AMOUNT_2,
            "Staked 50INCR-50WETH BPT",
            "stIBPT"
        );

        // Register staking tokens with safety module
        safetyModule.addStakingToken(stakedToken1);
        safetyModule.addStakingToken(stakedToken2);
        address[] memory stakingTokens = new address[](2);
        stakingTokens[0] = address(stakedToken1);
        stakingTokens[1] = address(stakedToken2);
        uint16[] memory rewardWeights = new uint16[](2);
        rewardWeights[0] = 5000;
        rewardWeights[1] = 5000;
        safetyModule.addRewardToken(
            address(rewardsToken),
            INITIAL_INFLATION_RATE,
            INITIAL_REDUCTION_FACTOR,
            stakingTokens,
            rewardWeights
        );

        // Approve staking tokens and Balancer vault for users
        vm.startPrank(liquidityProviderOne);
        rewardsToken.approve(address(stakedToken1), type(uint256).max);
        balancerPool.approve(address(stakedToken2), type(uint256).max);
        rewardsToken.approve(address(balancerVault), type(uint256).max);
        weth.approve(address(balancerVault), type(uint256).max);
        vm.startPrank(liquidityProviderTwo);
        rewardsToken.approve(address(stakedToken1), type(uint256).max);
        balancerPool.approve(address(stakedToken2), type(uint256).max);
        rewardsToken.approve(address(balancerVault), type(uint256).max);
        weth.approve(address(balancerVault), type(uint256).max);
        vm.stopPrank();

        // Deposit ETH to WETH for users
        vm.startPrank(liquidityProviderOne);
        weth.deposit{value: 10 ether}();
        vm.startPrank(liquidityProviderTwo);
        weth.deposit{value: 10 ether}();
        vm.stopPrank();

        // Join Balancer pool as user 1
        maxAmountsIn[0] = 5000 ether;
        maxAmountsIn[1] = 10 ether;
        _joinBalancerPool(liquidityProviderOne, maxAmountsIn);

        // Stake as user 1
        _stake(
            stakedToken1,
            liquidityProviderOne,
            rewardsToken.balanceOf(liquidityProviderOne)
        );
        _stake(
            stakedToken2,
            liquidityProviderOne,
            balancerPool.balanceOf(liquidityProviderOne)
        );
    }

    function testDeployment() public {
        assertEq(safetyModule.getNumMarkets(), 2, "Market count mismatch");
        assertEq(
            safetyModule.getMaxMarketIdx(),
            1,
            "Max market index mismatch"
        );
        assertEq(
            safetyModule.getMarketAddress(0),
            address(stakedToken1),
            "Market address mismatch"
        );
        assertEq(safetyModule.getMarketIdx(0), 0, "Market index mismatch");
        assertEq(
            safetyModule.getStakingTokenIdx(address(stakedToken2)),
            1,
            "Staking token index mismatch"
        );
        assertEq(
            safetyModule.getMarketWeightIdx(
                address(rewardsToken),
                address(stakedToken1)
            ),
            0,
            "Market reward weight index mismatch"
        );
        assertEq(
            safetyModule.getCurrentPosition(
                liquidityProviderTwo,
                address(stakedToken1)
            ),
            0,
            "Current position mismatch"
        );
        assertEq(
            safetyModule.computeRewardMultiplier(
                liquidityProviderTwo,
                address(stakedToken1)
            ),
            0,
            "Reward multiplier mismatch"
        );
        _stake(stakedToken1, liquidityProviderTwo, 100 ether);
        assertEq(
            safetyModule.getCurrentPosition(
                liquidityProviderTwo,
                address(stakedToken1)
            ),
            100 ether,
            "Current position mismatch"
        );
        assertEq(
            safetyModule.computeRewardMultiplier(
                liquidityProviderTwo,
                address(stakedToken1)
            ),
            1e18,
            "Reward multiplier mismatch"
        );
    }

    function testRewardMultiplier() public {
        // Test with smoothing value of 30 and max multiplier of 4
        // These values match those in the spreadsheet used to design the SM rewards
        _stake(stakedToken1, liquidityProviderTwo, 100 ether);
        assertEq(
            safetyModule.computeRewardMultiplier(
                liquidityProviderTwo,
                address(stakedToken1)
            ),
            1e18,
            "Reward multiplier mismatch after initial stake"
        );
        skip(2 days);
        assertEq(
            safetyModule.computeRewardMultiplier(
                liquidityProviderTwo,
                address(stakedToken1)
            ),
            1.5e18,
            "Reward multiplier mismatch after 2 days"
        );
        // Partially redeeming resets the multiplier to 1
        _redeem(stakedToken1, liquidityProviderTwo, 50 ether, 1 days);
        assertEq(
            safetyModule.computeRewardMultiplier(
                liquidityProviderTwo,
                address(stakedToken1)
            ),
            1e18,
            "Reward multiplier mismatch after redeeming half"
        );
        skip(5 days);
        assertEq(
            safetyModule.computeRewardMultiplier(
                liquidityProviderTwo,
                address(stakedToken1)
            ),
            2e18,
            "Reward multiplier mismatch after 5 days"
        );
        // Staking again does not reset the multiplier
        _stake(stakedToken1, liquidityProviderTwo, 50 ether);
        assertEq(
            safetyModule.computeRewardMultiplier(
                liquidityProviderTwo,
                address(stakedToken1)
            ),
            2e18,
            "Reward multiplier mismatch after staking again"
        );
        skip(5 days);
        assertEq(
            safetyModule.computeRewardMultiplier(
                liquidityProviderTwo,
                address(stakedToken1)
            ),
            2.5e18,
            "Reward multiplier mismatch after another 5 days"
        );
        // Redeeming completely resets the multiplier to 0
        _redeem(stakedToken1, liquidityProviderTwo, 100 ether, 1 days);
        assertEq(
            safetyModule.computeRewardMultiplier(
                liquidityProviderTwo,
                address(stakedToken1)
            ),
            0,
            "Reward multiplier mismatch after redeeming completely"
        );

        // Test with smoothing value of 60, doubling the time it takes to reach the same multiplier
        safetyModule.setSmoothingValue(60e18);
        _stake(stakedToken1, liquidityProviderTwo, 100 ether);
        assertEq(
            safetyModule.computeRewardMultiplier(
                liquidityProviderTwo,
                address(stakedToken1)
            ),
            1e18,
            "Reward multiplier mismatch after staking with new smoothing value"
        );
        skip(4 days);
        assertEq(
            safetyModule.computeRewardMultiplier(
                liquidityProviderTwo,
                address(stakedToken1)
            ),
            1.5e18,
            "Reward multiplier mismatch after increasing smoothing value"
        );

        // Test with max multiplier of 6, increasing the multiplier by 50%
        safetyModule.setMaxRewardMultiplier(6e18);
        assertEq(
            safetyModule.computeRewardMultiplier(
                liquidityProviderTwo,
                address(stakedToken1)
            ),
            2.25e18,
            "Reward multiplier mismatch after increasing max multiplier"
        );
    }

    function testMultipliedRewardAccrual(uint256 stakeAmount) public {
        /* bounds */
        stakeAmount = bound(stakeAmount, 100e18, 10_000e18);

        // Stake only with stakedToken1 for this test
        _stake(stakedToken1, liquidityProviderTwo, stakeAmount);

        // Skip some time
        skip(9 days);

        // Start cooldown period
        vm.startPrank(liquidityProviderTwo);
        stakedToken1.cooldown();

        // Skip cooldown period
        skip(1 days);

        // Get reward preview
        uint256 rewardPreview = safetyModule.viewNewRewardAccrual(
            address(stakedToken1),
            liquidityProviderTwo,
            address(rewardsToken)
        );

        // Get current reward multiplier
        uint256 rewardMultiplier = safetyModule.computeRewardMultiplier(
            liquidityProviderTwo,
            address(stakedToken1)
        );

        // Redeem stakedToken1
        stakedToken1.redeemTo(liquidityProviderTwo, stakeAmount);

        // Get accrued rewards
        uint256 accruedRewards = safetyModule.rewardsAccruedByUser(
            liquidityProviderTwo,
            address(rewardsToken)
        );

        // Check that accrued rewards are equal to reward preview
        assertEq(
            accruedRewards,
            rewardPreview,
            "Accrued rewards preview mismatch"
        );

        // Check that accrued rewards equal stake amount times cumulative reward per token times reward multiplier
        uint256 cumulativeRewardsPerLpToken = safetyModule
            .cumulativeRewardPerLpToken(
                address(rewardsToken),
                address(stakedToken1)
            );
        assertEq(
            accruedRewards,
            stakeAmount.wadMul(cumulativeRewardsPerLpToken).wadMul(
                rewardMultiplier
            ),
            "Accrued rewards mismatch"
        );

        // Check that rewards are not accrued after full redeem
        skip(10 days);
        safetyModule.accrueRewards(address(stakedToken1), liquidityProviderTwo);
        assertEq(
            safetyModule.rewardsAccruedByUser(
                liquidityProviderTwo,
                address(rewardsToken)
            ),
            accruedRewards,
            "Accrued more rewards after full redeem"
        );
    }

    function testAuctionableBalance(uint256 maxPercentUserLoss) public {
        /* bounds */
        maxPercentUserLoss = bound(maxPercentUserLoss, 0, 1e18);

        // Get initial balances
        uint256 balance1 = stakedToken1.balanceOf(liquidityProviderOne);
        uint256 balance2 = stakedToken2.balanceOf(liquidityProviderOne);

        // Set new max percent user loss and check auctionable balances
        safetyModule.setMaxPercentUserLoss(maxPercentUserLoss);
        assertEq(
            safetyModule.getAuctionableBalance(
                liquidityProviderOne,
                address(stakedToken1)
            ),
            balance1.wadMul(maxPercentUserLoss),
            "Auctionable balance 1 mismatch"
        );
        assertEq(
            safetyModule.getAuctionableBalance(
                liquidityProviderOne,
                address(stakedToken2)
            ),
            balance2.wadMul(maxPercentUserLoss),
            "Auctionable balance 2 mismatch"
        );
    }

    function testPreExistingBalances(
        uint256 maxTokenAmountIntoBalancer
    ) public {
        // liquidityProvider2 starts with 10,000 INCR and 10 WETH
        maxTokenAmountIntoBalancer = bound(
            maxTokenAmountIntoBalancer,
            100e18,
            9_000e18
        );

        // join balancer pool as liquidityProvider2
        console.log("joining balancer pool");
        uint256[] memory maxAmountsIn = new uint256[](2);
        maxAmountsIn[0] = maxTokenAmountIntoBalancer;
        maxAmountsIn[1] = maxTokenAmountIntoBalancer / 1000;
        console.log("maxAmountsIn: [%s, %s]", maxAmountsIn[0], maxAmountsIn[1]);
        _joinBalancerPool(liquidityProviderTwo, maxAmountsIn);

        console.log(
            "rewards token balance: %s",
            rewardsToken.balanceOf(liquidityProviderTwo)
        );
        console.log(
            "balancer pool balance: %s",
            balancerPool.balanceOf(liquidityProviderTwo)
        );

        // stake as liquidityProvider2
        console.log("staking");
        _stake(
            stakedToken1,
            liquidityProviderTwo,
            rewardsToken.balanceOf(liquidityProviderTwo)
        );
        _stake(
            stakedToken2,
            liquidityProviderTwo,
            balancerPool.balanceOf(liquidityProviderTwo)
        );
        console.log("original safety module lp positions:");
        console.log(
            safetyModule.lpPositionsPerUser(
                liquidityProviderTwo,
                address(stakedToken1)
            )
        );
        console.log(
            safetyModule.lpPositionsPerUser(
                liquidityProviderTwo,
                address(stakedToken2)
            )
        );

        // redeploy safety module
        uint16[] memory weights = new uint16[](2);
        weights[0] = 5000;
        weights[1] = 5000;

        console.log("deploying new safety module");
        SafetyModule newSafetyModule = new SafetyModule(
            address(vault),
            address(0),
            INITIAL_MAX_USER_LOSS,
            INITIAL_MAX_MULTIPLIER,
            INITIAL_SMOOTHING_VALUE,
            address(rewardVault)
        );
        rewardVault.approve(
            AaveIERC20(address(rewardsToken)),
            address(newSafetyModule),
            type(uint256).max
        );

        // add staking tokens to new safety module
        console.log("adding staking tokens to new safety module");
        newSafetyModule.addStakingToken(stakedToken1);
        newSafetyModule.addStakingToken(stakedToken2);
        address[] memory stakingTokens = new address[](2);
        stakingTokens[0] = address(stakedToken1);
        stakingTokens[1] = address(stakedToken2);
        uint16[] memory rewardWeights = new uint16[](2);
        rewardWeights[0] = 5000;
        rewardWeights[1] = 5000;
        newSafetyModule.addRewardToken(
            address(rewardsToken),
            INITIAL_INFLATION_RATE,
            INITIAL_REDUCTION_FACTOR,
            stakingTokens,
            rewardWeights
        );

        // connect staking tokens to new safety module
        console.log("updating safety module in staked tokens");
        stakedToken1.setSafetyModule(address(newSafetyModule));
        stakedToken2.setSafetyModule(address(newSafetyModule));

        console.log("new safety module lp positions:");
        console.log(
            newSafetyModule.lpPositionsPerUser(
                liquidityProviderTwo,
                address(stakedToken1)
            )
        );
        console.log(
            newSafetyModule.lpPositionsPerUser(
                liquidityProviderTwo,
                address(stakedToken2)
            )
        );

        // skip some time
        console.log("skipping 10 days");
        skip(10 days);

        // before registering positions, expect accruing rewards to fail
        console.log("expecting viewNewRewardAccrual to fail");
        vm.expectRevert(
            abi.encodeWithSignature(
                "RewardDistributor_UserPositionMismatch(address,address,uint256,uint256)",
                liquidityProviderTwo,
                address(stakedToken1),
                0,
                stakedToken1.balanceOf(liquidityProviderTwo)
            )
        );
        newSafetyModule.viewNewRewardAccrual(
            address(stakedToken1),
            liquidityProviderTwo
        );
        console.log("expecting accrueRewards to fail");
        vm.expectRevert(
            abi.encodeWithSignature(
                "RewardDistributor_UserPositionMismatch(address,address,uint256,uint256)",
                liquidityProviderTwo,
                address(stakedToken1),
                0,
                stakedToken1.balanceOf(liquidityProviderTwo)
            )
        );
        newSafetyModule.accrueRewards(liquidityProviderTwo);

        // register user positions
        vm.startPrank(liquidityProviderOne);
        newSafetyModule.registerPositions();
        vm.startPrank(liquidityProviderTwo);
        newSafetyModule.registerPositions(stakingTokens);

        // skip some time
        skip(10 days);

        // check that rewards were accrued correctly

        newSafetyModule.accrueRewards(liquidityProviderTwo);
        uint256 cumulativeRewards1 = newSafetyModule.cumulativeRewardPerLpToken(
            address(rewardsToken),
            address(stakedToken1)
        );
        uint256 cumulativeRewards2 = newSafetyModule.cumulativeRewardPerLpToken(
            address(rewardsToken),
            address(stakedToken2)
        );
        (, , , uint256 inflationRate, ) = newSafetyModule.rewardInfoByToken(
            address(rewardsToken)
        );
        uint256 totalLiquidity1 = newSafetyModule.totalLiquidityPerMarket(
            address(stakedToken1)
        );
        uint256 totalLiquidity2 = newSafetyModule.totalLiquidityPerMarket(
            address(stakedToken2)
        );
        uint256 expectedCumulativeRewards1 = (((((inflationRate * 5000) /
            10000) * 20) / 365) * 1e18) / totalLiquidity1;
        uint256 expectedCumulativeRewards2 = (((((inflationRate * 5000) /
            10000) * 20) / 365) * 1e18) / totalLiquidity2;
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

    function testRewardTokenShortfall(uint256 stakeAmount) public {
        /* bounds */
        stakeAmount = bound(stakeAmount, 100e18, 10_000e18);

        // Stake only with stakedToken1 for this test
        _stake(stakedToken1, liquidityProviderTwo, stakeAmount);

        // Remove all reward tokens from EcosystemReserve
        uint256 rewardBalance = rewardsToken.balanceOf(address(rewardVault));
        rewardVault.transfer(
            AaveIERC20(address(rewardsToken)),
            address(this),
            rewardBalance
        );

        // Skip some time
        skip(10 days);

        // Get reward preview
        uint256 rewardPreview = safetyModule.viewNewRewardAccrual(
            address(stakedToken1),
            liquidityProviderTwo,
            address(rewardsToken)
        );

        // Accrue rewards, expecting RewardTokenShortfall event
        vm.expectEmit(false, false, false, true);
        emit RewardTokenShortfall(address(rewardsToken), rewardPreview);
        safetyModule.accrueRewards(address(stakedToken1), liquidityProviderTwo);

        // Skip some more time
        skip(9 days);

        // Start cooldown period
        vm.startPrank(liquidityProviderTwo);
        stakedToken1.cooldown();

        // Skip cooldown period
        skip(1 days);

        // Get second reward preview
        uint256 rewardPreview2 = safetyModule.viewNewRewardAccrual(
            address(stakedToken1),
            liquidityProviderTwo,
            address(rewardsToken)
        );

        // Redeem stakedToken1, expecting RewardTokenShortfall event
        vm.expectEmit(false, false, false, true);
        emit RewardTokenShortfall(
            address(rewardsToken),
            rewardPreview + rewardPreview2
        );
        stakedToken1.redeemTo(liquidityProviderTwo, stakeAmount);

        // Try to claim reward tokens, expecting RewardTokenShortfall event
        vm.expectEmit(false, false, false, true);
        emit RewardTokenShortfall(
            address(rewardsToken),
            rewardPreview + rewardPreview2
        );
        safetyModule.claimRewards();
        assertEq(
            rewardsToken.balanceOf(liquidityProviderTwo),
            10_000e18,
            "Claimed rewards after shortfall"
        );

        // Transfer reward tokens back to the EcosystemReserve
        vm.stopPrank();
        rewardsToken.transfer(address(rewardVault), rewardBalance);

        // Claim tokens and check that the accrued rewards were distributed
        safetyModule.claimRewardsFor(liquidityProviderTwo);
        assertEq(
            rewardsToken.balanceOf(liquidityProviderTwo),
            10_000e18 + rewardPreview + rewardPreview2,
            "Incorrect rewards after resolving shortfall"
        );
    }

    function testStakedTokenZeroLiquidity() public {
        // Deploy a third staked token
        StakedToken stakedToken3 = new StakedToken(
            rewardsToken,
            safetyModule,
            COOLDOWN_SECONDS,
            UNSTAKE_WINDOW,
            MAX_STAKE_AMOUNT_1,
            "Staked INCR 2",
            "stINCR2"
        );

        // Add the third staked token to the safety module
        safetyModule.addStakingToken(stakedToken3);

        // Update the reward weights
        address[] memory stakingTokens = new address[](3);
        stakingTokens[0] = address(stakedToken1);
        stakingTokens[1] = address(stakedToken2);
        stakingTokens[2] = address(stakedToken3);
        uint16[] memory rewardWeights = new uint16[](3);
        rewardWeights[0] = 3333;
        rewardWeights[1] = 3334;
        rewardWeights[2] = 3333;
        safetyModule.updateRewardWeights(
            address(rewardsToken),
            stakingTokens,
            rewardWeights
        );

        // Check that rewardToken was added to the list of reward tokens for the new staked token
        assertEq(
            safetyModule.rewardTokensPerMarket(address(stakedToken3), 0),
            address(rewardsToken),
            "Reward token missing for new staked token"
        );

        // Skip some time
        skip(10 days);

        // Get reward preview, expecting it to be 0
        uint256 rewardPreview = safetyModule.viewNewRewardAccrual(
            address(stakedToken3),
            liquidityProviderTwo,
            address(rewardsToken)
        );
        assertEq(rewardPreview, 0, "Reward preview should be 0");

        // Accrue rewards, expecting it to accrue 0 rewards
        safetyModule.accrueRewards(address(stakedToken3), liquidityProviderTwo);
        assertEq(
            safetyModule.rewardsAccruedByUser(
                liquidityProviderTwo,
                address(rewardsToken)
            ),
            0,
            "Rewards should be 0"
        );
    }

    function testStakedTokenTransfer(uint256 stakeAmount) public {
        /* bounds */
        stakeAmount = bound(stakeAmount, 100e18, 10_000e18);

        // Stake only with stakedToken1 for this test
        _stake(stakedToken1, liquidityProviderTwo, stakeAmount);

        // Get initial stake balances
        uint256 initialBalance1 = stakedToken1.balanceOf(liquidityProviderOne);
        uint256 initialBalance2 = stakedToken1.balanceOf(liquidityProviderTwo);

        // Skip some time
        skip(5 days);

        // After 5 days, both users should have 2x multiplier (given smoothing value of 30 and max multiplier of 4)
        assertEq(
            safetyModule.computeRewardMultiplier(
                liquidityProviderOne,
                address(stakedToken1)
            ),
            2e18,
            "Reward multiplier mismatch: user 1"
        );
        assertEq(
            safetyModule.computeRewardMultiplier(
                liquidityProviderTwo,
                address(stakedToken1)
            ),
            2e18,
            "Reward multiplier mismatch: user 2"
        );

        // Transfer all of user 1's stakedToken1 to user 2
        vm.startPrank(liquidityProviderOne);
        // Start cooldown period for the sake of test coverage
        stakedToken1.cooldown();
        stakedToken1.transfer(liquidityProviderTwo, initialBalance1);
        vm.stopPrank();

        // Check that both users accrued rewards according to their initial balances and multipliers
        uint256 accruedRewards1 = safetyModule.rewardsAccruedByUser(
            liquidityProviderOne,
            address(rewardsToken)
        );
        uint256 accruedRewards2 = safetyModule.rewardsAccruedByUser(
            liquidityProviderTwo,
            address(rewardsToken)
        );
        uint256 cumRewardsPerLpToken = safetyModule.cumulativeRewardPerLpToken(
            address(rewardsToken),
            address(stakedToken1)
        );
        assertEq(
            accruedRewards1,
            initialBalance1.wadMul(cumRewardsPerLpToken).wadMul(2e18),
            "Accrued rewards mismatch: user 1"
        );
        assertEq(
            accruedRewards2,
            initialBalance2.wadMul(cumRewardsPerLpToken).wadMul(2e18),
            "Accrued rewards mismatch: user 2"
        );

        // Check that user 1's multiplier is now 0, while user 2's is still 2
        assertEq(
            safetyModule.computeRewardMultiplier(
                liquidityProviderOne,
                address(stakedToken1)
            ),
            0,
            "Reward multiplier mismatch after transfer: user 1"
        );
        assertEq(
            safetyModule.computeRewardMultiplier(
                liquidityProviderTwo,
                address(stakedToken1)
            ),
            2e18,
            "Reward multiplier mismatch after transfer: user 2"
        );

        // Claim rewards for both users
        safetyModule.claimRewardsFor(liquidityProviderOne);
        safetyModule.claimRewardsFor(liquidityProviderTwo);

        // Skip some more time
        skip(5 days);

        // After 10 days, user 2's multiplier should be 2.5, while user 1's is still 0
        assertEq(
            safetyModule.computeRewardMultiplier(
                liquidityProviderOne,
                address(stakedToken1)
            ),
            0,
            "Reward multiplier mismatch after 10 days: user 1"
        );
        assertEq(
            safetyModule.computeRewardMultiplier(
                liquidityProviderTwo,
                address(stakedToken1)
            ),
            2.5e18,
            "Reward multiplier mismatch after 10 days: user 2"
        );

        // Check that user 2 accrues rewards according to their new balance and multiplier, while user 1 accrues no rewards
        safetyModule.accrueRewards(address(stakedToken1), liquidityProviderOne);
        safetyModule.accrueRewards(address(stakedToken1), liquidityProviderTwo);
        accruedRewards1 = safetyModule.rewardsAccruedByUser(
            liquidityProviderOne,
            address(rewardsToken)
        );
        accruedRewards2 = safetyModule.rewardsAccruedByUser(
            liquidityProviderTwo,
            address(rewardsToken)
        );
        cumRewardsPerLpToken =
            safetyModule.cumulativeRewardPerLpToken(
                address(rewardsToken),
                address(stakedToken1)
            ) -
            cumRewardsPerLpToken;
        assertEq(
            accruedRewards1,
            0,
            "Accrued rewards mismatch after 10 days: user 1"
        );
        assertEq(
            accruedRewards2,
            (initialBalance1 + initialBalance2)
                .wadMul(cumRewardsPerLpToken)
                .wadMul(2.5e18),
            "Accrued rewards mismatch after 10 days: user 2"
        );
    }

    function testNextCooldownTimestamp() public {
        // When user first stakes, next cooldown timestamp should be 0
        assertEq(
            stakedToken1.getNextCooldownTimestamp(
                0,
                100e18,
                liquidityProviderOne,
                stakedToken1.balanceOf(liquidityProviderOne)
            ),
            0,
            "Next cooldown timestamp should be 0 after first staking"
        );

        // Activate cooldown period
        vm.startPrank(liquidityProviderOne);
        stakedToken1.cooldown();
        vm.stopPrank();
        uint256 fromCooldownTimestamp = stakedToken1.stakersCooldowns(
            liquidityProviderOne
        );
        assertEq(
            fromCooldownTimestamp,
            block.timestamp,
            "Cooldown timestamp mismatch"
        );

        // Wait for cooldown period and unstake window to pass
        skip(20 days);

        // When user's cooldown timestamp is less than minimal valid timestamp, next cooldown timestamp should be 0
        assertEq(
            stakedToken1.getNextCooldownTimestamp(
                fromCooldownTimestamp,
                100e18,
                liquidityProviderOne,
                stakedToken1.balanceOf(liquidityProviderOne)
            ),
            0,
            "Next cooldown timestamp should be 0 when cooldown timestamp is less than minimal valid timestamp"
        );

        // Test with different from and to addresses
        _stake(stakedToken1, liquidityProviderTwo, 100e18);

        // Reset user 1 cooldown timestamp
        vm.startPrank(liquidityProviderOne);
        stakedToken1.cooldown();
        vm.stopPrank();
        fromCooldownTimestamp = stakedToken1.stakersCooldowns(
            liquidityProviderOne
        );

        // Skip user 1 cooldown period
        skip(1 days);

        // Activate user 2 cooldown period
        vm.startPrank(liquidityProviderTwo);
        stakedToken1.cooldown();
        vm.stopPrank();
        uint256 toCooldownTimestamp = stakedToken1.stakersCooldowns(
            liquidityProviderTwo
        );

        // If user 1's cooldown timestamp is less than user 2's, next cooldown timestamp should be user 2's
        assertEq(
            stakedToken1.getNextCooldownTimestamp(
                fromCooldownTimestamp,
                100e18,
                liquidityProviderTwo,
                stakedToken1.balanceOf(liquidityProviderTwo)
            ),
            toCooldownTimestamp,
            "Next cooldown timestamp should be user 2's when user 1's cooldown timestamp is less than user 2's"
        );

        // Reset user 1 cooldown timestamp
        vm.startPrank(liquidityProviderOne);
        stakedToken1.cooldown();
        vm.stopPrank();
        fromCooldownTimestamp = stakedToken1.stakersCooldowns(
            liquidityProviderOne
        );

        // If user 1's cooldown timestamp is greater than or equal to user 2's, next cooldown timestamp should be weighted average
        assertEq(
            stakedToken1.getNextCooldownTimestamp(
                fromCooldownTimestamp,
                100e18,
                liquidityProviderTwo,
                stakedToken1.balanceOf(liquidityProviderTwo)
            ),
            (100e18 * fromCooldownTimestamp + (100e18 * toCooldownTimestamp)) /
                (100e18 + 100e18),
            "Next cooldown timestamp should be weighted average when user 1's cooldown timestamp is greater than or equal to user 2's"
        );
        skip(20 days);

        // Reset user 2 cooldown period
        vm.startPrank(liquidityProviderTwo);
        stakedToken1.cooldown();
        vm.stopPrank();
        toCooldownTimestamp = stakedToken1.stakersCooldowns(
            liquidityProviderTwo
        );
        skip(1 days);
        assertEq(
            stakedToken1.getNextCooldownTimestamp(
                fromCooldownTimestamp,
                100e18,
                liquidityProviderTwo,
                stakedToken1.balanceOf(liquidityProviderTwo)
            ),
            (100e18 * block.timestamp + (100e18 * toCooldownTimestamp)) /
                (100e18 + 100e18),
            "block.timestamp should be used for fromCooldownTimestamp when computing weighted average after cooldown period and unstake window have passed"
        );
    }

    function testSafetyModuleErrors(
        uint256 highMaxUserLoss,
        uint256 lowMaxMultiplier,
        uint256 highMaxMultiplier,
        uint256 lowSmoothingValue,
        uint256 highSmoothingValue,
        uint256 invalidMarketIdx,
        address invalidMarket,
        address invalidRewardToken
    ) public {
        /* bounds */
        highMaxUserLoss = bound(highMaxUserLoss, 1e18 + 1, type(uint256).max);
        lowMaxMultiplier = bound(lowMaxMultiplier, 0, 1e18 - 1);
        highMaxMultiplier = bound(
            highMaxMultiplier,
            10e18 + 1,
            type(uint256).max
        );
        lowSmoothingValue = bound(lowSmoothingValue, 0, 10e18 - 1);
        highSmoothingValue = bound(
            highSmoothingValue,
            100e18 + 1,
            type(uint256).max
        );
        invalidMarketIdx = bound(invalidMarketIdx, 2, type(uint256).max);
        vm.assume(
            invalidMarket != address(stakedToken1) &&
                invalidMarket != address(stakedToken2)
        );
        vm.assume(invalidRewardToken != address(rewardsToken));

        // test governor-controlled params out of bounds
        vm.expectRevert(
            abi.encodeWithSignature(
                "SafetyModule_InvalidMaxUserLossTooHigh(uint256,uint256)",
                highMaxUserLoss,
                1e18
            )
        );
        safetyModule.setMaxPercentUserLoss(highMaxUserLoss);
        vm.expectRevert(
            abi.encodeWithSignature(
                "SafetyModule_InvalidMaxMultiplierTooLow(uint256,uint256)",
                lowMaxMultiplier,
                1e18
            )
        );
        safetyModule.setMaxRewardMultiplier(lowMaxMultiplier);
        vm.expectRevert(
            abi.encodeWithSignature(
                "SafetyModule_InvalidMaxMultiplierTooHigh(uint256,uint256)",
                highMaxMultiplier,
                10e18
            )
        );
        safetyModule.setMaxRewardMultiplier(highMaxMultiplier);
        vm.expectRevert(
            abi.encodeWithSignature(
                "SafetyModule_InvalidSmoothingValueTooLow(uint256,uint256)",
                lowSmoothingValue,
                10e18
            )
        );
        safetyModule.setSmoothingValue(lowSmoothingValue);
        vm.expectRevert(
            abi.encodeWithSignature(
                "SafetyModule_InvalidSmoothingValueTooHigh(uint256,uint256)",
                highSmoothingValue,
                100e18
            )
        );
        safetyModule.setSmoothingValue(highSmoothingValue);

        // test staking token already registered
        vm.expectRevert(
            abi.encodeWithSignature(
                "SafetyModule_StakingTokenAlreadyRegistered(address)",
                address(stakedToken1)
            )
        );
        safetyModule.addStakingToken(stakedToken1);

        // test invalid staking token
        vm.expectRevert(
            abi.encodeWithSignature(
                "SafetyModule_InvalidStakingToken(address)",
                invalidMarket
            )
        );
        safetyModule.getStakingTokenIdx(invalidMarket);
        vm.expectRevert(
            abi.encodeWithSignature(
                "RewardController_MarketHasNoRewardWeight(address,address)",
                invalidMarket,
                address(rewardsToken)
            )
        );
        safetyModule.getMarketWeightIdx(address(rewardsToken), invalidMarket);
        vm.startPrank(address(stakedToken1));
        vm.expectRevert(
            abi.encodeWithSignature(
                "SafetyModule_InvalidStakingToken(address)",
                invalidMarket
            )
        );
        safetyModule.updateStakingPosition(invalidMarket, liquidityProviderOne);
        vm.startPrank(invalidMarket);
        vm.expectRevert(
            abi.encodeWithSignature(
                "SafetyModule_CallerIsNotStakingToken(address)",
                invalidMarket
            )
        );
        safetyModule.updateStakingPosition(invalidMarket, liquidityProviderOne);
        vm.stopPrank();

        // test invalid market index
        vm.expectRevert(
            abi.encodeWithSignature(
                "RewardDistributor_InvalidMarketIndex(uint256,uint256)",
                invalidMarketIdx,
                1
            )
        );
        safetyModule.getMarketAddress(invalidMarketIdx);
        vm.expectRevert(
            abi.encodeWithSignature(
                "RewardDistributor_InvalidMarketIndex(uint256,uint256)",
                invalidMarketIdx,
                1
            )
        );
        safetyModule.getMarketIdx(invalidMarketIdx);

        // test invalid reward token
        vm.expectRevert(
            abi.encodeWithSignature(
                "RewardController_MarketHasNoRewardWeight(address,address)",
                address(stakedToken1),
                invalidRewardToken
            )
        );
        safetyModule.getMarketWeightIdx(
            invalidRewardToken,
            address(stakedToken1)
        );
    }

    function testStakedTokenErrors(
        uint256 invalidStakeAmount1,
        uint256 invalidStakeAmount2
    ) public {
        /* bounds */
        invalidStakeAmount1 = bound(
            invalidStakeAmount1,
            MAX_STAKE_AMOUNT_1 -
                stakedToken1.balanceOf(liquidityProviderOne) +
                1,
            type(uint256).max / 2
        );
        invalidStakeAmount2 = bound(
            invalidStakeAmount2,
            MAX_STAKE_AMOUNT_2 -
                stakedToken2.balanceOf(liquidityProviderOne) +
                1,
            type(uint256).max / 2
        );

        // test zero amount
        vm.expectRevert(
            abi.encodeWithSignature("StakedToken_InvalidZeroAmount()")
        );
        stakedToken1.stakeOnBehalfOf(liquidityProviderOne, 0);
        vm.expectRevert(
            abi.encodeWithSignature("StakedToken_InvalidZeroAmount()")
        );
        stakedToken1.redeemTo(liquidityProviderOne, 0);

        // test zero balance
        vm.expectRevert(
            abi.encodeWithSignature("StakedToken_ZeroBalanceAtCooldown()")
        );
        stakedToken1.cooldown();

        // test above max stake amount
        vm.expectRevert(
            abi.encodeWithSignature(
                "StakedToken_AboveMaxStakeAmount(uint256,uint256)",
                MAX_STAKE_AMOUNT_1,
                MAX_STAKE_AMOUNT_1 -
                    stakedToken1.balanceOf(liquidityProviderOne)
            )
        );
        stakedToken1.stakeOnBehalfOf(liquidityProviderOne, invalidStakeAmount1);
        vm.expectRevert(
            abi.encodeWithSignature(
                "StakedToken_AboveMaxStakeAmount(uint256,uint256)",
                MAX_STAKE_AMOUNT_2,
                MAX_STAKE_AMOUNT_2 -
                    stakedToken2.balanceOf(liquidityProviderOne)
            )
        );
        stakedToken2.stakeOnBehalfOf(liquidityProviderOne, invalidStakeAmount2);
        deal(address(stakedToken1), liquidityProviderTwo, invalidStakeAmount1);
        vm.startPrank(liquidityProviderTwo);
        vm.expectRevert(
            abi.encodeWithSignature(
                "StakedToken_AboveMaxStakeAmount(uint256,uint256)",
                MAX_STAKE_AMOUNT_1,
                MAX_STAKE_AMOUNT_1 -
                    stakedToken1.balanceOf(liquidityProviderOne)
            )
        );
        stakedToken1.transfer(liquidityProviderOne, invalidStakeAmount1);
        // change max stake amount and try again, expecting it to succeed
        vm.stopPrank();
        stakedToken1.setMaxStakeAmount(type(uint256).max);
        vm.startPrank(liquidityProviderTwo);
        vm.expectEmit(false, false, false, true);
        emit Transfer(
            liquidityProviderTwo,
            liquidityProviderOne,
            invalidStakeAmount1
        );
        stakedToken1.transfer(liquidityProviderOne, invalidStakeAmount1);
        // transfer the amount back so that subsequent tests work
        vm.startPrank(liquidityProviderOne);
        stakedToken1.transfer(liquidityProviderTwo, invalidStakeAmount1);

        // test insufficient cooldown
        stakedToken1.cooldown();
        uint256 cooldownStartTimestamp = block.timestamp;
        uint256 stakedBalance = stakedToken1.balanceOf(liquidityProviderOne);
        vm.expectRevert(
            abi.encodeWithSignature(
                "StakedToken_InsufficientCooldown(uint256)",
                cooldownStartTimestamp + 1 days
            )
        );
        stakedToken1.redeem(stakedBalance);

        // test unstake window finished
        skip(20 days);
        vm.expectRevert(
            abi.encodeWithSignature(
                "StakedToken_UnstakeWindowFinished(uint256)",
                cooldownStartTimestamp + 11 days
            )
        );
        stakedToken1.redeem(stakedBalance);
        // redeem correctly
        stakedToken1.cooldown();
        skip(1 days);
        stakedToken1.redeem(stakedBalance);
        // restake, then try redeeming without cooldown
        stakedToken1.stake(stakedBalance);
        vm.expectRevert(
            abi.encodeWithSignature(
                "StakedToken_UnstakeWindowFinished(uint256)",
                11 days
            )
        );
        stakedToken1.redeem(stakedBalance);
    }

    /* ****************** */
    /*  Helper Functions  */
    /* ****************** */

    function _stake(
        IStakedToken stakedToken,
        address staker,
        uint256 amount
    ) internal {
        vm.startPrank(staker);
        stakedToken.stake(amount);
        vm.stopPrank();
    }

    function _redeem(
        IStakedToken stakedToken,
        address staker,
        uint256 amount,
        uint256 cooldown
    ) internal {
        vm.startPrank(staker);
        stakedToken.cooldown();
        skip(cooldown);
        stakedToken.redeem(amount);
        vm.stopPrank();
    }

    function _joinBalancerPool(
        address staker,
        uint256[] memory maxAmountsIn
    ) internal {
        vm.startPrank(staker);
        balancerVault.joinPool(
            poolId,
            staker,
            staker,
            IBalancerVault.JoinPoolRequest(
                poolAssets,
                maxAmountsIn,
                abi.encode(JoinKind.EXACT_TOKENS_IN_FOR_BPT_OUT, maxAmountsIn),
                false
            )
        );
        vm.stopPrank();
    }
}
