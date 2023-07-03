// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Capped.sol";

contract POSI is ERC20Capped {
    address public immutable minter;

    modifier onlyMinter() {
        require(msg.sender == minter, "only minter");
        _;
    }

    constructor(
        address _minter,
        uint256 _cap
    ) ERC20("POSI", "POSI") ERC20Capped(_cap) {
        minter = _minter;
    }

    function mint(address to, uint256 amount) external onlyMinter {
        _mint(to, amount);
    }

    function burn(uint256 amount) external onlyMinter {
        _burn(_msgSender(), amount);
    }

    function burnFrom(address account, uint256 amount) external onlyMinter {
        _spendAllowance(account, _msgSender(), amount);
        _burn(account, amount);
    }
}
