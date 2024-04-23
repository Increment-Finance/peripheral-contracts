// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.20;

// contracts
import {Test} from "forge/Test.sol";
import {UA} from "@increment/tokens/UA.sol";
import {Vault} from "@increment/Vault.sol";
import {ClearingHouse} from "@increment/ClearingHouse.sol";
import {ClearingHouseViewer} from "@increment/ClearingHouseViewer.sol";
import {Perpetual} from "@increment/Perpetual.sol";
import {USDCMock} from "@increment/utils/USDCMock.sol";
import {BatchCaller, Call} from "clave-contracts/contracts/batch/BatchCaller.sol";
import {MockValidator} from "clave-contracts/contracts/test/MockValidator.sol";
import {ClaveProxy} from "clave-contracts/contracts/ClaveProxy.sol";
import {ClaveImplementation} from "clave-contracts/contracts/ClaveImplementation.sol";
import {ClaveRegistry} from "clave-contracts/contracts/ClaveRegistry.sol";
import {AccountFactory} from "clave-contracts/contracts/AccountFactory.sol";

// utils
import "@increment/lib/LibMath.sol";

abstract contract Deployed is Test {
    using LibMath for int256;

    /* fork */
    uint256 public eraFork;

    /* fork addresses */
    address constant UA_ADDRESS = 0xfc840c55b791a1DbAF5C588116a8fC0b4859d227;
    address constant GOVERNANCE = 0x3082263EC78fa714a48F62869a77dABa0FfeF583;
    address constant VAULT = 0x703500cAF3c79aF68BB3dc85A6846d1C7999C672;
    address constant CLEARING_HOUSE = 0x9200536A28b0Bf5d02b7d8966cd441EDc173dE61;
    address constant CLEARING_HOUSE_VIEWER = 0xc8A34A3cfB835018B800c9A50ab0a71149Da13Fb;
    address constant PERPETUAL_ETHUSD = 0xeda91B6d87A257d209e947BD7f1bC25FC49272B6;
    address constant BATCH_CALLER = 0x4323cffC1Fda2da9928cB5A5A9dA45DC8Ee38a2f;
    address constant CLAVE_IMPLEMENTATION = 0xf5bEDd0304ee359844541262aC349a6016A50bc6;
    address constant CLAVE_REGISTRY = 0x4A70d13c117fAC84c07917755aCcAE236f4DF97f;
    address constant ACCOUNT_FACTORY = 0x2B196aaB35184aa539E3D8360258CAF8d8309Ebc;

    /* Increment contracts */
    UA public ua;
    USDCMock public usdcMock;
    Vault public vault;
    ClearingHouse public clearingHouse;
    ClearingHouseViewer public viewer;
    Perpetual public perpetual;

    /* Clave contracts */
    BatchCaller public batchCaller;
    MockValidator public validator;
    ClaveImplementation public claveImplementation;
    ClaveRegistry public claveRegistry;
    AccountFactory public accountFactory;

    function setUp() public virtual {
        /* initialize fork */
        eraFork = vm.createFork("https://mainnet.era.zksync.io");
        vm.selectFork(eraFork);

        /* get existing deployments */
        ua = UA(UA_ADDRESS);
        vault = Vault(VAULT);
        clearingHouse = ClearingHouse(CLEARING_HOUSE);
        viewer = ClearingHouseViewer(CLEARING_HOUSE_VIEWER);
        perpetual = Perpetual(PERPETUAL_ETHUSD);
        batchCaller = BatchCaller(BATCH_CALLER);
        validator = new MockValidator();
        claveImplementation = ClaveImplementation(payable(CLAVE_IMPLEMENTATION));
        claveRegistry = ClaveRegistry(CLAVE_REGISTRY);
        accountFactory = AccountFactory(ACCOUNT_FACTORY);

        /* change deployer address in factory */
        address owner = accountFactory.owner();
        vm.startPrank(owner);
        accountFactory.changeDeployer(address(this));
        vm.stopPrank();

        /* add mock USDC to UA reserves */
        usdcMock = new USDCMock("USDC Mock", "USDC", 6);
        vm.startPrank(GOVERNANCE);
        ua.addReserveToken(usdcMock, 1e25);
        vm.stopPrank();
    }
}
