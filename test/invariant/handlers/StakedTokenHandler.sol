// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.16;

// contracts
import "../../../contracts/StakedToken.sol";
import {Test} from "../../../lib/increment-protocol/lib/forge-std/src/Test.sol";

// interfaces
import "../../../contracts/interfaces/ISMRewardDistributor.sol";
import "../../../contracts/interfaces/IRewardController.sol";
import "../../../contracts/interfaces/IRewardDistributor.sol";
import {IBalancerPoolToken, IWeightedPool, IWETH, JoinKind} from "../../balancer/IWeightedPool.sol";
import {IWeightedPoolFactory, IAsset, IVault as IBalancerVault} from "../../balancer/IWeightedPoolFactory.sol";

// libraries
import {PRBMathUD60x18} from "../../../lib/increment-protocol/lib/prb-math/contracts/PRBMathUD60x18.sol";

contract StakedTokenHandler is Test {
    using PRBMathUD60x18 for uint256;

    event RewardAccruedToMarket(
        address indexed market,
        address rewardToken,
        uint256 reward
    );

    event RewardAccruedToUser(
        address indexed user,
        address rewardToken,
        address market,
        uint256 reward
    );

    event PositionUpdated(
        address indexed user,
        address market,
        uint256 prevPosition,
        uint256 newPosition
    );

    StakedToken public stakedToken;
    StakedToken[] public stakedTokens;

    ISMRewardDistributor public smRewardDistributor;
    IRewardDistributor public rewardDistributor;
    IRewardController rewardController;

    address[] public actors;

    address internal currentActor;

    address internal testContract;

    mapping(StakedToken => mapping(address => uint256)) public stakeBalances;
    mapping(StakedToken => bool) public isStakedBPT;

    modifier useActor(uint256 actorIndexSeed) {
        currentActor = actors[bound(actorIndexSeed, 0, actors.length - 1)];
        vm.startPrank(currentActor);
        _;
        vm.stopPrank();
    }

    modifier useStakedToken(uint256 tokenIndexSeed) {
        stakedToken = stakedTokens[
            bound(tokenIndexSeed, 0, stakedTokens.length - 1)
        ];
        _;
    }

    modifier useStakedBPT(uint256 tokenIndexSeed) {
        while (!isStakedBPT[stakedToken]) {
            tokenIndexSeed == type(uint256).max
                ? tokenIndexSeed = 0
                : tokenIndexSeed += 1;
            stakedToken = stakedTokens[
                bound(tokenIndexSeed, 0, stakedTokens.length - 1)
            ];
        }
        _;
    }

    constructor(
        StakedToken[] memory _stakedTokens,
        StakedToken[] memory _stakedBPTs,
        address[] memory _actors
    ) {
        require(
            _stakedTokens.length > 0,
            "StakedTokenHandler: staked tokens must not be empty"
        );
        require(
            _stakedBPTs.length > 0,
            "StakedTokenHandler: staked BPTs must not be empty"
        );
        stakedTokens = _stakedTokens;
        stakedToken = _stakedTokens[0];
        actors = _actors;
        currentActor = actors[0];
        testContract = msg.sender;
        smRewardDistributor = stakedTokens[0]
            .safetyModule()
            .smRewardDistributor();
        rewardDistributor = IRewardDistributor(address(smRewardDistributor));
        rewardController = IRewardController(address(smRewardDistributor));
        for (uint256 i; i < _stakedBPTs.length; ++i) {
            isStakedBPT[_stakedBPTs[i]] = true;
        }
    }

    /* ********************* */
    /* Test Helper Functions */
    /* ********************* */

    function dealUnderlying(
        uint256 amount,
        uint256 actorIndexSeed,
        uint256 tokenIndexSeed
    ) external virtual useActor(actorIndexSeed) useStakedToken(tokenIndexSeed) {
        if (isStakedBPT[stakedToken]) {
            IWeightedPool balancerPool = IWeightedPool(
                address(stakedToken.getUnderlyingToken())
            );
            IBalancerVault balancerVault = balancerPool.getVault();
            bytes32 poolId = balancerPool.getPoolId();
            (IERC20[] memory poolERC20s, , ) = balancerVault.getPoolTokens(
                poolId
            );
            address underlying = address(poolERC20s[0]);
            amount = bound(amount, 1e18, 1_000_000e18);
            deal(underlying, currentActor, amount);
        } else {
            address underlying = address(stakedToken.getUnderlyingToken());
            amount = bound(amount, 1e18, 1_000_000e18);
            deal(underlying, currentActor, amount);
        }
    }

    function dealWETH(
        uint256 amount,
        uint256 actorIndexSeed,
        uint256 tokenIndexSeed
    ) external useActor(actorIndexSeed) useStakedBPT(tokenIndexSeed) {
        amount = bound(amount, 0.1e18, 1_000e18);
        deal(currentActor, amount);
        IWeightedPool balancerPool = IWeightedPool(
            address(stakedToken.getUnderlyingToken())
        );
        IBalancerVault balancerVault = balancerPool.getVault();
        bytes32 poolId = balancerPool.getPoolId();
        (IERC20[] memory poolERC20s, , ) = balancerVault.getPoolTokens(poolId);
        IWETH weth = IWETH(address(poolERC20s[1]));
        weth.approve(address(balancerVault), amount);
        weth.deposit{value: amount}();
    }

    function joinBalancerPool(
        uint256 actorIndexSeed,
        uint256 tokenIndexSeed,
        uint256[2] memory maxAmountsIn
    ) external useActor(actorIndexSeed) useStakedBPT(tokenIndexSeed) {
        uint256[] memory maxAmounts = new uint256[](2);
        maxAmounts[0] = bound(maxAmountsIn[0], 100e18, 1_000_000e18);
        maxAmounts[1] = bound(
            maxAmountsIn[1],
            maxAmounts[0] / 1000,
            maxAmounts[0] / 10
        );
        IWeightedPool balancerPool = IWeightedPool(
            address(stakedToken.getUnderlyingToken())
        );
        IBalancerVault balancerVault = balancerPool.getVault();
        bytes32 poolId = balancerPool.getPoolId();
        (IERC20[] memory poolERC20s, , ) = balancerVault.getPoolTokens(poolId);
        if (
            poolERC20s[0].balanceOf(currentActor) < maxAmounts[0] ||
            poolERC20s[1].balanceOf(currentActor) < maxAmounts[1]
        ) {
            vm.expectRevert();
        }
        IAsset[] memory poolAssets = new IAsset[](2);
        poolAssets[0] = IAsset(address(poolERC20s[0]));
        poolAssets[1] = IAsset(address(poolERC20s[1]));
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

    /* ******************** */
    /*  External Functions  */
    /* ******************** */

    function stake(
        uint256 amount,
        uint256 actorIndexSeed,
        uint256 tokenIndexSeed
    ) external virtual useActor(actorIndexSeed) useStakedToken(tokenIndexSeed) {
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
        if (stakedToken.isInPostSlashingState()) {
            vm.expectRevert(
                abi.encodeWithSignature(
                    "StakedToken_StakingDisabledInPostSlashingState()"
                )
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
            if (isStakedBPT[stakedToken]) {
                vm.expectRevert(bytes("BAL#416"));
                stakedToken.stake(amount);
                return;
            }
            vm.expectRevert(bytes("ERC20: transfer amount exceeds balance"));
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
            stakeBalances[stakedToken][currentActor] + preview,
            "StakedTokenHandler: staked token balance mismatch after staking"
        );
        stakeBalances[stakedToken][currentActor] += preview;
    }

    function redeem(
        uint256 amount,
        uint256 actorIndexSeed,
        uint256 tokenIndexSeed
    ) external useActor(actorIndexSeed) useStakedToken(tokenIndexSeed) {
        if (stakedToken.paused()) {
            vm.expectRevert(bytes("Pausable: paused"));
            stakedToken.redeem(amount);
            return;
        }
        if (amount == 0) {
            vm.expectRevert(
                abi.encodeWithSignature("StakedToken_InvalidZeroAmount()")
            );
            stakedToken.redeem(amount);
            return;
        }
        uint256 cooldownPeriod = stakedToken.getCooldownSeconds();
        uint256 unstakeWindow = stakedToken.getUnstakeWindowSeconds();
        uint256 cooldownStart = stakedToken.stakersCooldowns(currentActor);
        uint256 cooldownEnd = cooldownStart + cooldownPeriod;
        bool inPostSlashingState = stakedToken.isInPostSlashingState();
        if (cooldownEnd <= block.timestamp || inPostSlashingState) {
            if (
                cooldownEnd + unstakeWindow >= block.timestamp ||
                inPostSlashingState
            ) {
                uint256 underlyingBalance = stakedToken
                    .getUnderlyingToken()
                    .balanceOf(currentActor);
                uint256 previousBalance = stakedToken.balanceOf(currentActor);
                uint256 amountToRedeem = amount <= previousBalance
                    ? amount
                    : previousBalance;
                uint256 preview = stakedToken.previewRedeem(amountToRedeem);
                if (previousBalance > 0) {
                    _expectRewardEvents(currentActor, previousBalance);
                }
                vm.expectEmit(false, false, false, true);
                emit PositionUpdated(
                    currentActor,
                    address(stakedToken),
                    previousBalance,
                    previousBalance - amountToRedeem
                );
                stakedToken.redeem(amount);
                assertEq(
                    stakedToken.balanceOf(currentActor),
                    stakeBalances[stakedToken][currentActor] - amountToRedeem,
                    "StakedTokenHandler: staked token balance mismatch after redeeming"
                );
                assertEq(
                    stakedToken.getUnderlyingToken().balanceOf(currentActor),
                    underlyingBalance + preview,
                    "StakedTokenHandler: underlying token balance mismatch after redeeming"
                );
                stakeBalances[stakedToken][currentActor] -= amountToRedeem;
            } else {
                vm.expectRevert(
                    abi.encodeWithSignature(
                        "StakedToken_UnstakeWindowFinished(uint256)",
                        cooldownEnd + unstakeWindow
                    )
                );
                stakedToken.redeem(amount);
            }
        } else {
            vm.expectRevert(
                abi.encodeWithSignature(
                    "StakedToken_InsufficientCooldown(uint256)",
                    cooldownEnd
                )
            );
            stakedToken.redeem(amount);
        }
    }

    function cooldown(
        uint256 actorIndexSeed,
        uint256 tokenIndexSeed
    ) external useActor(actorIndexSeed) useStakedToken(tokenIndexSeed) {
        if (stakedToken.balanceOf(currentActor) == 0) {
            vm.expectRevert(
                abi.encodeWithSignature("StakedToken_ZeroBalanceAtCooldown()")
            );
        } else if (stakedToken.isInPostSlashingState()) {
            vm.expectRevert(
                abi.encodeWithSignature(
                    "StakedToken_CooldownDisabledInPostSlashingState()"
                )
            );
        }
        stakedToken.cooldown();
    }

    function transfer(
        uint256 amount,
        uint256 actorIndexSeedFrom,
        uint256 actorIndexSeedTo,
        uint256 tokenIndexSeed
    ) external useActor(actorIndexSeedFrom) useStakedToken(tokenIndexSeed) {
        address to = actors[bound(actorIndexSeedTo, 0, actors.length - 1)];
        while (to == currentActor) {
            actorIndexSeedTo == type(uint256).max
                ? actorIndexSeedTo = 0
                : actorIndexSeedTo += 1;
            to = actors[bound(actorIndexSeedTo, 0, actors.length - 1)];
        }
        vm.assume(to != currentActor);
        if (amount > type(uint128).max) {
            amount = type(uint128).max;
        }
        if (stakedToken.paused()) {
            vm.expectRevert(bytes("Pausable: paused"));
            stakedToken.transfer(to, amount);
            return;
        }
        uint256 maxStake = stakedToken.maxStakeAmount();
        if (stakedToken.balanceOf(to) + amount > maxStake) {
            vm.expectRevert(
                abi.encodeWithSignature(
                    "StakedToken_AboveMaxStakeAmount(uint256,uint256)",
                    maxStake,
                    maxStake - stakedToken.balanceOf(to)
                )
            );
            stakedToken.transfer(to, amount);
            return;
        }
        if (stakedToken.balanceOf(currentActor) < amount) {
            vm.expectRevert(bytes("ERC20: transfer amount exceeds balance"));
            stakedToken.transfer(to, amount);
            return;
        }
        stakedToken.transfer(to, amount);
        assertEq(
            stakedToken.balanceOf(currentActor),
            stakeBalances[stakedToken][currentActor] - amount,
            "StakedTokenHandler: staked token balance mismatch after transfer from"
        );
        stakeBalances[stakedToken][currentActor] -= amount;
        assertEq(
            stakedToken.balanceOf(to),
            stakeBalances[stakedToken][to] + amount,
            "StakedTokenHandler: staked token balance mismatch after transfer to"
        );
        stakeBalances[stakedToken][to] += amount;
    }

    /* ****************** */
    /*      Internal      */
    /* ****************** */

    function _previewNewMarketRewards(
        address rewardToken
    ) internal view returns (uint256) {
        uint256 deltaTime = block.timestamp -
            rewardDistributor.timeOfLastCumRewardUpdate(address(stakedToken));
        uint256 rewardWeight = rewardController.getRewardWeight(
            rewardToken,
            address(stakedToken)
        );
        uint256 totalLiquidity = rewardDistributor.totalLiquidityPerMarket(
            address(stakedToken)
        );
        if (
            deltaTime == 0 ||
            totalLiquidity == 0 ||
            rewardWeight == 0 ||
            rewardController.isTokenPaused(rewardToken) ||
            rewardController.getInitialInflationRate(rewardToken) == 0
        ) {
            return 0;
        }
        uint256 inflationRate = rewardController.getInflationRate(rewardToken);
        uint256 newRewards = (((((inflationRate * rewardWeight) / 10000) *
            deltaTime) / 365 days) * 1e18) / totalLiquidity;
        return newRewards;
    }

    function _expectRewardEvents(
        address user,
        uint256 previousBalance
    ) internal {
        uint256 multiplier = smRewardDistributor.computeRewardMultiplier(
            user,
            address(stakedToken)
        );
        uint256 numRewards = rewardController.getRewardTokenCount();
        address[] memory rewardTokens = new address[](numRewards);
        uint256[] memory newMarketRewards = new uint256[](numRewards);
        uint256[] memory newUserRewards = new uint256[](numRewards);
        for (uint i; i < numRewards; ++i) {
            rewardTokens[i] = address(rewardController.rewardTokens(i));
            newMarketRewards[i] = _previewNewMarketRewards(rewardTokens[i]);
            uint256 cumRewardPerLpToken = rewardDistributor
                .cumulativeRewardPerLpToken(
                    address(rewardTokens[i]),
                    address(stakedToken)
                ) + newMarketRewards[i];
            uint256 cumRewardPerLpTokenPerUser = rewardDistributor
                .cumulativeRewardPerLpTokenPerUser(
                    user,
                    address(rewardTokens[i]),
                    address(stakedToken)
                );
            newUserRewards[i] = previousBalance
                .mul(cumRewardPerLpToken - cumRewardPerLpTokenPerUser)
                .mul(multiplier);
        }
        for (uint i; i < numRewards; ++i) {
            if (newMarketRewards[i] == 0) {
                continue;
            }
            vm.expectEmit(false, false, false, true);
            emit RewardAccruedToMarket(
                address(stakedToken),
                rewardTokens[i],
                newMarketRewards[i]
            );
        }
        for (uint i; i < numRewards; ++i) {
            if (newUserRewards[i] == 0) {
                continue;
            }
            vm.expectEmit(false, false, false, true);
            emit RewardAccruedToUser(
                user,
                rewardTokens[i],
                address(stakedToken),
                newUserRewards[i]
            );
        }
    }
}
