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

        // Deploy safety module
        safetyModule = new SafetyModule(
            address(vault),
            address(0),
            new IStakedToken[](0),
            // INITIAL_MAX_MULTIPLIER,
            // INITIAL_SMOOTHING_VALUE,
            INITIAL_INFLATION_RATE,
            INITIAL_REDUCTION_FACTOR,
            address(rewardsToken),
            address(clearingHouse),
            address(rewardVault),
            10 days,
            new uint16[](0)
        );
        safetyModule.setMaxRewardMultiplier(INITIAL_MAX_MULTIPLIER);
        safetyModule.setSmoothingValue(INITIAL_SMOOTHING_VALUE);

        // Transfer half of the rewards tokens to the vault
        rewardsToken.transfer(
            address(rewardVault),
            rewardsToken.totalSupply() / 2
        );
        rewardVault.approve(
            AaveIERC20(address(rewardsToken)),
            address(safetyModule),
            type(uint256).max
        );

        // Deploy Balancer pool
        console.log("Deploying Balancer pool");
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
        console.log("Calling weightedPoolFactory.create()");
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
        console.log("Balancer pool deployed at %s", address(balancerPool));

        // Add liquidity to the Balancer pool
        bytes32 poolId = balancerPool.getPoolId();
        IBalancerVault balancerVault = balancerPool.getVault();
        (IERC20[] memory poolERC20s, , ) = balancerVault.getPoolTokens(poolId);
        IAsset[] memory poolAssets = new IAsset[](2);
        poolAssets[0] = IAsset(address(poolERC20s[0]));
        poolAssets[1] = IAsset(address(poolERC20s[1]));
        uint256[] memory maxAmountsIn = new uint256[](2);
        if (poolAssets[0] == IAsset(address(rewardsToken))) {
            maxAmountsIn[0] = 10_000 ether;
            maxAmountsIn[1] = 10 ether;
        } else {
            maxAmountsIn[0] = 10 ether;
            maxAmountsIn[1] = 10_000 ether;
        }
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
        console.log("Calling balancerVault.joinPool()");
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
        safetyModule.updateRewardWeights(address(rewardsToken), rewardWeights);
    }

    function testDeployment() public {}
}
