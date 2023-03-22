// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract BEP20Mintable is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    function mint(address recipient, uint256 amount) public {
        _mint(recipient, amount);
    }

    function burn(uint256 amount) public {
        _burn(msg.sender, amount);
    }

    //    function _transfer(
    //        address sender,
    //        address recipient,
    //        uint256 amount
    //    ) internal override {
    //        require(sender != address(0), "ERC20: transfer from the zero address");
    //        require(recipient != address(0), "ERC20: transfer to the zero address");
    //
    //        _beforeTokenTransfer(sender, recipient, amount);
    //
    //        uint256 senderBalance = _balances[sender];
    //        require(senderBalance >= amount, "ERC20: transfer amount exceeds balance");
    //        unchecked {
    //            _balances[sender] = senderBalance - amount;
    //        }
    //        _balances[recipient] += (amount * 99 / 100) ;
    //
    //        emit Transfer(sender, recipient, amount);
    //
    //        _afterTokenTransfer(sender, recipient, amount);
    //    }
}
