pragma solidity 0.8.18;

import "forge-std/Test.sol";
import "contracts/utils/ETHUnwrapper.sol";
import "../mocks/WETH.t.sol";

contract Receiver {
    uint256 a;

    receive() external payable {
        // consume some gas
        a++;
    }
}

contract ETHUnwrapperTest is Test {
    ETHUnwrapper sut;
    WETH9 weth;
    Receiver receiver;

    function setUp() external {
        weth = new WETH9();
        sut = new ETHUnwrapper(address(weth));
        receiver = new Receiver();
    }

    /**
     * sent ETH to contract require more than default transfer gas limit
     */
    function test_unwrap_weth_to_contract() external {
        address alice = address(bytes20("alice"));
        vm.deal(alice, 10 ether);
        vm.startPrank(alice);
        weth.deposit{value: 10 ether}();

        assertEq(weth.balanceOf(alice), 10 ether);
        weth.approve(address(sut), 10 ether);

        uint256 before = address(receiver).balance;
        sut.unwrap(10 ether, address(receiver));
        uint256 receivedAmount = address(receiver).balance - before;
        assertEq(receivedAmount, 10 ether);
    }
}
