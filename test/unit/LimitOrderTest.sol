// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.20;

// contracts
import {Vm} from "forge/Vm.sol";
import {Deployed} from "../helpers/Deployed.EraFork.sol";
import {ClaveProxy} from "clave-contracts/contracts/ClaveProxy.sol";
import {ClaveImplementation} from "clave-contracts/contracts/ClaveImplementation.sol";
import {Call} from "clave-contracts/contracts/batch/BatchCaller.sol";
import {IncrementLimitOrderModule} from "../../contracts/IncrementLimitOrderModule.sol";
import {CallSimulator} from "../helpers/CallSimulator.sol";

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
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {MessageHashUtils} from "clave-contracts/contracts/helpers/EIP712.sol";
import {LibMath} from "increment-protocol/lib/LibMath.sol";
import {LibPerpetual} from "increment-protocol/lib/LibPerpetual.sol";
import {LibReserve} from "increment-protocol/lib/LibReserve.sol";
import {console2 as console} from "forge/console2.sol";

contract LimitOrderTest is Deployed {
    using LibMath for int256;
    using LibMath for uint256;
    using Strings for uint256;

    string public constant LOG_FILE = "fuzz-logs.txt";

    Vm.Wallet public lpOne;
    Vm.Wallet public lpTwo;
    Vm.Wallet public traderOne;
    Vm.Wallet public traderTwo;
    Vm.Wallet public keeperOne;
    Vm.Wallet public keeperTwo;

    IncrementLimitOrderModule public limitOrderModule;
    CallSimulator public simulator;

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

        super.setUp();

        limitOrderModule = new IncrementLimitOrderModule(clearingHouse, viewer, claveRegistry, 0.01 ether);
        simulator = new CallSimulator();
        simulator.transferOwnership(address(limitOrderModule));
    }

    receive() external payable {
        console.log("LimitOrderTest.receive: msg.value = %s", msg.value);
        require(false, "LimitOrderTest.receive: receive not allowed");
    }

    fallback() external payable {
        console.log("LimitOrderTest.fallback: msg.value = %s", msg.value);
        require(false, "LimitOrderTest.fallback: fallback not allowed");
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
        order.amount = 50 ether;
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
        limitOrderModule.changeOrder(0, 0, 50 ether, 0, 0, 0.2 ether);
        uint256 targetPrice = perpetual.marketPrice().wadMul(0.99e18);
        _expectInvalidExpiry();
        limitOrderModule.changeOrder(0, targetPrice, 50 ether, 0, 0, 0.2 ether);
        _expectInvalidSlippage();
        limitOrderModule.changeOrder(0, targetPrice, 50 ether, expiry, 1e19, 0.2 ether);
        _expectInvalidSenderNotOrderOwner(traderOne.addr, address(account));
        limitOrderModule.changeOrder(0, targetPrice, 50 ether, expiry, 1e15, 0.2 ether);
        vm.stopPrank();
        data = abi.encodeCall(limitOrderModule.changeOrder, (0, targetPrice, 50 ether, expiry, 1e15, 0.2 ether));
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
        data = abi.encodeCall(clearingHouse.changePosition, (0, 50 ether, 0, LibPerpetual.Side.Long));
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
        data = abi.encodeCall(clearingHouse.changePosition, (0, 0.01 ether, 0, LibPerpetual.Side.Short));
        _tx = _getSignedTransaction(address(clearingHouse), address(account), 0, data, traderOne);
        _executeTransactionFromBootloader(account, _tx);
        _expectInvalidPriceAtFill(perpetual.marketPrice(), order.targetPrice, order.slippage, order.side);
        limitOrderModule.fillOrder(0);
        // fillOrder - order execution reverted error
        // - Change target price to current price, with high amount to trigger UnderOpenNotionalAmountRequired
        data = abi.encodeCall(
            limitOrderModule.changeOrder,
            (0, perpetual.marketPrice(), 50 ether, order.expiry, order.slippage, order.tipFee)
        );
        _tx = _getSignedTransaction(address(limitOrderModule), address(account), 0, data, traderOne);
        _executeTransactionFromBootloader(account, _tx);
        // - Call `fillOrder` from keeper
        vm.startPrank(keeperOne.addr);
        _expectOrderExecutionReverted(abi.encodeWithSignature("ClearingHouse_UnderOpenNotionalAmountRequired()"));
        limitOrderModule.fillOrder(0);
        // fillOrder - transfer tip fee failed error
        // - Change to lower order amount so it can be executed
        data = abi.encodeCall(
            limitOrderModule.changeOrder,
            (0, perpetual.marketPrice(), 5 ether, order.expiry, order.slippage, order.tipFee)
        );
        _tx = _getSignedTransaction(address(limitOrderModule), address(account), 0, data, traderOne);
        _executeTransactionFromBootloader(account, _tx);
        // - Call `fillOrder` from this test contract, which reverts in `receive()`
        // TODO: figure out why this check is failing - should revert in `this.receive()`
        // _expectTipFeeTransferFailed(address(this), order.tipFee);
        // limitOrderModule.fillOrder(0);
        // fillOrder - order expired error
        // TODO: figure out why this check is failing - order should be expired after skipping 2 days
        // skip(2 days);
        // _expectOrderExpired(order.expiry);
        // limitOrderModule.fillOrder(0);

        // init and disable
        // init - already inited
        data = abi.encodeCall(limitOrderModule.init, (bytes("")));
        _tx = _getSignedTransaction(address(limitOrderModule), address(account), 0, data, traderOne);
        _expectAlreadyInited();
        _executeTransactionFromBootloader(account, _tx);
        // init - module not added correctly
        IClaveAccount accountTwo = _deployClaveAccount(traderTwo);
        _tx = _getSignedTransaction(address(limitOrderModule), address(accountTwo), 0, data, traderTwo);
        _expectModuleNotAddedCorrectly();
        _executeTransactionFromBootloader(accountTwo, _tx);
        // init - data should be empty
        data = abi.encodeCall(accountTwo.addModule, (abi.encodePacked(address(limitOrderModule), traderTwo.addr)));
        _tx = _getSignedTransaction(address(accountTwo), address(accountTwo), 0, data, traderTwo);
        _expectInitDataShouldBeEmpty();
        _executeTransactionFromBootloader(accountTwo, _tx);
        // disable - module not inited
        data = abi.encodeCall(limitOrderModule.disable, ());
        _tx = _getSignedTransaction(address(limitOrderModule), address(accountTwo), 0, data, traderTwo);
        _expectModuleNotInited();
        _executeTransactionFromBootloader(accountTwo, _tx);
        // disable - module not removed correctly
        _tx = _getSignedTransaction(address(limitOrderModule), address(account), 0, data, traderOne);
        _expectModuleNotRemovedCorrectly();
        _executeTransactionFromBootloader(account, _tx);

        // views
        _expectInvalidOrderId();
        limitOrderModule.getOrder(1);
        _expectInvalidOrderId();
        limitOrderModule.getTipFee(1);
    }

    function test_ExecuteOrdersImmediately() public {
        IClaveAccount account = _deployClaveAccount(traderOne);
        address accountAddress = address(account);
        _addModule(traderOne);
        deal(accountAddress, 1 ether);
        _fundAndPrepareClaveAccount(account, 1000 ether);

        // Long limit order at 1% over current price
        uint256 currentPrice = perpetual.marketPrice();
        IIncrementLimitOrderModule.LimitOrder memory order = IIncrementLimitOrderModule.LimitOrder({
            account: accountAddress,
            side: LibPerpetual.Side.Long,
            orderType: IIncrementLimitOrderModule.OrderType.LIMIT,
            reduceOnly: false,
            marketIdx: 0,
            targetPrice: currentPrice.wadMul(1.01e18),
            amount: 100 ether,
            expiry: block.timestamp + 1 days,
            slippage: 1e16,
            tipFee: 0.1 ether
        });
        bytes memory data = abi.encodeCall(limitOrderModule.createOrder, (order));
        Transaction memory _tx =
            _getSignedTransaction(address(limitOrderModule), accountAddress, 0.1 ether, data, traderOne);
        _executeTransactionFromBootloader(account, _tx);
        // traderOne should have a long position now
        assertTrue(perpetual.isTraderPositionOpen(accountAddress));
        LibPerpetual.TraderPosition memory position = perpetual.getTraderPosition(accountAddress);
        assertGt(position.positionSize, 0);
        // Since the order was executed immediately, nextOrderId should not change and tipFee should be returned
        assertEq(limitOrderModule.nextOrderId(), 0);
        assertEq(accountAddress.balance, 1 ether);

        // Short stop order at 1% under current price
        currentPrice = perpetual.indexPrice().toUint256();
        order.side = LibPerpetual.Side.Short;
        order.targetPrice = currentPrice.wadMul(0.99e18);
        order.orderType = IIncrementLimitOrderModule.OrderType.STOP;
        order.amount = viewer.getTraderProposedAmount(0, accountAddress, 0.5e18, 100, 0); // reduce long by 50%
        data = abi.encodeCall(limitOrderModule.createOrder, (order));
        _tx = _getSignedTransaction(address(limitOrderModule), accountAddress, 0.1 ether, data, traderOne);
        _executeTransactionFromBootloader(account, _tx);
        // traderOne should still have a long position open
        assertTrue(perpetual.isTraderPositionOpen(accountAddress));
        position = perpetual.getTraderPosition(accountAddress);
        assertGt(position.positionSize, 0);
        // Since the order was executed immediately, nextOrderId should not change and tipFee should be returned
        assertEq(limitOrderModule.nextOrderId(), 0);
        assertEq(accountAddress.balance, 1 ether);
    }

    function testFuzz_FillOrderSucceedsOnlyIfCanFillOrder(
        bool long,
        bool limit,
        bool reduceOnly,
        bool deltaDirection,
        bool initialPosition,
        uint256 initialAmount,
        uint256 orderAmount,
        uint256 targetDelta,
        uint256 slippage
    ) public {
        // Bounds
        LibPerpetual.Side orderSide = long ? LibPerpetual.Side.Long : LibPerpetual.Side.Short;
        IIncrementLimitOrderModule.OrderType orderType =
            limit ? IIncrementLimitOrderModule.OrderType.LIMIT : IIncrementLimitOrderModule.OrderType.STOP;
        initialAmount = bound(initialAmount, 35 ether, 350 ether);
        orderAmount = bound(orderAmount, 1 ether, 500 ether);
        targetDelta = bound(targetDelta, 1e14, 1e17);
        slippage = bound(slippage, 1e14, 1e17);

        // Prepare account
        IClaveAccount account = _deployClaveAccount(traderOne);
        _addModule(traderOne);
        deal(address(account), 1 ether);
        _fundAndPrepareClaveAccount(account, 10000 ether);

        // Open initial position
        bytes memory data;
        Transaction memory _tx;
        LibPerpetual.Side initialSide = orderSide;
        if (initialPosition) {
            if (reduceOnly || !limit || initialAmount % 2 == 0) {
                initialSide = long ? LibPerpetual.Side.Short : LibPerpetual.Side.Long;
            }
            data = abi.encodeCall(clearingHouse.changePosition, (0, initialAmount, 0, initialSide));
            _tx = _getSignedTransaction(address(clearingHouse), address(account), 0, data, traderOne);
            vm.startPrank(BOOTLOADER_FORMAL_ADDRESS);
            // Try opening initial position, but continue test if it fails
            try account.executeTransaction(bytes32(0), bytes32(0), _tx) {
                console.log("opened initial position");
                vm.stopPrank();
            } catch {
                console.log("failed to open initial position");
                vm.stopPrank();
            }
        }

        // Create order with target price that cannot be filled immediately
        uint256 currentPrice = orderType == IIncrementLimitOrderModule.OrderType.LIMIT
            ? perpetual.marketPrice()
            : perpetual.indexPrice().toUint256();
        console.log("currentPrice: %s", currentPrice);
        uint256 targetPrice = orderSide == LibPerpetual.Side.Long ? 1 : type(uint256).max;
        IIncrementLimitOrderModule.LimitOrder memory order = IIncrementLimitOrderModule.LimitOrder({
            account: address(account),
            side: orderSide,
            orderType: orderType,
            reduceOnly: reduceOnly,
            marketIdx: 0,
            targetPrice: targetPrice,
            amount: orderAmount,
            expiry: block.timestamp + 1 days,
            slippage: slippage,
            tipFee: 0.1 ether
        });
        data = abi.encodeCall(limitOrderModule.createOrder, (order));
        _tx = _getSignedTransaction(address(limitOrderModule), address(account), 0.1 ether, data, traderOne);
        console.log("creating order...");
        _executeTransactionFromBootloader(account, _tx);

        // Change target price to something more reasonable
        targetPrice = deltaDirection ? currentPrice.wadMul(1e18 + targetDelta) : currentPrice.wadMul(1e18 - targetDelta);
        console.log("targetPrice: %s", targetPrice);
        data = abi.encodeCall(
            limitOrderModule.changeOrder, (0, targetPrice, order.amount, order.expiry, order.slippage, order.tipFee)
        );
        _tx = _getSignedTransaction(address(limitOrderModule), address(account), 0, data, traderOne);
        console.log("changing order...");
        _executeTransactionFromBootloader(account, _tx);

        // Simulate and revert to check if order can be filled
        console.log("checking if order can be filled...");
        vm.startPrank(keeperOne.addr);
        try simulator.simulate(address(limitOrderModule), abi.encodeCall(limitOrderModule.fillOrder, (0))) returns (
            bytes memory response
        ) {
            console.log("simulate response.length = %s", response.length);
            console.logBytes(response);
            console.log("order can be filled");
            // Expect fillOrder to succeed
            try limitOrderModule.fillOrder(0) {
                console.log("fillOrder succeeded as expected");
            } catch (bytes memory returnData) {
                console.log("fillOrder failed...");
                console.logBytes(returnData);
                assertTrue(false);
            }
            vm.stopPrank();
            // Expect tip fee to have been sent to keeperOne
            assertEq(keeperOne.addr.balance, order.tipFee);
            // Expect limit order data to have been deleted
            _expectInvalidOrderId();
            limitOrderModule.getOrder(0);
        } catch (bytes memory response) {
            console.log("simulate response.length = %s", response.length);
            console.logBytes(response);
            if (response.length < 4) {
                response = new bytes(32);
            } else if (response.length == 4) {
                response = bytes.concat(response, new bytes(28));
            } else if (response.length >= 36 && response.length % 32 == 4) {
                // write 0s after the error selector
                for (uint256 i = 4; i < 36; i++) {
                    response[i] = 0;
                }
            }
            (bytes4 errorSelector) = abi.decode(response, (bytes4));
            console.log("simulate success: false");
            console.log("simulate errorSelector: %s", Strings.toHexString(uint256(uint32(errorSelector)), 4));
            // Expect fillOrder to fail
            console.log("order cannot be filled");
            try limitOrderModule.fillOrder(0) {
                vm.stopPrank();
                assertTrue(false);
            } catch (bytes memory returnData) {
                console.log("fillOrder returnData.length = %s", returnData.length);
                console.logBytes(returnData);
                bytes4 actualSelector;
                if (returnData.length == 4) {
                    returnData = bytes.concat(returnData, new bytes(28));
                    (actualSelector) = abi.decode(returnData, (bytes4));
                } else if (returnData.length >= 36 && returnData.length % 32 == 4) {
                    // write 0s after the error selector
                    for (uint256 i = 4; i < 36; i++) {
                        returnData[i] = 0;
                    }
                    (actualSelector) = abi.decode(returnData, (bytes4));
                }
                assertEq(errorSelector, actualSelector);
                vm.stopPrank();
            }
            // Expect that limit order data has not been deleted
            assertEq(limitOrderModule.getOrder(0).account, address(account));
            // Expect that tip fee has not been sent to the keeper
            assertEq(keeperOne.addr.balance, 0);
        }
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

    function _expectOrderExecutionReverted(bytes memory err) internal {
        vm.expectRevert(abi.encodeWithSignature("LimitOrderModule_OrderExecutionReverted(bytes)", err));
    }

    function _expectModuleNotInited() internal {
        vm.expectRevert(abi.encodeWithSignature("LimitOrderModule_ModuleNotInited()"));
    }

    function _expectInitDataShouldBeEmpty() internal {
        vm.expectRevert(abi.encodeWithSignature("LimitOrderModule_InitDataShouldBeEmpty()"));
    }

    function _expectAlreadyInited() internal {
        vm.expectRevert(abi.encodeWithSignature("ALREADY_INITED()"));
    }

    function _expectModuleNotAddedCorrectly() internal {
        vm.expectRevert(abi.encodeWithSignature("MODULE_NOT_ADDED_CORRECTLY()"));
    }

    function _expectModuleNotRemovedCorrectly() internal {
        vm.expectRevert(abi.encodeWithSignature("MODULE_NOT_REMOVED_CORRECTLY()"));
    }
}
