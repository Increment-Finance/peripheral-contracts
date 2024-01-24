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
import {console2 as console} from "forge/console2.sol";

contract BalancerPoolHandler is Test {
    using PRBMathUD60x18 for uint256;

    IBalancerVault public balancerVault;
    IWeightedPool[] public pools;
    IWETH public weth;

    address[] public actors;

    address internal currentActor;

    IWeightedPool internal currentPool;
    bytes32 internal currentPoolId;

    mapping(address => mapping(address => uint256))
        internal userBalancesByToken;

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

        uint256[] memory internalBalances = balancerVault.getInternalBalance(
            currentActor,
            poolERC20s
        );
        for (uint i; i < numTokens; i++) {
            userBalancesByToken[currentActor][
                address(poolERC20s[i])
            ] = internalBalances[i];
        }
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

        uint256[] memory internalBalances = balancerVault.getInternalBalance(
            currentActor,
            poolERC20s
        );
        for (uint i; i < poolERC20s.length; i++) {
            userBalancesByToken[currentActor][
                address(poolERC20s[i])
            ] = internalBalances[i];
        }
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

        uint256[] memory internalBalances = balancerVault.getInternalBalance(
            currentActor,
            poolERC20s
        );
        for (uint i; i < poolERC20s.length; i++) {
            userBalancesByToken[currentActor][
                address(poolERC20s[i])
            ] = internalBalances[i];
        }
    }

    function exitPoolExactTokensOut(
        uint256 actorIndexSeed,
        uint256 poolIndexSeed,
        uint256 maxAmountIn,
        uint256[8] memory minAmountsOut
    ) external useActor(actorIndexSeed) usePool(poolIndexSeed) {
        uint256 bptBalance = currentPool.balanceOf(currentActor);
        if (bptBalance == 0) return;
        maxAmountIn = bound(maxAmountIn, bptBalance / 100, bptBalance);
        (
            IERC20[] memory poolERC20s,
            uint256[] memory balances,
            uint256 lastChangeBlock
        ) = balancerVault.getPoolTokens(currentPoolId);
        IAsset[] memory poolAssets = new IAsset[](poolERC20s.length);
        uint256[] memory minAmounts = new uint256[](poolERC20s.length);
        for (uint i; i < poolERC20s.length; i++) {
            poolAssets[i] = IAsset(address(poolERC20s[i]));
            minAmounts[i] = bound(
                minAmountsOut[i],
                poolERC20s[i].balanceOf(address(currentPool)) / 100,
                poolERC20s[i].balanceOf(address(currentPool)) / 10
            );
        }
        bytes memory userData = abi.encode(
            ExitKind.BPT_IN_FOR_EXACT_TOKENS_OUT,
            minAmounts,
            maxAmountIn
        );
        (uint256 bptIn, ) = currentPool.queryExit(
            currentPoolId,
            currentActor,
            currentActor,
            balances,
            lastChangeBlock,
            balancerVault.getProtocolFeesCollector().getSwapFeePercentage(),
            userData
        );
        if (currentPool.balanceOf(currentActor) < bptIn) {
            vm.expectRevert();
        } else {
            currentPool.approve(address(balancerVault), (bptIn * 6) / 5);
        }

        balancerVault.exitPool(
            currentPoolId,
            currentActor,
            payable(currentActor),
            IBalancerVault.ExitPoolRequest(
                poolAssets,
                minAmounts,
                userData,
                false
            )
        );

        uint256[] memory internalBalances = balancerVault.getInternalBalance(
            currentActor,
            poolERC20s
        );
        for (uint i; i < poolERC20s.length; i++) {
            userBalancesByToken[currentActor][
                address(poolERC20s[i])
            ] = internalBalances[i];
        }
    }

    function exitPoolExactBptIn(
        uint256 actorIndexSeed,
        uint256 poolIndexSeed,
        uint256 bptAmountIn
    ) external useActor(actorIndexSeed) usePool(poolIndexSeed) {
        uint256 bptBalance = currentPool.balanceOf(currentActor);
        if (bptBalance == 0) return;
        bptAmountIn = bound(bptAmountIn, bptBalance / 100, bptBalance);
        (
            IERC20[] memory poolERC20s,
            uint256[] memory balances,
            uint256 lastChangeBlock
        ) = balancerVault.getPoolTokens(currentPoolId);
        IAsset[] memory poolAssets = new IAsset[](poolERC20s.length);
        for (uint i; i < poolERC20s.length; i++) {
            poolAssets[i] = IAsset(address(poolERC20s[i]));
        }
        bytes memory userData = abi.encode(
            ExitKind.EXACT_BPT_IN_FOR_TOKENS_OUT,
            bptAmountIn
        );
        (, uint256[] memory amountsOut) = currentPool.queryExit(
            currentPoolId,
            currentActor,
            currentActor,
            balances,
            lastChangeBlock,
            balancerVault.getProtocolFeesCollector().getSwapFeePercentage(),
            userData
        );
        for (uint i; i < amountsOut.length; i++) {
            amountsOut[i] = (amountsOut[i] * 4) / 5;
        }
        currentPool.approve(address(balancerVault), bptAmountIn);

        balancerVault.exitPool(
            currentPoolId,
            currentActor,
            payable(currentActor),
            IBalancerVault.ExitPoolRequest(
                poolAssets,
                amountsOut,
                userData,
                false
            )
        );

        uint256[] memory internalBalances = balancerVault.getInternalBalance(
            currentActor,
            poolERC20s
        );
        for (uint i; i < poolERC20s.length; i++) {
            userBalancesByToken[currentActor][
                address(poolERC20s[i])
            ] = internalBalances[i];
        }
    }

    function singleSwapGivenIn(
        uint256 actorIndexSeed,
        uint256 poolIndexSeed,
        uint256 amountIn,
        bool firstAssetIn
    ) external useActor(actorIndexSeed) usePool(poolIndexSeed) {
        amountIn = bound(amountIn, 0.01 ether, 1 ether);
        IBalancerVault.SwapKind swapKind = IBalancerVault.SwapKind.GIVEN_IN;
        IBalancerVault.FundManagement memory funds = IBalancerVault
            .FundManagement({
                sender: currentActor,
                fromInternalBalance: false,
                recipient: payable(currentActor),
                toInternalBalance: false
            });
        (IERC20[] memory poolERC20s, , ) = balancerVault.getPoolTokens(
            currentPoolId
        );
        IAsset assetIn = IAsset(address(poolERC20s[firstAssetIn ? 0 : 1]));
        IAsset assetOut = IAsset(address(poolERC20s[firstAssetIn ? 1 : 0]));
        IBalancerVault.SingleSwap memory singleSwap = IBalancerVault
            .SingleSwap({
                poolId: currentPoolId,
                kind: swapKind,
                assetIn: assetIn,
                assetOut: assetOut,
                amount: amountIn,
                userData: new bytes(0)
            });

        deal(address(assetIn), currentActor, amountIn);
        poolERC20s[firstAssetIn ? 0 : 1].approve(
            address(balancerVault),
            amountIn
        );

        balancerVault.swap(singleSwap, funds, 0, block.timestamp + 1 hours);

        uint256[] memory internalBalances = balancerVault.getInternalBalance(
            currentActor,
            poolERC20s
        );
        for (uint i; i < poolERC20s.length; i++) {
            userBalancesByToken[currentActor][
                address(poolERC20s[i])
            ] = internalBalances[i];
        }
    }

    function manageUserBalance(
        uint256 actorIndexSeedSender,
        uint256 actorIndexSeedReceiver,
        uint256 poolIndexSeed,
        uint256[5] memory assetKindSeeds,
        uint256[5] memory amounts,
        uint256 numOps
    ) external useActor(actorIndexSeedSender) usePool(poolIndexSeed) {
        console.log("manageUserBalance");
        address receiver = actors[
            bound(actorIndexSeedReceiver, 0, actors.length - 1)
        ];
        numOps = bound(numOps, 1, 5);

        IBalancerVault.UserBalanceOp[]
            memory ops = new IBalancerVault.UserBalanceOp[](numOps);
        (IERC20[] memory poolERC20s, , ) = balancerVault.getPoolTokens(
            currentPoolId
        );
        for (uint256 i; i < numOps; i++) {
            IERC20 token = poolERC20s[
                bound(assetKindSeeds[i], 0, poolERC20s.length - 1)
            ];
            IAsset asset = IAsset(address(token));
            IBalancerVault.UserBalanceOpKind kind = IBalancerVault
                .UserBalanceOpKind(bound(assetKindSeeds[i], 0, 3));
            uint256 amount;
            if (kind == IBalancerVault.UserBalanceOpKind.DEPOSIT_INTERNAL) {
                amount = bound(amounts[i], 0.1 ether, 10 ether);
                deal(
                    address(asset),
                    currentActor,
                    amount + token.balanceOf(currentActor)
                );
                uint256 allowance = token.allowance(
                    currentActor,
                    address(balancerVault)
                );
                if (allowance < amount)
                    token.approve(address(balancerVault), amount + allowance);
                userBalancesByToken[receiver][address(token)] += amount;
            } else {
                uint256 userBalance = userBalancesByToken[currentActor][
                    address(token)
                ];
                amount = bound(amounts[i], userBalance / 50, userBalance / 10);
                userBalancesByToken[currentActor][address(token)] -= amount;
                if (
                    kind == IBalancerVault.UserBalanceOpKind.TRANSFER_INTERNAL
                ) {
                    userBalancesByToken[receiver][address(token)] += amount;
                }
            }
            ops[i] = IBalancerVault.UserBalanceOp({
                kind: kind,
                asset: asset,
                amount: amount,
                sender: currentActor,
                recipient: payable(receiver)
            });
        }

        balancerVault.manageUserBalance(ops);

        uint256[] memory internalBalances = balancerVault.getInternalBalance(
            currentActor,
            poolERC20s
        );
        for (uint i; i < poolERC20s.length; i++) {
            userBalancesByToken[currentActor][
                address(poolERC20s[i])
            ] = internalBalances[i];
        }
    }
}
