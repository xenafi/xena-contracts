pragma solidity 0.8.18;

import "forge-std/console.sol";
import {PoolTestFixture} from "./Fixture.t.sol";
import {LPToken} from "contracts/tokens/LPToken.sol";
import {PoolLens} from "contracts/lens/PoolLens.sol";
import {Pool} from "contracts/pool/Pool.sol";
import {IPool} from "contracts/interfaces/IPool.sol";
import {MathUtils} from "contracts/lib/MathUtils.sol";
import {DataTypes} from "contracts/lib/DataTypes.sol";

contract MultipleTranchesTest is PoolTestFixture {
    LPToken tranche_1;
    LPToken tranche_2;
    LPToken tranche_3;

    function setUp() external {
        build();
        vm.startPrank(owner);
        /// unset fee
        liquidityCalculator.setFees(0, 0, 0, 0, 0);
        pool.setPositionFee(0, 0);
        tranche_1 = new LPToken("1", "1", address(pool));
        tranche_2 = new LPToken("2", "2", address(pool));
        tranche_3 = new LPToken("3", "3", address(pool));
        pool.addTranche(address(tranche_1));
        pool.addTranche(address(tranche_2));
        pool.addTranche(address(tranche_3));

        IPool.RiskConfig[] memory config = new IPool.RiskConfig[](3);
        config[0] = IPool.RiskConfig(address(tranche_1), 70);
        config[1] = IPool.RiskConfig(address(tranche_2), 20);
        config[2] = IPool.RiskConfig(address(tranche_3), 10);

        pool.setRiskFactor(address(btc), config);
        // pool.setRiskFactor(address(usdc), config);
        pool.setRiskFactor(address(weth), config);

        vm.stopPrank();

        vm.startPrank(alice);
        btc.mint(100e8);
        usdc.mint(1_000_000e6);
        btc.approve(address(pool), type(uint256).max);
        usdc.approve(address(pool), type(uint256).max);
        weth.approve(address(pool), type(uint256).max);
        vm.stopPrank();
        vm.deal(alice, 1000e18);
    }

    /// @notice add and remove liquidity to different tranches
    function test_liquidity() external {
        vm.startPrank(alice);
        uint256 priorBalance;
        uint256 lpAmount;
        oracle.setPrice(address(btc), 20_000e22);
        oracle.setPrice(address(usdc), 1e24);
        oracle.setPrice(address(weth), 1000e12);

        // add 1BTC to tranche 1 to receive 20k LP1
        priorBalance = tranche_1.balanceOf(alice);
        pool.addLiquidity(address(tranche_1), address(btc), 1e8, 0, alice);
        lpAmount = tranche_1.balanceOf(alice) - priorBalance;
        assertEq(lpAmount, 20_000e18);

        {
            assertEq(pool.tranchePoolBalance(address(btc), address(tranche_1)), 1e8, "tranche 1 balance not update");
            assertEq(
                pool.tranchePoolBalance(address(usdc), address(tranche_1)),
                0,
                "tranche 1: other token should not change"
            );
        }

        // add 2BTC to tranche 2 to receive 40k LP2
        priorBalance = tranche_2.balanceOf(alice);
        pool.addLiquidity(address(tranche_2), address(btc), 2e8, 0, alice);
        lpAmount = tranche_2.balanceOf(alice) - priorBalance;
        assertEq(lpAmount, 40_000e18);

        {
            assertEq(pool.tranchePoolBalance(address(btc), address(tranche_2)), 2e8, "tranche 2 balance not update");
        }

        // add 10000usdc to tranche 3 to receive 10k LP3
        priorBalance = tranche_3.balanceOf(alice);
        pool.addLiquidity(address(tranche_3), address(usdc), 10_000e6, 0, alice);
        lpAmount = tranche_3.balanceOf(alice) - priorBalance;
        assertEq(lpAmount, 10_000e18);

        {
            assertEq(
                pool.tranchePoolBalance(address(usdc), address(tranche_3)), 10000e6, "tranche 3 usdc balance not update"
            );
        }

        // add 1BTC more to tranche 3 to receive 20k LP1
        priorBalance = tranche_3.balanceOf(alice);
        pool.addLiquidity(address(tranche_3), address(btc), 1e8, 0, alice);
        lpAmount = tranche_3.balanceOf(alice) - priorBalance;
        {
            uint256 lpPrice = lens.getLpPrice(address(tranche_3));
            console.log("lp price", lpPrice);
            uint256 balanceInTranche = pool.tranchePoolBalance(address(btc), address(tranche_3));
            assertEq(balanceInTranche, 1e8, "tranche 3 should has 1BTC");
        }

        priorBalance = tranche_3.balanceOf(alice);
        pool.addLiquidity(address(tranche_3), address(usdc), 100e6, 0, alice);
        lpAmount = tranche_3.balanceOf(alice) - priorBalance;
        assertEq(lpAmount, 100e18);

        // remove liquidity
        priorBalance = tranche_1.balanceOf(alice);
        uint256 btcBalance = btc.balanceOf(alice);
        tranche_1.approve(address(pool), type(uint256).max);
        pool.removeLiquidity(address(tranche_1), address(btc), 100e18, 0, alice);
        lpAmount = priorBalance - tranche_1.balanceOf(alice);
        btcBalance = btc.balanceOf(alice) - btcBalance;
        assertEq(lpAmount, 100e18);
        assertEq(btcBalance, 5e5);
        vm.stopPrank();
    }

    function test_lp_price_with_positions() external {
        // unset fee to simply the calculation
        vm.prank(owner);
        pool.setPositionFee(0, 0);
        vm.startPrank(alice);
        oracle.setPrice(address(btc), 20_000e22);
        oracle.setPrice(address(usdc), 1e24);
        oracle.setPrice(address(weth), 1000e12);
        // add some init liquidity
        pool.addLiquidity(address(tranche_1), address(btc), 1e8, 0, alice);
        weth.deposit{value: 20 ether}();
        pool.addLiquidity(address(tranche_1), address(weth), 20 ether, 0, alice);
        pool.addLiquidity(address(tranche_1), address(usdc), 40_000e6, 0, alice);

        {
            assertEq(pool.getTrancheAsset(address(tranche_1), address(btc)).poolAmount, 1e8);
            assertEq(pool.getTrancheAsset(address(tranche_1), address(usdc)).poolAmount, 40_000e6);
            assertEq(pool.getTrancheValue(address(tranche_1), true), 80_000e30, "tranche value not match");
        }

        pool.addLiquidity(address(tranche_2), address(btc), 1e8, 0, alice);
        weth.deposit{value: 20 ether}();
        pool.addLiquidity(address(tranche_2), address(weth), 20 ether, 0, alice);
        pool.addLiquidity(address(tranche_2), address(usdc), 40_000e6, 0, alice);

        pool.addLiquidity(address(tranche_3), address(btc), 1e8, 0, alice);
        weth.deposit{value: 20 ether}();
        pool.addLiquidity(address(tranche_3), address(weth), 20 ether, 0, alice);
        pool.addLiquidity(address(tranche_3), address(usdc), 40_000e6, 0, alice);
        // total pool value should be 240k
        // assertEq(pool.getPoolValue(true), 240_000e30, "Pool value not match");

        btc.transfer(address(pool), 1e7);
        vm.stopPrank();

        vm.prank(orderManager);
        // try to open 10x long BTC @ 20k
        pool.increasePosition(alice, address(btc), address(btc), 20_000e30, DataTypes.Side.LONG);

        // then set price to 20500
        oracle.setPrice(address(btc), 20_500e22);
        PoolLens.PositionView memory position = lens.getPosition(alice, address(btc), address(btc), DataTypes.Side.LONG);
        console.log("Pnl", position.hasProfit, position.pnl);

        assertEq(lens.getLpPrice(address(tranche_1)), 1002312500000, "LP price is wrong");
    }

    function test_distribute_pnl() external {
        // unset fee to simply the calculation
        vm.prank(owner);
        pool.setPositionFee(0, 0);
        vm.startPrank(alice);
        oracle.setPrice(address(btc), 20_000e22);
        oracle.setPrice(address(usdc), 1e24);
        oracle.setPrice(address(weth), 1000e12);
        // add some init liquidity
        pool.addLiquidity(address(tranche_1), address(btc), 1e8, 0, alice);
        weth.deposit{value: 20 ether}();
        pool.addLiquidity(address(tranche_1), address(weth), 20 ether, 0, alice);
        pool.addLiquidity(address(tranche_1), address(usdc), 40_000e6, 0, alice);

        pool.addLiquidity(address(tranche_2), address(btc), 1e8, 0, alice);
        weth.deposit{value: 20 ether}();
        pool.addLiquidity(address(tranche_2), address(weth), 20 ether, 0, alice);
        pool.addLiquidity(address(tranche_2), address(usdc), 40_000e6, 0, alice);

        pool.addLiquidity(address(tranche_3), address(btc), 1e8, 0, alice);
        weth.deposit{value: 20 ether}();
        pool.addLiquidity(address(tranche_3), address(weth), 20 ether, 0, alice);
        pool.addLiquidity(address(tranche_3), address(usdc), 40_000e6, 0, alice);
        // total pool value should be 240k
        // assertEq(pool.getPoolValue(true), 240_000e30, "Pool value not match");
        assertEq(pool.getTrancheValue(address(tranche_1), true), 80_000e30, "tranche value not match");

        btc.transfer(address(pool), 1e7);
        vm.stopPrank();

        vm.prank(orderManager);
        // try to open 10x long BTC @ 20k
        pool.increasePosition(alice, address(btc), address(btc), 20_000e30, DataTypes.Side.LONG);

        // then set price to 20500
        oracle.setPrice(address(btc), 20_500e22);
        PoolLens.PositionView memory position = lens.getPosition(alice, address(btc), address(btc), DataTypes.Side.LONG);
        console.log("Pnl", position.hasProfit, position.pnl);
        uint256 estimatedLpPrice = lens.getLpPrice(address(tranche_1));

        uint256 btcAmount = btc.balanceOf(alice);
        vm.prank(orderManager);
        // pay 2000$ collateral + 500$ profit = 0.12195121
        pool.decreasePosition(alice, address(btc), address(btc), 2_000e30, 20_000e30, DataTypes.Side.LONG, alice);
        btcAmount = btc.balanceOf(alice) - btcAmount;

        console.log("tranche 1 BTC balance", pool.tranchePoolBalance(address(btc), address(tranche_1)));
        console.log("tranche 1 value", pool.getTrancheValue(address(tranche_1), true));
        assertEq(
            lens.poolAssets(address(btc)).guaranteedValue, 0, "guaranteed value not reset when close all positions"
        );
        assertEq(btcAmount, 12195121, "payout amount not correct");

        assertTrue(
            MathUtils.diff(lens.getLpPrice(address(tranche_1)), estimatedLpPrice) < 1e6,
            "LP price should remain as estimated"
        );

        vm.prank(owner);
        pool.rebalanceAsset(address(tranche_3), address(btc), 1e3, address(tranche_2), address(usdc));
    }

    function test_add_liquidity_after_open_position() external {
        // unset fee to simply the calculation
        vm.prank(owner);
        pool.setPositionFee(0, 0);
        vm.startPrank(alice);
        oracle.setPrice(address(btc), 20_000e22);
        oracle.setPrice(address(usdc), 1e24);
        oracle.setPrice(address(weth), 1000e12);
        // add some init liquidity
        pool.addLiquidity(address(tranche_1), address(btc), 1e8, 0, alice);
        weth.deposit{value: 20 ether}();
        pool.addLiquidity(address(tranche_1), address(weth), 20 ether, 0, alice);
        pool.addLiquidity(address(tranche_1), address(usdc), 40_000e6, 0, alice);

        btc.transfer(address(pool), 1e7);
        vm.stopPrank();

        vm.prank(orderManager);
        // try to open 10x long BTC @ 20k
        pool.increasePosition(alice, address(btc), address(btc), 20_000e30, DataTypes.Side.LONG);

        // then set price to 20500
        oracle.setPrice(address(btc), 20_500e22);

        vm.startPrank(alice);
        pool.addLiquidity(address(tranche_2), address(btc), 1e8, 0, alice);
    }

    function test_remove_liquidity_after_pnl_realized() external {
        // unset fee to simply the calculation
        vm.prank(owner);
        pool.setPositionFee(0, 0);
        vm.startPrank(alice);
        oracle.setPrice(address(btc), 20_000e22);
        oracle.setPrice(address(usdc), 1e24);
        oracle.setPrice(address(weth), 1000e12);
        // add some init liquidity
        pool.addLiquidity(address(tranche_1), address(usdc), 20_000e6, 0, alice);
        pool.addLiquidity(address(tranche_2), address(usdc), 20_000e6, 0, alice);
        pool.addLiquidity(address(tranche_3), address(usdc), 20_000e6, 0, alice);
        pool.addLiquidity(address(tranche_1), address(btc), 10e8, 0, alice);
        pool.addLiquidity(address(tranche_2), address(btc), 10e8, 0, alice);
        pool.addLiquidity(address(tranche_3), address(btc), 10e8, 0, alice);

        usdc.transfer(address(pool), 2_000e6);
        vm.stopPrank();

        vm.prank(orderManager);
        // try to open 10x long BTC @ 20k
        pool.increasePosition(alice, address(btc), address(usdc), 20_000e30, DataTypes.Side.SHORT);

        // then set price to 19500
        oracle.setPrice(address(btc), 19_500e22);
        uint256 usdcb4 = usdc.balanceOf(alice);
        vm.prank(orderManager);
        pool.decreasePosition(alice, address(btc), address(usdc), 2000e6, 20_000e30, DataTypes.Side.SHORT, alice);
        console.log("payout", usdc.balanceOf(alice) - usdcb4);

        console.log(pool.getTrancheValue(address(tranche_1), true));
    }

    function test_swap() external {
        vm.prank(owner);
        liquidityCalculator.setFees(3e7, 3e7, 1e7, 1e7, 2e7);
        oracle.setPrice(address(btc), 20_000e22);
        oracle.setPrice(address(usdc), 1e24);
        oracle.setPrice(address(weth), 1000e12);

        vm.startPrank(alice);
        pool.addLiquidity(address(tranche_1), address(usdc), 10e6, 0, alice);
        pool.addLiquidity(address(tranche_2), address(usdc), 2_000e6, 0, alice);
        pool.addLiquidity(address(tranche_3), address(usdc), 100e6, 0, alice);
        pool.addLiquidity(address(tranche_1), address(btc), 1e8, 0, alice);
        pool.addLiquidity(address(tranche_2), address(btc), 1e7, 0, alice);
        pool.addLiquidity(address(tranche_3), address(btc), 1e6, 0, alice);

        uint256 usdcBalance = usdc.balanceOf(alice);
        btc.transfer(address(pool), 1e5);
        pool.swap(address(btc), address(usdc), 0, alice, new bytes(0));
        console.log("output", usdc.balanceOf(alice) - usdcBalance);
    }

    function test_can_close_long_position_when_tranche_ratio_miss_match() external {
        vm.prank(owner);
        pool.setPositionFee(0, 0);
        vm.prank(bob);
        btc.mint(1e8);

        vm.startPrank(alice);

        // uint256 aliceBTCBalance = btc.balanceOf(alice);
        // uint256 bolBTCBalance = btc.balanceOf(bob);

        uint256 oldBTCPrice = 20_000e22;
        oracle.setPrice(address(btc), oldBTCPrice); // 20k
        oracle.setPrice(address(usdc), 1e24); // 1$
        oracle.setPrice(address(weth), 1000e12); // 1k

        // Add 1 BTC to 3 tranche
        pool.addLiquidity(address(tranche_1), address(btc), 11e7, 0, alice); // 1.1 BTC = 22.000$
        pool.addLiquidity(address(tranche_2), address(btc), 1e7, 0, alice); // 0.1 BTC = 2.000$
        pool.addLiquidity(address(tranche_3), address(btc), 1e7, 0, alice); // 0.1 BTC = 2.000$

        // Check pool value
        // assertEq(pool.getPoolValue(true), 26_000e30);
        assertEq(pool.getTrancheValue(address(tranche_1), true), 22_000e30, "wrong pool value ");
        vm.stopPrank();

        // Bob transfer 0.1 BTC
        vm.prank(bob);
        btc.transfer(address(pool), 1e7); // 0.1 BTC

        // Long 1 BTC 10x @20k
        vm.prank(orderManager);
        pool.increasePosition(bob, address(btc), address(btc), 20_000e30, DataTypes.Side.LONG); // Value 1 BTC

        // Update BTC price to 20k5
        uint256 newBTCPrice = 20_500e22;
        oracle.setPrice(address(btc), newBTCPrice);

        // Check BTC loss
        PoolLens.PositionView memory position = lens.getPosition(bob, address(btc), address(btc), DataTypes.Side.LONG);
        uint256 poolLost = (((2_000e30 + 500e30) / newBTCPrice) - 1e7);
        console.log("poolLost", poolLost, position.pnl);

        // Close long BTC @20.5k
        vm.prank(orderManager);
        pool.decreasePosition(bob, address(btc), address(btc), 2_000e30, 20_000e30, DataTypes.Side.LONG, bob);
    }
}
