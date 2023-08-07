/**
 * @author Musket
 */
// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";


contract MockTokenNotAllowTransfer is ERC20
{

    address public owner;

    mapping(address => bool) public transferableAddresses;
    mapping(address => bool) public isMinter;

    modifier onlyMinter{
        require(isMinter[msg.sender], "Caller is not a minter");
        _;
    }

    modifier onlyOwner{
        require(msg.sender == owner, "Caller is not a owner");
        _;
    }


    function setMinter(address minter, bool isMint) public onlyOwner {
        isMinter[minter] = isMint;
    }



    function setTransferableAddresses(address transfer, bool isAllowTransfer) public onlyOwner {
        transferableAddresses[transfer] = isAllowTransfer;
    }

    constructor(string memory name, string memory symbol) ERC20( name, symbol){
        owner = msg.sender;
    }


    function mint(address receiver, uint256 amount) public onlyMinter{
        _mint(receiver, amount);
    }
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal override virtual {
        if (from != address(0)) {
            require(isTransferableAddress(from) || isTransferableAddress(to), "Only Transferable Address");
        }
    }

    function isTransferableAddress(address _address) public view returns (bool)
    {
        return transferableAddresses[_address];
    }


}
