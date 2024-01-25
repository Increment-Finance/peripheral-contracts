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

    mapping(address => mapping(address => uint256)) internal userBalancesByToken;

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

    constructor(IBalancerVault _balancerVault, IWeightedPool[] memory _pools, IWETH _weth, address[] memory _actors) {
        balancerVault = _balancerVault;
        pools = _pools;
        weth = _weth;
        actors = _actors;
    }

    /* ********************* */
    /* Test Helper Functions */
    /* ********************* */

    function dealWETH(uint256 amount, uint256 actorIndexSeed) external useActor(actorIndexSeed) {
        amount = bound(amount, 0.1e18, 1_000e18);
        deal(currentActor, amount);
        weth.approve(address(balancerVault), amount);
        weth.deposit{value: amount}();
    }

    /* ******************** */
    /*  External Functions  */
    /* ******************** */

    function joinPoolExactTokensIn(uint256 actorIndexSeed, uint256 poolIndexSeed, uint256[8] memory maxAmountsIn)
        external
        useActor(actorIndexSeed)
        usePool(poolIndexSeed)
    {
        bytes32 poolId = currentPool.getPoolId();
        (IERC20[] memory poolERC20s,,) = balancerVault.getPoolTokens(poolId);
        uint256 numTokens = poolERC20s.length;

        // Prepare pool assets and max amounts in for queryJoin
        IAsset[] memory poolAssets = new IAsset[](numTokens);
        uint256[] memory maxAmounts = new uint256[](numTokens);
        for (uint256 i; i < numTokens; i++) {
            poolAssets[i] = IAsset(address(poolERC20s[i]));
            // Bounds w/ special case for WETH
            if (address(poolERC20s[i]) == address(weth) && i != 0) {
                maxAmounts[i] = bound(maxAmountsIn[i], maxAmounts[0] / 1000, maxAmounts[0] / 10);
            } else {
                maxAmounts[i] = bound(maxAmountsIn[i], 100e18, 1_000_000e18);
            }
            // Approve and deal tokens to actor
            poolERC20s[i].approve(address(balancerVault), maxAmounts[i]);
            deal(address(poolERC20s[i]), currentActor, maxAmounts[i]);
        }

        // Join pool
        balancerVault.joinPool(
            poolId,
            currentActor,
            currentActor,
            IBalancerVault.JoinPoolRequest(
                poolAssets, maxAmounts, abi.encode(JoinKind.EXACT_TOKENS_IN_FOR_BPT_OUT, maxAmounts), false
            )
        );

        // Update local user vault balances
        uint256[] memory internalBalances = balancerVault.getInternalBalance(currentActor, poolERC20s);
        for (uint256 i; i < numTokens; i++) {
            userBalancesByToken[currentActor][address(poolERC20s[i])] = internalBalances[i];
        }
    }

    function joinPoolSingleTokenIn(uint256 actorIndexSeed, uint256 poolIndexSeed, uint256 estBptOut)
        external
        useActor(actorIndexSeed)
        usePool(poolIndexSeed)
    {
        // Bounds
        estBptOut = bound(estBptOut, 0.1 ether, 10 ether);

        // Get pool tokens and arguments for queryJoin
        (IERC20[] memory poolERC20s, uint256[] memory balances, uint256 lastChangeBlock) =
            balancerVault.getPoolTokens(currentPoolId);

        // Prepare pool assets and userData for queryJoin
        IAsset[] memory poolAssets = new IAsset[](poolERC20s.length);
        bytes memory userData = abi.encode(JoinKind.TOKEN_IN_FOR_EXACT_BPT_OUT, estBptOut, 0);

        // Get amounts in and bpt amount out from queryJoin
        (uint256 bptAmountOut, uint256[] memory amountsIn) = currentPool.queryJoin(
            currentPoolId,
            currentActor,
            currentActor,
            balances,
            lastChangeBlock,
            balancerVault.getProtocolFeesCollector().getSwapFeePercentage(),
            userData
        );

        // Apply 20% increase to estimates for max amounts in and deal tokens to actor
        for (uint256 i; i < poolERC20s.length; i++) {
            poolAssets[i] = IAsset(address(poolERC20s[i]));
            amountsIn[i] = (amountsIn[i] * 6) / 5;
            poolERC20s[i].approve(address(balancerVault), amountsIn[i]);
            deal(address(poolERC20s[i]), currentActor, amountsIn[i]);
        }

        // Join pool
        balancerVault.joinPool(
            currentPoolId,
            currentActor,
            currentActor,
            IBalancerVault.JoinPoolRequest(
                poolAssets, amountsIn, abi.encode(JoinKind.TOKEN_IN_FOR_EXACT_BPT_OUT, bptAmountOut / 2, 0), false
            )
        );

        // Update local user vault balances
        uint256[] memory internalBalances = balancerVault.getInternalBalance(currentActor, poolERC20s);
        for (uint256 i; i < poolERC20s.length; i++) {
            userBalancesByToken[currentActor][address(poolERC20s[i])] = internalBalances[i];
        }
    }

    function joinPoolProportional(uint256 actorIndexSeed, uint256 poolIndexSeed, uint256 estBptOut)
        external
        useActor(actorIndexSeed)
        usePool(poolIndexSeed)
    {
        // Bounds
        estBptOut = bound(estBptOut, 0.1 ether, 10 ether);

        // Get pool assets and arguments for queryJoin
        (IERC20[] memory poolERC20s, uint256[] memory balances, uint256 lastChangeBlock) =
            balancerVault.getPoolTokens(currentPoolId);

        // Prepare pool assets and userData for queryJoin
        IAsset[] memory poolAssets = new IAsset[](poolERC20s.length);
        bytes memory userData = abi.encode(JoinKind.ALL_TOKENS_IN_FOR_EXACT_BPT_OUT, estBptOut);

        // Get amounts in and bpt amount out from queryJoin
        (uint256 bptAmountOut, uint256[] memory amountsIn) = currentPool.queryJoin(
            currentPoolId,
            currentActor,
            currentActor,
            balances,
            lastChangeBlock,
            balancerVault.getProtocolFeesCollector().getSwapFeePercentage(),
            userData
        );

        // Apply 20% increase to estimates for max amounts in and deal tokens to actor
        for (uint256 i; i < poolERC20s.length; i++) {
            poolAssets[i] = IAsset(address(poolERC20s[i]));
            amountsIn[i] = (amountsIn[i] * 6) / 5;
            poolERC20s[i].approve(address(balancerVault), amountsIn[i]);
            deal(address(poolERC20s[i]), currentActor, amountsIn[i]);
        }

        // Prepare userData and join pool
        userData = abi.encode(JoinKind.ALL_TOKENS_IN_FOR_EXACT_BPT_OUT, bptAmountOut);
        balancerVault.joinPool(
            currentPoolId,
            currentActor,
            currentActor,
            IBalancerVault.JoinPoolRequest(
                poolAssets, amountsIn, abi.encode(JoinKind.ALL_TOKENS_IN_FOR_EXACT_BPT_OUT, bptAmountOut), false
            )
        );

        // Update local user vault balances
        uint256[] memory internalBalances = balancerVault.getInternalBalance(currentActor, poolERC20s);
        for (uint256 i; i < poolERC20s.length; i++) {
            userBalancesByToken[currentActor][address(poolERC20s[i])] = internalBalances[i];
        }
    }

    function exitPoolExactBptIn(uint256 actorIndexSeed, uint256 poolIndexSeed, uint256 bptAmountIn)
        external
        useActor(actorIndexSeed)
        usePool(poolIndexSeed)
    {
        // Bounds
        uint256 bptBalance = currentPool.balanceOf(currentActor);
        if (bptBalance == 0) return;
        bptAmountIn = bound(bptAmountIn, bptBalance / 100, bptBalance);

        // Get pool assets and arguments for queryExit
        (IERC20[] memory poolERC20s, uint256[] memory balances, uint256 lastChangeBlock) =
            balancerVault.getPoolTokens(currentPoolId);
        IAsset[] memory poolAssets = new IAsset[](poolERC20s.length);
        for (uint256 i; i < poolERC20s.length; i++) {
            poolAssets[i] = IAsset(address(poolERC20s[i]));
        }

        // Get amounts out from queryExit and apply 20% slippage
        bytes memory userData = abi.encode(ExitKind.EXACT_BPT_IN_FOR_TOKENS_OUT, bptAmountIn);
        (, uint256[] memory amountsOut) = currentPool.queryExit(
            currentPoolId,
            currentActor,
            currentActor,
            balances,
            lastChangeBlock,
            balancerVault.getProtocolFeesCollector().getSwapFeePercentage(),
            userData
        );
        for (uint256 i; i < amountsOut.length; i++) {
            amountsOut[i] = (amountsOut[i] * 4) / 5;
        }

        // Approve vault to transfer BPTs
        currentPool.approve(address(balancerVault), bptAmountIn);

        // Exit pool
        balancerVault.exitPool(
            currentPoolId,
            currentActor,
            payable(currentActor),
            IBalancerVault.ExitPoolRequest(poolAssets, amountsOut, userData, false)
        );

        // Update local user vault balances
        uint256[] memory internalBalances = balancerVault.getInternalBalance(currentActor, poolERC20s);
        for (uint256 i; i < poolERC20s.length; i++) {
            userBalancesByToken[currentActor][address(poolERC20s[i])] = internalBalances[i];
        }
    }

    function singleSwapGivenIn(uint256 actorIndexSeed, uint256 poolIndexSeed, uint256 amountIn, bool firstAssetIn)
        external
        useActor(actorIndexSeed)
        usePool(poolIndexSeed)
    {
        // Bounds
        amountIn = bound(amountIn, 0.01 ether, 1 ether);

        // Get pool assets
        (IERC20[] memory poolERC20s,,) = balancerVault.getPoolTokens(currentPoolId);
        IAsset assetIn = IAsset(address(poolERC20s[firstAssetIn ? 0 : 1]));
        IAsset assetOut = IAsset(address(poolERC20s[firstAssetIn ? 1 : 0]));

        // Prepare structs and enums
        IBalancerVault.SwapKind swapKind = IBalancerVault.SwapKind.GIVEN_IN;
        IBalancerVault.SingleSwap memory singleSwap = IBalancerVault.SingleSwap({
            poolId: currentPoolId,
            kind: swapKind,
            assetIn: assetIn,
            assetOut: assetOut,
            amount: amountIn,
            userData: new bytes(0)
        });
        IBalancerVault.FundManagement memory funds = IBalancerVault.FundManagement({
            sender: currentActor,
            fromInternalBalance: false,
            recipient: payable(currentActor),
            toInternalBalance: false
        });

        // Deal tokens to actor and approve vault to transfer them
        deal(address(assetIn), currentActor, amountIn);
        poolERC20s[firstAssetIn ? 0 : 1].approve(address(balancerVault), amountIn);

        // Swap
        balancerVault.swap(singleSwap, funds, 0, block.timestamp + 1 hours);

        // Update local user vault balances
        uint256[] memory internalBalances = balancerVault.getInternalBalance(currentActor, poolERC20s);
        for (uint256 i; i < poolERC20s.length; i++) {
            userBalancesByToken[currentActor][address(poolERC20s[i])] = internalBalances[i];
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
        // Bounds
        address receiver = actors[bound(actorIndexSeedReceiver, 0, actors.length - 1)];
        numOps = bound(numOps, 1, 5);

        // Create ops array and get pool tokens
        IBalancerVault.UserBalanceOp[] memory ops = new IBalancerVault.UserBalanceOp[](numOps);
        (IERC20[] memory poolERC20s,,) = balancerVault.getPoolTokens(currentPoolId);

        // Populate ops array with UserBalanceOp structs
        for (uint256 i; i < numOps; i++) {
            // Bounds
            IERC20 token = poolERC20s[bound(assetKindSeeds[i], 0, poolERC20s.length - 1)];
            IAsset asset = IAsset(address(token));
            IBalancerVault.UserBalanceOpKind kind = IBalancerVault.UserBalanceOpKind(bound(assetKindSeeds[i], 0, 3));

            // Handle token amount according to op kind
            uint256 amount;
            if (kind == IBalancerVault.UserBalanceOpKind.DEPOSIT_INTERNAL) {
                // Vault needs to be able to transfer tokens from actor
                amount = bound(amounts[i], 0.1 ether, 10 ether);
                // Give tokens to actor
                deal(address(asset), currentActor, amount + token.balanceOf(currentActor));
                // Approve vault to transfer tokens if necessary
                uint256 allowance = token.allowance(currentActor, address(balancerVault));
                if (allowance != type(uint256).max) {
                    token.approve(
                        address(balancerVault),
                        type(uint256).max - allowance > amount ? amount + allowance : type(uint256).max
                    );
                }
                // Increase local user balance so it is reflected in subsequent ops
                userBalancesByToken[receiver][address(token)] += amount;
            } else {
                // All other op kinds decrement sender balance in vault
                uint256 userBalance = userBalancesByToken[currentActor][address(token)];
                amount = bound(amounts[i], userBalance / 50, userBalance / 10);
                // Decrease local user balance of sender so it is reflected in subsequent ops
                userBalancesByToken[currentActor][address(token)] -= amount;
                // WITHDRAW_INTERNAL and TRANSFER_EXTERNAL only decrement sender balance in vault
                // but TRANSFER_INTERNAL also increments receiver balance in vault
                if (kind == IBalancerVault.UserBalanceOpKind.TRANSFER_INTERNAL) {
                    // Increase local user balance of recipient so it is reflected in subsequent ops
                    userBalancesByToken[receiver][address(token)] += amount;
                }
            }
            // Create UserBalanceOp
            ops[i] = IBalancerVault.UserBalanceOp({
                kind: kind,
                asset: asset,
                amount: amount,
                sender: currentActor,
                recipient: payable(receiver)
            });
        }

        balancerVault.manageUserBalance(ops);

        // Check that local user vault balances reflect vault state after all ops
        uint256[] memory internalBalances = balancerVault.getInternalBalance(currentActor, poolERC20s);
        for (uint256 i; i < poolERC20s.length; i++) {
            assertEq(
                userBalancesByToken[currentActor][address(poolERC20s[i])],
                internalBalances[i],
                "Local user vault balance does not match vault state after ops"
            );
        }
    }
}
