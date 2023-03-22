pragma solidity ^0.8.2;

interface IUSDP {
  function mint(address _account, uint256 _amount) external;
  function burn(address _account, uint256 _amount) external;
  // Other standard ERC20 functions
}
