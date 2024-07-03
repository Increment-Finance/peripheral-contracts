// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.16;

// contracts
import "../../lib/increment-protocol/test/helpers/Deployment.MainnetFork.sol";
import "../../lib/increment-protocol/test/helpers/Utils.sol";
import "increment-protocol/ClearingHouse.sol";
import "../../lib/increment-protocol/test/mocks/TestPerpetual.sol";
import "increment-protocol/tokens/UA.sol";
import "increment-protocol/tokens/VBase.sol";
import "increment-protocol/tokens/VQuote.sol";
import {IncrementToken} from "@increment-governance/IncrementToken.sol";
import {TestPerpRewardDistributor, IRewardDistributor} from "../mocks/TestPerpRewardDistributor.sol";
import {EcosystemReserve} from "../../contracts/EcosystemReserve.sol";

// interfaces
import "increment-protocol/interfaces/ICryptoSwap.sol";
import "increment-protocol/interfaces/IPerpetual.sol";
import "increment-protocol/interfaces/IClearingHouse.sol";
import "increment-protocol/interfaces/ICurveCryptoFactory.sol";
import "increment-protocol/interfaces/IVault.sol";
import "increment-protocol/interfaces/IVBase.sol";
import "increment-protocol/interfaces/IVQuote.sol";
import "increment-protocol/interfaces/IInsurance.sol";
import {ERC20PresetFixedSupply} from "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetFixedSupply.sol";

// libraries
import {LibMath} from "increment-protocol/lib/LibMath.sol";
import "increment-protocol/lib/LibPerpetual.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {console2 as console} from "forge/console2.sol";

contract RewardsTest is Deployment, Utils {
    using LibMath for int256;
    using LibMath for uint256;

    event MarketRemovedFromRewards(address indexed market, address indexed rewardToken);
    event RewardTokenRemoved(address indexed rewardToken, uint256 unclaimedRewards, uint256 remainingBalance);
    event RewardTokenShortfall(address indexed rewardToken, uint256 shortfallAmount);
    event NewFundsAdmin(address indexed fundsAdmin);
    event EcosystemReserveUpdated(address prevEcosystemReserve, address newEcosystemReserve);

    uint88 public constant INITIAL_INFLATION_RATE = 1463753e18;
    uint88 public constant INITIAL_REDUCTION_FACTOR = 1.189207115e18;
    uint256 public constant INITIAL_WITHDRAW_THRESHOLD = 10 days;
    uint256 public constant INITIAL_MARKET_WEIGHT_0 = 7500;
    uint256 public constant INITIAL_MARKET_WEIGHT_1 = 2500;

    address public liquidityProviderOne = address(123);
    address public liquidityProviderTwo = address(456);
    address public traderOne = address(789);

    IncrementToken public rewardsToken;
    IncrementToken public rewardsToken2;

    EcosystemReserve public ecosystemReserve;
    TestPerpRewardDistributor public rewardDistributor;

    function setUp() public virtual override {
        deal(liquidityProviderOne, 100 ether);
        deal(liquidityProviderTwo, 100 ether);
        deal(traderOne, 100 ether);

        // Deploy protocol
        // increment-protocol/test/helpers/Deployment.MainnetFork.sol:setUp()
        super.setUp();

        // Deploy second perpetual contract
        _deployEthMarket();

        // Deploy the Ecosystem Reserve vault
        ecosystemReserve = new EcosystemReserve(address(this));

        // Deploy rewards tokens and distributor
        rewardsToken = new IncrementToken(20000000e18, address(this));
        rewardsToken2 = new IncrementToken(20000000e18, address(this));
        rewardsToken.unpause();
        rewardsToken2.unpause();

        uint256[] memory weights = new uint256[](2);
        weights[0] = INITIAL_MARKET_WEIGHT_0;
        weights[1] = INITIAL_MARKET_WEIGHT_1;

        rewardDistributor = new TestPerpRewardDistributor(
            INITIAL_INFLATION_RATE,
            INITIAL_REDUCTION_FACTOR,
            address(rewardsToken),
            address(clearingHouse),
            address(ecosystemReserve),
            INITIAL_WITHDRAW_THRESHOLD,
            weights
        );

        // Transfer all rewards tokens to the vault and approve the distributor
        rewardsToken.transfer(address(ecosystemReserve), rewardsToken.totalSupply());
        rewardsToken2.transfer(address(ecosystemReserve), rewardsToken2.totalSupply());
        ecosystemReserve.approve(rewardsToken, address(rewardDistributor), type(uint256).max);
        ecosystemReserve.approve(rewardsToken2, address(rewardDistributor), type(uint256).max);

        // initial liquidity
        fundAndPrepareAccount(liquidityProviderOne, 100_000e18, vault, ua);
        _provideLiquidity(10_000e18, liquidityProviderOne, perpetual);
        _provideLiquidity(10_000e18, liquidityProviderOne, eth_perpetual);
        address[] memory markets = _getMarkets();
        vm.startPrank(liquidityProviderOne);
        rewardDistributor.registerPositions(markets);
        vm.stopPrank();

        // Connect ClearingHouse to RewardsDistributor
        clearingHouse.addRewardContract(rewardDistributor);

        // Update ClearingHouse params to remove min open notional
        clearingHouse.setParameters(
            IClearingHouse.ClearingHouseParams({
                minMargin: 0.025 ether,
                minMarginAtCreation: 0.055 ether,
                minPositiveOpenNotional: 0 ether,
                liquidationReward: 0.015 ether,
                insuranceRatio: 0.1 ether,
                liquidationRewardInsuranceShare: 0.5 ether,
                liquidationDiscount: 0.95 ether,
                nonUACollSeizureDiscount: 0.75 ether,
                uaDebtSeizureThreshold: 10000 ether
            })
        );
        vBase.setHeartBeat(30 days);
        eth_vBase.setHeartBeat(30 days);
    }

    /* ******************* */
    /*  RewardDistributor  */
    /* ******************* */

    // solhint-disable-next-line func-name-mixedcase
    function testFuzz_EarlyWithdrawal(
        uint256 providedLiquidity1,
        uint256 providedLiquidity2,
        uint256 reductionRatio,
        uint256 thresholdTime,
        uint256 skipTime
    ) public {
        /* bounds */
        providedLiquidity1 = bound(providedLiquidity1, 100e18, 10_000e18);
        providedLiquidity2 = bound(providedLiquidity2, 100e18, 10_000e18);
        reductionRatio = bound(reductionRatio, 1e16, 5e17);
        thresholdTime = bound(thresholdTime, 1 days, 10 days);
        skipTime = bound(skipTime, thresholdTime / 10, thresholdTime / 2);

        // set early withdrawal threshold and provide liquidity
        rewardDistributor.setEarlyWithdrawalThreshold(thresholdTime);
        _provideLiquidityBothPerps(liquidityProviderTwo, providedLiquidity1, providedLiquidity2);

        // skip some time
        skip(skipTime);

        // store initial state before removing liquidity
        uint256[] memory balances = _getUserBalances(liquidityProviderTwo);
        uint256[] memory prevCumRewards = _getCumulativeRewardsByToken(rewardDistributor, address(rewardsToken));
        uint256[] memory prevTotalLiquidity = _getTotalLiquidityPerMarket(rewardDistributor);
        uint256[] memory skipTimes = _getSkipTimes(rewardDistributor);
        skipTimes[1] = 0; // removing liquidity will only accrue rewards for the first market

        // remove some liquidity from and accrue rewards for first perpetual
        _removeSomeLiquidity(liquidityProviderTwo, perpetual, reductionRatio);

        // check that early withdrawal penalty was applied to rewards
        uint256 accruedRewards = _checkRewards(
            address(rewardsToken), liquidityProviderTwo, skipTimes, balances, prevCumRewards, prevTotalLiquidity, 0
        );

        // skip to the end of the early withdrawal window
        skip(thresholdTime - skipTime);
        skipTimes = _getSkipTimes(rewardDistributor);

        // store updated balance and cumulative rewards per lp token before removing more liquidity
        balances[0] = perpetual.getLpLiquidity(liquidityProviderTwo);
        prevCumRewards = _getCumulativeRewardsByToken(rewardDistributor, address(rewardsToken));
        prevTotalLiquidity = _getTotalLiquidityPerMarket(rewardDistributor);

        // remove some liquidity again from first perpetual
        _removeSomeLiquidity(liquidityProviderTwo, perpetual, reductionRatio);

        // remove all liquidity from and accrue rewards for second perpetual
        _removeAllLiquidity(liquidityProviderTwo, eth_perpetual);

        // check that penalty was applied again, but only for the first perpetual
        accruedRewards = _checkRewards(
            address(rewardsToken),
            liquidityProviderTwo,
            skipTimes,
            balances,
            prevCumRewards,
            prevTotalLiquidity,
            accruedRewards
        );

        // check that the early withdrawal timer is updated correctly after partial and full withdrawals
        assertEq(
            rewardDistributor.withdrawTimerStartByUserByMarket(liquidityProviderTwo, address(perpetual)),
            block.timestamp,
            "Early withdrawal timer not reset to one after partial withdrawal"
        );
        assertEq(
            rewardDistributor.withdrawTimerStartByUserByMarket(liquidityProviderTwo, address(eth_perpetual)),
            0,
            "Early withdrawal timer not reset to zero after full withdrawal"
        );

        // check that early withdrawal timer is reset after adding liquidity
        skip(skipTime);
        _provideLiquidityBothPerps(liquidityProviderTwo, providedLiquidity1, providedLiquidity2);
        assertEq(
            rewardDistributor.withdrawTimerStartByUserByMarket(liquidityProviderTwo, address(perpetual)),
            block.timestamp,
            "Early withdrawal timer not reset after adding liquidity"
        );
    }

    // solhint-disable-next-line func-name-mixedcase
    function testFuzz_PausingAccrual(uint256 providedLiquidity1, uint256 providedLiquidity2) public {
        /* bounds */
        providedLiquidity1 = bound(providedLiquidity1, 100e18, 10_000e18);
        providedLiquidity2 = bound(providedLiquidity2, 100e18, 10_000e18);

        // add liquidity
        _provideLiquidityBothPerps(liquidityProviderTwo, providedLiquidity1, providedLiquidity2);

        // pause accrual
        vm.startPrank(address(this));
        rewardDistributor.togglePausedReward(address(rewardsToken));
        assertTrue(rewardDistributor.isTokenPaused(address(rewardsToken)), "Rewards not paused");

        // skip some time
        skip(10 days);

        // unpause accrual
        rewardDistributor.togglePausedReward(address(rewardsToken));
        assertTrue(!rewardDistributor.isTokenPaused(address(rewardsToken)), "Rewards not unpaused");

        // skip some more time
        skip(10 days);

        // store initial state before accruing rewards
        uint256[] memory balances = _getUserBalances(liquidityProviderTwo);
        uint256[] memory prevCumRewards = _getCumulativeRewardsByToken(rewardDistributor, address(rewardsToken));
        uint256[] memory prevTotalLiquidity = _getTotalLiquidityPerMarket(rewardDistributor);
        uint256[] memory skipTimes = new uint256[](2);
        skipTimes[0] = 10 days;
        skipTimes[1] = 10 days;

        // check that rewards are accrued for only the 10 days after unpausing
        rewardDistributor.accrueRewards(liquidityProviderTwo);
        _checkRewards(
            address(rewardsToken), liquidityProviderTwo, skipTimes, balances, prevCumRewards, prevTotalLiquidity, 0
        );
    }

    // solhint-disable-next-line func-name-mixedcase
    function testFuzz_AddNewMarket(uint256 providedLiquidity1, uint256 providedLiquidity2, uint256 providedLiquidity3)
        public
    {
        /* bounds */
        providedLiquidity1 = bound(providedLiquidity1, 100e18, 10_000e18);
        providedLiquidity2 = bound(providedLiquidity2, 100e18, 10_000e18);
        providedLiquidity3 = bound(providedLiquidity3, 100e18, 10_000e18);

        // add liquidity to first two perpetuals
        _provideLiquidityBothPerps(liquidityProviderTwo, providedLiquidity1, providedLiquidity2);

        // deploy new market, allowlist it in the clearing house, and initialize it in the reward distributor
        TestPerpetual perpetual3 = _deployTestPerpetual();
        clearingHouse.allowListPerpetual(perpetual3);
        rewardDistributor.initMarketStartTime(address(perpetual3));

        // skip some time
        skip(10 days);

        // store initial state before changing weights
        uint256[] memory balances = _getUserBalances(liquidityProviderTwo);
        uint256[] memory prevCumRewards = _getCumulativeRewardsByToken(rewardDistributor, address(rewardsToken));
        uint256[] memory prevTotalLiquidity = _getTotalLiquidityPerMarket(rewardDistributor);
        uint256[] memory prevWeights = _getRewardWeights(rewardDistributor, address(rewardsToken));
        uint256[] memory skipTimes = _getSkipTimes(rewardDistributor);

        // set new market weights, which also accrues rewards to the first two markets
        address[] memory markets = _getMarkets();
        uint256[] memory marketWeights = new uint256[](3);
        marketWeights[0] = 5000;
        marketWeights[1] = 3000;
        marketWeights[2] = 2000;
        rewardDistributor.updateRewardWeights(address(rewardsToken), markets, marketWeights);

        // check that rewards were accrued to first two perpetuals at previous weights
        rewardDistributor.accrueRewards(liquidityProviderTwo);
        uint256 accruedRewards = _checkRewards(
            address(rewardsToken),
            liquidityProviderTwo,
            skipTimes,
            balances,
            prevCumRewards,
            prevTotalLiquidity,
            prevWeights,
            0
        );

        // provide liquidity to new perpetual from both users, using providedLiquidity3 for user 2
        _provideLiquidity(10_000e18, liquidityProviderOne, perpetual3);
        fundAndPrepareAccount(liquidityProviderTwo, providedLiquidity3, vault, ua);
        _provideLiquidity(providedLiquidity3, liquidityProviderTwo, perpetual3);

        // update stored state after adding liquidity to new market
        balances = _getUserBalances(liquidityProviderTwo);
        prevCumRewards = _getCumulativeRewardsByToken(rewardDistributor, address(rewardsToken));
        prevTotalLiquidity = _getTotalLiquidityPerMarket(rewardDistributor);

        // skip some more time
        skip(10 days);

        // check that rewards are accrued to all three perpetuals at new weights
        rewardDistributor.accrueRewards(liquidityProviderTwo);
        accruedRewards = _checkRewards(
            address(rewardsToken),
            liquidityProviderTwo,
            skipTimes,
            balances,
            prevCumRewards,
            prevTotalLiquidity,
            marketWeights,
            accruedRewards
        );
    }

    // solhint-disable-next-line func-name-mixedcase
    function testFuzz_TenMarketsTwoTokens(uint256[10] memory providedLiquidity, uint256[9] memory rewardWeights)
        public
    {
        /* bounds */
        uint256 totalWeight1 = 10000;
        uint256 totalWeight2 = 10000;
        uint256[] memory weights = new uint256[](10);
        uint256[] memory weights2 = new uint256[](10);
        for (uint256 i; i < 10; i++) {
            providedLiquidity[i] = bound(providedLiquidity[i], 1_000e18, 10_000e18);
            if (i < 9) {
                weights[i] = bound(rewardWeights[i], 100, 1000);
                weights2[i] = bound(rewardWeights[8 - i], 100, 1000);
                totalWeight1 -= weights[i];
                totalWeight2 -= weights2[i];
            } else {
                weights[i] = totalWeight1;
                weights2[i] = totalWeight2;
            }
        }

        // add a new reward token
        rewardsToken2 =
            _addRewardToken(weights[0], 20000000e18, INITIAL_INFLATION_RATE / 2, INITIAL_REDUCTION_FACTOR * 2);

        // deploy, allowlist, and initialize 8 new markets
        TestPerpetual[] memory perpetuals = new TestPerpetual[](10);
        perpetuals[0] = perpetual;
        perpetuals[1] = eth_perpetual;
        for (uint256 i = 2; i < 10; i++) {
            perpetuals[i] = _deployTestPerpetual();
            clearingHouse.allowListPerpetual(perpetuals[i]);
            rewardDistributor.initMarketStartTime(address(perpetuals[i]));
        }

        // provide liquidity from both users to all new perpetuals
        for (uint256 i = 0; i < 10; i++) {
            fundAndPrepareAccount(liquidityProviderOne, 10_000e18, vault, ua);
            _provideLiquidity(10_000e18, liquidityProviderOne, perpetuals[i]);
            fundAndPrepareAccount(liquidityProviderTwo, providedLiquidity[i], vault, ua);
            _provideLiquidity(providedLiquidity[i], liquidityProviderTwo, perpetuals[i]);
        }

        // set new market weights
        address[] memory markets = _getMarkets();
        rewardDistributor.updateRewardWeights(address(rewardsToken), markets, weights);
        rewardDistributor.updateRewardWeights(address(rewardsToken2), markets, weights2);

        // skip some time
        skip(10 days);

        // store initial state before accruing rewards
        uint256[] memory balances = _getUserBalances(liquidityProviderTwo);
        uint256[] memory prevCumRewards = _getCumulativeRewardsByToken(rewardDistributor, address(rewardsToken));
        uint256[] memory prevTotalLiquidity = _getTotalLiquidityPerMarket(rewardDistributor);
        uint256[] memory skipTimes = _getSkipTimes(rewardDistributor);

        // check that rewards were accrued correctly for all markets
        rewardDistributor.accrueRewards(liquidityProviderTwo);
        uint256 accruedRewards = _checkRewards(
            address(rewardsToken),
            liquidityProviderTwo,
            skipTimes,
            balances,
            prevCumRewards,
            prevTotalLiquidity,
            weights,
            0
        );

        // skip some more time
        skip(10 days);

        // update stored state before removing liquidity
        balances = _getUserBalances(liquidityProviderTwo);
        prevCumRewards = _getCumulativeRewardsByToken(rewardDistributor, address(rewardsToken));
        prevTotalLiquidity = _getTotalLiquidityPerMarket(rewardDistributor);
        skipTimes = _getSkipTimes(rewardDistributor);

        // remove liquidity from user 2 from all 10 perpetuals
        for (uint256 i = 0; i < 10; i++) {
            if (i % 2 == 0) {
                _removeAllLiquidity(liquidityProviderTwo, perpetuals[i]);
            } else {
                _removeSomeLiquidity(liquidityProviderTwo, perpetuals[i], 5e17);
            }
        }

        // check that rewards were accrued correctly for previous balances in all markets
        accruedRewards = _checkRewards(
            address(rewardsToken),
            liquidityProviderTwo,
            skipTimes,
            balances,
            prevCumRewards,
            prevTotalLiquidity,
            weights,
            accruedRewards
        );
    }

    // solhint-disable-next-line func-name-mixedcase
    function testFuzz_DelistAndReplace(
        uint256 providedLiquidity1,
        uint256 providedLiquidity2,
        uint256 providedLiquidity3
    ) public {
        /* bounds */
        providedLiquidity1 = bound(providedLiquidity1, 100e18, 10_000e18);
        providedLiquidity2 = bound(providedLiquidity2, 100e18, 10_000e18);
        providedLiquidity3 = bound(providedLiquidity3, 100e18, 10_000e18);

        // add liquidity to first two perpetuals
        _provideLiquidityBothPerps(liquidityProviderTwo, providedLiquidity1, providedLiquidity2);

        // skip some time
        skip(10 days);

        // store initial state before accruing rewards
        uint256[] memory balances = _getUserBalances(liquidityProviderTwo);
        uint256[] memory prevCumRewards = _getCumulativeRewardsByToken(rewardDistributor, address(rewardsToken));
        uint256[] memory prevTotalLiquidity = _getTotalLiquidityPerMarket(rewardDistributor);
        uint256[] memory marketWeights = _getRewardWeights(rewardDistributor, address(rewardsToken));
        uint256[] memory skipTimes = _getSkipTimes(rewardDistributor);

        // check that rewards were accrued to first two perpetuals at previous weights
        rewardDistributor.accrueRewards(liquidityProviderTwo);
        uint256 accruedRewards = _checkRewards(
            address(rewardsToken), liquidityProviderTwo, skipTimes, balances, prevCumRewards, prevTotalLiquidity, 0
        );

        // delist second perpertual
        clearingHouse.delistPerpetual(eth_perpetual);

        // replace it with a new perpetual
        TestPerpetual perpetual3 = _deployTestPerpetual();
        clearingHouse.allowListPerpetual(perpetual3);
        assertEq(clearingHouse.getNumMarkets(), 2, "Incorrect number of markets");

        // check that the new perpetual does not accrue rewards with zero liquidity
        rewardDistributor.initMarketStartTime(address(perpetual3));
        assertEq(
            _viewNewRewardAccrual(address(perpetual3), liquidityProviderTwo, address(rewardsToken)),
            0,
            "Incorrect accrued rewards preview for new perp without liquidity"
        );

        // set new market weights, same as the old but with the new market in place of eth_perpetual
        address[] memory markets = _getMarkets();
        vm.expectEmit(false, false, false, true);
        emit MarketRemovedFromRewards(address(eth_perpetual), address(rewardsToken));
        rewardDistributor.updateRewardWeights(address(rewardsToken), markets, marketWeights);

        // provide liquidity to new perpetual from both users, using providedLiquidity3 for user 2
        _provideLiquidity(10_000e18, liquidityProviderOne, perpetual3);
        fundAndPrepareAccount(liquidityProviderTwo, providedLiquidity3, vault, ua);
        _provideLiquidity(providedLiquidity3, liquidityProviderTwo, perpetual3);

        // skip some more time
        skip(10 days);

        // update stored state before accruing rewards again
        balances = _getUserBalances(liquidityProviderTwo);
        prevCumRewards = _getCumulativeRewardsByToken(rewardDistributor, address(rewardsToken));
        prevTotalLiquidity = _getTotalLiquidityPerMarket(rewardDistributor);

        // check that rewards were accrued to first perpetual and new one at previous weights
        rewardDistributor.accrueRewards(liquidityProviderTwo);
        accruedRewards = _checkRewards(
            address(rewardsToken),
            liquidityProviderTwo,
            skipTimes,
            balances,
            prevCumRewards,
            prevTotalLiquidity,
            accruedRewards
        );
    }

    // solhint-disable-next-line func-name-mixedcase
    function testFuzz_PreExistingLiquidity(uint256 providedLiquidity1, uint256 providedLiquidity2) public {
        /* bounds */
        providedLiquidity1 = bound(providedLiquidity1, 100e18, 10_000e18);
        providedLiquidity2 = bound(providedLiquidity2, 100e18, 10_000e18);

        // add liquidity to first two perpetuals
        _provideLiquidityBothPerps(liquidityProviderTwo, providedLiquidity1, providedLiquidity2);

        // redeploy rewards distributor so it doesn't know about the pre-existing liquidity
        TestPerpRewardDistributor newRewardsDistributor = new TestPerpRewardDistributor(
            INITIAL_INFLATION_RATE,
            INITIAL_REDUCTION_FACTOR,
            address(rewardsToken),
            address(clearingHouse),
            address(ecosystemReserve),
            INITIAL_WITHDRAW_THRESHOLD,
            _getRewardWeights(rewardDistributor, address(rewardsToken))
        );
        ecosystemReserve.approve(rewardsToken, address(newRewardsDistributor), type(uint256).max);
        ecosystemReserve.approve(rewardsToken2, address(newRewardsDistributor), type(uint256).max);

        // Connect ClearingHouse to new RewardsDistributor
        clearingHouse.addRewardContract(newRewardsDistributor);

        // skip some time
        skip(10 days);

        // register user positions
        address[] memory markets = _getMarkets();
        vm.startPrank(liquidityProviderOne);
        newRewardsDistributor.registerPositions(markets);
        vm.startPrank(liquidityProviderTwo);
        newRewardsDistributor.registerPositions(markets);
        vm.stopPrank();

        // skip some time
        skip(10 days);

        // store initial state before accruing rewards
        uint256[] memory balances = _getUserBalances(liquidityProviderTwo);
        uint256[] memory prevCumRewards = _getCumulativeRewardsByToken(newRewardsDistributor, address(rewardsToken));
        uint256[] memory prevTotalLiquidity = _getTotalLiquidityPerMarket(newRewardsDistributor);
        uint256[] memory skipTimes = _getSkipTimes(newRewardsDistributor);

        // check that the user only accrues rewards for the 10 days since registering
        newRewardsDistributor.accrueRewards(liquidityProviderTwo);
        _checkRewards(
            newRewardsDistributor,
            address(rewardsToken),
            liquidityProviderTwo,
            skipTimes,
            balances,
            prevCumRewards,
            prevTotalLiquidity,
            0
        );
    }

    // solhint-disable-next-line func-name-mixedcase
    function test_RewardDistributorErrors() public {
        // updatePosition
        _expectCallerIsNotClearingHouse(address(this));
        rewardDistributor.updatePosition(address(perpetual), liquidityProviderOne);

        // initMarketStartTime
        _expectAlreadyInitializedStartTime(address(perpetual));
        rewardDistributor.initMarketStartTime(address(perpetual));

        // removeRewardToken
        _expectInvalidRewardTokenAddress(address(0));
        rewardDistributor.removeRewardToken(address(0));

        // registerPositions
        vm.startPrank(liquidityProviderOne);
        address[] memory markets = new address[](1);
        markets[0] = address(perpetual);
        uint256 position = perpetual.getLpLiquidity(liquidityProviderOne);
        _expectPositionAlreadyRegistered(liquidityProviderOne, address(perpetual), position);
        rewardDistributor.registerPositions(markets);
        vm.stopPrank();

        // addRewardToken
        vm.startPrank(address(this));
        address[] memory markets2 = _getMarkets();
        uint256[] memory weights1 = new uint256[](1);
        _expectIncorrectWeightsCount(1, 2);
        rewardDistributor.addRewardToken(address(rewardsToken), 1e18, 1e18, markets2, weights1);
        uint256[] memory weights2 = new uint256[](2);
        weights2[0] = type(uint256).max;
        _expectWeightExceedsMax(type(uint256).max, 10000);
        rewardDistributor.addRewardToken(address(rewardsToken), 1e18, 1e18, markets2, weights2);
        weights2[0] = 0;
        _expectIncorrectWeightsSum(0, 10000);
        rewardDistributor.addRewardToken(address(rewardsToken), 1e18, 1e18, markets2, weights2);
        weights2[0] = 5000;
        weights2[1] = 5000;
        for (uint256 i; i < 9; ++i) {
            rewardDistributor.addRewardToken(address(rewardsToken), 1e18, 1e18, markets2, weights2);
        }
        _expectAboveMaxRewardTokens(10);
        rewardDistributor.addRewardToken(address(rewardsToken), 1e18, 1e18, markets2, weights2);

        // paused
        vm.startPrank(address(this));
        clearingHouse.pause();
        assertTrue(rewardDistributor.paused(), "Reward distributor not paused when clearing house is paused");
        vm.startPrank(liquidityProviderOne);
        vm.expectRevert(bytes("Pausable: paused"));
        rewardDistributor.claimRewards();
        vm.stopPrank();
        clearingHouse.unpause();
        rewardDistributor.pause();
        assertTrue(rewardDistributor.paused(), "Reward distributor not paused directly");
        vm.startPrank(liquidityProviderOne);
        vm.expectRevert(bytes("Pausable: paused"));
        rewardDistributor.claimRewards();
        vm.stopPrank();
        rewardDistributor.unpause();
        assertTrue(!rewardDistributor.paused(), "Reward distributor not unpaused directly");
    }

    // solhint-disable-next-line func-name-mixedcase
    function test_EcosystemReserve() public {
        // access control errors
        vm.startPrank(liquidityProviderOne);
        vm.expectRevert(bytes("ONLY_BY_FUNDS_ADMIN"));
        ecosystemReserve.transferAdmin(liquidityProviderOne);
        vm.stopPrank();

        // invalid address errors
        vm.expectRevert(abi.encodeWithSignature("EcosystemReserve_InvalidAdmin()"));
        ecosystemReserve.transferAdmin(address(0));

        // no errors
        vm.expectEmit(false, false, false, true);
        emit NewFundsAdmin(liquidityProviderOne);
        ecosystemReserve.transferAdmin(liquidityProviderOne);
        assertEq(ecosystemReserve.getFundsAdmin(), liquidityProviderOne, "Incorrect funds admin");
    }

    /* ****************** */
    /*  Helper Functions  */
    /* ****************** */

    function _accrueAndCheckUserRewards(address token, address user, uint256 initialRewards)
        internal
        returns (uint256)
    {
        uint256 numMarkets = clearingHouse.getNumMarkets();
        uint256[] memory priorCumRewards = _getCumulativeRewardsByUserByToken(rewardDistributor, token, user);
        address[] memory markets = _getMarkets();
        rewardDistributor.accrueRewards(user);
        uint256 accruedRewards = rewardDistributor.rewardsAccruedByUser(user, token);
        assertGt(accruedRewards, 0, "Rewards not accrued");
        uint256 expectedAccruedRewards = initialRewards;
        for (uint256 i; i < numMarkets; ++i) {
            IPerpetual market = IPerpetual(markets[i]);
            uint256 cumulativeRewards = rewardDistributor.cumulativeRewardPerLpToken(token, address(market));
            expectedAccruedRewards += (cumulativeRewards - priorCumRewards[i]).wadMul(market.getLpLiquidity(user));
        }
        assertApproxEqRel(
            accruedRewards,
            expectedAccruedRewards,
            1e15, // 0.1%
            "Incorrect user rewards"
        );
        return accruedRewards;
    }

    function _getMarkets() internal view returns (address[] memory) {
        uint256 numMarkets = clearingHouse.getNumMarkets();
        address[] memory markets = new address[](numMarkets);
        for (uint256 i; i < numMarkets; ++i) {
            markets[i] = address(clearingHouse.perpetuals(clearingHouse.id(i)));
        }
        return markets;
    }

    function _getUserBalances(address user) internal view returns (uint256[] memory) {
        uint256 numMarkets = clearingHouse.getNumMarkets();
        uint256[] memory balances = new uint256[](numMarkets);
        for (uint256 i; i < numMarkets; ++i) {
            balances[i] = clearingHouse.perpetuals(clearingHouse.id(i)).getLpLiquidity(user);
        }
        return balances;
    }

    function _getRewardWeights(TestPerpRewardDistributor distributor, address token)
        internal
        view
        returns (uint256[] memory)
    {
        uint256 numMarkets = clearingHouse.getNumMarkets();
        uint256[] memory weights = new uint256[](numMarkets);
        for (uint256 i; i < numMarkets; ++i) {
            weights[i] = distributor.getRewardWeight(token, address(clearingHouse.perpetuals(clearingHouse.id(i))));
        }
        return weights;
    }

    function _getCumulativeRewardsByToken(TestPerpRewardDistributor distributor, address token)
        internal
        view
        returns (uint256[] memory)
    {
        uint256 numMarkets = clearingHouse.getNumMarkets();
        uint256[] memory cumulativeRewards = new uint256[](numMarkets);
        for (uint256 i; i < numMarkets; ++i) {
            cumulativeRewards[i] =
                distributor.cumulativeRewardPerLpToken(token, address(clearingHouse.perpetuals(clearingHouse.id(i))));
        }
        return cumulativeRewards;
    }

    function _getCumulativeRewardsByUserByToken(TestPerpRewardDistributor distributor, address token, address user)
        internal
        view
        returns (uint256[] memory)
    {
        uint256 numMarkets = clearingHouse.getNumMarkets();
        uint256[] memory cumulativeRewards = new uint256[](numMarkets);
        for (uint256 i; i < numMarkets; ++i) {
            cumulativeRewards[i] = distributor.cumulativeRewardPerLpTokenPerUser(
                user, token, address(clearingHouse.perpetuals(clearingHouse.id(i)))
            );
        }
        return cumulativeRewards;
    }

    function _getTotalLiquidityPerMarket(TestPerpRewardDistributor distributor)
        internal
        view
        returns (uint256[] memory)
    {
        uint256 numMarkets = clearingHouse.getNumMarkets();
        uint256[] memory totalLiquidity = new uint256[](numMarkets);
        for (uint256 i; i < numMarkets; ++i) {
            totalLiquidity[i] =
                distributor.totalLiquidityPerMarket(address(clearingHouse.perpetuals(clearingHouse.id(i))));
        }
        return totalLiquidity;
    }

    function _getSkipTimes(TestPerpRewardDistributor distributor) internal view returns (uint256[] memory) {
        uint256 numMarkets = clearingHouse.getNumMarkets();
        uint256[] memory skipTimes = new uint256[](numMarkets);
        for (uint256 i; i < numMarkets; ++i) {
            skipTimes[i] = block.timestamp
                - distributor.timeOfLastCumRewardUpdate(address(clearingHouse.perpetuals(clearingHouse.id(i))));
        }
        return skipTimes;
    }

    function _checkRewards(address token, address user, uint256 skipTime, uint256 initialRewards)
        internal
        returns (uint256)
    {
        uint256 accruedRewards = rewardDistributor.rewardsAccruedByUser(user, token);
        assertGt(accruedRewards, 0, "Rewards not accrued");
        uint256 expectedAccruedRewards = initialRewards;
        uint256 numMarkets = clearingHouse.getNumMarkets();
        for (uint256 i; i < numMarkets; ++i) {
            IPerpetual market = clearingHouse.perpetuals(clearingHouse.id(i));
            uint256 cumulativeRewards = rewardDistributor.cumulativeRewardPerLpToken(token, address(market));
            uint256 expectedCumulativeRewards = _calcExpectedCumulativeRewards(token, address(market), skipTime);
            assertApproxEqRel(
                cumulativeRewards,
                expectedCumulativeRewards,
                5e16, // 5%, accounts for reduction factor
                "Incorrect cumulative rewards"
            );
            uint256 lpBalance = market.getLpLiquidity(user);
            expectedAccruedRewards +=
                _calcExpectedUserRewards(rewardDistributor, cumulativeRewards, skipTime, lpBalance);
        }
        assertApproxEqRel(
            accruedRewards,
            expectedAccruedRewards,
            1e15, // 0.1%
            "Incorrect user rewards"
        );
        return accruedRewards;
    }

    function _checkRewards(
        address token,
        address user,
        uint256[] memory skipTimes,
        uint256[] memory lpBalances,
        uint256[] memory initialCumRewards,
        uint256[] memory priorTotalLiquidity,
        uint256 initialUserRewards
    ) internal returns (uint256) {
        uint256[] memory weights = _getRewardWeights(rewardDistributor, token);
        return _checkRewards(
            token, user, skipTimes, lpBalances, initialCumRewards, priorTotalLiquidity, weights, initialUserRewards
        );
    }

    function _checkRewards(
        address token,
        address user,
        uint256[] memory skipTimes,
        uint256[] memory lpBalances,
        uint256[] memory initialCumRewards,
        uint256[] memory priorTotalLiquidity,
        uint256[] memory weights,
        uint256 initialUserRewards
    ) internal returns (uint256) {
        return _checkRewards(
            rewardDistributor,
            token,
            user,
            skipTimes,
            lpBalances,
            initialCumRewards,
            priorTotalLiquidity,
            weights,
            initialUserRewards
        );
    }

    function _checkRewards(
        TestPerpRewardDistributor distributor,
        address token,
        address user,
        uint256[] memory skipTimes,
        uint256[] memory lpBalances,
        uint256[] memory initialCumRewards,
        uint256[] memory priorTotalLiquidity,
        uint256 initialUserRewards
    ) internal returns (uint256) {
        uint256[] memory weights = _getRewardWeights(distributor, token);
        return _checkRewards(
            distributor,
            token,
            user,
            skipTimes,
            lpBalances,
            initialCumRewards,
            priorTotalLiquidity,
            weights,
            initialUserRewards
        );
    }

    function _checkRewards(
        TestPerpRewardDistributor distributor,
        address token,
        address user,
        uint256[] memory skipTimes,
        uint256[] memory lpBalances,
        uint256[] memory initialCumRewards,
        uint256[] memory priorTotalLiquidity,
        uint256[] memory weights,
        uint256 initialUserRewards
    ) internal returns (uint256) {
        require(skipTimes.length == lpBalances.length, "Invalid input");
        require(skipTimes.length == initialCumRewards.length, "Invalid input");
        require(skipTimes.length == priorTotalLiquidity.length, "Invalid input");

        uint256 accruedRewards = distributor.rewardsAccruedByUser(user, token);
        assertGt(accruedRewards, 0, "Rewards not accrued");
        uint256 expectedAccruedRewards = _checkMarketRewards(
            distributor,
            token,
            initialUserRewards,
            skipTimes,
            lpBalances,
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
        uint256[] memory skipTimes,
        uint256[] memory lpBalances,
        uint256[] memory initialCumRewards,
        uint256[] memory priorTotalLiquidity
    ) internal returns (uint256) {
        uint256[] memory weights = _getRewardWeights(rewardDistributor, token);
        return _checkMarketRewards(
            token, initialUserRewards, skipTimes, lpBalances, initialCumRewards, priorTotalLiquidity, weights
        );
    }

    function _checkMarketRewards(
        address token,
        uint256 initialUserRewards,
        uint256[] memory skipTimes,
        uint256[] memory lpBalances,
        uint256[] memory initialCumRewards,
        uint256[] memory priorTotalLiquidity,
        uint256[] memory weights
    ) internal returns (uint256) {
        return _checkMarketRewards(
            rewardDistributor,
            token,
            initialUserRewards,
            skipTimes,
            lpBalances,
            initialCumRewards,
            priorTotalLiquidity,
            weights
        );
    }

    function _checkMarketRewards(
        TestPerpRewardDistributor distributor,
        address token,
        uint256 initialUserRewards,
        uint256[] memory skipTimes,
        uint256[] memory lpBalances,
        uint256[] memory initialCumRewards,
        uint256[] memory priorTotalLiquidity
    ) internal returns (uint256) {
        uint256[] memory weights = _getRewardWeights(distributor, token);
        return _checkMarketRewards(
            distributor,
            token,
            initialUserRewards,
            skipTimes,
            lpBalances,
            initialCumRewards,
            priorTotalLiquidity,
            weights
        );
    }

    function _checkMarketRewards(
        TestPerpRewardDistributor distributor,
        address token,
        uint256 initialUserRewards,
        uint256[] memory skipTimes,
        uint256[] memory lpBalances,
        uint256[] memory initialCumRewards,
        uint256[] memory priorTotalLiquidity,
        uint256[] memory weights
    ) internal returns (uint256) {
        uint256 expectedAccruedRewards = initialUserRewards;
        uint256 numMarkets = clearingHouse.getNumMarkets();
        require(numMarkets == skipTimes.length, "Invalid input");
        for (uint256 i; i < numMarkets; ++i) {
            IPerpetual market = clearingHouse.perpetuals(clearingHouse.id(i));
            uint256 cumulativeRewards =
                distributor.cumulativeRewardPerLpToken(token, address(market)) - initialCumRewards[i];
            uint256 expectedCumulativeRewards =
                _calcExpectedCumulativeRewards(token, skipTimes[i], priorTotalLiquidity[i], weights[i]);
            assertApproxEqRel(
                cumulativeRewards,
                expectedCumulativeRewards,
                5e16, // 5%, accounts for reduction factor
                "Incorrect cumulative rewards"
            );
            expectedAccruedRewards +=
                _calcExpectedUserRewards(distributor, cumulativeRewards, skipTimes[i], lpBalances[i]);
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

    function _calcExpectedUserRewards(
        TestPerpRewardDistributor distributor,
        uint256 cumulativeRewards,
        uint256 skipTime,
        uint256 lpBalance
    ) internal view returns (uint256) {
        uint256 thresholdTime = distributor.earlyWithdrawalThreshold();
        if (skipTime > thresholdTime) {
            skipTime = thresholdTime;
        }
        return cumulativeRewards.wadMul(lpBalance) * skipTime / thresholdTime;
    }

    function _provideLiquidityBothPerps(address user, uint256 amount1, uint256 amount2)
        internal
        returns (uint256 percentOfLiquidity1, uint256 percentOfLiquidity2)
    {
        // provide some liquidity
        fundAndPrepareAccount(user, amount1 + amount2, vault, ua);
        _provideLiquidity(amount1, user, perpetual);
        _provideLiquidity(amount2, user, eth_perpetual);
        percentOfLiquidity1 = (amount1 * 1e18) / (10_000e18 + amount1);
        percentOfLiquidity2 = (amount2 * 1e18) / (10_000e18 + amount2);
    }

    function _provideLiquidity(uint256 depositAmount, address user, TestPerpetual perp) internal {
        vm.startPrank(user);

        clearingHouse.deposit(depositAmount, ua);
        uint256 quoteAmount = depositAmount / 2;
        uint256 baseAmount = quoteAmount.wadDiv(perp.indexPrice().toUint256());
        clearingHouse.provideLiquidity(_getMarketIdx(address(perp)), [quoteAmount, baseAmount], 0);
        vm.stopPrank();
    }

    function _removeAllLiquidity(address user, TestPerpetual perp) internal {
        vm.startPrank(user);

        uint256 proposedAmount = _getLiquidityProviderProposedAmount(user, perp, 1e18);
        /*
        according to curve v2 whitepaper:
        discard values that do not converge
        */
        // vm.assume(proposedAmount > 1e17);

        clearingHouse.removeLiquidity(
            _getMarketIdx(address(perp)),
            perp.getLpPosition(user).liquidityBalance,
            [uint256(0), uint256(0)],
            proposedAmount,
            0
        );

        // clearingHouse.withdrawAll(ua);
    }

    function _removeSomeLiquidity(address user, TestPerpetual perp, uint256 reductionRatio) internal {
        uint256 lpBalance = perp.getLpPosition(user).liquidityBalance;
        uint256 amount = (lpBalance * reductionRatio) / 1e18;
        uint256 idx = _getMarketIdx(address(perp));
        vm.startPrank(user);
        uint256 proposedAmount = _getLiquidityProviderProposedAmount(user, perp, reductionRatio);
        clearingHouse.removeLiquidity(idx, amount, [uint256(0), uint256(0)], proposedAmount, 0);

        // clearingHouse.withdrawAll(ua);
    }

    function _getMarketIdx(address perp) internal view returns (uint256) {
        uint256 numMarkets = clearingHouse.getNumMarkets();
        for (uint256 i; i < numMarkets; ++i) {
            uint256 idx = clearingHouse.id(i);
            if (perp == address(clearingHouse.perpetuals(idx))) {
                return idx;
            }
        }
        return type(uint256).max;
    }

    function _getLiquidityProviderProposedAmount(address user, IPerpetual perp, uint256 reductionRatio)
        internal
        returns (uint256 proposedAmount)
    {
        LibPerpetual.LiquidityProviderPosition memory lp = perp.getLpPosition(user);
        if (lp.liquidityBalance == 0) revert("No liquidity provided");
        uint256 idx = _getMarketIdx(address(perp));
        return viewer.getLpProposedAmount(idx, user, reductionRatio, 100, [uint256(0), uint256(0)], 0);
    }

    function _viewNewRewardAccrual(address user) internal view returns (uint256[] memory) {
        uint256 numMarkets = clearingHouse.getNumMarkets();
        uint256 numTokens = rewardDistributor.getRewardTokenCount();
        uint256[] memory newRewards = new uint256[](numTokens);
        for (uint256 i; i < numMarkets; ++i) {
            address market = address(clearingHouse.perpetuals(clearingHouse.id(i)));
            uint256[] memory marketRewards = _viewNewRewardAccrual(market, user);
            for (uint256 j; j < numTokens; ++j) {
                newRewards[j] += marketRewards[j];
            }
        }
        return newRewards;
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
        uint256 timeOfLastCumRewardUpdate = rewardDistributor.timeOfLastCumRewardUpdate(market);
        uint256 deltaTime = block.timestamp - timeOfLastCumRewardUpdate;
        if (rewardDistributor.totalLiquidityPerMarket(market) == 0) return 0;
        // Calculate the new cumRewardPerLpToken by adding (inflationRatePerSecond x guageWeight x deltaTime) to the previous cumRewardPerLpToken
        uint256 marketWeight = rewardDistributor.getRewardWeight(token, market);
        uint256 newMarketRewards =
            (((rewardDistributor.getInflationRate(token) * marketWeight) / 10000) * deltaTime) / 365 days;
        uint256 newCumRewardPerLpToken = rewardDistributor.cumulativeRewardPerLpToken(token, market)
            + newMarketRewards.wadDiv(rewardDistributor.totalLiquidityPerMarket(market));
        uint256 newUserRewards = rewardDistributor.lpPositionsPerUser(user, market).wadMul(
            (newCumRewardPerLpToken - rewardDistributor.cumulativeRewardPerLpTokenPerUser(user, token, market))
        );
        return newUserRewards;
    }

    function _addRewardToken(uint256 marketWeight1, uint256 totalSupply, uint88 inflationRate, uint88 reductionFactor)
        internal
        returns (IncrementToken token)
    {
        address[] memory markets = new address[](2);
        markets[0] = address(perpetual);
        markets[1] = address(eth_perpetual);
        uint256[] memory marketWeights = new uint256[](2);
        marketWeights[0] = marketWeight1;
        marketWeights[1] = 10000 - marketWeight1;
        token = new IncrementToken(totalSupply, address(this));
        token.unpause();
        rewardDistributor.addRewardToken(address(token), inflationRate, reductionFactor, markets, marketWeights);
        token.transfer(address(ecosystemReserve), token.totalSupply());
        ecosystemReserve.approve(token, address(rewardDistributor), type(uint256).max);
    }

    function _deployTestPerpetual() internal returns (TestPerpetual) {
        // solhint-disable-next-line var-name-mixedcase
        AggregatorV3Interface dai_baseOracle =
            AggregatorV3Interface(address(0xAed0c38402a5d19df6E4c03F4E2DceD6e29c1ee9));
        VBase vBase3 =
            new VBase("vDAI base token", "vDAI", dai_baseOracle, 30 days, sequencerUptimeFeed, ETHUSD.gracePeriod);
        VQuote vQuote3 = new VQuote("vUSD quote token", "vUSD");
        (, int256 answer,,,) = baseOracle.latestRoundData();
        uint8 decimals = dai_baseOracle.decimals();
        uint256 initialPrice = answer.toUint256() * (10 ** (18 - decimals));
        TestPerpetual perpetual3 = new TestPerpetual(
            vBase3,
            vQuote3,
            ICryptoSwap(
                factory.deploy_pool(
                    "DAI_USD",
                    "DAI_USD",
                    [address(vQuote3), address(vBase3)],
                    ETHUSD.A,
                    ETHUSD.gamma,
                    ETHUSD.mid_fee,
                    ETHUSD.out_fee,
                    ETHUSD.allowed_extra_profit,
                    ETHUSD.fee_gamma,
                    ETHUSD.adjustment_step,
                    ETHUSD.admin_fee,
                    ETHUSD.ma_half_time,
                    initialPrice
                )
            ),
            clearingHouse,
            curveCryptoViews,
            true,
            IPerpetual.PerpetualParams(
                ETHUSD.riskWeight,
                ETHUSD.maxLiquidityProvided,
                ETHUSD.twapFrequency,
                ETHUSD.sensitivity,
                ETHUSD.maxBlockTradeAmount,
                ETHUSD.insuranceFee,
                ETHUSD.lpDebtCoef,
                ETHUSD.lockPeriod
            )
        );

        vBase3.transferPerpOwner(address(perpetual3));
        vQuote3.transferPerpOwner(address(perpetual3));
        return perpetual3;
    }

    /* ***************** */
    /*   Error Helpers   */
    /* ***************** */

    function _expectInvalidRewardTokenAddress(address token) internal {
        vm.expectRevert(abi.encodeWithSignature("RewardController_InvalidRewardTokenAddress(address)", token));
    }

    function _expectAboveMaxInflationRate(uint256 inflationRate, uint256 maxInflationRate) internal {
        vm.expectRevert(
            abi.encodeWithSignature(
                "RewardController_AboveMaxInflationRate(uint256,uint256)", inflationRate, maxInflationRate
            )
        );
    }

    function _expectBelowMinReductionFactor(uint256 reductionFactor, uint256 minReductionFactor) internal {
        vm.expectRevert(
            abi.encodeWithSignature(
                "RewardController_BelowMinReductionFactor(uint256,uint256)", reductionFactor, minReductionFactor
            )
        );
    }

    function _expectAboveMaxRewardTokens(uint256 numTokens) internal {
        vm.expectRevert(abi.encodeWithSignature("RewardController_AboveMaxRewardTokens(uint256)", numTokens));
    }

    function _expectIncorrectWeightsCount(uint256 numWeights, uint256 numMarkets) internal {
        vm.expectRevert(
            abi.encodeWithSignature("RewardController_IncorrectWeightsCount(uint256,uint256)", numWeights, numMarkets)
        );
    }

    function _expectWeightExceedsMax(uint256 weight, uint256 maxWeight) internal {
        vm.expectRevert(
            abi.encodeWithSignature("RewardController_WeightExceedsMax(uint256,uint256)", weight, maxWeight)
        );
    }

    function _expectIncorrectWeightsSum(uint256 sum, uint256 expected) internal {
        vm.expectRevert(abi.encodeWithSignature("RewardController_IncorrectWeightsSum(uint256,uint256)", sum, expected));
    }

    function _expectCallerIsNotClearingHouse(address caller) internal {
        vm.expectRevert(abi.encodeWithSignature("PerpRewardDistributor_CallerIsNotClearingHouse(address)", caller));
    }

    function _expectAlreadyInitializedStartTime(address market) internal {
        vm.expectRevert(abi.encodeWithSignature("RewardDistributor_AlreadyInitializedStartTime(address)", market));
    }

    function _expectPositionAlreadyRegistered(address user, address market, uint256 position) internal {
        vm.expectRevert(
            abi.encodeWithSignature(
                "RewardDistributor_PositionAlreadyRegistered(address,address,uint256)", user, market, position
            )
        );
    }

    function _expectAccessControlGovernanceRole(address account) internal {
        vm.expectRevert(
            bytes(
                string(
                    abi.encodePacked(
                        "AccessControl: account ",
                        Strings.toHexString(account),
                        " is missing role ",
                        Strings.toHexString(uint256(keccak256("GOVERNANCE")), 32)
                    )
                )
            )
        );
    }
}
