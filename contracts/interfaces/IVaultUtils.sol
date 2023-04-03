pragma solidity ^0.8.2;

interface IVaultUtils {
    function getBuyUsdgFeeBasisPoints(
        address _token,
        uint256 _usdpAmount
    ) external view returns (uint256);

    function getSellUsdgFeeBasisPoints(
        address _token,
        uint256 _usdpAmount
    ) external view returns (uint256);

    function getSwapFeeBasisPoints(
        address _tokenIn,
        address _tokenOut,
        uint256 _usdgAmount
    ) external view returns (uint256);

    function getFeeBasisPoints(
        address _token,
        uint256 _usdgDelta,
        uint256 _feeBasisPoints,
        uint256 _taxBasisPoints,
        bool _increment
    ) external view returns (uint256);

    function getFundingFee(
        address _collateralToken,
        uint256 _size,
        uint256 _entryFundingRate
    ) external view returns (uint256);

    function getEntryFundingRate(
        address _collateralToken,
        address _indexToken,
        bool _isLong
    ) external view returns (uint256);

}
