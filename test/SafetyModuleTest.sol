// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.16;

// contracts
import {Deployment} from "../lib/increment-protocol/test/helpers/Deployment.MainnetFork.sol";
import {Utils} from "../lib/increment-protocol/test/helpers/Utils.sol";
import {ClearingHouse} from "increment-protocol/ClearingHouse.sol";
import {TestPerpetual} from "../lib/increment-protocol/test/mocks/TestPerpetual.sol";
import {UA} from "increment-protocol/tokens/UA.sol";
import {VBase} from "increment-protocol/tokens/VBase.sol";
import {VQuote} from "increment-protocol/tokens/VQuote.sol";
import {IncrementToken} from "@increment-governance/IncrementToken.sol";
import {SafetyModule, ISafetyModule} from "../contracts/SafetyModule.sol";
import {StakedToken, IStakedToken} from "../contracts/StakedToken.sol";
import {AuctionModule, IAuctionModule} from "../contracts/AuctionModule.sol";
import {TestSMRewardDistributor, IRewardDistributor} from "./mocks/TestSMRewardDistributor.sol";
import {EcosystemReserve} from "../contracts/EcosystemReserve.sol";

// interfaces
import {ICryptoSwap} from "increment-protocol/interfaces/ICryptoSwap.sol";
import {IPerpetual} from "increment-protocol/interfaces/IPerpetual.sol";
import {IClearingHouse} from "increment-protocol/interfaces/IClearingHouse.sol";
import {ICurveCryptoFactory} from "increment-protocol/interfaces/ICurveCryptoFactory.sol";
import {IVault} from "increment-protocol/interfaces/IVault.sol";
import {IVBase} from "increment-protocol/interfaces/IVBase.sol";
import {IVQuote} from "increment-protocol/interfaces/IVQuote.sol";
import {IInsurance} from "increment-protocol/interfaces/IInsurance.sol";
import {ERC20PresetFixedSupply, IERC20} from "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetFixedSupply.sol";
import {IBalancerPoolToken, IWeightedPool, IWETH, JoinKind} from "./balancer/IWeightedPool.sol";
import {IWeightedPoolFactory, IAsset, IVault as IBalancerVault} from "./balancer/IWeightedPoolFactory.sol";

// libraries
import {LibMath} from "increment-protocol/lib/LibMath.sol";
import "increment-protocol/lib/LibPerpetual.sol";
import {console2 as console} from "forge/console2.sol";

contract SafetyModuleTest is Deployment, Utils {
    using LibMath for int256;
    using LibMath for uint256;

    event Staked(
        address indexed from,
        address indexed onBehalfOf,
        uint256 amount
    );

    event Redeemed(address indexed from, address indexed to, uint256 amount);

    event Cooldown(address indexed user);

    event RewardTokenShortfall(
        address indexed rewardToken,
        uint256 shortfallAmount
    );

    event Transfer(address indexed from, address indexed to, uint256 value);

    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );

    event LotsSold(
        uint256 indexed auctionId,
        address indexed buyer,
        uint8 numLots,
        uint256 lotSize,
        uint128 lotPrice
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

    event SlashingSettled();

    event FundsReturned(address indexed from, uint256 amount);

    event ExchangeRateUpdated(uint256 exchangeRate);

    event PaymentTokenChanged(address oldPaymentToken, address newPaymentToken);

    uint88 constant INITIAL_INFLATION_RATE = 1463753e18;
    uint88 constant INITIAL_REDUCTION_FACTOR = 1.189207115e18;
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
    AuctionModule public auctionModule;
    TestSMRewardDistributor public rewardDistributor;
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
            address(0),
            address(0),
            INITIAL_MAX_USER_LOSS
        );

        // Deploy auction module
        auctionModule = new AuctionModule(safetyModule, IERC20(address(usdc)));
        safetyModule.setAuctionModule(auctionModule);

        // Deploy reward distributor
        rewardDistributor = new TestSMRewardDistributor(
            safetyModule,
            INITIAL_MAX_MULTIPLIER,
            INITIAL_SMOOTHING_VALUE,
            address(rewardVault)
        );
        safetyModule.setRewardDistributor(rewardDistributor);

        // Transfer half of the rewards tokens to the reward vault
        rewardsToken.transfer(
            address(rewardVault),
            rewardsToken.totalSupply() / 2
        );
        rewardVault.approve(
            rewardsToken,
            address(rewardDistributor),
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
        uint256[] memory rewardWeights = new uint256[](2);
        rewardWeights[0] = 5000;
        rewardWeights[1] = 5000;
        rewardDistributor.addRewardToken(
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
        assertEq(
            safetyModule.getNumStakingTokens(),
            2,
            "Staking token count mismatch"
        );
        assertEq(
            address(safetyModule.stakingTokens(0)),
            address(stakedToken1),
            "Market address mismatch"
        );
        assertEq(
            safetyModule.getStakingTokenIdx(address(stakedToken2)),
            1,
            "Staking token index mismatch"
        );
        assertEq(
            stakedToken1.balanceOf(liquidityProviderTwo),
            0,
            "Current position mismatch"
        );
        assertEq(
            rewardDistributor.computeRewardMultiplier(
                liquidityProviderTwo,
                address(stakedToken1)
            ),
            0,
            "Reward multiplier mismatch"
        );
        _stake(stakedToken1, liquidityProviderTwo, 100 ether);
        assertEq(
            stakedToken1.balanceOf(liquidityProviderTwo),
            100 ether,
            "Current position mismatch"
        );
        assertEq(
            rewardDistributor.computeRewardMultiplier(
                liquidityProviderTwo,
                address(stakedToken1)
            ),
            1e18,
            "Reward multiplier mismatch"
        );
        assertEq(
            address(stakedToken1.getUnderlyingToken()),
            address(rewardsToken),
            "Underlying token mismatch"
        );
        assertEq(
            stakedToken1.getCooldownSeconds(),
            COOLDOWN_SECONDS,
            "Cooldown seconds mismatch"
        );
        assertEq(
            stakedToken1.getUnstakeWindowSeconds(),
            UNSTAKE_WINDOW,
            "Unstake window mismatch"
        );
    }

    /* ******************* */
    /*   Staking Rewards   */
    /* ******************* */

    function testRewardMultiplier() public {
        // Test with smoothing value of 30 and max multiplier of 4
        // These values match those in the spreadsheet used to design the SM rewards
        _stake(stakedToken1, liquidityProviderTwo, 100 ether);
        assertEq(
            rewardDistributor.computeRewardMultiplier(
                liquidityProviderTwo,
                address(stakedToken1)
            ),
            1e18,
            "Reward multiplier mismatch after initial stake"
        );
        skip(2 days);
        assertEq(
            rewardDistributor.computeRewardMultiplier(
                liquidityProviderTwo,
                address(stakedToken1)
            ),
            1.5e18,
            "Reward multiplier mismatch after 2 days"
        );
        // Partially redeeming resets the multiplier to 1
        _redeem(stakedToken1, liquidityProviderTwo, 50 ether, 1 days);
        assertEq(
            rewardDistributor.computeRewardMultiplier(
                liquidityProviderTwo,
                address(stakedToken1)
            ),
            1e18,
            "Reward multiplier mismatch after redeeming half"
        );
        skip(5 days);
        assertEq(
            rewardDistributor.computeRewardMultiplier(
                liquidityProviderTwo,
                address(stakedToken1)
            ),
            2e18,
            "Reward multiplier mismatch after 5 days"
        );
        // Staking again pushed the multiplier start time forward by a weighted amount
        // In this case, the multiplier start time is pushed forward by 2.5 days, because
        // it had been 5 days ago, and the user doubled their stake
        _stake(stakedToken1, liquidityProviderTwo, 50 ether);
        assertEq(
            rewardDistributor.computeRewardMultiplier(
                liquidityProviderTwo,
                address(stakedToken1)
            ),
            1.6e18,
            "Reward multiplier mismatch after staking again"
        );
        skip(2.5 days);
        assertEq(
            rewardDistributor.computeRewardMultiplier(
                liquidityProviderTwo,
                address(stakedToken1)
            ),
            2e18,
            "Reward multiplier mismatch after another 2.5 days"
        );
        // Redeeming completely resets the multiplier to 0
        _redeem(stakedToken1, liquidityProviderTwo, 100 ether, 1 days);
        assertEq(
            rewardDistributor.computeRewardMultiplier(
                liquidityProviderTwo,
                address(stakedToken1)
            ),
            0,
            "Reward multiplier mismatch after redeeming completely"
        );

        // Test with smoothing value of 60, doubling the time it takes to reach the same multiplier
        rewardDistributor.setSmoothingValue(60e18);
        _stake(stakedToken1, liquidityProviderTwo, 100 ether);
        assertEq(
            rewardDistributor.computeRewardMultiplier(
                liquidityProviderTwo,
                address(stakedToken1)
            ),
            1e18,
            "Reward multiplier mismatch after staking with new smoothing value"
        );
        skip(4 days);
        assertEq(
            rewardDistributor.computeRewardMultiplier(
                liquidityProviderTwo,
                address(stakedToken1)
            ),
            1.5e18,
            "Reward multiplier mismatch after increasing smoothing value"
        );

        // Test with max multiplier of 6, increasing the multiplier by 50%
        rewardDistributor.setMaxRewardMultiplier(6e18);
        assertEq(
            rewardDistributor.computeRewardMultiplier(
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
        uint256 rewardPreview = _viewNewRewardAccrual(
            address(stakedToken1),
            liquidityProviderTwo,
            address(rewardsToken)
        );

        // Get current reward multiplier
        uint256 rewardMultiplier = rewardDistributor.computeRewardMultiplier(
            liquidityProviderTwo,
            address(stakedToken1)
        );

        // Redeem stakedToken1
        stakedToken1.redeemTo(liquidityProviderTwo, stakeAmount);

        // Get accrued rewards
        uint256 accruedRewards = rewardDistributor.rewardsAccruedByUser(
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
        uint256 cumulativeRewardsPerLpToken = rewardDistributor
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
        rewardDistributor.accrueRewards(
            address(stakedToken1),
            liquidityProviderTwo
        );
        assertEq(
            rewardDistributor.rewardsAccruedByUser(
                liquidityProviderTwo,
                address(rewardsToken)
            ),
            accruedRewards,
            "Accrued more rewards after full redeem"
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
            rewardDistributor.lpPositionsPerUser(
                liquidityProviderTwo,
                address(stakedToken1)
            )
        );
        console.log(
            rewardDistributor.lpPositionsPerUser(
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
            address(0),
            address(0),
            INITIAL_MAX_USER_LOSS
        );
        AuctionModule newAuctionModule = new AuctionModule(
            ISafetyModule(address(0)),
            IERC20(address(usdc))
        );
        newSafetyModule.setAuctionModule(newAuctionModule);
        newAuctionModule.setSafetyModule(newSafetyModule);
        TestSMRewardDistributor newRewardDistributor = new TestSMRewardDistributor(
                ISafetyModule(address(0)),
                INITIAL_MAX_MULTIPLIER,
                INITIAL_SMOOTHING_VALUE,
                address(rewardVault)
            );
        newSafetyModule.setRewardDistributor(newRewardDistributor);
        newRewardDistributor.setSafetyModule(newSafetyModule);

        rewardVault.approve(
            rewardsToken,
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
        uint256[] memory rewardWeights = new uint256[](2);
        rewardWeights[0] = 5000;
        rewardWeights[1] = 5000;
        newRewardDistributor.addRewardToken(
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

        // skip some time
        console.log("skipping 10 days");
        skip(10 days);

        // before registering positions, expect accruing rewards to fail
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
        newRewardDistributor.accrueRewards(liquidityProviderTwo);

        // register user positions
        vm.startPrank(liquidityProviderOne);
        newRewardDistributor.registerPositions(stakingTokens);
        vm.startPrank(liquidityProviderTwo);
        newRewardDistributor.registerPositions(stakingTokens);

        // skip some time
        skip(10 days);

        // check that rewards were accrued correctly

        newRewardDistributor.accrueRewards(liquidityProviderTwo);
        uint256 cumulativeRewards1 = newRewardDistributor
            .cumulativeRewardPerLpToken(
                address(rewardsToken),
                address(stakedToken1)
            );
        uint256 cumulativeRewards2 = newRewardDistributor
            .cumulativeRewardPerLpToken(
                address(rewardsToken),
                address(stakedToken2)
            );
        uint256 inflationRate = newRewardDistributor.getInitialInflationRate(
            address(rewardsToken)
        );
        uint256 totalLiquidity1 = newRewardDistributor.totalLiquidityPerMarket(
            address(stakedToken1)
        );
        uint256 totalLiquidity2 = newRewardDistributor.totalLiquidityPerMarket(
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

        // redeem all staked tokens and claim rewards (for gas measurement)
        IStakedToken[] memory stakedTokens = new IStakedToken[](2);
        stakedTokens[0] = stakedToken1;
        stakedTokens[1] = stakedToken2;
        _claimAndRedeemAll(
            stakedTokens,
            newRewardDistributor,
            liquidityProviderTwo
        );
    }

    function testRewardTokenShortfall(uint256 stakeAmount) public {
        /* bounds */
        stakeAmount = bound(stakeAmount, 100e18, 10_000e18);

        // Stake only with stakedToken1 for this test
        _stake(stakedToken1, liquidityProviderTwo, stakeAmount);

        // Remove all reward tokens from EcosystemReserve
        uint256 rewardBalance = rewardsToken.balanceOf(address(rewardVault));
        rewardVault.transfer(rewardsToken, address(this), rewardBalance);

        // Skip some time
        skip(10 days);

        // Get reward preview
        uint256 rewardPreview = _viewNewRewardAccrual(
            address(stakedToken1),
            liquidityProviderTwo,
            address(rewardsToken)
        );

        // Accrue rewards, expecting RewardTokenShortfall event
        vm.expectEmit(false, false, false, true);
        emit RewardTokenShortfall(address(rewardsToken), rewardPreview);
        rewardDistributor.accrueRewards(
            address(stakedToken1),
            liquidityProviderTwo
        );

        // Skip some more time
        skip(9 days);

        // Start cooldown period
        vm.startPrank(liquidityProviderTwo);
        stakedToken1.cooldown();

        // Skip cooldown period
        skip(1 days);

        // Get second reward preview
        uint256 rewardPreview2 = _viewNewRewardAccrual(
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
        rewardDistributor.claimRewardsFor(liquidityProviderTwo);
        assertEq(
            rewardsToken.balanceOf(liquidityProviderTwo),
            10_000e18,
            "Claimed rewards after shortfall"
        );

        // Transfer reward tokens back to the EcosystemReserve
        vm.stopPrank();
        rewardsToken.transfer(address(rewardVault), rewardBalance);

        // Claim tokens and check that the accrued rewards were distributed
        rewardDistributor.claimRewardsFor(liquidityProviderTwo);
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
        uint256[] memory rewardWeights = new uint256[](3);
        rewardWeights[0] = 3333;
        rewardWeights[1] = 3334;
        rewardWeights[2] = 3333;
        rewardDistributor.updateRewardWeights(
            address(rewardsToken),
            stakingTokens,
            rewardWeights
        );

        // Check that rewardToken was added to the list of reward tokens for the new staked token
        assertEq(
            rewardDistributor.rewardTokens(0),
            address(rewardsToken),
            "Reward token missing for new staked token"
        );

        // Skip some time
        skip(10 days);

        // Get reward preview, expecting it to be 0
        uint256 rewardPreview = _viewNewRewardAccrual(
            address(stakedToken3),
            liquidityProviderTwo,
            address(rewardsToken)
        );
        assertEq(rewardPreview, 0, "Reward preview should be 0");

        // Accrue rewards, expecting it to accrue 0 rewards
        rewardDistributor.accrueRewards(
            address(stakedToken3),
            liquidityProviderTwo
        );
        assertEq(
            rewardDistributor.rewardsAccruedByUser(
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
            rewardDistributor.computeRewardMultiplier(
                liquidityProviderOne,
                address(stakedToken1)
            ),
            2e18,
            "Reward multiplier mismatch: user 1"
        );
        assertEq(
            rewardDistributor.computeRewardMultiplier(
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
        uint256 accruedRewards1 = rewardDistributor.rewardsAccruedByUser(
            liquidityProviderOne,
            address(rewardsToken)
        );
        uint256 accruedRewards2 = rewardDistributor.rewardsAccruedByUser(
            liquidityProviderTwo,
            address(rewardsToken)
        );
        uint256 cumRewardsPerLpToken = rewardDistributor
            .cumulativeRewardPerLpToken(
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

        // Check that user 1's multiplier is now 0, while user 2's is scaled according to the increase in stake
        uint256 increaseRatio = initialBalance1.wadDiv(
            initialBalance1 + initialBalance2
        );
        console.log("increaseRatio: %s", increaseRatio);
        assertEq(
            rewardDistributor.computeRewardMultiplier(
                liquidityProviderOne,
                address(stakedToken1)
            ),
            0,
            "Reward multiplier mismatch after transfer: user 1"
        );
        uint256 newMultiplierStartTime = rewardDistributor
            .multiplierStartTimeByUser(
                liquidityProviderTwo,
                address(stakedToken1)
            );
        assertEq(
            newMultiplierStartTime,
            block.timestamp - uint256(5 days).wadMul(1e18 - increaseRatio),
            "Multiplier start time mismatch after transfer: user 2"
        );
        uint256 deltaDays = (block.timestamp - newMultiplierStartTime).wadDiv(
            1 days
        );
        uint256 expectedMultiplier = INITIAL_MAX_MULTIPLIER -
            (INITIAL_SMOOTHING_VALUE * (INITIAL_MAX_MULTIPLIER - 1e18)) /
            ((deltaDays * (INITIAL_MAX_MULTIPLIER - 1e18)) /
                1e18 +
                INITIAL_SMOOTHING_VALUE);
        assertEq(
            rewardDistributor.computeRewardMultiplier(
                liquidityProviderTwo,
                address(stakedToken1)
            ),
            expectedMultiplier,
            "Reward multiplier mismatch after transfer: user 2"
        );

        // Claim rewards for both users
        rewardDistributor.claimRewardsFor(liquidityProviderOne);
        rewardDistributor.claimRewardsFor(liquidityProviderTwo);

        // Skip some more time
        skip(10 days - (block.timestamp - newMultiplierStartTime));

        // 10 days after the new multiplier start time, user 2's multiplier should be 2.5
        assertEq(
            rewardDistributor.computeRewardMultiplier(
                liquidityProviderOne,
                address(stakedToken1)
            ),
            0,
            "Reward multiplier mismatch after 10 days: user 1"
        );
        assertEq(
            rewardDistributor.computeRewardMultiplier(
                liquidityProviderTwo,
                address(stakedToken1)
            ),
            2.5e18,
            "Reward multiplier mismatch after 10 days: user 2"
        );

        // Check that user 2 accrues rewards according to their new balance and multiplier, while user 1 accrues no rewards
        rewardDistributor.accrueRewards(
            address(stakedToken1),
            liquidityProviderOne
        );
        rewardDistributor.accrueRewards(
            address(stakedToken1),
            liquidityProviderTwo
        );
        accruedRewards1 = rewardDistributor.rewardsAccruedByUser(
            liquidityProviderOne,
            address(rewardsToken)
        );
        accruedRewards2 = rewardDistributor.rewardsAccruedByUser(
            liquidityProviderTwo,
            address(rewardsToken)
        );
        cumRewardsPerLpToken =
            rewardDistributor.cumulativeRewardPerLpToken(
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

        // redeem all staked tokens and claim rewards (for gas measurement)
        IStakedToken[] memory stakedTokens = new IStakedToken[](1);
        stakedTokens[0] = stakedToken1;
        _claimAndRedeemAll(
            stakedTokens,
            rewardDistributor,
            liquidityProviderTwo
        );
        rewardDistributor.claimRewardsFor(liquidityProviderOne);
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

    /* ******************* */
    /*  Slashing/Auctions  */
    /* ******************* */

    function testAuctionableBalance(uint256 maxPercentUserLoss) public {
        /* bounds */
        maxPercentUserLoss = bound(maxPercentUserLoss, 0, 1e18);

        // Get initial balances
        uint256 balance1 = stakedToken1.balanceOf(liquidityProviderOne);
        uint256 balance2 = stakedToken2.balanceOf(liquidityProviderOne);

        // Set new max percent user loss and check auctionable balances
        safetyModule.setMaxPercentUserLoss(maxPercentUserLoss);
        assertEq(
            safetyModule.getAuctionableTotal(address(stakedToken1)),
            balance1.wadMul(maxPercentUserLoss),
            "Auctionable total 1 mismatch"
        );
        assertEq(
            safetyModule.getAuctionableTotal(address(stakedToken2)),
            balance2.wadMul(maxPercentUserLoss),
            "Auctionable total 2 mismatch"
        );
    }

    function testStakedTokenExchangeRate(
        uint256 donatePercent,
        uint256 slashPercent,
        uint256 stakeAmount
    ) public {
        /* bounds */
        donatePercent = bound(donatePercent, 1e16, 1e18);
        slashPercent = bound(slashPercent, 1e16, 1e18);
        stakeAmount = bound(stakeAmount, 100e18, 10_000e18);

        safetyModule.setMaxPercentUserLoss(1e18);

        // Check initial conditions
        uint256 initialSupply = stakedToken1.totalSupply();
        assertEq(
            initialSupply,
            rewardsToken.balanceOf(address(stakedToken1)),
            "Initial supply mismatch"
        );
        assertEq(
            stakedToken1.exchangeRate(),
            1e18,
            "Initial exchange rate mismatch"
        );
        assertEq(
            stakedToken1.previewStake(stakeAmount),
            stakeAmount,
            "Preview stake mismatch"
        );
        assertEq(
            stakedToken1.previewRedeem(stakeAmount),
            stakeAmount,
            "Preview redeem mismatch"
        );

        // Get amounts from percents
        uint256 donateAmount = initialSupply.wadMul(donatePercent);
        uint256 slashAmount = initialSupply.wadMul(slashPercent);

        // Donate some tokens to the staked token and check the resulting exchange rate
        rewardsToken.approve(address(stakedToken1), donateAmount);
        safetyModule.returnFunds(
            address(stakedToken1),
            address(this),
            donateAmount
        );
        assertEq(
            stakedToken1.exchangeRate(),
            1e18 + donatePercent,
            "Exchange rate mismatch after donation"
        );
        assertEq(
            stakedToken1.previewStake(stakeAmount),
            stakeAmount.wadDiv(1e18 + donatePercent),
            "Preview stake mismatch after donation"
        );
        assertEq(
            stakedToken1.previewRedeem(stakeAmount),
            stakeAmount.wadMul(1e18 + donatePercent),
            "Preview redeem mismatch after donation"
        );

        // Slash the donated tokens and check the resulting exchange rate
        vm.startPrank(address(safetyModule));
        uint256 slashedDonation = stakedToken1.slash(
            address(this),
            stakedToken1.previewStake(donateAmount)
        );
        assertApproxEqAbs(
            slashedDonation,
            donateAmount,
            10, // 10 wei tolerance for rounding error
            "Slashed donation mismatch"
        );
        assertEq(
            stakedToken1.exchangeRate(),
            1e18,
            "Exchange rate mismatch after donating then slashing the same amount"
        );
        stakedToken1.settleSlashing();

        // Slash some more tokens and check the resulting exchange rate
        uint256 slashedAmount = stakedToken1.slash(address(this), slashAmount);
        assertApproxEqAbs(
            slashedAmount,
            slashAmount,
            10, // 10 wei tolerance for rounding error
            "Slashed amount mismatch"
        );
        assertEq(
            stakedToken1.exchangeRate(),
            1e18 - slashPercent,
            "Exchange rate mismatch after slashing"
        );
        if (slashPercent == 1e18) {
            assertEq(
                stakedToken1.previewStake(stakeAmount),
                0,
                "Preview stake mismatch after slashing"
            );
        } else {
            assertEq(
                stakedToken1.previewStake(stakeAmount),
                stakeAmount.wadDiv(1e18 - slashPercent),
                "Preview stake mismatch after slashing"
            );
        }
        assertEq(
            stakedToken1.previewRedeem(stakeAmount),
            stakeAmount.wadMul(1e18 - slashPercent),
            "Preview redeem mismatch after slashing"
        );

        // Return the slashed tokens to the staked token and check the resulting exchange rate
        vm.stopPrank();
        rewardsToken.approve(address(stakedToken1), slashedAmount);
        safetyModule.returnFunds(
            address(stakedToken1),
            address(this),
            slashedAmount
        );
        assertEq(
            stakedToken1.exchangeRate(),
            1e18,
            "Exchange rate mismatch after returning slashed amount"
        );
    }

    function testAuctionSoldOut(
        uint8 numLots,
        uint128 lotPrice,
        uint128 initialLotSize
    ) public {
        /* bounds */
        numLots = uint8(bound(numLots, 2, 10));
        lotPrice = uint128(bound(lotPrice, 1e8, 1e12)); // denominated in USDC w/ 6 decimals
        // lotSize x numLots should not exceed auctionable balance
        uint256 auctionableBalance = safetyModule.getAuctionableTotal(
            address(stakedToken1)
        );
        initialLotSize = uint128(
            bound(initialLotSize, 1e18, auctionableBalance / numLots)
        );
        uint96 lotIncreaseIncrement = uint96(
            bound(initialLotSize / 50, 2e16, type(uint96).max)
        );
        uint16 lotIncreasePeriod = uint16(2 hours);
        uint32 timeLimit = uint32(10 days);

        // Start an auction and check that it was created correctly
        uint256 auctionId = safetyModule.slashAndStartAuction(
            address(stakedToken1),
            numLots,
            lotPrice,
            initialLotSize,
            lotIncreaseIncrement,
            lotIncreasePeriod,
            timeLimit
        );
        assertEq(
            auctionModule.getCurrentLotSize(auctionId),
            initialLotSize,
            "Initial lot size mismatch"
        );
        assertEq(
            auctionModule.getRemainingLots(auctionId),
            numLots,
            "Initial lots mismatch"
        );
        assertEq(
            auctionModule.getLotPrice(auctionId),
            lotPrice,
            "Lot price mismatch"
        );
        assertEq(
            auctionModule.getLotIncreaseIncrement(auctionId),
            lotIncreaseIncrement,
            "Lot increase increment mismatch"
        );
        assertEq(
            auctionModule.getLotIncreasePeriod(auctionId),
            lotIncreasePeriod,
            "Lot increase period mismatch"
        );
        assertEq(
            address(auctionModule.getAuctionToken(auctionId)),
            address(stakedToken1.getUnderlyingToken()),
            "Auction token mismatch"
        );
        assertEq(
            auctionModule.getStartTime(auctionId),
            block.timestamp,
            "Start time mismatch"
        );
        assertEq(
            auctionModule.getEndTime(auctionId),
            block.timestamp + timeLimit,
            "End time mismatch"
        );
        assertTrue(
            auctionModule.isAuctionActive(auctionId),
            "Auction should be active"
        );

        // Check the state of the StakedToken after slashing
        assertTrue(
            stakedToken1.isInPostSlashingState(),
            "Staked token should be in post slashing state"
        );
        assertEq(
            stakedToken1.exchangeRate(),
            1e18 - INITIAL_MAX_USER_LOSS,
            "Exchange rate mismatch after slashing"
        );

        // Buy all the lots at once and check the buyer's resulting balance
        uint256 balanceBefore = stakedToken1.getUnderlyingToken().balanceOf(
            liquidityProviderTwo
        );
        _dealAndBuyLots(liquidityProviderTwo, auctionId, numLots, lotPrice);
        uint256 balanceAfter = stakedToken1.getUnderlyingToken().balanceOf(
            liquidityProviderTwo
        );
        assertEq(
            balanceAfter,
            balanceBefore + initialLotSize * numLots,
            "Balance mismatch after buying all lots"
        );

        // Check that the auction is no longer active and unsold tokens have been returned
        assertTrue(
            !auctionModule.isAuctionActive(auctionId),
            "Auction should not be active after selling out"
        );
        assertEq(
            auctionModule.getAuctionToken(auctionId).balanceOf(
                address(auctionModule)
            ),
            0,
            "Unsold tokens should be returned from the auction module"
        );

        // Check the state of the StakedToken after slashing is settled and unsold tokens are returned
        assertTrue(
            !stakedToken1.isInPostSlashingState(),
            "Staked token should not be in post slashing state after selling out"
        );
        assertApproxEqAbs(
            stakedToken1.exchangeRate(),
            1e18 -
                uint256(initialLotSize * numLots).wadDiv(
                    stakedToken1.totalSupply()
                ),
            10, // 10 wei tolerance for rounding error
            "Exchange rate mismatch after returning unsold tokens"
        );

        // Withdraw the funds raised from the auction and check the resulting balance
        uint256 fundsRaised = auctionModule.fundsRaisedPerAuction(auctionId);
        assertEq(
            fundsRaised,
            lotPrice * numLots,
            "Funds raised mismatch after selling out"
        );
        safetyModule.withdrawFundsRaisedFromAuction(fundsRaised);
        assertEq(
            usdc.balanceOf(address(this)),
            fundsRaised,
            "Balance mismatch after withdrawing funds raised from auction"
        );
        assertEq(
            usdc.balanceOf(address(auctionModule)),
            0,
            "Auction module should have no remaining funds after withdrawing"
        );
    }

    function testAuctionTimeOut(
        uint8 numLots,
        uint128 lotPrice,
        uint128 initialLotSize
    ) public {
        /* bounds */
        numLots = uint8(bound(numLots, 2, 10));
        lotPrice = uint128(bound(lotPrice, 1e18, 1e22)); // denominated in UA w/ 18 decimals
        // initialLotSize x numLots should not exceed auctionable balance
        uint256 auctionableBalance = safetyModule.getAuctionableTotal(
            address(stakedToken1)
        );
        initialLotSize = uint128(
            bound(initialLotSize, 1e18, auctionableBalance / numLots)
        );
        uint96 lotIncreaseIncrement = uint96(
            bound(initialLotSize / 50, 2e16, type(uint96).max)
        );
        uint16 lotIncreasePeriod = uint16(2 hours);
        uint32 timeLimit = uint32(10 days);

        // Change the payment token to UA
        vm.expectEmit(false, false, false, true);
        emit PaymentTokenChanged(address(usdc), address(ua));
        auctionModule.setPaymentToken(IERC20(address(ua)));

        // Start an auction and check the end time
        uint256 auctionId = safetyModule.slashAndStartAuction(
            address(stakedToken1),
            numLots,
            lotPrice,
            initialLotSize,
            lotIncreaseIncrement,
            lotIncreasePeriod,
            timeLimit
        );
        uint256 endTime = auctionModule.getEndTime(auctionId);
        assertEq(
            endTime,
            block.timestamp + timeLimit,
            "End time mismatch after starting auction"
        );

        // Skip one day at a time until the end of the auction without buying any lots,
        // checking that the currentLotSize x numLots does not exceed auctionable balance
        for (uint i; i < 10; i++) {
            skip(1 days);
            uint256 currentLotSize = auctionModule.getCurrentLotSize(auctionId);
            assertLe(
                currentLotSize * numLots,
                auctionableBalance,
                "Current lot size x num lots should not exceed auctionable balance"
            );
        }
        assertEq(
            auctionModule.fundsRaisedPerAuction(auctionId),
            0,
            "Funds raised should be 0 after auction times out"
        );

        // Check that the auction is no longer active
        assertTrue(
            !auctionModule.isAuctionActive(auctionId),
            "Auction should not be active after timing out"
        );
        vm.expectRevert(
            abi.encodeWithSignature(
                "AuctionModule_AuctionNotActive(uint256)",
                auctionId
            )
        );
        auctionModule.buyLots(auctionId, 1);

        // Complete the auction and check that all tokens were returned
        vm.startPrank(liquidityProviderOne); // Anyone can complete the auction after it times out
        uint256 finalLotSize = uint256(initialLotSize) +
            lotIncreaseIncrement *
            (10 days / 2 hours);
        if (finalLotSize > auctionableBalance / numLots) {
            finalLotSize = auctionableBalance / numLots;
        }
        vm.expectEmit(false, false, false, true);
        emit Approval(
            address(auctionModule),
            address(stakedToken1),
            auctionableBalance
        );
        vm.expectEmit(false, false, false, true);
        emit AuctionEnded(auctionId, numLots, finalLotSize, 0, 0);
        auctionModule.completeAuction(auctionId);
        assertEq(
            auctionModule.getAuctionToken(auctionId).balanceOf(
                address(auctionModule)
            ),
            0,
            "Unsold tokens should be returned from the auction module"
        );
        assertEq(
            stakedToken1.exchangeRate(),
            1e18,
            "Exchange rate mismatch after returning unsold tokens"
        );
    }

    function testTerminateAuctionEarly(
        uint8 numLots,
        uint128 lotPrice,
        uint128 initialLotSize
    ) public {
        /* bounds */
        numLots = uint8(bound(numLots, 2, 10));
        lotPrice = uint128(bound(lotPrice, 1e8, 1e12)); // denominated in USDC w/ 6 decimals
        // lotSize x numLots should not exceed auctionable balance
        uint256 auctionableBalance = safetyModule.getAuctionableTotal(
            address(stakedToken1)
        );
        initialLotSize = uint128(
            bound(initialLotSize, 1e18, auctionableBalance / numLots)
        );
        uint96 lotIncreaseIncrement = uint96(
            bound(initialLotSize / 50, 2e16, type(uint96).max)
        );
        uint16 lotIncreasePeriod = uint16(2 hours);
        uint32 timeLimit = uint32(10 days);

        // Start an auction and check that it was created correctly
        uint256 auctionId = safetyModule.slashAndStartAuction(
            address(stakedToken1),
            numLots,
            lotPrice,
            initialLotSize,
            lotIncreaseIncrement,
            lotIncreasePeriod,
            timeLimit
        );
        assertTrue(
            auctionModule.isAuctionActive(auctionId),
            "Auction should be active"
        );

        // Check the state of the StakedToken after slashing
        assertTrue(
            stakedToken1.isInPostSlashingState(),
            "Staked token should be in post slashing state"
        );
        assertEq(
            stakedToken1.exchangeRate(),
            1e18 - INITIAL_MAX_USER_LOSS,
            "Exchange rate mismatch after slashing"
        );

        // Terminate the auction early and check events
        vm.expectEmit(false, false, false, true);
        emit Approval(
            address(auctionModule),
            address(stakedToken1),
            auctionableBalance
        );
        vm.expectEmit(false, false, false, true);
        emit AuctionEnded(auctionId, numLots, initialLotSize, 0, 0);
        vm.expectEmit(false, false, false, true);
        emit ExchangeRateUpdated(1e18);
        vm.expectEmit(false, false, false, true);
        emit FundsReturned(address(auctionModule), auctionableBalance);
        vm.expectEmit(false, false, false, true);
        emit SlashingSettled();
        vm.expectEmit(false, false, false, true);
        emit AuctionTerminated(
            auctionId,
            address(stakedToken1),
            address(rewardsToken),
            auctionableBalance
        );
        safetyModule.terminateAuction(auctionId);

        // Check that the auction is no longer active and unsold tokens have been returned
        assertTrue(
            !auctionModule.isAuctionActive(auctionId),
            "Auction should not be active after terminating early"
        );
        assertEq(
            auctionModule.getAuctionToken(auctionId).balanceOf(
                address(auctionModule)
            ),
            0,
            "Unsold tokens should be returned from the auction module"
        );
        assertEq(
            stakedToken1.exchangeRate(),
            1e18,
            "Exchange rate mismatch after returning unsold tokens"
        );
        assertTrue(
            !stakedToken1.isInPostSlashingState(),
            "Staked token should not be in post slashing state after settling slashing"
        );
        vm.startPrank(liquidityProviderOne);
        vm.expectRevert(
            abi.encodeWithSignature(
                "AuctionModule_AuctionNotActive(uint256)",
                auctionId
            )
        );
        auctionModule.buyLots(auctionId, 1);
        vm.expectRevert(
            abi.encodeWithSignature(
                "AuctionModule_AuctionNotActive(uint256)",
                auctionId
            )
        );
        auctionModule.completeAuction(auctionId);
        vm.stopPrank();
    }

    /* ******************* */
    /*    Custom Errors    */
    /* ******************* */

    function testSafetyModuleErrors(
        uint256 highMaxUserLoss,
        uint256 lowMaxMultiplier,
        uint256 highMaxMultiplier,
        uint256 lowSmoothingValue,
        uint256 highSmoothingValue,
        uint256 invalidMarketIdx,
        address invalidMarket,
        address invalidRewardToken,
        uint8 numLots,
        uint128 lotSize
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
        vm.assume(
            uint256(numLots) * uint256(lotSize) >
                safetyModule.getAuctionableTotal(address(stakedToken1))
        );

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
                "SMRD_InvalidMaxMultiplierTooLow(uint256,uint256)",
                lowMaxMultiplier,
                1e18
            )
        );
        rewardDistributor.setMaxRewardMultiplier(lowMaxMultiplier);
        vm.expectRevert(
            abi.encodeWithSignature(
                "SMRD_InvalidMaxMultiplierTooHigh(uint256,uint256)",
                highMaxMultiplier,
                10e18
            )
        );
        rewardDistributor.setMaxRewardMultiplier(highMaxMultiplier);
        vm.expectRevert(
            abi.encodeWithSignature(
                "SMRD_InvalidSmoothingValueTooLow(uint256,uint256)",
                lowSmoothingValue,
                10e18
            )
        );
        rewardDistributor.setSmoothingValue(lowSmoothingValue);
        vm.expectRevert(
            abi.encodeWithSignature(
                "SMRD_InvalidSmoothingValueTooHigh(uint256,uint256)",
                highSmoothingValue,
                100e18
            )
        );
        rewardDistributor.setSmoothingValue(highSmoothingValue);
        vm.expectRevert(
            abi.encodeWithSignature("RewardDistributor_InvalidZeroAddress()")
        );
        rewardDistributor.setSafetyModule(ISafetyModule(address(0)));

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
        vm.startPrank(invalidMarket);
        vm.expectRevert(
            abi.encodeWithSignature(
                "SafetyModule_CallerIsNotStakingToken(address)",
                invalidMarket
            )
        );
        safetyModule.updatePosition(invalidMarket, liquidityProviderOne);
        vm.startPrank(address(safetyModule));
        vm.expectRevert(
            abi.encodeWithSignature(
                "RewardDistributor_AlreadyInitializedStartTime(address)",
                address(stakedToken1)
            )
        );
        rewardDistributor.initMarketStartTime(address(stakedToken1));
        vm.stopPrank();

        // test insufficient auctionable funds
        vm.expectRevert(
            abi.encodeWithSignature(
                "SafetyModule_InsufficientSlashedTokensForAuction(address,uint256,uint256)",
                address(stakedToken1.getUnderlyingToken()),
                uint256(numLots) * uint256(lotSize),
                safetyModule.getAuctionableTotal(address(stakedToken1))
            )
        );
        safetyModule.slashAndStartAuction(
            address(stakedToken1),
            numLots,
            0,
            lotSize,
            0,
            0,
            1 days
        );

        // test invalid caller not auction module
        vm.expectRevert(
            abi.encodeWithSignature(
                "SafetyModule_CallerIsNotAuctionModule(address)",
                address(this)
            )
        );
        safetyModule.auctionEnded(0, 0);
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
        vm.startPrank(address(safetyModule));
        vm.expectRevert(
            abi.encodeWithSignature("StakedToken_InvalidZeroAmount()")
        );
        stakedToken1.slash(address(safetyModule), 0);
        vm.expectRevert(
            abi.encodeWithSignature("StakedToken_InvalidZeroAmount()")
        );
        stakedToken1.returnFunds(address(safetyModule), 0);

        // test zero address
        vm.expectRevert(
            abi.encodeWithSignature("StakedToken_InvalidZeroAddress()")
        );
        stakedToken1.stakeOnBehalfOf(address(0), 1);
        vm.expectRevert(
            abi.encodeWithSignature("StakedToken_InvalidZeroAddress()")
        );
        stakedToken1.redeemTo(address(0), 1);
        vm.expectRevert(
            abi.encodeWithSignature("StakedToken_InvalidZeroAddress()")
        );
        stakedToken1.slash(address(0), 1);
        vm.expectRevert(
            abi.encodeWithSignature("StakedToken_InvalidZeroAddress()")
        );
        stakedToken1.returnFunds(address(0), 1);
        vm.stopPrank();

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
        if (stakedBalance % 2 == 0 && stakedBalance < type(uint256).max / 2)
            // test redeeming more than staked balance to make sure it adjusts the amount
            stakedToken1.redeem(stakedBalance * 2);
        else stakedToken1.redeem(stakedBalance);
        // restake, then try redeeming without cooldown
        stakedToken1.stake(stakedBalance);
        vm.expectRevert(
            abi.encodeWithSignature(
                "StakedToken_UnstakeWindowFinished(uint256)",
                11 days
            )
        );
        stakedToken1.redeem(stakedBalance);
        vm.stopPrank();

        // test invalid caller not safety module
        vm.expectRevert(
            abi.encodeWithSignature(
                "StakedToken_CallerIsNotSafetyModule(address)",
                address(this)
            )
        );
        stakedToken1.slash(address(this), 0);
        vm.expectRevert(
            abi.encodeWithSignature(
                "StakedToken_CallerIsNotSafetyModule(address)",
                address(this)
            )
        );
        stakedToken1.returnFunds(address(this), 0);
        vm.expectRevert(
            abi.encodeWithSignature(
                "StakedToken_CallerIsNotSafetyModule(address)",
                address(this)
            )
        );
        stakedToken1.settleSlashing();

        // test zero exchange rate
        safetyModule.setMaxPercentUserLoss(1e18); // set max user loss to 100%
        vm.startPrank(address(safetyModule));
        // slash 100% of staked tokens, resulting in zero exchange rate
        uint256 maxAuctionableTotal = safetyModule.getAuctionableTotal(
            address(stakedToken1)
        );
        uint256 slashedTokens = stakedToken1.slash(
            address(this),
            maxAuctionableTotal
        );
        vm.stopPrank();
        assertEq(
            stakedToken1.exchangeRate(),
            0,
            "Exchange rate should be 0 after slashing 100% of staked tokens"
        );
        assertEq(
            stakedToken1.previewStake(1e18),
            0,
            "Preview stake should be 0 when exchange rate is 0"
        );
        assertEq(
            stakedToken1.previewRedeem(1e18),
            0,
            "Preview redeem should be 0 when exchange rate is 0"
        );
        // staking and redeeming should fail due to zero exchange rate
        vm.expectRevert(
            abi.encodeWithSignature("StakedToken_ZeroExchangeRate()")
        );
        stakedToken1.stake(1);
        vm.expectRevert(
            abi.encodeWithSignature("StakedToken_ZeroExchangeRate()")
        );
        stakedToken1.redeem(1);

        // test features disabled in post-slashing state
        stakedToken1.getUnderlyingToken().approve(
            address(stakedToken1),
            type(uint256).max
        );
        vm.startPrank(address(safetyModule));
        // return all slashed funds, but do not settle slashing yet
        stakedToken1.returnFunds(address(this), slashedTokens);
        // slashing, staking and cooldown should fail due to post-slashing state
        vm.expectRevert(
            abi.encodeWithSignature(
                "StakedToken_SlashingDisabledInPostSlashingState()"
            )
        );
        stakedToken1.slash(address(this), slashedTokens);
        vm.startPrank(liquidityProviderOne);
        vm.expectRevert(
            abi.encodeWithSignature(
                "StakedToken_StakingDisabledInPostSlashingState()"
            )
        );
        stakedToken1.stake(1);
        vm.expectRevert(
            abi.encodeWithSignature(
                "StakedToken_CooldownDisabledInPostSlashingState()"
            )
        );
        stakedToken1.cooldown();
        vm.stopPrank();

        // test above max slash amount
        safetyModule.setMaxPercentUserLoss(0.3e18); // set max user loss to 30%
        uint256 maxSlashAmount = safetyModule.getAuctionableTotal(
            address(stakedToken1)
        );
        vm.startPrank(address(safetyModule));
        // end post-slashing state, which re-enables slashing
        stakedToken1.settleSlashing();
        vm.expectRevert(
            abi.encodeWithSignature(
                "StakedToken_AboveMaxSlashAmount(uint256,uint256)",
                maxAuctionableTotal,
                maxSlashAmount
            )
        );
        // try slashing 100% of staked tokens, when only 30% is allowed
        stakedToken1.slash(address(this), maxAuctionableTotal);
        vm.stopPrank();

        // test paused
        stakedToken1.pause();
        assertTrue(stakedToken1.paused(), "Staked token should be paused");
        vm.startPrank(address(liquidityProviderOne));
        vm.expectRevert(bytes("Pausable: paused"));
        stakedToken1.stake(1);
        vm.expectRevert(bytes("Pausable: paused"));
        stakedToken1.transfer(liquidityProviderTwo, 1);
        vm.stopPrank();
        stakedToken1.unpause();
        safetyModule.pause();
        assertTrue(
            stakedToken1.paused(),
            "Staked token should be paused when Safety Module is"
        );
        vm.startPrank(address(liquidityProviderOne));
        vm.expectRevert(bytes("Pausable: paused"));
        stakedToken1.stake(1);
        vm.expectRevert(bytes("Pausable: paused"));
        stakedToken1.transfer(liquidityProviderTwo, 1);
        vm.stopPrank();
        safetyModule.unpause();
    }

    function testAuctionModuleErrors() public {
        // start an auction successfully for later tests
        uint256 auctionId = safetyModule.slashAndStartAuction(
            address(stakedToken1),
            1,
            1 ether,
            1e18,
            0.1 ether,
            1 hours,
            10 days
        );

        // test invalid zero arguments
        vm.startPrank(address(safetyModule));
        vm.expectRevert(
            abi.encodeWithSignature(
                "AuctionModule_InvalidZeroAddress(uint256)",
                0
            )
        );
        auctionModule.startAuction(IERC20(address(0)), 0, 0, 0, 0, 0, 0);
        vm.expectRevert(
            abi.encodeWithSignature(
                "AuctionModule_InvalidZeroArgument(uint256)",
                1
            )
        );
        auctionModule.startAuction(rewardsToken, 0, 0, 0, 0, 0, 0);
        vm.expectRevert(
            abi.encodeWithSignature(
                "AuctionModule_InvalidZeroArgument(uint256)",
                2
            )
        );
        auctionModule.startAuction(rewardsToken, 1, 0, 0, 0, 0, 0);
        vm.expectRevert(
            abi.encodeWithSignature(
                "AuctionModule_InvalidZeroArgument(uint256)",
                3
            )
        );
        auctionModule.startAuction(rewardsToken, 1, 1, 0, 0, 0, 0);
        vm.expectRevert(
            abi.encodeWithSignature(
                "AuctionModule_InvalidZeroArgument(uint256)",
                4
            )
        );
        auctionModule.startAuction(rewardsToken, 1, 1, 1, 0, 0, 0);
        vm.expectRevert(
            abi.encodeWithSignature(
                "AuctionModule_InvalidZeroArgument(uint256)",
                5
            )
        );
        auctionModule.startAuction(rewardsToken, 1, 1, 1, 1, 0, 0);
        vm.expectRevert(
            abi.encodeWithSignature(
                "AuctionModule_InvalidZeroArgument(uint256)",
                6
            )
        );
        auctionModule.startAuction(rewardsToken, 1, 1, 1, 1, 1, 0);
        vm.stopPrank();
        vm.expectRevert(
            abi.encodeWithSignature(
                "AuctionModule_InvalidZeroAddress(uint256)",
                0
            )
        );
        auctionModule.setPaymentToken(IERC20(address(0)));
        vm.expectRevert(
            abi.encodeWithSignature(
                "AuctionModule_InvalidZeroAddress(uint256)",
                0
            )
        );
        auctionModule.setSafetyModule(ISafetyModule(address(0)));
        vm.expectRevert(
            abi.encodeWithSignature(
                "AuctionModule_InvalidZeroArgument(uint256)",
                1
            )
        );
        auctionModule.buyLots(auctionId, 0);

        // test invalid auction ID
        vm.expectRevert(
            abi.encodeWithSignature(
                "AuctionModule_InvalidAuctionId(uint256)",
                1
            )
        );
        auctionModule.buyLots(1, 1);
        vm.expectRevert(
            abi.encodeWithSignature(
                "AuctionModule_InvalidAuctionId(uint256)",
                1
            )
        );
        auctionModule.completeAuction(1);
        vm.expectRevert(
            abi.encodeWithSignature(
                "AuctionModule_InvalidAuctionId(uint256)",
                1
            )
        );
        auctionModule.getCurrentLotSize(1);
        vm.startPrank(address(safetyModule));
        vm.expectRevert(
            abi.encodeWithSignature(
                "AuctionModule_InvalidAuctionId(uint256)",
                1
            )
        );
        auctionModule.terminateAuction(1);
        vm.stopPrank();

        // test paused
        auctionModule.pause();
        assertTrue(auctionModule.paused(), "Auction module should be paused");
        vm.startPrank(address(safetyModule));
        vm.expectRevert(bytes("Pausable: paused"));
        auctionModule.startAuction(IERC20(address(0)), 0, 0, 0, 0, 0, 0);
        vm.stopPrank();
        vm.expectRevert(bytes("Pausable: paused"));
        auctionModule.buyLots(auctionId, 1);
        vm.expectRevert(bytes("Pausable: paused"));
        auctionModule.completeAuction(auctionId);
        auctionModule.unpause();
        safetyModule.pause();
        assertTrue(
            auctionModule.paused(),
            "Auction module should be paused when Safety Module is"
        );
        vm.startPrank(address(safetyModule));
        vm.expectRevert(bytes("Pausable: paused"));
        auctionModule.startAuction(IERC20(address(0)), 0, 0, 0, 0, 0, 0);
        vm.stopPrank();
        vm.expectRevert(bytes("Pausable: paused"));
        auctionModule.buyLots(auctionId, 1);
        vm.expectRevert(bytes("Pausable: paused"));
        auctionModule.completeAuction(auctionId);
        safetyModule.unpause();

        // test not enough lots remaining
        vm.expectRevert(
            abi.encodeWithSignature(
                "AuctionModule_NotEnoughLotsRemaining(uint256,uint256)",
                auctionId,
                1
            )
        );
        auctionModule.buyLots(auctionId, 2);

        // test invalid caller not safety module
        vm.expectRevert(
            abi.encodeWithSignature(
                "AuctionModule_CallerIsNotSafetyModule(address)",
                address(this)
            )
        );
        auctionModule.startAuction(IERC20(address(0)), 0, 0, 0, 0, 0, 0);
        vm.expectRevert(
            abi.encodeWithSignature(
                "AuctionModule_CallerIsNotSafetyModule(address)",
                address(this)
            )
        );
        auctionModule.terminateAuction(auctionId);

        // test auction still active
        vm.expectRevert(
            abi.encodeWithSignature(
                "AuctionModule_AuctionStillActive(uint256,uint256)",
                auctionId,
                block.timestamp + 10 days
            )
        );
        auctionModule.completeAuction(auctionId);

        // skip to auction end time
        skip(10 days);

        // test auction not active
        vm.expectRevert(
            abi.encodeWithSignature(
                "AuctionModule_AuctionNotActive(uint256)",
                auctionId
            )
        );
        auctionModule.buyLots(auctionId, 1); // reverts due to timestamp check, not active flag
        // complete auction manually, setting active flag to false
        auctionModule.completeAuction(auctionId);
        vm.expectRevert(
            abi.encodeWithSignature(
                "AuctionModule_AuctionNotActive(uint256)",
                auctionId
            )
        );
        auctionModule.completeAuction(auctionId);
        vm.startPrank(address(safetyModule));
        vm.expectRevert(
            abi.encodeWithSignature(
                "AuctionModule_AuctionNotActive(uint256)",
                auctionId
            )
        );
        auctionModule.terminateAuction(auctionId);
        vm.stopPrank();
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
        vm.expectEmit(false, false, false, true);
        emit Staked(staker, staker, amount);
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
        vm.expectEmit(false, false, false, true);
        emit Cooldown(staker);
        stakedToken.cooldown();
        skip(cooldown);
        vm.expectEmit(false, false, false, true);
        emit Redeemed(staker, staker, amount);
        stakedToken.redeem(amount);
        vm.stopPrank();
    }

    function _claimAndRedeemAll(
        IStakedToken[] memory stakedTokens,
        IRewardDistributor distributor,
        address staker
    ) internal {
        for (uint256 i; i < stakedTokens.length; i++) {
            IStakedToken stakedToken = stakedTokens[i];
            _redeem(
                stakedToken,
                staker,
                stakedToken.balanceOf(staker),
                stakedToken.getCooldownSeconds()
            );
        }
        distributor.claimRewardsFor(staker);
    }

    function _dealAndBuyLots(
        address buyer,
        uint256 auctionId,
        uint8 numLots,
        uint128 lotPrice
    ) internal {
        IERC20 paymentToken = auctionModule.paymentToken();
        IStakedToken stakedToken = safetyModule.stakingTokenByAuctionId(
            auctionId
        );
        deal(address(paymentToken), buyer, lotPrice * numLots);
        vm.startPrank(buyer);
        paymentToken.approve(address(auctionModule), lotPrice * numLots);
        uint256 lotSize = auctionModule.getCurrentLotSize(auctionId);
        uint256 tokensAlreadySold = auctionModule.tokensSoldPerAuction(
            auctionId
        );
        uint256 fundsAlreadyRaised = auctionModule.fundsRaisedPerAuction(
            auctionId
        );
        uint256 remainingBalance = auctionModule
            .getAuctionToken(auctionId)
            .balanceOf(address(auctionModule)) - lotSize * numLots;
        vm.expectEmit(true, true, false, true);
        emit LotsSold(auctionId, buyer, numLots, lotSize, lotPrice);
        if (numLots == auctionModule.getRemainingLots(auctionId)) {
            if (remainingBalance > 0) {
                vm.expectEmit(false, false, false, true);
                emit Approval(
                    address(auctionModule),
                    address(stakedToken),
                    remainingBalance
                );
            }
            vm.expectEmit(false, false, false, true);
            emit Approval(
                address(auctionModule),
                address(safetyModule),
                fundsAlreadyRaised + lotPrice * numLots
            );
            vm.expectEmit(true, false, false, true);
            emit AuctionEnded(
                auctionId,
                0,
                lotSize,
                tokensAlreadySold + lotSize * numLots,
                fundsAlreadyRaised + lotPrice * numLots
            );
        }
        auctionModule.buyLots(auctionId, numLots);
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

    function _viewNewRewardAccrual(
        address market,
        address user
    ) public view returns (uint256[] memory) {
        uint256 numTokens = rewardDistributor.getRewardTokenCount();
        uint256[] memory newRewards = new uint256[](numTokens);
        for (uint i; i < numTokens; ++i) {
            newRewards[i] = _viewNewRewardAccrual(
                market,
                user,
                rewardDistributor.rewardTokens(i)
            );
        }
        return newRewards;
    }

    function _viewNewRewardAccrual(
        address market,
        address user,
        address token
    ) internal view returns (uint256) {
        uint256 deltaTime = block.timestamp -
            rewardDistributor.timeOfLastCumRewardUpdate(market);
        if (rewardDistributor.totalLiquidityPerMarket(market) == 0) return 0;
        // Calculate the new cumRewardPerLpToken by adding (inflationRatePerSecond x guageWeight x deltaTime) to the previous cumRewardPerLpToken
        uint256 newMarketRewards = (((rewardDistributor.getInflationRate(
            token
        ) * rewardDistributor.getRewardWeight(token, market)) / 10000) *
            deltaTime) / 365 days;
        uint256 newCumRewardPerLpToken = rewardDistributor
            .cumulativeRewardPerLpToken(token, market) +
            (newMarketRewards * 1e18) /
            rewardDistributor.totalLiquidityPerMarket(market);
        uint256 newUserRewards = rewardDistributor
            .lpPositionsPerUser(user, market)
            .wadMul(
                (newCumRewardPerLpToken -
                    rewardDistributor.cumulativeRewardPerLpTokenPerUser(
                        user,
                        token,
                        market
                    ))
            )
            .wadMul(rewardDistributor.computeRewardMultiplier(user, market));
        return newUserRewards;
    }
}
