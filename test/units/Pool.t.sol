// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.18;

import "forge-std/Test.sol";
import {TransparentUpgradeableProxy as Proxy} from
    "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {Pool} from "contracts/pool/Pool.sol";
import {IPool} from "contracts/interfaces/IPool.sol";
import {DataTypes} from "contracts/lib/DataTypes.sol";
import {PoolLens} from "contracts/lens/PoolLens.sol";
import {MockOracle} from "test/mocks/MockOracle.t.sol";
import {MockERC20} from "test/mocks/MockERC20.t.sol";
import {ILPToken} from "contracts/interfaces/ILPToken.sol";
import {LPToken} from "contracts/tokens/LPToken.sol";
import {SimpleInterestRateModel} from "contracts/interest/SimpleInterestRateModel.sol";
import {PoolTestFixture} from "./Fixture.t.sol";

/// @dev DAO take all fee. Test Position param only
contract PoolTest is PoolTestFixture {
    address tranche;

    function _beforeTestPosition() internal {
        vm.prank(owner);
        pool.setOrderManager(orderManager);
        oracle.setPrice(address(usdc), 1e24);
        oracle.setPrice(address(btc), 20000e22);
        oracle.setPrice(address(weth), 1000e12);
        vm.startPrank(alice);
        btc.mint(10e8);
        usdc.mint(50000e6);
        vm.deal(alice, 100e18);
        vm.stopPrank();
    }

    function setUp() external {
        build();
        vm.startPrank(owner);
        tranche = address(new LPToken("LLP", "LLP", address(pool)));
        pool.addTranche(tranche);
        IPool.RiskConfig[] memory config = new IPool.RiskConfig[](1);
        config[0] = IPool.RiskConfig(tranche, 1000);
        pool.setRiskFactor(address(btc), config);
        // pool.setRiskFactor(address(usdc), config);
        pool.setRiskFactor(address(weth), config);
        vm.stopPrank();
    }

    function test_initilize_pool() external {
        vm.startPrank(owner);
        Pool poolImpl = new Pool();
        address admin = address(bytes20("admin"));
        Proxy proxy = new Proxy(address(poolImpl), address(admin), new bytes(0));
        Pool pool = Pool(address(proxy));
        lens = new PoolLens(address(pool));
        pool.initialize(
            20, // max leverage | 20x
            1e8, // maintenance margin
            100
        );
    }

    // ========== ADMIN FUNCTIONS ==========
    function test_fail_set_oracle_from_unauthorized_should_revert() public {
        vm.prank(eve);
        vm.expectRevert("Ownable: caller is not the owner");
        pool.setOracle(address(oracle));
    }

    function test_set_oracle() public {
        vm.prank(owner);
        pool.setOracle(address(oracle));
    }

    function test_set_risk_factor() public {
        vm.prank(owner);
        IPool.RiskConfig[] memory config = new IPool.RiskConfig[](1);
        config[0] = IPool.RiskConfig(tranche, 1000);
        pool.setRiskFactor(address(btc), config);
    }

    function test_add_token() public {
        vm.prank(owner);
        address token = address(bytes20("tusd"));
        pool.addToken(token, true);
    }

    function test_delist_token() public {
        vm.startPrank(owner);
        address token = address(bytes20("tusd"));
        pool.addToken(token, true);
        pool.delistToken(token);

        vm.expectRevert();
        pool.delistToken(token);
        vm.stopPrank();
    }

    function test_set_dao_fee() public {
        vm.prank(owner);
        pool.setDaoFee(1e10);

        vm.prank(owner);
        vm.expectRevert();
        pool.setDaoFee(2e10);

        vm.prank(address(1));
        vm.expectRevert();
        pool.setDaoFee(1e10);
    }

    function test_set_max_leverage() public {
        vm.prank(owner);
        pool.setMaxLeverage(30);

        vm.prank(owner);
        vm.expectRevert();
        pool.setMaxLeverage(0);

        vm.prank(address(1));
        vm.expectRevert();
        pool.setMaxLeverage(10);
    }

    function test_set_fee_distributor() public {
        vm.prank(owner);
        pool.setFeeDistributor(address(bytes20("fd")));

        vm.prank(owner);
        vm.expectRevert();
        pool.setFeeDistributor(address(0));

        vm.prank(address(1));
        vm.expectRevert();
        pool.setFeeDistributor(address(bytes20("fd")));
    }

    function test_withdraw_fee() external {
        address feeDistributor = address(bytes20("fd"));
        vm.prank(owner);
        pool.setFeeDistributor(feeDistributor);

        test_add_and_remove_liquidity();
        vm.prank(feeDistributor);
        pool.withdrawFee(address(btc), feeDistributor);
        assertTrue(btc.balanceOf(feeDistributor) > 0);

        vm.prank(address(bytes20("eve")));
        vm.expectRevert();
        pool.withdrawFee(address(btc), feeDistributor);
    }

    function test_set_target_weight() external {
        IPool.TokenWeight[] memory config = new IPool.TokenWeight[](3);
        config[0] = IPool.TokenWeight({token: address(btc), weight: 1000});
        config[1] = IPool.TokenWeight({token: address(weth), weight: 1000});
        config[2] = IPool.TokenWeight({token: address(usdc), weight: 2000});

        vm.prank(owner);
        pool.setTargetWeight(config);

        vm.prank(address(bytes20("eve")));
        vm.expectRevert();
        pool.setTargetWeight(config);
    }

    function test_add_tranche() external {
        vm.prank(owner);
        pool.addTranche(address(2));

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(IPool.TrancheAlreadyAdded.selector));
        pool.addTranche(address(2));

        vm.prank(owner);
        pool.addTranche(address(3));

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(IPool.MaxNumberOfTranchesReached.selector));
        pool.addTranche(address(4));
    }

    function test_set_controller() external {
        address controller = address(bytes20("controller"));
        vm.prank(owner);
        pool.setController(controller);

        address eve = address(bytes20("eve"));
        vm.prank(eve);
        vm.expectRevert();
        pool.setController(eve);
    }

    function test_set_liquidity_calculator() external {
        address calculator = address(bytes20("liquidity_calculator"));
        vm.prank(owner);
        pool.setLiquidityCalculator(calculator);

        address eve = address(bytes20("eve"));
        vm.prank(eve);
        vm.expectRevert();
        pool.setLiquidityCalculator(eve);
    }

    function test_set_max_liquidity() external {
        address controller = address(bytes20("liquidity_calculator"));
        vm.prank(owner);
        pool.setController(controller);

        vm.prank(controller);
        pool.setMaxLiquidity(address(btc), 1e18);
    }

    // ========== LIQUIDITY PROVIDER ==========

    function test_fail_to_add_liquidity_when_risk_factor_not_set() public {
        MockERC20 tokenA = new MockERC20("tokenA", "TA", 18);
        vm.prank(owner);
        pool.addToken(address(tokenA), false);
        vm.startPrank(alice, alice);
        tokenA.mint(1 ether);
        tokenA.approve(address(router), 1 ether);
        vm.expectRevert(IPool.AddLiquidityNotAllowed.selector);
        router.addLiquidity(tranche, address(tokenA), 1 ether, 0, alice);
    }

    function test_add_liquidity_using_not_whitelisted_token() public {
        vm.startPrank(alice, alice);
        btc.approve(address(router), 1000e6);
        vm.expectRevert();
        router.addLiquidity(tranche, address(0), 100e6, 0, alice);
    }

    function test_add_liquidity_to_unknown_tranche() public {
        vm.startPrank(alice, alice);
        btc.approve(address(router), 1000e6);
        vm.expectRevert();
        router.addLiquidity(address(1), address(btc), 100e6, 0, alice);
    }

    function test_add_and_remove_liquidity() public {
        oracle.setPrice(address(usdc), 1e24);
        oracle.setPrice(address(btc), 20000e22);
        oracle.setPrice(address(weth), 1000e12);
        vm.startPrank(alice);
        vm.deal(alice, 100e18);
        btc.mint(1e8);
        usdc.mint(10000e6);
        btc.approve(address(router), type(uint256).max);
        usdc.approve(address(router), type(uint256).max);
        ILPToken lpToken = ILPToken(tranche);

        // add 10k $ => 9.98k LP
        router.addLiquidity(tranche, address(usdc), 10_000e6, 0, address(alice));
        uint256 poolAmount1;
        {
            PoolLens.PoolAsset memory asset = lens.poolAssets(address(usdc));
            assertEq(asset.poolBalance, 10000e6, "pool should take all deposited token");
            assertEq(asset.poolAmount, 9_980e6, "should take 0.2% fee");
            assertEq(asset.feeReserve, 20e6, "should take 0.2% fee");
            assertEq(lpToken.balanceOf(address(alice)), 9_980e18, "initial price should be 1$");
            poolAmount1 = asset.poolAmount;
        }

        //add 1btc = 20k$, receive 19.9k LP
        router.addLiquidity(tranche, address(btc), 1e8, 0, address(alice));
        console.log("liquidity added 2");
        assertEq(lpToken.balanceOf(address(alice)), 29880e18);
        {
            PoolLens.PoolAsset memory asset = lens.poolAssets(address(btc));
            assertEq(asset.poolBalance, 1e8);
            assertEq(asset.poolAmount, 99500000);
            assertEq(asset.feeReserve, 500000);
            assertEq(asset.reservedAmount, 0);
        }

        // eth, fee discount applied
        router.addLiquidityETH{value: 10e18}(tranche, 0, address(alice));
        console.log("liquidity added 3");
        assertEq(liquidityCalculator.getPoolValue(true), 39880e30, "should take 0 fee");
        assertEq(lpToken.balanceOf(address(alice)), 39880e18);

        lpToken.approve(address(router), type(uint256).max);
        router.removeLiquidity(tranche, address(usdc), 1e18, 0, alice);

        {
            PoolLens.PoolAsset memory asset = lens.poolAssets(address(usdc));
            console.log("after remove", asset.poolAmount);
            assertEq(asset.poolAmount, poolAmount1 - 1e6);
        }
        // console.log("check balance");
        // assertEq(usdc.balanceOf(alice), 1e6);
        vm.stopPrank();
    }

    // ============ POSITIONS ==============
    function test_only_order_manager_can_increase_decrease_position() external {
        vm.expectRevert(abi.encodeWithSelector(IPool.OrderManagerOnly.selector));
        pool.increasePosition(alice, address(btc), address(btc), 1e8, DataTypes.Side.LONG);
        vm.expectRevert(abi.encodeWithSelector(IPool.OrderManagerOnly.selector));
        pool.decreasePosition(alice, address(btc), address(btc), 1e6, 1e8, DataTypes.Side.LONG, alice);
    }

    function test_set_order_manager() external {
        vm.expectRevert("Ownable: caller is not the owner");
        pool.setOrderManager(alice);
        vm.prank(owner);
        pool.setOrderManager(alice);
        assertEq(pool.orderManager(), alice);
    }

    function test_cannot_long_with_invalid_size() external {
        _beforeTestPosition();
        vm.startPrank(orderManager);
        btc.mint(1e8);
        // cannot open position with size larger than pool amount
        btc.transfer(address(pool), 1e7); // 0.1BTC = 2_000$
        // try to long 10x
        vm.expectRevert(abi.encodeWithSelector(IPool.CannotDistributeToTranches.selector));
        pool.increasePosition(alice, address(btc), address(btc), 20_000e30, DataTypes.Side.LONG);
        vm.stopPrank();
    }

    function test_long_position() external {
        _beforeTestPosition();
        // add liquidity
        vm.startPrank(alice);
        btc.approve(address(router), type(uint256).max);
        router.addLiquidity(tranche, address(btc), 10e8, 0, alice);
        vm.stopPrank();

        vm.startPrank(orderManager);
        btc.mint(1e8);

        {
            PoolLens.PoolAsset memory asset = lens.poolAssets(address(btc));
            console.log("cumulativeInterestRate", asset.borrowIndex, asset.lastAccrualTimestamp);
            assertEq(asset.poolAmount + asset.feeReserve, asset.poolBalance, "addLiquidity: !invariant");
        }

        // try to open long position with 5x leverage
        btc.transfer(address(pool), 1e7); // 0.1BTC = 2_000$

        // == OPEN POSITION ==
        vm.warp(1001);
        uint256 feeReserveBefore = pool.feeReserves(address(btc));
        uint256 poolAmountBefore = pool.getPoolAsset(address(btc)).poolAmount;
        vm.expectRevert();
        pool.increasePosition(alice, address(btc), address(btc), 1_000e30, DataTypes.Side.LONG);
        console.log("poolAmountBefore", poolAmountBefore);
        pool.increasePosition(alice, address(btc), address(btc), 10_000e30, DataTypes.Side.LONG);
        PoolLens.PositionView[] memory positions = lens.getUserPositions(alice);
        assertEq(positions.length, 1);
        PoolLens.PositionView memory position = positions[0];
        assertTrue(position.side == DataTypes.Side.LONG);
        assertEq(position.owner, alice);
        assertEq(position.revision, 1);
        assertEq(position.indexToken, address(btc));
        assertEq(position.collateralToken, address(btc));
        assertEq(position.size, 10_000e30);
        assertEq(position.reserveAmount, 5e7);
        // fee = 10_000 * 0.1% = 10$
        // collateral value 0.1% fee = 2000 - (20_000 * 0.1%) = 1990
        // take to pool amount: 0.1BTC - 10$
        // collateral amount = 0.0995
        assertEq(position.collateralValue, 1990e30);

        {
            uint256 lastAccrual = pool.lastAccrualTimestamps(address(btc));
            console.log("lastAccrual", lastAccrual);
            PoolLens.PoolAsset memory asset = lens.poolAssets(address(btc));
            assertEq(asset.lastAccrualTimestamp, 1000, "increase: interest not accrued");
            assertEq(asset.borrowIndex, 0, "increase: interest not accrued");
            assertEq(asset.poolBalance, btc.balanceOf(address(pool)), "pool balance not update"); // 1BTC deposit + 0.1BTC collateral
            assertEq(asset.feeReserve, feeReserveBefore + 50000, "fee reserve not match");
            assertEq(asset.poolAmount, 1007950000, "pool amount not match");
            assertEq(asset.poolAmount + asset.feeReserve, asset.poolBalance, "increase: !invariant");
            assertEq(asset.reservedAmount, 5e7); // 0.5BTC = position size
            assertEq(asset.guaranteedValue, 8_010e30, "increase: guranteed value incorrect");
            assertEq(pool.getTrancheAsset(tranche, address(btc)).reservedAmount, 5e7, "trache reserve not update");
            // assertEq(pool.getTrancheValue(tranche), lens.getTrancheValue( tranche));
        }

        // calculate pnl
        oracle.setPrice(address(btc), 20_500e22);
        position = lens.getPosition(alice, address(btc), address(btc), DataTypes.Side.LONG);
        assertEq(position.pnl, 250e30);

        vm.warp(1100);
        uint256 priorBalance = btc.balanceOf(alice);

        // ==== DECREASE PARTIAL ====
        // close 50%, fee = 5 (position) + 0.454566 (funding/interest)
        // profit = 125, transfer out 995$ + 119$ = 0.05434146BTC
        pool.decreasePosition(alice, address(btc), address(btc), 995e30, 5_000e30, DataTypes.Side.LONG, alice);

        {
            PoolLens.PoolAsset memory asset = lens.poolAssets(address(btc));
            console.log(asset.poolAmount, asset.feeReserve, asset.poolBalance);
            assertEq(asset.lastAccrualTimestamp, 1100, "interest not accrued");
            assertEq(asset.borrowIndex, 49605, "interest not accrued"); // 1 interval
            assertEq(asset.reservedAmount, 25e6);
            assertEq(asset.poolBalance, 1004561218);
            assertApproxEqAbs(
                asset.poolAmount + asset.feeReserve, asset.poolBalance, 1, "pool balance and amount not match"
            );
        }

        position = lens.getPosition(alice, address(btc), address(btc), DataTypes.Side.LONG);
        assertEq(position.pnl, 125e30);
        assertEq(position.size, 5_000e30);
        assertEq(position.collateralValue, 995e30);
        {
            uint256 balance = btc.balanceOf(alice);
            uint256 transferOut = balance - priorBalance;
            assertEq(transferOut, 5438782);
            priorBalance = balance;
        }

        // == CLOSE ALL POSITION ==
        vm.warp(1200);
        position = lens.getPosition(alice, address(btc), address(btc), DataTypes.Side.LONG);
        pool.decreasePosition(alice, address(btc), address(btc), 995e30, 5_000e30, DataTypes.Side.LONG, alice);

        {
            PoolLens.PoolAsset memory asset = lens.poolAssets(address(btc));
            assertEq(asset.guaranteedValue, 0);
        }

        position = lens.getPosition(alice, address(btc), address(btc), DataTypes.Side.LONG);
        assertEq(position.size, 0);
        assertEq(position.collateralValue, 0);
        {
            uint256 balance = btc.balanceOf(alice);
            uint256 transferOut = balance - priorBalance;
            assertEq(transferOut, 5438963);
            priorBalance = balance;
        }

        vm.stopPrank();
    }

    function test_short_position() external {
        vm.startPrank(owner);
        pool.setPositionFee(0, 0);
        SimpleInterestRateModel irModel = new SimpleInterestRateModel(0);
        pool.setInterestRateModel(address(usdc), address(irModel));
        pool.setInterestRateModel(address(btc), address(irModel));
        pool.setInterestRateModel(address(weth), address(irModel));
        vm.stopPrank();

        _beforeTestPosition();
        // add liquidity
        vm.startPrank(alice);
        usdc.approve(address(router), type(uint256).max);
        router.addLiquidity(tranche, address(usdc), 20000e6, 0, alice);
        uint256 amountToRemove = LPToken(tranche).balanceOf(alice);
        btc.approve(address(router), type(uint256).max);
        router.addLiquidity(tranche, address(btc), 10e8, 0, alice);
        vm.stopPrank();

        vm.startPrank(orderManager);
        // OPEN SHORT position with 5x leverage
        usdc.mint(2000e6);
        usdc.transfer(address(pool), 2000e6); // 0.1BTC = 2_000$
        vm.warp(1000);
        pool.increasePosition(alice, address(btc), address(usdc), 10_000e30, DataTypes.Side.SHORT);

        {
            PoolLens.PositionView[] memory positions = lens.getUserPositions(alice);
            assertEq(positions.length, 1);
            PoolLens.PositionView memory position = positions[0];
            assertTrue(position.side == DataTypes.Side.SHORT);
            assertEq(position.owner, alice);
            assertEq(position.revision, 1);
            assertEq(position.indexToken, address(btc));
            assertEq(position.collateralToken, address(usdc));
            assertEq(position.size, 10_000e30);
            assertEq(position.collateralValue, 2_000e30);
            assertEq(position.reserveAmount, 10_000e6);
        }

        uint256 poolAmountBefore;
        {
            PoolLens.PoolAsset memory asset = lens.poolAssets(address(btc));
            assertEq(asset.totalShortSize, 10_000e30);
            assertEq(asset.averageShortPrice, 20_000e22);
            poolAmountBefore = asset.poolAmount;
            // test usdc balance
            assertEq(lens.poolAssets(address(usdc)).poolBalance, 22000e6);
        }
        // console.log("pool value before", pool.getPoolValue(true));

        // CLOSE position in full
        oracle.setPrice(address(btc), 19500e22);
        uint256 close;
        {
            PoolLens.PositionView memory position =
                lens.getPosition(alice, address(btc), address(usdc), DataTypes.Side.SHORT);
            console.log("Pnl", position.pnl);
            console.log("collateral value", position.collateralValue);
            close = position.collateralValue;
        }

        vm.warp(1100);
        uint256 priorBalance = usdc.balanceOf(alice);
        pool.decreasePosition(alice, address(btc), address(usdc), close, 10_000e30, DataTypes.Side.SHORT, alice);
        uint256 transferOut = usdc.balanceOf(alice) - priorBalance;
        console.log("transfer out", transferOut);
        // console.log("pool value after", pool.getPoolValue(true));

        {
            PoolLens.PoolAsset memory asset = lens.poolAssets(address(btc));
            PoolLens.PositionView memory position =
                lens.getPosition(alice, address(btc), address(usdc), DataTypes.Side.SHORT);
            assertEq(position.size, 0);
            assertEq(position.collateralValue, 0);
            assertEq(asset.poolAmount, poolAmountBefore);
        }
        vm.stopPrank();
        // REMOVE liquidity after add
        vm.startPrank(alice);

        uint256 aliceUsdc = usdc.balanceOf(alice);
        LPToken(tranche).approve(address(router), type(uint256).max);
        router.removeLiquidity(tranche, address(usdc), amountToRemove, 0, alice);
        console.log("USDC out", usdc.balanceOf(alice) - aliceUsdc);
        vm.stopPrank();
    }

    // liquidate when maintenance margin not sufficient
    function test_liquidate_position_with_low_maintenance_margin() external {
        _beforeTestPosition();
        // add liquidity
        vm.startPrank(alice);
        btc.approve(address(router), type(uint256).max);
        router.addLiquidity(tranche, address(btc), 1e8, 0, alice);
        vm.stopPrank();

        vm.startPrank(orderManager);
        btc.mint(1e8);
        // try to open long position with 5x leverage
        vm.warp(1000);
        btc.transfer(address(pool), 1e7); // 0.1BTC = 2_000$
        pool.increasePosition(alice, address(btc), address(btc), 10_000e30, DataTypes.Side.LONG);
        vm.stopPrank();

        PoolLens.PositionView memory position = lens.getPosition(alice, address(btc), address(btc), DataTypes.Side.LONG);
        assertEq(position.size, 10_000e30);
        assertEq(position.reserveAmount, 5e7);
        assertEq(position.collateralValue, 1990e30); // 0.1% fee = 2000 - (20_000 * 0.1%) = 1990

        {
            PoolLens.PoolAsset memory asset = lens.poolAssets(address(btc));
            assertEq(asset.poolBalance, 110000000, "pool balance not update"); // 1BTC deposit + 0.1BTC collateral
            assertEq(asset.reservedAmount, 5e7); // 0.5BTC = position size
            _checkInvariant(address(btc));
        }

        // calculate pnl
        oracle.setPrice(address(btc), 16190e22);
        position = lens.getPosition(alice, address(btc), address(btc), DataTypes.Side.LONG);
        assertEq(position.pnl, 1905e30);
        assertFalse(position.hasProfit);

        // liquidate position
        // profit = -1905, collateral value = 85, margin rate = 0.85% -> liquidated
        // take 10$ position fee, refund 70$ collateral, pay 5$ to liquidator
        // pool balance = 1.1 - 75/16190
        // vm.startPrank(bob);
        uint256 balance = btc.balanceOf(orderManager);
        vm.startPrank(orderManager);
        pool.liquidatePosition(alice, address(btc), address(btc), DataTypes.Side.LONG);
        {
            PoolLens.PoolAsset memory asset = lens.poolAssets(address(btc));
            assertEq(asset.reservedAmount, 0, "liquidate: reserved not reset");
            assertEq(asset.poolBalance, 109536752, "balance not update after liquidate");
            _checkInvariant(address(btc));
        }
        balance = btc.balanceOf(orderManager) - balance;
        assertEq(balance, 30883, "not transfer out liquidation fee"); // 5$ / 16190
        vm.stopPrank();
    }

    // liquidate too slow, net value far lower than liquidation fee
    // collect all collateral amount, liquidation fee take from pool amount
    function test_liquidate_when_net_value_lower_than_liquidate_fee() external {
        _beforeTestPosition();
        // add liquidity
        vm.startPrank(alice);
        btc.approve(address(router), type(uint256).max);
        router.addLiquidity(tranche, address(btc), 1e8, 0, alice);
        vm.stopPrank();

        vm.startPrank(orderManager);
        btc.mint(1e8);

        // try to open long position with 5x leverage
        vm.warp(1000);
        btc.transfer(address(pool), 1e7); // 0.1BTC = 2_000$
        pool.increasePosition(alice, address(btc), address(btc), 10_000e30, DataTypes.Side.LONG);
        PoolLens.PositionView memory position = lens.getPosition(alice, address(btc), address(btc), DataTypes.Side.LONG);
        assertEq(position.size, 10_000e30);
        assertEq(position.reserveAmount, 5e7);
        assertEq(position.collateralValue, 1990e30); // 0.1% fee = 2000 - (20_000 * 0.1%) = 1990

        {
            PoolLens.PoolAsset memory asset = lens.poolAssets(address(btc));
            assertEq(asset.poolBalance, 110000000, "pool balance not update"); // 1BTC deposit + 0.1BTC collateral
            assertEq(asset.reservedAmount, 5e7); // 0.5BTC = position size
            _checkInvariant(address(btc));
        }

        // calculate pnl
        oracle.setPrice(address(btc), 16000e22);
        position = lens.getPosition(alice, address(btc), address(btc), DataTypes.Side.LONG);
        assertEq(position.pnl, 2000e30);
        assertFalse(position.hasProfit);
        // collateral = (init + pnl) = 85$ < 0.01 * 10_000
        // charge liquidate fee = 5$, position fee = 10$ transfer remain 70$ to position owner
        // pool balance =
        vm.stopPrank();

        // liquidate position
        // profit = -2000, transfer out liquidation fee
        // pool balance -= 5$ (liquidation fee only)
        uint256 balance = btc.balanceOf(orderManager);
        vm.startPrank(orderManager);
        pool.liquidatePosition(alice, address(btc), address(btc), DataTypes.Side.LONG);
        {
            PoolLens.PoolAsset memory asset = lens.poolAssets(address(btc));

            assertEq(asset.reservedAmount, 0, "liquidate: reserve amount reset");
            assertEq(asset.poolBalance, 109968750, "balance not update after liquidate");
            assertApproxEqAbs(
                asset.poolAmount + asset.feeReserve, asset.poolBalance, 1, "pool amount and pool balance miss matched"
            );
        }
        balance = btc.balanceOf(orderManager) - balance;
        assertEq(balance, 31250, "not transfer out liquidation fee"); // 5$ / 16k
        vm.stopPrank();
    }

    function test_liquidate_short_position() external {
        vm.prank(owner);
        pool.setPositionFee(1e7, 5e30);
        _beforeTestPosition();
        // add liquidity
        vm.startPrank(alice);
        usdc.approve(address(router), type(uint256).max);
        router.addLiquidity(tranche, address(usdc), 11_000e6, 0, alice);
        btc.approve(address(router), type(uint256).max);
        router.addLiquidity(tranche, address(btc), 10e8, 0, alice);
        vm.stopPrank();

        vm.startPrank(orderManager);
        usdc.mint(1000e6);

        // try to open long position with 5x leverage
        vm.warp(1000);
        usdc.transfer(address(pool), 1000e6); // 0.1BTC = 2_000$
        pool.increasePosition(alice, address(btc), address(usdc), 10_000e30, DataTypes.Side.SHORT);
        PoolLens.PositionView memory position =
            lens.getPosition(alice, address(btc), address(usdc), DataTypes.Side.SHORT);
        assertEq(position.size, 10_000e30);
        assertEq(position.reserveAmount, 10_000e6);
        assertEq(position.collateralValue, 990e30); // 0.1% fee = 1000 - (10_000 * 0.1%) = 1990

        {
            PoolLens.PoolAsset memory asset = lens.poolAssets(address(usdc));
            assertEq(asset.reservedAmount, 10_000e6); //
        }

        // calculate pnl
        oracle.setPrice(address(btc), 22_000e22);
        position = lens.getPosition(alice, address(btc), address(usdc), DataTypes.Side.SHORT);
        assertEq(position.pnl, 1000e30);
        assertFalse(position.hasProfit);

        vm.stopPrank();

        // liquidate position
        // profit = -1000, transfer out liquidation fee
        vm.startPrank(bob);
        pool.liquidatePosition(alice, address(btc), address(usdc), DataTypes.Side.SHORT);
        {
            PoolLens.PoolAsset memory asset = lens.poolAssets(address(usdc));

            assertEq(asset.reservedAmount, 0);
            // balance take all 1000$ collateral, minus 5$ liq fee sent to liquidator
            assertEq(asset.poolBalance, 11995000000, "balance not update after liquidate");
            console.log("feeReserve", asset.feeReserve);
            console.log("poolAmount", asset.poolAmount);
            assertEq(
                asset.poolAmount + asset.feeReserve, asset.poolBalance, "pool amount and pool balance miss matched"
            );
        }
        uint256 balance = usdc.balanceOf(bob);
        assertEq(balance, 5e6, "not transfer out liquidation fee"); // 5$ / 6190
        vm.stopPrank();
    }

    function test_swap() external {
        _beforeTestPosition();

        oracle.setPrice(address(usdc), 1e24);
        oracle.setPrice(address(btc), 20000e22);
        oracle.setPrice(address(weth), 1000e12);

        vm.prank(owner);
        liquidityCalculator.setFees(1e7, 1e7, 1e7, 1e7, 1e7);

        // target weight: 25 eth - 25 btc - 50 usdc
        vm.startPrank(alice);
        btc.approve(address(router), type(uint256).max);
        router.addLiquidity(tranche, address(btc), 1e8, 0, alice);
        usdc.approve(address(router), type(uint256).max);
        router.addLiquidity(tranche, address(usdc), 20000e6, 0, alice);
        // current weight: 0eth - 50btc - 50usdc

        {
            vm.expectRevert(abi.encodeWithSelector(IPool.ZeroAmount.selector));
            pool.swap(address(usdc), address(btc), 0, alice, new bytes(0));
        }

        {
            vm.expectRevert(); // SameTokenSwap
            pool.swap(address(btc), address(btc), 0, alice, new bytes(0));
        }

        {
            console.log("swap 1USDC to BTC");
            uint256 output = btc.balanceOf(alice);
            usdc.transfer(address(pool), 1e6);
            (uint256 amountOut,,,) = liquidityCalculator.calcSwapOutput(address(usdc), address(btc), 1e6);
            pool.swap(address(usdc), address(btc), 0, alice, new bytes(0));
            output = btc.balanceOf(alice) - output;
            assertEq(output, amountOut);
            assertEq(amountOut, 4995);
        }
        {
            console.log("swap 0.00005BTC to USDC");
            uint256 output = usdc.balanceOf(alice);
            btc.transfer(address(pool), 5000);
            (uint256 amountOut,,,) = liquidityCalculator.calcSwapOutput(address(btc), address(usdc), 5000);
            console.log("amountOut", amountOut);
            pool.swap(address(btc), address(usdc), 0, alice, new bytes(0));
            output = usdc.balanceOf(alice) - output;
            assertEq(output, amountOut);
            assertEq(output, 998000);
            console.log("price", output * 1e8 / 5000);
        }
        {
            /// swap a larger amount
            uint256 output = usdc.balanceOf(alice);
            btc.transfer(address(pool), 5e7);
            pool.swap(address(btc), address(usdc), 0, alice, new bytes(0));
            output = usdc.balanceOf(alice) - output;
            console.log("price", output * 1e8 / 5e7);
        }
        vm.stopPrank();
    }

    function test_set_max_global_short_size() public {
        _beforeTestPosition();

        vm.prank(eve);
        vm.expectRevert();
        pool.setMaxGlobalPositionSize(address(btc), 0, 1000e30);

        assertEq(pool.maxGlobalShortSizes(address(btc)), 0, "initial short size should be 0");
        vm.prank(owner);
        // vm.expectEmit(true, false, false, false);
        pool.setMaxGlobalPositionSize(address(btc), 0, 1000e30);
        assertEq(pool.maxGlobalShortSizes(address(btc)), 1000e30, "max short size not set properly");

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(IPool.NotApplicableForStableCoin.selector));
        pool.setMaxGlobalPositionSize(address(usdc), 0, 1000e30);
    }

    function test_max_global_short_size() external {
        vm.startPrank(owner);
        oracle.setPrice(address(usdc), 1e24);
        oracle.setPrice(address(btc), 20000e22);
        oracle.setPrice(address(weth), 1000e12);
        vm.stopPrank();
        vm.startPrank(alice);
        usdc.mint(10_000e6);
        usdc.approve(address(router), type(uint256).max);
        router.addLiquidity(tranche, address(usdc), 10_000e6, 0, alice);
        btc.mint(10e8);
        btc.approve(address(router), type(uint256).max);
        router.addLiquidity(tranche, address(btc), 10e8, 0, alice);
        vm.stopPrank();

        test_set_max_global_short_size();
        vm.prank(alice);
        usdc.transfer(address(pool), 100e6); // 100$
        vm.prank(orderManager);
        pool.increasePosition(alice, address(btc), address(usdc), 1_000e30, DataTypes.Side.SHORT);
        vm.prank(alice);
        usdc.transfer(address(pool), 100e6); // 100$
        vm.prank(orderManager);
        vm.expectRevert();
        pool.increasePosition(alice, address(btc), address(usdc), 1_000e30, DataTypes.Side.SHORT);
    }

    function test_max_global_long_size() external {
        vm.startPrank(owner);
        oracle.setPrice(address(usdc), 1e24);
        oracle.setPrice(address(btc), 20000e22);
        oracle.setPrice(address(weth), 1000e12);
        vm.stopPrank();
        vm.startPrank(alice);
        usdc.mint(1000e6);
        btc.mint(2e8);
        usdc.approve(address(router), type(uint256).max);
        btc.approve(address(router), type(uint256).max);
        router.addLiquidity(tranche, address(usdc), 1000e6, 0, alice);
        router.addLiquidity(tranche, address(btc), 1e8, 0, alice);
        vm.stopPrank();

        vm.prank(owner);
        pool.setMaxGlobalPositionSize(address(btc), 5e9, 0); // 50%

        vm.prank(alice);
        btc.transfer(address(pool), 1e6); // 0.01BTC
        vm.prank(orderManager);
        pool.increasePosition(alice, address(btc), address(btc), 2_000e30, DataTypes.Side.LONG);
        vm.prank(alice);
        btc.transfer(address(pool), 1e7); // 100$
        vm.prank(orderManager);
        vm.expectRevert();
        pool.increasePosition(alice, address(btc), address(btc), 10_000e30, DataTypes.Side.SHORT);
    }

    function test_vuln2() external {
        PoolLens.PoolAsset memory asset;
        _beforeTestPosition();

        vm.prank(owner);
        pool.setMaxGlobalPositionSize(address(btc), 5e9, 1000_000e30);

        oracle.setPrice(address(usdc), 1e24);
        oracle.setPrice(address(btc), 20000e22);
        oracle.setPrice(address(weth), 1000e12);

        vm.prank(owner);
        liquidityCalculator.setFees(1e7, 1e7, 1e7, 1e7, 1e7);

        vm.startPrank(alice);
        btc.approve(address(router), type(uint256).max);
        router.addLiquidity(tranche, address(btc), 105_000_000, 0, alice);
        usdc.approve(address(router), type(uint256).max);
        router.addLiquidity(tranche, address(usdc), 20000e6, 0, alice);
        vm.stopPrank();

        vm.warp(1000);

        // first open a long position with 1x leverage
        vm.startPrank(orderManager);
        btc.mint(1e8);
        btc.transfer(address(pool), 5e7);
        pool.increasePosition(alice, address(btc), address(btc), 10000e30, DataTypes.Side.LONG);
        vm.stopPrank();

        // PoolAsset memory asset = lens.poolAssets(address(pool), address(btc));
        // console.log(asset.poolAmount, asset.feeReserve, asset.reservedAmount, asset.poolBalance);

        vm.warp(1100);
        // swap as much as possible to get poolAmount close to reservedAmount
        vm.startPrank(alice);
        usdc.transfer(address(pool), 18000e6);
        pool.swap(address(usdc), address(btc), 0, alice, new bytes(0));
        vm.stopPrank();

        // asset = lens.poolAssets(address(pool), address(btc));
        // console.log(asset.poolAmount, asset.feeReserve, asset.reservedAmount, asset.poolBalance);

        oracle.setPrice(address(btc), 25000e22);
        // decreasePosition to decrease collateral without increasing size
        vm.expectRevert(IPool.InsufficientPoolAmount.selector);
        vm.startPrank(orderManager);
        pool.decreasePosition(alice, address(btc), address(btc), 4000e30, 0, DataTypes.Side.LONG, alice);
        vm.stopPrank();

        asset = lens.poolAssets(address(btc));
        console.log("poolAmount: ", asset.poolAmount);
        console.log("feeReserve: ", asset.feeReserve);
        console.log("reservedAmount: ", asset.reservedAmount);
        console.log("poolBalance: ", asset.poolBalance);

        // desired outcome
        assertTrue(asset.poolAmount > asset.reservedAmount);
    }
}
