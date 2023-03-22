pragma solidity ^0.8.2;

import "../interfaces/IVaultUtils.sol";

contract VaultUtils is IVaultUtils {
    function getBuyUsdgFeeBasisPoints(
        address _token,
        uint256 _usdpAmount
    ) external view override returns (uint256) {}

    function getSellUsdgFeeBasisPoints(
        address _token,
        uint256 _usdpAmount
    ) external view override returns (uint256) {}
}
