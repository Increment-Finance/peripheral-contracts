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
import {EcosystemReserve} from "../../contracts/EcosystemReserve.sol";
import {ERC20PresetFixedSupply, IERC20} from "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetFixedSupply.sol";
import {StakedTokenHandler} from "./handlers/StakedTokenHandler.sol";
import {StakedBPTHandler} from "./handlers/StakedBPTHandler.sol";
import {SMRDHandler} from "./handlers/SMRDHandler.sol";

// interfaces
import {IBalancerPoolToken, IWeightedPool, IWETH, JoinKind} from "../balancer/IWeightedPool.sol";
import {IWeightedPoolFactory, IAsset, IVault as IBalancerVault} from "../balancer/IWeightedPoolFactory.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

// libraries
import {LibMath} from "increment-protocol/lib/LibMath.sol";
import {Test} from "forge/Test.sol";
import {console2 as console} from "forge/console2.sol";

contract SafetyModuleInvariantTest is Test {
    using LibMath for int256;
    using LibMath for uint256;

    /* fork */
    uint256 public mainnetFork;

    /* fork addresses */
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    uint88 constant INITIAL_INFLATION_RATE = 1463753e18;
    uint88 constant INITIAL_REDUCTION_FACTOR = 1.189207115e18;
    uint256 constant INITIAL_MAX_USER_LOSS = 0.5e18;
    uint256 constant INITIAL_MAX_MULTIPLIER = 4e18;
    uint256 constant INITIAL_SMOOTHING_VALUE = 30e18;
    uint256 constant COOLDOWN_SECONDS = 1 days;
    uint256 constant UNSTAKE_WINDOW = 10 days;
    uint256 constant MAX_STAKE_AMOUNT_1 = 1_000_000e18;
    uint256 constant MAX_STAKE_AMOUNT_2 = 100_000e18;

    // Actors
    address stakerOne = address(123);
    address stakerTwo = address(456);
    address stakerThree = address(789);
    address[] stakers = [stakerOne, stakerTwo, stakerThree];

    // Tokens
    IncrementToken public rewardsToken;
    IERC20Metadata public usdc;
    IWETH public weth;
    StakedToken public stakedToken1;
    StakedToken public stakedToken2;
    StakedToken[] public stakedTokens;

    // Safety Module contracts
    EcosystemReserve public rewardVault;
    SafetyModule public safetyModule;
    AuctionModule public auctionModule;
    TestSMRewardDistributor public rewardDistributor;

    // Balancer contracts
    IWeightedPoolFactory public weightedPoolFactory;
    IWeightedPool public balancerPool;
    IBalancerVault public balancerVault;
    bytes32 public poolId;
    IAsset[] public poolAssets;

    // Handler contracts
    SMRDHandler public smrdHandler;
    StakedTokenHandler public stakedTokenHandler1;
    StakedBPTHandler public stakedTokenHandler2;
    StakedTokenHandler[] public stakedTokenHandlers;

    // Invariant ghost variables
    mapping(address => mapping(address => uint256))
        public lastMarketAccumulatorValue;

    mapping(address => mapping(address => mapping(address => uint256)))
        public lastUserAccumulatorValue;

    mapping(address => mapping(address => uint256))
        public lastUserRewardsBalance;

    mapping(address => mapping(address => uint256))
        public lastUserRewardsAccrued;

    function setUp() public virtual {
        /* initialize fork */
        vm.createFork(vm.envString("MAINNET_RPC_URL"));
        vm.selectFork(mainnetFork);

        deal(stakerOne, 100 ether);
        deal(stakerTwo, 100 ether);
        deal(stakerThree, 100 ether);
        deal(address(this), 100 ether);

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
        stakedTokens = [stakedToken1, stakedToken2];

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
        vm.startPrank(stakerOne);
        rewardsToken.approve(address(stakedToken1), type(uint256).max);
        balancerPool.approve(address(stakedToken2), type(uint256).max);
        rewardsToken.approve(address(balancerVault), type(uint256).max);
        weth.approve(address(balancerVault), type(uint256).max);
        vm.startPrank(stakerTwo);
        rewardsToken.approve(address(stakedToken1), type(uint256).max);
        balancerPool.approve(address(stakedToken2), type(uint256).max);
        rewardsToken.approve(address(balancerVault), type(uint256).max);
        weth.approve(address(balancerVault), type(uint256).max);
        vm.startPrank(stakerThree);
        rewardsToken.approve(address(stakedToken1), type(uint256).max);
        balancerPool.approve(address(stakedToken2), type(uint256).max);
        rewardsToken.approve(address(balancerVault), type(uint256).max);
        weth.approve(address(balancerVault), type(uint256).max);
        vm.stopPrank();

        // Deposit ETH to WETH for users
        vm.startPrank(stakerOne);
        weth.deposit{value: 10 ether}();
        vm.startPrank(stakerTwo);
        weth.deposit{value: 10 ether}();
        vm.startPrank(stakerThree);
        weth.deposit{value: 10 ether}();
        vm.stopPrank();

        // Deploy handler contracts
        smrdHandler = new SMRDHandler(rewardDistributor, stakers);
        stakedTokenHandler1 = new StakedTokenHandler(stakedToken1, stakers);
        stakedTokenHandler2 = new StakedBPTHandler(
            stakedToken2,
            stakers,
            balancerVault,
            poolAssets,
            poolId
        );
        stakedTokenHandlers = [stakedTokenHandler1, stakedTokenHandler2];

        // Set handlers as target contracts
        targetContract(address(smrdHandler));
        targetContract(address(stakedTokenHandler1));
        targetContract(address(stakedTokenHandler2));
    }

    /* ****************** */
    /*     Invariants     */
    /* ****************** */

    function invariantMarketAccumulatorNeverDecreases() public {
        uint256 numRewards = rewardDistributor.getRewardTokenCount();
        uint256 numMarkets = safetyModule.getNumStakingTokens();
        for (uint256 i; i < numRewards; i++) {
            address rewardToken = rewardDistributor.rewardTokens(i);
            for (uint j; j < numMarkets; j++) {
                address market = address(safetyModule.stakingTokens(j));
                uint256 accumulatorValue = rewardDistributor
                    .cumulativeRewardPerLpToken(rewardToken, market);
                assertGe(
                    accumulatorValue,
                    lastMarketAccumulatorValue[rewardToken][market],
                    "Invariant: accumulator does not decrease"
                );
                lastMarketAccumulatorValue[rewardToken][
                    market
                ] = accumulatorValue;
            }
        }
    }

    function invariantUserAccumulatorUpdatesOnAccrual() public {
        uint256 numRewards = rewardDistributor.getRewardTokenCount();
        uint256 numMarkets = safetyModule.getNumStakingTokens();
        for (uint256 i; i < numRewards; i++) {
            address rewardToken = rewardDistributor.rewardTokens(i);
            for (uint j; j < numMarkets; j++) {
                address market = address(safetyModule.stakingTokens(j));
                uint256 marketAccumulatorValue = rewardDistributor
                    .cumulativeRewardPerLpToken(rewardToken, market);
                for (uint k; k < stakers.length; k++) {
                    address staker = stakers[k];
                    uint256 userAccumulatorValue = rewardDistributor
                        .cumulativeRewardPerLpTokenPerUser(
                            staker,
                            rewardToken,
                            market
                        );
                    assertGe(
                        userAccumulatorValue,
                        lastUserAccumulatorValue[staker][rewardToken][market],
                        "Invariant: user accumulator does not decrease"
                    );
                    lastUserAccumulatorValue[staker][rewardToken][
                        market
                    ] = userAccumulatorValue;
                    if (userAccumulatorValue == marketAccumulatorValue) {
                        uint256 rewardsAccrued = rewardDistributor
                            .rewardsAccruedByUser(staker, rewardToken);
                        uint256 rewardsBalance = IERC20(rewardToken).balanceOf(
                            staker
                        );
                        if (rewardsAccrued > 0) {
                            assertGe(
                                rewardsAccrued,
                                lastUserRewardsAccrued[staker][rewardToken],
                                "Invariant: user accumulator updates on reward accrual"
                            );
                        } else {
                            assertGe(
                                rewardsBalance,
                                lastUserRewardsBalance[staker][rewardToken],
                                "Invariant: user accumulator updates on claim rewards"
                            );
                        }
                        lastUserRewardsAccrued[staker][
                            rewardToken
                        ] = rewardsAccrued;
                        lastUserRewardsBalance[staker][
                            rewardToken
                        ] = rewardsBalance;
                    }
                }
            }
        }
        skip(1 days);
    }

    function invariantStakerPositionsMatch() public {
        uint256 numMarkets = safetyModule.getNumStakingTokens();
        for (uint256 i; i < numMarkets; i++) {
            IStakedToken stakedToken = safetyModule.stakingTokens(i);
            address market = address(stakedToken);
            for (uint256 j; j < stakers.length; j++) {
                address staker = stakers[j];
                assertEq(
                    rewardDistributor.lpPositionsPerUser(staker, market),
                    stakedToken.balanceOf(staker),
                    "Invariant: staker positions always match in StakedToken and SMRewardDistributor"
                );
            }
        }
    }

    function invariantTotalLiquidityMatches() public {
        uint256 numMarkets = safetyModule.getNumStakingTokens();
        for (uint256 i; i < numMarkets; i++) {
            IStakedToken stakedToken = safetyModule.stakingTokens(i);
            address market = address(stakedToken);
            assertEq(
                rewardDistributor.totalLiquidityPerMarket(market),
                stakedToken.totalSupply(),
                "Invariant: total liquidity always matches in StakedToken and SMRewardDistributor"
            );
        }
    }

    function invariantSumOfAccruedRewardsUnclaimed() public {
        uint256 numRewards = rewardDistributor.getRewardTokenCount();
        for (uint i; i < numRewards; i++) {
            address rewardToken = rewardDistributor.rewardTokens(i);
            uint256 totalUnclaimedRewards = rewardDistributor
                .totalUnclaimedRewards(rewardToken);
            uint256 sumOfAccruedRewards;
            for (uint j; j < stakers.length; j++) {
                address staker = stakers[j];
                sumOfAccruedRewards += rewardDistributor.rewardsAccruedByUser(
                    staker,
                    rewardToken
                );
            }
            assertEq(
                totalUnclaimedRewards,
                sumOfAccruedRewards,
                "Invariant: sum of accrued rewards equals total unclaimed rewards"
            );
        }
    }

    function invariantExchangeRates() public {
        for (uint256 i; i < stakedTokens.length; i++) {
            StakedToken stakedToken = stakedTokens[i];
            uint256 underlyingBalance = stakedToken
                .getUnderlyingToken()
                .balanceOf(address(stakedToken));

            assertEq(
                underlyingBalance,
                stakedToken.totalSupply().wadMul(stakedToken.exchangeRate()),
                "Invariant: exchange rate equals underlying balance / total supply"
            );
        }
    }

    /* ****************** */
    /*  Helper Functions  */
    /* ****************** */
}
