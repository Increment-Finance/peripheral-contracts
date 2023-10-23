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
import "../src/SafetyModule.sol";
import "../src/StakedToken.sol";
import {EcosystemReserve, IERC20 as AaveIERC20} from "../src/EcosystemReserve.sol";

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
import {IBalancerPoolToken, IWeightedPool, IWETH, JoinKind} from "../src/interfaces/balancer/IWeightedPool.sol";
import {IWeightedPoolFactory, IAsset, IVault as IBalancerVault} from "../src/interfaces/balancer/IWeightedPoolFactory.sol";

// libraries
import "increment-protocol/lib/LibMath.sol";
import "increment-protocol/lib/LibPerpetual.sol";
import {console2 as console} from "forge/console2.sol";

contract SafetyModuleTest is PerpetualUtils {
    using LibMath for int256;
    using LibMath for uint256;

    uint256 constant INITIAL_INFLATION_RATE = 1463753e18;
    uint256 constant INITIAL_REDUCTION_FACTOR = 1.189207115e18;
    uint256 constant INITIAL_MAX_USER_LOSS = 0.5e18;
    uint256 constant INITIAL_MAX_MULTIPLIER = 4e18;
    uint256 constant INITIAL_SMOOTHING_VALUE = 30e18;

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
        rewardsToken = new IncrementToken(20000000e18, address(this));
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
            1 days,
            10 days,
            "Staked INCR",
            "stINCR"
        );
        stakedToken2 = new StakedToken(
            balancerPool,
            safetyModule,
            1 days,
            10 days,
            "Staked 50INCR-50WETH BPT",
            "stIBPT"
        );

        // Register staking tokens with safety module
        safetyModule.addStakingToken(stakedToken1);
        safetyModule.addStakingToken(stakedToken2);
        uint16[] memory rewardWeights = new uint16[](2);
        rewardWeights[0] = 5000;
        rewardWeights[1] = 5000;
        safetyModule.addRewardToken(
            address(rewardsToken),
            INITIAL_INFLATION_RATE,
            INITIAL_REDUCTION_FACTOR,
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
            safetyModule.getAllowlistIdx(0),
            0,
            "Allowlist index mismatch"
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

    function testPreExistingBalance(uint256 maxTokenAmountIntoBalancer) public {
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
        uint16[] memory rewardWeights = new uint16[](2);
        rewardWeights[0] = 5000;
        rewardWeights[1] = 5000;
        newSafetyModule.addRewardToken(
            address(rewardsToken),
            INITIAL_INFLATION_RATE,
            INITIAL_REDUCTION_FACTOR,
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
                "RewardDistributor_LpPositionMismatch(address,uint256,uint256,uint256)",
                liquidityProviderTwo,
                0,
                0,
                stakedToken1.balanceOf(liquidityProviderTwo)
            )
        );
        newSafetyModule.viewNewRewardAccrual(0, liquidityProviderTwo);
        console.log("expecting accrueRewards to fail");
        vm.expectRevert(
            abi.encodeWithSignature(
                "RewardDistributor_LpPositionMismatch(address,uint256,uint256,uint256)",
                liquidityProviderTwo,
                0,
                0,
                stakedToken1.balanceOf(liquidityProviderTwo)
            )
        );
        newSafetyModule.accrueRewards(liquidityProviderTwo);
    }

    function testSafetyModuleErrors(
        uint256 highMaxUserLoss,
        uint256 lowMaxMultiplier,
        uint256 highMaxMultiplier,
        uint256 lowSmoothingValue,
        uint256 highSmoothingValue,
        uint256 invalidMarketIdx,
        address invalidToken
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
            invalidToken != address(stakedToken1) &&
                invalidToken != address(stakedToken2)
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
                invalidToken
            )
        );
        safetyModule.getStakingTokenIdx(invalidToken);

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
        vm.expectRevert(
            abi.encodeWithSignature(
                "RewardDistributor_InvalidMarketIndex(uint256,uint256)",
                invalidMarketIdx,
                1
            )
        );
        safetyModule.getAllowlistIdx(invalidMarketIdx);
        vm.startPrank(address(stakedToken1));
        vm.expectRevert(
            abi.encodeWithSignature(
                "RewardDistributor_InvalidMarketIndex(uint256,uint256)",
                invalidMarketIdx,
                1
            )
        );
        safetyModule.updateStakingPosition(
            invalidMarketIdx,
            liquidityProviderOne
        );
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
        stakedToken.stake(staker, amount);
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
        stakedToken.redeem(staker, amount);
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
