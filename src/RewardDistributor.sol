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

contract RewardDistributor is IRewardDistributor, GaugeController {
    using SafeERC20 for IERC20Metadata;
    using LibMath for uint256;

    /// @notice Rewards accrued and not yet claimed by user
    mapping(address => uint256) public rewardsAccruedByUser;

    /// @notice INCR token used for rewards
    IERC20Metadata public override rewardToken;

    /// @notice Vault contract
    IVault public override vault;

    constructor(
        uint256 _initialInflationRate,
        uint256 _initialReductionFactor,
        address _rewardToken, 
        address _clearingHouse,
        address _safetyModule,
        address _vault
    ) GaugeController(
        _initialInflationRate, 
        _initialReductionFactor, 
        _clearingHouse, 
        _safetyModule
    ) {
        rewardToken = IERC20Metadata(_rewardToken);
        vault = IVault(_vault);
    }
}
