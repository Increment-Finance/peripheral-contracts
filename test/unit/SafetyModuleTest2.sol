// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.16;

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
        safetyModule = new TestSafetyModule(address(0), address(0), address(this));

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

        // Transfer tokens back to user 1 and check that their position is updated
        vm.startPrank(liquidityProviderTwo);
        stakedToken1.transfer(liquidityProviderOne, stakeAmount);
        vm.stopPrank();
        assertEq(
            rewardDistributor.lpPositionsPerUser(liquidityProviderOne, address(stakedToken1)),
            stakeAmount,
            "User 1 position mismatch after transfer"
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
