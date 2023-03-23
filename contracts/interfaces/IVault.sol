pragma solidity ^0.8.2;

interface IVault {
  /* Variables Getter */
  function priceFeed() external view returns (address);
  function vaultUtils() external view returns (address);
  function hasDynamicFees() external view returns (bool);



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



  function liquidationFeeUsd() external view returns (uint256);
  function taxBasisPoints() external view returns (uint256);
  function stableTaxBasisPoints() external view returns (uint256);
  function mintBurnFeeBasisPoints() external view returns (uint256);
  function swapFeeBasisPoints() external view returns (uint256);
  function stableSwapFeeBasisPoints() external view returns (uint256);
  function marginFeeBasisPoints() external view returns (uint256);
  
  function isStableToken(address _token) external view returns (bool);

  // pool info
  function usdpAmount(address _token) external view returns (uint256);

  function getTargetUsdpAmount(address _token) external view returns (uint256);
  function getFeeBasisPoints(address _token, uint256 _usdpDelta, uint256 _feeBasisPoints, uint256 _taxBasisPoints, bool _increment) external view returns (uint256);
 
}


