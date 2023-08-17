// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.18;

import "forge-std/Test.sol";
import {TransparentUpgradeableProxy as Proxy} from
    "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {Pool} from "contracts/pool/Pool.sol";
import {DataTypes} from "contracts/lib/DataTypes.sol";
import {PoolLens} from "contracts/lens/PoolLens.sol";
import {ILPToken} from "contracts/interfaces/ILPToken.sol";
import {LPToken} from "contracts/tokens/LPToken.sol";
import {IPool} from "contracts/interfaces/IPool.sol";
import {IOrderManager} from "contracts/interfaces/IOrderManager.sol";
import {OrderManager} from "contracts/orders/OrderManager.sol";
import {ETHUnwrapper} from "contracts/utils/ETHUnwrapper.sol";
import {PoolTestFixture} from "./Fixture.t.sol";

contract OrderManagerTest is PoolTestFixture {
    address tranche;
    OrderManager orders;

    address private constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address private executor = address(bytes20("executor"));

    function setUp() external {
        build();
        vm.startPrank(owner);
        tranche = address(new LPToken("LLP", "LLP", address(pool)));
        pool.addTranche(tranche);
        Pool.RiskConfig[] memory config = new Pool.RiskConfig[](1);
        config[0] = IPool.RiskConfig(tranche, 1000);
        pool.setRiskFactor(address(btc), config);
        pool.setRiskFactor(address(weth), config);
        OrderManager impl = new OrderManager();
        ProxyAdmin admin = new ProxyAdmin();
        Proxy proxy = new Proxy(address(impl), address(admin), bytes(""));
        orders = OrderManager(payable(address(proxy)));
        pool.setOrderManager(address(orders));

        address ethUnwapper = orders.ETH_UNWRAPPER();
        ETHUnwrapper unwrapper = new ETHUnwrapper(address(weth));
        vm.etch(ethUnwapper, address(unwrapper).code);

        liquidityCalculator.setFees(0, 0, 0, 0, 0);
        oracle.setPrice(address(btc), 20_000e22);
        oracle.setPrice(address(usdc), 1e24);
        oracle.setPrice(address(weth), 1000e12);
        vm.stopPrank();
    }

    function init() internal {
        vm.startPrank(owner);
        orders.initialize(address(weth), address(oracle), address(pool), 1, 1);
        orders.setMinExecutionFee(1e7, 1e7);
        orders.setExecutor(executor);
        orders.setExecutionDelayTime(1);
        vm.stopPrank();
    }

    function addLiquidity() internal {
        vm.startPrank(alice);
        btc.mint(10e8);
        usdc.mint(1_000_000e6);
        vm.deal(alice, 100e18);
        btc.approve(address(pool), type(uint256).max);
        usdc.approve(address(pool), type(uint256).max);
        weth.approve(address(pool), type(uint256).max);
        // add some init liquidity
        pool.addLiquidity(address(tranche), address(btc), 1e8, 0, alice);
        weth.deposit{value: 20 ether}();
        pool.addLiquidity(address(tranche), address(weth), 20 ether, 0, alice);
        pool.addLiquidity(address(tranche), address(usdc), 40_000e6, 0, alice);
        vm.stopPrank();
    }

    function test_initialize() external {
        vm.startPrank(owner);
        vm.expectRevert(IOrderManager.ZeroAddress.selector);
        orders.initialize(address(0), address(oracle), address(pool), 0.01 ether, 0.01 ether);

        vm.expectRevert(IOrderManager.ZeroAddress.selector);
        orders.initialize(address(weth), address(0), address(pool), 0.01 ether, 0.01 ether);

        vm.expectRevert(IOrderManager.InvalidExecutionFee.selector);
        orders.initialize(address(weth), address(oracle), address(pool), 1 ether, 1 ether);

        vm.expectRevert(IOrderManager.ZeroAddress.selector);
        orders.initialize(address(weth), address(oracle), address(0), 0.01 ether, 0.01 ether);

        orders.initialize(address(weth), address(oracle), address(pool), 0.01 ether, 0.01 ether);
        vm.stopPrank();
    }

    function test_place_leverage_order() external {
        init();
        addLiquidity();
        vm.prank(owner);
        pool.setPositionFee(0, 0);
        vm.startPrank(alice);
        btc.approve(address(orders), type(uint256).max);

        vm.roll(1);
        vm.warp(100);
        uint256 balanceBefore = btc.balanceOf(alice);
        uint256 payAmount = 1e7;
        orders.placeLeverageOrder{value: 1e17}(
            DataTypes.UpdatePositionType.INCREASE,
            DataTypes.Side.LONG,
            address(btc),
            address(btc),
            DataTypes.OrderType.MARKET,
            abi.encode(20_000e22, address(btc), payAmount, 2000e30, bytes(""))
        );

        vm.expectRevert(abi.encodeWithSelector(IOrderManager.InvalidLeverageTokenPair.selector, address(0), address(0)));
        orders.placeLeverageOrder{value: 1e17}(
            DataTypes.UpdatePositionType.INCREASE,
            DataTypes.Side.LONG,
            address(0),
            address(0),
            DataTypes.OrderType.MARKET,
            abi.encode(20_000e22, address(btc), payAmount, 2000e30, bytes(""))
        );

        vm.expectRevert(IOrderManager.ZeroPurchaseAmount.selector);
        orders.placeLeverageOrder{value: 1e17}(
            DataTypes.UpdatePositionType.INCREASE,
            DataTypes.Side.LONG,
            address(btc),
            address(btc),
            DataTypes.OrderType.MARKET,
            abi.encode(20_000e22, address(0), 0, 2000e30, bytes(""))
        );

        vm.expectRevert(IOrderManager.InvalidPurchaseToken.selector);
        orders.placeLeverageOrder{value: 1e17}(
            DataTypes.UpdatePositionType.INCREASE,
            DataTypes.Side.LONG,
            address(btc),
            address(btc),
            DataTypes.OrderType.MARKET,
            abi.encode(20_000e22, address(0), payAmount, 2000e30, bytes(""))
        );

        (, uint256 total) = orders.getOrders(alice, 0, 5);
        assertEq(total, 1);
        assertEq(btc.balanceOf(address(orders)), 1e7, "should deposit all token to order book");
        vm.stopPrank();

        vm.roll(2);
        vm.warp(101);
        vm.prank(executor);
        orders.executeLeverageOrder(1, payable(bob));
        PoolLens.PositionView memory position = lens.getPosition(alice, address(btc), address(btc), DataTypes.Side.LONG);
        console.log("Position", position.size, position.collateralValue);

        uint256 deposited = balanceBefore - btc.balanceOf(alice);
        console.log("Deposited", deposited);
        assertEq(deposited, 1e7);

        vm.prank(alice);
        orders.placeLeverageOrder{value: 1e16}(
            DataTypes.UpdatePositionType.DECREASE,
            DataTypes.Side.LONG,
            address(btc),
            address(btc),
            DataTypes.OrderType.MARKET,
            abi.encode(20_000e22, btc, 2000e30, 0, bytes(""))
        );

        vm.roll(3);
        vm.warp(102);
        balanceBefore = btc.balanceOf(alice);
        vm.prank(executor);
        orders.executeLeverageOrder(2, payable(bob));
        uint256 received = btc.balanceOf(alice) - balanceBefore;
        console.log("received", received);
        assertEq(received, 1e7);
    }

    function test_place_leverage_order_eth() external {
        init();
        addLiquidity();
        vm.startPrank(alice);
        vm.roll(1);
        vm.warp(100);
        uint256 balanceBefore = alice.balance;
        uint256 payAmount = 1e17;
        orders.placeLeverageOrder{value: 11e16}(
            DataTypes.UpdatePositionType.INCREASE,
            DataTypes.Side.LONG,
            address(weth),
            address(weth),
            DataTypes.OrderType.MARKET,
            abi.encode(1_000e12, ETH, payAmount, 1000e30, bytes(""))
        );
        assertEq(weth.balanceOf(address(orders)), 1e17);
        vm.stopPrank();

        vm.roll(2);
        vm.warp(101);
        vm.prank(executor);
        orders.executeLeverageOrder(1, payable(bob));
        PoolLens.PositionView memory position =
            lens.getPosition(alice, address(weth), address(weth), DataTypes.Side.LONG);
        console.log("Position", position.size, position.collateralValue);

        uint256 deposited = balanceBefore - alice.balance;
        //console.log("Deposited", deposited);
        assertEq(deposited, 11e16);

        vm.prank(alice);
        orders.placeLeverageOrder{value: 1e16}(
            DataTypes.UpdatePositionType.DECREASE,
            DataTypes.Side.LONG,
            address(weth),
            address(weth),
            DataTypes.OrderType.MARKET,
            abi.encode(1_000e12, ETH, 1000e30, 0, bytes(""))
        );

        vm.roll(3);
        vm.warp(102);
        balanceBefore = alice.balance;
        vm.prank(executor);
        orders.executeLeverageOrder(2, payable(bob));
        uint256 received = alice.balance - balanceBefore;
        //console.log("fee", lens.poolAssets(address(pool), address(weth)).feeReserve);
        assertEq(received, 98e15);
    }

    function test_swap_eth() external {
        init();
        addLiquidity();
        vm.startPrank(alice);
        uint256 ethBefore = alice.balance;
        uint256 usdcBefore = usdc.balanceOf(alice);
        orders.swap{value: 1e16}(ETH, address(usdc), 1e16, 0, new bytes(0));
        console.log("ETH in", ethBefore - alice.balance);
        console.log("USDC out", usdc.balanceOf(alice) - usdcBefore);

        ethBefore = alice.balance;
        usdc.approve(address(orders), 1e7);
        orders.swap(address(usdc), ETH, 1e7, 0, new bytes(0));
        console.log("ETH out", alice.balance - ethBefore);
        vm.stopPrank();
    }

    function test_cancel_order() external {
        init();
        addLiquidity();
        vm.startPrank(alice);
        btc.approve(address(orders), type(uint256).max);
        vm.roll(1);
        uint256 balanceBefore = btc.balanceOf(alice);
        uint256 payAmount = 1e7;
        orders.placeLeverageOrder{value: 1e17}(
            DataTypes.UpdatePositionType.INCREASE,
            DataTypes.Side.LONG,
            address(btc),
            address(btc),
            DataTypes.OrderType.MARKET,
            abi.encode(20_000e22, address(btc), payAmount, 2000e30, bytes(""))
        );
        assertEq(btc.balanceOf(address(orders)), 1e7);
        vm.roll(2);
        assertEq(btc.balanceOf(address(alice)), balanceBefore - 1e7);
        vm.stopPrank();

        vm.startPrank(owner);
        vm.expectRevert(IOrderManager.OnlyOrderOwner.selector);
        orders.cancelLeverageOrder(1);
        vm.stopPrank();

        vm.startPrank(alice);
        orders.cancelLeverageOrder(1);
        assertEq(btc.balanceOf(address(alice)), balanceBefore);
        assertEq(btc.balanceOf(address(orders)), 0);
    }

    function test_expire_order() external {
        init();
        addLiquidity();
        vm.startPrank(alice);
        btc.approve(address(orders), type(uint256).max);
        vm.roll(1);
        uint256 balanceBefore = btc.balanceOf(alice);
        vm.warp(0);
        uint256 payAmount = 1e7;
        orders.placeLeverageOrder{value: 1e17}(
            DataTypes.UpdatePositionType.INCREASE,
            DataTypes.Side.LONG,
            address(btc),
            address(btc),
            DataTypes.OrderType.MARKET,
            abi.encode(20_000e22, address(btc), payAmount, 2000e30, bytes(""))
        );
        assertEq(btc.balanceOf(address(orders)), 1e7);
        vm.stopPrank();
        vm.prank(executor);
        vm.expectRevert(IOrderManager.ExecutionDelay.selector);
        orders.executeLeverageOrder(1, payable(alice));

        assertEq(btc.balanceOf(address(alice)), balanceBefore - 1e7);

        vm.roll(2);
        vm.warp(10 days);
        vm.prank(executor);
        vm.expectRevert(IOrderManager.OrderNotOpen.selector);
        orders.executeLeverageOrder(0, payable(alice));

        vm.prank(alice);
        vm.expectRevert(IOrderManager.OnlyExecutor.selector);
        orders.executeLeverageOrder(1, payable(owner));

        vm.prank(executor);
        orders.executeLeverageOrder(1, payable(alice));
        (,,, DataTypes.OrderStatus status,,,,,,,) = orders.leverageOrders(1);
        assertTrue(status == DataTypes.OrderStatus.EXPIRED);
    }

    function test_place_swap_order() external {
        init();
        addLiquidity();
        vm.startPrank(alice);
        btc.approve(address(orders), type(uint256).max);
        vm.expectRevert(IOrderManager.ExecutionFeeTooLow.selector);
        orders.placeSwapOrder(address(btc), address(usdc), 1e7, 0, 20_000e22, new bytes(0));
        vm.expectRevert(IOrderManager.InvalidSwapPair.selector);
        orders.placeSwapOrder{value: 1e17}(address(0), address(usdc), 1e7, 0, 20_000e22, new bytes(0));
        orders.placeSwapOrder{value: 1e17}(address(btc), address(usdc), 1e7, 0, 20_000e22, new bytes(0));
        orders.placeSwapOrder{value: 1e17}(ETH, address(usdc), 1e7, 0, 1_600e22, new bytes(0));
        (, uint256 total) = orders.getSwapOrders(alice, 0, 5);
        assertEq(total, 2);
    }

    function test_execute_swap_order() external {
        init();
        addLiquidity();
        vm.startPrank(alice);
        vm.warp(100);
        btc.approve(address(orders), type(uint256).max);
        uint256 id = orders.placeSwapOrder{value: 1e17}(address(btc), address(usdc), 1e7, 0, 20_000e22, new bytes(0));
        vm.stopPrank();

        (,,,,,,,,, uint256 time) = orders.swapOrders(id);
        assertEq(time, 100);

        vm.roll(2);
        vm.warp(101);
        vm.prank(executor);
        orders.executeSwapOrder(1, payable(alice));
        assertEq(btc.balanceOf(address(orders)), 0);
    }

    function test_execute_swap_eth_order() external {
        init();
        addLiquidity();
        vm.warp(100);
        vm.startPrank(alice);
        btc.approve(address(orders), type(uint256).max);
        orders.placeSwapOrder{value: 1e17}(address(btc), ETH, 1e7, 0, 20_000e22, new bytes(0));
        vm.stopPrank();

        vm.warp(101);
        vm.prank(executor);
        orders.executeSwapOrder(1, payable(alice));
        assertEq(btc.balanceOf(address(orders)), 0);
    }

    function test_cancel_swap_order() external {
        init();
        addLiquidity();
        vm.startPrank(alice);
        uint256 balanceBefore = btc.balanceOf(alice);
        btc.approve(address(orders), type(uint256).max);
        orders.placeSwapOrder{value: 1e17}(address(btc), address(usdc), 1e7, 0, 20_000e22, new bytes(0));
        vm.stopPrank();

        vm.startPrank(bob);
        vm.expectRevert(IOrderManager.OnlyOrderOwner.selector);
        orders.cancelSwapOrder(1);
        vm.stopPrank();

        vm.startPrank(alice);
        orders.cancelSwapOrder(1);
        assertEq(btc.balanceOf(address(alice)), balanceBefore);
    }

    function test_set_oracle() external {
        init();
        vm.startPrank(owner);
        vm.expectRevert(IOrderManager.ZeroAddress.selector);
        orders.setOracle(address(0));
        orders.setOracle(address(oracle));
    }

    function test_set_order_hook() external {
        init();
        vm.startPrank(owner);
        orders.setOrderHook(address(0));
    }

    function test_set_executor() external {
        init();
        vm.startPrank(owner);
        vm.expectRevert(IOrderManager.ZeroAddress.selector);
        orders.setExecutor(address(0));
        orders.setExecutor(alice);
    }

    function test_set_min_execution_fee() external {
        init();
        vm.startPrank(owner);
        vm.expectRevert(IOrderManager.InvalidExecutionFee.selector);
        orders.setMinExecutionFee(0, 0);
        vm.expectRevert(IOrderManager.InvalidExecutionFee.selector);
        orders.setMinExecutionFee(1e18, 1e18);
        orders.setMinExecutionFee(1e7, 1e7);
    }

    function test_controller_can_enable_public_execution() external {
        init();
        address controller = address(42);
        vm.prank(bob);
        vm.expectRevert("Ownable: caller is not the owner");
        orders.setController(controller);
        assertEq(orders.controller(), address(0), "controller should be zero");

        vm.prank(owner);
        orders.setController(controller);
        assertEq(orders.controller(), controller, "controller should be set");

        vm.prank(bob);
        vm.expectRevert(IOrderManager.OnlyOwnerOrController.selector);
        orders.setEnablePublicExecution(true);
        assertFalse(orders.enablePublicExecution(), "should disable public exec");

        vm.prank(controller);
        orders.setEnablePublicExecution(true);
        assertTrue(orders.enablePublicExecution(), "should disable public exec");
    }
}
