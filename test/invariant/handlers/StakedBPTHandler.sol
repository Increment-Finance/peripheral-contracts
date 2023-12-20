// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.16;

// contracts
import "./StakedTokenHandler.sol";

// interfaces
import {IBalancerPoolToken, IWeightedPool, IWETH, JoinKind} from "../../balancer/IWeightedPool.sol";
import {IWeightedPoolFactory, IAsset, IVault as IBalancerVault} from "../../balancer/IWeightedPoolFactory.sol";

contract StakedBPTHandler is StakedTokenHandler {
    IBalancerVault public balancerVault;
    bytes32 public poolId;
    IAsset[] public poolAssets;

    constructor(
        StakedToken _stakedToken,
        address[] memory _actors,
        IBalancerVault _vault,
        IAsset[] memory _assets,
        bytes32 _poolId
    ) StakedTokenHandler(_stakedToken, _actors) {
        balancerVault = _vault;
        poolAssets = _assets;
        poolId = _poolId;
    }

    function dealUnderlying(
        uint256 amount,
        uint256 actorIndexSeed
    ) external override {
        address actor = actors[bound(actorIndexSeed, 0, actors.length - 1)];
        (IERC20[] memory poolERC20s, , ) = balancerVault.getPoolTokens(poolId);
        address underlying = address(poolERC20s[0]);
        amount = bound(amount, 1e18, 1_000_000e18);
        deal(underlying, actor, amount);
    }

    function dealWETH(
        uint256 amount,
        uint256 actorIndexSeed
    ) external useActor(actorIndexSeed) {
        amount = bound(amount, 0.1e18, 1_000e18);
        deal(currentActor, amount);
        (IERC20[] memory poolERC20s, , ) = balancerVault.getPoolTokens(poolId);
        IWETH weth = IWETH(address(poolERC20s[1]));
        weth.approve(address(balancerVault), amount);
        weth.deposit{value: amount}();
    }

    function joinBalancerPool(
        uint256 actorIndexSeed,
        uint256[2] memory maxAmountsIn
    ) external useActor(actorIndexSeed) {
        uint256[] memory maxAmounts = new uint256[](2);
        maxAmounts[0] = bound(maxAmountsIn[0], 100e18, 1_000_000e18);
        maxAmounts[1] = bound(
            maxAmountsIn[1],
            maxAmounts[0] / 1000,
            maxAmounts[0] / 10
        );
        (IERC20[] memory poolERC20s, , ) = balancerVault.getPoolTokens(poolId);
        if (
            poolERC20s[0].balanceOf(currentActor) < maxAmounts[0] ||
            poolERC20s[1].balanceOf(currentActor) < maxAmounts[1]
        ) {
            vm.expectRevert();
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

    function stake(
        uint256 amount,
        uint256 actorIndexSeed
    ) external override useActor(actorIndexSeed) {
        if (stakedToken.paused()) {
            vm.expectRevert(bytes("Pausable: paused"));
            stakedToken.stake(amount);
            return;
        }
        if (amount == 0) {
            vm.expectRevert(
                abi.encodeWithSignature("StakedToken_InvalidZeroAmount()")
            );
            stakedToken.stake(amount);
            return;
        }
        if (amount > type(uint128).max) {
            amount = type(uint128).max;
        }
        IERC20 underlying = stakedToken.getUnderlyingToken();
        uint256 preview = stakedToken.previewStake(amount);
        uint256 previousBalance = stakedToken.balanceOf(currentActor);
        uint256 maxStake = stakedToken.maxStakeAmount();
        if (previousBalance + preview > maxStake) {
            vm.expectRevert(
                abi.encodeWithSignature(
                    "StakedToken_AboveMaxStakeAmount(uint256,uint256)",
                    maxStake,
                    maxStake - stakedToken.balanceOf(currentActor)
                )
            );
            stakedToken.stake(amount);
            return;
        }
        if (underlying.balanceOf(currentActor) < amount) {
            vm.expectRevert(bytes("BAL#416"));
            stakedToken.stake(amount);
            return;
        }
        if (previousBalance > 0) {
            _expectRewardEvents(currentActor, previousBalance);
        }
        vm.expectEmit(false, false, false, true);
        emit PositionUpdated(
            currentActor,
            address(stakedToken),
            previousBalance,
            previousBalance + preview
        );
        stakedToken.stake(amount);
        assertEq(
            stakedToken.balanceOf(currentActor),
            stakeBalances[currentActor] + preview,
            "StakedBPTHandler: staked token balance mismatch after staking"
        );
        stakeBalances[currentActor] += preview;
    }
}
