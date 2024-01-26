// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.16;

// contracts
import "../mocks/TestPerpRewardDistributor.sol";
import "../../contracts/EcosystemReserve.sol";
import "../../lib/increment-protocol/test/helpers/Deployment.MainnetFork.sol";
import {IncrementToken} from "@increment-governance/IncrementToken.sol";
import {ClearingHouseHandler} from "./handlers/ClearingHouseHandler.sol";
import {PerpRewardDistributorHandler} from "./handlers/PerpRewardDistributorHandler.sol";

// interfaces
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

// libraries
import {LibMath} from "increment-protocol/lib/LibMath.sol";
import {console2 as console} from "forge/console2.sol";

contract PerpRewardsInvariantTest is Deployment {
    using LibMath for int256;
    using LibMath for uint256;

    // Constants
    uint88 constant INITIAL_INFLATION_RATE = 1463753e18;
    uint88 constant INITIAL_REDUCTION_FACTOR = 1.189207115e18;
    uint256 constant INITIAL_WITHDRAW_THRESHOLD = 10 days;

    // Actors
    address lpOne = address(123);
    address lpTwo = address(456);
    address lpThree = address(789);
    address[] lps = [lpOne, lpTwo, lpThree];

    // Perpetuals
    TestPerpetual[] public perpetuals;

    // Peripherals
    IERC20[] public rewardTokens;
    TestPerpRewardDistributor public rewardDistributor;
    EcosystemReserve public ecosystemReserve;

    // Handlers
    ClearingHouseHandler public clearingHouseHandler;
    PerpRewardDistributorHandler public rewardDistributorHandler;

    // Invariant ghost variables
    mapping(address => mapping(address => uint256)) public lastMarketAccumulatorValue;

    mapping(address => mapping(address => mapping(address => uint256))) public lastUserAccumulatorValue;

    mapping(address => mapping(address => uint256)) public lastUserRewardsBalance;

    mapping(address => mapping(address => uint256)) public lastUserRewardsAccrued;

    function setUp() public override {
        // Fund actors with ETH
        deal(lpOne, 100 ether);
        deal(lpTwo, 100 ether);
        deal(lpThree, 100 ether);
        deal(address(this), 100 ether);

        // Deploy protocol with two perpetual markets
        super.setUp();
        _deployEthMarket();
        perpetuals.push(perpetual);
        perpetuals.push(eth_perpetual);
        clearingHouseHandler = new ClearingHouseHandler(clearingHouse, viewer, lps, ua);

        // Deploy the Ecosystem Reserve vault
        ecosystemReserve = new EcosystemReserve(address(this));

        // Deploy first reward token
        IncrementToken rewardsToken = new IncrementToken(20000000e18, address(this));
        rewardTokens.push(rewardsToken);

        // Deploy the reward distributor with initial reward token and market weights
        uint256[] memory weights = new uint256[](2);
        weights[0] = 7500;
        weights[1] = 2500;
        rewardDistributor = new TestPerpRewardDistributor(
            INITIAL_INFLATION_RATE,
            INITIAL_REDUCTION_FACTOR,
            address(rewardTokens[0]),
            address(clearingHouse),
            address(ecosystemReserve),
            INITIAL_WITHDRAW_THRESHOLD,
            weights
        );
        rewardDistributorHandler = new PerpRewardDistributorHandler(rewardDistributor, lps);

        // Transfer all rewards tokens to the vault and approve the distributor
        rewardsToken.transfer(address(ecosystemReserve), rewardsToken.totalSupply());
        ecosystemReserve.approve(rewardsToken, address(rewardDistributor), type(uint256).max);

        // Connect clearing house to the reward distributor
        clearingHouse.addRewardContract(rewardDistributor);

        // Set handlers as target contracts
        targetContract(address(clearingHouseHandler));
        targetContract(address(rewardDistributorHandler));

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

        // Make VBase heartbeat more forgiving
        vBase.setHeartBeat(30 days);
        eth_vBase.setHeartBeat(30 days);
    }

    /* ****************** */
    /*     Invariants     */
    /* ****************** */

    function invariantMarketAccumulatorNeverDecreases() public {
        uint256 numRewards = rewardDistributor.getRewardTokenCount();
        uint256 numMarkets = clearingHouse.getNumMarkets();
        for (uint256 i; i < numRewards; i++) {
            address rewardToken = rewardDistributor.rewardTokens(i);
            for (uint256 j; j < numMarkets; j++) {
                address market = address(clearingHouse.perpetuals(clearingHouse.id(j)));
                uint256 accumulatorValue = rewardDistributor.cumulativeRewardPerLpToken(rewardToken, market);
                assertGe(
                    accumulatorValue,
                    lastMarketAccumulatorValue[rewardToken][market],
                    "Invariant: accumulator does not decrease"
                );
                lastMarketAccumulatorValue[rewardToken][market] = accumulatorValue;
            }
        }
    }

    function invariantUserAccumulatorUpdatesOnAccrual() public {
        uint256 numRewards = rewardDistributor.getRewardTokenCount();
        uint256 numMarkets = clearingHouse.getNumMarkets();
        for (uint256 i; i < numRewards; i++) {
            address rewardToken = rewardDistributor.rewardTokens(i);
            for (uint256 j; j < numMarkets; j++) {
                address market = address(clearingHouse.perpetuals(clearingHouse.id(j)));
                uint256 marketAccumulatorValue = rewardDistributor.cumulativeRewardPerLpToken(rewardToken, market);
                for (uint256 k; k < lps.length; k++) {
                    address lp = lps[k];
                    uint256 userAccumulatorValue =
                        rewardDistributor.cumulativeRewardPerLpTokenPerUser(lp, rewardToken, market);
                    assertGe(
                        userAccumulatorValue,
                        lastUserAccumulatorValue[lp][rewardToken][market],
                        "Invariant: user accumulator does not decrease"
                    );
                    lastUserAccumulatorValue[lp][rewardToken][market] = userAccumulatorValue;
                    if (userAccumulatorValue == marketAccumulatorValue) {
                        uint256 rewardsAccrued = rewardDistributor.rewardsAccruedByUser(lp, rewardToken);
                        uint256 rewardsBalance = IERC20(rewardToken).balanceOf(lp);
                        if (rewardsAccrued > 0) {
                            assertGe(
                                rewardsAccrued,
                                lastUserRewardsAccrued[lp][rewardToken],
                                "Invariant: user accumulator updates on reward accrual"
                            );
                        } else {
                            assertGe(
                                rewardsBalance,
                                lastUserRewardsBalance[lp][rewardToken],
                                "Invariant: user accumulator updates on claim rewards"
                            );
                        }
                        lastUserRewardsAccrued[lp][rewardToken] = rewardsAccrued;
                        lastUserRewardsBalance[lp][rewardToken] = rewardsBalance;
                    }
                }
            }
        }
        skip(1 days);
    }

    function invariantLPPositionsMatch() public {
        uint256 numMarkets = clearingHouse.getNumMarkets();
        for (uint256 i; i < numMarkets; i++) {
            IPerpetual perp = clearingHouse.perpetuals(clearingHouse.id(i));
            address market = address(perp);
            for (uint256 j; j < lps.length; j++) {
                address lp = lps[j];
                assertEq(
                    rewardDistributor.lpPositionsPerUser(lp, market),
                    perp.getLpLiquidity(lp),
                    "Invariant: lp positions always match in Perpetual and PerpRewardDistributor"
                );
            }
        }
    }

    function invariantTotalLiquidityMatches() public {
        uint256 numMarkets = clearingHouse.getNumMarkets();
        for (uint256 i; i < numMarkets; i++) {
            IPerpetual perp = clearingHouse.perpetuals(clearingHouse.id(i));
            address market = address(perp);
            assertEq(
                rewardDistributor.totalLiquidityPerMarket(market),
                perp.getTotalLiquidityProvided(),
                "Invariant: total liquidity always matches in Perpetual and PerpRewardDistributor"
            );
        }
    }

    function invariantSumOfAccruedRewardsUnclaimed() public {
        uint256 numRewards = rewardDistributor.getRewardTokenCount();
        for (uint256 i; i < numRewards; i++) {
            address rewardToken = rewardDistributor.rewardTokens(i);
            uint256 totalUnclaimedRewards = rewardDistributor.totalUnclaimedRewards(rewardToken);
            uint256 sumOfAccruedRewards;
            for (uint256 j; j < lps.length; j++) {
                address lp = lps[j];
                sumOfAccruedRewards += rewardDistributor.rewardsAccruedByUser(lp, rewardToken);
            }
            assertEq(
                totalUnclaimedRewards,
                sumOfAccruedRewards,
                "Invariant: sum of accrued rewards equals total unclaimed rewards"
            );
        }
    }
}
