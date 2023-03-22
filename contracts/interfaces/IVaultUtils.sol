pragma solidity ^0.8.2;

interface IVaultUtils {
    function getBuyUsdgFeeBasisPoints(address _token, uint256 _usdpAmount) external view returns (uint256);
    function getSellUsdgFeeBasisPoints(address _token, uint256 _usdpAmount) external view returns (uint256);
}
