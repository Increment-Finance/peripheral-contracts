// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.16;

// contracts
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IncreAccessControl} from "@increment/utils/IncreAccessControl.sol";

// interfaces
import {ISafetyModule, ISMRewardDistributor} from "./interfaces/ISafetyModule.sol";
import {IStakedToken, IERC20} from "./interfaces/IStakedToken.sol";
import {IAuctionModule} from "./interfaces/IAuctionModule.sol";
import {IRewardContract} from "@increment/interfaces/IRewardContract.sol";

// libraries
import {PRBMathUD60x18} from "prb-math/contracts/PRBMathUD60x18.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title SafetyModule
/// @author webthethird
/// @notice Handles reward accrual and distribution for staking tokens, and allows governance to auction a
/// percentage of user funds in the event of an insolvency in the vault
contract SafetyModule is ISafetyModule, IncreAccessControl, Pausable, ReentrancyGuard {
    using PRBMathUD60x18 for uint256;
    using SafeERC20 for IERC20;

    /// @notice Address of the auction module, which sells user funds in the event of an insolvency
    IAuctionModule public auctionModule;

    /// @notice Address of the SMRewardDistributor contract, which distributes rewards to stakers
    ISMRewardDistributor public smRewardDistributor;

    /// @notice Array of staking tokens that are registered with the SafetyModule
    IStakedToken[] public stakingTokens;

    /// @notice Mapping from auction ID to staking token that was slashed for the auction
    mapping(uint256 => IStakedToken) public stakingTokenByAuctionId;

    /// @notice Modifier for functions that can only be called by a registered StakedToken contract,
    /// i.e., `updatePosition`
    modifier onlyStakingToken() {
        bool isStakingToken;
        uint256 numTokens = stakingTokens.length;
        for (uint256 i; i < numTokens;) {
            if (msg.sender == address(stakingTokens[i])) {
                isStakingToken = true;
                break;
            }
            unchecked {
                ++i;
            }
        }
        if (!isStakingToken) {
            revert SafetyModule_CallerIsNotStakingToken(msg.sender);
        }
        _;
    }

    /// @notice Modifier for functions that can only be called by the AuctionModule contract,
    /// i.e., `auctionEnded`
    modifier onlyAuctionModule() {
        if (msg.sender != address(auctionModule)) {
            revert SafetyModule_CallerIsNotAuctionModule(msg.sender);
        }
        _;
    }

    /// @notice SafetyModule constructor
    /// @param _auctionModule Address of the auction module, which sells user funds in the event of an insolvency
    /// @param _smRewardDistributor Address of the SMRewardDistributor contract, which distributes rewards to stakers
    constructor(address _auctionModule, address _smRewardDistributor) payable {
        auctionModule = IAuctionModule(_auctionModule);
        smRewardDistributor = ISMRewardDistributor(_smRewardDistributor);
        emit AuctionModuleUpdated(address(0), _auctionModule);
        emit RewardDistributorUpdated(address(0), _smRewardDistributor);
    }

    /* ****************** */
    /*      Markets       */
    /* ****************** */

    /// @inheritdoc ISafetyModule
    function getStakingTokens() external view returns (IStakedToken[] memory) {
        return stakingTokens;
    }

    /// @inheritdoc ISafetyModule
    function getNumStakingTokens() public view returns (uint256) {
        return stakingTokens.length;
    }

    /// @inheritdoc ISafetyModule
    function getStakingTokenIdx(address token) public view returns (uint256) {
        uint256 numTokens = stakingTokens.length;
        for (uint256 i; i < numTokens;) {
            if (address(stakingTokens[i]) == token) return i;
            unchecked {
                ++i;
            }
        }
        revert SafetyModule_InvalidStakingToken(token);
    }

    /* ****************** */
    /*   Reward Accrual   */
    /* ****************** */

    /// @inheritdoc ISafetyModule
    /// @dev Only callable by a registered StakedToken contract
    function updatePosition(address stakedToken, address staker) external override nonReentrant onlyStakingToken {
        smRewardDistributor.updatePosition(stakedToken, staker);
    }

    /* ****************** */
    /*   Auction Module   */
    /* ****************** */

    /// @inheritdoc ISafetyModule
    /// @dev Only callable by the auction module
    function auctionEnded(uint256 _auctionId, uint256 _remainingBalance) external onlyAuctionModule {
        IStakedToken stakingToken = stakingTokenByAuctionId[_auctionId];
        if (_remainingBalance != 0) {
            _returnFunds(stakingToken, address(auctionModule), _remainingBalance);
        }
        _settleSlashing(stakingToken);
        emit AuctionEnded(
            _auctionId, address(stakingToken), address(stakingToken.getUnderlyingToken()), _remainingBalance
        );
    }

    /* ****************** */
    /*     Governance     */
    /* ****************** */

    /// @inheritdoc ISafetyModule
    /// @dev Only callable by governance
    function slashAndStartAuction(
        address _stakedToken,
        uint8 _numLots,
        uint128 _lotPrice,
        uint128 _initialLotSize,
        uint64 _slashPercent,
        uint96 _lotIncreaseIncrement,
        uint16 _lotIncreasePeriod,
        uint32 _timeLimit
    ) external onlyRole(GOVERNANCE) returns (uint256) {
        if (_slashPercent > 1e18) {
            revert SafetyModule_InvalidSlashPercentTooHigh();
        }

        IStakedToken stakedToken = stakingTokens[getStakingTokenIdx(_stakedToken)];

        // Slash the staked tokens and transfer the underlying tokens to the auction module
        uint256 slashAmount = stakedToken.totalSupply().mul(_slashPercent);
        uint256 underlyingAmount = stakedToken.slash(address(auctionModule), slashAmount);

        // Make sure the amount of underlying tokens transferred to the auction module is enough to
        // cover the initial lot size and number of lots to auction
        if (underlyingAmount < uint256(_initialLotSize) * uint256(_numLots)) {
            revert SafetyModule_InsufficientSlashedTokensForAuction(
                stakedToken.getUnderlyingToken(), uint256(_initialLotSize) * uint256(_numLots), underlyingAmount
            );
        }

        // Start the auction and return the auction ID
        // Note: the AuctionModule contract will revert if zero is passed for any of the parameters
        uint256 auctionId = auctionModule.startAuction(
            stakedToken.getUnderlyingToken(),
            _numLots,
            _lotPrice,
            _initialLotSize,
            _lotIncreaseIncrement,
            _lotIncreasePeriod,
            _timeLimit
        );
        stakingTokenByAuctionId[auctionId] = stakedToken;
        emit TokensSlashedForAuction(_stakedToken, slashAmount, underlyingAmount, auctionId);
        return auctionId;
    }

    /// @inheritdoc ISafetyModule
    /// @dev Only callable by governance
    function terminateAuction(uint256 _auctionId) external onlyRole(GOVERNANCE) {
        auctionModule.terminateAuction(_auctionId);
        IERC20 auctionToken = auctionModule.getAuctionToken(_auctionId);
        IStakedToken stakingToken = stakingTokenByAuctionId[_auctionId];
        uint256 remainingBalance = auctionToken.balanceOf(address(auctionModule));
        // Remaining balance should always be non-zero, since the only way the auction module could run out
        // of auction tokens is if they are all sold, in which case the auction would have ended on its own
        // But just in case, check to avoid reverting
        if (remainingBalance != 0) {
            _returnFunds(stakingToken, address(auctionModule), remainingBalance);
        }
        _settleSlashing(stakingToken);
        emit AuctionTerminated(_auctionId, address(stakingToken), address(auctionToken), remainingBalance);
    }

    /// @inheritdoc ISafetyModule
    /// @dev Only callable by governance
    function returnFunds(address _stakingToken, address _from, uint256 _amount) external onlyRole(GOVERNANCE) {
        IStakedToken stakingToken = stakingTokens[getStakingTokenIdx(_stakingToken)];
        _returnFunds(stakingToken, _from, _amount);
    }

    /// @inheritdoc ISafetyModule
    /// @dev Only callable by governance
    function withdrawFundsRaisedFromAuction(uint256 _amount) external onlyRole(GOVERNANCE) {
        IERC20 paymentToken = auctionModule.paymentToken();
        paymentToken.safeTransferFrom(address(auctionModule), msg.sender, _amount);
    }

    /// @inheritdoc ISafetyModule
    /// @dev Only callable by governance
    function setAuctionModule(IAuctionModule _newAuctionModule) external onlyRole(GOVERNANCE) {
        emit AuctionModuleUpdated(address(auctionModule), address(_newAuctionModule));
        auctionModule = _newAuctionModule;
    }

    /// @inheritdoc ISafetyModule
    /// @dev Only callable by governance
    function setRewardDistributor(ISMRewardDistributor _newRewardDistributor) external onlyRole(GOVERNANCE) {
        emit RewardDistributorUpdated(address(smRewardDistributor), address(_newRewardDistributor));
        smRewardDistributor = _newRewardDistributor;
    }

    /// @inheritdoc ISafetyModule
    /// @dev Only callable by governance, reverts if the staking token is already registered
    function addStakingToken(IStakedToken _stakingToken) external onlyRole(GOVERNANCE) {
        uint256 numTokens = stakingTokens.length;
        for (uint256 i; i < numTokens;) {
            if (stakingTokens[i] == _stakingToken) {
                revert SafetyModule_StakingTokenAlreadyRegistered(address(_stakingToken));
            }
            unchecked {
                ++i;
            }
        }
        stakingTokens.push(_stakingToken);
        smRewardDistributor.initMarketStartTime(address(_stakingToken));
        emit StakingTokenAdded(address(_stakingToken));
    }

    /// @inheritdoc ISafetyModule
    /// @dev Only callable by governance
    function pause() external override onlyRole(GOVERNANCE) {
        _pause();
    }

    /// @inheritdoc ISafetyModule
    /// @dev Only callable by governance
    function unpause() external override onlyRole(GOVERNANCE) {
        _unpause();
    }

    /* ****************** */
    /*      Internal      */
    /* ****************** */

    function _returnFunds(IStakedToken _stakingToken, address _from, uint256 _amount) internal {
        _stakingToken.returnFunds(_from, _amount);
    }

    function _settleSlashing(IStakedToken _stakingToken) internal {
        _stakingToken.settleSlashing();
    }
}
