// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.16;

// contracts
import {Test} from "../../../lib/increment-protocol/lib/forge-std/src/Test.sol";

// interfaces
import {IBalancerPoolToken, IWeightedPool, IWETH, JoinKind, ExitKind} from "../../balancer/IWeightedPool.sol";
import {IAsset, IVault as IBalancerVault} from "../../balancer/IWeightedPoolFactory.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20} from "../../../lib/increment-protocol/lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

// libraries
import {PRBMathUD60x18} from "../../../lib/increment-protocol/lib/prb-math/contracts/PRBMathUD60x18.sol";

contract BalancerPoolHandler is Test {
    using PRBMathUD60x18 for uint256;

    IBalancerVault public balancerVault;
    IWeightedPool[] public pools;
    IWETH public weth;

    address[] public actors;

    address internal currentActor;

    IWeightedPool internal currentPool;
    bytes32 internal currentPoolId;

    modifier useActor(uint256 actorIndexSeed) {
        currentActor = actors[bound(actorIndexSeed, 0, actors.length - 1)];
        vm.startPrank(currentActor);
        _;
        vm.stopPrank();
    }

    modifier usePool(uint256 poolIndexSeed) {
        currentPool = pools[bound(poolIndexSeed, 0, pools.length - 1)];
        currentPoolId = currentPool.getPoolId();
        _;
    }

    constructor(
        IBalancerVault _balancerVault,
        IWeightedPool[] memory _pools,
        IWETH _weth,
        address[] memory _actors
    ) {
        balancerVault = _balancerVault;
        pools = _pools;
        weth = _weth;
        actors = _actors;
    }

    /* ********************* */
    /* Test Helper Functions */
    /* ********************* */

    function dealWETH(
        uint256 amount,
        uint256 actorIndexSeed
    ) external useActor(actorIndexSeed) {
        amount = bound(amount, 0.1e18, 1_000e18);
        deal(currentActor, amount);
        weth.approve(address(balancerVault), amount);
        weth.deposit{value: amount}();
    }

    /* ******************** */
    /*  External Functions  */
    /* ******************** */

    function joinPoolExactTokensIn(
        uint256 actorIndexSeed,
        uint256 poolIndexSeed,
        uint256[8] memory maxAmountsIn
    ) external useActor(actorIndexSeed) usePool(poolIndexSeed) {
        bytes32 poolId = currentPool.getPoolId();
        (IERC20[] memory poolERC20s, , ) = balancerVault.getPoolTokens(poolId);
        uint256 numTokens = poolERC20s.length;
        IAsset[] memory poolAssets = new IAsset[](numTokens);
        uint256[] memory maxAmounts = new uint256[](numTokens);
        for (uint i; i < numTokens; i++) {
            poolAssets[i] = IAsset(address(poolERC20s[i]));
            if (address(poolERC20s[i]) == address(weth) && i != 0)
                maxAmounts[i] = bound(
                    maxAmountsIn[i],
                    maxAmounts[0] / 1000,
                    maxAmounts[0] / 10
                );
            else maxAmounts[i] = bound(maxAmountsIn[i], 100e18, 1_000_000e18);
            poolERC20s[i].approve(address(balancerVault), maxAmounts[i]);
            deal(address(poolERC20s[i]), currentActor, maxAmounts[i]);
        }
        balancerVault.joinPool(
            poolId,
            currentActor,
            currentActor,
            IBalancerVault.JoinPoolRequest(
                poolAssets,
                maxAmounts,
                abi.encode(JoinKind.EXACT_TOKENS_IN_FOR_BPT_OUT, maxAmounts),
                false
            )
        );
    }

    function joinPoolSingleTokenIn(
        uint256 actorIndexSeed,
        uint256 poolIndexSeed,
        uint256 estBptOut
    ) external useActor(actorIndexSeed) usePool(poolIndexSeed) {
        estBptOut = bound(estBptOut, 0.1 ether, 10 ether);
        (
            IERC20[] memory poolERC20s,
            uint256[] memory balances,
            uint256 lastChangeBlock
        ) = balancerVault.getPoolTokens(currentPoolId);
        IAsset[] memory poolAssets = new IAsset[](poolERC20s.length);
        bytes memory userData = abi.encode(
            JoinKind.TOKEN_IN_FOR_EXACT_BPT_OUT,
            estBptOut,
            0
        );
        (uint256 bptAmountOut, uint256[] memory amountsIn) = currentPool
            .queryJoin(
                currentPoolId,
                currentActor,
                currentActor,
                balances,
                lastChangeBlock,
                balancerVault.getProtocolFeesCollector().getSwapFeePercentage(),
                userData
            );
        for (uint i; i < poolERC20s.length; i++) {
            poolAssets[i] = IAsset(address(poolERC20s[i]));
            amountsIn[i] = (amountsIn[i] * 6) / 5;
            poolERC20s[i].approve(address(balancerVault), amountsIn[i]);
            deal(address(poolERC20s[i]), currentActor, amountsIn[i]);
        }

        balancerVault.joinPool(
            currentPoolId,
            currentActor,
            currentActor,
            IBalancerVault.JoinPoolRequest(
                poolAssets,
                amountsIn,
                abi.encode(
                    JoinKind.TOKEN_IN_FOR_EXACT_BPT_OUT,
                    bptAmountOut / 2,
                    0
                ),
                false
            )
        );
    }

    function joinPoolProportional(
        uint256 actorIndexSeed,
        uint256 poolIndexSeed,
        uint256 estBptOut
    ) external useActor(actorIndexSeed) usePool(poolIndexSeed) {
        estBptOut = bound(estBptOut, 0.1 ether, 10 ether);
        (
            IERC20[] memory poolERC20s,
            uint256[] memory balances,
            uint256 lastChangeBlock
        ) = balancerVault.getPoolTokens(currentPoolId);
        IAsset[] memory poolAssets = new IAsset[](poolERC20s.length);
        bytes memory userData = abi.encode(
            JoinKind.ALL_TOKENS_IN_FOR_EXACT_BPT_OUT,
            estBptOut
        );
        (uint256 bptAmountOut, uint256[] memory amountsIn) = currentPool
            .queryJoin(
                currentPoolId,
                currentActor,
                currentActor,
                balances,
                lastChangeBlock,
                balancerVault.getProtocolFeesCollector().getSwapFeePercentage(),
                userData
            );

        for (uint i; i < poolERC20s.length; i++) {
            poolAssets[i] = IAsset(address(poolERC20s[i]));
            amountsIn[i] = (amountsIn[i] * 6) / 5;
            poolERC20s[i].approve(address(balancerVault), amountsIn[i]);
            deal(address(poolERC20s[i]), currentActor, amountsIn[i]);
        }

        userData = abi.encode(
            JoinKind.ALL_TOKENS_IN_FOR_EXACT_BPT_OUT,
            bptAmountOut
        );

        balancerVault.joinPool(
            currentPoolId,
            currentActor,
            currentActor,
            IBalancerVault.JoinPoolRequest(
                poolAssets,
                amountsIn,
                abi.encode(
                    JoinKind.ALL_TOKENS_IN_FOR_EXACT_BPT_OUT,
                    bptAmountOut
                ),
                false
            )
        );
    }
}
