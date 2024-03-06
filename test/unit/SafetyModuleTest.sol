// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.16;

// contracts
import {Deployment} from "../../lib/increment-protocol/test/helpers/Deployment.MainnetFork.sol";
import {Utils} from "../../lib/increment-protocol/test/helpers/Utils.sol";
import {IncrementToken} from "@increment-governance/IncrementToken.sol";
import {SafetyModule, ISafetyModule} from "../../contracts/SafetyModule.sol";
import {StakedToken, IStakedToken} from "../../contracts/StakedToken.sol";
import {AuctionModule, IAuctionModule} from "../../contracts/AuctionModule.sol";
import {TestSMRewardDistributor, IRewardDistributor} from "../mocks/TestSMRewardDistributor.sol";
import {TestSafetyModule} from "../mocks/TestSafetyModule.sol";
import {EcosystemReserve} from "../../contracts/EcosystemReserve.sol";

// interfaces
import {ERC20PresetFixedSupply, IERC20} from "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetFixedSupply.sol";
import {IBalancerPoolToken, IWeightedPool, IWETH, JoinKind} from "../balancer/IWeightedPool.sol";
import {IWeightedPoolFactory, IAsset, IVault as IBalancerVault} from "../balancer/IWeightedPoolFactory.sol";

// libraries
import {LibMath} from "increment-protocol/lib/LibMath.sol";
import {console2 as console} from "forge/console2.sol";

contract SafetyModuleTest is Deployment, Utils {
    using LibMath for int256;
    using LibMath for uint256;

    event Staked(address indexed from, address indexed onBehalfOf, uint256 amount);

    event Redeemed(address indexed from, address indexed to, uint256 amount);

    event Cooldown(address indexed user);

    event RewardTokenShortfall(address indexed rewardToken, uint256 shortfallAmount);

    event Transfer(address indexed from, address indexed to, uint256 value);

    event Approval(address indexed owner, address indexed spender, uint256 value);

    event LotsSold(uint256 indexed auctionId, address indexed buyer, uint8 numLots, uint256 lotSize, uint128 lotPrice);

    event AuctionCompleted(
        uint256 indexed auctionId,
        uint8 remainingLots,
        uint256 finalLotSize,
        uint256 totalTokensSold,
        uint256 totalFundsRaised
    );

    event AuctionTerminated(
        uint256 indexed auctionId, address stakedToken, address underlyingToken, uint256 underlyingBalanceReturned
    );

    event SlashingSettled();

    event FundsReturned(address indexed from, uint256 amount);

    event ExchangeRateUpdated(uint256 exchangeRate);

    event PaymentTokenChanged(address oldPaymentToken, address newPaymentToken);

    uint88 public constant INITIAL_INFLATION_RATE = 1463753e18;
    uint88 public constant INITIAL_REDUCTION_FACTOR = 1.189207115e18;
    uint256 public constant INITIAL_MAX_MULTIPLIER = 4e18;
    uint256 public constant INITIAL_SMOOTHING_VALUE = 30e18;
    uint256 public constant COOLDOWN_SECONDS = 1 days;
    uint256 public constant UNSTAKE_WINDOW = 10 days;
    uint256 public constant MAX_STAKE_AMOUNT_1 = 1_000_000e18;
    uint256 public constant MAX_STAKE_AMOUNT_2 = 100_000e18;
    uint256 public constant INITIAL_MARKET_WEIGHT_0 = 5000;
    uint256 public constant INITIAL_MARKET_WEIGHT_1 = 5000;

    address public liquidityProviderOne = address(123);
    address public liquidityProviderTwo = address(456);

    IncrementToken public rewardsToken;
    IWETH public weth;
    StakedToken public stakedToken1;
    StakedToken public stakedToken2;

    EcosystemReserve public ecosystemReserve;
    TestSafetyModule public safetyModule;
    AuctionModule public auctionModule;
    TestSMRewardDistributor public rewardDistributor;
    IWeightedPoolFactory public weightedPoolFactory;
    IWeightedPool public balancerPool;
    IBalancerVault public balancerVault;
    bytes32 public poolId;

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
        ecosystemReserve = new EcosystemReserve(address(this));

        // Deploy safety module
        safetyModule = new TestSafetyModule(address(0), address(0));

        // Deploy auction module
        auctionModule = new AuctionModule(ISafetyModule(address(0)), IERC20(address(usdc)));
        auctionModule.setSafetyModule(safetyModule);
        safetyModule.setAuctionModule(auctionModule);

        // Deploy reward distributor
        rewardDistributor = new TestSMRewardDistributor(
            safetyModule, INITIAL_MAX_MULTIPLIER, INITIAL_SMOOTHING_VALUE, address(ecosystemReserve)
        );
        safetyModule.setRewardDistributor(rewardDistributor);

        // Transfer half of the rewards tokens to the reward vault
        rewardsToken.transfer(address(ecosystemReserve), rewardsToken.totalSupply() / 2);
        ecosystemReserve.approve(rewardsToken, address(rewardDistributor), type(uint256).max);

        // Transfer some of the rewards tokens to the liquidity providers
        rewardsToken.transfer(liquidityProviderOne, 10_000 ether);
        rewardsToken.transfer(liquidityProviderTwo, 10_000 ether);

        // Deploy Balancer pool
        weightedPoolFactory = IWeightedPoolFactory(0x897888115Ada5773E02aA29F775430BFB5F34c51);
        weth = IWETH(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
        balancerPool = _deployBalancerPool(address(rewardsToken), address(weth), "50INCR-50WETH");

        // Add initial liquidity to the Balancer pool
        poolId = balancerPool.getPoolId();
        balancerVault = balancerPool.getVault();
        _joinBalancerPoolInit(poolId, 10_000 ether, 10 ether);

        // Deploy staked tokens
        stakedToken1 = new StakedToken(
            rewardsToken, safetyModule, COOLDOWN_SECONDS, UNSTAKE_WINDOW, MAX_STAKE_AMOUNT_1, "Staked INCR", "stINCR"
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
        // Unnecessary, but for test coverage...
        stakedToken1.setSafetyModule(address(safetyModule));
        stakedToken2.setSafetyModule(address(safetyModule));

        // Register staked tokens with safety module
        safetyModule.addStakedToken(stakedToken1);
        safetyModule.addStakedToken(stakedToken2);
        address[] memory stakedTokens = _getMarkets();
        uint256[] memory rewardWeights = new uint256[](2);
        rewardWeights[0] = INITIAL_MARKET_WEIGHT_0;
        rewardWeights[1] = INITIAL_MARKET_WEIGHT_1;
        rewardDistributor.addRewardToken(
            address(rewardsToken), INITIAL_INFLATION_RATE, INITIAL_REDUCTION_FACTOR, stakedTokens, rewardWeights
        );

        // Approve staked tokens and Balancer vault for users
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
        deal(address(weth), liquidityProviderOne, 10 ether);
        deal(address(weth), liquidityProviderTwo, 10 ether);

        // Join Balancer pool as user 1
        _joinBalancerPool(poolId, liquidityProviderOne, 5000 ether, 10 ether);

        // Stake as user 1
        _stake(stakedToken1, liquidityProviderOne, rewardsToken.balanceOf(liquidityProviderOne));
        _stake(stakedToken2, liquidityProviderOne, balancerPool.balanceOf(liquidityProviderOne));
    }

    // solhint-disable-next-line func-name-mixedcase
    function test_Deployment() public {
        assertEq(safetyModule.getStakedTokens().length, 2, "Staked token count mismatch");
        assertEq(safetyModule.getNumStakedTokens(), 2, "Staked token count mismatch");
        assertEq(address(safetyModule.stakedTokens(0)), address(stakedToken1), "Market address mismatch");
        assertEq(safetyModule.getStakedTokenIdx(address(stakedToken2)), 1, "Staked token index mismatch");
        assertEq(stakedToken1.balanceOf(liquidityProviderTwo), 0, "Current position mismatch");
        assertEq(
            rewardDistributor.computeRewardMultiplier(liquidityProviderTwo, address(stakedToken1)),
            0,
            "Reward multiplier mismatch"
        );
        _stake(stakedToken1, liquidityProviderTwo, 100 ether);
        assertEq(stakedToken1.balanceOf(liquidityProviderTwo), 100 ether, "Current position mismatch");
        assertEq(
            rewardDistributor.computeRewardMultiplier(liquidityProviderTwo, address(stakedToken1)),
            1e18,
            "Reward multiplier mismatch"
        );
        assertEq(address(stakedToken1.getUnderlyingToken()), address(rewardsToken), "Underlying token mismatch");
        assertEq(stakedToken1.getCooldownSeconds(), COOLDOWN_SECONDS, "Cooldown seconds mismatch");
        assertEq(stakedToken1.getUnstakeWindowSeconds(), UNSTAKE_WINDOW, "Unstake window mismatch");
        assertEq(auctionModule.getNextAuctionId(), 0, "Next auction ID mismatch");
    }

    /* ******************* */
    /*   Staked Rewards   */
    /* ******************* */

    // solhint-disable-next-line func-name-mixedcase
    function test_RewardMultiplier() public {
        // Test with smoothing value of 30 and max multiplier of 4
        // These values match those in the spreadsheet used to design the SM rewards
        _stake(stakedToken1, liquidityProviderTwo, 100 ether);
        assertEq(
            rewardDistributor.computeRewardMultiplier(liquidityProviderTwo, address(stakedToken1)),
            1e18,
            "Reward multiplier mismatch after initial stake"
        );
        skip(2 days);
        assertEq(
            rewardDistributor.computeRewardMultiplier(liquidityProviderTwo, address(stakedToken1)),
            1.5e18,
            "Reward multiplier mismatch after 2 days"
        );
        // Partially redeeming resets the multiplier to 1
        _redeem(stakedToken1, liquidityProviderTwo, 50 ether);
        assertEq(
            rewardDistributor.computeRewardMultiplier(liquidityProviderTwo, address(stakedToken1)),
            1e18,
            "Reward multiplier mismatch after redeeming half"
        );
        skip(5 days);
        assertEq(
            rewardDistributor.computeRewardMultiplier(liquidityProviderTwo, address(stakedToken1)),
            2e18,
            "Reward multiplier mismatch after 5 days"
        );
        // Staked again pushed the multiplier start time forward by a weighted amount
        // In this case, the multiplier start time is pushed forward by 2.5 days, because
        // it had been 5 days ago, and the user doubled their stake
        _stake(stakedToken1, liquidityProviderTwo, 50 ether);
        assertEq(
            rewardDistributor.computeRewardMultiplier(liquidityProviderTwo, address(stakedToken1)),
            1.6e18,
            "Reward multiplier mismatch after staked again"
        );
        skip(2.5 days);
        assertEq(
            rewardDistributor.computeRewardMultiplier(liquidityProviderTwo, address(stakedToken1)),
            2e18,
            "Reward multiplier mismatch after another 2.5 days"
        );
        // Redeeming completely resets the multiplier to 0
        _redeem(stakedToken1, liquidityProviderTwo, 100 ether);
        assertEq(
            rewardDistributor.computeRewardMultiplier(liquidityProviderTwo, address(stakedToken1)),
            0,
            "Reward multiplier mismatch after redeeming completely"
        );

        // Test with smoothing value of 60, doubling the time it takes to reach the same multiplier
        rewardDistributor.setSmoothingValue(60e18);
        _stake(stakedToken1, liquidityProviderTwo, 100 ether);
        assertEq(
            rewardDistributor.computeRewardMultiplier(liquidityProviderTwo, address(stakedToken1)),
            1e18,
            "Reward multiplier mismatch after staked with new smoothing value"
        );
        skip(4 days);
        assertEq(
            rewardDistributor.computeRewardMultiplier(liquidityProviderTwo, address(stakedToken1)),
            1.5e18,
            "Reward multiplier mismatch after increasing smoothing value"
        );

        // Test with max multiplier of 6, increasing the multiplier by 50%
        rewardDistributor.setMaxRewardMultiplier(6e18);
        assertEq(
            rewardDistributor.computeRewardMultiplier(liquidityProviderTwo, address(stakedToken1)),
            2.25e18,
            "Reward multiplier mismatch after increasing max multiplier"
        );

        // Calling cooldown resets the multiplier to 1
        vm.startPrank(liquidityProviderTwo);
        stakedToken1.cooldown();
        assertEq(
            rewardDistributor.computeRewardMultiplier(liquidityProviderTwo, address(stakedToken1)),
            1e18,
            "Reward multiplier mismatch after cooldown"
        );
    }

    // solhint-disable-next-line func-name-mixedcase
    function testFuzz_MultipliedRewardAccrual(uint256 stakeAmount) public {
        /* bounds */
        stakeAmount = bound(stakeAmount, 100e18, 10_000e18);

        // Stake only with stakedToken1 for this test
        _stake(stakedToken1, liquidityProviderTwo, stakeAmount);

        // Skip some time
        skip(9 days);

        // Get reward preview
        uint256 rewardPreview =
            _viewNewRewardAccrual(address(stakedToken1), liquidityProviderTwo, address(rewardsToken));

        // Get current reward multiplier
        uint256 rewardMultiplier =
            rewardDistributor.computeRewardMultiplier(liquidityProviderTwo, address(stakedToken1));

        // Get accrued rewards
        rewardDistributor.accrueRewards(address(stakedToken1), liquidityProviderTwo);
        uint256 accruedRewards = rewardDistributor.rewardsAccruedByUser(liquidityProviderTwo, address(rewardsToken));

        // Check that accrued rewards are equal to reward preview
        assertEq(accruedRewards, rewardPreview, "Accrued rewards preview mismatch");

        // Check that accrued rewards equal stake amount times cumulative reward per token times reward multiplier
        uint256 cumulativeRewardsPerLpToken =
            rewardDistributor.cumulativeRewardPerLpToken(address(rewardsToken), address(stakedToken1));
        assertEq(
            accruedRewards,
            stakeAmount.wadMul(cumulativeRewardsPerLpToken).wadMul(rewardMultiplier),
            "Accrued rewards mismatch"
        );

        // Start cooldown period (accrues rewards)
        vm.startPrank(liquidityProviderTwo);
        stakedToken1.cooldown();

        // Skip cooldown period
        skip(1 days);

        // Add to reward preview
        rewardPreview += _viewNewRewardAccrual(address(stakedToken1), liquidityProviderTwo, address(rewardsToken));

        // Redeem stakedToken1
        stakedToken1.redeemTo(liquidityProviderTwo, stakeAmount);

        // Get new accrued rewards
        accruedRewards = rewardDistributor.rewardsAccruedByUser(liquidityProviderTwo, address(rewardsToken));

        // Check that accrued rewards are equal to reward preview
        assertEq(accruedRewards, rewardPreview, "Accrued rewards preview mismatch");

        // Check that rewards are not accrued after full redeem
        skip(10 days);
        rewardDistributor.accrueRewards(address(stakedToken1), liquidityProviderTwo);
        assertEq(
            rewardDistributor.rewardsAccruedByUser(liquidityProviderTwo, address(rewardsToken)),
            accruedRewards,
            "Accrued more rewards after full redeem"
        );
    }

    // solhint-disable-next-line func-name-mixedcase
    function testFuzz_PreExistingBalances(uint256 maxTokenAmountIntoBalancer) public {
        // liquidityProvider2 starts with 10,000 INCR and 10 WETH
        maxTokenAmountIntoBalancer = bound(maxTokenAmountIntoBalancer, 100e18, 9_000e18);

        // join balancer pool as liquidityProvider2
        _joinBalancerPool(poolId, liquidityProviderTwo, maxTokenAmountIntoBalancer, maxTokenAmountIntoBalancer / 1000);

        // stake as liquidityProvider2
        _stake(stakedToken1, liquidityProviderTwo, rewardsToken.balanceOf(liquidityProviderTwo));
        _stake(stakedToken2, liquidityProviderTwo, balancerPool.balanceOf(liquidityProviderTwo));

        // redeploy reward distributor so it doesn't know of pre-existing balances
        TestSMRewardDistributor newRewardDistributor = new TestSMRewardDistributor(
            ISafetyModule(address(0)), INITIAL_MAX_MULTIPLIER, INITIAL_SMOOTHING_VALUE, address(ecosystemReserve)
        );
        safetyModule.setRewardDistributor(newRewardDistributor);
        newRewardDistributor.setSafetyModule(safetyModule);
        ecosystemReserve.approve(rewardsToken, address(newRewardDistributor), type(uint256).max);

        // add reward token to new reward distributor
        address[] memory stakedTokens = _getMarkets();
        uint256[] memory rewardWeights = _getRewardWeights(rewardDistributor, address(rewardsToken));
        newRewardDistributor.addRewardToken(
            address(rewardsToken), INITIAL_INFLATION_RATE, INITIAL_REDUCTION_FACTOR, stakedTokens, rewardWeights
        );

        // skip some time
        skip(10 days);

        // register user positions
        vm.startPrank(liquidityProviderOne);
        newRewardDistributor.registerPositions(stakedTokens);
        vm.startPrank(liquidityProviderTwo);
        newRewardDistributor.registerPositions(stakedTokens);
        vm.stopPrank();

        // skip some more time
        skip(10 days);

        // store initial state before accruing rewards
        uint256[] memory balances = _getUserBalances(liquidityProviderTwo);
        uint256[] memory prevCumRewards = _getCumulativeRewardsByToken(newRewardDistributor, address(rewardsToken));
        uint256[] memory prevTotalLiquidity = _getTotalLiquidityPerMarket(newRewardDistributor);
        uint256[] memory skipTimes = _getSkipTimes(newRewardDistributor);
        uint256[] memory multipliers = _getRewardMultipliers(newRewardDistributor, liquidityProviderTwo);

        // check that the user only accrues rewards for the 10 days since registering
        newRewardDistributor.accrueRewards(liquidityProviderTwo);
        _checkRewards(
            newRewardDistributor,
            address(rewardsToken),
            liquidityProviderTwo,
            multipliers,
            skipTimes,
            balances,
            prevCumRewards,
            prevTotalLiquidity,
            0
        );

        // redeem all staked tokens and claim rewards (for gas measurement)
        _claimAndRedeemAll(_getStakedTokens(), newRewardDistributor, liquidityProviderTwo);
    }

    // solhint-disable-next-line func-name-mixedcase
    function testFuzz_RewardTokenShortfall(uint256 stakeAmount) public {
        /* bounds */
        stakeAmount = bound(stakeAmount, 100e18, 10_000e18);

        // Stake only with stakedToken1 for this test
        _stake(stakedToken1, liquidityProviderTwo, stakeAmount);

        // Remove all reward tokens from EcosystemReserve
        uint256 rewardBalance = rewardsToken.balanceOf(address(ecosystemReserve));
        ecosystemReserve.transfer(rewardsToken, address(this), rewardBalance);

        // Skip some time
        skip(10 days);

        // Get reward preview
        uint256 rewardPreview =
            _viewNewRewardAccrual(address(stakedToken1), liquidityProviderTwo, address(rewardsToken));

        // Accrue rewards, expecting RewardTokenShortfall event
        vm.expectEmit(false, false, false, true);
        emit RewardTokenShortfall(address(rewardsToken), rewardPreview);
        rewardDistributor.accrueRewards(address(stakedToken1), liquidityProviderTwo);

        // Skip some more time
        skip(9 days);

        // Get second reward preview
        uint256 rewardPreview2 =
            _viewNewRewardAccrual(address(stakedToken1), liquidityProviderTwo, address(rewardsToken));

        // Start cooldown period (accrues rewards)
        vm.startPrank(liquidityProviderTwo);
        stakedToken1.cooldown();

        // Skip cooldown period
        skip(1 days);

        // Get third reward preview
        uint256 rewardPreview3 =
            _viewNewRewardAccrual(address(stakedToken1), liquidityProviderTwo, address(rewardsToken));

        // Redeem stakedToken1, expecting RewardTokenShortfall event
        vm.expectEmit(false, false, false, true);
        emit RewardTokenShortfall(address(rewardsToken), rewardPreview + rewardPreview2 + rewardPreview3);
        stakedToken1.redeemTo(liquidityProviderTwo, stakeAmount);

        // Try to claim reward tokens, expecting RewardTokenShortfall event
        vm.startPrank(liquidityProviderTwo);
        vm.expectEmit(false, false, false, true);
        emit RewardTokenShortfall(address(rewardsToken), rewardPreview + rewardPreview2 + rewardPreview3);
        rewardDistributor.claimRewards();
        assertEq(rewardsToken.balanceOf(liquidityProviderTwo), 10_000e18, "Claimed rewards after shortfall");

        // Transfer reward tokens back to the EcosystemReserve
        vm.stopPrank();
        rewardsToken.transfer(address(ecosystemReserve), rewardBalance);

        // Claim tokens and check that the accrued rewards were distributed
        vm.startPrank(liquidityProviderTwo);
        rewardDistributor.claimRewards();
        assertEq(
            rewardsToken.balanceOf(liquidityProviderTwo),
            10_000e18 + rewardPreview + rewardPreview2 + rewardPreview3,
            "Incorrect rewards after resolving shortfall"
        );
    }

    // solhint-disable-next-line func-name-mixedcase
    function test_StakedTokenZeroLiquidity() public {
        // Deploy a third staked token
        StakedToken stakedToken3 = new StakedToken(
            rewardsToken, safetyModule, COOLDOWN_SECONDS, UNSTAKE_WINDOW, MAX_STAKE_AMOUNT_1, "Staked INCR 2", "stINCR2"
        );

        // Add the third staked token to the safety module
        safetyModule.addStakedToken(stakedToken3);

        // Update the reward weights
        address[] memory stakedTokens = _getMarkets();
        uint256[] memory rewardWeights = new uint256[](3);
        rewardWeights[0] = 3333;
        rewardWeights[1] = 3334;
        rewardWeights[2] = 3333;
        rewardDistributor.updateRewardWeights(address(rewardsToken), stakedTokens, rewardWeights);

        // Check that stakedToken3 was added to the list of markets for rewards
        assertEq(
            rewardDistributor.getRewardMarkets(address(rewardsToken))[2],
            address(stakedToken3),
            "Reward token missing for new staked token"
        );

        // Skip some time
        skip(10 days);

        // Get reward preview, expecting it to be 0
        uint256 rewardPreview =
            _viewNewRewardAccrual(address(stakedToken3), liquidityProviderTwo, address(rewardsToken));
        assertEq(rewardPreview, 0, "Reward preview should be 0");

        // Accrue rewards, expecting it to accrue 0 rewards
        rewardDistributor.accrueRewards(address(stakedToken3), liquidityProviderTwo);
        assertEq(
            rewardDistributor.rewardsAccruedByUser(liquidityProviderTwo, address(rewardsToken)),
            0,
            "Rewards should be 0"
        );
    }

    // solhint-disable-next-line func-name-mixedcase
    function testFuzz_StakedTokenTransfer(uint256 stakeAmount) public {
        /* bounds */
        stakeAmount = bound(stakeAmount, 100e18, 10_000e18);

        // Stake only with stakedToken1 for this test
        _stake(stakedToken1, liquidityProviderTwo, stakeAmount);

        // Skip some time
        skip(5 days);

        // store initial state before accruing rewards
        uint256[] memory balances1 = _getUserBalances(liquidityProviderOne);
        uint256[] memory balances2 = _getUserBalances(liquidityProviderTwo);
        uint256[] memory multipliers1 = _getRewardMultipliers(rewardDistributor, liquidityProviderOne);
        uint256[] memory multipliers2 = _getRewardMultipliers(rewardDistributor, liquidityProviderTwo);
        uint256[] memory prevCumRewards = _getCumulativeRewardsByToken(rewardDistributor, address(rewardsToken));
        uint256[] memory prevTotalLiquidity = _getTotalLiquidityPerMarket(rewardDistributor);
        uint256[] memory skipTimes = _getSkipTimes(rewardDistributor);
        skipTimes[1] = 0; // Ignore stakedToken2

        // After 5 days, both users should have 2x multiplier (given smoothing value of 30 and max multiplier of 4)
        assertEq(multipliers1[0], 2e18, "Reward multiplier mismatch: user 1");
        assertEq(multipliers2[0], 2e18, "Reward multiplier mismatch: user 2");

        // Transfer all of user 1's stakedToken1 to user 2, accruing rewards for both users
        vm.startPrank(liquidityProviderOne);
        stakedToken1.cooldown(); // Start cooldown period for the sake of test coverage
        stakedToken1.transfer(liquidityProviderTwo, balances1[0]);
        vm.stopPrank();

        // Check that user 1 accrued rewards according to their initial balance and multiplier,
        // while user 2 has not accrued rewards yet since they already had a staking position
        _checkRewards(
            address(rewardsToken),
            liquidityProviderOne,
            multipliers1,
            skipTimes,
            balances1,
            prevCumRewards,
            prevTotalLiquidity,
            0
        );
        assertEq(
            rewardDistributor.rewardsAccruedByUser(liquidityProviderTwo, address(rewardsToken)),
            0,
            "Rewards should be 0: user 2"
        );
        // Accrue and check rewards for user 2
        rewardDistributor.accrueRewards(address(stakedToken1), liquidityProviderTwo);
        _checkRewards(
            address(rewardsToken),
            liquidityProviderTwo,
            multipliers2,
            skipTimes,
            balances2,
            prevCumRewards,
            prevTotalLiquidity,
            0
        );

        // Check that user 1's multiplier is now 0, while user 2's is scaled according to the increase in stake
        assertEq(
            rewardDistributor.computeRewardMultiplier(liquidityProviderOne, address(stakedToken1)),
            0,
            "Reward multiplier mismatch after transfer: user 1"
        );
        // Increase ratio is (newPosition - oldPosition) / newPosition, and is used to adjust the multiplier
        // see the note in SMRewardDistributor.sol:updatePosition
        uint256 increaseRatio = balances1[0].wadDiv(balances1[0] + balances2[0]);
        uint256 newMultiplierStartTime =
            _checkMultiplierAdjustment(address(stakedToken1), liquidityProviderTwo, increaseRatio, 5 days);

        // Claim rewards for both users
        vm.startPrank(liquidityProviderOne);
        rewardDistributor.claimRewards();
        vm.startPrank(liquidityProviderTwo);
        rewardDistributor.claimRewards();
        vm.stopPrank();

        // Skip some more time
        skip(10 days - (block.timestamp - newMultiplierStartTime));

        // update stored state before accruing rewards
        balances1 = _getUserBalances(liquidityProviderOne);
        balances2 = _getUserBalances(liquidityProviderTwo);
        multipliers1 = _getRewardMultipliers(rewardDistributor, liquidityProviderOne);
        multipliers2 = _getRewardMultipliers(rewardDistributor, liquidityProviderTwo);
        prevCumRewards = _getCumulativeRewardsByToken(rewardDistributor, address(rewardsToken));
        prevTotalLiquidity = _getTotalLiquidityPerMarket(rewardDistributor);
        skipTimes = _getSkipTimes(rewardDistributor);
        skipTimes[1] = 0; // Ignore stakedToken2

        // 10 days after the new multiplier start time, user 2's multiplier should be 2.5
        assertEq(multipliers1[0], 0, "Reward multiplier mismatch after 10 days: user 1");
        assertEq(multipliers2[0], 2.5e18, "Reward multiplier mismatch after 10 days: user 2");

        // Check that user 2 accrues rewards according to their new balance and multiplier, while user 1 accrues no rewards
        rewardDistributor.accrueRewards(address(stakedToken1), liquidityProviderOne);
        rewardDistributor.accrueRewards(address(stakedToken1), liquidityProviderTwo);
        assertEq(
            rewardDistributor.rewardsAccruedByUser(liquidityProviderOne, address(rewardsToken)),
            0,
            "Rewards should be 0: user 1"
        );
        _checkRewards(
            address(rewardsToken),
            liquidityProviderTwo,
            multipliers2,
            skipTimes,
            balances2,
            prevCumRewards,
            prevTotalLiquidity,
            0
        );

        // redeem all staked tokens and claim rewards (for gas measurement)
        _claimAndRedeemAll(_getStakedTokens(), rewardDistributor, liquidityProviderTwo);
    }

    // solhint-disable-next-line func-name-mixedcase
    function testFuzz_PausingAccrual(uint256 stakeAmount1, uint256 stakeAmount2) public {
        /* bounds */
        stakeAmount1 = bound(stakeAmount1, 100e18, 10_000e18);
        stakeAmount2 = bound(stakeAmount2, 100e18, 10_000e18);

        // stake
        deal(address(rewardsToken), liquidityProviderTwo, stakeAmount1);
        deal(address(balancerPool), liquidityProviderTwo, stakeAmount2);
        _stake(stakedToken1, liquidityProviderTwo, stakeAmount1);
        _stake(stakedToken2, liquidityProviderTwo, stakeAmount2);

        // pause accrual
        vm.startPrank(address(this));
        rewardDistributor.togglePausedReward(address(rewardsToken));
        assertTrue(rewardDistributor.isTokenPaused(address(rewardsToken)), "Rewards not paused");

        // skip some time
        skip(10 days);

        // unpause accrual
        rewardDistributor.togglePausedReward(address(rewardsToken));
        assertTrue(!rewardDistributor.isTokenPaused(address(rewardsToken)), "Rewards not unpaused");

        // skip some more time
        skip(10 days);

        // store initial state before accruing rewards
        uint256[] memory multipliers = _getRewardMultipliers(rewardDistributor, liquidityProviderTwo);
        uint256[] memory balances = _getUserBalances(liquidityProviderTwo);
        uint256[] memory prevCumRewards = _getCumulativeRewardsByToken(rewardDistributor, address(rewardsToken));
        uint256[] memory prevTotalLiquidity = _getTotalLiquidityPerMarket(rewardDistributor);
        uint256[] memory skipTimes = new uint256[](2);
        skipTimes[0] = 10 days;
        skipTimes[1] = 10 days;

        // check that rewards are accrued for only the 10 days after unpausing
        rewardDistributor.accrueRewards(liquidityProviderTwo);
        _checkRewards(
            address(rewardsToken),
            liquidityProviderTwo,
            multipliers,
            skipTimes,
            balances,
            prevCumRewards,
            prevTotalLiquidity,
            0
        );
    }

    // solhint-disable-next-line func-name-mixedcase
    function testFuzz_NextCooldownTimestamp(uint256 stakeAmount) public {
        /* bounds */
        stakeAmount = bound(stakeAmount, 100e18, 10_000e18);

        /**
         * StakedToken.getNextCooldownTimestamp(fromCooldownTimestamp, amountToReceive, toAddress, toBalance)
         * is from Aave's original StakedToken, and has the following notes:
         *
         * Calculation depends on the sender/receiver situation, as follows:
         *  - If the timestamp of the sender is "better" or the timestamp of the recipient is 0,
         *    we take the one of the recipient
         *  - Weighted average of from/to cooldown timestamps if:
         *    - The sender doesn't have the cooldown activated (timestamp 0).
         *    - The sender timestamp is expired
         *    - The sender has a "worse" timestamp
         *  - If the receiver's cooldown timestamp expired (too old), the next is 0
         */

        // Define initial arguments
        uint256 fromCooldownTimestamp = stakedToken1.getCooldownStartTime(liquidityProviderOne);
        uint256 amountToReceive = 100e18;
        address toAddress = liquidityProviderOne;
        uint256 toBalance = stakedToken1.balanceOf(liquidityProviderOne);

        // When user first stakes, next cooldown timestamp should be 0 (user 1 staked 10,000 INCR in setUp())
        assertEq(
            stakedToken1.getNextCooldownTimestamp(fromCooldownTimestamp, amountToReceive, toAddress, toBalance),
            0,
            "Next cooldown timestamp should be 0 after first staked"
        );

        // Activate cooldown period, so stakersCooldowns[liquidityProviderOne] is set to block.timestamp
        vm.startPrank(liquidityProviderOne);
        stakedToken1.cooldown();
        vm.stopPrank();
        fromCooldownTimestamp = stakedToken1.getCooldownStartTime(liquidityProviderOne);
        assertEq(fromCooldownTimestamp, block.timestamp, "Cooldown timestamp mismatch");

        // Wait for cooldown period and unstake window to pass
        skip(COOLDOWN_SECONDS + UNSTAKE_WINDOW + 1 days);

        // When recipient's cooldown timestamp is less than minimal valid timestamp, next timestamp should be 0
        // minimalValidCooldownTimestamp = block.timestamp - COOLDOWN_SECONDS - UNSTAKE_WINDOW
        assertEq(
            stakedToken1.getNextCooldownTimestamp(fromCooldownTimestamp, amountToReceive, toAddress, toBalance),
            0,
            "Next cooldown timestamp should be 0 when cooldown timestamp is less than minimal valid timestamp"
        );

        // To test with different from and to addresses, stake with user 2
        _stake(stakedToken1, liquidityProviderTwo, stakeAmount);
        toAddress = liquidityProviderTwo;
        toBalance = stakedToken1.balanceOf(liquidityProviderTwo);

        // Reset user 1 cooldown timestamp
        vm.startPrank(liquidityProviderOne);
        stakedToken1.cooldown();
        vm.stopPrank();
        fromCooldownTimestamp = stakedToken1.getCooldownStartTime(liquidityProviderOne);

        // Skip user 1 cooldown period
        skip(COOLDOWN_SECONDS);

        // Activate user 2 cooldown period
        vm.startPrank(liquidityProviderTwo);
        stakedToken1.cooldown();
        vm.stopPrank();
        uint256 toCooldownTimestamp = stakedToken1.getCooldownStartTime(liquidityProviderTwo);

        // If user 1's cooldown timestamp is less than user 2's, next cooldown timestamp should be user 2's
        assertEq(
            stakedToken1.getNextCooldownTimestamp(fromCooldownTimestamp, amountToReceive, toAddress, toBalance),
            toCooldownTimestamp,
            "Next cooldown timestamp should be user 2's when user 1's cooldown timestamp is less than user 2's"
        );

        // Reset user 1 cooldown timestamp
        vm.startPrank(liquidityProviderOne);
        stakedToken1.cooldown();
        vm.stopPrank();
        fromCooldownTimestamp = stakedToken1.getCooldownStartTime(liquidityProviderOne);

        // If sender's cooldown timestamp is greater than or equal to recipient's,
        // recipient's next timestamp should be weighted average of from and to timestamps
        uint256 expectedWeightedAverage =
            _calcWeightedAverageCooldown(fromCooldownTimestamp, toCooldownTimestamp, amountToReceive, toBalance);
        assertEq(
            stakedToken1.getNextCooldownTimestamp(fromCooldownTimestamp, amountToReceive, toAddress, toBalance),
            expectedWeightedAverage,
            "Next cooldown timestamp should be weighted average when user 1's cooldown timestamp is greater than or equal to user 2's"
        );

        // Skip user 1 cooldown period and unstake window
        skip(COOLDOWN_SECONDS + UNSTAKE_WINDOW + 1 days);

        // Reset user 2 cooldown period
        vm.startPrank(liquidityProviderTwo);
        stakedToken1.cooldown();
        vm.stopPrank();
        toCooldownTimestamp = stakedToken1.getCooldownStartTime(liquidityProviderTwo);

        // Skip user 2 cooldown period
        skip(COOLDOWN_SECONDS);

        // If fromCooldownTimestamp is less than minimal valid timestamp, block.timestamp should be used
        expectedWeightedAverage =
            _calcWeightedAverageCooldown(block.timestamp, toCooldownTimestamp, amountToReceive, toBalance);
        assertEq(
            stakedToken1.getNextCooldownTimestamp(fromCooldownTimestamp, amountToReceive, toAddress, toBalance),
            expectedWeightedAverage,
            "block.timestamp should be used for fromCooldownTimestamp when computing weighted average after cooldown period and unstake window have passed"
        );

        // Transfer stake from user 1 to user 2 and check that user 2's cooldown timestamp is updated as expected
        vm.startPrank(liquidityProviderOne);
        stakedToken1.transfer(liquidityProviderTwo, amountToReceive);
        vm.stopPrank();
        assertEq(
            stakedToken1.getCooldownStartTime(liquidityProviderTwo),
            expectedWeightedAverage,
            "Cooldown timestamp mismatch after transfer"
        );
    }

    /* ******************* */
    /*  Slashing/Auctions  */
    /* ******************* */

    // solhint-disable-next-line func-name-mixedcase
    function testFuzz_StakedTokenExchangeRate(uint256 donatePercent, uint256 slashPercent, uint256 stakeAmount)
        public
    {
        /* bounds */
        donatePercent = bound(donatePercent, 1e16, 1e18);
        slashPercent = bound(slashPercent, 1e16, 1e18);
        stakeAmount = bound(stakeAmount, 100e18, 10_000e18);

        // Check initial conditions
        uint256 initialSupply = stakedToken1.totalSupply();
        assertEq(initialSupply, rewardsToken.balanceOf(address(stakedToken1)), "Initial supply mismatch");
        _checkExchangeRatePreviews(stakedToken1, stakeAmount, 1e18, "initially");

        // Get amounts from percents
        uint256 donateAmount = initialSupply.wadMul(donatePercent);
        uint256 slashAmount = initialSupply.wadMul(slashPercent);

        // Donate some tokens to the staked token and check the resulting exchange rate
        rewardsToken.approve(address(stakedToken1), donateAmount);
        safetyModule.returnFunds(address(stakedToken1), address(this), donateAmount);
        _checkExchangeRatePreviews(stakedToken1, stakeAmount, 1e18 + donatePercent, "after donating");

        // Slash the donated tokens and check the resulting exchange rate
        vm.startPrank(address(safetyModule));
        uint256 slashedDonation = stakedToken1.slash(address(this), stakedToken1.previewStake(donateAmount));
        assertApproxEqAbs(
            slashedDonation,
            donateAmount,
            10, // 10 wei tolerance for rounding error
            "Slashed donation mismatch"
        );
        _checkExchangeRatePreviews(stakedToken1, stakeAmount, 1e18, "after donating then slashing the same amount");
        stakedToken1.settleSlashing();

        // Slash some more tokens and check the resulting exchange rate
        uint256 slashedAmount = stakedToken1.slash(address(this), slashAmount);
        vm.stopPrank();
        assertApproxEqAbs(
            slashedAmount,
            slashAmount,
            10, // 10 wei tolerance for rounding error
            "Slashed amount mismatch"
        );
        _checkExchangeRatePreviews(stakedToken1, stakeAmount, 1e18 - slashPercent, "after slashing");

        // Return the slashed tokens to the staked token and check the resulting exchange rate
        rewardsToken.approve(address(stakedToken1), slashedAmount);
        safetyModule.returnFunds(address(stakedToken1), address(this), slashedAmount);
        _checkExchangeRatePreviews(stakedToken1, stakeAmount, 1e18, "after returning the slashed amount");
    }

    // solhint-disable-next-line func-name-mixedcase
    function testFuzz_AuctionSoldOut(
        uint8 numLots,
        uint128 lotPrice,
        uint128 initialLotSize,
        uint64 slashPercent,
        uint16 lotIncreasePeriod,
        uint32 timeLimit
    ) public {
        /* bounds */
        numLots = uint8(bound(numLots, 2, 10));
        lotPrice = uint128(bound(lotPrice, 1e8, 1e12)); // denominated in USDC w/ 6 decimals
        slashPercent = uint64(bound(slashPercent, 1e16, 0.99e18));
        // lotSize x numLots should not exceed auctionable balance
        uint256 auctionableBalance = stakedToken1.totalSupply().wadMul(slashPercent);
        initialLotSize = uint128(bound(initialLotSize, 1e18, auctionableBalance / numLots));
        uint96 lotIncreaseIncrement = uint96(bound(initialLotSize / 50, 2e16, type(uint96).max));
        lotIncreasePeriod = uint16(bound(lotIncreasePeriod, 1 hours, 18 hours));
        timeLimit = uint32(bound(timeLimit, 5 days, 30 days));

        // Start an auction and check that it was created correctly
        uint256 auctionId = _startAndCheckAuction(
            stakedToken1,
            numLots,
            lotPrice,
            initialLotSize,
            slashPercent,
            lotIncreaseIncrement,
            lotIncreasePeriod,
            timeLimit
        );

        // Buy all the lots at once and check the buyer's resulting balance
        uint256 balanceBefore = stakedToken1.getUnderlyingToken().balanceOf(liquidityProviderTwo);
        _dealAndBuyLots(liquidityProviderTwo, auctionId, numLots, lotPrice);
        uint256 balanceAfter = stakedToken1.getUnderlyingToken().balanceOf(liquidityProviderTwo);
        assertEq(balanceAfter, balanceBefore + initialLotSize * numLots, "Balance mismatch after buying all lots");

        // Check that the auction is no longer active and unsold tokens have been returned
        assertTrue(!auctionModule.isAuctionActive(auctionId), "Auction should not be active after selling out");
        assertEq(_getAuctionRemainingBalance(auctionId), 0, "Unsold tokens should be returned from the auction module");

        // Check the state of the StakedToken after slashing is settled and unsold tokens are returned
        assertTrue(
            !stakedToken1.isInPostSlashingState(), "Staked token should not be in post slashing state after selling out"
        );
        uint256 percentSold = uint256(initialLotSize * numLots).wadDiv(stakedToken1.totalSupply());
        _checkExchangeRatePreviews(stakedToken1, 1e18, 1e18 - percentSold, "after selling out");

        // Withdraw the funds raised from the auction and check the resulting balance
        uint256 fundsRaised = auctionModule.getFundsRaised(auctionId);
        assertEq(fundsRaised, lotPrice * numLots, "Funds raised mismatch after selling out");
        assertEq(
            usdc.balanceOf(address(safetyModule)),
            fundsRaised,
            "Safety module should have the funds raised before withdrawing"
        );
        safetyModule.withdrawFundsRaisedFromAuction(fundsRaised);
        assertEq(
            usdc.balanceOf(address(this)), fundsRaised, "Balance mismatch after withdrawing funds raised from auction"
        );
        assertEq(
            usdc.balanceOf(address(safetyModule)), 0, "Safety module should have no remaining funds after withdrawing"
        );
    }

    // solhint-disable-next-line func-name-mixedcase
    function testFuzz_AuctionTimeOut(
        uint8 numLots,
        uint128 lotPrice,
        uint128 initialLotSize,
        uint64 slashPercent,
        uint16 lotIncreasePeriod,
        uint32 timeLimit
    ) public {
        /* bounds */
        numLots = uint8(bound(numLots, 2, 10));
        lotPrice = uint128(bound(lotPrice, 1e18, 1e22)); // denominated in UA w/ 18 decimals
        slashPercent = uint64(bound(slashPercent, 1e16, 0.99e18));
        // initialLotSize x numLots should not exceed auctionable balance
        uint256 auctionableBalance = stakedToken1.totalSupply().wadMul(slashPercent);
        initialLotSize = uint128(bound(initialLotSize, 1e18, auctionableBalance / numLots));
        uint96 lotIncreaseIncrement = uint96(bound(initialLotSize / 50, 2e16, type(uint96).max));
        lotIncreasePeriod = uint16(bound(lotIncreasePeriod, 1 hours, 18 hours));
        timeLimit = uint32(bound(timeLimit, 5 days, 30 days));

        // Change the payment token to UA
        vm.expectEmit(false, false, false, true);
        emit PaymentTokenChanged(address(usdc), address(ua));
        auctionModule.setPaymentToken(IERC20(address(ua)));

        // Start an auction and check the end time
        uint256 auctionId = _startAndCheckAuction(
            stakedToken1,
            numLots,
            lotPrice,
            initialLotSize,
            slashPercent,
            lotIncreaseIncrement,
            lotIncreasePeriod,
            timeLimit
        );

        // Skip one day at a time until the end of the auction without buying any lots,
        // checking that the currentLotSize x numLots does not exceed auctionable balance
        uint256 numDays = timeLimit / 1 days;
        for (uint256 i; i < numDays; i++) {
            skip(1 days);
            uint256 currentLotSize = auctionModule.getCurrentLotSize(auctionId);
            assertLe(
                currentLotSize * numLots,
                auctionableBalance,
                "Current lot size x num lots should not exceed auctionable balance"
            );
        }
        if (block.timestamp < auctionModule.getEndTime(auctionId)) {
            skip(auctionModule.getEndTime(auctionId) - block.timestamp);
        }

        // Check that the auction is no longer active and trying to buy lots fails
        assertTrue(!auctionModule.isAuctionActive(auctionId), "Auction should not be active after timing out");
        _expectAuctionNotActive(auctionId);
        auctionModule.buyLots(auctionId, 1);

        // Complete the auction and check that all tokens were returned
        vm.startPrank(liquidityProviderOne); // Anyone can complete the auction after it times out
        uint256 finalLotSize = uint256(initialLotSize) + lotIncreaseIncrement * (timeLimit / lotIncreasePeriod);
        if (finalLotSize > auctionableBalance / numLots) {
            finalLotSize = auctionableBalance / numLots;
        }
        vm.expectEmit(false, false, false, true);
        emit Approval(address(auctionModule), address(stakedToken1), auctionableBalance);
        vm.expectEmit(false, false, false, true);
        emit AuctionCompleted(auctionId, numLots, finalLotSize, 0, 0);
        auctionModule.completeAuction(auctionId);
        assertEq(_getAuctionRemainingBalance(auctionId), 0, "Unsold tokens should be returned from the auction module");
        assertEq(stakedToken1.exchangeRate(), 1e18, "Exchange rate mismatch after returning unsold tokens");
    }

    // solhint-disable-next-line func-name-mixedcase
    function testFuzz_TerminateAuctionEarly(
        uint8 numLots,
        uint128 lotPrice,
        uint128 initialLotSize,
        uint64 slashPercent,
        uint16 lotIncreasePeriod,
        uint32 timeLimit
    ) public {
        /* bounds */
        numLots = uint8(bound(numLots, 2, 10));
        lotPrice = uint128(bound(lotPrice, 1e8, 1e12)); // denominated in USDC w/ 6 decimals
        slashPercent = uint64(bound(slashPercent, 1e16, 0.99e18));
        // lotSize x numLots should not exceed auctionable balance
        uint256 auctionableBalance = stakedToken1.totalSupply().wadMul(slashPercent);
        initialLotSize = uint128(bound(initialLotSize, 1e18, auctionableBalance / numLots));
        uint96 lotIncreaseIncrement = uint96(bound(initialLotSize / 50, 2e16, type(uint96).max));
        lotIncreasePeriod = uint16(bound(lotIncreasePeriod, 1 hours, 18 hours));
        timeLimit = uint32(bound(timeLimit, 5 days, 30 days));

        // Start an auction and check that it was created correctly
        uint256 auctionId = _startAndCheckAuction(
            stakedToken1,
            numLots,
            lotPrice,
            initialLotSize,
            slashPercent,
            lotIncreaseIncrement,
            lotIncreasePeriod,
            timeLimit
        );

        // Terminate the auction early and check events
        vm.expectEmit(false, false, false, true);
        emit Approval(address(auctionModule), address(stakedToken1), auctionableBalance);
        vm.expectEmit(false, false, false, true);
        emit AuctionCompleted(auctionId, numLots, initialLotSize, 0, 0);
        vm.expectEmit(false, false, false, true);
        emit ExchangeRateUpdated(1e18);
        vm.expectEmit(false, false, false, true);
        emit FundsReturned(address(auctionModule), auctionableBalance);
        vm.expectEmit(false, false, false, true);
        emit SlashingSettled();
        vm.expectEmit(false, false, false, true);
        emit AuctionTerminated(auctionId, address(stakedToken1), address(rewardsToken), auctionableBalance);
        safetyModule.terminateAuction(auctionId);

        // Check that the auction is no longer active and unsold tokens have been returned
        assertTrue(!auctionModule.isAuctionActive(auctionId), "Auction should not be active after terminating early");
        assertEq(_getAuctionRemainingBalance(auctionId), 0, "Unsold tokens should be returned from the auction module");
        assertEq(stakedToken1.exchangeRate(), 1e18, "Exchange rate mismatch after returning unsold tokens");
        assertTrue(
            !stakedToken1.isInPostSlashingState(),
            "Staked token should not be in post slashing state after terminating the auction"
        );

        // Check that trying to buy lots or complete the terminated auction fails
        vm.startPrank(liquidityProviderOne);
        _expectAuctionNotActive(auctionId);
        auctionModule.buyLots(auctionId, 1);
        _expectAuctionNotActive(auctionId);
        auctionModule.completeAuction(auctionId);
        vm.stopPrank();
    }

    // solhint-disable-next-line func-name-mixedcase
    function testFuzz_RedeemAllDuringAuction(
        uint8 numLots,
        uint128 lotPrice,
        uint128 initialLotSize,
        uint64 slashPercent,
        uint16 lotIncreasePeriod,
        uint32 timeLimit
    ) public {
        /* bounds */
        numLots = uint8(bound(numLots, 2, 10));
        lotPrice = uint128(bound(lotPrice, 1e8, 1e12)); // denominated in USDC w/ 6 decimals
        slashPercent = uint64(bound(slashPercent, 1e16, 0.99e18));
        // lotSize x numLots should not exceed auctionable balance
        uint256 auctionableBalance = stakedToken1.totalSupply().wadMul(slashPercent);
        initialLotSize = uint128(bound(initialLotSize, 1e18, auctionableBalance / numLots));
        uint96 lotIncreaseIncrement = uint96(bound(initialLotSize / 50, 2e16, type(uint96).max));
        lotIncreasePeriod = uint16(bound(lotIncreasePeriod, 1 hours, 18 hours));
        timeLimit = uint32(bound(timeLimit, 5 days, 30 days));

        // Start an auction and check that it was created correctly
        uint256 auctionId = _startAndCheckAuction(
            stakedToken1,
            numLots,
            lotPrice,
            initialLotSize,
            slashPercent,
            lotIncreaseIncrement,
            lotIncreasePeriod,
            timeLimit
        );

        // User 1 (the only staker) redeems during the auction at the lowered exchange rate
        uint256 balanceBefore = stakedToken1.getUnderlyingToken().balanceOf(liquidityProviderOne);
        uint256 exchangeRate = stakedToken1.exchangeRate();
        uint256 expectedBalance = balanceBefore + stakedToken1.totalSupply().wadMul(exchangeRate);
        _redeem(stakedToken1, liquidityProviderOne, stakedToken1.totalSupply());
        uint256 balanceAfter = stakedToken1.getUnderlyingToken().balanceOf(liquidityProviderOne);
        assertEq(balanceAfter, expectedBalance, "User balance mismatch after redeeming during the auction");
        assertEq(stakedToken1.totalSupply(), 0, "Total supply should be 0 after redeeming");
        assertEq(stakedToken1.exchangeRate(), 1e18, "Exchange rate should be reset after last staker redeems");

        // Terminate the auction early and check that funds are returned to governance
        balanceBefore = stakedToken1.getUnderlyingToken().balanceOf(address(this));
        safetyModule.terminateAuction(auctionId);
        expectedBalance = balanceBefore + auctionableBalance;
        balanceAfter = stakedToken1.getUnderlyingToken().balanceOf(address(this));
        assertEq(balanceAfter, expectedBalance, "Governance balance mismatch after terminating the auction");
    }

    // solhint-disable-next-line func-name-mixedcase
    function testFuzz_MultipleAuctions(
        uint8[2] memory numLots,
        uint128[2] memory lotPrice,
        uint128[2] memory initialLotSize,
        uint64[2] memory slashPercent,
        uint16[2] memory lotIncreasePeriod,
        uint32[2] memory timeLimit
    ) public {
        /* bounds */
        numLots[0] = uint8(bound(numLots[0], 2, 10));
        numLots[1] = uint8(bound(numLots[1], 2, 10));
        lotPrice[0] = uint128(bound(lotPrice[0], 1e8, 1e12)); // denominated in USDC w/ 6 decimals
        lotPrice[1] = uint128(bound(lotPrice[1], 1e8, 1e12));
        slashPercent[0] = uint64(bound(slashPercent[0], 1e16, 0.99e18));
        slashPercent[1] = uint64(bound(slashPercent[1], 1e16, 0.99e18));
        // lotSize x numLots should not exceed auctionable balance
        uint256[] memory auctionableBalance = new uint256[](2);
        auctionableBalance[0] = stakedToken1.totalSupply().wadMul(slashPercent[0]);
        auctionableBalance[1] = stakedToken2.totalSupply().wadMul(slashPercent[1]);
        initialLotSize[0] = uint128(bound(initialLotSize[0], 1e16, auctionableBalance[0] / numLots[0]));
        initialLotSize[1] = uint128(bound(initialLotSize[1], 1e16, auctionableBalance[1] / numLots[1]));
        uint96[] memory lotIncreaseIncrement = new uint96[](2);
        lotIncreaseIncrement[0] = uint96(bound(initialLotSize[0] / 50, 2e16, type(uint96).max));
        lotIncreaseIncrement[1] = uint96(bound(initialLotSize[1] / 50, 2e16, type(uint96).max));
        lotIncreasePeriod[0] = uint16(bound(lotIncreasePeriod[0], 1 hours, 18 hours));
        lotIncreasePeriod[1] = uint16(bound(lotIncreasePeriod[1], 1 hours, 18 hours));
        timeLimit[0] = uint32(bound(timeLimit[0], 5 days, 30 days));
        timeLimit[1] = uint32(bound(timeLimit[1], 5 days, 30 days));

        // Start auctions and check that they are created correctly
        uint256 auctionId1 = _startAndCheckAuction(
            stakedToken1,
            numLots[0],
            lotPrice[0],
            initialLotSize[0],
            slashPercent[0],
            lotIncreaseIncrement[0],
            lotIncreasePeriod[0],
            timeLimit[0]
        );
        uint256 auctionId2 = _startAndCheckAuction(
            stakedToken2,
            numLots[1],
            lotPrice[1],
            initialLotSize[1],
            slashPercent[1],
            lotIncreaseIncrement[1],
            lotIncreasePeriod[1],
            timeLimit[1]
        );

        // Buy all the lots at once and check the buyer's resulting balances
        uint256[] memory balanceBefore = new uint256[](2);
        balanceBefore[0] = stakedToken1.getUnderlyingToken().balanceOf(liquidityProviderTwo);
        balanceBefore[1] = stakedToken2.getUnderlyingToken().balanceOf(liquidityProviderTwo);
        _dealAndBuyLots(liquidityProviderTwo, auctionId1, numLots[0], lotPrice[0]);
        _dealAndBuyLots(liquidityProviderTwo, auctionId2, numLots[1], lotPrice[1]);
        uint256[] memory balanceAfter = new uint256[](2);
        balanceAfter[0] = stakedToken1.getUnderlyingToken().balanceOf(liquidityProviderTwo);
        balanceAfter[1] = stakedToken2.getUnderlyingToken().balanceOf(liquidityProviderTwo);
        assertEq(
            balanceAfter[0],
            balanceBefore[0] + initialLotSize[0] * numLots[0],
            "Balance mismatch after buying all lots: auction 1"
        );
        assertEq(
            balanceAfter[1],
            balanceBefore[1] + initialLotSize[1] * numLots[1],
            "Balance mismatch after buying all lots: auction 2"
        );

        // Check that the auctions are no longer active and unsold tokens have been returned
        assertTrue(!auctionModule.isAuctionActive(auctionId1), "Auction should not be active after selling out");
        assertTrue(!auctionModule.isAuctionActive(auctionId2), "Auction should not be active after selling out");
        assertEq(_getAuctionRemainingBalance(auctionId1), 0, "Unsold tokens should be returned from the auction module");
        assertEq(_getAuctionRemainingBalance(auctionId2), 0, "Unsold tokens should be returned from the auction module");

        // Check the state of the StakedTokens after slashing is settled and unsold tokens are returned
        uint256[] memory percentSold = new uint256[](2);
        percentSold[0] = uint256(initialLotSize[0] * numLots[0]).wadDiv(stakedToken1.totalSupply());
        percentSold[1] = uint256(initialLotSize[1] * numLots[1]).wadDiv(stakedToken2.totalSupply());
        _checkExchangeRatePreviews(stakedToken1, 1e18, 1e18 - percentSold[0], "after selling out auction 1");
        _checkExchangeRatePreviews(stakedToken2, 1e18, 1e18 - percentSold[1], "after selling out auction 2");

        // Withdraw the funds raised from the auctions and check the resulting balance
        uint256[] memory fundsRaised = new uint256[](2);
        fundsRaised[0] = auctionModule.getFundsRaised(auctionId1);
        fundsRaised[1] = auctionModule.getFundsRaised(auctionId2);
        assertEq(fundsRaised[0], lotPrice[0] * numLots[0], "Funds raised mismatch after selling out auction 1");
        assertEq(fundsRaised[1], lotPrice[1] * numLots[1], "Funds raised mismatch after selling out auction 2");
        assertEq(
            usdc.balanceOf(address(safetyModule)),
            fundsRaised[0] + fundsRaised[1],
            "Safety module should have the funds raised before withdrawing"
        );
        safetyModule.withdrawFundsRaisedFromAuction(fundsRaised[0] + fundsRaised[1]);
        assertEq(
            usdc.balanceOf(address(this)),
            fundsRaised[0] + fundsRaised[1],
            "Balance mismatch after withdrawing funds raised from auction"
        );
        assertEq(
            usdc.balanceOf(address(safetyModule)), 0, "Safety module should have no remaining funds after withdrawing"
        );
    }

    /* ******************* */
    /*    Custom Errors    */
    /* ******************* */

    // solhint-disable-next-line func-name-mixedcase
    function test_SafetyModuleErrors() public {
        // test staked token already registered
        _expectStakedTokenAlreadyRegistered(address(stakedToken1));
        safetyModule.addStakedToken(stakedToken1);

        // test insufficient auctionable funds
        // i.e., lotSize x numLots exceeds total supply of underlying token
        uint128 lotSize = uint128(stakedToken1.totalSupply()) + 1;
        // other auction params
        uint128 lotPrice = 1e18;
        uint8 numLots = 2;
        uint256 slashAmount = stakedToken1.totalSupply();
        uint96 increment = 1e18;
        uint16 period = 1 hours;
        uint32 timelimit = 5 days;
        address stakedToken = address(stakedToken1);
        address underlyingToken = address(stakedToken1.getUnderlyingToken());
        _expectInsufficientSlashedTokensForAuction(
            underlyingToken, numLots * lotSize, stakedToken1.totalSupply().wadMul(0.99e18)
        );
        safetyModule.slashAndStartAuction(
            stakedToken, numLots, lotPrice, lotSize, slashAmount, increment, period, timelimit
        );

        // test invalid staked token
        _expectInvalidStakedToken(liquidityProviderOne);
        safetyModule.getStakedTokenIdx(liquidityProviderOne);
        _expectInvalidStakedToken(liquidityProviderOne);
        safetyModule.slashAndStartAuction(
            liquidityProviderOne, numLots, lotPrice, lotSize, slashAmount, increment, period, timelimit
        );

        // test invalid callers
        vm.startPrank(liquidityProviderOne);
        _expectCallerIsNotAuctionModule(liquidityProviderOne);
        safetyModule.auctionEnded(0, 0);
        vm.stopPrank();

        // test setting auction module during auction
        safetyModule.slashAndStartAuction(
            address(stakedToken1),
            1,
            1 ether,
            uint128(stakedToken1.totalSupply() / 10),
            stakedToken1.totalSupply(),
            0.1 ether,
            1 hours,
            10 days
        );
        _expectCannotReplaceAuctionModuleActiveAuction();
        safetyModule.setAuctionModule(IAuctionModule(address(0)));
    }

    // solhint-disable-next-line func-name-mixedcase
    function test_SMRDErrors() public {
        /* bounds */
        uint256 lowMaxMultiplier1 = 0;
        uint256 lowMaxMultiplier2 = 1e18 - 1;
        uint256 highMaxMultiplier1 = 10e18 + 1;
        uint256 highMaxMultiplier2 = type(uint256).max;
        uint256 lowSmoothingValue1 = 0;
        uint256 lowSmoothingValue2 = 10e18 - 1;
        uint256 highSmoothingValue1 = 100e18 + 1;
        uint256 highSmoothingValue2 = type(uint256).max;

        // test governor-controlled params out of bounds
        _expectInvalidMaxMultiplierTooLow(lowMaxMultiplier1, 1e18);
        rewardDistributor.setMaxRewardMultiplier(lowMaxMultiplier1);
        _expectInvalidMaxMultiplierTooLow(lowMaxMultiplier2, 1e18);
        rewardDistributor.setMaxRewardMultiplier(lowMaxMultiplier2);
        _expectInvalidMaxMultiplierTooHigh(highMaxMultiplier1, 10e18);
        rewardDistributor.setMaxRewardMultiplier(highMaxMultiplier1);
        _expectInvalidMaxMultiplierTooHigh(highMaxMultiplier2, 10e18);
        rewardDistributor.setMaxRewardMultiplier(highMaxMultiplier2);
        _expectInvalidSmoothingValueTooLow(lowSmoothingValue1, 10e18);
        rewardDistributor.setSmoothingValue(lowSmoothingValue1);
        _expectInvalidSmoothingValueTooLow(lowSmoothingValue2, 10e18);
        rewardDistributor.setSmoothingValue(lowSmoothingValue2);
        _expectInvalidSmoothingValueTooHigh(highSmoothingValue1, 100e18);
        rewardDistributor.setSmoothingValue(highSmoothingValue1);
        _expectInvalidSmoothingValueTooHigh(highSmoothingValue2, 100e18);
        rewardDistributor.setSmoothingValue(highSmoothingValue2);
        _expectRewardDistributorInvalidZeroAddress();
        rewardDistributor.setSafetyModule(ISafetyModule(address(0)));

        // test already initialized market
        vm.startPrank(address(safetyModule));
        _expectAlreadyInitializedStartTime(address(stakedToken1));
        rewardDistributor.initMarketStartTime(address(stakedToken1));
        vm.stopPrank();

        // test invalid callers
        vm.startPrank(liquidityProviderOne);
        _expectCallerIsNotStakedToken(liquidityProviderOne);
        rewardDistributor.updatePosition(address(stakedToken1), liquidityProviderOne);
        vm.stopPrank();

        // test paused
        rewardDistributor.pause();
        assertTrue(rewardDistributor.paused(), "SMRD should be paused");
        vm.startPrank(liquidityProviderOne);
        vm.expectRevert(bytes("Pausable: paused"));
        rewardDistributor.claimRewards();
        vm.stopPrank();
        rewardDistributor.unpause();
        assertTrue(!rewardDistributor.paused(), "SMRD should not be paused");
        safetyModule.pause();
        assertTrue(rewardDistributor.paused(), "SMRD should be paused when safety module is paused");
        vm.startPrank(liquidityProviderOne);
        vm.expectRevert(bytes("Pausable: paused"));
        rewardDistributor.claimRewards();
        vm.stopPrank();
        safetyModule.unpause();
        assertTrue(!rewardDistributor.paused(), "SMRD should not be paused when safety module is unpaused");
    }

    // solhint-disable-next-line func-name-mixedcase
    function test_StakedTokenErrors() public {
        // test zero amount
        _expectStakedTokenInvalidZeroAmount();
        stakedToken1.stakeOnBehalfOf(liquidityProviderTwo, 0);
        _expectStakedTokenInvalidZeroAmount();
        stakedToken1.redeemTo(liquidityProviderOne, 0);
        vm.startPrank(address(safetyModule));
        _expectStakedTokenInvalidZeroAmount();
        stakedToken1.slash(address(safetyModule), 0);
        _expectStakedTokenInvalidZeroAmount();
        stakedToken1.returnFunds(address(safetyModule), 0);

        // test zero address
        _expectStakedTokenInvalidZeroAddress();
        stakedToken1.stakeOnBehalfOf(address(0), 1);
        _expectStakedTokenInvalidZeroAddress();
        stakedToken1.redeemTo(address(0), 1);
        _expectStakedTokenInvalidZeroAddress();
        stakedToken1.slash(address(0), 1);
        _expectStakedTokenInvalidZeroAddress();
        stakedToken1.returnFunds(address(0), 1);
        vm.stopPrank();

        // test zero balance
        _expectZeroBalanceAtCooldown();
        stakedToken1.cooldown();

        // test above max stake amount
        uint256 invalidStakeAmount = type(uint256).max / 2;
        deal(address(stakedToken1.getUnderlyingToken()), liquidityProviderOne, MAX_STAKE_AMOUNT_1);
        deal(address(stakedToken2.getUnderlyingToken()), liquidityProviderOne, MAX_STAKE_AMOUNT_2);
        vm.startPrank(liquidityProviderOne);
        // first stake the max amount, then try to stake more, expecting it to fail
        stakedToken1.stake(MAX_STAKE_AMOUNT_1);
        stakedToken2.stake(MAX_STAKE_AMOUNT_2);
        _expectAboveMaxStakeAmount(MAX_STAKE_AMOUNT_1, 0);
        stakedToken1.stake(1);
        _expectAboveMaxStakeAmount(MAX_STAKE_AMOUNT_2, 0);
        stakedToken2.stake(1);
        deal(address(stakedToken1), liquidityProviderTwo, invalidStakeAmount);
        vm.startPrank(liquidityProviderTwo);
        _expectAboveMaxStakeAmount(MAX_STAKE_AMOUNT_1, 0);
        stakedToken1.transfer(liquidityProviderOne, invalidStakeAmount);
        // change max stake amount and try again, expecting it to succeed
        vm.stopPrank();
        stakedToken1.setMaxStakeAmount(type(uint256).max);
        vm.startPrank(liquidityProviderTwo);
        vm.expectEmit(false, false, false, true);
        emit Transfer(liquidityProviderTwo, liquidityProviderOne, invalidStakeAmount);
        stakedToken1.transfer(liquidityProviderOne, invalidStakeAmount);
        // transfer the amount back so that subsequent tests work
        vm.startPrank(liquidityProviderOne);
        stakedToken1.transfer(liquidityProviderTwo, invalidStakeAmount);

        // test insufficient cooldown
        stakedToken1.cooldown();
        uint256 cooldownStartTimestamp = block.timestamp;
        uint256 stakedBalance = stakedToken1.balanceOf(liquidityProviderOne);
        _expectInsufficientCooldown(cooldownStartTimestamp + 1 days);
        stakedToken1.redeem(stakedBalance);

        // test unstake window finished
        skip(20 days);
        _expectUnstakeWindowFinished(cooldownStartTimestamp + 11 days);
        stakedToken1.redeem(stakedBalance);
        // redeem correctly
        stakedToken1.cooldown();
        skip(1 days);
        if (stakedBalance % 2 == 0 && stakedBalance < type(uint256).max / 2) {
            // test redeeming more than staked balance to make sure it adjusts the amount
            stakedToken1.redeem(stakedBalance * 2);
        } else {
            stakedToken1.redeem(stakedBalance);
        }
        // restake, then try redeeming without cooldown
        stakedToken1.stake(stakedBalance);
        _expectUnstakeWindowFinished(11 days);
        stakedToken1.redeem(stakedBalance);
        vm.stopPrank();

        // test invalid caller not safety module
        _expectStakedTokenCallerIsNotSafetyModule(address(this));
        stakedToken1.slash(address(this), 0);
        _expectStakedTokenCallerIsNotSafetyModule(address(this));
        stakedToken1.returnFunds(address(this), 0);
        _expectStakedTokenCallerIsNotSafetyModule(address(this));
        stakedToken1.settleSlashing();

        // test zero exchange rate
        vm.startPrank(address(safetyModule));
        // slash 100% of staked tokens, resulting in zero exchange rate
        uint256 maxAuctionableTotal = stakedToken1.totalSupply();
        uint256 slashedTokens = stakedToken1.slash(address(this), maxAuctionableTotal);
        vm.stopPrank();
        assertEq(stakedToken1.exchangeRate(), 0, "Exchange rate should be 0 after slashing 100% of staked tokens");
        assertEq(stakedToken1.previewStake(1e18), 0, "Preview stake should be 0 when exchange rate is 0");
        assertEq(stakedToken1.previewRedeem(1e18), 0, "Preview redeem should be 0 when exchange rate is 0");
        // staked and redeeming should fail due to zero exchange rate
        _expectZeroExchangeRate();
        stakedToken1.stake(1);
        _expectZeroExchangeRate();
        stakedToken1.redeem(1);

        // test features disabled in post-slashing state
        stakedToken1.getUnderlyingToken().approve(address(stakedToken1), type(uint256).max);
        vm.startPrank(address(safetyModule));
        // return all slashed funds, but do not settle slashing yet
        stakedToken1.returnFunds(address(this), slashedTokens);
        // slashing, staked and cooldown should fail due to post-slashing state
        _expectSlashingDisabledInPostSlashingState();
        stakedToken1.slash(address(this), slashedTokens);
        vm.startPrank(liquidityProviderOne);
        _expectStakingDisabledInPostSlashingState();
        stakedToken1.stake(1);
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
        assertTrue(stakedToken1.paused(), "Staked token should be paused when Safety Module is");
        vm.startPrank(address(liquidityProviderOne));
        vm.expectRevert(bytes("Pausable: paused"));
        stakedToken1.stake(1);
        vm.expectRevert(bytes("Pausable: paused"));
        stakedToken1.transfer(liquidityProviderTwo, 1);
        vm.stopPrank();
        safetyModule.unpause();
    }

    // solhint-disable-next-line func-name-mixedcase
    function test_AuctionModuleErrors() public {
        // start an auction successfully for later tests
        uint256 auctionId = safetyModule.slashAndStartAuction(
            address(stakedToken1),
            1,
            1 ether,
            uint128(stakedToken1.totalSupply() / 10),
            stakedToken1.totalSupply(),
            0.1 ether,
            1 hours,
            10 days
        );

        // test invalid zero arguments
        vm.startPrank(address(safetyModule));
        _expectInvalidZeroAddress(0);
        auctionModule.startAuction(IERC20(address(0)), 0, 0, 0, 0, 0, 0);
        _expectInvalidZeroArgument(1);
        auctionModule.startAuction(rewardsToken, 0, 0, 0, 0, 0, 0);
        _expectInvalidZeroArgument(2);
        auctionModule.startAuction(rewardsToken, 1, 0, 0, 0, 0, 0);
        _expectInvalidZeroArgument(3);
        auctionModule.startAuction(rewardsToken, 1, 1, 0, 0, 0, 0);
        _expectInvalidZeroArgument(4);
        auctionModule.startAuction(rewardsToken, 1, 1, 1, 0, 0, 0);
        _expectInvalidZeroArgument(5);
        auctionModule.startAuction(rewardsToken, 1, 1, 1, 1, 0, 0);
        _expectInvalidZeroArgument(6);
        auctionModule.startAuction(rewardsToken, 1, 1, 1, 1, 1, 0);
        vm.stopPrank();
        _expectInvalidZeroAddress(0);
        auctionModule.setPaymentToken(IERC20(address(0)));
        _expectInvalidZeroAddress(0);
        auctionModule.setSafetyModule(ISafetyModule(address(0)));
        _expectInvalidZeroArgument(1);
        auctionModule.buyLots(auctionId, 0);

        // test token already in auction
        vm.startPrank(address(safetyModule));
        _expectTokenAlreadyInAuction(address(rewardsToken));
        auctionModule.startAuction(rewardsToken, 1, 1, 1, 1, 1, 1);
        vm.stopPrank();

        // test setting payment token during auction
        _expectCannotReplacePaymentTokenActiveAuction();
        auctionModule.setPaymentToken(usdc);

        // test invalid auction ID
        _expectInvalidAuctionId(1);
        auctionModule.buyLots(1, 1);
        _expectInvalidAuctionId(1);
        auctionModule.completeAuction(1);
        _expectInvalidAuctionId(1);
        auctionModule.getCurrentLotSize(1);
        vm.startPrank(address(safetyModule));
        _expectInvalidAuctionId(1);
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
        assertTrue(auctionModule.paused(), "Auction module should be paused when Safety Module is");
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
        _expectNotEnoughLotsRemaining(auctionId, 1);
        auctionModule.buyLots(auctionId, 2);

        // test invalid caller not safety module
        _expectAuctionModuleCallerIsNotSafetyModule(address(this));
        auctionModule.startAuction(IERC20(address(0)), 0, 0, 0, 0, 0, 0);
        _expectAuctionModuleCallerIsNotSafetyModule(address(this));
        auctionModule.terminateAuction(auctionId);

        // test auction still active
        _expectAuctionStillActive(auctionId, block.timestamp + 10 days);
        auctionModule.completeAuction(auctionId);

        // skip to auction end time
        skip(10 days);

        // test auction not active
        _expectAuctionNotActive(auctionId);
        auctionModule.buyLots(auctionId, 1); // reverts due to timestamp check, not active flag
        // complete auction manually, setting active flag to false
        auctionModule.completeAuction(auctionId);
        _expectAuctionNotActive(auctionId);
        auctionModule.completeAuction(auctionId);
        vm.startPrank(address(safetyModule));
        _expectAuctionNotActive(auctionId);
        auctionModule.terminateAuction(auctionId);
        vm.stopPrank();
    }

    /* ****************** */
    /*  Helper Functions  */
    /* ****************** */

    function _stake(IStakedToken stakedToken, address staker, uint256 amount) internal {
        uint256 balance = stakedToken.balanceOf(staker);
        uint256 maxStake = stakedToken.maxStakeAmount();
        vm.startPrank(staker);
        if (balance + amount <= maxStake) {
            vm.expectEmit(false, false, false, true);
            emit Staked(staker, staker, amount);
        } else {
            _expectAboveMaxStakeAmount(maxStake, maxStake - balance);
        }
        stakedToken.stake(amount);
        vm.stopPrank();
    }

    function _redeem(IStakedToken stakedToken, address staker, uint256 amount) internal {
        uint256 balance = stakedToken.balanceOf(staker);
        uint256 cooldown = stakedToken.getCooldownSeconds();
        vm.startPrank(staker);
        vm.expectEmit(false, false, false, true);
        emit Cooldown(staker);
        stakedToken.cooldown();
        skip(cooldown);
        vm.expectEmit(false, false, false, true);
        if (amount < balance) {
            emit Redeemed(staker, staker, amount);
        } else {
            emit Redeemed(staker, staker, balance);
        }
        stakedToken.redeem(amount);
        vm.stopPrank();
    }

    function _claimAndRedeemAll(IStakedToken[] memory stakedTokens, IRewardDistributor distributor, address staker)
        internal
    {
        for (uint256 i; i < stakedTokens.length; i++) {
            IStakedToken stakedToken = stakedTokens[i];
            uint256 balance = stakedToken.balanceOf(staker);
            if (balance != 0) {
                _redeem(stakedToken, staker, balance);
            }
        }
        vm.startPrank(staker);
        distributor.claimRewards();
        vm.stopPrank();
    }

    function _calcExpectedMultiplier(uint256 deltaDays) internal view returns (uint256) {
        uint256 smoothingValue = rewardDistributor.getSmoothingValue();
        uint256 maxMultiplier = rewardDistributor.getMaxRewardMultiplier();
        return maxMultiplier
            - (smoothingValue * (maxMultiplier - 1e18)) / (deltaDays.wadMul(maxMultiplier - 1e18) + smoothingValue);
    }

    function _calcWeightedAverageCooldown(
        uint256 fromCooldownTimestamp,
        uint256 toCooldownTimestamp,
        uint256 amountToReceive,
        uint256 toBalance
    ) internal pure returns (uint256) {
        return
            (fromCooldownTimestamp * amountToReceive + toCooldownTimestamp * toBalance) / (amountToReceive + toBalance);
    }

    function _getMarkets() internal view returns (address[] memory) {
        uint256 numMarkets = safetyModule.getNumStakedTokens();
        address[] memory markets = new address[](numMarkets);
        for (uint256 i; i < numMarkets; i++) {
            markets[i] = address(safetyModule.stakedTokens(i));
        }
        return markets;
    }

    function _getStakedTokens() internal view returns (IStakedToken[] memory) {
        uint256 numMarkets = safetyModule.getNumStakedTokens();
        IStakedToken[] memory markets = new IStakedToken[](numMarkets);
        for (uint256 i; i < numMarkets; i++) {
            markets[i] = safetyModule.stakedTokens(i);
        }
        return markets;
    }

    function _getUserBalances(address user) internal view returns (uint256[] memory) {
        uint256 numMarkets = safetyModule.getNumStakedTokens();
        uint256[] memory balances = new uint256[](numMarkets);
        for (uint256 i; i < numMarkets; i++) {
            balances[i] = safetyModule.stakedTokens(i).balanceOf(user);
        }
        return balances;
    }

    function _getRewardWeights(TestSMRewardDistributor distributor, address token)
        internal
        view
        returns (uint256[] memory)
    {
        uint256 numMarkets = safetyModule.getNumStakedTokens();
        uint256[] memory weights = new uint256[](numMarkets);
        for (uint256 i; i < numMarkets; i++) {
            weights[i] = distributor.getRewardWeight(token, address(safetyModule.stakedTokens(i)));
        }
        return weights;
    }

    function _getRewardMultipliers(TestSMRewardDistributor distributor, address user)
        internal
        view
        returns (uint256[] memory)
    {
        uint256 numMarkets = safetyModule.getNumStakedTokens();
        uint256[] memory multipliers = new uint256[](numMarkets);
        for (uint256 i; i < numMarkets; i++) {
            multipliers[i] = distributor.computeRewardMultiplier(user, address(safetyModule.stakedTokens(i)));
        }
        return multipliers;
    }

    function _getCumulativeRewardsByToken(TestSMRewardDistributor distributor, address token)
        internal
        view
        returns (uint256[] memory)
    {
        uint256 numMarkets = safetyModule.getNumStakedTokens();
        uint256[] memory rewards = new uint256[](numMarkets);
        for (uint256 i; i < numMarkets; i++) {
            rewards[i] = distributor.cumulativeRewardPerLpToken(token, address(safetyModule.stakedTokens(i)));
        }
        return rewards;
    }

    function _getCumulativeRewardsByUserByToken(TestSMRewardDistributor distributor, address token, address user)
        internal
        view
        returns (uint256[] memory)
    {
        uint256 numMarkets = safetyModule.getNumStakedTokens();
        uint256[] memory rewards = new uint256[](numMarkets);
        for (uint256 i; i < numMarkets; i++) {
            rewards[i] =
                distributor.cumulativeRewardPerLpTokenPerUser(user, token, address(safetyModule.stakedTokens(i)));
        }
        return rewards;
    }

    function _getTotalLiquidityPerMarket(TestSMRewardDistributor distributor)
        internal
        view
        returns (uint256[] memory)
    {
        uint256 numMarkets = safetyModule.getNumStakedTokens();
        uint256[] memory totalLiquidity = new uint256[](numMarkets);
        for (uint256 i; i < numMarkets; i++) {
            totalLiquidity[i] = distributor.totalLiquidityPerMarket(address(safetyModule.stakedTokens(i)));
        }
        return totalLiquidity;
    }

    function _getSkipTimes(TestSMRewardDistributor distributor) internal view returns (uint256[] memory) {
        uint256 numMarkets = safetyModule.getNumStakedTokens();
        uint256[] memory skipTimes = new uint256[](numMarkets);
        for (uint256 i; i < numMarkets; i++) {
            skipTimes[i] =
                block.timestamp - distributor.timeOfLastCumRewardUpdate(address(safetyModule.stakedTokens(i)));
        }
        return skipTimes;
    }

    function _getAuctionRemainingBalance(uint256 auctionId) internal view returns (uint256) {
        return auctionModule.getAuctionToken(auctionId).balanceOf(address(auctionModule));
    }

    function _dealAndBuyLots(address buyer, uint256 auctionId, uint8 numLots, uint128 lotPrice) internal {
        IERC20 paymentToken = auctionModule.paymentToken();
        IStakedToken stakedToken = safetyModule.stakedTokenByAuctionId(auctionId);
        deal(address(paymentToken), buyer, lotPrice * numLots);
        vm.startPrank(buyer);
        paymentToken.approve(address(auctionModule), lotPrice * numLots);
        uint256 lotSize = auctionModule.getCurrentLotSize(auctionId);
        uint256 tokensAlreadySold = auctionModule.getTokensSold(auctionId);
        uint256 fundsAlreadyRaised = auctionModule.getFundsRaised(auctionId);
        uint256 remainingBalance = _getAuctionRemainingBalance(auctionId) - lotSize * numLots;
        vm.expectEmit(true, true, false, true);
        emit LotsSold(auctionId, buyer, numLots, lotSize, lotPrice);
        if (numLots == auctionModule.getRemainingLots(auctionId)) {
            if (remainingBalance > 0) {
                vm.expectEmit(false, false, false, true);
                emit Approval(address(auctionModule), address(stakedToken), remainingBalance);
            }
            vm.expectEmit(false, false, false, true);
            emit Transfer(address(auctionModule), address(safetyModule), fundsAlreadyRaised + lotPrice * numLots);
            vm.expectEmit(true, false, false, true);
            emit AuctionCompleted(
                auctionId, 0, lotSize, tokensAlreadySold + lotSize * numLots, fundsAlreadyRaised + lotPrice * numLots
            );
        }
        auctionModule.buyLots(auctionId, numLots);
        vm.stopPrank();
    }

    function _deployBalancerPool(address token1, address token2, string memory name) internal returns (IWeightedPool) {
        address[] memory poolTokens = new address[](2);
        poolTokens[0] = token1;
        poolTokens[1] = token2;
        uint256[] memory poolWeights = new uint256[](2);
        poolWeights[0] = 0.5e18;
        poolWeights[1] = 0.5e18;
        return IWeightedPool(
            weightedPoolFactory.create(
                name, name, poolTokens, poolWeights, new address[](2), 1e15, address(this), bytes32(0)
            )
        );
    }

    function _joinBalancerPool(bytes32 id, address staker, uint256 maxAmountIn0, uint256 maxAmountIn1) internal {
        (IERC20[] memory poolERC20s,,) = balancerVault.getPoolTokens(id);
        IAsset[] memory poolAssets = new IAsset[](2);
        poolAssets[0] = IAsset(address(poolERC20s[0]));
        poolAssets[1] = IAsset(address(poolERC20s[1]));
        uint256[] memory maxAmountsIn = new uint256[](2);
        maxAmountsIn[0] = maxAmountIn0;
        maxAmountsIn[1] = maxAmountIn1;
        vm.startPrank(staker);
        balancerVault.joinPool(
            poolId,
            staker,
            staker,
            IBalancerVault.JoinPoolRequest(
                poolAssets, maxAmountsIn, abi.encode(JoinKind.EXACT_TOKENS_IN_FOR_BPT_OUT, maxAmountsIn), false
            )
        );
        vm.stopPrank();
    }

    function _joinBalancerPoolInit(bytes32 id, uint256 maxAmountIn0, uint256 maxAmountIn1) internal {
        (IERC20[] memory poolERC20s,,) = balancerVault.getPoolTokens(id);
        IAsset[] memory poolAssets = new IAsset[](2);
        poolAssets[0] = IAsset(address(poolERC20s[0]));
        poolAssets[1] = IAsset(address(poolERC20s[1]));
        uint256[] memory maxAmountsIn = new uint256[](2);
        maxAmountsIn[0] = maxAmountIn0;
        maxAmountsIn[1] = maxAmountIn1;
        poolERC20s[0].approve(address(balancerVault), maxAmountIn0);
        poolERC20s[1].approve(address(balancerVault), maxAmountIn1);
        if (address(poolERC20s[0]) == address(weth)) {
            weth.deposit{value: maxAmountIn0}();
        } else if (address(poolERC20s[1]) == address(weth)) {
            weth.deposit{value: maxAmountIn1}();
        }
        IBalancerVault.JoinPoolRequest memory joinRequest =
            IBalancerVault.JoinPoolRequest(poolAssets, maxAmountsIn, abi.encode(JoinKind.INIT, maxAmountsIn), false);
        balancerVault.joinPool(id, address(this), address(this), joinRequest);
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
        uint256 deltaTime = block.timestamp - rewardDistributor.timeOfLastCumRewardUpdate(market);
        if (rewardDistributor.totalLiquidityPerMarket(market) == 0) return 0;
        // Calculate the new cumRewardPerLpToken by adding (inflationRatePerSecond x guageWeight x deltaTime) to the previous cumRewardPerLpToken
        uint256 newMarketRewards = (
            ((rewardDistributor.getInflationRate(token) * rewardDistributor.getRewardWeight(token, market)) / 10000)
                * deltaTime
        ) / 365 days;
        uint256 newCumRewardPerLpToken = rewardDistributor.cumulativeRewardPerLpToken(token, market)
            + newMarketRewards.wadDiv(rewardDistributor.totalLiquidityPerMarket(market));
        uint256 newUserRewards = rewardDistributor.lpPositionsPerUser(user, market).wadMul(
            (newCumRewardPerLpToken - rewardDistributor.cumulativeRewardPerLpTokenPerUser(user, token, market))
        ).wadMul(rewardDistributor.computeRewardMultiplier(user, market));
        return newUserRewards;
    }

    function _checkMultiplierAdjustment(address token, address user, uint256 increaseRatio, uint256 skipTime)
        internal
        returns (uint256)
    {
        uint256 newMultiplierStartTime = rewardDistributor.multiplierStartTimeByUser(user, token);
        assertEq(
            newMultiplierStartTime,
            block.timestamp - uint256(skipTime).wadMul(1e18 - increaseRatio),
            "Multiplier start time mismatch after transfer: user 2"
        );
        uint256 deltaDays = (block.timestamp - newMultiplierStartTime).wadDiv(1 days);
        uint256 expectedMultiplier = _calcExpectedMultiplier(deltaDays);
        assertEq(
            rewardDistributor.computeRewardMultiplier(liquidityProviderTwo, address(stakedToken1)),
            expectedMultiplier,
            "Reward multiplier mismatch after transfer: user 2"
        );
        return newMultiplierStartTime;
    }

    function _checkExchangeRatePreviews(
        IStakedToken stakedToken,
        uint256 previewAmount,
        uint256 expectedExchangeRate,
        string memory errorMsg
    ) internal {
        assertApproxEqRel(
            stakedToken.exchangeRate(),
            expectedExchangeRate,
            1e15, // 0.1% tolerance
            string(abi.encodePacked("Exchange rate mismatch ", errorMsg))
        );
        assertApproxEqRel(
            stakedToken.previewStake(previewAmount),
            expectedExchangeRate == 0 ? 0 : previewAmount.wadDiv(expectedExchangeRate),
            1e15, // 0.1% tolerance
            string(abi.encodePacked("Preview stake mismatch ", errorMsg))
        );
        assertApproxEqRel(
            stakedToken.previewRedeem(previewAmount),
            previewAmount.wadMul(expectedExchangeRate),
            1e15, // 0.1% tolerance
            string(abi.encodePacked("Preview redeem mismatch ", errorMsg))
        );
    }

    function _startAndCheckAuction(
        IStakedToken stakedToken,
        uint8 numLots,
        uint128 lotPrice,
        uint128 initialLotSize,
        uint256 slashPercent,
        uint96 lotIncreaseIncrement,
        uint16 lotIncreasePeriod,
        uint32 timeLimit
    ) internal returns (uint256) {
        slashPercent = bound(slashPercent, 1e16, 0.99e18);
        uint256 slashAmount = stakedToken.totalSupply().wadMul(slashPercent);
        uint256 nextId = auctionModule.getNextAuctionId();
        uint256 auctionId = safetyModule.slashAndStartAuction(
            address(stakedToken),
            numLots,
            lotPrice,
            initialLotSize,
            slashAmount,
            lotIncreaseIncrement,
            lotIncreasePeriod,
            timeLimit
        );
        assertTrue(auctionModule.isAnyAuctionActive(), "Auction should be active");
        assertEq(auctionId, nextId, "Auction ID mismatch");
        assertEq(auctionModule.getNextAuctionId(), nextId + 1, "Next auction ID mismatch");
        assertEq(auctionModule.getCurrentLotSize(auctionId), initialLotSize, "Initial lot size mismatch");
        assertEq(auctionModule.getRemainingLots(auctionId), numLots, "Initial lots mismatch");
        assertEq(auctionModule.getLotPrice(auctionId), lotPrice, "Lot price mismatch");
        assertEq(
            auctionModule.getLotIncreaseIncrement(auctionId), lotIncreaseIncrement, "Lot increase increment mismatch"
        );
        assertEq(auctionModule.getLotIncreasePeriod(auctionId), lotIncreasePeriod, "Lot increase period mismatch");
        assertEq(
            address(auctionModule.getAuctionToken(auctionId)),
            address(stakedToken.getUnderlyingToken()),
            "Auction token mismatch"
        );
        assertEq(auctionModule.getStartTime(auctionId), block.timestamp, "Start time mismatch");
        assertEq(auctionModule.getEndTime(auctionId), block.timestamp + timeLimit, "End time mismatch");
        assertTrue(auctionModule.isAuctionActive(auctionId), "Auction should be active");

        assertTrue(stakedToken.isInPostSlashingState(), "Staked token should be in post slashing state");
        _checkExchangeRatePreviews(stakedToken, 1e18, 1e18 - slashPercent, "after slashing");

        return auctionId;
    }

    function _checkRewards(
        address token,
        address user,
        uint256[] memory multipliers,
        uint256[] memory skipTimes,
        uint256[] memory balances,
        uint256[] memory initialCumRewards,
        uint256[] memory priorTotalLiquidity,
        uint256 initialUserRewards
    ) internal returns (uint256) {
        uint256[] memory weights = _getRewardWeights(rewardDistributor, token);
        return _checkRewards(
            token,
            user,
            multipliers,
            skipTimes,
            balances,
            initialCumRewards,
            priorTotalLiquidity,
            weights,
            initialUserRewards
        );
    }

    function _checkRewards(
        address token,
        address user,
        uint256[] memory multipliers,
        uint256[] memory skipTimes,
        uint256[] memory balances,
        uint256[] memory initialCumRewards,
        uint256[] memory priorTotalLiquidity,
        uint256[] memory weights,
        uint256 initialUserRewards
    ) internal returns (uint256) {
        return _checkRewards(
            rewardDistributor,
            token,
            user,
            multipliers,
            skipTimes,
            balances,
            initialCumRewards,
            priorTotalLiquidity,
            weights,
            initialUserRewards
        );
    }

    function _checkRewards(
        TestSMRewardDistributor distributor,
        address token,
        address user,
        uint256[] memory multipliers,
        uint256[] memory skipTimes,
        uint256[] memory balances,
        uint256[] memory initialCumRewards,
        uint256[] memory priorTotalLiquidity,
        uint256 initialUserRewards
    ) internal returns (uint256) {
        uint256[] memory weights = _getRewardWeights(distributor, token);
        return _checkRewards(
            distributor,
            token,
            user,
            multipliers,
            skipTimes,
            balances,
            initialCumRewards,
            priorTotalLiquidity,
            weights,
            initialUserRewards
        );
    }

    function _checkRewards(
        TestSMRewardDistributor distributor,
        address token,
        address user,
        uint256[] memory multipliers,
        uint256[] memory skipTimes,
        uint256[] memory balances,
        uint256[] memory initialCumRewards,
        uint256[] memory priorTotalLiquidity,
        uint256[] memory weights,
        uint256 initialUserRewards
    ) internal returns (uint256) {
        require(skipTimes.length == balances.length, "Invalid input");
        require(skipTimes.length == initialCumRewards.length, "Invalid input");
        require(skipTimes.length == priorTotalLiquidity.length, "Invalid input");

        uint256 accruedRewards = distributor.rewardsAccruedByUser(user, token);
        assertGt(accruedRewards, 0, "Rewards not accrued");
        uint256 expectedAccruedRewards = _checkMarketRewards(
            distributor,
            token,
            initialUserRewards,
            multipliers,
            skipTimes,
            balances,
            initialCumRewards,
            priorTotalLiquidity,
            weights
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
        uint256[] memory multipliers,
        uint256[] memory skipTimes,
        uint256[] memory balances,
        uint256[] memory initialCumRewards,
        uint256[] memory priorTotalLiquidity
    ) internal returns (uint256) {
        uint256[] memory weights = _getRewardWeights(rewardDistributor, token);
        return _checkMarketRewards(
            token, initialUserRewards, multipliers, skipTimes, balances, initialCumRewards, priorTotalLiquidity, weights
        );
    }

    function _checkMarketRewards(
        address token,
        uint256 initialUserRewards,
        uint256[] memory multipliers,
        uint256[] memory skipTimes,
        uint256[] memory balances,
        uint256[] memory initialCumRewards,
        uint256[] memory priorTotalLiquidity,
        uint256[] memory weights
    ) internal returns (uint256) {
        return _checkMarketRewards(
            rewardDistributor,
            token,
            initialUserRewards,
            multipliers,
            skipTimes,
            balances,
            initialCumRewards,
            priorTotalLiquidity,
            weights
        );
    }

    function _checkMarketRewards(
        TestSMRewardDistributor distributor,
        address token,
        uint256 initialUserRewards,
        uint256[] memory multipliers,
        uint256[] memory skipTimes,
        uint256[] memory balances,
        uint256[] memory initialCumRewards,
        uint256[] memory priorTotalLiquidity
    ) internal returns (uint256) {
        uint256[] memory weights = _getRewardWeights(distributor, token);
        return _checkMarketRewards(
            distributor,
            token,
            initialUserRewards,
            multipliers,
            skipTimes,
            balances,
            initialCumRewards,
            priorTotalLiquidity,
            weights
        );
    }

    function _checkMarketRewards(
        TestSMRewardDistributor distributor,
        address token,
        uint256 initialUserRewards,
        uint256[] memory multipliers,
        uint256[] memory skipTimes,
        uint256[] memory balances,
        uint256[] memory initialCumRewards,
        uint256[] memory priorTotalLiquidity,
        uint256[] memory weights
    ) internal returns (uint256) {
        uint256 expectedAccruedRewards = initialUserRewards;
        uint256 numMarkets = safetyModule.getNumStakedTokens();
        require(numMarkets == skipTimes.length, "Invalid input");
        for (uint256 i; i < numMarkets; ++i) {
            console.log("skipTimes[%s] = %s", i, skipTimes[i]);
            console.log("balances[%s] = %s", i, balances[i]);
            console.log("multipliers[%s] = %s", i, multipliers[i]);
            console.log("initialCumRewards[%s] = %s", i, initialCumRewards[i]);
            console.log("priorTotalLiquidity[%s] = %s", i, priorTotalLiquidity[i]);
            console.log("weights[%s] = %s", i, weights[i]);
            uint256 cumulativeRewards = distributor.cumulativeRewardPerLpToken(
                token, address(safetyModule.stakedTokens(i))
            ) - initialCumRewards[i];
            console.log("cumulativeRewards = %s", cumulativeRewards);
            uint256 expectedCumulativeRewards =
                _calcExpectedCumulativeRewards(token, skipTimes[i], priorTotalLiquidity[i], weights[i]);
            console.log("expectedCumulativeRewards = %s", expectedCumulativeRewards);
            assertApproxEqRel(
                cumulativeRewards,
                expectedCumulativeRewards,
                5e16, // 5%, accounts for reduction factor
                "Incorrect cumulative rewards"
            );
            expectedAccruedRewards += cumulativeRewards.wadMul(balances[i]).wadMul(multipliers[i]);
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
        uint256 marketWeight = rewardDistributor.getRewardWeight(token, market);
        return _calcExpectedCumulativeRewards(token, skipTime, totalLiquidity, marketWeight);
    }

    function _calcExpectedCumulativeRewards(
        address token,
        uint256 skipTime,
        uint256 totalLiquidity,
        uint256 marketWeight
    ) internal view returns (uint256) {
        if (totalLiquidity == 0) return 0;
        uint256 inflationRate = rewardDistributor.getInflationRate(token);
        uint256 weightedAnnualInflationRate = inflationRate * marketWeight / 10000; // basis points
        uint256 weightedInflation = weightedAnnualInflationRate * skipTime / 365 days;
        return weightedInflation.wadDiv(totalLiquidity);
    }

    /* ***************** */
    /*   Error Helpers   */
    /* ***************** */

    function _expectStakedTokenCallerIsNotSafetyModule(address caller) internal {
        vm.expectRevert(abi.encodeWithSignature("StakedToken_CallerIsNotSafetyModule(address)", caller));
    }

    function _expectAuctionModuleCallerIsNotSafetyModule(address caller) internal {
        vm.expectRevert(abi.encodeWithSignature("AuctionModule_CallerIsNotSafetyModule(address)", caller));
    }

    function _expectCallerIsNotStakedToken(address caller) internal {
        vm.expectRevert(abi.encodeWithSignature("SMRD_CallerIsNotStakedToken(address)", caller));
    }

    function _expectCallerIsNotAuctionModule(address caller) internal {
        vm.expectRevert(abi.encodeWithSignature("SafetyModule_CallerIsNotAuctionModule(address)", caller));
    }

    function _expectStakedTokenAlreadyRegistered(address token) internal {
        vm.expectRevert(abi.encodeWithSignature("SafetyModule_StakedTokenAlreadyRegistered(address)", token));
    }

    function _expectInvalidStakedToken(address token) internal {
        vm.expectRevert(abi.encodeWithSignature("SafetyModule_InvalidStakedToken(address)", token));
    }

    function _expectInsufficientSlashedTokensForAuction(address token, uint256 expected, uint256 actual) internal {
        vm.expectRevert(
            abi.encodeWithSignature(
                "SafetyModule_InsufficientSlashedTokensForAuction(address,uint256,uint256)", token, expected, actual
            )
        );
    }

    function _expectInvalidSlashPercentTooHigh() internal {
        vm.expectRevert(abi.encodeWithSignature("SafetyModule_InvalidSlashPercentTooHigh()"));
    }

    function _expectInvalidMaxMultiplierTooLow(uint256 value, uint256 min) internal {
        vm.expectRevert(abi.encodeWithSignature("SMRD_InvalidMaxMultiplierTooLow(uint256,uint256)", value, min));
    }

    function _expectInvalidMaxMultiplierTooHigh(uint256 value, uint256 max) internal {
        vm.expectRevert(abi.encodeWithSignature("SMRD_InvalidMaxMultiplierTooHigh(uint256,uint256)", value, max));
    }

    function _expectInvalidSmoothingValueTooLow(uint256 value, uint256 min) internal {
        vm.expectRevert(abi.encodeWithSignature("SMRD_InvalidSmoothingValueTooLow(uint256,uint256)", value, min));
    }

    function _expectInvalidSmoothingValueTooHigh(uint256 value, uint256 max) internal {
        vm.expectRevert(abi.encodeWithSignature("SMRD_InvalidSmoothingValueTooHigh(uint256,uint256)", value, max));
    }

    function _expectRewardDistributorInvalidZeroAddress() internal {
        vm.expectRevert(abi.encodeWithSignature("RewardDistributor_InvalidZeroAddress()"));
    }

    function _expectAlreadyInitializedStartTime(address market) internal {
        vm.expectRevert(abi.encodeWithSignature("RewardDistributor_AlreadyInitializedStartTime(address)", market));
    }

    function _expectStakedTokenInvalidZeroAmount() internal {
        vm.expectRevert(abi.encodeWithSignature("StakedToken_InvalidZeroAmount()"));
    }

    function _expectStakedTokenInvalidZeroAddress() internal {
        vm.expectRevert(abi.encodeWithSignature("StakedToken_InvalidZeroAddress()"));
    }

    function _expectZeroBalanceAtCooldown() internal {
        vm.expectRevert(abi.encodeWithSignature("StakedToken_ZeroBalanceAtCooldown()"));
    }

    function _expectAboveMaxStakeAmount(uint256 max, uint256 amount) internal {
        vm.expectRevert(abi.encodeWithSignature("StakedToken_AboveMaxStakeAmount(uint256,uint256)", max, amount));
    }

    function _expectInsufficientCooldown(uint256 endTime) internal {
        vm.expectRevert(abi.encodeWithSignature("StakedToken_InsufficientCooldown(uint256)", endTime));
    }

    function _expectUnstakeWindowFinished(uint256 endTime) internal {
        vm.expectRevert(abi.encodeWithSignature("StakedToken_UnstakeWindowFinished(uint256)", endTime));
    }

    function _expectZeroExchangeRate() internal {
        vm.expectRevert(abi.encodeWithSignature("StakedToken_ZeroExchangeRate()"));
    }

    function _expectSlashingDisabledInPostSlashingState() internal {
        vm.expectRevert(abi.encodeWithSignature("StakedToken_SlashingDisabledInPostSlashingState()"));
    }

    function _expectStakingDisabledInPostSlashingState() internal {
        vm.expectRevert(abi.encodeWithSignature("StakedToken_StakingDisabledInPostSlashingState()"));
    }

    function _expectNoStakingOnBehalf() internal {
        vm.expectRevert(abi.encodeWithSignature("StakedToken_NoStakingOnBehalfOfExistingStaker()"));
    }

    function _expectInvalidZeroArgument(uint256 argIdx) internal {
        vm.expectRevert(abi.encodeWithSignature("AuctionModule_InvalidZeroArgument(uint256)", argIdx));
    }

    function _expectInvalidZeroAddress(uint256 argIdx) internal {
        vm.expectRevert(abi.encodeWithSignature("AuctionModule_InvalidZeroAddress(uint256)", argIdx));
    }

    function _expectInvalidAuctionId(uint256 auctionId) internal {
        vm.expectRevert(abi.encodeWithSignature("AuctionModule_InvalidAuctionId(uint256)", auctionId));
    }

    function _expectNotEnoughLotsRemaining(uint256 auctionId, uint256 lotsRemaining) internal {
        vm.expectRevert(
            abi.encodeWithSignature("AuctionModule_NotEnoughLotsRemaining(uint256,uint256)", auctionId, lotsRemaining)
        );
    }

    function _expectAuctionStillActive(uint256 auctionId, uint256 endTime) internal {
        vm.expectRevert(
            abi.encodeWithSignature("AuctionModule_AuctionStillActive(uint256,uint256)", auctionId, endTime)
        );
    }

    function _expectAuctionNotActive(uint256 auctionId) internal {
        vm.expectRevert(abi.encodeWithSignature("AuctionModule_AuctionNotActive(uint256)", auctionId));
    }

    function _expectTokenAlreadyInAuction(address token) internal {
        vm.expectRevert(abi.encodeWithSignature("AuctionModule_TokenAlreadyInAuction(address)", token));
    }

    function _expectCannotReplacePaymentTokenActiveAuction() internal {
        vm.expectRevert(abi.encodeWithSignature("AuctionModule_CannotReplacePaymentTokenActiveAuction()"));
    }

    function _expectCannotReplaceAuctionModuleActiveAuction() internal {
        vm.expectRevert(abi.encodeWithSignature("SafetyModule_CannotReplaceAuctionModuleActiveAuction()"));
    }
}
