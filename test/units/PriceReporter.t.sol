pragma solidity 0.8.18;

import "forge-std/Test.sol";
import "contracts/oracle/PriceReporter.sol";
import "contracts/interfaces/IOrderManager.sol";
import "contracts/interfaces/IOracle.sol";

contract PriceReporterTest is Test {
    address keeper = address(bytes20("keeper"));
    address oracle = address(bytes20("oracle"));
    address orderManager = address(bytes20("orderManager"));
    address owner = address(bytes20("owner"));
    address eve = address(bytes20("eve"));

    PriceReporter reporter;

    function setUp() external {
        vm.startPrank(owner);
        reporter = new PriceReporter(oracle, orderManager);
        reporter.addReporter(keeper);
        vm.stopPrank();
    }

    function test_only_owner_can_add_reporter() external {
        vm.prank(eve);
        vm.expectRevert("Ownable: caller is not the owner");
        reporter.addReporter(eve);
    }

    function test_keeper_can_report() external {
        address[] memory tokens = new address[](0);
        uint256[] memory prices = new uint[](0);
        uint256[] memory leverageOrders = new uint[](0);
        uint256[] memory swapOrders = new uint[](0);

        vm.mockCall(orderManager, abi.encodeWithSelector(IOrderManager.executeSwapOrder.selector), new bytes(0));
        vm.mockCall(oracle, abi.encodeWithSelector(IPriceFeed.postPrices.selector), new bytes(0));
        vm.prank(keeper);
        reporter.postPriceAndExecuteOrders(tokens, prices, leverageOrders, swapOrders);

        vm.prank(eve);
        vm.expectRevert(bytes("PriceReporter:unauthorized"));
        reporter.postPriceAndExecuteOrders(tokens, prices, leverageOrders, swapOrders);
    }
}
