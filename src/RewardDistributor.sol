// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.15;

// contracts
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IncreAccessControl} from "increment-protocol/utils/IncreAccessControl.sol";
import {GaugeController} from "./GaugeController.sol";

// interfaces
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IClearingHouse} from "increment-protocol/interfaces/IClearingHouse.sol";
import {IPerpetual} from "increment-protocol/interfaces/IPerpetual.sol";
import {IInsurance} from "increment-protocol/interfaces/IInsurance.sol";
import {IVault} from "increment-protocol/interfaces/IVault.sol";
import {ICryptoSwap} from "increment-protocol/interfaces/ICryptoSwap.sol";
import {IStakingContract} from "increment-protocol/interfaces/IStakingContract.sol";
import {IRewardDistributor} from "./interfaces/IRewardDistributor.sol";

// libraries
import {LibMath} from "increment-protocol/lib/LibMath.sol";
import {LibPerpetual} from "increment-protocol/lib/LibPerpetual.sol";
import {LibReserve} from "increment-protocol/lib/LibReserve.sol";

contract RewardDistributor is IRewardDistributor, IStakingContract, GaugeController {
    using SafeERC20 for IERC20Metadata;
    using LibMath for uint256;

    /// @notice Rewards accrued and not yet claimed by user
    mapping(address => uint256) public rewardsAccruedByUser;

    /// @notice Last timestamp when user accrued rewards
    mapping(address => uint256) public lastAccrualTimeByUser;

    /// @notice Last timestamp when user withdrew liquidity
    mapping(address => uint256) public lastWithdrawalTimeByUser;

    /// @notice Latest LP positions per user and market index
    /// @dev Market index is ClearingHouse.perpetuals index
    mapping(address => uint256[]) public lpPositionsPerUser;

    /// @notice Total LP tokens registered for rewards per market
    /// @dev Market index is ClearingHouse.perpetuals index
    mapping(uint256 => uint256) public totalLiquidityPerMarket;

    /// @notice INCR token used for rewards
    IERC20Metadata public override rewardToken;

    /// @notice Amount of time after which LPs can remove liquidity without penalties
    uint256 public override earlyWithdrawalThreshold;

    constructor(
        uint256 _initialInflationRate,
        uint256 _initialReductionFactor,
        address _rewardToken, 
        address _clearingHouse,
        uint256 _earlyWithdrawalThreshold
    ) GaugeController(
        _initialInflationRate, 
        _initialReductionFactor, 
        _clearingHouse
    ) {
        rewardToken = IERC20Metadata(_rewardToken);
        earlyWithdrawalThreshold = _earlyWithdrawalThreshold;
    }

    /* *********************** */
    /* External Clearing House */
    /* *********************** */

    function updateStakingPosition(uint256 idx, address user) external override nonReentrant onlyClearingHouse {
        require(idx < clearingHouse.getNumMarkets(), "Invalid perpetual index");
        IPerpetual perp = clearingHouse.perpetuals(idx);
        uint256 prevLpPosition = lpPositionsPerUser[user][idx];
        uint256 newLpPosition = perp.getLpLiquidity(user);
        uint256 prevTotalLiquidity = totalLiquidityPerMarket[idx];
        if (newLpPosition >= prevLpPosition) {
            // Added liquidity

        } else {
            // Removed liquidity - need to check if within early withdrawal threshold
            if (block.timestamp - lastWithdrawalTimeByUser[user] < earlyWithdrawalThreshold) {
                // Early withdrawal - apply penalty

            } else {
                // Not an early withdrawal - no penalty

            }
            lastWithdrawalTimeByUser[user] = block.timestamp;
        }
    }

    /* ****************** */
    /*    External User   */
    /* ****************** */

    function registerPositions() external nonReentrant {
        uint256 numMarkets = clearingHouse.getNumMarkets();
        for(uint i; i < numMarkets; ++i) {
            require(i < clearingHouse.getNumMarkets(), "Invalid perpetual index");
            require(lpPositionsPerUser[msg.sender][i] == 0, "Position already registered");
            IPerpetual perp = clearingHouse.perpetuals(i);
            uint256 lpPosition = perp.getLpLiquidity(msg.sender);
            lpPositionsPerUser[msg.sender][i] = lpPosition;
            totalLiquidityPerMarket[i] += lpPosition;
        }
    }

    function registerPositions(uint256[] calldata _marketIndexes) external nonReentrant {
        for(uint i; i < _marketIndexes.length; ++i) {
            uint256 idx = _marketIndexes[i];
            require(idx < clearingHouse.getNumMarkets(), "Invalid perpetual index");
            require(lpPositionsPerUser[msg.sender][idx] == 0, "Position already registered");
            IPerpetual perp = clearingHouse.perpetuals(idx);
            uint256 lpPosition = perp.getLpLiquidity(msg.sender);
            lpPositionsPerUser[msg.sender][idx] = lpPosition;
            totalLiquidityPerMarket[idx] += lpPosition;
        }
    }

    function claimRewards() public override {
        claimRewardsFor(msg.sender);
    }

    function claimRewardsFor(address user) public override nonReentrant whenNotPaused {
        uint256 rewards = rewardsAccruedByUser[user];
        require(rewards > 0, "RewardDistributor: no rewards to claim");
        lastAccrualTimeByUser[user] = block.timestamp;
        rewardsAccruedByUser[user] = _distributeReward(user, rewards);
        emit RewardClaimed(user, rewards);
    }


    /* ****************** */
    /*      Internal      */
    /* ****************** */

    function _distributeReward(address _to, uint256 _amount) internal returns (uint256) {
        uint256 rewardsRemaining = _rewardTokenBalance();
        if (_amount > 0 && _amount <= rewardsRemaining) {
            rewardToken.safeTransfer(_to, _amount);
            return 0;
        }
        return _amount;
    }

    function _rewardTokenBalance() internal view returns (uint256) {
        return rewardToken.balanceOf(address(this));
    }
}
