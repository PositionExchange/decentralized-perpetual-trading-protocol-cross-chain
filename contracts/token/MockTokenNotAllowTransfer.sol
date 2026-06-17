/**
 * @author Musket
 */
// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.9;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

contract MockTokenNotAllowTransfer is ERC20Upgradeable {
    address public owner;
    uint8 _decimals;

    mapping(address => bool) public transferableAddresses;
    mapping(address => bool) public isMinter;

    modifier onlyMinter() {
        require(isMinter[msg.sender], "Caller is not a minter");
        _;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Caller is not a owner");
        _;
    }

    function initialize(
        uint256 _initialAmount,
        string memory name,
        string memory symbol,
        uint8 decimal
    ) public initializer {
        _mint(msg.sender, _initialAmount);
        owner = msg.sender;
        __ERC20_init(name, symbol);
        _decimals = decimal;
    }

    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }

    function setMinter(address minter, bool isMint) public onlyOwner {
        isMinter[minter] = isMint;
    }

    function setTransferableAddresses(
        address transfer,
        bool isAllowTransfer
    ) public onlyOwner {
        transferableAddresses[transfer] = isAllowTransfer;
    }

    function mint(address receiver, uint256 amount) public onlyMinter {
        _mint(receiver, amount);
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual override {
        if (from != address(0)) {
            require(
                isTransferableAddress(from) || isTransferableAddress(to),
                "Only Transferable Address"
            );
        }
    }

    function isTransferableAddress(
        address _address
    ) public view returns (bool) {
        return transferableAddresses[_address];
    }
}
