pragma solidity ^0.8.9;

contract VaultPriceFeedMock {
    uint256 public tokenPriceMock = 1000;

    function getPrice(
        address _token,
        bool _maximise
    ) external view returns (uint256) {
        return tokenPriceMock;
    }

    function getPrimaryPrice(
        address _token,
        bool _maximise
    ) external view returns (uint256) {
        return tokenPriceMock;
    }
}
