//SPDX-License-Identifier: UNLCIENSED

pragma solidity >=0.8.0;

import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {TransparentUpgradeableProxy} from
"@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

/**
 * @dev THIS CONTRACT IS FOR TESTING PURPOSES ONLY.
 */
contract MockERC20 is ERC20Burnable {
    uint256 public constant INITIAL_SUPPLY = 100_000 ether;
    uint256 public constant EMITTED_PER_SECONDS = 0.1 ether;

    uint256 public lastMintTime;
    uint8 internal decimals_;

    constructor(string memory _name, string memory _symbol, uint8 _decimals) ERC20(_name, _symbol) {
        decimals_ = _decimals;
        lastMintTime = block.timestamp;
        _mint(msg.sender, INITIAL_SUPPLY);
    }

    function availableToMint() public view returns (uint256) {
        if (block.timestamp <= lastMintTime) {
            return 0;
        }
        return (block.timestamp - lastMintTime) * EMITTED_PER_SECONDS;
    }

    function mint(uint256 _amount) public {
        // require(_amount <= availableToMint(), "!availableToMint");
        _mint(msg.sender, _amount);
        lastMintTime = block.timestamp;
    }

    function mintTo(uint256 _amount, address _to) public {
        // require(_amount <= availableToMint(), "!availableToMint");
        _mint(_to, _amount);
        lastMintTime = block.timestamp;
    }

    function decimals() public view virtual override returns (uint8) {
        return decimals_;
    }
}
