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

// libraries
import {PRBMathUD60x18} from "prb-math/contracts/PRBMathUD60x18.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title SafetyModule
/// @author webthethird
/// @notice Handles reward accrual and distribution for staked tokens, and allows governance to auction a
/// percentage of user funds in the event of an insolvency in the vault
contract SafetyModule is ISafetyModule, IncreAccessControl, Pausable, ReentrancyGuard {
    using PRBMathUD60x18 for uint256;
    using SafeERC20 for IERC20;

    /// @notice Address of the auction module, which sells user funds in the event of an insolvency
    IAuctionModule public auctionModule;

    /// @notice Address of the SMRewardDistributor contract, which distributes rewards to stakers
    ISMRewardDistributor public smRewardDistributor;

    /// @notice Array of staked tokens that are registered with the SafetyModule
    IStakedToken[] public stakedTokens;

    /// @notice Mapping from auction ID to staked token that was slashed for the auction
    mapping(uint256 => IStakedToken) public stakedTokenByAuctionId;

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
        // Note: if the SafetyModule is ever re-deployed, the new contract should also set the array of staked tokens
        // in the constructor to avoid having to call `addStakedToken` for each staked token. Otherwise, unless the
        // SMRewardDistributor is also redeployed, `addStakedToken` will revert when trying to re-initialize a staked
        // token in the SMRD which was already initialized when added to the previous SafetyModule.
        auctionModule = IAuctionModule(_auctionModule);
        smRewardDistributor = ISMRewardDistributor(_smRewardDistributor);
        emit AuctionModuleUpdated(address(0), _auctionModule);
        emit RewardDistributorUpdated(address(0), _smRewardDistributor);
    }

    /* ****************** */
    /*      Markets       */
    /* ****************** */

    /// @inheritdoc ISafetyModule
    function getStakedTokens() external view returns (IStakedToken[] memory) {
        return stakedTokens;
    }

    /// @inheritdoc ISafetyModule
    function getNumStakedTokens() public view returns (uint256) {
        return stakedTokens.length;
    }

    /// @inheritdoc ISafetyModule
    function getStakedTokenIdx(address token) public view returns (uint256) {
        uint256 numTokens = stakedTokens.length;
        for (uint256 i; i < numTokens;) {
            if (address(stakedTokens[i]) == token) return i;
            unchecked {
                ++i; // saves 63 gas per iteration
            }
        }
        revert SafetyModule_InvalidStakedToken(token);
    }

    /* ****************** */
    /*   Auction Module   */
    /* ****************** */

    /// @inheritdoc ISafetyModule
    /// @dev Only callable by the auction module
    function auctionEnded(uint256 _auctionId, uint256 _remainingBalance) external onlyAuctionModule {
        IStakedToken stakedToken = stakedTokenByAuctionId[_auctionId];
        if (_remainingBalance != 0) {
            _returnFunds(stakedToken, address(auctionModule), _remainingBalance);
        }
        _settleSlashing(stakedToken);
        emit AuctionEnded(
            _auctionId, address(stakedToken), address(stakedToken.getUnderlyingToken()), _remainingBalance
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

        IStakedToken stakedToken = stakedTokens[getStakedTokenIdx(_stakedToken)];

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
        stakedTokenByAuctionId[auctionId] = stakedToken;
        emit TokensSlashedForAuction(_stakedToken, slashAmount, underlyingAmount, auctionId);
        return auctionId;
    }

    /// @inheritdoc ISafetyModule
    /// @dev Only callable by governance
    function terminateAuction(uint256 _auctionId) external onlyRole(GOVERNANCE) {
        auctionModule.terminateAuction(_auctionId);
        IERC20 auctionToken = auctionModule.getAuctionToken(_auctionId);
        IStakedToken stakedToken = stakedTokenByAuctionId[_auctionId];
        uint256 remainingBalance = auctionToken.balanceOf(address(auctionModule));
        // Remaining balance should always be non-zero, since the only way the auction module could run out
        // of auction tokens is if they are all sold, in which case the auction would have ended on its own
        // But just in case, check to avoid reverting
        if (remainingBalance != 0) {
            _returnFunds(stakedToken, address(auctionModule), remainingBalance);
        }
        _settleSlashing(stakedToken);
        emit AuctionTerminated(_auctionId, address(stakedToken), address(auctionToken), remainingBalance);
    }

    /// @inheritdoc ISafetyModule
    /// @dev Only callable by governance
    function returnFunds(address _stakedToken, address _from, uint256 _amount) external onlyRole(GOVERNANCE) {
        IStakedToken stakedToken = stakedTokens[getStakedTokenIdx(_stakedToken)];
        _returnFunds(stakedToken, _from, _amount);
    }

    /// @inheritdoc ISafetyModule
    /// @dev Only callable by governance
    function withdrawFundsRaisedFromAuction(uint256 _amount) external onlyRole(GOVERNANCE) {
        IERC20 paymentToken = auctionModule.paymentToken();
        paymentToken.safeTransfer(msg.sender, _amount);
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
        uint256 numTokens = stakedTokens.length;
        for (uint256 i; i < numTokens;) {
            stakedTokens[i].setRewardDistributor(_newRewardDistributor);
            unchecked {
                ++i; // saves 63 gas per iteration
            }
        }
    }

    /// @inheritdoc ISafetyModule
    /// @dev Only callable by governance, reverts if the staked token is already registered
    function addStakedToken(IStakedToken _stakedToken) external onlyRole(GOVERNANCE) {
        uint256 numTokens = stakedTokens.length;
        for (uint256 i; i < numTokens;) {
            if (stakedTokens[i] == _stakedToken) {
                revert SafetyModule_StakedTokenAlreadyRegistered(address(_stakedToken));
            }
            unchecked {
                ++i; // saves 63 gas per iteration
            }
        }
        stakedTokens.push(_stakedToken);
        // Note: if the SafetyModule is ever re-deployed, the new contract should set the array of staked tokens
        // in the constructor to avoid having to call this function for each staked token. Otherwise, unless the
        // SMRewardDistributor is also redeployed, the following line will revert when trying to re-initialize a
        // staked token that was already initialized when added to the previous SafetyModule.
        smRewardDistributor.initMarketStartTime(address(_stakedToken));
        emit StakedTokenAdded(address(_stakedToken));
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

    function _returnFunds(IStakedToken _stakedToken, address _from, uint256 _amount) internal {
        _stakedToken.returnFunds(_from, _amount);
    }

    function _settleSlashing(IStakedToken _stakedToken) internal {
        _stakedToken.settleSlashing();
    }
}
