pragma solidity ^0.8.2;

interface IUSDP {
    function mint(address _account, uint256 _amount) external;

    function burn(address _account, uint256 _amount) external;

    function addVault(address _vault) external;

    function removeVault(address _vault) external;
    // Other standard ERC20 functions
}
