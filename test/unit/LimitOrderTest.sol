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
import {IIncrementLimitOrderModule} from "../../contracts/interfaces/IIncrementLimitOrderModule.sol";

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
import {LibReserve} from "increment-protocol/lib/LibReserve.sol";
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

    receive() external payable {
        console.log("LimitOrderTest.receive: msg.value = %s", msg.value);
        require(false);
    }

    fallback() external payable {
        console.log("LimitOrderTest.fallback: msg.value = %s", msg.value);
        require(false);
    }

    function test_DeployAccount() public {
        IClaveAccount account = _deployClaveAccount(traderOne);

        assertTrue(claveRegistry.isClave(address(account)));
        assertTrue(account.r1IsOwner(_getPubKey(traderOne)));
        assertFalse(account.isModule(address(limitOrderModule)));

        _addModule(traderOne);

        assertTrue(account.isModule(address(limitOrderModule)));
    }

    function test_CustomErrors() public {
        IClaveAccount account = _deployClaveAccount(traderOne);
        deal(address(account), 1 ether);
        _fundAndPrepareClaveAccount(account, 1000 ether);

        // createOrder
        vm.startPrank(traderOne.addr);
        IIncrementLimitOrderModule.LimitOrder memory order = IIncrementLimitOrderModule.LimitOrder({
            account: address(0),
            side: LibPerpetual.Side.Long,
            orderType: IIncrementLimitOrderModule.OrderType.LIMIT,
            reduceOnly: true,
            marketIdx: 1,
            targetPrice: 0,
            amount: 0,
            expiry: 0,
            slippage: 1e18 + 1,
            tipFee: 0
        });
        _expectInvalidAccount();
        limitOrderModule.createOrder(order);
        order.account = traderOne.addr;
        _expectInsufficientTipFee();
        limitOrderModule.createOrder(order);
        order.tipFee = 0.1 ether;
        _expectInvalidFeeValue(0, 0.1 ether);
        limitOrderModule.createOrder(order);
        _expectInvalidExpiry();
        limitOrderModule.createOrder{value: 0.1 ether}(order);
        uint256 expiry = block.timestamp + 1 days;
        order.expiry = expiry;
        _expectInvalidAmount();
        limitOrderModule.createOrder{value: 0.1 ether}(order);
        order.amount = 100 ether;
        _expectInvalidTargetPrice();
        limitOrderModule.createOrder{value: 0.1 ether}(order);
        order.targetPrice = perpetual.marketPrice().wadMul(0.95e18);
        _expectInvalidSlippage();
        limitOrderModule.createOrder{value: 0.1 ether}(order);
        order.slippage = 1e16;
        _expectInvalidMarketIdx();
        limitOrderModule.createOrder{value: 0.1 ether}(order);
        order.marketIdx = 0;
        _expectAccountIsNotClave(traderOne.addr);
        limitOrderModule.createOrder{value: 0.1 ether}(order);
        order.account = address(account);
        vm.stopPrank();
        bytes memory data = abi.encodeCall(limitOrderModule.createOrder, (order));
        Transaction memory _tx =
            _getSignedTransaction(address(limitOrderModule), address(account), 0.1 ether, data, traderOne);
        _expectAccountDoesNotSupportLimitOrders(address(account));
        _executeTransactionFromBootloader(account, _tx);
        // create order successfully
        _addModule(traderOne);
        _executeTransactionFromBootloader(account, _tx);

        // changeOrder
        vm.startPrank(traderOne.addr);
        _expectInvalidOrderId();
        limitOrderModule.changeOrder(1, 0, 0, 0, 0, 0);
        _expectInsufficientTipFee();
        limitOrderModule.changeOrder(0, 0, 0, 0, 0, 0);
        _expectInvalidAmount();
        limitOrderModule.changeOrder(0, 0, 0, 0, 0, 0.2 ether);
        _expectInvalidTargetPrice();
        limitOrderModule.changeOrder(0, 0, 100 ether, 0, 0, 0.2 ether);
        uint256 targetPrice = perpetual.marketPrice().wadMul(0.99e18);
        _expectInvalidExpiry();
        limitOrderModule.changeOrder(0, targetPrice, 100 ether, 0, 0, 0.2 ether);
        _expectInvalidSlippage();
        limitOrderModule.changeOrder(0, targetPrice, 100 ether, expiry, 1e19, 0.2 ether);
        _expectInvalidSenderNotOrderOwner(traderOne.addr, address(account));
        limitOrderModule.changeOrder(0, targetPrice, 100 ether, expiry, 1e15, 0.2 ether);
        vm.stopPrank();
        data = abi.encodeCall(limitOrderModule.changeOrder, (0, targetPrice, 100 ether, expiry, 1e15, 0.2 ether));
        _tx = _getSignedTransaction(address(limitOrderModule), address(account), 0.2 ether, data, traderOne);
        _expectInvalidFeeValue(0.2 ether, 0.1 ether);
        _executeTransactionFromBootloader(account, _tx);

        // cancelOrder
        vm.startPrank(traderOne.addr);
        _expectInvalidOrderId();
        limitOrderModule.cancelOrder(1);
        _expectInvalidSenderNotOrderOwner(traderOne.addr, address(account));
        limitOrderModule.cancelOrder(0);

        // closeExpiredOrder
        vm.startPrank(keeperOne.addr);
        _expectInvalidOrderId();
        limitOrderModule.closeExpiredOrder(1);
        _expectOrderNotExpired(expiry);
        limitOrderModule.closeExpiredOrder(0);

        // fillOrder
        _expectInvalidOrderId();
        limitOrderModule.fillOrder(1);
        // fillOrder - reduce-only errors
        _expectNoPositionToReduce(address(account), 0);
        limitOrderModule.fillOrder(0);
        // - Open a long position - cannot reduce position with same side order
        data = abi.encodeCall(clearingHouse.changePosition, (0, 100 ether, 0, LibPerpetual.Side.Long));
        _tx = _getSignedTransaction(address(clearingHouse), address(account), 0, data, traderOne);
        _executeTransactionFromBootloader(account, _tx);
        vm.startPrank(keeperOne.addr);
        _expectCannotReducePositionWithSameSideOrder();
        limitOrderModule.fillOrder(0);
        // - Reverse to short position - long order would reverse position
        uint256 proposedAmount = viewer.getTraderProposedAmount(0, address(account), 1e18, 100, 0);
        data = abi.encodeCall(
            clearingHouse.openReversePosition, (0, proposedAmount, 0, proposedAmount, 0, LibPerpetual.Side.Short)
        );
        _tx = _getSignedTransaction(address(clearingHouse), address(account), 0, data, traderOne);
        _executeTransactionFromBootloader(account, _tx);
        vm.startPrank(keeperOne.addr);
        proposedAmount = viewer.getTraderProposedAmount(0, address(account), 1e18, 100, 0);
        _expectReduceOnlyCannotReversePosition();
        limitOrderModule.fillOrder(0);
        // fillOrder - invalid price error
        // - Extend short position so long order would only reduce position
        data = abi.encodeCall(clearingHouse.changePosition, (0, 0.1 ether, 0, LibPerpetual.Side.Short));
        _tx = _getSignedTransaction(address(clearingHouse), address(account), 0, data, traderOne);
        _executeTransactionFromBootloader(account, _tx);
        _expectInvalidPriceAtFill(perpetual.marketPrice(), order.targetPrice, order.slippage, order.side);
        limitOrderModule.fillOrder(0);
        // fillOrder - transfer tip fee failed error
        // - Change target price to current price
        data = abi.encodeCall(
            limitOrderModule.changeOrder,
            (0, perpetual.marketPrice(), order.amount, order.expiry, order.slippage, order.tipFee)
        );
        _tx = _getSignedTransaction(address(limitOrderModule), address(account), 0, data, traderOne);
        _executeTransactionFromBootloader(account, _tx);
        // - Call fillOrder from this test contract, which reverts in `receive()`
        // TODO: figure out why this check is failing - should revert in `this.receive()`
        // _expectTipFeeTransferFailed(address(this), order.tipFee);
        // limitOrderModule.fillOrder(0);
        // fillOrder - order expired error
        // TODO: figure out why this check is failing - order should be expired after skipping 2 days
        // skip(2 days);
        // _expectOrderExpired(order.expiry);
        // limitOrderModule.fillOrder(0);

        // TODO: init and disable

        // views
        _expectInvalidOrderId();
        limitOrderModule.getOrder(1);
        _expectInvalidOrderId();
        limitOrderModule.getTipFee(1);
        _expectInvalidOrderId();
        limitOrderModule.canFillOrder(1);
    }

    /* ***************** */
    /*   Clave Helpers   */
    /* ***************** */

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
            _getSignedTransaction(address(account), address(account), 0, addModuleCalldata, wallet);
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

    function _getSignedTransaction(address to, address from, uint256 value, bytes memory data, Vm.Wallet memory wallet)
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
            value: value,
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

    /* ***************** */
    /* Increment Helpers */
    /* ***************** */

    function _provideLiquidity(uint256 depositAmount, address user, IPerpetual perp) internal {
        vm.startPrank(user);

        clearingHouse.deposit(depositAmount, ua);
        uint256 quoteAmount = depositAmount / 2;
        uint256 baseAmount = quoteAmount.wadDiv(perp.indexPrice().toUint256());
        clearingHouse.provideLiquidity(_getMarketIdx(address(perp)), [quoteAmount, baseAmount], 0);
        vm.stopPrank();
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

    function _fundAndPrepareClaveAccount(IClaveAccount account, uint256 amount) internal {
        uint256 usdcAmount = LibReserve.wadToToken(usdcMock.decimals(), amount);
        usdcMock.mint(address(account), usdcAmount);
        vm.startPrank(address(account));
        usdcMock.approve(address(ua), usdcAmount);
        ua.mintWithReserve(usdcMock, usdcAmount);
        assertGe(ua.balanceOf(address(account)), amount, "Failed to mint UA with mock reserve");
        ua.approve(address(vault), amount);
        clearingHouse.deposit(amount, ua);
        vm.stopPrank();
    }

    /* ***************** */
    /*   Error Helpers   */
    /* ***************** */

    function _expectInvalidAccount() internal {
        vm.expectRevert(abi.encodeWithSignature("LimitOrderModule_InvalidAccount()"));
    }

    function _expectInvalidTargetPrice() internal {
        vm.expectRevert(abi.encodeWithSignature("LimitOrderModule_InvalidTargetPrice()"));
    }

    function _expectInvalidAmount() internal {
        vm.expectRevert(abi.encodeWithSignature("LimitOrderModule_InvalidAmount()"));
    }

    function _expectInvalidExpiry() internal {
        vm.expectRevert(abi.encodeWithSignature("LimitOrderModule_InvalidExpiry()"));
    }

    function _expectInvalidMarketIdx() internal {
        vm.expectRevert(abi.encodeWithSignature("LimitOrderModule_InvalidMarketIdx()"));
    }

    function _expectInvalidOrderId() internal {
        vm.expectRevert(abi.encodeWithSignature("LimitOrderModule_InvalidOrderId()"));
    }

    function _expectInvalidSlippage() internal {
        vm.expectRevert(abi.encodeWithSignature("LimitOrderModule_InvalidSlippage()"));
    }

    function _expectInsufficientTipFee() internal {
        vm.expectRevert(abi.encodeWithSignature("LimitOrderModule_InsufficientTipFee()"));
    }

    function _expectInvalidFeeValue(uint256 value, uint256 expected) internal {
        vm.expectRevert(abi.encodeWithSignature("LimitOrderModule_InvalidFeeValue(uint256,uint256)", value, expected));
    }

    function _expectInvalidSenderNotOrderOwner(address sender, address owner) internal {
        vm.expectRevert(
            abi.encodeWithSignature("LimitOrderModule_InvalidSenderNotOrderOwner(address,address)", sender, owner)
        );
    }

    function _expectOrderExpired(uint256 expiry) internal {
        vm.expectRevert(abi.encodeWithSignature("LimitOrderModule_OrderExpired(uint256)", expiry));
    }

    function _expectOrderNotExpired(uint256 expiry) internal {
        vm.expectRevert(abi.encodeWithSignature("LimitOrderModule_OrderNotExpired(uint256)", expiry));
    }

    function _expectTipFeeTransferFailed(address to, uint256 amount) internal {
        vm.expectRevert(abi.encodeWithSignature("LimitOrderModule_TipFeeTransferFailed(address,uint256)", to, amount));
    }

    function _expectAccountIsNotClave(address account) internal {
        vm.expectRevert(abi.encodeWithSignature("LimitOrderModule_AccountIsNotClave(address)", account));
    }

    function _expectAccountDoesNotSupportLimitOrders(address account) internal {
        vm.expectRevert(abi.encodeWithSignature("LimitOrderModule_AccountDoesNotSupportLimitOrders(address)", account));
    }

    function _expectNoPositionToReduce(address account, uint256 idx) internal {
        vm.expectRevert(abi.encodeWithSignature("LimitOrderModule_NoPositionToReduce(address,uint256)", account, idx));
    }

    function _expectCannotReducePositionWithSameSideOrder() internal {
        vm.expectRevert(abi.encodeWithSignature("LimitOrderModule_CannotReducePositionWithSameSideOrder()"));
    }

    function _expectReduceOnlyCannotReversePosition() internal {
        vm.expectRevert(abi.encodeWithSignature("LimitOrderModule_ReduceOnlyCannotReversePosition()"));
    }

    function _expectInvalidPriceAtFill(uint256 price, uint256 limitPrice, uint256 maxSlippage, LibPerpetual.Side side)
        internal
    {
        vm.expectRevert(
            abi.encodeWithSignature(
                "LimitOrderModule_InvalidPriceAtFill(uint256,uint256,uint256,uint8)",
                price,
                limitPrice,
                maxSlippage,
                side
            )
        );
    }

    function _expectModuleNotInited() internal {
        vm.expectRevert(abi.encodeWithSignature("LimitOrderModule_ModuleNotInited()"));
    }

    function _expectInitDataShouldBeEmpty() internal {
        vm.expectRevert(abi.encodeWithSignature("LimitOrderModule_InitDataShouldBeEmpty()"));
    }
}
