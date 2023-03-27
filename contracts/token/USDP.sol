pragma solidity ^0.8.2;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "./YieldToken.sol";

contract USDP is YieldToken, Ownable {
    mapping(address => bool) public isVaults;

    event VaultChanged(address indexed vault, bool isVault);

    constructor() YieldToken("USD P", "USDP", 0) {}

    modifier onlyVault() {
        require(isVaults[msg.sender], "Caller is not a vault");
        _;
    }

    function mint(address _to, uint256 _amount) public onlyVault {
        _mint(_to, _amount);
    }

    function burn(address _from, uint256 _amount) public onlyVault {
        _burn(_from, _amount);
    }

    function addVault(address _vault) public onlyOwner {
        emit VaultChanged(_vault, true);
        isVaults[_vault] = true;
    }

    function removeVault(address _vault) public onlyOwner {
        emit VaultChanged(_vault, false);
        isVaults[_vault] = false;
    }
}
