// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.16;

// contracts
import "../../../contracts/SMRewardDistributor.sol";
import {Test} from "../../../lib/increment-protocol/lib/forge-std/src/Test.sol";

// interfaces
import {ISafetyModule} from "../../../contracts/interfaces/ISafetyModule.sol";

// libraries
import {PRBMathUD60x18} from "../../../lib/increment-protocol/lib/prb-math/contracts/PRBMathUD60x18.sol";

contract SMRDHandler is Test {
    using PRBMathUD60x18 for uint256;

    event RewardAccruedToUser(address indexed user, address rewardToken, address market, uint256 reward);

    event RewardClaimed(address indexed user, address rewardToken, uint256 reward);

    SMRewardDistributor public rewardDistributor;

    ISafetyModule public safetyModule;

    address[] public actors;

    address internal currentActor;

    modifier useActor(uint256 actorIndexSeed) {
        currentActor = actors[bound(actorIndexSeed, 0, actors.length - 1)];
        vm.startPrank(currentActor);
        _;
        vm.stopPrank();
    }

    constructor(SMRewardDistributor _rewardDistributor, address[] memory _actors) {
        rewardDistributor = _rewardDistributor;
        safetyModule = rewardDistributor.safetyModule();
        actors = _actors;
    }

    /* ******************** */
    /*  Global Environment  */
    /* ******************** */

    function skipTime(uint256 time) external {
        time = bound(time, 1 hours, 1 weeks);
        skip(time);
    }

    /* ******************** */
    /*  External Functions  */
    /* ******************** */

    function registerPositions(uint256 actorIndexSeed) external useActor(actorIndexSeed) {
        address[] memory markets = new address[](safetyModule.getNumStakedTokens());
        for (uint256 i; i < markets.length; i++) {
            markets[i] = address(safetyModule.stakedTokens(i));
            uint256 registeredPosition = rewardDistributor.lpPositionsPerUser(currentActor, markets[i]);
            if (registeredPosition != 0) {
                vm.expectRevert(
                    abi.encodeWithSignature(
                        "RewardDistributor_PositionAlreadyRegistered(address,address,uint256)",
                        currentActor,
                        markets[i],
                        registeredPosition
                    )
                );
                break;
            }
        }
        rewardDistributor.registerPositions(markets);
    }

    function claimRewards(uint256 actorIndexSeed) external useActor(actorIndexSeed) {
        uint256 numRewards = rewardDistributor.getRewardTokenCount();
        uint256 numMarkets = safetyModule.getNumStakedTokens();
        address[] memory markets = new address[](numMarkets);
        address[] memory tokens = new address[](numRewards);
        uint256[] memory prevBalances = new uint256[](numRewards);
        uint256[] memory reserveBalances = new uint256[](numRewards);
        uint256[] memory rewardsAccrued = new uint256[](numRewards);
        uint256[][] memory newRewardsPerTokenPerMarket = new uint256[][](numRewards);
        for (uint256 i; i < numMarkets; i++) {
            markets[i] = address(safetyModule.stakedTokens(i));
        }
        for (uint256 i; i < numRewards; i++) {
            newRewardsPerTokenPerMarket[i] = new uint256[](numMarkets);
            for (uint256 j; j < numMarkets; j++) {
                newRewardsPerTokenPerMarket[i][j] =
                    _previewNewUserRewardsPerMarket(currentActor, rewardDistributor.rewardTokens(i), markets[j]);
            }
            tokens[i] = rewardDistributor.rewardTokens(i);
            prevBalances[i] = IERC20(tokens[i]).balanceOf(currentActor);
            reserveBalances[i] = IERC20(tokens[i]).balanceOf(rewardDistributor.ecosystemReserve());
            rewardsAccrued[i] = rewardDistributor.rewardsAccruedByUser(currentActor, tokens[i])
                + _previewNewUserRewards(currentActor, tokens[i]);
        }
        _expectClaimRewardsEvents(
            currentActor, markets, tokens, reserveBalances, rewardsAccrued, newRewardsPerTokenPerMarket
        );
        rewardDistributor.claimRewards();
        for (uint256 i; i < numRewards; i++) {
            if (rewardsAccrued[i] <= reserveBalances[i]) {
                assertEq(
                    IERC20(tokens[i]).balanceOf(currentActor),
                    prevBalances[i] + rewardsAccrued[i],
                    "SMRDHandler: reward token balance mismatch after claiming"
                );
                assertEq(
                    IERC20(tokens[i]).balanceOf(rewardDistributor.ecosystemReserve()),
                    reserveBalances[i] - rewardsAccrued[i],
                    "SMRDHandler: ecosystem reserve balance mismatch after claiming"
                );
            } else {
                assertEq(
                    IERC20(tokens[i]).balanceOf(currentActor),
                    prevBalances[i] + reserveBalances[i],
                    "SMRDHandler: reward token balance mismatch after claiming (shortfall)"
                );
                assertEq(
                    IERC20(tokens[i]).balanceOf(rewardDistributor.ecosystemReserve()),
                    0,
                    "SMRDHandler: ecosystem reserve balance mismatch after claiming (shortfall)"
                );
            }
        }
    }

    /* ********************* */
    /* Public View Functions */
    /* ********************* */

    function computeRewardMultiplier(address user, address stakedToken) public view returns (uint256) {
        return rewardDistributor.computeRewardMultiplier(user, stakedToken);
    }

    /* ****************** */
    /*      Internal      */
    /* ****************** */

    function _previewNewUserRewards(address user, address rewardToken) internal view returns (uint256) {
        uint256 numMarkets = safetyModule.getNumStakedTokens();
        uint256 newUserRewards;
        for (uint256 i; i < numMarkets; i++) {
            address stakedToken = address(safetyModule.stakedTokens(i));
            newUserRewards += _previewNewUserRewardsPerMarket(user, rewardToken, stakedToken);
        }
        return newUserRewards;
    }

    function _previewNewUserRewardsPerMarket(address user, address rewardToken, address stakedToken)
        internal
        view
        returns (uint256)
    {
        uint256 previousBalance = IStakedToken(stakedToken).balanceOf(user);
        uint256 multiplier = computeRewardMultiplier(user, stakedToken);
        uint256 deltaTime = block.timestamp - rewardDistributor.timeOfLastCumRewardUpdate(stakedToken);
        uint256 rewardWeight = rewardDistributor.getRewardWeight(rewardToken, stakedToken);
        uint256 totalLiquidity = rewardDistributor.totalLiquidityPerMarket(stakedToken);
        if (
            deltaTime == 0 || totalLiquidity == 0 || rewardWeight == 0 || multiplier == 0
                || rewardDistributor.isTokenPaused(rewardToken)
                || rewardDistributor.getInitialInflationRate(rewardToken) == 0
        ) return 0;
        uint256 inflationRate = rewardDistributor.getInflationRate(rewardToken);
        uint256 newMarketRewards =
            (((((inflationRate * rewardWeight) / 10000) * deltaTime) / 365 days) * 1e18) / totalLiquidity;
        uint256 cumRewardPerLpToken =
            rewardDistributor.cumulativeRewardPerLpToken(address(rewardToken), address(stakedToken)) + newMarketRewards;
        uint256 cumRewardPerLpTokenPerUser =
            rewardDistributor.cumulativeRewardPerLpTokenPerUser(user, address(rewardToken), address(stakedToken));
        return previousBalance.mul(cumRewardPerLpToken - cumRewardPerLpTokenPerUser).mul(multiplier);
    }

    function _expectClaimRewardsEvents(
        address user,
        address[] memory markets,
        address[] memory tokens,
        uint256[] memory reserveBalances,
        uint256[] memory rewardsAccrued,
        uint256[][] memory newRewardsPerTokenPerMarket
    ) internal {
        for (uint256 i; i < markets.length; ++i) {
            for (uint256 j; j < tokens.length; ++j) {
                if (newRewardsPerTokenPerMarket[j][i] == 0) continue;
                vm.expectEmit(false, false, false, true);
                emit RewardAccruedToUser(user, tokens[j], markets[i], newRewardsPerTokenPerMarket[j][i]);
            }
        }
        for (uint256 i; i < tokens.length; ++i) {
            if (rewardsAccrued[i] == 0) continue;
            if (rewardsAccrued[i] <= reserveBalances[i]) {
                vm.expectEmit(false, false, false, true);
                emit RewardClaimed(user, tokens[i], rewardsAccrued[i]);
            } else {
                vm.expectEmit(false, false, false, true);
                emit RewardClaimed(user, tokens[i], reserveBalances[i]);
            }
        }
    }
}
