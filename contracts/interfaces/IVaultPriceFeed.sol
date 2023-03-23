pragma solidity ^0.8.2;

interface IVaultPriceFeed {
    function getPrice(address _token, bool _maximise) external view returns (uint256);
    function getPrimaryPrice(address _token, bool _maximise) external view returns (uint256);
    function setTokenConfig(
        address _token,
        address _priceFeed,
        uint256 _priceDecimals,
        bool _isStrictStable
    ) external;
}
