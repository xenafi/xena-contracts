pragma solidity 0.8.18;

import "forge-std/Test.sol";

import {TransparentUpgradeableProxy as Proxy} from
    "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {Pool} from "contracts/pool/Pool.sol";
import {Constants} from "contracts/lib/Constants.sol";
import {PoolLens} from "contracts/lens/PoolLens.sol";
import {DataTypes} from "contracts/lib/DataTypes.sol";
import {MockOracle} from "../mocks/MockOracle.t.sol";
import {MockERC20} from "../mocks/MockERC20.t.sol";
import {WETH9} from "../mocks/WETH.t.sol";
import {ILPToken} from "contracts/interfaces/ILPToken.sol";
import {IPool} from "contracts/interfaces/IPool.sol";
import {IOracle} from "contracts/interfaces/IOracle.sol";
import {LiquidityCalculator} from "contracts/pool/LiquidityCalculator.sol";
import {LiquidityRouter} from "contracts/utils/LiquidityRouter.sol";
import {SimpleInterestRateModel} from "contracts/interest/SimpleInterestRateModel.sol";

address constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
uint256 constant PRECISION = 1e10; // 50%
uint256 constant MAX_TRANCHES = 3;
uint256 constant SWAP_FEE = 2e7; // 0.2%
uint256 constant ADD_REMOVE_FEE = 1e7; // 0.1%
uint256 constant POSITION_FEE = 1e7; // 0.1%
uint256 constant DAO_FEE = 5e9; // 50%

struct PoolTokenInfo {
    uint256 poolBalance;
    uint256 feeReserve;
}

contract TestPool is Pool {
    constructor() {}

    function getTrancheAsset(address tranche, address token) external view returns (DataTypes.AssetInfo memory) {
        return trancheAssets[tranche][token];
    }

    function tranchePoolBalance(address token, address tranche) external view returns (uint256) {
        return trancheAssets[tranche][token].poolAmount;
    }

    function getPoolTokenInfo(address token) external view returns (PoolTokenInfo memory) {
        return PoolTokenInfo({poolBalance: poolBalances[token], feeReserve: feeReserves[token]});
    }

    function getTrancheValue(address _tranche, bool _max) external view returns (uint256) {
        return liquidityCalculator.getTrancheValue(_tranche, _max);
    }
}

abstract contract Fixture is Test {
    address public owner = 0x2E20CFb2f7f98Eb5c9FD31Df41620872C0aef524;
    address public orderManager = 0x69D4aDe841175fE72642D03D82417215D4f47790;
    address public alice = 0xfC067b2BE205F8e8C85aC653f64C52baa225aCa4;
    address public bob = 0x90FbB788b18241a4bBAb4cd5eb839a42FF59D235;
    address public eve = 0x462beDFDAFD8681827bf8E91Ce27914cb00CcF83;
    WETH9 public weth = WETH9(payable(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1));

    MockERC20 public btc;
    MockERC20 public usdc;
    MockERC20 public busd;
    MockOracle oracle;
    PoolLens lens;

    function build() internal virtual {
        vm.startPrank(owner);
        btc = new MockERC20("WBTC", "WBTC", 8);
        usdc = new MockERC20("USDC", "USDC", 6);
        busd = new MockERC20("BUSD", "BUSD", 18);
        oracle = new MockOracle();
        vm.stopPrank();

        WETH9 impl = new WETH9();
        vm.etch(address(weth), address(impl).code);
    }
}

abstract contract PoolTestFixture is Fixture {
    TestPool public pool;
    LiquidityCalculator liquidityCalculator;
    LiquidityRouter router;

    function build() internal override {
        Fixture.build();

        vm.startPrank(owner);
        TestPool poolImpl = new TestPool();
        ProxyAdmin admin = new ProxyAdmin();
        Proxy proxy = new Proxy(address(poolImpl), address(admin), new bytes(0));
        pool = TestPool(address(proxy));
        lens = new PoolLens(address(pool));
        pool.initialize(
            20, // max leverage | 20x
            1e8, // maintenance margin
            100
        );
        liquidityCalculator = new LiquidityCalculator(address(proxy), 3e7, 3e7, 1e7, 1e7, 2e7);

        pool.setPositionFee(POSITION_FEE, 5e30);

        pool.setOrderManager(orderManager);
        pool.setOracle(address(oracle));
        pool.setLiquidityCalculator(address(liquidityCalculator));
        pool.addToken(address(weth), false);
        pool.addToken(address(btc), false);
        pool.addToken(address(usdc), true);

        SimpleInterestRateModel irModel = new SimpleInterestRateModel(1e6);
        pool.setInterestRateModel(address(weth), address(irModel));
        pool.setInterestRateModel(address(btc), address(irModel));
        pool.setInterestRateModel(address(usdc), address(irModel));

        IPool.TokenWeight[] memory config = new IPool.TokenWeight[](3);
        config[0] = IPool.TokenWeight({token: address(btc), weight: 1000});
        config[1] = IPool.TokenWeight({token: address(weth), weight: 1000});
        config[2] = IPool.TokenWeight({token: address(usdc), weight: 2000});

        pool.setTargetWeight(config);
        router = new LiquidityRouter(address(pool));
        pool.unpause();
        vm.stopPrank();
    }

    function _checkInvariant(address _token) internal {
        PoolLens.PoolAsset memory asset = lens.poolAssets(_token);
        assertApproxEqAbs(
            asset.poolAmount + asset.feeReserve,
            asset.poolBalance,
            1,
            "invariant: poolAmount + feeReserve ~ poolBalance"
        );
    }
}
