// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.10;

import {IERC20} from "../lib/increment-protocol/lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IAdminControlledEcosystemReserve} from "./interfaces/IAdminControlledEcosystemReserve.sol";
import {SafeERC20} from "../lib/increment-protocol/lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from
    "../lib/increment-protocol/lib/openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";
import {Address} from "../lib/increment-protocol/lib/openzeppelin-contracts/contracts/utils/Address.sol";

/**
 * @title VersionedInitializable
 *
 * @dev Helper contract to support initializer functions. To use it, replace
 * the constructor with a function that has the `initializer` modifier.
 * WARNING: Unlike constructors, initializer functions must be manually
 * invoked. This applies both to deploying an Initializable contract, as well
 * as extending an Initializable contract via inheritance.
 * WARNING: When used with inheritance, manual care must be taken to not invoke
 * a parent initializer twice, or ensure that all initializers are idempotent,
 * because this is not dealt with automatically as with constructors.
 *
 * @author Aave, inspired by the OpenZeppelin Initializable contract
 */
abstract contract VersionedInitializable {
    /**
     * @dev Indicates that the contract has been initialized.
     */
    uint256 internal lastInitializedRevision = 0;

    /**
     * @dev Modifier to use in the initializer function of a contract.
     */
    modifier initializer() {
        uint256 revision = getRevision();
        require(revision > lastInitializedRevision, "Contract instance has already been initialized");

        lastInitializedRevision = revision;

        _;
    }

    /// @dev returns the revision number of the contract.
    /// Needs to be defined in the inherited class as a constant.
    function getRevision() internal pure virtual returns (uint256);

    // Reserved storage space to allow for layout changes in the future.
    uint256[50] private ______gap;
}

/**
 * @title AdminControlledEcosystemReserve
 * @notice Stores ERC20 tokens, and allows to dispose of them via approval or transfer dynamics
 * Adapted to be an implementation of a transparent proxy
 * @dev Done abstract to add an `initialize()` function on the child, with `initializer` modifier
 * @author BGD Labs
 *
 */
abstract contract AdminControlledEcosystemReserve is VersionedInitializable, IAdminControlledEcosystemReserve {
    using SafeERC20 for IERC20;
    using Address for address payable;

    address internal _fundsAdmin;

    uint256 public constant REVISION = 1;

    /// @inheritdoc IAdminControlledEcosystemReserve
    address public constant ETH_MOCK_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    modifier onlyFundsAdmin() {
        require(msg.sender == _fundsAdmin, "ONLY_BY_FUNDS_ADMIN");
        _;
    }

    function getRevision() internal pure override returns (uint256) {
        return REVISION;
    }

    /// @inheritdoc IAdminControlledEcosystemReserve
    function getFundsAdmin() external view returns (address) {
        return _fundsAdmin;
    }

    /// @inheritdoc IAdminControlledEcosystemReserve
    function approve(IERC20 token, address recipient, uint256 amount) external onlyFundsAdmin {
        token.safeApprove(recipient, amount);
    }

    /// @inheritdoc IAdminControlledEcosystemReserve
    function transfer(IERC20 token, address recipient, uint256 amount) external onlyFundsAdmin {
        require(recipient != address(0), "INVALID_0X_RECIPIENT");

        if (address(token) == ETH_MOCK_ADDRESS) {
            payable(recipient).sendValue(amount);
        } else {
            token.safeTransfer(recipient, amount);
        }
    }

    /// @dev needed in order to receive ETH from the Aave v1 ecosystem reserve
    receive() external payable {}

    function _setFundsAdmin(address admin) internal {
        _fundsAdmin = admin;
        emit NewFundsAdmin(admin);
    }
}
