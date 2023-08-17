pragma solidity 0.8.18;

import "forge-std/Test.sol";
import "contracts/tokens/LPToken.sol";

contract LpTokenTest is Test {
    event Transfer(address indexed from, address indexed to, uint256 amount);

    function test_can_mint_by_minter_only() external {
        address minter = address(bytes20("minter"));
        address eve = address(bytes20("eve"));

        LPToken token = new LPToken("LP1", "LP1", minter);

        vm.expectEmit();
        emit Transfer(address(0), minter, 1 ether);
        vm.prank(minter);
        token.mint(minter, 1 ether);

        vm.expectRevert(LPToken.OnlyMinter.selector);
        vm.prank(eve);
        token.mint(eve, 1 ether);
    }
}
