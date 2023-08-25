pragma solidity 0.8.18;

import "forge-std/Test.sol";
import "contracts/oracle/Oracle.sol";
import "contracts/interfaces/AggregatorV3Interface.sol";
import "../mocks/MockERC20.t.sol";

contract OracleTest is Test {
    Oracle oracle;
    address token;
    address sequence;
    address chainlink = address(bytes20("token_price_feed"));
    address reporter = address(bytes20("reporter"));
    address owner = address(bytes20("owner"));

    function setUp() external {
        vm.startPrank(owner);
        oracle = new Oracle();
        token = address(new MockERC20("token", "tk", 18));
        sequence = address(oracle.sequencerUptimeFeed());
        oracle.configToken(token, 18, chainlink, 8, 3600, 500);
        oracle.addReporter(reporter);
        vm.stopPrank();
    }

    function test_only_owner_can_add_reporter() external {
        address reporter2 = address(bytes20("reporter2"));
        vm.prank(reporter);
        vm.expectRevert("Ownable: caller is not the owner");
        oracle.addReporter(reporter2);
    }

    function test_sequence_down() external {
        vm.warp(1_000_000);
        vm.mockCall(
            sequence,
            0,
            abi.encodeWithSelector(AggregatorV3Interface.latestRoundData.selector),
            abi.encode(uint80(1), int256(1), uint256(1_00_000), uint256(1_00_000), uint80(1))
        );

        vm.expectRevert(Oracle.SequencerDown.selector);
        oracle.getPrice(token, true);
    }

    function test_successs() external {
        vm.warp(1_000_000);
        vm.mockCall(
            sequence,
            0,
            abi.encodeWithSelector(AggregatorV3Interface.latestRoundData.selector),
            abi.encode(uint80(1), int256(0), uint256(1_00_000), uint256(1_00_000), uint80(1))
        );
        vm.mockCall(
            chainlink,
            0,
            abi.encodeWithSelector(AggregatorV3Interface.latestRoundData.selector),
            abi.encode(uint80(1), int256(1e8), uint256(1_000_000), uint256(1_000_000), uint80(1))
        );

        uint256 price = oracle.getPrice(token, true);
        console.log("price", price);
    }

    function test_sequence_up_price_feed_down() external {
        uint256 _now = 1_000_000;
        uint256 chainlinkLastTime = _now - 1 days;
        vm.warp(_now);
        vm.mockCall(
            sequence,
            0,
            abi.encodeWithSelector(AggregatorV3Interface.latestRoundData.selector),
            abi.encode(uint80(1), int256(0), uint256(1_00_000), uint256(1_00_000), uint80(1))
        );
        vm.mockCall(
            chainlink,
            0,
            abi.encodeWithSelector(AggregatorV3Interface.latestRoundData.selector),
            abi.encode(uint80(1), int256(1e8), uint256(1_000_000), uint256(chainlinkLastTime), uint80(1))
        );

        vm.expectRevert(Oracle.ChainlinkStaled.selector);
        oracle.getPrice(token, true);
    }

    function postPrices(address _token, uint256 _price, uint256 _timeStamp) internal {
        address[] memory tokens = new address[](1);
        tokens[0] = _token;
        uint256[] memory prices = new uint[](1);
        prices[0] = _price;
        uint256[] memory timeStamps = new uint[](1);
        timeStamps[0] = _timeStamp;
        vm.prank(reporter);
        oracle.postPrices(tokens, prices, timeStamps);
    }

    function test_reporter_not_report() external {
        uint256 _now = 1_000_000;
        uint256 chainlinkLastTime = _now - 1 minutes;

        vm.warp(_now - 6 minutes);
        postPrices(token, 900_000, _now - 6 minutes);

        vm.warp(_now);
        vm.mockCall(
            sequence,
            0,
            abi.encodeWithSelector(AggregatorV3Interface.latestRoundData.selector),
            abi.encode(uint80(1), int256(0), uint256(1_00_000), uint256(1_00_000), uint80(1))
        );
        vm.mockCall(
            chainlink,
            0,
            abi.encodeWithSelector(AggregatorV3Interface.latestRoundData.selector),
            abi.encode(uint80(1), int256(1e8), uint256(1_000_000), uint256(chainlinkLastTime), uint80(1))
        );

        uint256 price = oracle.getPrice(token, true);
        assertEq(price, 1002000000000, "should be 0.2% higher than chainlink price");
    }

    function test_reporter_price_out_of_protect_range() external {
        uint256 _now = 1_000_000;
        uint256 chainlinkLastTime = _now - 1 minutes;

        vm.warp(_now);
        vm.mockCall(
            sequence,
            0,
            abi.encodeWithSelector(AggregatorV3Interface.latestRoundData.selector),
            abi.encode(uint80(1), int256(0), uint256(1_00_000), uint256(1_00_000), uint80(1))
        );
        // chainlink price = 1, allowed band = 1.0005 - 0.9995
        vm.mockCall(
            chainlink,
            0,
            abi.encodeWithSelector(AggregatorV3Interface.latestRoundData.selector),
            abi.encode(uint80(1), int256(1e8), uint256(100_000_000), uint256(chainlinkLastTime), uint80(1))
        );

        {
            // keeper price too low
            postPrices(token, 99940000, _now);
            uint256 maxPrice = oracle.getPrice(token, true);
            uint256 minPrice = oracle.getPrice(token, false);

            console.log(minPrice, maxPrice);
            assertEq(minPrice, 999400000000, "should be keeper price");
            assertEq(maxPrice, 1000000000000, "should be chainlink price");
        }
        {
            // keeper price too high
            vm.warp(_now + 1);
            postPrices(token, 100050001, _now + 1);
            uint256 maxPrice = oracle.getPrice(token, true);
            uint256 minPrice = oracle.getPrice(token, false);

            console.log(minPrice, maxPrice);
            assertEq(minPrice, 1e12, "should be chainlink price");
            assertEq(maxPrice, 1000500010000, "should be keeper price");
        }
        {
            // keeper price too damn high
            vm.warp(_now + 2);
            postPrices(token, 100150001, _now + 2);
            uint256 maxPrice = oracle.getPrice(token, true);
            uint256 minPrice = oracle.getPrice(token, false);

            console.log(minPrice, maxPrice);
            assertEq(minPrice, 1e12, "should be chainlink price");
            assertEq(maxPrice, 1001500000000, "should be keeper price");
        }
    }
}
