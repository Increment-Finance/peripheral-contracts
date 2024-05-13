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

        // test no staking on behalf of staker
        uint256 govBalance = rewardsToken.balanceOf(address(this));
        rewardsToken.approve(address(stakedToken1), govBalance);
        _expectNoStakingOnBehalf();
        stakedToken1.stakeOnBehalfOf(liquidityProviderOne, govBalance);

        // test above max stake amount
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
        vm.stopPrank();
        // stake on behalf of user 2, then try transferring to user 1, expecting it to fail
        stakedToken1.stakeOnBehalfOf(liquidityProviderTwo, govBalance);
        uint256 user2Balance = stakedToken1.balanceOf(liquidityProviderTwo);
        vm.startPrank(liquidityProviderTwo);
        _expectAboveMaxStakeAmount(MAX_STAKE_AMOUNT_1, 0);
        stakedToken1.transfer(liquidityProviderOne, user2Balance);
        // change max stake amount and try again, expecting it to succeed
        vm.stopPrank();
        stakedToken1.setMaxStakeAmount(type(uint256).max);
        vm.startPrank(liquidityProviderTwo);
        vm.expectEmit(false, false, false, true);
        emit Transfer(liquidityProviderTwo, liquidityProviderOne, user2Balance);
        stakedToken1.transfer(liquidityProviderOne, user2Balance);
        // transfer the amount back so that subsequent tests work
        vm.startPrank(liquidityProviderOne);
        stakedToken1.transfer(liquidityProviderTwo, user2Balance);

        // test insufficient cooldown
        stakedToken1.cooldown();
        uint256 cooldownStartTimestamp = stakedToken1.getCooldownStartTime(liquidityProviderOne);
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
