// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.20;

// contracts
import {Vm} from "forge/Vm.sol";
import {Utils} from "../../lib/increment-protocol/test/helpers/Utils.sol";
import {Deployed} from "../helpers/Deployed.EraFork.sol";
import {ClaveProxy} from "clave-contracts/contracts/ClaveProxy.sol";
import {ClaveImplementation} from "clave-contracts/contracts/ClaveImplementation.sol";
import {Call} from "clave-contracts/contracts/batch/BatchCaller.sol";
import {IncrementLimitOrderModule} from "../../contracts/IncrementLimitOrderModule.sol";

// interfaces
import {IClaveAccount} from "clave-contracts/contracts/interfaces/IClave.sol";
import "increment-protocol/interfaces/IPerpetual.sol";
import "increment-protocol/interfaces/IClearingHouse.sol";

// libraries
import {
    TransactionHelper,
    Transaction,
    EIP_712_TX_TYPE
} from "@matterlabs/zksync-contracts/l2/system-contracts/libraries/TransactionHelper.sol";
import {
    NONCE_HOLDER_SYSTEM_CONTRACT,
    BOOTLOADER_FORMAL_ADDRESS
} from "@matterlabs/zksync-contracts/l2/system-contracts/Constants.sol";
import {MessageHashUtils} from "clave-contracts/contracts/helpers/EIP712.sol";
import {LibMath} from "increment-protocol/lib/LibMath.sol";
import {LibPerpetual} from "increment-protocol/lib/LibPerpetual.sol";
import {console2 as console} from "forge/console2.sol";

contract LimitOrderTest is Deployed, Utils {
    using LibMath for int256;
    using LibMath for uint256;

    Vm.Wallet public lpOne;
    Vm.Wallet public lpTwo;
    Vm.Wallet public traderOne;
    Vm.Wallet public traderTwo;
    Vm.Wallet public keeperOne;
    Vm.Wallet public keeperTwo;

    IncrementLimitOrderModule public limitOrderModule;

    mapping(address => IClaveAccount) public accounts;

    function setUp() public virtual override {
        lpOne = vm.createWallet("lpOne");
        lpTwo = vm.createWallet("lpTwo");
        traderOne = vm.createWallet("traderOne");
        traderTwo = vm.createWallet("traderTwo");
        keeperOne = vm.createWallet("keeperOne");
        keeperTwo = vm.createWallet("keeperTwo");

        deal(lpOne.addr, 100 ether);
        deal(lpTwo.addr, 100 ether);
        deal(traderOne.addr, 100 ether);
        deal(traderTwo.addr, 100 ether);
        deal(keeperOne.addr, 100 ether);
        deal(keeperTwo.addr, 100 ether);

        super.setUp();

        limitOrderModule = new IncrementLimitOrderModule(clearingHouse, viewer, claveRegistry, 0.01 ether);
    }

    function test_deployAccount() public {
        IClaveAccount account = _deployClaveAccount(lpOne);

        assertTrue(claveRegistry.isClave(address(account)));
        assertTrue(account.r1IsOwner(_getPubKey(lpOne)));
        assertFalse(account.isModule(address(limitOrderModule)));

        _addModule(lpOne);

        assertTrue(account.isModule(address(limitOrderModule)));
    }

    function _deployClaveAccount(Vm.Wallet memory wallet) internal returns (IClaveAccount clave) {
        if (accounts[wallet.addr] != IClaveAccount(address(0))) {
            return accounts[wallet.addr];
        }
        bytes32 salt = keccak256(abi.encodePacked(wallet.addr));
        Call memory call = Call({target: address(0), allowFailure: false, value: 0, callData: bytes("")});
        bytes[] memory modules = new bytes[](0);
        bytes memory pubKey = _getPubKey(wallet);
        bytes memory initializer =
            abi.encodeCall(ClaveImplementation.initialize, (pubKey, address(validator), modules, call));
        address accountAddress = accountFactory.deployAccount(salt, initializer);
        clave = IClaveAccount(accountAddress);
        accounts[wallet.addr] = clave;
    }

    function _addModule(Vm.Wallet memory wallet) internal {
        if (accounts[wallet.addr] == IClaveAccount(address(0))) {
            _deployClaveAccount(wallet);
        }
        IClaveAccount account = accounts[wallet.addr];
        bytes memory moduleData = abi.encodePacked(address(limitOrderModule));
        bytes memory addModuleCalldata = abi.encodeWithSelector(account.addModule.selector, moduleData);
        Transaction memory transaction =
            _getSignedTransaction(address(account), address(account), addModuleCalldata, wallet);
        _executeTransactionFromBootloader(account, transaction);
    }

    function _executeTransactionFromBootloader(IClaveAccount account, Transaction memory transaction) internal {
        vm.startPrank(BOOTLOADER_FORMAL_ADDRESS);
        account.executeTransaction(bytes32(0), bytes32(0), transaction);
        vm.stopPrank();
    }

    function _getPubKey(Vm.Wallet memory wallet) internal pure returns (bytes memory) {
        return abi.encode(wallet.publicKeyX, wallet.publicKeyY);
    }

    function _getSignedTransaction(address to, address from, bytes memory data, Vm.Wallet memory wallet)
        internal
        view
        returns (Transaction memory)
    {
        uint256[4] memory _reserved;
        Transaction memory transaction = Transaction({
            txType: EIP_712_TX_TYPE,
            from: uint256(uint160(from)),
            to: uint256(uint160(to)),
            gasLimit: 30_000_000,
            gasPerPubdataByteLimit: 800,
            maxFeePerGas: 1 ether,
            maxPriorityFeePerGas: 1 ether,
            paymaster: 0,
            nonce: NONCE_HOLDER_SYSTEM_CONTRACT.getMinNonce(from),
            value: 0,
            reserved: _reserved,
            data: data,
            signature: bytes(""),
            factoryDeps: new bytes32[](0),
            paymasterInput: bytes(""),
            reservedDynamic: bytes("")
        });
        bytes32 digest = MessageHashUtils.toTypedDataHash(
            TransactionHelper.EIP712_DOMAIN_TYPEHASH,
            keccak256(abi.encode(TransactionHelper.EIP712_TRANSACTION_TYPE_HASH, abi.encode(transaction)))
        );
        (bytes32 r, bytes32 s) = vm.signP256(wallet.privateKey, digest);
        transaction.signature = abi.encode(r, s);
        return transaction;
    }
}
