pragma solidity ^0.8.2;

interface IVault {
  /* Variables Getter */
  function priceFeed() external view returns (address);
  function vaultUtils() external view returns (address);



  /* Write Functions */
  function buyUSDP(address _token, address _receiver) external returns (uint256);
  function sellUSDP(address _token, address _receiver) external returns (uint256);
  function swap(address _tokenIn, address _tokenOut, address _receiver) external returns (uint256);


  /* View Functions */
  function getBidPrice(address _token) external view returns (uint256);
  function getAskPrice(address _token) external view returns (uint256);
  function getRedemptionAmount(
        address _token,
        uint256 _usdpAmount
    ) external view returns (uint256);
}


