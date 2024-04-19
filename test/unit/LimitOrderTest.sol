// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.20;

// contracts
import {AccountFactory} from "clave-contracts/contracts/AccountFactory.sol";
import {ClaveImplementation} from "clave-contracts/contracts/ClaveImplementation.sol";
import {ClaveProxy} from "clave-contracts/contracts/ClaveProxy.sol";
import {ClaveRegistry} from "clave-contracts/contracts/ClaveRegistry.sol";
import {BatchCaller} from "clave-contracts/contracts/batch/BatchCaller.sol";
import {Deployment} from "../../lib/increment-protocol/test/helpers/Deployment.MainnetFork.sol";
import {Utils} from "../../lib/increment-protocol/test/helpers/Utils.sol";
import {IncrementLimitOrderModule} from "../../contracts/IncrementLimitOrderModule.sol";

// libraries
import {LibMath} from "increment-protocol/lib/LibMath.sol";
import {LibPerpetual} from "increment-protocol/lib/LibPerpetual.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {console2 as console} from "forge/console2.sol";

contract LimitOrderTest is Deployment, Utils {
    using LibMath for int256;
    using LibMath for uint256;

    address public liquidityProviderOne = address(123);
    address public liquidityProviderTwo = address(456);
    address public traderOne = address(789);
    address public traderTwo = address(987);
    address public keeperOne = address(654);
    address public keeperTwo = address(321);

    AccountFactory public accountFactory;
    ClaveImplementation public claveImplementation;
    ClaveRegistry public claveRegistry;
    IncrementLimitOrderModule public limitOrderModule;

    function setUp() public virtual override {
        deal(liquidityProviderOne, 100 ether);
        deal(liquidityProviderTwo, 100 ether);
        deal(traderOne, 100 ether);
        deal(traderTwo, 100 ether);
        deal(keeperOne, 100 ether);
        deal(keeperTwo, 100 ether);

        // Deploy protocol
        // increment-protocol/test/helpers/Deployment.MainnetFork.sol:setUp()
        super.setUp();

        // Deploy second perpetual contract
        _deployEthMarket();
    }

    function _deployClaveContracts() internal {
        claveRegistry = new ClaveRegistry();
        BatchCaller batchCaller = new BatchCaller();
        claveImplementation = new ClaveImplementation(address(batchCaller));
        bytes32 proxyBytecodeHash = keccak256(type(ClaveProxy).bytecode);
    }
}
